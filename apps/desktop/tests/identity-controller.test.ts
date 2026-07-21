// @vitest-environment node

import { createServer } from "node:http";
import { afterEach, describe, expect, it, vi } from "vitest";

import {
  parseDesktopRedirectUri,
  prepareIdentityCallbackListener,
} from "../src/main/identityCallbackServer";
import { registerIdentityController } from "../src/main/identityController";
import {
  IDENTITY_LOGOUT_CHANNEL,
  IDENTITY_PASSWORD_CHANNEL,
  IDENTITY_START_CHANNEL,
  IDENTITY_STATUS_CHANNEL,
} from "../src/shared/identity";
import type { AgentAppHostDiscovery } from "../src/shared/hostBootstrap";

const disposers: Array<() => void> = [];

afterEach(() => {
  for (const dispose of disposers.splice(0)) dispose();
});

describe("desktop identity controller", () => {
  it("keeps the authorization URL and callback credentials in Main", async () => {
    const port = await unusedPort();
    const redirectUri = `http://127.0.0.1:${port}/identity/callback`;
    const handlers = new Map<string, (
      event: { sender: { id: number } },
      value?: unknown,
    ) => unknown>();
    const callbacks: unknown[] = [];
    const openExternal = vi.fn(async () => undefined);
    const ensureCredentialVault = vi.fn(async () => undefined);
    const sidecarRequest = vi.fn(async (pathname: string, init?: RequestInit) => {
      if (pathname === "/identity/authorization") {
        return jsonResponse({
          authorizationUrl: "https://identity.example/authorize?state=secret-state",
          expiresAt: new Date(Date.now() + 60_000).toISOString(),
        });
      }
      if (pathname === "/identity/callback") {
        callbacks.push(JSON.parse(String(init?.body)) as unknown);
        return jsonResponse({ state: "signed_in", account: account() });
      }
      if (pathname === "/identity/status") {
        return jsonResponse({ state: "signed_out", account: null });
      }
      if (pathname === "/identity/logout") {
        return jsonResponse({
          status: { state: "signed_out", account: null },
          endSessionUrl: null,
          remoteRevocation: "succeeded",
        });
      }
      return new Response("not found", { status: 404 });
    });
    const dispose = registerIdentityController({
      ensureCredentialVault,
      ipcMain: {
        handle: (channel, handler) => handlers.set(channel, handler),
        removeHandler: (channel) => handlers.delete(channel),
      },
      loadHostDiscovery: async () => discovery(redirectUri),
      openExternal,
      requesterWebContents: { id: 7 },
      sidecarRequest,
    });
    disposers.push(dispose);

    const start = await handlers.get(IDENTITY_START_CHANNEL)!({ sender: { id: 7 } });

    expect(start).toMatchObject({ state: "waiting" });
    expect(JSON.stringify(start)).not.toContain("secret-state");
    expect(ensureCredentialVault).toHaveBeenCalledOnce();
    expect(openExternal).toHaveBeenCalledWith(
      "https://identity.example/authorize?state=secret-state",
    );

    const callback = `${redirectUri}?code=secret-code&state=secret-state`;
    const response = await fetch(callback, { redirect: "error" });
    expect(response.status).toBe(200);
    expect(callbacks).toEqual([{ callbackUrl: callback }]);

    expect(await handlers.get(IDENTITY_STATUS_CHANNEL)!({ sender: { id: 7 } }))
      .toEqual({ state: "signed_out", account: null });
    expect(await handlers.get(IDENTITY_LOGOUT_CHANNEL)!({ sender: { id: 7 } }))
      .toEqual({ state: "signed_out", account: null });
  });

  it("sends Firebase email credentials only to the trusted password endpoint", async () => {
    const handlers = new Map<string, (
      event: { sender: { id: number } },
      value?: unknown,
    ) => unknown>();
    const bodies: unknown[] = [];
    const dispose = registerIdentityController({
      ensureCredentialVault: async () => undefined,
      ipcMain: {
        handle: (channel, handler) => handlers.set(channel, handler),
        removeHandler: (channel) => handlers.delete(channel),
      },
      loadHostDiscovery: async () => firebaseDiscovery(),
      openExternal: vi.fn(),
      requesterWebContents: { id: 7 },
      sidecarRequest: async (pathname, init) => {
        expect(pathname).toBe("/identity/password");
        bodies.push(JSON.parse(String(init?.body)) as unknown);
        return jsonResponse({ state: "signed_in", account: account() });
      },
    });
    disposers.push(dispose);

    const result = await handlers.get(IDENTITY_PASSWORD_CHANNEL)!(
      { sender: { id: 7 } },
      { email: "person@example.test", password: "password-sentinel" },
    );

    expect(result).toMatchObject({
      state: "signed_in",
      account: { id: `usr_${"a".repeat(64)}` },
    });
    expect(bodies).toEqual([{
      email: "person@example.test",
      password: "password-sentinel",
    }]);
    expect(JSON.stringify(result)).not.toContain("password-sentinel");
  });

  it("rejects control characters in Firebase email credentials before sidecar transport", async () => {
    const handlers = new Map<string, (
      event: { sender: { id: number } },
      value?: unknown,
    ) => unknown>();
    const sidecarRequest = vi.fn();
    const dispose = registerIdentityController({
      ensureCredentialVault: async () => undefined,
      ipcMain: {
        handle: (channel, handler) => handlers.set(channel, handler),
        removeHandler: (channel) => handlers.delete(channel),
      },
      loadHostDiscovery: async () => firebaseDiscovery(),
      openExternal: vi.fn(),
      requesterWebContents: { id: 7 },
      sidecarRequest,
    });
    disposers.push(dispose);
    const passwordHandler = handlers.get(IDENTITY_PASSWORD_CHANNEL)!;

    for (const request of [
      { email: "person\r@example.test", password: "password-sentinel" },
      { email: "person\n@example.test", password: "password-sentinel" },
      { email: "person\x7f@example.test", password: "password-sentinel" },
      { email: "person@example.test", password: "password\r-sentinel" },
      { email: "person@example.test", password: "password\n-sentinel" },
      { email: "person@example.test", password: "password\x7f-sentinel" },
    ]) {
      await expect(passwordHandler({ sender: { id: 7 } }, request))
        .rejects.toThrow(/credentials are invalid/);
    }
    expect(sidecarRequest).not.toHaveBeenCalled();
  });

  it("accepts only a fixed literal IPv4 loopback callback", () => {
    expect(parseDesktopRedirectUri("http://127.0.0.1:43122/identity/callback").port)
      .toBe("43122");
    for (const value of [
      "http://localhost:43122/identity/callback",
      "http://127.0.0.1/identity/callback",
      "https://127.0.0.1:43122/identity/callback",
      "http://127.0.0.1:43122/",
      "http://127.0.0.1:43122/identity/callback?next=x",
    ]) {
      expect(() => parseDesktopRedirectUri(value)).toThrow(/fixed 127\.0\.0\.1/);
    }
  });

  it("keeps the callback listener available after a temporary completion failure", async () => {
    const port = await unusedPort();
    const redirectUri = `http://127.0.0.1:${port}/identity/callback`;
    let attempts = 0;
    const listener = await prepareIdentityCallbackListener({
      redirectUri,
      callback: async () => {
        attempts += 1;
        if (attempts === 1) throw new Error("temporary sidecar failure");
      },
    });
    try {
      const callback = `${redirectUri}?code=secret-code&state=secret-state`;
      expect((await fetch(callback)).status).toBe(400);
      expect((await fetch(callback)).status).toBe(200);
      expect(attempts).toBe(2);
    } finally {
      await listener.close();
    }
  });

  it("rejects identity IPC from a different renderer", async () => {
    const handlers = new Map<string, (
      event: { sender: { id: number } },
      value?: unknown,
    ) => unknown>();
    const dispose = registerIdentityController({
      ipcMain: {
        handle: (channel, handler) => handlers.set(channel, handler),
        removeHandler: (channel) => handlers.delete(channel),
      },
      loadHostDiscovery: async () => discovery("http://127.0.0.1:43122/identity/callback"),
      openExternal: vi.fn(),
      requesterWebContents: { id: 7 },
      sidecarRequest: vi.fn(),
    });
    disposers.push(dispose);

    await expect(handlers.get(IDENTITY_STATUS_CHANNEL)!({ sender: { id: 8 } }))
      .rejects.toThrow(/requester window/);
  });
});

