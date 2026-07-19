import type { AgentAppHostDiscovery } from "../shared/hostBootstrap";
import {
  IDENTITY_LOGOUT_CHANNEL,
  IDENTITY_START_CHANNEL,
  IDENTITY_STATUS_CHANNEL,
  parseIdentityAuthorizationStart,
  parseIdentitySessionStatus,
  type IdentityAuthorizationStart,
  type IdentitySessionStatus,
} from "../shared/identity";
import {
  parseDesktopRedirectUri,
  prepareIdentityCallbackListener,
  type IdentityCallbackListener,
} from "./identityCallbackServer";
import type { SidecarRequest } from "./sidecarSupervisor";

const MAX_RESPONSE_BYTES = 128 * 1024;

type IpcEvent = { sender: { id: number } };

type IpcMainLike = {
  handle(channel: string, handler: (event: IpcEvent) => unknown): void;
  removeHandler(channel: string): void;
};

export function registerIdentityController(options: {
  ensureCredentialVault?: () => Promise<void>;
  ipcMain: IpcMainLike;
  loadHostDiscovery: () => Promise<AgentAppHostDiscovery>;
  openExternal: (url: string) => Promise<unknown> | unknown;
  requesterWebContents: { id: number };
  sidecarRequest: SidecarRequest;
}): () => void {
  let listener: IdentityCallbackListener | null = null;
  const assertRequester = (event: IpcEvent) => {
    if (event.sender.id !== options.requesterWebContents.id) {
      throw new Error("Identity control is restricted to the requester window");
    }
  };
  const closeListener = async () => {
    const active = listener;
    listener = null;
    await active?.close();
  };

  options.ipcMain.handle(IDENTITY_STATUS_CHANNEL, async (event) => {
    assertRequester(event);
    return identityStatus(options.sidecarRequest);
  });
  options.ipcMain.handle(IDENTITY_START_CHANNEL, async (event) => {
    assertRequester(event);
    await options.ensureCredentialVault?.();
    const discovery = await options.loadHostDiscovery();
    const redirectUri = identityRedirectUri(discovery);
    await closeListener();
    const prepared = await prepareIdentityCallbackListener({
      redirectUri,
      callback: async (callbackUrl) => {
        await requestJson(options.sidecarRequest, "/identity/callback", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ callbackUrl }),
        });
      },
    });
    listener = prepared;
    try {
      const start = parseAuthorizationServerResponse(
        await requestJson(options.sidecarRequest, "/identity/authorization", { method: "POST" }),
      );
      prepared.setExpiresAt(start.expiresAt);
      await options.openExternal(start.authorizationUrl);
      return parseIdentityAuthorizationStart({ state: "waiting", expiresAt: start.expiresAt });
    } catch {
      await closeListener();
      throw new Error("Identity authorization could not be started");
    }
  });
  options.ipcMain.handle(IDENTITY_LOGOUT_CHANNEL, async (event) => {
    assertRequester(event);
    await closeListener();
    const value = exactRecord(
      await requestJson(options.sidecarRequest, "/identity/logout", { method: "POST" }),
      ["endSessionUrl", "remoteRevocation", "status"],
    );
    const status = parseIdentitySessionStatus(value.status);
    if (value.endSessionUrl !== null) {
      const endSessionUrl = safeExternalUrl(value.endSessionUrl);
      try {
        await options.openExternal(endSessionUrl);
      } catch {
        // Local logout has already completed; remote browser logout is best effort.
      }
    }
    return status;
  });

  return () => {
    options.ipcMain.removeHandler(IDENTITY_STATUS_CHANNEL);
    options.ipcMain.removeHandler(IDENTITY_START_CHANNEL);
    options.ipcMain.removeHandler(IDENTITY_LOGOUT_CHANNEL);
    void closeListener();
  };
}

function identityRedirectUri(discovery: AgentAppHostDiscovery): string {
  const identity = discovery.access.identity;
  if (identity.mode !== "required" || identity.provider?.id !== "agentweave.identity.oidc") {
    throw new Error("OIDC identity is not configured for this App");
  }
  const redirectUri = identity.provider.publicConfig.redirectUri;
  if (typeof redirectUri !== "string") throw new Error("OIDC callback URI is unavailable");
  return parseDesktopRedirectUri(redirectUri).toString();
}

async function identityStatus(request: SidecarRequest): Promise<IdentitySessionStatus> {
  return parseIdentitySessionStatus(await requestJson(request, "/identity/status"));
}

function parseAuthorizationServerResponse(value: unknown): {
  authorizationUrl: string;
  expiresAt: string;
} {
  const root = exactRecord(value, ["authorizationUrl", "expiresAt"]);
  const expiresAt = timestamp(root.expiresAt);
  return {
    expiresAt,
    authorizationUrl: safeExternalUrl(root.authorizationUrl),
  };
}

function safeExternalUrl(value: unknown): string {
  if (typeof value !== "string" || value.length === 0 || value.length > 16 * 1024) {
    throw new Error("Identity provider URL is invalid");
  }
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw new Error("Identity provider URL is invalid");
  }
  const loopback = url.protocol === "http:" && url.hostname === "127.0.0.1";
  if ((!loopback && url.protocol !== "https:") || url.username || url.password || url.hash) {
    throw new Error("Identity provider URL is invalid");
  }
  return url.toString();
}

async function requestJson(
  request: SidecarRequest,
  pathname: string,
  init?: RequestInit,
): Promise<unknown> {
  const response = await request(pathname, init);
  const length = response.headers.get("content-length");
  if (length && Number(length) > MAX_RESPONSE_BYTES) {
    throw new Error("Identity response is too large");
  }
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes.byteLength > MAX_RESPONSE_BYTES) throw new Error("Identity response is too large");
  let value: unknown;
  try {
    value = JSON.parse(new TextDecoder().decode(bytes)) as unknown;
  } catch {
    throw new Error("Identity response is invalid");
  }
  if (!response.ok) throw new Error("Identity operation failed");
  return value;
}

function timestamp(value: unknown): string {
  if (typeof value !== "string" || value.length > 64 || !Number.isFinite(Date.parse(value))) {
    throw new Error("Identity timestamp is invalid");
  }
  return value;
}

function exactRecord(value: unknown, keys: readonly string[]): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Identity response is invalid");
  }
  const record = value as Record<string, unknown>;
  if (
    Object.keys(record).some((key) => !keys.includes(key))
    || keys.some((key) => !Object.hasOwn(record, key))
  ) {
    throw new Error("Identity response is invalid");
  }
  return record;
}
