import {
  SIDECAR_API_REQUEST_CHANNEL,
  type SidecarApiOperation,
  type SidecarApiRequest,
} from "../shared/sidecarApi";
import type { SidecarRequest } from "./sidecarSupervisor";

const MAX_RESPONSE_BYTES = 8 * 1024 * 1024;
const UUID_OR_ID = /^[A-Za-z0-9._-]+$/;

type IpcEvent = { sender: { id: number } };

type IpcMainLike = {
  handle(channel: string, handler: (event: IpcEvent, value: unknown) => unknown): void;
  removeHandler(channel: string): void;
};

type RequestDescription = {
  body?: unknown;
  method: "DELETE" | "GET" | "POST";
  pathname: string;
};

export function registerSidecarApiController(options: {
  ipcMain: IpcMainLike;
  requesterWebContents: { id: number };
  sidecarRequest: SidecarRequest;
}): () => void {
  options.ipcMain.handle(SIDECAR_API_REQUEST_CHANNEL, async (event, value) => {
    if (event.sender.id !== options.requesterWebContents.id) {
      throw new Error("Sidecar API is restricted to the requester window");
    }
    const request = describeRequest(parseRequest(value));
    return requestSidecarJson(options.sidecarRequest, request);
  });
  return () => options.ipcMain.removeHandler(SIDECAR_API_REQUEST_CHANNEL);
}

function parseRequest(value: unknown): SidecarApiRequest {
  if (!isRecord(value)) throw new Error("Sidecar API request is invalid");
  const keys = Object.keys(value);
  if (keys.some((key) => key !== "input" && key !== "operation")) {
    throw new Error("Sidecar API request is invalid");
  }
  if (typeof value.operation !== "string" || !OPERATIONS.has(value.operation as SidecarApiOperation)) {
    throw new Error("Sidecar API operation is not allowed");
  }
  return {
    operation: value.operation as SidecarApiOperation,
    ...(Object.hasOwn(value, "input") ? { input: value.input } : {}),
  };
}

function describeRequest(request: SidecarApiRequest): RequestDescription {
  switch (request.operation) {
    case "sessions.create":
      return json("POST", "/sessions", {
        title: fieldString(request.input, "title", 256),
      });
    case "memory.list": {
      const query = fieldString(request.input, "query", 4_096, true);
      const limit = fieldInteger(request.input, "limit", 1, 100);
      return get(`/foundation/memory?${new URLSearchParams({ query, limit: String(limit) })}`);
    }
    case "memory.get":
      return get(`/foundation/memory/${identifier(request.input, "id")}`);
    case "memory.forget":
      return json("DELETE", `/foundation/memory/${identifier(request.input, "id")}`, {
        expectedVersion: fieldInteger(request.input, "expectedVersion", 1, Number.MAX_SAFE_INTEGER),
      });
    case "memory.export":
      return get("/foundation/memory/export");
    case "mail.list":
      return get("/foundation/mail/accounts");
    case "mail.status":
      return get(`/foundation/mail/accounts/${identifier(request.input, "id")}`);
    case "mail.connect":
      return { method: "POST", pathname: `/foundation/mail/accounts/${identifier(request.input, "id")}` };
    case "mail.disconnect":
      return { method: "DELETE", pathname: `/foundation/mail/accounts/${identifier(request.input, "id")}` };
    case "actions.list":
      return get("/foundation/actions");
    case "actions.resolve": {
      const decision = fieldString(request.input, "decision", 32);
      if (decision !== "approve_once" && decision !== "reject") {
        throw new Error("Foundation action decision is invalid");
      }
      return json(
        "POST",
        `/foundation/actions/${identifier(request.input, "approvalId")}`,
        { decision },
      );
    }
    case "devSkills.list":
      return get("/dev/skills");
    case "devSkills.validate":
      return { method: "POST", pathname: "/dev/skills/validate" };
    case "devSkills.reload":
      return { method: "POST", pathname: "/dev/skills/reload" };
    case "devSkills.delete":
      return { method: "DELETE", pathname: `/dev/skills/${identifier(request.input, "id")}` };
  }
}

async function requestSidecarJson(
  request: SidecarRequest,
  description: RequestDescription,
): Promise<unknown> {
  const response = await request(description.pathname, {
    body: description.body === undefined ? undefined : JSON.stringify(description.body),
    headers: description.body === undefined ? undefined : { "Content-Type": "application/json" },
    method: description.method,
  });
  const declaredLength = Number(response.headers.get("content-length"));
  if (Number.isFinite(declaredLength) && declaredLength > MAX_RESPONSE_BYTES) {
    throw new Error("Sidecar response is too large");
  }
  const text = await response.text();
  if (new TextEncoder().encode(text).byteLength > MAX_RESPONSE_BYTES) {
    throw new Error("Sidecar response is too large");
  }
  const payload = text ? parseJson(text) : {};
  if (!response.ok) {
    throw new Error(
      isRecord(payload) && typeof payload.error === "string"
        ? payload.error.slice(0, 1_024)
        : `AgentWeave server returned HTTP ${response.status}`,
    );
  }
  return payload;
}

function get(pathname: string): RequestDescription {
  return { method: "GET", pathname };
}

function json(method: "DELETE" | "POST", pathname: string, body: unknown): RequestDescription {
  return { body, method, pathname };
}

function identifier(value: unknown, name: string): string {
  const id = fieldString(value, name, 256);
  if (!UUID_OR_ID.test(id) || id === "." || id === "..") {
    throw new Error(`${name} is invalid`);
  }
  return encodeURIComponent(id);
}

function fieldString(value: unknown, name: string, maximum: number, allowEmpty = false): string {
  const field = recordField(value, name);
  if (typeof field !== "string" || (!allowEmpty && field.length === 0) || field.length > maximum) {
    throw new Error(`${name} is invalid`);
  }
  return field;
}

function fieldInteger(value: unknown, name: string, minimum: number, maximum: number): number {
  const field = recordField(value, name);
  if (!Number.isSafeInteger(field) || (field as number) < minimum || (field as number) > maximum) {
    throw new Error(`${name} is invalid`);
  }
  return field as number;
}

function recordField(value: unknown, name: string): unknown {
  if (!isRecord(value) || !Object.hasOwn(value, name)) throw new Error(`${name} is required`);
  return value[name];
}

function parseJson(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    throw new Error("Sidecar response is invalid");
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

const OPERATIONS = new Set<SidecarApiOperation>([
  "actions.list",
  "actions.resolve",
  "devSkills.delete",
  "devSkills.list",
  "devSkills.reload",
  "devSkills.validate",
  "mail.connect",
  "mail.disconnect",
  "mail.list",
  "mail.status",
  "memory.export",
  "memory.forget",
  "memory.get",
  "memory.list",
  "sessions.create",
]);
