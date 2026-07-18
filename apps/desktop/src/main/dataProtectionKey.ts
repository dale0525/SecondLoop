import { hkdfSync, randomBytes } from "node:crypto";
import {
  closeSync,
  existsSync,
  fsyncSync,
  lstatSync,
  mkdirSync,
  openSync,
  readFileSync,
  renameSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import path from "node:path";

export type SafeStorageLike = {
  decryptString(value: Buffer): string;
  encryptString(value: string): Buffer;
  isEncryptionAvailable(): boolean;
};

type StoredDataProtectionKey = {
  encryptedKey: string;
  schemaVersion: 1;
};

export type DesktopDataProtectionKey = Readonly<{
  key: Buffer;
  wrappedKey: string;
}>;

export function loadOrCreateDataProtectionKey(options: {
  randomKey?: () => Buffer;
  safeStorage: SafeStorageLike;
  storagePath: string;
}): DesktopDataProtectionKey | null {
  if (!options.safeStorage.isEncryptionAvailable()) return null;
  if (existsSync(options.storagePath)) {
    const stored = readStoredKey(options.storagePath);
    return Object.freeze({
      key: decryptStoredKey(stored, options.safeStorage),
      wrappedKey: stored.encryptedKey,
    });
  }
  const key = (options.randomKey ?? (() => randomBytes(32)))();
  if (key.byteLength !== 32) throw new Error("Generated data protection key is invalid");
  const encryptedKey = options.safeStorage
    .encryptString(key.toString("base64"))
    .toString("base64");
  writeStoredKey(options.storagePath, { encryptedKey, schemaVersion: 1 });
  return Object.freeze({ key, wrappedKey: encryptedKey });
}

export function unwrapDataProtectionKey(
  wrappedKey: string,
  safeStorage: SafeStorageLike,
): Buffer {
  return decryptStoredKey({ encryptedKey: wrappedKey, schemaVersion: 1 }, safeStorage);
}

export function deriveCredentialVaultKey(dataProtectionKey: Buffer): Buffer {
  if (dataProtectionKey.byteLength !== 32) {
    throw new Error("Data protection key is invalid");
  }
  return Buffer.from(hkdfSync(
    "sha256",
    dataProtectionKey,
    Buffer.from("agentweave.desktop.key-derivation.v1", "utf8"),
    Buffer.from("agentweave.credential-vault.v1", "utf8"),
    32,
  ));
}

function decryptStoredKey(
  stored: StoredDataProtectionKey,
  safeStorage: SafeStorageLike,
): Buffer {
  let plaintext: string;
  try {
    plaintext = safeStorage.decryptString(Buffer.from(stored.encryptedKey, "base64"));
  } catch {
    throw new Error("Stored data protection key could not be decrypted");
  }
  const key = Buffer.from(plaintext, "base64");
  if (key.byteLength !== 32) throw new Error("Stored data protection key is invalid");
  return key;
}

function readStoredKey(storagePath: string): StoredDataProtectionKey {
  const metadata = lstatSync(storagePath);
  if (!metadata.isFile() || metadata.isSymbolicLink() || metadata.size > 16 * 1_024) {
    throw new Error("Stored data protection settings are not a private file");
  }
  let value: unknown;
  try {
    value = JSON.parse(readFileSync(storagePath, "utf8"));
  } catch {
    throw new Error("Stored data protection settings are unreadable");
  }
  if (!isRecord(value)
    || value.schemaVersion !== 1
    || typeof value.encryptedKey !== "string"
    || Object.keys(value).some((key) => !["encryptedKey", "schemaVersion"].includes(key))) {
    throw new Error("Stored data protection settings are invalid");
  }
  return { encryptedKey: value.encryptedKey, schemaVersion: 1 };
}

function writeStoredKey(storagePath: string, stored: StoredDataProtectionKey): void {
  const directory = path.dirname(storagePath);
  mkdirSync(directory, { recursive: true, mode: 0o700 });
  const temporary = `${storagePath}.tmp-${process.pid}`;
  const descriptor = openSync(temporary, "wx", 0o600);
  try {
    writeFileSync(descriptor, `${JSON.stringify(stored, null, 2)}\n`, "utf8");
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

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
