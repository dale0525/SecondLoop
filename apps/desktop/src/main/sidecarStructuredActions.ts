import type { SidecarApiOperation } from "../shared/sidecarApi";
import type { SidecarRequest } from "./sidecarSupervisor";

type StructuredActionRequestDescription = {
  body: unknown;
  method: "POST";
  pathname: string;
  structuredAction: true;
};

export function describeStructuredActionRequest(
  operation: SidecarApiOperation,
  value: unknown,
): StructuredActionRequestDescription | null {
  if (operation !== "structuredActions.accept") return null;
  const input = exactRecord(value, ["bindingId", "input", "sessionId"]);
  const sessionId = identifier(input.sessionId, "sessionId");
  const bindingId = identifier(input.bindingId, "bindingId");
  return {
    body: { input: boundedJson(input.input ?? {}, "input") },
    method: "POST",
    pathname: `/sessions/${sessionId}/structured-actions/${bindingId}/accept`,
    structuredAction: true,
  };
}

export async function handleStructuredActionResponse(options: {
  openExternal: (url: string) => Promise<unknown> | unknown;
  sidecarRequest: SidecarRequest;
  value: unknown;
}): Promise<unknown> {
  const response = exactRecord(options.value, ["hostDirective", "receipt"]);
  const receipt = boundedJson(response.receipt, "receipt");
  if (response.hostDirective === undefined || response.hostDirective === null) return receipt;
  const directive = exactRecord(response.hostDirective, [
    "authorization_id",
    "expected_origin",
    "type",
    "url",
  ]);
  if (directive.type !== "open_external") {
    throw new Error("Structured action Host directive is invalid");
  }
  const authorizationId = identifier(directive.authorization_id, "authorizationId");
  const target = secureExternalUrl(directive.url, directive.expected_origin);
  try {
    await options.openExternal(target);
  } catch {
    await cancelUnopenedOAuth(options.sidecarRequest, authorizationId);
    throw new Error("Structured OAuth authorization could not be opened");
  }
  return receipt;
}

async function cancelUnopenedOAuth(
  request: SidecarRequest,
  authorizationId: string,
): Promise<void> {
  try {
    await request(`/host/oauth/authorizations/${authorizationId}`, { method: "DELETE" });
  } catch {
    // Preserve the sanitized browser-open error; broker cleanup will expire the transaction.
  }
}

function secureExternalUrl(value: unknown, expectedOrigin: unknown): string {
  if (typeof value !== "string" || value.length > 16 * 1024) {
    throw new Error("Structured action URL is invalid");
  }
  if (typeof expectedOrigin !== "string" || expectedOrigin.length > 2_048) {
    throw new Error("Structured action origin is invalid");
  }
  let parsed: URL;
  try {
    parsed = new URL(value);
  } catch {
    throw new Error("Structured action URL is invalid");
  }
  if (
    parsed.protocol !== "https:"
    || parsed.username !== ""
    || parsed.password !== ""
    || value.includes("#")
    || parsed.origin !== expectedOrigin
  ) {
    throw new Error("Structured action URL is invalid");
  }
  return parsed.href;
}

function identifier(value: unknown, name: string): string {
  if (
    typeof value !== "string"
    || value.length === 0
    || value.length > 255
    || !/^[A-Za-z0-9._-]+$/.test(value)
    || value === "."
    || value === ".."
  ) {
    throw new Error(`${name} is invalid`);
  }
  return encodeURIComponent(value);
}

function boundedJson(value: unknown, name: string): unknown {
  let serialized: string;
  try {
    serialized = JSON.stringify(value);
  } catch {
    throw new Error(`${name} is invalid`);
  }
  if (serialized === undefined || new TextEncoder().encode(serialized).byteLength > 256 * 1024) {
    throw new Error(`${name} is invalid`);
  }
  return value;
}

function exactRecord(value: unknown, allowedKeys: readonly string[]): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Structured action payload is invalid");
  }
  const record = value as Record<string, unknown>;
  if (Object.keys(record).some((key) => !allowedKeys.includes(key))) {
    throw new Error("Structured action payload contains unknown fields");
  }
  return record;
}
