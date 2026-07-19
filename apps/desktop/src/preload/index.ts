import { contextBridge, ipcRenderer } from "electron";
import type { ApprovalObservationResult } from "../shared/approvalObservation";
import {
  DEVELOPER_ACCESS_REQUEST_CHANNEL,
  type DeveloperAccessOperation,
} from "../shared/developerAccess";
import {
  DEVELOPER_PROJECT_LOAD_CHANNEL,
  DEVELOPER_PROJECT_PACKAGE_CHANNEL,
  DEVELOPER_PROJECT_SAVE_CHANNEL,
  DEVELOPER_PROJECT_SHOW_OUTPUT_CHANNEL,
  type DeveloperPackageReceipt,
  type DeveloperProjectSaveRequest,
  type DeveloperProjectSnapshot,
} from "../shared/developerProject";
import {
  ATTACHMENT_PICK_IMPORT_CHANNEL,
  parseAttachmentMetadata,
  type AttachmentMetadata,
} from "../shared/attachments";
import {
  DATA_PROTECTION_EXPORT_CHANNEL,
  DATA_PROTECTION_RESTORE_CHANNEL,
  DATA_PROTECTION_STATUS_CHANNEL,
  parseBackupExportReceipt,
  parseBackupRestoreReceipt,
  parseDataProtectionStatus,
  type BackupExportReceipt,
  type BackupRestoreReceipt,
  type DataProtectionStatus,
} from "../shared/dataProtection";
import {
  HOST_BOOTSTRAP_LOAD_CHANNEL,
  type AgentAppHostDiscovery,
} from "../shared/hostBootstrap";
import {
  IDENTITY_LOGOUT_CHANNEL,
  IDENTITY_START_CHANNEL,
  IDENTITY_STATUS_CHANNEL,
  parseIdentityAuthorizationStart,
  parseIdentitySessionStatus,
  type IdentityAuthorizationStart,
  type IdentitySessionStatus,
} from "../shared/identity";
import {
  parseSidecarStatus,
  SIDECAR_ENSURE_RUNNING_CHANNEL,
  SIDECAR_STATUS_CHANNEL,
  type SidecarStatus,
} from "../shared/sidecarStatus";
import {
  SIDECAR_API_REQUEST_CHANNEL,
  type SidecarApiOperation,
} from "../shared/sidecarApi";
import { createOwnerTransport } from "./ownerTransport";

type DesktopRuntimeInfo = {
  platform: string;
  shell: "agentweave-desktop";
};

export type DesktopPreloadApi = {
  attachments: {
    pickAndImport: () => Promise<AttachmentMetadata | null>;
  };
  dataProtection: {
    exportBackup: () => Promise<BackupExportReceipt | null>;
    restoreBackup: () => Promise<BackupRestoreReceipt | null>;
    status: () => Promise<DataProtectionStatus>;
  };
  developerProject: {
    load: () => Promise<DeveloperProjectSnapshot>;
    packageApp: () => Promise<DeveloperPackageReceipt>;
    save: (request: DeveloperProjectSaveRequest) => Promise<DeveloperProjectSnapshot>;
    showOutput: () => Promise<void>;
  };
  developerAccess: {
    request: (operation: DeveloperAccessOperation, input?: unknown) => Promise<unknown>;
  };
  getRuntimeInfo: () => DesktopRuntimeInfo;
  hostBootstrap: {
    load: () => Promise<AgentAppHostDiscovery>;
  };
  identity: {
    logout: () => Promise<IdentitySessionStatus>;
    start: () => Promise<IdentityAuthorizationStart>;
    status: () => Promise<IdentitySessionStatus>;
  };
  sidecar: {
    ensureRunning: () => Promise<SidecarStatus>;
    status: () => Promise<SidecarStatus>;
  };
  server: {
    request: (operation: SidecarApiOperation, input?: unknown) => Promise<unknown>;
  };
  owner: ReturnType<typeof createOwnerTransport>;
  approval: {
    open: (approvalId: string) => Promise<ApprovalObservationResult>;
  };
  modelSettings: {
    clearApiKey: () => Promise<unknown>;
    load: () => Promise<unknown>;
    postSessionMessage: (sessionId: string, content: string) => Promise<unknown>;
    startSessionTurn: (sessionId: string, requestId: string, content: string) => Promise<unknown>;
    save: (settings: unknown) => Promise<unknown>;
    testConnection: () => Promise<unknown>;
  };
};

