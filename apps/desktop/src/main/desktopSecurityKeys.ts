import { randomBytes } from "node:crypto";
import {
  closeSync,
  chmodSync,
  existsSync,
  fsyncSync,
  lstatSync,
  linkSync,
  mkdirSync,
  openSync,
  readFileSync,
  readdirSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import path from "node:path";

import {
  deriveCredentialVaultKey,
  loadOrCreateDataProtectionKey,
  unwrapDataProtectionKey,
  type SafeStorageLike,
} from "./dataProtectionKey";

export type DesktopSecurityKeyPurpose = "backup" | "credential-vault";

export type DesktopSecurityKey = Readonly<{
  key: Buffer;
  wrappedKey: string;
}>;

type StoredPurposeKey = {
  encryptedKey: string;
  purpose: DesktopSecurityKeyPurpose;
  schemaVersion: 1;
};

export type DesktopSecurityKeyStore = Readonly<{
  loadBackupKey(options?: { allowCreate?: boolean }): DesktopSecurityKey;
  loadCredentialVaultKey(options?: { allowCreate?: boolean }): Buffer;
  unwrapBackupKey(wrappedKey: string): Buffer;
}>;

export function createDesktopSecurityKeyStore(options: {
  legacyKeyPath: string;
  backupKeyPath: string;
  credentialVaultKeyPath: string;
  randomKey?: () => Buffer;
  safeStorage: SafeStorageLike;
}): DesktopSecurityKeyStore {
  const load = (
    purpose: DesktopSecurityKeyPurpose,
    storagePath: string,
    allowCreate = true,
  ): DesktopSecurityKey => loadPurposeKey({
    allowCreate,
    legacyKeyPath: options.legacyKeyPath,
    purpose,
    randomKey: options.randomKey,
    safeStorage: options.safeStorage,
    storagePath,
  });
  return Object.freeze({
    loadBackupKey: ({ allowCreate = true } = {}) => (
      load("backup", options.backupKeyPath, allowCreate)
    ),
    loadCredentialVaultKey: ({ allowCreate = true } = {}) => {
      const loaded = load("credential-vault", options.credentialVaultKeyPath, allowCreate);
      return loaded.key;
    },
    unwrapBackupKey: (wrappedKey) => unwrapDataProtectionKey(wrappedKey, options.safeStorage),
  });
}

export function hasPersistedCredentialSecrets(dataRoot: string): boolean {
  const roots = [path.join(dataRoot, "credentials")];
  const tenantsRoot = path.join(dataRoot, "tenants");
  if (existsSync(tenantsRoot)) {
    assertPrivateDirectory(tenantsRoot, "Credential tenant root");
    const tenants = readdirSync(tenantsRoot, { withFileTypes: true });
    if (tenants.length > 1_024) throw new Error("Credential tenant root has too many entries");
    for (const tenant of tenants) {
      if (tenant.isSymbolicLink()) throw new Error("Credential tenant root contains a symbolic link");
      if (tenant.isDirectory()) roots.push(path.join(tenantsRoot, tenant.name, "credentials"));
    }
  }
  return roots.some(credentialRootContainsSecret);
}

export function credentialVaultRequiredAtStartup(options: {
  dataRoot: string;
  env: NodeJS.ProcessEnv;
}): boolean {
  return credentialVaultStartupPolicy(options).required;
}

export function credentialVaultStartupPolicy(options: {
  dataRoot: string;
  env: NodeJS.ProcessEnv;
}): Readonly<{ allowCreate: boolean; required: boolean }> {
  if (hasPersistedCredentialSecrets(options.dataRoot)) {
    return Object.freeze({ allowCreate: false, required: true });
  }
  const workspace = options.env.AGENTWEAVE_WORKSPACE_PROVIDER;
  const mail = options.env.AGENTWEAVE_MAIL_CONNECTOR;
  const configured = workspace === "google"
    || workspace === "microsoft"
    || mail === "imap-smtp"
    || options.env.AGENTWEAVE_DEV_API === "1"
    || appManifestRequiresIdentity(options.env.AGENTWEAVE_APP_ROOT);
  return Object.freeze({ allowCreate: configured, required: configured });
}

function appManifestRequiresIdentity(appRoot: string | undefined): boolean {
  if (!appRoot || !path.isAbsolute(appRoot)) return false;
  const manifestPath = path.join(appRoot, "agent-app.json");
  try {
    const metadata = lstatSync(manifestPath);
    if (!metadata.isFile() || metadata.isSymbolicLink() || metadata.size > 256 * 1024) return false;
    const value = JSON.parse(readFileSync(manifestPath, "utf8")) as unknown;
    if (!value || typeof value !== "object" || Array.isArray(value)) return false;
    const identity = (value as Record<string, unknown>).identity;
    return Boolean(
      identity
      && typeof identity === "object"
      && !Array.isArray(identity)
      && (identity as Record<string, unknown>).mode === "required",
    );
  } catch {
    return false;
  }
}

function loadPurposeKey(options: {
  allowCreate: boolean;
  legacyKeyPath: string;
  purpose: DesktopSecurityKeyPurpose;
  randomKey?: () => Buffer;
  safeStorage: SafeStorageLike;
  storagePath: string;
}): DesktopSecurityKey {
  if (!options.safeStorage.isEncryptionAvailable()) {
    throw new Error("Operating-system credential encryption is unavailable");
  }
  if (existsSync(options.storagePath)) {
    const stored = readPurposeKey(options.storagePath, options.purpose);
    return Object.freeze({
      key: decryptPurposeKey(stored, options.safeStorage),
      wrappedKey: stored.encryptedKey,
    });
  }
  if (existsSync(options.legacyKeyPath)) {
    return migrateLegacyKey(options);
  }
  if (!options.allowCreate) throw new Error(`${options.purpose} key is unavailable`);
  const key = (options.randomKey ?? (() => randomBytes(32)))();
  if (key.byteLength !== 32) {
    key.fill(0);
    throw new Error(`Generated ${options.purpose} key is invalid`);
  }
  try {
    return persistPurposeKey(options, key);
  } finally {
    key.fill(0);
  }
}

function migrateLegacyKey(options: {
  legacyKeyPath: string;
  purpose: DesktopSecurityKeyPurpose;
  safeStorage: SafeStorageLike;
  storagePath: string;
}): DesktopSecurityKey {
  const legacy = loadOrCreateDataProtectionKey({
    safeStorage: options.safeStorage,
    storagePath: options.legacyKeyPath,
  });
  if (!legacy) throw new Error("Legacy data protection key is unavailable");
  const key = options.purpose === "backup"
    ? Buffer.from(legacy.key)
    : deriveCredentialVaultKey(legacy.key);
  legacy.key.fill(0);
  try {
    return persistPurposeKey(options, key);
  } finally {
    key.fill(0);
  }
}

function persistPurposeKey(
  options: {
    purpose: DesktopSecurityKeyPurpose;
    safeStorage: SafeStorageLike;
    storagePath: string;
  },
  source: Buffer,
): DesktopSecurityKey {
  const key = Buffer.from(source);
  let encryptedKey: string;
  try {
    const encrypted = options.safeStorage.encryptString(key.toString("base64"));
    if (encrypted.byteLength === 0 || encrypted.byteLength > 64 * 1_024) {
      throw new Error(`Operating-system ${options.purpose} key wrapping is invalid`);
    }
    encryptedKey = encrypted.toString("base64");
    writePurposeKey(options.storagePath, {
      encryptedKey,
      purpose: options.purpose,
      schemaVersion: 1,
    });
  } catch (error) {
    key.fill(0);
    throw error;
  }
  return Object.freeze({ key, wrappedKey: encryptedKey });
}

function decryptPurposeKey(stored: StoredPurposeKey, safeStorage: SafeStorageLike): Buffer {
  let plaintext: string;
  try {
    plaintext = safeStorage.decryptString(Buffer.from(stored.encryptedKey, "base64"));
  } catch {
    throw new Error(`Stored ${stored.purpose} key could not be decrypted`);
  }
  const key = Buffer.from(plaintext, "base64");
  if (key.byteLength !== 32) throw new Error(`Stored ${stored.purpose} key is invalid`);
  return key;
}

function readPurposeKey(
  storagePath: string,
  expectedPurpose: DesktopSecurityKeyPurpose,
): StoredPurposeKey {
  const metadata = lstatSync(storagePath);
  if (!metadata.isFile() || metadata.isSymbolicLink() || metadata.size > 16 * 1_024) {
    throw new Error(`Stored ${expectedPurpose} key is not a private file`);
  }
  if (process.platform !== "win32" && (metadata.mode & 0o077) !== 0) {
    throw new Error(`Stored ${expectedPurpose} key permissions are not private`);
  }
  let value: unknown;
  try {
    value = JSON.parse(readFileSync(storagePath, "utf8"));
  } catch {
    throw new Error(`Stored ${expectedPurpose} key settings are unreadable`);
  }
  if (!isRecord(value)
    || value.schemaVersion !== 1
    || value.purpose !== expectedPurpose
    || typeof value.encryptedKey !== "string"
    || value.encryptedKey.length === 0
    || Object.keys(value).some((key) => !["encryptedKey", "purpose", "schemaVersion"].includes(key))) {
    throw new Error(`Stored ${expectedPurpose} key settings are invalid`);
  }
  return {
    encryptedKey: value.encryptedKey,
    purpose: expectedPurpose,
    schemaVersion: 1,
  };
}

function writePurposeKey(storagePath: string, stored: StoredPurposeKey): void {
  const directory = path.dirname(storagePath);
  mkdirSync(directory, { recursive: true, mode: 0o700 });
  if (process.platform !== "win32") chmodSync(directory, 0o700);
  const temporary = `${storagePath}.tmp-${process.pid}`;
  const descriptor = openSync(temporary, "wx", 0o600);
  try {
    writeFileSync(descriptor, `${JSON.stringify(stored, null, 2)}\n`, "utf8");
    fsyncSync(descriptor);
  } finally {
    closeSync(descriptor);
  }
  try {
    linkSync(temporary, storagePath);
  } finally {
    if (existsSync(temporary)) unlinkSync(temporary);
  }
  syncDirectory(directory);
}

function syncDirectory(directory: string): void {
  if (process.platform === "win32") return;
  const descriptor = openSync(directory, "r");
  try {
    fsyncSync(descriptor);
  } finally {
    closeSync(descriptor);
  }
}

function credentialRootContainsSecret(root: string): boolean {
  if (!existsSync(root)) return false;
  assertPrivateDirectory(root, "Credential root");
  const entries = readdirSync(root, { withFileTypes: true });
  if (entries.length > 4_096) throw new Error("Credential root has too many entries");
  for (const entry of entries) {
    if (!entry.name.endsWith(".secret")) continue;
    if (entry.isSymbolicLink() || !entry.isFile()) {
      throw new Error("Credential root contains an invalid secret entry");
    }
    return true;
  }
  return false;
}

function assertPrivateDirectory(candidate: string, label: string): void {
  const metadata = lstatSync(candidate);
  if (!metadata.isDirectory() || metadata.isSymbolicLink()) {
    throw new Error(`${label} is invalid`);
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
