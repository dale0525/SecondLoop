export const SIDECAR_STATUS_SCHEMA_VERSION = 1;
export const SIDECAR_STATUS_CHANNEL = "agentweave:sidecar:status";
export const SIDECAR_ENSURE_RUNNING_CHANNEL = "agentweave:sidecar:ensure-running";

export type SidecarMode = "managed" | "external" | "unavailable";

export type SidecarState =
  | "idle"
  | "starting"
  | "ready"
  | "stopping"
  | "stopped"
  | "failed"
  | "crashed"
  | "circuit_open"
  | "external"
  | "unavailable";

export type SidecarExit = Readonly<{
  code: number | null;
  signal: string | null;
}>;

export type SidecarStatus = Readonly<{
  attempt: number;
  canEnsureRunning: boolean;
  lastExit: SidecarExit | null;
  mode: SidecarMode;
  schemaVersion: 1;
  state: SidecarState;
}>;

export function parseSidecarStatus(value: unknown): SidecarStatus {
  const status = exactRecord(value, "Sidecar status", [
    "schemaVersion",
    "mode",
    "state",
    "attempt",
    "canEnsureRunning",
    "lastExit",
  ]);
  if (status.schemaVersion !== SIDECAR_STATUS_SCHEMA_VERSION) {
    throw new Error("Sidecar status schema is unsupported");
  }
  const mode = enumValue(status.mode, "Sidecar mode", [
    "managed",
    "external",
    "unavailable",
  ] as const);
  const state = enumValue(status.state, "Sidecar state", [
    "idle",
    "starting",
    "ready",
    "stopping",
    "stopped",
    "failed",
    "crashed",
    "circuit_open",
    "external",
    "unavailable",
  ] as const);
  if (!Number.isSafeInteger(status.attempt) || (status.attempt as number) < 0) {
    throw new Error("Sidecar attempt is invalid");
  }
  if (typeof status.canEnsureRunning !== "boolean") {
    throw new Error("Sidecar recovery state is invalid");
  }
  if (
    (mode === "external" && state !== "external")
    || (mode === "unavailable" && state !== "unavailable")
    || (mode === "managed" && new Set<SidecarState>(["external", "unavailable"]).has(state))
  ) {
    throw new Error("Sidecar mode and state are inconsistent");
  }
  const attempt = status.attempt as number;
  const lastExit = parseExit(status.lastExit);
  const expectedRecovery = mode === "managed"
    && !new Set<SidecarState>(["ready", "starting", "stopping"]).has(state);
  if (status.canEnsureRunning !== expectedRecovery) {
    throw new Error("Sidecar recovery state is inconsistent");
  }
  if (mode !== "managed" && (attempt !== 0 || lastExit !== null)) {
    throw new Error("Unmanaged sidecar status contains process state");
  }
  return Object.freeze({
    schemaVersion: SIDECAR_STATUS_SCHEMA_VERSION,
    mode,
    state,
    attempt,
    canEnsureRunning: status.canEnsureRunning,
    lastExit,
  });
}

function parseExit(value: unknown): SidecarExit | null {
  if (value === null) return null;
  const exit = exactRecord(value, "Sidecar exit", ["code", "signal"]);
  if (exit.code !== null && !Number.isSafeInteger(exit.code)) {
    throw new Error("Sidecar exit code is invalid");
  }
  if (exit.signal !== null && (typeof exit.signal !== "string" || exit.signal.length > 64)) {
    throw new Error("Sidecar exit signal is invalid");
  }
  return Object.freeze({
    code: exit.code as number | null,
    signal: exit.signal as string | null,
  });
}

function exactRecord(
  value: unknown,
  label: string,
  keys: readonly string[],
): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${label} is invalid`);
  }
  const record = value as Record<string, unknown>;
  if (Object.keys(record).some((key) => !keys.includes(key))) {
    throw new Error(`${label} contains unknown fields`);
  }
  if (keys.some((key) => !Object.hasOwn(record, key))) {
    throw new Error(`${label} is incomplete`);
  }
  return record;
}

function enumValue<const T extends readonly string[]>(
  value: unknown,
  label: string,
  allowed: T,
): T[number] {
  if (typeof value !== "string" || !allowed.includes(value)) {
    throw new Error(`${label} is unsupported`);
  }
  return value as T[number];
}
