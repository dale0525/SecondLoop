import { Badge, Card, Flex, Heading, Text } from "@radix-ui/themes";
import { CalendarDays, CircleAlert, LoaderCircle, Mail, ShieldCheck } from "lucide-react";
import { useEffect, useMemo, useState } from "react";

import {
  type PendingFoundationAction,
  listFoundationActions,
  listMailAccounts,
} from "../api";
import { useHostBootstrap } from "../hostBootstrap";
import { useI18n } from "../i18n/I18nProvider";

export function Today(): JSX.Element {
  const { t } = useI18n();
  const bootstrap = useHostBootstrap();
  const [actions, setActions] = useState<PendingFoundationAction[]>([]);
  const [mailConnected, setMailConnected] = useState(false);
  const [loading, setLoading] = useState(true);
  const [sourceError, setSourceError] = useState(false);

  const load = async () => {
    setLoading(true);
    setSourceError(false);
    const results = await Promise.allSettled([
      bootstrap.features.actions ? listFoundationActions() : Promise.resolve([]),
      bootstrap.features.accounts ? listMailAccounts() : Promise.resolve([]),
    ]);
    const actionResult = results[0];
    const mailResult = results[1];
    if (actionResult.status === "fulfilled") setActions(actionResult.value);
    if (mailResult.status === "fulfilled") setMailConnected(mailResult.value.length > 0);
    if (results.every((result) => result.status === "rejected")) {
      setSourceError(true);
    }
    setLoading(false);
  };

  useEffect(() => { void load(); }, [bootstrap.features.accounts, bootstrap.features.actions]);

  const pending = useMemo(
    () => actions.filter((item) => item.approval.status === "pending"),
    [actions],
  );
  const date = new Intl.DateTimeFormat(undefined, {
    day: "numeric",
    month: "long",
    weekday: "long",
  }).format(new Date());

  return (
    <main className="today-screen" aria-label={t("today.title")}>
      <header className="today-header">
        <div>
          <Text className="today-date" size="1" weight="bold">{date}</Text>
          <Heading as="h1">{t("today.title")}</Heading>
          <Text color="gray" size="2">{t("today.subtitle")}</Text>
        </div>
        <div className="today-source-state">
          <span className={mailConnected ? "ready" : "missing"} />
          <Text size="2">{mailConnected ? t("today.sourceReady") : t("today.sourceMissing")}</Text>
        </div>
      </header>
      {sourceError ? (
        <button className="today-error" onClick={() => void load()} type="button">
          <CircleAlert size={17} /> <span>{t("today.sourcesUnavailable")} {t("today.retry")}.</span>
        </button>
      ) : null}
      <div className="today-grid">
        <section className="today-main-column">
          <TodaySection icon={<CalendarDays size={17} />} title={t("today.focus")}>
            {loading ? <LoadingRows /> : <EmptyState text={mailConnected ? t("today.noItems") : t("today.noSources")} />}
          </TodaySection>
          <TodaySection icon={<Mail size={17} />} title={t("today.replies")}>
            <EmptyState text={mailConnected ? t("today.noItems") : t("today.noSources")} />
          </TodaySection>
        </section>
        <aside className="today-side-column">
          <TodaySection count={pending.length} icon={<ShieldCheck size={17} />} title={t("today.approvals")}>
            {loading ? <LoadingRows compact /> : pending.length > 0 ? pending.map((item) => (
              <article className="today-action-row" key={item.approval.approval_id}>
                <span><strong>{item.preview?.subject || item.approval.binding.action_name}</strong><small>{item.approval.binding.resource_target}</small></span>
                <Badge color="amber" radius="full">{t("today.pending")}</Badge>
              </article>
            )) : <EmptyState text={t("today.noItems")} />}
          </TodaySection>
          <TodaySection icon={<span className="today-commitment-mark">✓</span>} title={t("today.commitments")}>
            <EmptyState text={t("today.noItems")} />
          </TodaySection>
        </aside>
      </div>
    </main>
  );
}

function TodaySection({
  children,
  count,
  icon,
  title,
}: {
  children: React.ReactNode;
  count?: number;
  icon: React.ReactNode;
  title: string;
}): JSX.Element {
  return (
    <Card className="today-card" size="3">
      <Flex align="center" className="today-card-heading" gap="2">
        <span className="today-card-icon">{icon}</span>
        <Heading as="h2" size="3">{title}</Heading>
        {count !== undefined ? <Badge color="gray" ml="auto" radius="full">{count}</Badge> : null}
      </Flex>
      <div className="today-card-body">{children}</div>
    </Card>
  );
}

function LoadingRows({ compact = false }: { compact?: boolean }): JSX.Element {
  const { t } = useI18n();
  return (
    <div className="today-loading" role="status">
      <LoaderCircle className="spin" size={16} />
      <span>{compact ? t("today.checkingApprovals") : t("today.checkingSources")}</span>
    </div>
  );
}

function EmptyState({ text }: { text: string }): JSX.Element {
  return <p className="today-empty">{text}</p>;
}
