// @vitest-environment node

import { mkdirSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";

import {
  MODEL_SETTINGS_CLEAR_KEY_CHANNEL,
  MODEL_SETTINGS_LOAD_CHANNEL,
  MODEL_SETTINGS_MESSAGE_CHANNEL,
  MODEL_SETTINGS_SAVE_CHANNEL,
  MODEL_SETTINGS_TURN_CHANNEL,
  registerModelSettingsController,
} from "../src/main/modelSettingsController";
import { hostDiscoveryFixture } from "./hostBootstrapFixture";

const roots: string[] = [];

afterEach(() => {
  vi.unstubAllGlobals();
  roots.splice(0).forEach((root) => rmSync(root, { force: true, recursive: true }));
});

describe("desktop model credential storage", () => {
  it("persists only encrypted API keys and returns a public status", async () => {
    const fixture = createFixture();
    const save = fixture.handlers.get(MODEL_SETTINGS_SAVE_CHANNEL)!;
    const load = fixture.handlers.get(MODEL_SETTINGS_LOAD_CHANNEL)!;

    await save(fixture.requesterEvent, {
      apiKey: "desktop-secret",
      baseUrl: "https://models.example.test/v1",
      endpointType: "responses",
      modelName: "agent-model",
    });

    const stored = readFileSync(fixture.storagePath, "utf8");
    expect(stored).not.toContain("desktop-secret");
    expect(stored).toContain(Buffer.from("enc:desktop-secret").toString("base64"));
    await expect(load(fixture.requesterEvent)).resolves.toEqual({
      apiKeyConfigured: true,
      baseUrl: "https://models.example.test/v1",
      endpointType: "responses",
      modelName: "agent-model",
      saved: true,
    });
  });

  it("injects the credential only in main-process server requests", async () => {
    const fixture = createFixture();
    const sidecarRequest = vi.fn(async (_path: string, init: RequestInit = {}) =>
      new Response(JSON.stringify({ accepted: true, received: JSON.parse(String(init.body)) }), {
        headers: { "Content-Type": "application/json" },
      }),
    );
    fixture.sidecarRequest.mockImplementation(sidecarRequest);
    await fixture.handlers.get(MODEL_SETTINGS_SAVE_CHANNEL)!(fixture.requesterEvent, {
      apiKey: "desktop-secret",
      baseUrl: "https://models.example.test/v1",
      endpointType: "chat_completions",
      modelName: "agent-model",
    });

    const result = await fixture.handlers.get(MODEL_SETTINGS_MESSAGE_CHANNEL)!(
      fixture.requesterEvent,
      { sessionId: "session-1", content: "Hello" },
    );

    expect(result).toMatchObject({
      accepted: true,
      received: {
        content: "Hello",
        modelSettings: { apiKey: "desktop-secret" },
      },
    });
    expect(sidecarRequest.mock.calls[0][0]).toBe("/sessions/session-1/messages");

    const turn = await fixture.handlers.get(MODEL_SETTINGS_TURN_CHANNEL)!(
      fixture.requesterEvent,
      { sessionId: "session-1", requestId: "request-1", content: "Stream" },
    );
    expect(turn).toMatchObject({
      received: {
        content: "Stream",
        modelSettings: { apiKey: "desktop-secret" },
        requestId: "request-1",
      },
    });
    expect(sidecarRequest.mock.calls[1][0]).toBe("/sessions/session-1/turns");
  });

  it("clears a credential, rejects other renderers, and fails closed without encryption", async () => {
    const fixture = createFixture();
    const save = fixture.handlers.get(MODEL_SETTINGS_SAVE_CHANNEL)!;
    await expect(save({ sender: { id: 99 } }, validSettings("secret"))).rejects.toThrow(
      /requester window/,
    );
    await save(fixture.requesterEvent, validSettings("secret"));
    await expect(
      fixture.handlers.get(MODEL_SETTINGS_CLEAR_KEY_CHANNEL)!(fixture.requesterEvent),
    ).resolves.toMatchObject({ apiKeyConfigured: false });

    const unavailable = createFixture(false);
    await expect(
      unavailable.handlers.get(MODEL_SETTINGS_SAVE_CHANNEL)!(
        unavailable.requesterEvent,
        validSettings("secret"),
      ),
    ).rejects.toThrow(/encryption is unavailable/);
  });

  it("keeps app-managed model settings outside the renderer and omits user overrides", async () => {
    const fixture = createFixture(true, true);

    await expect(
      fixture.handlers.get(MODEL_SETTINGS_LOAD_CHANNEL)!(fixture.requesterEvent),
    ).rejects.toThrow("managed by the Agent App");
    await expect(
      fixture.handlers.get(MODEL_SETTINGS_SAVE_CHANNEL)!(
        fixture.requesterEvent,
        validSettings("must-not-be-used"),
      ),
    ).rejects.toThrow("managed by the Agent App");

    const message = await fixture.handlers.get(MODEL_SETTINGS_MESSAGE_CHANNEL)!(
      fixture.requesterEvent,
      { sessionId: "session-1", content: "Hello" },
    );
    const turn = await fixture.handlers.get(MODEL_SETTINGS_TURN_CHANNEL)!(
      fixture.requesterEvent,
      { sessionId: "session-1", requestId: "request-1", content: "Stream" },
    );

    expect(message).toEqual({});
    expect(turn).toEqual({});
    expect(JSON.parse(String(fixture.sidecarRequest.mock.calls[0][1]?.body))).toEqual({
      content: "Hello",
    });
    expect(JSON.parse(String(fixture.sidecarRequest.mock.calls[1][1]?.body))).toEqual({
      content: "Stream",
      requestId: "request-1",
    });
  });
});

type Handler = (event: { sender: { id: number } }, value?: unknown) => Promise<unknown> | unknown;

function createFixture(encryptionAvailable = true, appManaged = false) {
  mkdirSync(join(process.cwd(), ".tool"), { recursive: true });
  const root = mkdtempSync(join(process.cwd(), ".tool", "desktop-model-settings-"));
  roots.push(root);
  const handlers = new Map<string, Handler>();
  const requesterEvent = { sender: { id: 7 } };
  const storagePath = join(root, "model-settings.v1.json");
  const sidecarRequest = vi.fn(async (_path: string, _init?: RequestInit) => new Response("{}"));
  registerModelSettingsController({
    ipcMain: {
      handle: (channel, handler) => handlers.set(channel, handler),
      removeHandler: (channel) => handlers.delete(channel),
    },
    requesterWebContents: requesterEvent.sender,
    ...(appManaged
      ? {
          loadHostDiscovery: async () => hostDiscoveryFixture({
            access: {
              modelAccess: {
                configurationPolicy: "app_managed",
                profile: {
                  authentication: "user_identity",
                  baseUrl: "https://gateway.example.test/v1",
                  endpointType: "responses",
                  headers: {},
                  modelName: "agent-model",
                  providerId: "example.gateway",
                },
              },
              identity: {
                mode: "required",
                provider: {
                  id: "agentweave.identity.oidc",
                  publicConfig: { issuer: "https://identity.example.test" },
                  version: "^1.0.0",
                },
              },
              entitlements: {
                mode: "required",
                provider: {
                  id: "agentweave.entitlements.http",
                  publicConfig: { endpoint: "https://access.example.test" },
                  version: "^1.0.0",
                },
              },
            },
          }),
        }
      : {}),
    safeStorage: {
      isEncryptionAvailable: () => encryptionAvailable,
      encryptString: (value) => Buffer.from(`enc:${value}`),
      decryptString: (value) => value.toString().replace(/^enc:/, ""),
    },
    sidecarRequest,
    storagePath,
  });
  return { handlers, requesterEvent, sidecarRequest, storagePath };
}

function validSettings(apiKey: string) {
  return {
    apiKey,
    baseUrl: "https://models.example.test/v1",
    endpointType: "responses",
    modelName: "agent-model",
  };
}
