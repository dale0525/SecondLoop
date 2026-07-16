import type { OAuthAuthorizationView } from "./workspaceApi";

const STORAGE_KEY = "agentweave.workspace.bindings.v1";
const SAFE_ID = /^[A-Za-z0-9._-]+$/;

type StoredBinding = Readonly<{
  accountId: string;
  providerId: string;
  updatedAt: string;
}>;

type StoredBindings = Record<string, StoredBinding>;

export function loadWorkspaceAccountId(connectorId: string): string | null {
  return loadBindings()[connectorId]?.accountId ?? null;
}

export function rememberWorkspaceBindings(view: OAuthAuthorizationView): void {
  if (view.status !== "completed") return;
  const next = loadBindings();
  for (const binding of view.bindings) {
    next[binding.connectorId] = {
      accountId: binding.accountId,
      providerId: view.providerId,
      updatedAt: view.updatedAt,
    };
  }
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
  } catch {
    // The binding remains authoritative in the Host even when this convenience cache is unavailable.
  }
}

function loadBindings(): StoredBindings {
  try {
    const value = window.localStorage.getItem(STORAGE_KEY);
    if (!value) return {};
    const parsed = JSON.parse(value) as unknown;
    if (!isRecord(parsed)) return {};
    const result: StoredBindings = {};
    for (const [connectorId, candidate] of Object.entries(parsed)) {
      if (!SAFE_ID.test(connectorId) || !isStoredBinding(candidate)) continue;
      result[connectorId] = candidate;
    }
    return result;
  } catch {
    return {};
  }
}

function isStoredBinding(value: unknown): value is StoredBinding {
  if (!isRecord(value)) return false;
  return Object.keys(value).length === 3
    && typeof value.accountId === "string"
    && SAFE_ID.test(value.accountId)
    && typeof value.providerId === "string"
    && SAFE_ID.test(value.providerId)
    && typeof value.updatedAt === "string"
    && Number.isFinite(Date.parse(value.updatedAt));
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
