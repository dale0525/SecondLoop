import {
  closeSync,
  existsSync,
  fsyncSync,
  mkdirSync,
  openSync,
  readFileSync,
  renameSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import path from "node:path";
import type { SidecarRequest } from "./sidecarSupervisor";

export const MODEL_SETTINGS_LOAD_CHANNEL = "agentweave:model-settings:load";
export const MODEL_SETTINGS_SAVE_CHANNEL = "agentweave:model-settings:save";
export const MODEL_SETTINGS_CLEAR_KEY_CHANNEL = "agentweave:model-settings:clear-key";
export const MODEL_SETTINGS_TEST_CHANNEL = "agentweave:model-settings:test";
export const MODEL_SETTINGS_MESSAGE_CHANNEL = "agentweave:model-settings:message";

const endpointTypes = new Set(["responses", "chat_completions", "completion"]);

type IpcEvent = { sender: { id: number } };

type IpcMainLike = {
  handle(channel: string, handler: (event: IpcEvent, value?: unknown) => unknown): void;
  removeHandler(channel: string): void;
};

type SafeStorageLike = {
  decryptString(value: Buffer): string;
  encryptString(value: string): Buffer;
  isEncryptionAvailable(): boolean;
};

type ModelSettingsInput = {
  apiKey?: string;
  baseUrl: string;
  endpointType: string;
  modelName: string;
};

type StoredModelSettings = {
  baseUrl: string;
  encryptedApiKey?: string;
  endpointType: string;
  modelName: string;
  schemaVersion: 1;
};

export type PublicModelSettings = {
  apiKeyConfigured: boolean;
  baseUrl: string;
  endpointType: string;
  modelName: string;
  saved: boolean;
};

export type ModelSettingsControllerOptions = {
  ipcMain: IpcMainLike;
  requesterWebContents: { id: number };
  safeStorage: SafeStorageLike;
  sidecarRequest: SidecarRequest;
  storagePath: string;
};

export function registerModelSettingsController(
  options: ModelSettingsControllerOptions,
): () => void {
  const assertRequester = (event: IpcEvent) => {
    if (event.sender.id !== options.requesterWebContents.id) {
      throw new Error("Model settings are restricted to the requester window");
    }
  };

  options.ipcMain.handle(MODEL_SETTINGS_LOAD_CHANNEL, (event) => {
    assertRequester(event);
    return publicSettings(readStoredSettings(options.storagePath));
  });
  options.ipcMain.handle(MODEL_SETTINGS_SAVE_CHANNEL, (event, value) => {
    assertRequester(event);
    const input = validateSettingsInput(value);
    const existing = readStoredSettings(options.storagePath);
    const encryptedApiKey = input.apiKey
      ? encryptApiKey(input.apiKey, options.safeStorage)
      : existing?.encryptedApiKey;
    const stored: StoredModelSettings = {
      schemaVersion: 1,
      baseUrl: input.baseUrl,
      endpointType: input.endpointType,
      modelName: input.modelName,
      ...(encryptedApiKey ? { encryptedApiKey } : {}),
    };
    writeStoredSettings(options.storagePath, stored);
    return publicSettings(stored);
  });
  options.ipcMain.handle(MODEL_SETTINGS_CLEAR_KEY_CHANNEL, (event) => {
    assertRequester(event);
    const existing = readStoredSettings(options.storagePath);
    if (!existing) return publicSettings(null);
    const { encryptedApiKey: _, ...withoutKey } = existing;
    writeStoredSettings(options.storagePath, withoutKey);
    return publicSettings(withoutKey);
  });
  options.ipcMain.handle(MODEL_SETTINGS_TEST_CHANNEL, async (event) => {
    assertRequester(event);
    const settings = materializeSettings(options);
    return postJson(options.sidecarRequest, "/model/test", settings);
  });
  options.ipcMain.handle(MODEL_SETTINGS_MESSAGE_CHANNEL, async (event, value) => {
    assertRequester(event);
    const request = validateMessageRequest(value);
    const settings = materializeSettings(options);
    return postJson(
      options.sidecarRequest,
      `/sessions/${encodeURIComponent(request.sessionId)}/messages`,
      { content: request.content, modelSettings: settings },
    );
  });

  return () => {
    options.ipcMain.removeHandler(MODEL_SETTINGS_LOAD_CHANNEL);
    options.ipcMain.removeHandler(MODEL_SETTINGS_SAVE_CHANNEL);
    options.ipcMain.removeHandler(MODEL_SETTINGS_CLEAR_KEY_CHANNEL);
    options.ipcMain.removeHandler(MODEL_SETTINGS_TEST_CHANNEL);
    options.ipcMain.removeHandler(MODEL_SETTINGS_MESSAGE_CHANNEL);
  };
}

function validateSettingsInput(value: unknown): ModelSettingsInput {
  if (!value || typeof value !== "object") throw new Error("Model settings are required");
  const input = value as Record<string, unknown>;
  const baseUrl = boundedString(input.baseUrl, "Base URL", 2048);
  let parsed: URL;
  try {
    parsed = new URL(baseUrl);
  } catch {
    throw new Error("Base URL is invalid");
  }
  if (!new Set(["http:", "https:"]).has(parsed.protocol)) {
    throw new Error("Base URL must use HTTP or HTTPS");
  }
  const endpointType = boundedString(input.endpointType, "Endpoint type", 64);
  if (!endpointTypes.has(endpointType)) throw new Error("Endpoint type is unsupported");
  const modelName = boundedString(input.modelName, "Model name", 256);
  const apiKey = input.apiKey === undefined ? undefined : boundedString(input.apiKey, "API key", 8192);
  return { apiKey, baseUrl, endpointType, modelName };
}

function validateMessageRequest(value: unknown): { content: string; sessionId: string } {
  if (!value || typeof value !== "object") throw new Error("Message request is required");
  const request = value as Record<string, unknown>;
  const sessionId = boundedString(request.sessionId, "Session identifier", 256);
  if (!/^[A-Za-z0-9._-]+$/.test(sessionId) || sessionId === "." || sessionId === "..") {
    throw new Error("Session identifier is invalid");
  }
  return {
    content: boundedString(request.content, "Message", 1_000_000),
    sessionId,
  };
}

function boundedString(value: unknown, label: string, maximum: number): string {
  if (typeof value !== "string" || value.length === 0 || value.length > maximum) {
    throw new Error(`${label} is invalid`);
  }
  return value;
}

function encryptApiKey(apiKey: string, safeStorage: SafeStorageLike): string {
  if (!safeStorage.isEncryptionAvailable()) {
    throw new Error("Operating-system credential encryption is unavailable");
  }
  return safeStorage.encryptString(apiKey).toString("base64");
}

function materializeSettings(options: ModelSettingsControllerOptions): ModelSettingsInput {
  const stored = readStoredSettings(options.storagePath);
  if (!stored) throw new Error("Model settings have not been saved");
  const apiKey = stored.encryptedApiKey
    ? decryptApiKey(stored.encryptedApiKey, options.safeStorage)
    : "";
  return {
    apiKey,
    baseUrl: stored.baseUrl,
    endpointType: stored.endpointType,
    modelName: stored.modelName,
  };
}

function decryptApiKey(encrypted: string, safeStorage: SafeStorageLike): string {
  if (!safeStorage.isEncryptionAvailable()) {
    throw new Error("Operating-system credential encryption is unavailable");
  }
  try {
    return safeStorage.decryptString(Buffer.from(encrypted, "base64"));
  } catch {
    throw new Error("Stored model credential could not be decrypted");
  }
}

function readStoredSettings(storagePath: string): StoredModelSettings | null {
  if (!existsSync(storagePath)) return null;
  let value: unknown;
  try {
    value = JSON.parse(readFileSync(storagePath, "utf8"));
  } catch {
    throw new Error("Stored model settings are unreadable");
  }
  if (!value || typeof value !== "object") throw new Error("Stored model settings are invalid");
  const record = value as Record<string, unknown>;
  if (record.schemaVersion !== 1) throw new Error("Stored model settings schema is unsupported");
  const settings = validateSettingsInput(record);
  if (record.encryptedApiKey !== undefined && typeof record.encryptedApiKey !== "string") {
    throw new Error("Stored model credential is invalid");
  }
  return {
    schemaVersion: 1,
    baseUrl: settings.baseUrl,
    endpointType: settings.endpointType,
    modelName: settings.modelName,
    ...(record.encryptedApiKey ? { encryptedApiKey: record.encryptedApiKey } : {}),
  };
}

function writeStoredSettings(storagePath: string, settings: StoredModelSettings): void {
  const directory = path.dirname(storagePath);
  mkdirSync(directory, { recursive: true, mode: 0o700 });
  const temporary = `${storagePath}.tmp-${process.pid}`;
  const data = `${JSON.stringify(settings, null, 2)}\n`;
  const descriptor = openSync(temporary, "w", 0o600);
  try {
    writeFileSync(descriptor, data, "utf8");
    fsyncSync(descriptor);
  } finally {
    closeSync(descriptor);
  }
  try {
    renameSync(temporary, storagePath);
  } finally {
    if (existsSync(temporary)) unlinkSync(temporary);
  }
}

function publicSettings(settings: StoredModelSettings | null): PublicModelSettings {
  return settings
    ? {
        apiKeyConfigured: Boolean(settings.encryptedApiKey),
        baseUrl: settings.baseUrl,
        endpointType: settings.endpointType,
        modelName: settings.modelName,
        saved: true,
      }
    : {
        apiKeyConfigured: false,
        baseUrl: "http://127.0.0.1:11434/v1",
        endpointType: "responses",
        modelName: "local-agent-model",
        saved: false,
      };
}

async function postJson(request: SidecarRequest, pathname: string, body: unknown): Promise<unknown> {
  const response = await request(pathname, {
    body: JSON.stringify(body),
    headers: { "Content-Type": "application/json" },
    method: "POST",
  });
  const payload = await response.json().catch(() => null);
  if (!response.ok) throw new Error(`AgentWeave server returned HTTP ${response.status}`);
  return payload;
}
