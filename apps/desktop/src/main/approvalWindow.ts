import type {
  ApprovalDecision,
  ApprovalObservationResult
} from "../shared/approvalObservation";
import {
  APPROVAL_REQUEST_CHANNEL,
  type ApprovalRequest,
} from "../shared/approvalRequest";
import type { SidecarRequest } from "./sidecarSupervisor";

export const APPROVAL_OPEN_CHANNEL = "agentweave:approval:open";
export const APPROVAL_COMPLETE_CHANNEL = "agentweave:approval:complete";
export const APPROVAL_CLOSE_CHANNEL = "agentweave:approval:close";

type IpcEvent = { sender: ApprovalWebContents };
type IpcHandler = (event: IpcEvent, value: unknown) => unknown;

export type ApprovalWebContents = {
  id: number;
  on(event: "will-navigate", listener: (event: { preventDefault(): void }, url: string) => void): void;
  setWindowOpenHandler(handler: () => { action: "deny" }): void;
};

export type ApprovalWindow = {
  webContents: ApprovalWebContents;
  close(): void;
  destroy(): void;
  isDestroyed(): boolean;
  loadURL(url: string): Promise<void>;
  on(event: "closed", listener: () => void): void;
};

export type ApprovalWindowOptions = {
  height: number;
  modal: true;
  resizable: boolean;
  show: boolean;
  title: string;
  width: number;
  webPreferences: {
    contextIsolation: true;
    nodeIntegration: false;
    preload: string;
    sandbox: true;
  };
};

type ApprovalWindowControllerOptions = {
  approverToken?: string;
  approvalPreload: string;
  approvalUrl: string;
  createWindow(options: ApprovalWindowOptions): ApprovalWindow;
  ipcMain: {
    handle(channel: string, handler: IpcHandler): void;
    removeHandler(channel: string): void;
  };
  requesterWebContents: ApprovalWebContents;
  sidecarRequest?: SidecarRequest;
};

type Completion = {
  approvalId: string;
  decision: ApprovalDecision;
  resolution?: unknown;
};

type PendingWindow = {
  approvalId: string;
  resolve(value: ApprovalObservationResult): void;
  webContentsId: number;
  window: ApprovalWindow;
};

