import {
  DATA_PROTECTION_EXPORT_CHANNEL,
  DATA_PROTECTION_RESTORE_CHANNEL,
  DATA_PROTECTION_STATUS_CHANNEL,
  parseBackupRestoreReceipt,
  parseDataProtectionStatus,
  type BackupExportReceipt,
} from "../shared/dataProtection";
import type { DesktopSidecarController } from "./sidecarController";

const MAX_BACKUP_BYTES = 256 * 1024 * 1024 + 1024;
const MAX_BUNDLE_BYTES = MAX_BACKUP_BYTES + 64 * 1024;
const MAX_JSON_BYTES = 64 * 1024;
const DESKTOP_BUNDLE_MAGIC = Buffer.from("AWDBK001", "ascii");

type IpcEvent = { sender: { id: number } };

type IpcMainLike = {
  handle(channel: string, handler: (event: IpcEvent) => unknown): void;
  removeHandler(channel: string): void;
};

export function registerDataProtectionController(options: {
  chooseBackupDestination: () => Promise<string | null>;
  chooseBackupSource: () => Promise<string | null>;
  ipcMain: IpcMainLike;
  prepareBackup?: () => Promise<{ wrappedKey: string }>;
  readFile: (filePath: string) => Promise<Uint8Array>;
  requesterWebContents: { id: number };
  sidecar: Pick<DesktopSidecarController, "request" | "start" | "stop">;
  unwrapKey?: (wrappedKey: string) => Buffer;
  writeFile: (filePath: string, bytes: Uint8Array) => Promise<void>;
}): () => void {
  const assertRequester = (event: IpcEvent) => {
    if (event.sender.id !== options.requesterWebContents.id) {
      throw new Error("Data protection is restricted to the requester window");
    }
  };

  options.ipcMain.handle(DATA_PROTECTION_STATUS_CHANNEL, async (event) => {
    assertRequester(event);
    const response = await options.sidecar.request("/foundation/data-protection/status");
    return parseDataProtectionStatus(await readJsonResponse(response));
  });
  options.ipcMain.handle(DATA_PROTECTION_EXPORT_CHANNEL, async (event) => {
    assertRequester(event);
    const destination = await safeChoose(options.chooseBackupDestination, "Backup destination selection failed");
    if (!destination) return null;
    if (!options.prepareBackup) throw new Error("Portable backup key wrapping is unavailable");
    const protection = await options.prepareBackup();
    const response = await options.sidecar.request("/foundation/data-protection/backup");
    await ensureOk(response);
    const declaredBytes = boundedLength(response.headers.get("content-length"));
    const envelopeBytes = new Uint8Array(await response.arrayBuffer());
    if (envelopeBytes.byteLength === 0 || envelopeBytes.byteLength > MAX_BACKUP_BYTES) {
      throw new Error("Backup response exceeds the size limit");
    }
    if (declaredBytes !== null && declaredBytes !== envelopeBytes.byteLength) {
      throw new Error("Backup response length is inconsistent");
    }
    const createdAt = requiredHeader(response, "x-agentweave-backup-created-at");
    const envelopeSha256 = requiredHeader(response, "x-agentweave-backup-sha256");
    if (!Number.isFinite(Date.parse(createdAt)) || !/^[0-9a-f]{64}$/.test(envelopeSha256)) {
      throw new Error("Backup response metadata is invalid");
    }
    if (createHash("sha256").update(envelopeBytes).digest("hex") !== envelopeSha256) {
      throw new Error("Backup response hash is inconsistent");
    }
    const backupBytes = encodeDesktopBundle(protection.wrappedKey, envelopeBytes);
    const sha256 = createHash("sha256").update(backupBytes).digest("hex");
    try {
      await options.writeFile(destination, backupBytes);
    } catch {
      throw new Error("Encrypted backup could not be written");
    }
    return Object.freeze<BackupExportReceipt>({
      exported: true,
      bytes: backupBytes.byteLength,
      createdAt,
      sha256,
    });
  });
  options.ipcMain.handle(DATA_PROTECTION_RESTORE_CHANNEL, async (event) => {
    assertRequester(event);
    const source = await safeChoose(options.chooseBackupSource, "Backup selection failed");
    if (!source) return null;
    let bytes: Uint8Array;
    try {
      bytes = await options.readFile(source);
    } catch {
      throw new Error("Encrypted backup could not be read");
    }
    if (bytes.byteLength === 0 || bytes.byteLength > MAX_BUNDLE_BYTES) {
      throw new Error("Encrypted backup exceeds the size limit");
    }
    if (!options.prepareBackup) throw new Error("Portable backup key wrapping is unavailable");
    await options.prepareBackup();
    if (!options.unwrapKey) throw new Error("Portable backup key unwrapping is unavailable");
    const bundle = decodeDesktopBundle(bytes);
    const key = options.unwrapKey(bundle.wrappedKey);
    if (key.byteLength !== 32) throw new Error("Portable backup key is invalid");
    let response: Response;
    try {
      response = await options.sidecar.request("/foundation/data-protection/restore", {
        body: Uint8Array.from(bundle.envelope).buffer,
        headers: {
          "Content-Type": "application/vnd.agentweave.backup",
          "X-AgentWeave-Backup-Key": key.toString("hex"),
        },
        method: "POST",
      });
    } finally {
      key.fill(0);
    }
    const receipt = parseStagedRestore(await readJsonResponse(response));
    await options.sidecar.stop();
    const status = await options.sidecar.start();
    if (status.state !== "ready") throw new Error("Sidecar did not restart after restore");
    return parseBackupRestoreReceipt({
      accepted: receipt.accepted,
      backup: receipt.backup,
      restarted: true,
    });
  });

  return () => {
    options.ipcMain.removeHandler(DATA_PROTECTION_STATUS_CHANNEL);
    options.ipcMain.removeHandler(DATA_PROTECTION_EXPORT_CHANNEL);
    options.ipcMain.removeHandler(DATA_PROTECTION_RESTORE_CHANNEL);
  };
}

