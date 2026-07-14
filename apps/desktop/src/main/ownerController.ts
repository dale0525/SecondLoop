import {
  OWNER_REQUEST_CHANNEL,
  normalizeOwnerRequest,
  type OwnerIpcRequest,
  type OwnerOperation,
} from "../shared/ownerRequest";
import type { SidecarRequest } from "./sidecarSupervisor";

type IpcEvent = { sender: { id: number } };
type IpcMainLike = {
  handle(channel: string, handler: (event: IpcEvent, value: unknown) => unknown): void;
  removeHandler(channel: string): void;
};

type OwnerDescription = {
  body?: unknown;
  method: "DELETE" | "GET" | "POST" | "PUT";
  path: string;
};

export function registerOwnerController(options: {
  ipcMain: IpcMainLike;
  requesterToken: string;
  requesterWebContents: { id: number };
  sidecarRequest: SidecarRequest;
}): () => void {
  options.ipcMain.handle(OWNER_REQUEST_CHANNEL, async (event, value) => {
    if (event.sender.id !== options.requesterWebContents.id) {
      throw new Error("Owner requests are restricted to the requester window");
    }
    if (!options.requesterToken) throw new Error("Owner skill management is disabled");
    const description = describeOwnerRequest(parseOwnerRequest(value));
    const response = await options.sidecarRequest(description.path, {
      body: description.body === undefined ? undefined : JSON.stringify(description.body),
      headers: {
        Authorization: `Bearer ${options.requesterToken}`,
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
  return () => options.ipcMain.removeHandler(OWNER_REQUEST_CHANNEL);
}

function parseOwnerRequest(value: unknown): OwnerIpcRequest {
  if (!isRecord(value) || typeof value.operation !== "string" || !OPERATIONS.has(value.operation as OwnerOperation)) {
    throw new Error("Owner operation is not allowed");
  }
  if (Object.keys(value).some((key) => key !== "input" && key !== "operation")) {
    throw new Error("Owner request is invalid");
  }
  return {
    operation: value.operation as OwnerOperation,
    ...(Object.hasOwn(value, "input") ? { input: value.input } : {}),
  };
}

function describeOwnerRequest(request: OwnerIpcRequest): OwnerDescription {
  let description: OwnerDescription;
  switch (request.operation) {
    case "principal":
      description = { method: "GET", path: "/owner/principal" };
      break;
    case "listSkills":
      description = { method: "GET", path: "/owner/skills" };
      break;
    case "skillDetail":
      description = { method: "GET", path: `/owner/skills/${packageId(request.input)}/detail` };
      break;
    case "createDraft":
      description = { body: field(request.input, "draft"), method: "POST", path: "/owner/skills/drafts" };
      break;
    case "updateDraft":
      description = {
        body: { files: field(request.input, "files") },
        method: "PUT",
        path: `/owner/skills/drafts/${uuid(request.input, "revisionId")}`,
      };
      break;
    case "validateDraft":
    case "requestActivation":
      description = {
        body: {},
        method: "POST",
        path: `/owner/skills/drafts/${uuid(request.input, "revisionId")}/${request.operation === "validateDraft" ? "validate" : "activation"}`,
      };
      break;
    case "rollback":
      description = {
        body: { revision_id: uuid(request.input, "revisionId") },
        method: "POST",
        path: `/owner/skills/${packageId(request.input)}/rollback`,
      };
      break;
    case "disable":
      description = { body: {}, method: "POST", path: `/owner/skills/${packageId(request.input)}/disable` };
      break;
    case "requestRemoval":
      description = { method: "DELETE", path: `/owner/skills/${packageId(request.input)}` };
      break;
  }
  description.path = normalizeOwnerRequest(description.path, description.method);
  return description;
}

function packageId(value: unknown): string {
  const result = field(value, "packageId");
  if (
    typeof result !== "string"
    || !/^[A-Za-z0-9._-]+$/.test(result)
    || result === "."
    || result === ".."
  ) {
    throw new Error("Owner package id is not allowed");
  }
  return result;
}

function uuid(value: unknown, name: string): string {
  const result = field(value, name);
  if (typeof result !== "string" || !/^[0-9a-f-]+$/.test(result)) {
    throw new Error("Owner identifier is not allowed");
  }
  return result;
}

function field(value: unknown, name: string): unknown {
  if (!isRecord(value) || !Object.hasOwn(value, name)) throw new Error("Owner request is invalid");
  return value[name];
}

function parsePayload(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return { error: text.slice(0, 1_024) };
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

const OPERATIONS = new Set<OwnerOperation>([
  "createDraft",
  "disable",
  "listSkills",
  "principal",
  "requestActivation",
  "requestRemoval",
  "rollback",
  "skillDetail",
  "updateDraft",
  "validateDraft",
]);
