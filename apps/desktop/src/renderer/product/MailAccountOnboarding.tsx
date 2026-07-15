import * as Dialog from "@radix-ui/react-dialog";
import {
  Badge,
  Button,
  Card,
  Flex,
  Heading,
  Select,
  Text,
  TextField,
  Theme,
} from "@radix-ui/themes";
import {
  CheckCircle2,
  CircleAlert,
  KeyRound,
  LoaderCircle,
  MailPlus,
  Pencil,
  Server,
  ShieldCheck,
  Trash2,
  X,
} from "lucide-react";
import { FormEvent, useCallback, useEffect, useState } from "react";

import { connectMailAccount } from "../api";
import { useAppearance } from "../appearance/AppearanceProvider";
import { isLightTheme } from "../appearance/themePalette";
import {
  deleteMailAccountConfiguration,
  listMailAccountConfigurations,
  putMailAccountConfiguration,
  type FoundationMailConfiguration,
  type FoundationMailConfigurationInput,
  type FoundationMailTlsMode,
} from "../mailConfigurationApi";
import { useI18n } from "../i18n/I18nProvider";

type ProviderPreset = "custom" | "gmail" | "icloud" | "microsoft";
type MutationPhase = "idle" | "saving" | "testing";

type MailForm = {
  archiveMailbox: string;
  displayName: string;
  draftsMailbox: string;
  imapHost: string;
  imapPort: string;
  imapTls: FoundationMailTlsMode;
  password: string;
  primaryAddress: string;
  primaryName: string;
  provider: ProviderPreset;
  sentMailbox: string;
  smtpHost: string;
  smtpPort: string;
  smtpTls: FoundationMailTlsMode;
  trashMailbox: string;
  username: string;
};

