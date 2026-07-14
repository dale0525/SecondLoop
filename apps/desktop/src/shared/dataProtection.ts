export const DATA_PROTECTION_STATUS_CHANNEL = "agentweave:data-protection:status";
export const DATA_PROTECTION_EXPORT_CHANNEL = "agentweave:data-protection:export";
export const DATA_PROTECTION_RESTORE_CHANNEL = "agentweave:data-protection:restore";

export type DataProtectionStatus = Readonly<{
  enabled: boolean;
  atRestEncryption: "not_provided";
  backupEncryption: "aes-256-gcm" | "unavailable";
  backupFormat: "agentweave-backup-v1";
  pendingRestart: boolean;
  restoreRollbackAvailable: boolean;
}>;

export type BackupExportReceipt = Readonly<{
  exported: true;
  bytes: number;
  createdAt: string;
  sha256: string;
}>;

export type BackupRestoreReceipt = Readonly<{
  accepted: true;
  restarted: true;
  backup: {
    appId: string;
    createdAt: string;
    plaintextBytes: number;
    plaintextSha256: string;
    envelopeSha256: string;
  };
}>;

export function parseDataProtectionStatus(value: unknown): DataProtectionStatus {
  const record = exactRecord(value, [
    "atRestEncryption",
    "backupEncryption",
    "backupFormat",
    "enabled",
    "pendingRestart",
    "restoreRollbackAvailable",
  ]);
  if (typeof record.enabled !== "boolean"
    || record.atRestEncryption !== "not_provided"
    || !new Set(["aes-256-gcm", "unavailable"]).has(String(record.backupEncryption))
    || record.backupFormat !== "agentweave-backup-v1"
    || typeof record.pendingRestart !== "boolean"
    || typeof record.restoreRollbackAvailable !== "boolean") {
    throw new Error("Data protection status is invalid");
  }
  return Object.freeze(record as DataProtectionStatus);
}

export function parseBackupExportReceipt(value: unknown): BackupExportReceipt | null {
  if (value === null) return null;
  const record = exactRecord(value, ["bytes", "createdAt", "exported", "sha256"]);
  if (record.exported !== true
    || !Number.isSafeInteger(record.bytes)
    || (record.bytes as number) <= 0
    || typeof record.createdAt !== "string"
    || !Number.isFinite(Date.parse(record.createdAt))
    || typeof record.sha256 !== "string"
    || !/^[0-9a-f]{64}$/.test(record.sha256)) {
    throw new Error("Backup export receipt is invalid");
  }
  return Object.freeze(record as BackupExportReceipt);
}

export function parseBackupRestoreReceipt(value: unknown): BackupRestoreReceipt | null {
  if (value === null) return null;
  const record = exactRecord(value, ["accepted", "backup", "restarted"]);
  const backup = exactRecord(record.backup, [
    "appId",
    "createdAt",
    "envelopeSha256",
    "plaintextBytes",
    "plaintextSha256",
  ]);
  if (record.accepted !== true
    || record.restarted !== true
    || typeof backup.appId !== "string"
    || backup.appId.length === 0
    || typeof backup.createdAt !== "string"
    || !Number.isFinite(Date.parse(backup.createdAt))
    || !Number.isSafeInteger(backup.plaintextBytes)
    || (backup.plaintextBytes as number) < 0
    || typeof backup.plaintextSha256 !== "string"
    || !/^[0-9a-f]{64}$/.test(backup.plaintextSha256)
    || typeof backup.envelopeSha256 !== "string"
    || !/^[0-9a-f]{64}$/.test(backup.envelopeSha256)) {
    throw new Error("Backup restore receipt is invalid");
  }
  return Object.freeze({ accepted: true, backup, restarted: true }) as BackupRestoreReceipt;
}

function exactRecord(value: unknown, keys: readonly string[]): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error("Data protection response is invalid");
  }
  const record = value as Record<string, unknown>;
  if (Object.keys(record).some((key) => !keys.includes(key))) {
    throw new Error("Data protection response contains unknown fields");
  }
  return record;
}
