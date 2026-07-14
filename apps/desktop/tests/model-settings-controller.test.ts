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
    expect(load(fixture.requesterEvent)).toEqual({
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
    expect(() => save({ sender: { id: 99 } }, validSettings("secret"))).toThrow(/requester window/);
    await save(fixture.requesterEvent, validSettings("secret"));
    expect(fixture.handlers.get(MODEL_SETTINGS_CLEAR_KEY_CHANNEL)!(fixture.requesterEvent)).toMatchObject({
      apiKeyConfigured: false,
    });

    const unavailable = createFixture(false);
    expect(() =>
      unavailable.handlers.get(MODEL_SETTINGS_SAVE_CHANNEL)!(
        unavailable.requesterEvent,
        validSettings("secret"),
      ),
    ).toThrow(/encryption is unavailable/);
  });
});

type Handler = (event: { sender: { id: number } }, value?: unknown) => Promise<unknown> | unknown;

function createFixture(encryptionAvailable = true) {
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