function account() {
  return {
    id: `usr_${"a".repeat(64)}`,
    authenticatedAt: new Date().toISOString(),
    expiresAt: new Date(Date.now() + 60_000).toISOString(),
  };
}

function firebaseDiscovery(): AgentAppHostDiscovery {
  const value = discovery("http://127.0.0.1:43122/identity/callback");
  return {
    ...value,
    access: {
      ...value.access,
      identity: {
        mode: "required",
        provider: {
          id: "agentweave.identity.firebase",
          version: "^0.1.0",
          publicConfig: {
            projectId: "sample-project-123",
            firebaseWebKey: "public-web-key",
            webApplicationId: "1:123:web:abc",
          },
        },
      },
    },
  };
}

function discovery(redirectUri: string): AgentAppHostDiscovery {
  return {
    schemaVersion: 2,
    manifestSha256: "a".repeat(64),
    runtimeVersion: "0.1.0",
    platform: "desktop",
    identity: {
      appId: "com.example.app",
      packageId: "com.example.app",
      version: "1.0.0",
      displayName: "Example",
      shortName: null,
      description: null,
      accentColor: null,
    },
    features: [],
    requirements: { packages: [], capabilities: [], runtimeTools: [], connectors: [] },
    policy: {
      backgroundExecution: "disabled",
      externalSideEffects: "deny",
      memoryPersistence: "local_only",
      network: "declared_only",
      skillManagement: "disabled",
    },
    access: {
      modelAccess: { configurationPolicy: "app_managed", profile: null },
      identity: {
        mode: "required",
        provider: {
          id: "agentweave.identity.oidc",
          version: "^0.1.0",
          publicConfig: {
            preset: "generic",
            issuer: "https://identity.example",
            clientId: "client",
            audience: "https://gateway.example",
            scopes: ["openid"],
            redirectUri,
          },
        },
      },
      entitlements: { mode: "required", provider: null },
    },
  };
}

function jsonResponse(value: unknown): Response {
  return new Response(JSON.stringify(value), {
    headers: { "content-type": "application/json" },
  });
}

async function unusedPort(): Promise<number> {
  const server = createServer();
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  if (!address || typeof address === "string") throw new Error("test listener is unavailable");
  await new Promise<void>((resolve) => server.close(() => resolve()));
  return address.port;
}
