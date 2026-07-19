// @vitest-environment node

import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";

import { deriveCredentialVaultKey } from "../src/main/dataProtectionKey";
import {
  createDesktopSecurityProvisioner,
  DesktopSecurityProvisioningError,
} from "../src/main/desktopSecurityProvisioner";
import { startDesktopSidecarWithSecurity } from "../src/main/desktopStartupSecurity";
import {
  createDesktopSecurityKeyStore,
  credentialVaultRequiredAtStartup,
  credentialVaultStartupPolicy,
  hasPersistedCredentialSecrets,
} from "../src/main/desktopSecurityKeys";

const roots: string[] = [];

afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { force: true, recursive: true });
});

describe("desktop purpose key store", () => {
  it("creates independent backup and Credential Vault keys only when requested", () => {
    const root = temporaryRoot();
    const first = Buffer.alloc(32, 1);
    const second = Buffer.alloc(32, 2);
    const values = [first, second];
    const safeStorage = fakeSafeStorage();
    const store = createStore(root, safeStorage, () => Buffer.from(values.shift()!));

    expect(safeStorage.encryptString).not.toHaveBeenCalled();
    const backup = store.loadBackupKey();
    expect(backup.key).toEqual(first);
    expect(safeStorage.encryptString).toHaveBeenCalledOnce();
    const credential = store.loadCredentialVaultKey();
    expect(credential).toEqual(second);
    expect(credential).not.toEqual(backup.key);
    expect(safeStorage.encryptString).toHaveBeenCalledTimes(2);

    expect(JSON.parse(readFileSync(path.join(root, "backup-key.v1.json"), "utf8")))
      .toMatchObject({ purpose: "backup", schemaVersion: 1 });
    expect(JSON.parse(readFileSync(path.join(root, "credential-vault-key.v1.json"), "utf8")))
      .toMatchObject({ purpose: "credential-vault", schemaVersion: 1 });
  });

  it("migrates each legacy purpose lazily without changing old key semantics", () => {
    const root = temporaryRoot();
    const legacy = Buffer.alloc(32, 7);
    writeLegacyKey(root, legacy);
    const safeStorage = fakeSafeStorage();
    const store = createStore(root, safeStorage);

    const backup = store.loadBackupKey({ allowCreate: false });
    expect(backup.key).toEqual(legacy);
    expect(pathExists(root, "backup-key.v1.json")).toBe(true);
    expect(pathExists(root, "credential-vault-key.v1.json")).toBe(false);

    const credential = store.loadCredentialVaultKey({ allowCreate: false });
    expect(credential).toEqual(deriveCredentialVaultKey(legacy));
    expect(pathExists(root, "credential-vault-key.v1.json")).toBe(true);
    expect(pathExists(root, "data-protection-key.v1.json")).toBe(true);
  });

  it("fails closed instead of creating a replacement for a missing existing Vault key", () => {
    const root = temporaryRoot();
    const safeStorage = fakeSafeStorage();
    const store = createStore(root, safeStorage);

    expect(() => store.loadCredentialVaultKey({ allowCreate: false }))
      .toThrow(/credential-vault key is unavailable/);
    expect(safeStorage.encryptString).not.toHaveBeenCalled();
  });

  it("does not persist an invalid operating-system key wrapping", () => {
    const root = temporaryRoot();
    const safeStorage = fakeSafeStorage();
    safeStorage.encryptString.mockReturnValue(Buffer.alloc(0));
    const store = createStore(root, safeStorage);

    expect(() => store.loadBackupKey()).toThrow(/wrapping is invalid/);
    expect(pathExists(root, "backup-key.v1.json")).toBe(false);
  });

  it("rejects a purpose-confused key file", () => {
    const root = temporaryRoot();
    writeFileSync(
      path.join(root, "backup-key.v1.json"),
      JSON.stringify({
        encryptedKey: Buffer.from("enc:ignored").toString("base64"),
        purpose: "credential-vault",
        schemaVersion: 1,
      }),
      { mode: 0o600 },
    );
    const store = createStore(root, fakeSafeStorage());
    expect(() => store.loadBackupKey()).toThrow(/backup key settings are invalid/);
  });
});

