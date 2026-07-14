import * as Dialog from "@radix-ui/react-dialog";
import { Badge, Button, Callout, Flex, Text } from "@radix-ui/themes";
import {
  ArchiveRestore,
  CheckCircle2,
  DatabaseBackup,
  LoaderCircle,
  ShieldAlert,
  ShieldCheck,
  X,
} from "lucide-react";
import { useEffect, useState } from "react";

import {
  exportEncryptedBackup,
  getDataProtectionStatus,
  restoreEncryptedBackup,
  type DataProtectionStatus,
} from "../api";
import { useI18n } from "../i18n/I18nProvider";

type Operation = "export" | "restore" | null;
type Notice = "exported" | "restored" | "failed" | null;

export function SettingsDataProtection(): JSX.Element {
  const { t } = useI18n();
  const [status, setStatus] = useState<DataProtectionStatus | null>(null);
  const [loading, setLoading] = useState(true);
  const [operation, setOperation] = useState<Operation>(null);
  const [notice, setNotice] = useState<Notice>(null);
  const [restoreOpen, setRestoreOpen] = useState(false);

  const load = async () => {
    setLoading(true);
    try {
      setStatus(await getDataProtectionStatus());
    } catch {
      setStatus(null);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void load();
  }, []);

  const exportBackup = async () => {
    setOperation("export");
    setNotice(null);
    try {
      const receipt = await exportEncryptedBackup();
      if (receipt) setNotice("exported");
    } catch {
      setNotice("failed");
    } finally {
      setOperation(null);
    }
  };

  const restoreBackup = async () => {
    setOperation("restore");
    setNotice(null);
    try {
      const receipt = await restoreEncryptedBackup();
      if (receipt) {
        setNotice("restored");
        setRestoreOpen(false);
        await load();
      }
    } catch {
      setNotice("failed");
    } finally {
      setOperation(null);
    }
  };

  const backupAvailable = status?.enabled === true
    && status.backupEncryption === "aes-256-gcm";

  return (
    <section className="settings-panel data-protection-panel" aria-labelledby="settings-data-title">
      <div className="settings-panel-heading">
        <h2 id="settings-data-title">{t("settings.dataProtection.title")}</h2>
        <p>{t("settings.dataProtection.description")}</p>
      </div>

      {loading ? (
        <Flex align="center" gap="2" role="status">
          <LoaderCircle aria-hidden="true" className="spin" size={16} />
          <Text color="gray" size="2">{t("settings.dataProtection.loading")}</Text>
        </Flex>
      ) : status ? (
        <div className="data-protection-status-grid">
          <StatusFact
            label={t("settings.dataProtection.activeDatabase")}
            state="neutral"
            value={t("settings.dataProtection.atRestNotProvided")}
          />
          <StatusFact
            label={t("settings.dataProtection.backups")}
            state={backupAvailable ? "ready" : "warning"}
            value={backupAvailable
              ? t("settings.dataProtection.encryptedBackupReady")
              : t("settings.dataProtection.secureStorageUnavailable")}
          />
          <StatusFact
            label={t("settings.dataProtection.rollback")}
            state={status.restoreRollbackAvailable ? "ready" : "neutral"}
            value={status.restoreRollbackAvailable
              ? t("settings.dataProtection.rollbackAvailable")
              : t("settings.dataProtection.rollbackNotCreated")}
          />
        </div>
      ) : (
        <Callout.Root color="amber" role="alert" size="2">
          <Callout.Icon><ShieldAlert aria-hidden="true" /></Callout.Icon>
          <Callout.Text>{t("settings.dataProtection.unavailable")}</Callout.Text>
          <Button onClick={() => void load()} size="1" variant="soft">
            {t("today.retry")}
          </Button>
        </Callout.Root>
      )}

      <Callout.Root color="gray" size="2">
        <Callout.Icon><ShieldCheck aria-hidden="true" /></Callout.Icon>
        <Callout.Text>{t("settings.dataProtection.scopeNote")}</Callout.Text>
      </Callout.Root>

      {notice ? (
        <Callout.Root color={notice === "failed" ? "red" : "green"} role="status" size="2">
          <Callout.Icon>
            {notice === "failed"
              ? <ShieldAlert aria-hidden="true" />
              : <CheckCircle2 aria-hidden="true" />}
          </Callout.Icon>
          <Callout.Text>{t(`settings.dataProtection.${notice}`)}</Callout.Text>
        </Callout.Root>
      ) : null}

      <Flex className="data-protection-actions" gap="3" wrap="wrap">
        <Button
          disabled={!backupAvailable || operation !== null}
          onClick={() => void exportBackup()}
          variant="soft"
        >
          {operation === "export"
            ? <LoaderCircle aria-hidden="true" className="spin" size={16} />
            : <DatabaseBackup aria-hidden="true" size={16} />}
          {operation === "export"
            ? t("settings.dataProtection.exporting")
            : t("settings.dataProtection.export")}
        </Button>
        <Button
          color="amber"
          disabled={!backupAvailable || operation !== null}
          onClick={() => setRestoreOpen(true)}
          variant="soft"
        >
          <ArchiveRestore aria-hidden="true" size={16} />
          {t("settings.dataProtection.restore")}
        </Button>
      </Flex>

      <Dialog.Root onOpenChange={setRestoreOpen} open={restoreOpen}>
        <Dialog.Portal>
          <Dialog.Overlay className="foundation-dialog-overlay" />
          <Dialog.Content className="foundation-dialog-content data-protection-dialog">
            <Flex align="start" justify="between" gap="3">
              <div>
                <Dialog.Title className="foundation-dialog-title">
                  {t("settings.dataProtection.restoreTitle")}
                </Dialog.Title>
                <Dialog.Description className="foundation-dialog-description">
                  {t("settings.dataProtection.restoreDescription")}
                </Dialog.Description>
              </div>
              <Dialog.Close asChild>
                <button
                  aria-label={t("common.close")}
                  className="dialog-close"
                  disabled={operation === "restore"}
                  type="button"
                >
                  <X aria-hidden="true" size={16} />
                </button>
              </Dialog.Close>
            </Flex>
            <Callout.Root color="amber" mt="4" size="2">
              <Callout.Icon><ShieldAlert aria-hidden="true" /></Callout.Icon>
              <Callout.Text>{t("settings.dataProtection.restoreWarning")}</Callout.Text>
            </Callout.Root>
            <Flex className="data-protection-dialog-actions" gap="3" justify="end" mt="5">
              <Dialog.Close asChild>
                <Button disabled={operation === "restore"} variant="soft">
                  {t("common.cancel")}
                </Button>
              </Dialog.Close>
              <Button
                color="amber"
                disabled={operation === "restore"}
                onClick={() => void restoreBackup()}
              >
                {operation === "restore"
                  ? <LoaderCircle aria-hidden="true" className="spin" size={16} />
                  : <ArchiveRestore aria-hidden="true" size={16} />}
                {operation === "restore"
                  ? t("settings.dataProtection.restoring")
                  : t("settings.dataProtection.confirmRestore")}
              </Button>
            </Flex>
          </Dialog.Content>
        </Dialog.Portal>
      </Dialog.Root>
    </section>
  );
}

function StatusFact({
  label,
  state,
  value,
}: {
  label: string;
  state: "neutral" | "ready" | "warning";
  value: string;
}): JSX.Element {
  return (
    <div className="data-protection-status-fact">
      <Text color="gray" size="1" weight="bold">{label}</Text>
      <Flex align="center" gap="2">
        <Badge
          color={state === "ready" ? "green" : state === "warning" ? "amber" : "gray"}
          radius="full"
          variant="soft"
        >
          {value}
        </Badge>
      </Flex>
    </div>
  );
}
