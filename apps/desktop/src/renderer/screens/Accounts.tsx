import { Badge, Button, Card, Flex, Heading, Text } from "@radix-ui/themes";
import { ArrowLeft, CircleAlert, LoaderCircle, Mail, Plug, Unplug } from "lucide-react";
import { useEffect, useMemo, useState } from "react";

import {
  MailAccount,
  MailAccountStatus,
  connectMailAccount,
  disconnectMailAccount,
  getMailAccountStatus,
  listMailAccounts
} from "../api";
import { AppIconButton } from "../components/AppIconButton";
import { useI18n } from "../i18n/I18nProvider";

type AccountsProps = { onBack: () => void };

export function Accounts({ onBack }: AccountsProps): JSX.Element {
  const { t } = useI18n();
  const [accounts, setAccounts] = useState<MailAccount[]>([]);
  const [statuses, setStatuses] = useState<Record<string, MailAccountStatus>>({});
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = async () => {
    setLoading(true);
    setError(null);
    try {
      const nextAccounts = await listMailAccounts();
      const nextStatuses = await Promise.all(
        nextAccounts.map((account) => getMailAccountStatus(account.id))
      );
      setAccounts(nextAccounts);
      setStatuses(Object.fromEntries(nextStatuses.map((status) => [status.account.id, status])));
      setSelectedId((current) => current ?? nextAccounts[0]?.id ?? null);
    } catch (reason) {
      setError(errorMessage(reason));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { void load(); }, []);
  const selected = useMemo(
    () => accounts.find((account) => account.id === selectedId) ?? null,
    [accounts, selectedId]
  );
  const status = selected ? statuses[selected.id] : undefined;

  const changeConnection = async () => {
    if (!selected || !status) return;
    setBusy(true);
    setError(null);
    try {
      const next = status.state === "connected"
        ? await disconnectMailAccount(selected.id)
        : await connectMailAccount(selected.id);
      setStatuses((current) => ({ ...current, [selected.id]: next }));
    } catch (reason) {
      setError(errorMessage(reason));
    } finally {
      setBusy(false);
    }
  };

  return (
    <main className="foundation-screen" aria-label={t("foundation.accounts.title")}>
      <FoundationHeader
        eyebrow={t("foundation.accounts.eyebrow")}
        onBack={onBack}
        subtitle={t("foundation.accounts.subtitle")}
        title={t("foundation.accounts.title")}
      />
      <div className="foundation-page-shell accounts-layout">
        <aside className="foundation-list-column" aria-label={t("foundation.accounts.available")}>
          <div className="foundation-column-heading">
            <Text color="gray" size="1" weight="bold">{t("foundation.accounts.list")}</Text>
            <Badge color="gray" radius="full">{accounts.length}</Badge>
          </div>
          {loading ? <LoadingRow label={t("foundation.accounts.loading")} /> : null}
          {!loading && accounts.length === 0 && !error ? (
            <EmptyCard
              icon={<Mail size={20} />}
              text={t("foundation.accounts.emptyDescription")}
              title={t("foundation.accounts.emptyTitle")}
            />
          ) : null}
          {accounts.map((account) => {
            const itemStatus = statuses[account.id];
            return (
              <button
                aria-pressed={selectedId === account.id}
                className="foundation-list-item"
                key={account.id}
                onClick={() => setSelectedId(account.id)}
                type="button"
              >
                <span className="account-monogram" aria-hidden="true">{account.displayName.slice(0, 1)}</span>
                <span><strong>{account.displayName}</strong><small>{account.primaryAddress.address}</small></span>
                <StatusDot state={itemStatus?.state} />
              </button>
            );
          })}
        </aside>
        <section className="foundation-detail-column" aria-live="polite">
          {error ? <ErrorCard message={error} onRetry={() => void load()} /> : null}
          {!error && selected && status ? (
            <Card className="foundation-detail-card" size="4">
              <Flex align="start" justify="between" gap="4" wrap="wrap">
                <Flex align="center" gap="3">
                  <span className="account-monogram large" aria-hidden="true">{selected.displayName.slice(0, 1)}</span>
                  <div>
                    <Text color="gray" size="1" weight="bold">{t("foundation.accounts.active")}</Text>
                    <Heading as="h2" mt="1" size="6">{selected.displayName}</Heading>
                    <Text color="gray" size="2">{selected.primaryAddress.address}</Text>
                  </div>
                </Flex>
                <AccountStateBadge state={status.state} />
              </Flex>
              <div className="foundation-rule" />
              <dl className="foundation-facts">
                <Fact label={t("foundation.accounts.connectorContract")} value="agentweave-mail / v1" />
                <Fact label={t("foundation.accounts.accountReference")} value={selected.id} />
                <Fact label={t("foundation.accounts.credentialAccess")} value={t("foundation.accounts.hostVaultOnly")} />
                <Fact label={t("foundation.accounts.sendPolicy")} value={t("foundation.accounts.exactPreviewApproval")} />
              </dl>
              {status.detail ? <Text className="foundation-note" size="2">{status.detail}</Text> : null}
              <Flex align="center" justify="between" gap="3" mt="5" wrap="wrap">
                <Text color="gray" size="2">{t("foundation.accounts.hostChangeNotice")}</Text>
                <Button
                  color={status.state === "connected" ? "red" : "green"}
                  disabled={busy}
                  onClick={() => void changeConnection()}
                  variant={status.state === "connected" ? "soft" : "solid"}
                >
                  {busy ? <LoaderCircle className="spin" size={15} /> : status.state === "connected" ? <Unplug size={15} /> : <Plug size={15} />}
                  {status.state === "connected"
                    ? t("foundation.accounts.disconnect")
                    : t("foundation.accounts.connect")}
                </Button>
              </Flex>
            </Card>
          ) : null}
        </section>
      </div>
    </main>
  );
}

export function FoundationHeader({ eyebrow, onBack, subtitle, title }: { eyebrow: string; onBack: () => void; subtitle: string; title: string }): JSX.Element {
  const { t } = useI18n();
  return (
    <header className="foundation-header">
      <AppIconButton label={t("common.backToSettings")} onClick={onBack}><ArrowLeft aria-hidden="true" size={18} /></AppIconButton>
      <div><Text className="foundation-kicker" size="1" weight="bold">{eyebrow}</Text><Heading as="h1" size="6">{title}</Heading><Text color="gray" size="2">{subtitle}</Text></div>
      <span className="top-bar-spacer" aria-hidden="true" />
    </header>
  );
}

function AccountStateBadge({ state }: { state: MailAccountStatus["state"] }): JSX.Element {
  const { t } = useI18n();
  const connected = state === "connected";
  return <Badge color={connected ? "green" : state === "unavailable" ? "red" : "amber"} radius="full" size="2">{connected ? t("foundation.accounts.connected") : state === "unavailable" ? t("foundation.accounts.unavailable") : t("foundation.accounts.signInRequired")}</Badge>;
}

function StatusDot({ state }: { state?: MailAccountStatus["state"] }): JSX.Element {
  return <span aria-label={state ?? "unknown"} className={`status-dot ${state ?? "unknown"}`} />;
}

function Fact({ label, value }: { label: string; value: string }): JSX.Element {
  return <div><dt>{label}</dt><dd>{value}</dd></div>;
}

function LoadingRow({ label }: { label: string }): JSX.Element {
  return <Flex align="center" gap="2" p="3"><LoaderCircle className="spin" size={16} /><Text color="gray" size="2">{label}</Text></Flex>;
}

function EmptyCard({ icon, text, title }: { icon: React.ReactNode; text: string; title: string }): JSX.Element {
  return <Card className="foundation-empty"><Flex align="center" direction="column" gap="2">{icon}<Text weight="bold">{title}</Text><Text align="center" color="gray" size="2">{text}</Text></Flex></Card>;
}

function ErrorCard({ message, onRetry }: { message: string; onRetry: () => void }): JSX.Element {
  const { t } = useI18n();
  return <Card className="foundation-error"><Flex align="start" gap="3"><CircleAlert aria-hidden="true" size={18} /><div><Text as="div" weight="bold">{t("foundation.serviceUnavailable")}</Text><Text as="div" color="gray" size="2">{message}</Text><Button mt="3" onClick={onRetry} variant="soft">{t("foundation.tryAgain")}</Button></div></Flex></Card>;
}

function errorMessage(value: unknown): string {
  return value instanceof Error ? value.message : "Request failed";
}
