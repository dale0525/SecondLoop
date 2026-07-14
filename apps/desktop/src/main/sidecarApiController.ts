import {
  SIDECAR_API_REQUEST_CHANNEL,
  type SidecarApiOperation,
  type SidecarApiRequest,
} from "../shared/sidecarApi";
import type { SidecarRequest } from "./sidecarSupervisor";

const MAX_RESPONSE_BYTES = 8 * 1024 * 1024;
const UUID_OR_ID = /^[A-Za-z0-9._-]+$/;
const RFC3339_TIMESTAMP = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/;
const TASK_PRIORITIES = new Set(["low", "normal", "high", "urgent"]);
const TASK_STATUSES = new Set(["open", "completed", "cancelled"]);
const SCHEDULE_STATUSES = new Set(["active", "paused", "completed", "cancelled"]);
const NOTIFICATION_STATUSES = new Set([
  "pending",
  "delivering",
  "delivered",
  "failed",
  "uncertain",
  "cancelled",
]);

type IpcEvent = { sender: { id: number } };

type IpcMainLike = {
  handle(channel: string, handler: (event: IpcEvent, value: unknown) => unknown): void;
  removeHandler(channel: string): void;
};

type RequestDescription = {
  body?: unknown;
  method: "DELETE" | "GET" | "PATCH" | "POST";
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
    case "sessions.list": {
      const limit = optionalInteger(request.input, "limit", 1, 100) ?? 50;
      const cursor = optionalString(request.input, "cursor", 2_048);
      return get(`/sessions?${new URLSearchParams({
        limit: String(limit),
        ...(cursor ? { cursor } : {}),
      })}`);
    }
    case "sessions.load":
      return get(`/sessions/${identifier(request.input, "id")}`);
    case "sessions.update":
      return json("PATCH", `/sessions/${identifier(request.input, "id")}`, {
        title: fieldString(request.input, "title", 256),
        expectedUpdatedAt: fieldString(request.input, "expectedUpdatedAt", 64),
      });
    case "sessions.delete": {
      const expectedUpdatedAt = fieldString(request.input, "expectedUpdatedAt", 64);
      return {
        method: "DELETE",
        pathname: `/sessions/${identifier(request.input, "id")}?${new URLSearchParams({ expectedUpdatedAt })}`,
      };
    }
    case "turns.events": {
      const sessionId = identifier(request.input, "sessionId");
      const turnId = identifier(request.input, "turnId");
      const after = optionalInteger(request.input, "after", -1, Number.MAX_SAFE_INTEGER) ?? -1;
      const limit = optionalInteger(request.input, "limit", 1, 100) ?? 100;
      const waitMs = optionalInteger(request.input, "waitMs", 0, 25_000) ?? 0;
      return get(`/sessions/${sessionId}/turns/${turnId}/events?${new URLSearchParams({
        after: String(after),
        limit: String(limit),
        waitMs: String(waitMs),
      })}`);
    }
    case "turns.cancel":
      return {
        method: "POST",
        pathname: `/sessions/${identifier(request.input, "sessionId")}/turns/${identifier(request.input, "turnId")}/cancel`,
      };
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
    case "tasks.list": {
      const input = exactRecord(
        request.input,
        ["cursor", "dueAfter", "dueBefore", "limit", "status", "tag", "text"],
        true,
      );
      const limit = optionalInteger(input, "limit", 1, 100) ?? 50;
      const status = optionalEnum(input, "status", TASK_STATUSES);
      const dueAfter = optionalTimestamp(input, "dueAfter");
      const dueBefore = optionalTimestamp(input, "dueBefore");
      const tag = optionalString(input, "tag", 256);
      const text = optionalString(input, "text", 4_096);
      const cursor = optionalString(input, "cursor", 2_048);
      return get(`/foundation/tasks?${new URLSearchParams({
        ...(status ? { status } : {}),
        ...(dueAfter ? { dueAfter } : {}),
        ...(dueBefore ? { dueBefore } : {}),
        ...(tag ? { tag } : {}),
        ...(text ? { text } : {}),
        limit: String(limit),
        ...(cursor ? { cursor } : {}),
      })}`);
    }
    case "tasks.get": {
      const input = exactRecord(request.input, ["id"]);
      return get(`/foundation/tasks/${identifier(input, "id")}`);
    }
    case "tasks.create": {
      const input = exactRecord(request.input, ["content", "idempotencyKey"]);
      return json("POST", "/foundation/tasks", {
        content: taskContent(recordField(input, "content")),
        idempotencyKey: nonBlankString(input, "idempotencyKey", 512),
      });
    }
    case "tasks.update": {
      const input = exactRecord(request.input, ["content", "expectedVersion", "id"]);
      return json("PATCH", `/foundation/tasks/${identifier(input, "id")}`, {
        content: taskContent(recordField(input, "content")),
        expectedVersion: fieldInteger(input, "expectedVersion", 1, Number.MAX_SAFE_INTEGER),
      });
    }
    case "tasks.setStatus": {
      const input = exactRecord(request.input, ["expectedVersion", "id", "status"]);
      return json("POST", `/foundation/tasks/${identifier(input, "id")}/status`, {
        expectedVersion: fieldInteger(input, "expectedVersion", 1, Number.MAX_SAFE_INTEGER),
        status: fieldEnum(input, "status", TASK_STATUSES),
      });
    }
    case "tasks.delete": {
      const input = exactRecord(request.input, ["expectedVersion", "id"]);
      return json("DELETE", `/foundation/tasks/${identifier(input, "id")}`, {
        expectedVersion: fieldInteger(input, "expectedVersion", 1, Number.MAX_SAFE_INTEGER),
      });
    }
    case "schedules.list": {
      const input = exactRecord(request.input, ["limit"], true);
      const limit = optionalInteger(input, "limit", 1, 100) ?? 25;
      return get(`/foundation/schedules?${new URLSearchParams({ limit: String(limit) })}`);
    }
    case "schedules.get":
      return get(`/foundation/schedules/${identifier(request.input, "id")}`);
    case "schedules.create": {
      const input = exactRecord(
        request.input,
        ["idempotencyKey", "misfire", "name", "payload", "schedule"],
      );
      return json("POST", "/foundation/schedules", {
        name: nonBlankString(input, "name", 255),
        schedule: scheduleSpec(recordField(input, "schedule")),
        misfire: misfirePolicy(recordField(input, "misfire")),
        payload: boundedJson(input.payload ?? {}, "payload"),
        idempotencyKey: nonBlankString(input, "idempotencyKey", 512),
      });
    }
    case "schedules.setStatus": {
      const input = exactRecord(request.input, ["expectedVersion", "id", "status"]);
      return json("POST", `/foundation/schedules/${identifier(input, "id")}`, {
        expectedVersion: fieldInteger(input, "expectedVersion", 1, Number.MAX_SAFE_INTEGER),
        status: fieldEnum(input, "status", SCHEDULE_STATUSES),
      });
    }
    case "notifications.list": {
      const input = exactRecord(request.input, ["limit", "status"], true);
      const limit = optionalInteger(input, "limit", 1, 100) ?? 25;
      const status = optionalEnum(input, "status", NOTIFICATION_STATUSES);
      return get(`/foundation/notifications?${new URLSearchParams({
        limit: String(limit),
        ...(status ? { status } : {}),
      })}`);
    }
    case "notifications.get":
      return get(`/foundation/notifications/${identifier(request.input, "id")}`);
    case "notifications.enqueue": {
      const input = exactRecord(
        request.input,
        ["body", "channel", "data", "dedupeKey", "notBefore", "quietHours", "title"],
      );
      return json("POST", "/foundation/notifications", {
        channel: nonBlankString(input, "channel", 512),
        title: nonBlankString(input, "title", 512),
        body: fieldString(input, "body", 64 * 1_024, true),
        dedupeKey: nonBlankString(input, "dedupeKey", 512),
        notBefore: timestamp(fieldString(input, "notBefore", 64), "notBefore"),
        ...(Object.hasOwn(input, "quietHours")
          ? { quietHours: input.quietHours === null ? null : quietHours(input.quietHours) }
          : {}),
        data: boundedJson(input.data ?? {}, "data"),
      });
    }
    case "notifications.cancel":
      return json(
        "POST",
        `/foundation/notifications/${identifier(request.input, "id")}/cancel`,
        {},
      );
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

function json(
  method: "DELETE" | "PATCH" | "POST",
  pathname: string,
  body: unknown,
): RequestDescription {
  return { body, method, pathname };
}

function identifier(value: unknown, name: string): string {
  const id = fieldString(value, name, 256);
  if (!UUID_OR_ID.test(id) || id === "." || id === "..") {
    throw new Error(`${name} is invalid`);
  }
  return encodeURIComponent(id);
}

function taskContent(value: unknown): Record<string, unknown> {
  const content = exactRecord(
    value,
    ["dueAt", "notes", "priority", "recurrence", "tags", "timezone", "title"],
  );
  const title = fieldString(content, "title", 1_024);
  if (title.trim().length === 0) throw new Error("title is invalid");
  const dueAt = optionalNullableTimestamp(content, "dueAt");
  const timezone = optionalNullableString(content, "timezone", 128);
  const recurrence = optionalNullableString(content, "recurrence", 4_096);
  if (timezone === "") throw new Error("timezone is invalid");
  if (recurrence === "") throw new Error("recurrence is invalid");
  if (recurrence !== undefined && recurrence !== null && !dueAt) {
    throw new Error("recurrence requires dueAt");
  }
  return {
    title,
    ...(Object.hasOwn(content, "notes")
      ? { notes: optionalNullableString(content, "notes", 64 * 1_024) ?? null }
      : {}),
    ...(Object.hasOwn(content, "dueAt") ? { dueAt: dueAt ?? null } : {}),
    ...(Object.hasOwn(content, "timezone")
      ? { timezone: timezone ?? null }
      : {}),
    ...(Object.hasOwn(content, "recurrence") ? { recurrence: recurrence ?? null } : {}),
    priority: fieldEnum(content, "priority", TASK_PRIORITIES),
    tags: stringArray(content, "tags", 100, 256),
  };
}

function scheduleSpec(value: unknown): Record<string, unknown> {
  const record = exactRecord(
    value,
    ["anchor", "at", "every_seconds", "expression", "kind", "rule", "start", "timezone"],
  );
  const kind = fieldString(record, "kind", 32);
  switch (kind) {
    case "one_shot":
      return { kind, at: timestamp(fieldString(record, "at", 64), "at") };
    case "interval":
      return {
        kind,
        anchor: timestamp(fieldString(record, "anchor", 64), "anchor"),
        every_seconds: fieldInteger(record, "every_seconds", 1, 366 * 24 * 60 * 60),
      };
    case "cron":
      return {
        kind,
        expression: nonBlankString(record, "expression", 4_096),
        timezone: nonBlankString(record, "timezone", 128),
      };
    case "rrule":
      return {
        kind,
        rule: nonBlankString(record, "rule", 4_096),
        timezone: nonBlankString(record, "timezone", 128),
        start: timestamp(fieldString(record, "start", 64), "start"),
      };
    default:
      throw new Error("schedule kind is invalid");
  }
}

function misfirePolicy(value: unknown): Record<string, unknown> {
  const record = exactRecord(value, ["grace_seconds", "kind", "max_runs"]);
  const kind = fieldString(record, "kind", 32);
  switch (kind) {
    case "skip":
      return {
        kind,
        grace_seconds: fieldInteger(record, "grace_seconds", 0, Number.MAX_SAFE_INTEGER),
      };
    case "fire_once":
      return { kind };
    case "catch_up":
      return { kind, max_runs: fieldInteger(record, "max_runs", 1, 100) };
    default:
      throw new Error("misfire kind is invalid");
  }
}

function quietHours(value: unknown): Record<string, unknown> {
  const record = exactRecord(value, ["endMinute", "startMinute", "timezone"]);
  const startMinute = fieldInteger(record, "startMinute", 0, 1_439);
  const endMinute = fieldInteger(record, "endMinute", 0, 1_439);
  if (startMinute === endMinute) throw new Error("quietHours is invalid");
  return {
    timezone: nonBlankString(record, "timezone", 128),
    startMinute,
    endMinute,
  };
}

function boundedJson(value: unknown, name: string): unknown {
  let serialized: string;
  try {
    serialized = JSON.stringify(value);
  } catch {
    throw new Error(`${name} is invalid`);
  }
  if (serialized === undefined || new TextEncoder().encode(serialized).byteLength > 64 * 1_024) {
    throw new Error(`${name} is invalid`);
  }
  return value;
}

function fieldString(value: unknown, name: string, maximum: number, allowEmpty = false): string {
  const field = recordField(value, name);
  if (typeof field !== "string" || (!allowEmpty && field.length === 0) || field.length > maximum) {
    throw new Error(`${name} is invalid`);
  }
  return field;
}

function nonBlankString(value: unknown, name: string, maximum: number): string {
  const field = fieldString(value, name, maximum);
  if (field.trim().length === 0) throw new Error(`${name} is invalid`);
  return field;
}

function fieldInteger(value: unknown, name: string, minimum: number, maximum: number): number {
  const field = recordField(value, name);
  if (!Number.isSafeInteger(field) || (field as number) < minimum || (field as number) > maximum) {
    throw new Error(`${name} is invalid`);
  }
  return field as number;
}

function fieldEnum(value: unknown, name: string, allowed: ReadonlySet<string>): string {
  const field = fieldString(value, name, 64);
  if (!allowed.has(field)) throw new Error(`${name} is invalid`);
  return field;
}

function optionalString(value: unknown, name: string, maximum: number): string | undefined {
  if (!isRecord(value) || value[name] === undefined) return undefined;
  return fieldString(value, name, maximum);
}

function optionalInteger(
  value: unknown,
  name: string,
  minimum: number,
  maximum: number,
): number | undefined {
  if (!isRecord(value) || value[name] === undefined) return undefined;
  return fieldInteger(value, name, minimum, maximum);
}

function optionalEnum(
  value: unknown,
  name: string,
  allowed: ReadonlySet<string>,
): string | undefined {
  if (!isRecord(value) || value[name] === undefined) return undefined;
  return fieldEnum(value, name, allowed);
}

function optionalTimestamp(value: unknown, name: string): string | undefined {
  if (!isRecord(value) || value[name] === undefined) return undefined;
  return timestamp(fieldString(value, name, 64), name);
}

function optionalNullableString(
  value: unknown,
  name: string,
  maximum: number,
): string | null | undefined {
  if (!isRecord(value) || value[name] === undefined) return undefined;
  if (value[name] === null) return null;
  return fieldString(value, name, maximum, true);
}

function optionalNullableTimestamp(value: unknown, name: string): string | null | undefined {
  const field = optionalNullableString(value, name, 64);
  if (field === undefined || field === null) return field;
  return timestamp(field, name);
}

function timestamp(value: string, name: string): string {
  if (!RFC3339_TIMESTAMP.test(value) || !Number.isFinite(Date.parse(value))) {
    throw new Error(`${name} is invalid`);
  }
  return value;
}

function stringArray(
  value: unknown,
  name: string,
  maximumItems: number,
  maximumItemLength: number,
): string[] {
  const field = recordField(value, name);
  if (!Array.isArray(field) || field.length > maximumItems) {
    throw new Error(`${name} is invalid`);
  }
  return field.map((item) => {
    if (typeof item !== "string" || item.length === 0 || item.length > maximumItemLength) {
      throw new Error(`${name} is invalid`);
    }
    return item;
  });
}

function exactRecord(
  value: unknown,
  allowedKeys: readonly string[],
  allowUndefined = false,
): Record<string, unknown> {
  if (allowUndefined && value === undefined) return {};
  if (!isRecord(value) || Array.isArray(value)) throw new Error("Sidecar API input is invalid");
  if (Object.keys(value).some((key) => !allowedKeys.includes(key))) {
    throw new Error("Sidecar API input contains unknown fields");
  }
  return value;
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
  "notifications.cancel",
  "notifications.enqueue",
  "notifications.get",
  "notifications.list",
  "schedules.create",
  "schedules.get",
  "schedules.list",
  "schedules.setStatus",
  "sessions.create",
  "sessions.delete",
  "sessions.list",
  "sessions.load",
  "sessions.update",
  "tasks.create",
  "tasks.delete",
  "tasks.get",
  "tasks.list",
  "tasks.setStatus",
  "tasks.update",
  "turns.cancel",
  "turns.events",
]);
