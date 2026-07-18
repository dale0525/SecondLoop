import type { DesktopSecurityKeyStore } from "./desktopSecurityKeys";
import type { DesktopSidecarController } from "./sidecarController";

export type ProvisionedBackupKey = Readonly<{
  wrappedKey: string;
}>;

export type DesktopSecurityProvisioningFailure =
  | "credential-key-unavailable"
  | "sidecar-startup-failed";

export class DesktopSecurityProvisioningError extends Error {
  readonly failure: DesktopSecurityProvisioningFailure;

  constructor(failure: DesktopSecurityProvisioningFailure) {
    super(`Desktop security provisioning failed: ${failure}`);
    this.name = "DesktopSecurityProvisioningError";
    this.failure = failure;
  }
}

export function securityProvisioningFailure(
  error: unknown,
): DesktopSecurityProvisioningFailure | "unknown" {
  return error instanceof DesktopSecurityProvisioningError ? error.failure : "unknown";
}

export type DesktopSecurityProvisioner = Readonly<{
  ensureBackup(): Promise<ProvisionedBackupKey>;
  ensureCredentialVault(options?: { allowCreate?: boolean }): Promise<void>;
  unwrapBackupKey(wrappedKey: string): Buffer;
}>;

export function createDesktopSecurityProvisioner(options: {
  keyStore: DesktopSecurityKeyStore;
  sidecar: Pick<DesktopSidecarController, "provisionLaunchKeys">;
}): DesktopSecurityProvisioner {
  let backup: ProvisionedBackupKey | null = null;
  let backupOperation: Promise<ProvisionedBackupKey> | null = null;
  let credentialVaultReady = false;
  let credentialVaultOperation: Promise<void> | null = null;

  const ensureBackup = (): Promise<ProvisionedBackupKey> => {
    if (backup) return Promise.resolve(backup);
    if (backupOperation) return backupOperation;
    const operation = Promise.resolve().then(async () => {
      const loaded = options.keyStore.loadBackupKey();
      try {
        await options.sidecar.provisionLaunchKeys({ backupKey: loaded.key });
        backup = Object.freeze({ wrappedKey: loaded.wrappedKey });
        return backup;
      } finally {
        loaded.key.fill(0);
      }
    });
    backupOperation = operation;
    void operation.finally(() => {
      if (backupOperation === operation) backupOperation = null;
    }).catch(() => undefined);
    return operation;
  };

  const ensureCredentialVault = (
    { allowCreate = true }: { allowCreate?: boolean } = {},
  ): Promise<void> => {
    if (credentialVaultReady) return Promise.resolve();
    if (credentialVaultOperation) return credentialVaultOperation;
    const operation = Promise.resolve().then(async () => {
      let key: Buffer;
      try {
        key = options.keyStore.loadCredentialVaultKey({ allowCreate });
      } catch {
        throw new DesktopSecurityProvisioningError("credential-key-unavailable");
      }
      try {
        try {
          await options.sidecar.provisionLaunchKeys({ credentialVaultKey: key });
        } catch {
          throw new DesktopSecurityProvisioningError("sidecar-startup-failed");
        }
        credentialVaultReady = true;
      } finally {
        key.fill(0);
      }
    });
    credentialVaultOperation = operation;
    void operation.finally(() => {
      if (credentialVaultOperation === operation) credentialVaultOperation = null;
    }).catch(() => undefined);
    return operation;
  };

  return Object.freeze({
    ensureBackup,
    ensureCredentialVault,
    unwrapBackupKey: (wrappedKey) => options.keyStore.unwrapBackupKey(wrappedKey),
  });
}