const owner = createOwnerTransport({
  invoke: (channel, value) => ipcRenderer.invoke(channel, value) as Promise<unknown>,
});

const runtimeInfo: DesktopRuntimeInfo = {
  platform: typeof process === "undefined" ? "browser" : process.platform,
  shell: "agentweave-desktop"
};

export const desktopPreloadApi: DesktopPreloadApi = Object.freeze({
  attachments: Object.freeze({
    pickAndImport: async (): Promise<AttachmentMetadata | null> => {
      const value = await ipcRenderer.invoke(ATTACHMENT_PICK_IMPORT_CHANNEL) as unknown;
      return value === null ? null : parseAttachmentMetadata(value);
    },
  }),
  dataProtection: Object.freeze({
    exportBackup: async () => parseBackupExportReceipt(
      await ipcRenderer.invoke(DATA_PROTECTION_EXPORT_CHANNEL) as unknown,
    ),
    restoreBackup: async () => parseBackupRestoreReceipt(
      await ipcRenderer.invoke(DATA_PROTECTION_RESTORE_CHANNEL) as unknown,
    ),
    status: async () => parseDataProtectionStatus(
      await ipcRenderer.invoke(DATA_PROTECTION_STATUS_CHANNEL) as unknown,
    ),
  }),
  developerProject: Object.freeze({
    load: () => ipcRenderer.invoke(
      DEVELOPER_PROJECT_LOAD_CHANNEL,
    ) as Promise<DeveloperProjectSnapshot>,
    packageApp: () => ipcRenderer.invoke(
      DEVELOPER_PROJECT_PACKAGE_CHANNEL,
    ) as Promise<DeveloperPackageReceipt>,
    save: (request: DeveloperProjectSaveRequest) => ipcRenderer.invoke(
      DEVELOPER_PROJECT_SAVE_CHANNEL,
      request,
    ) as Promise<DeveloperProjectSnapshot>,
    showOutput: () => ipcRenderer.invoke(DEVELOPER_PROJECT_SHOW_OUTPUT_CHANNEL) as Promise<void>,
  }),
  developerAccess: Object.freeze({
    request: (operation: DeveloperAccessOperation, input?: unknown) =>
      ipcRenderer.invoke(DEVELOPER_ACCESS_REQUEST_CHANNEL, {
        operation,
        ...(input === undefined ? {} : { input }),
      }) as Promise<unknown>,
  }),
  getRuntimeInfo: () => runtimeInfo,
  hostBootstrap: Object.freeze({
    load: () =>
      ipcRenderer.invoke(HOST_BOOTSTRAP_LOAD_CHANNEL) as Promise<AgentAppHostDiscovery>
  }),
  identity: Object.freeze({
    logout: async () => parseIdentitySessionStatus(
      await ipcRenderer.invoke(IDENTITY_LOGOUT_CHANNEL) as unknown,
    ),
    start: async () => parseIdentityAuthorizationStart(
      await ipcRenderer.invoke(IDENTITY_START_CHANNEL) as unknown,
    ),
    status: async () => parseIdentitySessionStatus(
      await ipcRenderer.invoke(IDENTITY_STATUS_CHANNEL) as unknown,
    ),
  }),
  sidecar: Object.freeze({
    ensureRunning: async () => parseSidecarStatus(
      await ipcRenderer.invoke(SIDECAR_ENSURE_RUNNING_CHANNEL),
    ),
    status: async () => parseSidecarStatus(
      await ipcRenderer.invoke(SIDECAR_STATUS_CHANNEL),
    ),
  }),
  server: Object.freeze({
    request: (operation: SidecarApiOperation, input?: unknown) =>
      ipcRenderer.invoke(SIDECAR_API_REQUEST_CHANNEL, {
        operation,
        ...(input === undefined ? {} : { input }),
      }) as Promise<unknown>,
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
    startSessionTurn: (sessionId: string, requestId: string, content: string) =>
      ipcRenderer.invoke("agentweave:model-settings:turn", {
        content,
        requestId,
        sessionId,
      }) as Promise<unknown>,
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