describe("desktop Credential Vault startup policy", () => {
  it("does not touch credential storage for a clean local App", () => {
    const root = temporaryRoot();
    expect(hasPersistedCredentialSecrets(root)).toBe(false);
    expect(credentialVaultRequiredAtStartup({ dataRoot: root, env: {} })).toBe(false);
  });

  it("unlocks only for persisted secrets or an explicitly configured real provider", () => {
    const root = temporaryRoot();
    const credentialRoot = path.join(root, "tenants", "local", "credentials");
    mkdirSync(credentialRoot, { recursive: true });
    writeFileSync(path.join(credentialRoot, "account.secret"), "encrypted");
    expect(hasPersistedCredentialSecrets(root)).toBe(true);
    expect(credentialVaultRequiredAtStartup({ dataRoot: root, env: {} })).toBe(true);

    const clean = temporaryRoot();
    expect(credentialVaultRequiredAtStartup({
      dataRoot: clean,
      env: { AGENTWEAVE_WORKSPACE_PROVIDER: "google" },
    })).toBe(true);
    expect(credentialVaultRequiredAtStartup({
      dataRoot: clean,
      env: { AGENTWEAVE_MAIL_CONNECTOR: "imap-smtp" },
    })).toBe(true);
    expect(credentialVaultStartupPolicy({
      dataRoot: clean,
      env: { AGENTWEAVE_WORKSPACE_PROVIDER: "google" },
    })).toEqual({ allowCreate: true, required: true });
    expect(credentialVaultStartupPolicy({ dataRoot: root, env: {} }))
      .toEqual({ allowCreate: false, required: true });
    expect(credentialVaultStartupPolicy({
      dataRoot: clean,
      env: { AGENTWEAVE_DEV_API: "1" },
    })).toEqual({ allowCreate: true, required: true });
  });

  it("provisions the Vault before starting an App with required identity", () => {
    const dataRoot = temporaryRoot();
    const appRoot = temporaryRoot();
    writeFileSync(path.join(appRoot, "agent-app.json"), JSON.stringify({
      schemaVersion: 2,
      identity: { mode: "required", provider: { id: "agentweave.identity.oidc" } },
    }));

    expect(credentialVaultStartupPolicy({
      dataRoot,
      env: { AGENTWEAVE_APP_ROOT: appRoot },
    })).toEqual({ allowCreate: true, required: true });
  });

  it("starts a clean App without provisioning or reading a legacy key", async () => {
    const root = temporaryRoot();
    writeLegacyKey(root, Buffer.alloc(32, 7));
    const ensureCredentialVault = vi.fn();
    const start = vi.fn(async () => readyStatus());

    await startDesktopSidecarWithSecurity({
      resolution: managedResolution(path.join(root, "sidecar", "data")),
      security: { ensureCredentialVault },
      sidecar: { start },
    });

    expect(ensureCredentialVault).not.toHaveBeenCalled();
    expect(start).toHaveBeenCalledOnce();
  });

  it("unlocks an existing Vault without allowing silent replacement", async () => {
    const root = temporaryRoot();
    const credentialRoot = path.join(root, "tenants", "local", "credentials");
    mkdirSync(credentialRoot, { recursive: true });
    writeFileSync(path.join(credentialRoot, "account.secret"), "encrypted");
    const ensureCredentialVault = vi.fn(async () => undefined);
    const start = vi.fn();

    await startDesktopSidecarWithSecurity({
      resolution: managedResolution(root),
      security: { ensureCredentialVault },
      sidecar: { start },
    });

    expect(ensureCredentialVault).toHaveBeenCalledWith({ allowCreate: false });
    expect(start).not.toHaveBeenCalled();
  });

  it("reports a sidecar failure without mislabeling the Vault key as unavailable", async () => {
    const root = temporaryRoot();
    const credentialRoot = path.join(root, "credentials");
    mkdirSync(credentialRoot, { recursive: true });
    writeFileSync(path.join(credentialRoot, "account.secret"), "encrypted");
    const onCredentialVaultStartupFailure = vi.fn();
    const start = vi.fn(async () => readyStatus());

    await startDesktopSidecarWithSecurity({
      onCredentialVaultStartupFailure,
      resolution: managedResolution(root),
      security: {
        ensureCredentialVault: vi.fn(async () => {
          throw new DesktopSecurityProvisioningError("sidecar-startup-failed");
        }),
      },
      sidecar: { start },
    });

    expect(onCredentialVaultStartupFailure).toHaveBeenCalledWith("sidecar-startup-failed");
    expect(start).toHaveBeenCalledOnce();
  });
});