export function MailAccountOnboarding({
  onChanged,
}: {
  onChanged: () => void;
}): JSX.Element {
  const { t } = useI18n();
  const { activeTheme } = useAppearance();
  const portalAppearance = isLightTheme(activeTheme) ? "light" : "dark";
  const [configurations, setConfigurations] = useState<FoundationMailConfiguration[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  const [editing, setEditing] = useState<FoundationMailConfiguration | "new" | null>(null);
  const [deleting, setDeleting] = useState<FoundationMailConfiguration | null>(null);
  const [deletingBusy, setDeletingBusy] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError(false);
    try {
      setConfigurations(await listMailAccountConfigurations());
    } catch {
      setError(true);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const changed = async () => {
    await load();
    onChanged();
  };

  const remove = async () => {
    if (!deleting) return;
    setDeletingBusy(true);
    try {
      await deleteMailAccountConfiguration(deleting.id);
      setDeleting(null);
      await changed();
    } catch {
      setError(true);
    } finally {
      setDeletingBusy(false);
    }
  };

  return (
    <section className="mail-onboarding" aria-labelledby="mail-onboarding-title">
      <div className="mail-onboarding-heading">
        <div>
          <Text className="foundation-kicker" size="1" weight="bold">
            {t("connections.mailOnboarding.eyebrow")}
          </Text>
          <Heading as="h2" id="mail-onboarding-title" size="5">
            {t("connections.mailOnboarding.title")}
          </Heading>
          <Text color="gray" size="2">
            {t("connections.mailOnboarding.description")}
          </Text>
        </div>
        <Button onClick={() => setEditing("new")}>
          <MailPlus aria-hidden="true" size={16} />
          {t("connections.mailOnboarding.add")}
        </Button>
      </div>

      <div className="mail-onboarding-boundary">
        <ShieldCheck aria-hidden="true" size={16} />
        <Text size="2">{t("connections.mailOnboarding.securityBoundary")}</Text>
      </div>

      {loading ? (
        <div className="mail-onboarding-loading" role="status">
          <LoaderCircle aria-hidden="true" className="spin" size={16} />
          <Text color="gray" size="2">{t("connections.mailOnboarding.loading")}</Text>
        </div>
      ) : null}

      {!loading && error ? (
        <Card className="mail-onboarding-error">
          <Flex align="start" gap="3">
            <CircleAlert aria-hidden="true" size={18} />
            <div>
              <Text as="div" weight="bold">{t("connections.mailOnboarding.loadFailed")}</Text>
              <Button mt="3" onClick={() => void load()} variant="soft">
                {t("today.retry")}
              </Button>
            </div>
          </Flex>
        </Card>
      ) : null}

      {!loading && !error && configurations.length === 0 ? (
        <Card className="mail-onboarding-empty" size="3">
          <span className="mail-onboarding-empty-icon"><KeyRound aria-hidden="true" size={20} /></span>
          <div>
            <Text as="div" weight="bold">{t("connections.mailOnboarding.emptyTitle")}</Text>
            <Text as="div" color="gray" size="2">
              {t("connections.mailOnboarding.emptyDescription")}
            </Text>
          </div>
          <Button onClick={() => setEditing("new")} variant="soft">
            {t("connections.mailOnboarding.addFirst")}
          </Button>
        </Card>
      ) : null}

      {!loading && !error && configurations.length > 0 ? (
        <div className="mail-configuration-list">
          {configurations.map((configuration) => (
            <Card className="mail-configuration-card" key={configuration.id} size="3">
              <div className="mail-configuration-identity">
                <span aria-hidden="true" className="account-monogram">
                  {configuration.displayName.slice(0, 1)}
                </span>
                <div>
                  <Text as="div" weight="bold">{configuration.displayName}</Text>
                  <Text as="div" color="gray" size="2">{configuration.primaryAddress}</Text>
                </div>
                <Badge
                  color={configuration.credentialConfigured ? "green" : "amber"}
                  radius="full"
                  variant="soft"
                >
                  {configuration.credentialConfigured
                    ? t("connections.mailOnboarding.credentialReady")
                    : t("connections.mailOnboarding.credentialMissing")}
                </Badge>
              </div>
              <div className="mail-configuration-endpoints">
                <EndpointFact
                  label={t("connections.mailOnboarding.incoming")}
                  value={`${configuration.imapHost}:${configuration.imapPort}`}
                />
                <EndpointFact
                  label={t("connections.mailOnboarding.outgoing")}
                  value={`${configuration.smtpHost}:${configuration.smtpPort}`}
                />
              </div>
              <Flex className="mail-configuration-actions" gap="2" justify="end">
                <Button onClick={() => setEditing(configuration)} variant="soft">
                  <Pencil aria-hidden="true" size={15} />
                  {t("connections.mailOnboarding.edit")}
                </Button>
                <Button color="red" onClick={() => setDeleting(configuration)} variant="soft">
                  <Trash2 aria-hidden="true" size={15} />
                  {t("connections.mailOnboarding.remove")}
                </Button>
              </Flex>
            </Card>
          ))}
        </div>
      ) : null}

      <Dialog.Root
        onOpenChange={(open) => {
          if (!open) setEditing(null);
        }}
        open={editing !== null}
      >
        <Dialog.Portal>
          <Theme
            accentColor="blue"
            appearance={portalAppearance}
            grayColor="gray"
            hasBackground={false}
            radius="small"
            scaling="100%"
          >
            <Dialog.Overlay className="mail-dialog-overlay" />
            <Dialog.Content className="mail-dialog-content">
              {editing ? (
                <MailConfigurationForm
                  configuration={editing === "new" ? null : editing}
                  onCancel={() => setEditing(null)}
                  onChanged={changed}
                  onComplete={() => setEditing(null)}
                />
              ) : null}
            </Dialog.Content>
          </Theme>
        </Dialog.Portal>
      </Dialog.Root>

      <Dialog.Root
        onOpenChange={(open) => {
          if (!open && !deletingBusy) setDeleting(null);
        }}
        open={deleting !== null}
      >
        <Dialog.Portal>
          <Theme
            accentColor="blue"
            appearance={portalAppearance}
            grayColor="gray"
            hasBackground={false}
            radius="small"
            scaling="100%"
          >
            <Dialog.Overlay className="mail-dialog-overlay" />
            <Dialog.Content className="mail-delete-dialog">
              <Dialog.Title>{t("connections.mailOnboarding.removeTitle")}</Dialog.Title>
              <Dialog.Description>
                {t("connections.mailOnboarding.removeDescription", {
                  account: deleting?.primaryAddress ?? "",
                })}
              </Dialog.Description>
              <Flex gap="3" justify="end" mt="5">
                <Button disabled={deletingBusy} onClick={() => setDeleting(null)} variant="soft">
                  {t("today.cancel")}
                </Button>
                <Button color="red" disabled={deletingBusy} onClick={() => void remove()}>
                  {deletingBusy ? <LoaderCircle className="spin" size={15} /> : <Trash2 size={15} />}
                  {t("connections.mailOnboarding.confirmRemove")}
                </Button>
              </Flex>
            </Dialog.Content>
          </Theme>
        </Dialog.Portal>
      </Dialog.Root>
    </section>
  );
}

function MailConfigurationForm({
  configuration,
  onCancel,
  onChanged,
  onComplete,
}: {
  configuration: FoundationMailConfiguration | null;
  onCancel: () => void;
  onChanged: () => Promise<void>;
  onComplete: () => void;
}): JSX.Element {
  const { t } = useI18n();
  const [form, setForm] = useState(() => initialForm(configuration));
  const [phase, setPhase] = useState<MutationPhase>("idle");
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const accountId = useState(() => configuration?.id ?? createAccountId())[0];
  const busy = phase !== "idle";

  const update = <K extends keyof MailForm>(key: K, value: MailForm[K]) => {
    setForm((current) => ({ ...current, [key]: value }));
    setError(null);
    setSaved(false);
  };

  const selectProvider = (provider: ProviderPreset) => {
    setForm((current) => ({ ...current, ...providerDefaults(provider), provider }));
    setError(null);
    setSaved(false);
  };

  const testConnection = async () => {
    setPhase("testing");
    setError(null);
    try {
      await connectMailAccount(accountId);
      await onChanged();
      onComplete();
    } catch {
      setError(t("connections.mailOnboarding.testFailed"));
    } finally {
      setPhase("idle");
    }
  };

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (saved) {
      await testConnection();
      return;
    }
    const input = configurationInput(accountId, form);
    if (!input) {
      setError(t("connections.mailOnboarding.invalid"));
      return;
    }
    setPhase("saving");
    setError(null);
    try {
      await putMailAccountConfiguration(input);
      setForm((current) => ({ ...current, password: "" }));
      setSaved(true);
      await onChanged();
      await testConnection();
    } catch {
      setForm((current) => ({ ...current, password: "" }));
      setError(t("connections.mailOnboarding.saveFailed"));
      setPhase("idle");
    }
  };

  return (
    <form className="mail-configuration-form" onSubmit={(event) => void submit(event)}>
      <div className="mail-dialog-heading">
        <div>
          <Text className="foundation-kicker" size="1" weight="bold">
            {configuration
              ? t("connections.mailOnboarding.editEyebrow")
              : t("connections.mailOnboarding.addEyebrow")}
          </Text>
          <Dialog.Title>
            {configuration
              ? t("connections.mailOnboarding.editTitle")
              : t("connections.mailOnboarding.addTitle")}
          </Dialog.Title>
          <Dialog.Description>{t("connections.mailOnboarding.formDescription")}</Dialog.Description>
        </div>
        <Dialog.Close asChild>
          <button aria-label={t("connections.mailOnboarding.close")} className="mail-dialog-close" type="button">
            <X aria-hidden="true" size={18} />
          </button>
        </Dialog.Close>
      </div>

      <div className="mail-provider-field">
        <FormLabel label={t("connections.mailOnboarding.provider")}>
          <Select.Root
            disabled={busy}
            onValueChange={(value) => selectProvider(value as ProviderPreset)}
            value={form.provider}
          >
            <Select.Trigger />
            <Select.Content>
              {(["gmail", "microsoft", "icloud", "custom"] as const).map((provider) => (
                <Select.Item key={provider} value={provider}>
                  {t(`connections.mailOnboarding.provider.${provider}`)}
                </Select.Item>
              ))}
            </Select.Content>
          </Select.Root>
        </FormLabel>
        <Text color="gray" size="1">{t("connections.mailOnboarding.appPasswordHint")}</Text>
      </div>

      <fieldset disabled={busy}>
        <legend>{t("connections.mailOnboarding.identity")}</legend>
        <div className="mail-form-grid">
          <FormText
            label={t("connections.mailOnboarding.displayName")}
            onChange={(value) => update("displayName", value)}
            value={form.displayName}
          />
          <FormText
            label={t("connections.mailOnboarding.primaryName")}
            onChange={(value) => update("primaryName", value)}
            value={form.primaryName}
          />
          <FormText
            autoComplete="email"
            label={t("connections.mailOnboarding.email")}
            onChange={(value) => {
              setForm((current) => ({
                ...current,
                primaryAddress: value,
                username: current.username === current.primaryAddress ? value : current.username,
              }));
              setError(null);
              setSaved(false);
            }}
            type="email"
            value={form.primaryAddress}
          />
          <FormText
            autoComplete="username"
            label={t("connections.mailOnboarding.username")}
            onChange={(value) => update("username", value)}
            value={form.username}
          />
          <FormText
            autoComplete="new-password"
            label={t("connections.mailOnboarding.password")}
            onChange={(value) => update("password", value)}
            type="password"
            value={form.password}
          />
        </div>
      </fieldset>

      <fieldset disabled={busy}>
        <legend>{t("connections.mailOnboarding.servers")}</legend>
        <div className="mail-server-grid">
          <ServerFields
            disabled={busy}
            host={form.imapHost}
            hostLabel={t("connections.mailOnboarding.imapHost")}
            onHost={(value) => update("imapHost", value)}
            onPort={(value) => update("imapPort", value)}
            onTls={(value) => update("imapTls", value)}
            port={form.imapPort}
            tls={form.imapTls}
          />
          <ServerFields
            disabled={busy}
            host={form.smtpHost}
            hostLabel={t("connections.mailOnboarding.smtpHost")}
            onHost={(value) => update("smtpHost", value)}
            onPort={(value) => update("smtpPort", value)}
            onTls={(value) => update("smtpTls", value)}
            port={form.smtpPort}
            tls={form.smtpTls}
          />
        </div>
      </fieldset>

      <details className="mail-advanced-fields">
        <summary>{t("connections.mailOnboarding.advanced")}</summary>
        <div className="mail-form-grid">
          {(["archiveMailbox", "sentMailbox", "draftsMailbox", "trashMailbox"] as const).map((key) => (
            <FormText
              disabled={busy}
              key={key}
              label={t(`connections.mailOnboarding.${key}`)}
              onChange={(value) => update(key, value)}
              value={form[key]}
            />
          ))}
        </div>
      </details>

      {saved ? (
        <div className="mail-form-status is-saved" role="status">
          <CheckCircle2 aria-hidden="true" size={16} />
          {t("connections.mailOnboarding.saved")}
        </div>
      ) : null}
      {error ? (
        <div className="mail-form-status is-error" role="alert">
          <CircleAlert aria-hidden="true" size={16} />
          {error}
        </div>
      ) : null}

      <div className="mail-form-actions">
        <Button disabled={busy} onClick={onCancel} type="button" variant="soft">
          {t("today.cancel")}
        </Button>
        <Button disabled={busy} type="submit">
          {phase === "saving" ? <LoaderCircle className="spin" size={15} /> : null}
          {phase === "testing" ? <LoaderCircle className="spin" size={15} /> : null}
          {phase === "saving"
            ? t("connections.mailOnboarding.saving")
            : phase === "testing"
              ? t("connections.mailOnboarding.testing")
              : saved
                ? t("connections.mailOnboarding.retryTest")
                : t("connections.mailOnboarding.saveAndTest")}
        </Button>
      </div>
    </form>
  );
}

function EndpointFact({ label, value }: { label: string; value: string }): JSX.Element {
  return (
    <div>
      <Server aria-hidden="true" size={14} />
      <span><small>{label}</small><strong>{value}</strong></span>
    </div>
  );
}

function FormLabel({ children, label }: { children: React.ReactNode; label: string }): JSX.Element {
  return <label><Text as="span" size="2" weight="medium">{label}</Text>{children}</label>;
}

function FormText({
  autoComplete,
  disabled = false,
  label,
  onChange,
  type = "text",
  value,
}: {
  autoComplete?: string;
  disabled?: boolean;
  label: string;
  onChange: (value: string) => void;
  type?: "email" | "password" | "text";
  value: string;
}): JSX.Element {
  return (
    <FormLabel label={label}>
      <TextField.Root
        autoComplete={autoComplete}
        disabled={disabled}
        onChange={(event) => onChange(event.currentTarget.value)}
        spellCheck={false}
        type={type}
        value={value}
      />
    </FormLabel>
  );
}

function ServerFields({
  disabled,
  host,
  hostLabel,
  onHost,
  onPort,
  onTls,
  port,
  tls,
}: {
  disabled: boolean;
  host: string;
  hostLabel: string;
  onHost: (value: string) => void;
  onPort: (value: string) => void;
  onTls: (value: FoundationMailTlsMode) => void;
  port: string;
  tls: FoundationMailTlsMode;
}): JSX.Element {
  const { t } = useI18n();
  return (
    <div className="mail-server-fields">
      <FormText label={hostLabel} onChange={onHost} value={host} />
      <FormText label={t("connections.mailOnboarding.port")} onChange={onPort} value={port} />
      <FormLabel label={t("connections.mailOnboarding.tls")}>
        <Select.Root
          disabled={disabled}
          onValueChange={(value) => onTls(value as FoundationMailTlsMode)}
          value={tls}
        >
          <Select.Trigger />
          <Select.Content>
            <Select.Item value="implicit">{t("connections.mailOnboarding.tls.implicit")}</Select.Item>
            <Select.Item value="start_tls">{t("connections.mailOnboarding.tls.startTls")}</Select.Item>
          </Select.Content>
        </Select.Root>
      </FormLabel>
    </div>
  );
}

function initialForm(configuration: FoundationMailConfiguration | null): MailForm {
  if (!configuration) return { ...emptyForm(), ...providerDefaults("gmail"), provider: "gmail" };
  return {
    archiveMailbox: configuration.archiveMailbox ?? "",
    displayName: configuration.displayName,
    draftsMailbox: configuration.draftsMailbox ?? "",
    imapHost: configuration.imapHost,
    imapPort: String(configuration.imapPort),
    imapTls: configuration.imapTls,
    password: "",
    primaryAddress: configuration.primaryAddress,
    primaryName: configuration.primaryName ?? "",
    provider: detectProvider(configuration),
    sentMailbox: configuration.sentMailbox ?? "",
    smtpHost: configuration.smtpHost,
    smtpPort: String(configuration.smtpPort),
    smtpTls: configuration.smtpTls,
    trashMailbox: configuration.trashMailbox ?? "",
    username: configuration.username,
  };
}

function emptyForm(): MailForm {
  return {
    archiveMailbox: "Archive",
    displayName: "",
    draftsMailbox: "Drafts",
    imapHost: "",
    imapPort: "993",
    imapTls: "implicit",
    password: "",
    primaryAddress: "",
    primaryName: "",
    provider: "custom",
    sentMailbox: "Sent",
    smtpHost: "",
    smtpPort: "587",
    smtpTls: "start_tls",
    trashMailbox: "Trash",
    username: "",
  };
}

function providerDefaults(provider: ProviderPreset): Partial<MailForm> {
  switch (provider) {
    case "gmail":
      return { displayName: "Gmail", imapHost: "imap.gmail.com", imapPort: "993", imapTls: "implicit", smtpHost: "smtp.gmail.com", smtpPort: "465", smtpTls: "implicit" };
    case "microsoft":
      return { displayName: "Microsoft 365", imapHost: "outlook.office365.com", imapPort: "993", imapTls: "implicit", smtpHost: "smtp.office365.com", smtpPort: "587", smtpTls: "start_tls" };
    case "icloud":
      return { displayName: "iCloud Mail", imapHost: "imap.mail.me.com", imapPort: "993", imapTls: "implicit", smtpHost: "smtp.mail.me.com", smtpPort: "587", smtpTls: "start_tls" };
    case "custom":
      return { displayName: "", imapHost: "", imapPort: "993", imapTls: "implicit", smtpHost: "", smtpPort: "587", smtpTls: "start_tls" };
  }
}

function detectProvider(configuration: FoundationMailConfiguration): ProviderPreset {
  if (configuration.imapHost === "imap.gmail.com") return "gmail";
  if (configuration.imapHost === "outlook.office365.com") return "microsoft";
  if (configuration.imapHost === "imap.mail.me.com") return "icloud";
  return "custom";
}

function configurationInput(
  id: string,
  form: MailForm,
): FoundationMailConfigurationInput | null {
  const imapPort = Number(form.imapPort);
  const smtpPort = Number(form.smtpPort);
  const required = [form.displayName, form.primaryAddress, form.username, form.password, form.imapHost, form.smtpHost];
  if (required.some((value) => value.trim().length === 0)) return null;
  if (![imapPort, smtpPort].every((port) => Number.isInteger(port) && port > 0 && port <= 65_535)) return null;
  return {
    id,
    displayName: form.displayName.trim(),
    ...(form.primaryName.trim() ? { primaryName: form.primaryName.trim() } : {}),
    primaryAddress: form.primaryAddress.trim(),
    username: form.username.trim(),
    password: form.password,
    imapHost: form.imapHost.trim(),
    imapPort,
    imapTls: form.imapTls,
    smtpHost: form.smtpHost.trim(),
    smtpPort,
    smtpTls: form.smtpTls,
    ...(form.archiveMailbox.trim() ? { archiveMailbox: form.archiveMailbox.trim() } : {}),
    ...(form.sentMailbox.trim() ? { sentMailbox: form.sentMailbox.trim() } : {}),
    ...(form.draftsMailbox.trim() ? { draftsMailbox: form.draftsMailbox.trim() } : {}),
    ...(form.trashMailbox.trim() ? { trashMailbox: form.trashMailbox.trim() } : {}),
  };
}

function createAccountId(): string {
  return typeof globalThis.crypto?.randomUUID === "function"
    ? globalThis.crypto.randomUUID()
    : `mail-${Date.now().toString(36)}`;
}
