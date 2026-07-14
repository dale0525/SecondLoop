import { contextBridge, ipcRenderer } from "electron";
import type { ApprovalObservationResult } from "../shared/approvalObservation";
import {
  HOST_BOOTSTRAP_LOAD_CHANNEL,
  type AgentAppHostDiscovery,
} from "../shared/hostBootstrap";
import { createOwnerTransport } from "./ownerTransport";

type DesktopRuntimeInfo = {
  platform: string;
  shell: "agentweave-desktop";
};

export type DesktopPreloadApi = {
  getRuntimeInfo: () => DesktopRuntimeInfo;
  hostBootstrap: {
    load: () => Promise<AgentAppHostDiscovery>;
  };
  owner: ReturnType<typeof createOwnerTransport>;
  approval: {
    open: (approvalId: string) => Promise<ApprovalObservationResult>;
  };
  modelSettings: {
    clearApiKey: () => Promise<unknown>;
    load: () => Promise<unknown>;
    postSessionMessage: (sessionId: string, content: string) => Promise<unknown>;
    save: (settings: unknown) => Promise<unknown>;
    testConnection: () => Promise<unknown>;
  };
};

const ownerToken = process.env.AGENTWEAVE_OWNER_TOKEN ?? "";
const owner = createOwnerTransport({ requesterToken: ownerToken });

const runtimeInfo: DesktopRuntimeInfo = {
  platform: typeof process === "undefined" ? "browser" : process.platform,
  shell: "agentweave-desktop"
};

export const desktopPreloadApi: DesktopPreloadApi = Object.freeze({
  getRuntimeInfo: () => runtimeInfo,
  hostBootstrap: Object.freeze({
    load: () =>
      ipcRenderer.invoke(HOST_BOOTSTRAP_LOAD_CHANNEL) as Promise<AgentAppHostDiscovery>
  }),
  owner,
  approval: Object.freeze({
    open: (approvalId: string): Promise<ApprovalObservationResult> => {
      if (!/^[0-9a-f-]+$/.test(approvalId)) {
        return Promise.reject(new Error("Approval identifier is not allowed"));
      }
      return ipcRenderer.invoke("agentweave:approval:open", approvalId) as Promise<ApprovalObservationResult>;
    }
  }),
  modelSettings: Object.freeze({
    clearApiKey: () => ipcRenderer.invoke("agentweave:model-settings:clear-key") as Promise<unknown>,
    load: () => ipcRenderer.invoke("agentweave:model-settings:load") as Promise<unknown>,
    postSessionMessage: (sessionId: string, content: string) =>
      ipcRenderer.invoke("agentweave:model-settings:message", { sessionId, content }) as Promise<unknown>,
    save: (settings: unknown) =>
      ipcRenderer.invoke("agentweave:model-settings:save", settings) as Promise<unknown>,
    testConnection: () => ipcRenderer.invoke("agentweave:model-settings:test") as Promise<unknown>
  })
});

if (typeof process !== "undefined" && process.contextIsolated) {
  contextBridge.exposeInMainWorld("agentWeave", desktopPreloadApi);
}

export function getDesktopRuntimeInfo(): DesktopRuntimeInfo {
  return desktopPreloadApi.getRuntimeInfo();
}