describe("desktop security provisioner", () => {
  it("coalesces concurrent Backup provisioning and clears temporary key material", async () => {
    const key = Buffer.alloc(32, 4);
    const observed: Buffer[] = [];
    const provisionLaunchKeys = vi.fn(async (keys: { backupKey?: Buffer }) => {
      observed.push(Buffer.from(keys.backupKey!));
      return readyStatus();
    });
    const keyStore = {
      loadBackupKey: vi.fn(() => ({ key, wrappedKey: "wrapped-backup" })),
      loadCredentialVaultKey: vi.fn(),
      unwrapBackupKey: vi.fn(),
    };
    const provisioner = createDesktopSecurityProvisioner({
      keyStore,
      sidecar: { provisionLaunchKeys },
    });

    const [first, second] = await Promise.all([
      provisioner.ensureBackup(),
      provisioner.ensureBackup(),
    ]);
    expect(first).toEqual({ wrappedKey: "wrapped-backup" });
    expect(second).toBe(first);
    expect(keyStore.loadBackupKey).toHaveBeenCalledOnce();
    expect(provisionLaunchKeys).toHaveBeenCalledOnce();
    expect(observed[0]).toEqual(Buffer.alloc(32, 4));
    expect(key).toEqual(Buffer.alloc(32));
  });

  it("preserves fail-closed existing-Vault provisioning", async () => {
    const key = Buffer.alloc(32, 8);
    const loadCredentialVaultKey = vi.fn(() => key);
    const provisioner = createDesktopSecurityProvisioner({
      keyStore: {
        loadBackupKey: vi.fn(),
        loadCredentialVaultKey,
        unwrapBackupKey: vi.fn(),
      },
      sidecar: { provisionLaunchKeys: vi.fn(async () => readyStatus()) },
    });

    await provisioner.ensureCredentialVault({ allowCreate: false });
    await provisioner.ensureCredentialVault();
    expect(loadCredentialVaultKey).toHaveBeenCalledOnce();
    expect(loadCredentialVaultKey).toHaveBeenCalledWith({ allowCreate: false });
    expect(key).toEqual(Buffer.alloc(32));
  });

  it("classifies key loading separately from sidecar startup failures", async () => {
    const missing = createDesktopSecurityProvisioner({
      keyStore: {
        loadBackupKey: vi.fn(),
        loadCredentialVaultKey: vi.fn(() => {
          throw new Error("missing");
        }),
        unwrapBackupKey: vi.fn(),
      },
      sidecar: { provisionLaunchKeys: vi.fn() },
    });
    await expect(missing.ensureCredentialVault({ allowCreate: false })).rejects.toMatchObject({
      failure: "credential-key-unavailable",
    });

    const key = Buffer.alloc(32, 9);
    const failedSidecar = createDesktopSecurityProvisioner({
      keyStore: {
        loadBackupKey: vi.fn(),
        loadCredentialVaultKey: vi.fn(() => key),
        unwrapBackupKey: vi.fn(),
      },
      sidecar: {
        provisionLaunchKeys: vi.fn(async () => {
          throw new Error("crashed");
        }),
      },
    });
    await expect(failedSidecar.ensureCredentialVault()).rejects.toMatchObject({
      failure: "sidecar-startup-failed",
    });
    expect(key).toEqual(Buffer.alloc(32));
  });
});

function createStore(
  root: string,
  safeStorage: ReturnType<typeof fakeSafeStorage>,
  randomKey?: () => Buffer,
) {
  return createDesktopSecurityKeyStore({
    backupKeyPath: path.join(root, "backup-key.v1.json"),
    credentialVaultKeyPath: path.join(root, "credential-vault-key.v1.json"),
    legacyKeyPath: path.join(root, "data-protection-key.v1.json"),
    randomKey,
    safeStorage,
  });
}

function fakeSafeStorage() {
  return {
    decryptString: vi.fn((value: Buffer) => value.toString("utf8").slice(4)),
    encryptString: vi.fn((value: string) => Buffer.from(`enc:${value}`)),
    isEncryptionAvailable: vi.fn(() => true),
  };
}

function writeLegacyKey(root: string, key: Buffer): void {
  writeFileSync(path.join(root, "data-protection-key.v1.json"), JSON.stringify({
    encryptedKey: Buffer.from(`enc:${key.toString("base64")}`).toString("base64"),
    schemaVersion: 1,
  }));
}

function pathExists(root: string, name: string): boolean {
  try {
    readFileSync(path.join(root, name));
    return true;
  } catch {
    return false;
  }
}

function temporaryRoot(): string {
  const root = mkdtempSync(path.join(tmpdir(), "agentweave-desktop-security-"));
  roots.push(root);
  return root;
}

function readyStatus() {
  return {
    attempt: 1,
    canEnsureRunning: false,
    lastExit: null,
    mode: "managed" as const,
    schemaVersion: 1 as const,
    state: "ready" as const,
  };
}

function managedResolution(dataRoot: string) {
  return {
    args: [],
    cacheRoot: path.join(dataRoot, "..", "cache"),
    command: "/app/agent-server",
    cwd: "/app",
    dataRoot,
    env: {},
    mode: "managed" as const,
    workspaceRoot: path.join(dataRoot, "..", "workspace"),
  };
}