async function readJsonResponse(response: Response): Promise<unknown> {
  const declared = boundedLength(response.headers.get("content-length"), MAX_JSON_BYTES);
  const text = await response.text();
  if (new TextEncoder().encode(text).byteLength > MAX_JSON_BYTES) {
    throw new Error("Data protection response is too large");
  }
  if (declared !== null && declared !== new TextEncoder().encode(text).byteLength) {
    throw new Error("Data protection response length is inconsistent");
  }
  let value: unknown;
  try {
    value = text ? JSON.parse(text) : {};
  } catch {
    throw new Error("Data protection response is invalid");
  }
  if (!response.ok) {
    throw new Error(
      isRecord(value) && typeof value.error === "string"
        ? value.error.slice(0, 1_024)
        : `AgentWeave server returned HTTP ${response.status}`,
    );
  }
  return value;
}

function parseStagedRestore(value: unknown): {
  accepted: true;
  backup: Record<string, unknown>;
} {
  if (!isRecord(value)
    || value.accepted !== true
    || value.restartRequired !== true
    || !isRecord(value.backup)
    || Object.keys(value).some((key) => !["accepted", "backup", "restartRequired"].includes(key))) {
    throw new Error("Backup restore response is invalid");
  }
  return { accepted: true, backup: value.backup };
}

async function ensureOk(response: Response): Promise<void> {
  if (response.ok) return;
  await readJsonResponse(response);
}

async function safeChoose(
  choose: () => Promise<string | null>,
  message: string,
): Promise<string | null> {
  try {
    return await choose();
  } catch {
    throw new Error(message);
  }
}

function requiredHeader(response: Response, name: string): string {
  const value = response.headers.get(name);
  if (!value || value.length > 512) throw new Error("Backup response metadata is missing");
  return value;
}

function boundedLength(value: string | null, maximum = MAX_BACKUP_BYTES): number | null {
  if (value === null) return null;
  const length = Number(value);
  if (!Number.isSafeInteger(length) || length < 0 || length > maximum) {
    throw new Error("Data protection response exceeds the size limit");
  }
  return length;
}

function encodeDesktopBundle(wrappedKey: string, envelope: Uint8Array): Uint8Array {
  const wrapped = Buffer.from(wrappedKey, "utf8");
  if (wrapped.byteLength === 0 || wrapped.byteLength > 64 * 1024) {
    throw new Error("Portable backup key wrapping is invalid");
  }
  const output = Buffer.allocUnsafe(
    DESKTOP_BUNDLE_MAGIC.byteLength + 4 + wrapped.byteLength + envelope.byteLength,
  );
  DESKTOP_BUNDLE_MAGIC.copy(output, 0);
  output.writeUInt32BE(wrapped.byteLength, DESKTOP_BUNDLE_MAGIC.byteLength);
  wrapped.copy(output, DESKTOP_BUNDLE_MAGIC.byteLength + 4);
  Buffer.from(envelope).copy(output, DESKTOP_BUNDLE_MAGIC.byteLength + 4 + wrapped.byteLength);
  return output;
}

function decodeDesktopBundle(bytes: Uint8Array): {
  envelope: Uint8Array;
  wrappedKey: string;
} {
  const input = Buffer.from(bytes);
  const fixed = DESKTOP_BUNDLE_MAGIC.byteLength + 4;
  if (input.byteLength <= fixed + 1
    || !input.subarray(0, DESKTOP_BUNDLE_MAGIC.byteLength).equals(DESKTOP_BUNDLE_MAGIC)) {
    throw new Error("Encrypted backup format is invalid");
  }
  const wrappedLength = input.readUInt32BE(DESKTOP_BUNDLE_MAGIC.byteLength);
  const envelopeStart = fixed + wrappedLength;
  if (wrappedLength === 0 || wrappedLength > 64 * 1024 || envelopeStart >= input.byteLength) {
    throw new Error("Encrypted backup format is invalid");
  }
  const wrappedKey = input.subarray(fixed, envelopeStart).toString("utf8");
  return {
    envelope: new Uint8Array(input.subarray(envelopeStart)),
    wrappedKey,
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
import { createHash } from "node:crypto";
