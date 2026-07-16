import * as Dialog from "@radix-ui/react-dialog";
import { Badge, Button, Card, Flex, Heading, Text } from "@radix-ui/themes";
import { Check, LoaderCircle, MailCheck, ShieldAlert, X, XCircle } from "lucide-react";
import { useEffect, useMemo, useState } from "react";

import {
  PendingFoundationAction,
  listFoundationActions,
  resolveFoundationAction
} from "../api";
import { useI18n } from "../i18n/I18nProvider";
import { FoundationHeader } from "./Accounts";

type FoundationActionsProps = { onBack: () => void };
type Translate = ReturnType<typeof useI18n>["t"];

export function FoundationActions({ onBack }: FoundationActionsProps): JSX.Element {
  const { t } = useI18n();
  const [actions, setActions] = useState<PendingFoundationAction[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [detailOpen, setDetailOpen] = useState(false);
  const [loading, setLoading] = useState(true);
  const [resolving, setResolving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const selected = useMemo(
    () => actions.find((item) => item.approval.approval_id === selectedId) ?? null,
    [actions, selectedId]
  );

  const load = async () => {
    setLoading(true);
    setError(null);
    try {
      const next = await listFoundationActions();
      setActions(next);
      setSelectedId((current) =>
        next.some((item) => item.approval.approval_id === current)
          ? current
          : next[0]?.approval.approval_id ?? null
      );
    } catch (reason) {
      setError(errorMessage(reason));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void load();
  }, []);

  const resolve = async (decision: "approve_once" | "reject") => {
    if (!selected) return;
    setResolving(true);
    setError(null);
    try {
      const result = await resolveFoundationAction(
        selected.approval.approval_id,
        decision
      );
      setActions((current) =>
        current.map((item) =>
          item.approval.approval_id === selected.approval.approval_id
            ? { ...item, approval: result.approval, action: result.action }
            : item
        )
      );
      setDetailOpen(false);
    } catch (reason) {
      setError(errorMessage(reason));
    } finally {
      setResolving(false);
    }
  };

  const select = (item: PendingFoundationAction) => {
    setSelectedId(item.approval.approval_id);
    setDetailOpen(true);
  };

  return (
    <main className="foundation-screen" aria-label={t("foundation.actions.title")}>
      <FoundationHeader
        eyebrow={t("foundation.actions.eyebrow")}
        onBack={onBack}
        subtitle={t("foundation.actions.subtitle")}
        title={t("foundation.actions.title")}
      />
      {error ? (
        <div className="memory-error" role="alert">
          <ShieldAlert size={16} /> {error}
        </div>
      ) : null}
      <div className="foundation-page-shell actions-layout">
        <section className="foundation-list-column" aria-label={t("foundation.actions.approvals")}>
          <div className="foundation-column-heading">
            <Text color="gray" size="1" weight="bold">{t("foundation.actions.ledger")}</Text>
            <Badge color="gray" radius="full">{actions.length}</Badge>
          </div>
          {loading ? (
            <Flex align="center" gap="2" p="4">
              <LoaderCircle className="spin" size={16} />
              <Text color="gray" size="2">{t("foundation.actions.loading")}</Text>
            </Flex>
          ) : null}
          {!loading && !error && actions.length === 0 ? (
            <Card className="foundation-empty">
              <Flex align="center" direction="column" gap="2">
                <MailCheck size={22} />
                <Text weight="bold">{t("foundation.actions.emptyTitle")}</Text>
                <Text align="center" color="gray" size="2">
                  {t("foundation.actions.emptyDescription")}
                </Text>
              </Flex>
            </Card>
          ) : null}
          {actions.map((item) => (
            <button
              aria-pressed={selectedId === item.approval.approval_id}
              className="action-list-item memory-list-item"
              key={item.approval.approval_id}
              onClick={() => select(item)}
              type="button"
            >
              <span className="memory-kind">{actionStatusLabel(item, t)}</span>
              <strong>{item.preview?.subject || item.approval.binding.action_name}</strong>
              <small>{item.approval.binding.resource_target}</small>
            </button>
          ))}
        </section>
        <section className="foundation-detail-column actions-detail" aria-live="polite">
          {selected ? (
            <ActionDetail
              item={selected}
              onApprove={() => void resolve("approve_once")}
              onReject={() => void resolve("reject")}
              resolving={resolving}
            />
          ) : null}
        </section>
      </div>
      <Dialog.Root onOpenChange={setDetailOpen} open={detailOpen}>
        <Dialog.Portal>
          <Dialog.Overlay className="foundation-dialog-overlay actions-mobile-detail" />
          <Dialog.Content className="foundation-dialog-content actions-mobile-detail memory-mobile-detail-content">
            <Dialog.Title className="sr-only">{t("foundation.actions.details")}</Dialog.Title>
            <Dialog.Close asChild>
              <button
                aria-label={t("foundation.actions.closeDetails")}
                className="dialog-close mobile-detail-close"
                type="button"
              >
                <X size={16} />
              </button>
            </Dialog.Close>
            {selected ? (
              <ActionDetail
                item={selected}
                onApprove={() => void resolve("approve_once")}
                onReject={() => void resolve("reject")}
                resolving={resolving}
              />
            ) : null}
          </Dialog.Content>
        </Dialog.Portal>
      </Dialog.Root>
    </main>
  );
}

function ActionDetail({
  item,
  onApprove,
  onReject,
  resolving
}: {
  item: PendingFoundationAction;
  onApprove: () => void;
  onReject: () => void;
  resolving: boolean;
}): JSX.Element {
  const { t } = useI18n();
  const preview = item.preview;
  const pending = item.approval.status === "pending" && item.action.status === "waiting_approval";
  return (
    <Card className="foundation-detail-card action-detail-card" size="4">
      <Flex align="start" justify="between" gap="4" wrap="wrap">
        <div>
          <Text className="foundation-kicker" size="1" weight="bold">{t("foundation.actions.mailSend")}</Text>
          <Heading as="h2" mt="2" size="6">{preview?.subject || t("foundation.actions.externalAction")}</Heading>
        </div>
        <Badge color={pending ? "amber" : statusColor(item.action.status)} radius="full">
          {actionStatusLabel(item, t)}
        </Badge>
      </Flex>
      <div className="foundation-rule" />
      <Text className="action-risk-summary" size="2">
        <ShieldAlert aria-hidden="true" size={16} />
        {item.approval.binding.risk_summary}
      </Text>
      {preview ? (
        <dl className="mail-preview-grid">
          <PreviewFact label={t("foundation.actions.account")} value={preview.accountId} />
          <PreviewFact label={t("foundation.actions.from")} value={formatAddress(preview.from)} />
          <PreviewFact label={t("foundation.actions.to")} value={formatAddresses(preview.to)} />
          <PreviewFact label={t("foundation.actions.ccBcc")} value={formatAddresses([...preview.cc, ...preview.bcc]) || t("foundation.actions.none")} />
          <PreviewFact label={t("foundation.actions.draftRevision")} value={`v${preview.draftRevision}`} />
          <PreviewFact label={t("foundation.actions.attachments")} value={String(preview.attachments.length)} />
        </dl>
      ) : null}
      <section className="action-hashes">
        <Text size="2" weight="bold">{t("foundation.actions.immutableBinding")}</Text>
        <HashFact label={t("foundation.actions.arguments")} value={item.action.arguments_sha256} />
        {preview ? <HashFact label={t("foundation.actions.preview")} value={preview.previewHash} /> : null}
      </section>
      {item.action.last_error ? (
        <Text className="action-error-detail" color="red" size="2">
          {item.action.last_error}
        </Text>
      ) : null}
      {pending ? (
        <div className="action-decision-row">
          <Button disabled={resolving} onClick={onReject} variant="soft">
            <XCircle size={15} /> {t("foundation.actions.reject")}
          </Button>
          <Button disabled={resolving} onClick={onApprove}>
            <Check size={15} /> {resolving ? t("foundation.actions.applying") : t("foundation.actions.approveOnce")}
          </Button>
        </div>
      ) : (
        <Text className="action-terminal-note" color="gray" size="2">
          {t("foundation.actions.terminalNote")}
        </Text>
      )}
    </Card>
  );
}

function PreviewFact({ label, value }: { label: string; value: string }): JSX.Element {
  return <div><dt>{label}</dt><dd>{value}</dd></div>;
}

function HashFact({ label, value }: { label: string; value: string }): JSX.Element {
  return <div><span>{label}</span><code>{value}</code></div>;
}

function formatAddress(address: { name?: string | null; address: string }): string {
  return address.name ? `${address.name} <${address.address}>` : address.address;
}

function formatAddresses(addresses: Array<{ name?: string | null; address: string }>): string {
  return addresses.map(formatAddress).join(", ");
}

function actionStatusLabel(item: PendingFoundationAction, t: Translate): string {
  if (item.approval.status === "pending") return t("foundation.actions.status.awaitingApproval");
  const key = `foundation.actions.status.${item.action.status}`;
  const localized = t(key);
  return localized === key ? item.action.status.replaceAll("_", " ") : localized;
}

function statusColor(status: string): "gray" | "green" | "red" | "amber" {
  if (status === "succeeded") return "green";
  if (status === "uncertain") return "amber";
  if (status === "failed" || status === "cancelled") return "red";
  return "gray";
}

function errorMessage(value: unknown): string {
  return value instanceof Error ? value.message : "Foundation action request failed";
}