export function registerApprovalWindowController(
  options: ApprovalWindowControllerOptions
): () => void {
  const byApproval = new Map<string, PendingWindow>();
  const byWebContents = new Map<number, PendingWindow>();

  options.ipcMain.handle(APPROVAL_OPEN_CHANNEL, async (event, value) => {
    if (event.sender !== options.requesterWebContents) {
      throw new Error("Approval requests must originate from the requester window");
    }
    const approvalId = approvalUuid(value);
    if (byApproval.has(approvalId)) throw new Error("Approval window is already open");
    const target = approvalTarget(options.approvalUrl, approvalId);
    const window = options.createWindow({
      height: 760,
      modal: true,
      resizable: true,
      show: true,
      title: "AgentWeave Approval",
      width: 720,
      webPreferences: {
        contextIsolation: true,
        nodeIntegration: false,
        preload: options.approvalPreload,
        sandbox: true
      }
    });
    window.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
    window.webContents.on("will-navigate", (navigation, url) => {
      if (url !== target) navigation.preventDefault();
    });
    const observed = new Promise<ApprovalObservationResult>((resolve) => {
      const webContentsId = window.webContents.id;
      const pending = { approvalId, resolve, webContentsId, window };
      byApproval.set(approvalId, pending);
      byWebContents.set(webContentsId, pending);
      window.on("closed", () => settle(pending, { approvalId, status: "closed" }));
    });
    try {
      await window.loadURL(target);
    } catch {
      const pending = byApproval.get(approvalId);
      if (pending) settle(pending, { approvalId, status: "load_failed" });
      if (!window.isDestroyed()) window.close();
    }
    return observed;
  });

  options.ipcMain.handle(APPROVAL_COMPLETE_CHANNEL, (event, value) => {
    const pending = byWebContents.get(event.sender.id);
    if (!pending || event.sender !== pending.window.webContents) {
      throw new Error("Approval completion must originate from the approval window");
    }
    const completion = parseCompletion(value);
    if (completion.approvalId !== pending.approvalId) {
      throw new Error("Approval completion identifier does not match the isolated window");
    }
    settle(pending, { ...completion, status: "completed" });
    if (!pending.window.isDestroyed()) pending.window.close();
    return { accepted: true };
  });

  options.ipcMain.handle(APPROVAL_CLOSE_CHANNEL, async (event, value) => {
    const pending = byWebContents.get(event.sender.id);
    if (!pending || event.sender !== pending.window.webContents) {
      throw new Error("Approval close must originate from the approval window");
    }
    if (approvalUuid(value) !== pending.approvalId) {
      throw new Error("Approval close identifier does not match the isolated window");
    }
    if (!pending.window.isDestroyed()) pending.window.destroy();
    return { accepted: true };
  });

  options.ipcMain.handle(APPROVAL_REQUEST_CHANNEL, async (event, value) => {
    const pending = byWebContents.get(event.sender.id);
    if (!pending || event.sender !== pending.window.webContents) {
      throw new Error("Approval request must originate from the isolated approval window");
    }
    if (!options.approverToken || !options.sidecarRequest) {
      throw new Error("Independent approver credential is not configured");
    }
    const request = parseApprovalRequest(value, pending.approvalId);
    const description = approvalDescription(request);
    const response = await options.sidecarRequest(description.path, {
      body: description.body === undefined ? undefined : JSON.stringify(description.body),
      headers: {
        Authorization: `Bearer ${options.approverToken}`,
        ...(description.body === undefined ? {} : { "Content-Type": "application/json" }),
      },
      method: description.method,
    });
    const text = await response.text();
    const payload = text ? parsePayload(text) : {};
    if (!response.ok) {
      throw new Error(
        isRecord(payload) && typeof payload.error === "string"
          ? payload.error.slice(0, 1_024)
          : `AgentWeave server returned HTTP ${response.status}`,
      );
    }
    return payload;
  });

  function settle(pending: PendingWindow, value: ApprovalObservationResult): void {
    if (byApproval.get(pending.approvalId) !== pending) return;
    byApproval.delete(pending.approvalId);
    byWebContents.delete(pending.webContentsId);
    pending.resolve(value);
  }

  return () => {
    options.ipcMain.removeHandler(APPROVAL_OPEN_CHANNEL);
    options.ipcMain.removeHandler(APPROVAL_COMPLETE_CHANNEL);
    options.ipcMain.removeHandler(APPROVAL_CLOSE_CHANNEL);
    options.ipcMain.removeHandler(APPROVAL_REQUEST_CHANNEL);
    for (const pending of byApproval.values()) {
      settle(pending, { approvalId: pending.approvalId, status: "disposed" });
      if (!pending.window.isDestroyed()) pending.window.close();
    }
  };
}

function parseApprovalRequest(value: unknown, expectedApprovalId: string): ApprovalRequest {
  if (!isRecord(value) || typeof value.operation !== "string") {
    throw new Error("Approval request is invalid");
  }
  if (value.operation === "principal") return { operation: "principal" };
  const approvalId = approvalUuid(value.approvalId);
  if (approvalId !== expectedApprovalId) throw new Error("Approval request identifier does not match");
  if (value.operation === "approval") return { approvalId, operation: "approval" };
  if (value.operation === "resolve" && (value.decision === "approve" || value.decision === "reject")) {
    return { approvalId, decision: value.decision, operation: "resolve" };
  }
  throw new Error("Approval request is invalid");
}

function approvalDescription(request: ApprovalRequest): {
  body?: unknown;
  method: "GET" | "POST";
  path: string;
} {
  if (request.operation === "principal") return { method: "GET", path: "/owner/principal" };
  const path = `/owner/skills/approvals/${request.approvalId}`;
  return request.operation === "approval"
    ? { method: "GET", path }
    : { body: { decision: request.decision }, method: "POST", path };
}

function parsePayload(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return { error: text.slice(0, 1_024) };
  }
}

function approvalTarget(base: string, approvalId: string): string {
  const url = new URL(base);
  url.searchParams.set("approvalId", approvalId);
  return url.href;
}

function approvalUuid(value: unknown): string {
  if (typeof value !== "string" || !UUID_V4.test(value)) {
    throw new Error("Approval identifier is not allowed");
  }
  return value;
}

function parseCompletion(value: unknown): Completion {
  if (!isRecord(value)) throw new Error("Approval completion is invalid");
  const approvalId = approvalUuid(value.approvalId);
  const decision = value.decision;
  if (decision !== "approve" && decision !== "reject") {
    throw new Error("Approval decision is invalid");
  }
  return {
    approvalId,
    decision,
    ...(Object.hasOwn(value, "resolution") ? { resolution: value.resolution } : {})
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

const UUID_V4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
