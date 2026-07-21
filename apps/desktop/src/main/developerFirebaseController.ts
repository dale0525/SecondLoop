import {
  prepareIdentityCallbackListener,
  type IdentityCallbackListener,
} from "./identityCallbackServer";

type RequestDescription = Readonly<{
  body?: unknown;
  method: "DELETE" | "GET" | "POST";
  pathname: string;
}>;

export async function connectDeveloperFirebase(options: {
  closeListener: () => Promise<void>;
  input: unknown;
  openExternal: (url: string) => Promise<unknown> | unknown;
  redirectUri?: string;
  requestJson: (description: RequestDescription) => Promise<unknown>;
  setListener: (listener: IdentityCallbackListener) => void;
}): Promise<unknown> {
  const client = firebaseClient(options.input);
  const redirectUri = options.redirectUri
    ?? "http://127.0.0.1:8979/agentweave/firebase/callback";
  await options.closeListener();
  const prepared = await prepareIdentityCallbackListener({
    redirectUri,
    callback: async (callbackUrl) => {
      await options.requestJson({
        body: { callbackUrl },
        method: "POST",
        pathname: "/dev/control/firebase/authorization/callback",
      });
    },
  });
  options.setListener(prepared);
  try {
    const start = exactRecord(await options.requestJson({
      body: { client, redirectUri },
      method: "POST",
      pathname: "/dev/control/firebase/authorization",
    }), ["authorizationUrl", "expiresAtUnixMs"]);
    const expiresAtUnixMs = safeInteger(start.expiresAtUnixMs);
    prepared.setExpiresAt(new Date(expiresAtUnixMs).toISOString());
    await options.openExternal(googleAuthorizationUrl(start.authorizationUrl));
    return Object.freeze({ expiresAtUnixMs, phase: "awaiting_callback" });
  } catch {
    await options.requestJson({
      method: "DELETE",
      pathname: "/dev/control/firebase/authorization/pending",
    }).catch(() => undefined);
    await options.closeListener();
    throw new Error("Firebase authorization could not be started");
  }
}

function firebaseClient(value: unknown): Record<string, unknown> {
  const root = exactRecord(value, ["client"]);
  if (!isRecord(root.client)) throw new Error("Firebase OAuth client is invalid");
  if (root.client.mode === "agent_weave_public") {
    return exactRecord(root.client, ["mode"]);
  }
  const client = exactRecord(root.client, ["mode", "clientId", "clientSecret"], true);
  if (client.mode !== "custom") throw new Error("Firebase OAuth client is invalid");
  const clientId = publicString(client.clientId, 4096);
  const clientSecret = client.clientSecret === undefined
    ? undefined
    : publicString(client.clientSecret, 4096);
  return { mode: "custom", clientId, ...(clientSecret ? { clientSecret } : {}) };
}

function googleAuthorizationUrl(value: unknown): string {
  if (typeof value !== "string" || value.length > 16 * 1024) {
    throw new Error("Google authorization URL is invalid");
  }
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw new Error("Google authorization URL is invalid");
  }
  if (
    url.protocol !== "https:"
    || url.hostname !== "accounts.google.com"
    || url.pathname !== "/o/oauth2/v2/auth"
    || url.username
    || url.password
    || url.hash
  ) throw new Error("Google authorization URL is invalid");
  return url.toString();
}

function exactRecord(
  value: unknown,
  keys: readonly string[],
  optionalKeys = false,
): Record<string, unknown> {
  if (!isRecord(value)
    || Object.keys(value).some((key) => !keys.includes(key))
    || (!optionalKeys && keys.some((key) => !Object.hasOwn(value, key)))) {
    throw new Error("Firebase OAuth payload is invalid");
  }
  return value;
}

function publicString(value: unknown, maximum: number): string {
  if (typeof value !== "string"
    || value.length === 0
    || value.length > maximum
    || /[\x00-\x1f\x7f]/.test(value)) {
    throw new Error("Firebase OAuth payload is invalid");
  }
  return value;
}

function safeInteger(value: unknown): number {
  if (!Number.isSafeInteger(value) || Number(value) <= 0) {
    throw new Error("Firebase OAuth payload is invalid");
  }
  return Number(value);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
