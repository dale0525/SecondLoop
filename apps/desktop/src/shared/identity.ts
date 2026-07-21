export const IDENTITY_STATUS_CHANNEL = "agentweave:identity:status";
export const IDENTITY_START_CHANNEL = "agentweave:identity:start";
export const IDENTITY_LOGOUT_CHANNEL = "agentweave:identity:logout";
export const IDENTITY_PASSWORD_CHANNEL = "agentweave:identity:password";

export type IdentityPasswordRequest = Readonly<{
  email: string;
  password: string;
}>;

export type IdentityAccount = Readonly<{
  authenticatedAt: string;
  expiresAt: string;
  id: string;
}>;

export type IdentitySessionStatus = Readonly<{
  account: IdentityAccount | null;
  state: "signed_out" | "signed_in" | "unavailable";
}>;

export type IdentityAuthorizationStart = Readonly<{
  expiresAt: string;
  state: "waiting";
}>;

export function parseIdentitySessionStatus(value: unknown): IdentitySessionStatus {
  const root = exactRecord(value, ["account", "state"]);
  if (!new Set(["signed_out", "signed_in", "unavailable"]).has(String(root.state))) {
    throw new Error("Identity status is invalid");
  }
  const state = root.state as IdentitySessionStatus["state"];
  const account = root.account === null ? null : parseAccount(root.account);
  if ((state === "signed_in") !== (account !== null)) {
    throw new Error("Identity account does not match its status");
  }
  return Object.freeze({ state, account });
}

export function parseIdentityAuthorizationStart(value: unknown): IdentityAuthorizationStart {
  const root = exactRecord(value, ["expiresAt", "state"]);
  if (root.state !== "waiting") throw new Error("Identity authorization state is invalid");
  return Object.freeze({
    state: "waiting",
    expiresAt: timestamp(root.expiresAt),
  });
}

function parseAccount(value: unknown): IdentityAccount {
  const account = exactRecord(value, ["authenticatedAt", "expiresAt", "id"]);
  const id = boundedString(account.id, 80);
  if (!/^usr_[0-9a-f]{64}$/.test(id)) throw new Error("Identity account is invalid");
  return Object.freeze({
    id,
    authenticatedAt: timestamp(account.authenticatedAt),
    expiresAt: timestamp(account.expiresAt),
  });
}

function timestamp(value: unknown): string {
  const parsed = boundedString(value, 64);
  if (!Number.isFinite(Date.parse(parsed))) throw new Error("Identity timestamp is invalid");
  return parsed;
}

function boundedString(value: unknown, maximum: number): string {
  if (typeof value !== "string" || value.length === 0 || value.length > maximum) {
    throw new Error("Identity response is invalid");
  }
  return value;
}

function exactRecord(value: unknown, keys: readonly string[]): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Identity response is invalid");
  }
  const record = value as Record<string, unknown>;
  if (Object.keys(record).some((key) => !keys.includes(key))) {
    throw new Error("Identity response is invalid");
  }
  if (keys.some((key) => !Object.hasOwn(record, key))) {
    throw new Error("Identity response is invalid");
  }
  return record;
}
