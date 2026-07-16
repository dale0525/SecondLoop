import type { SidecarApiOperation } from "../shared/sidecarApi";

type SessionRequestDescription = {
  body?: unknown;
  method: "DELETE" | "GET" | "PATCH" | "POST";
  pathname: string;
};

const IDENTIFIER = /^[A-Za-z0-9._-]+$/;
const TIMESTAMP = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/;

export function describeSessionRequest(
  operation: SidecarApiOperation,
  value: unknown,
): SessionRequestDescription | null {
  switch (operation) {
    case "sessions.create": {
      const input = exactRecord(value, ["title"]);
      return json("POST", "/sessions", { title: fieldString(input, "title", 256) });
    }
    case "sessions.list": {
      const input = exactRecord(value, ["cursor", "limit"]);
      const limit = optionalInteger(input, "limit", 1, 100) ?? 50;
      const cursor = optionalString(input, "cursor", 2_048);
      return get(`/sessions?${new URLSearchParams({
        limit: String(limit),
        ...(cursor ? { cursor } : {}),
      })}`);
    }
    case "sessions.load": {
      const input = exactRecord(value, ["id"]);
      return get(`/sessions/${identifier(input, "id")}`);
    }
    case "sessions.update": {
      const input = exactRecord(value, ["expectedUpdatedAt", "id", "title"]);
      return json("PATCH", `/sessions/${identifier(input, "id")}`, {
        title: fieldString(input, "title", 256),
        expectedUpdatedAt: timestamp(fieldString(input, "expectedUpdatedAt", 64)),
      });
    }
    case "sessions.delete": {
      const input = exactRecord(value, ["expectedUpdatedAt", "id"]);
      const expectedUpdatedAt = timestamp(fieldString(input, "expectedUpdatedAt", 64));
      return {
        method: "DELETE",
        pathname: `/sessions/${identifier(input, "id")}?${new URLSearchParams({ expectedUpdatedAt })}`,
      };
    }
    case "sessions.events": {
      const input = exactRecord(value, ["after", "limit", "sessionId", "waitMs"]);
      const after = optionalInteger(input, "after", -1, Number.MAX_SAFE_INTEGER) ?? -1;
      const limit = optionalInteger(input, "limit", 1, 100) ?? 100;
      const waitMs = optionalInteger(input, "waitMs", 0, 25_000) ?? 0;
      return get(`/sessions/${identifier(input, "sessionId")}/events?${new URLSearchParams({
        after: String(after),
        limit: String(limit),
        waitMs: String(waitMs),
      })}`);
    }
    case "turns.events": {
      const input = exactRecord(value, ["after", "limit", "sessionId", "turnId", "waitMs"]);
      const after = optionalInteger(input, "after", -1, Number.MAX_SAFE_INTEGER) ?? -1;
      const limit = optionalInteger(input, "limit", 1, 100) ?? 100;
      const waitMs = optionalInteger(input, "waitMs", 0, 25_000) ?? 0;
      return get(`/sessions/${identifier(input, "sessionId")}/turns/${identifier(input, "turnId")}/events?${new URLSearchParams({
        after: String(after),
        limit: String(limit),
        waitMs: String(waitMs),
      })}`);
    }
    case "turns.cancel": {
      const input = exactRecord(value, ["sessionId", "turnId"]);
      return {
        method: "POST",
        pathname: `/sessions/${identifier(input, "sessionId")}/turns/${identifier(input, "turnId")}/cancel`,
      };
    }
    default:
      return null;
  }
}

function get(pathname: string): SessionRequestDescription {
  return { method: "GET", pathname };
}

function json(
  method: "PATCH" | "POST",
  pathname: string,
  body: unknown,
): SessionRequestDescription {
  return { body, method, pathname };
}

function exactRecord(value: unknown, allowedKeys: readonly string[]): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Session API input is invalid");
  }
  const record = value as Record<string, unknown>;
  if (Object.keys(record).some((key) => !allowedKeys.includes(key))) {
    throw new Error("Session API input is invalid");
  }
  return record;
}

function fieldString(value: Record<string, unknown>, name: string, maxLength: number): string {
  const field = value[name];
  if (typeof field !== "string" || field.length === 0 || field.length > maxLength) {
    throw new Error(`${name} is invalid`);
  }
  return field;
}

function optionalString(
  value: Record<string, unknown>,
  name: string,
  maxLength: number,
): string | undefined {
  if (value[name] === undefined) return undefined;
  return fieldString(value, name, maxLength);
}

function optionalInteger(
  value: Record<string, unknown>,
  name: string,
  minimum: number,
  maximum: number,
): number | undefined {
  const field = value[name];
  if (field === undefined) return undefined;
  if (!Number.isSafeInteger(field) || (field as number) < minimum || (field as number) > maximum) {
    throw new Error(`${name} is invalid`);
  }
  return field as number;
}

function identifier(value: Record<string, unknown>, name: string): string {
  const id = fieldString(value, name, 256);
  if (!IDENTIFIER.test(id) || id === "." || id === "..") {
    throw new Error(`${name} is invalid`);
  }
  return encodeURIComponent(id);
}

function timestamp(value: string): string {
  if (!TIMESTAMP.test(value) || !Number.isFinite(Date.parse(value))) {
    throw new Error("expectedUpdatedAt is invalid");
  }
  return value;
}
