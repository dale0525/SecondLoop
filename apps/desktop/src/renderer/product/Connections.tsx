import { Badge, Button, Card, Flex, Heading, Text } from "@radix-ui/themes";
import { Bot, CalendarDays, CheckCircle2, CircleAlert, ContactRound, LoaderCircle, Mail } from "lucide-react";
import { useEffect, useState } from "react";

import { getMailAccountStatus, listMailAccounts } from "../api";
import { SettingsModel } from "../components/SettingsModel";
import { useI18n } from "../i18n/I18nProvider";
import { loadModelSettings } from "../modelSettings";
import { Accounts } from "../screens/Accounts";
import { MailAccountOnboarding } from "./MailAccountOnboarding";
import { WorkspaceOAuthPanel } from "./WorkspaceOAuthPanel";
import { loadWorkspaceAccountId } from "../workspaceBindings";
import { listFoundationCalendarEvents, resolveFoundationContacts } from "../workspaceApi";

type Readiness = "checking" | "error" | "missing" | "ready";

export function Connections(): JSX.Element {
  const { t } = useI18n();
  const [model, setModel] = useState<Readiness>("checking");
  const [mail, setMail] = useState<Readiness>("checking");
  const [calendar, setCalendar] = useState<Readiness>("checking");
  const [contacts, setContacts] = useState<Readiness>("checking");
  const [mailRevision, setMailRevision] = useState(0);

  useEffect(() => {
    let active = true;
    void loadModelSettings()
      .then((snapshot) => {
        if (active) setModel(snapshot.saved || snapshot.apiKeyConfigured ? "ready" : "missing");
      })
      .catch(() => {
        if (active) setModel("error");
      });
    return () => {
      active = false;
    };
  }, []);

  useEffect(() => {
    let active = true;
    setMail("checking");
    setCalendar("checking");
    setContacts("checking");
    void listMailAccounts()
      .then(async (accounts) => {
        const fallbackAccountId = accounts[0]?.id ?? null;
        const calendarAccountId = loadWorkspaceAccountId("agentweave-calendar") ?? fallbackAccountId;
        const contactsAccountId = loadWorkspaceAccountId("agentweave-contacts") ?? fallbackAccountId;
        const start = new Date();
        const end = new Date(start.getTime() + 24 * 60 * 60 * 1_000);
        const [mailState, calendarState, contactsState] = await Promise.all([
          accounts.length === 0
            ? Promise.resolve("missing" as const)
            : Promise.all(accounts.map((account) => getMailAccountStatus(account.id)))
              .then((statuses) => statuses.some((status) => status.state === "connected")
                ? "ready" as const
                : "missing" as const),
          calendarAccountId
            ? listFoundationCalendarEvents(calendarAccountId, start.toISOString(), end.toISOString())
              .then(() => "ready" as const)
              .catch(() => "error" as const)
            : Promise.resolve("missing" as const),
          contactsAccountId
            ? resolveFoundationContacts(contactsAccountId, "*", 1)
              .then(() => "ready" as const)
              .catch(() => "error" as const)
            : Promise.resolve("missing" as const),
        ]);
        return { calendarState, contactsState, mailState };
      })
      .then((state) => {
        if (!active) return;
        setMail(state.mailState);
        setCalendar(state.calendarState);
        setContacts(state.contactsState);
      })
      .catch(() => {
        if (!active) return;
        setMail("error");
        setCalendar("error");
        setContacts("error");
      });
    return () => {
      active = false;
    };
  }, [mailRevision]);

  return (
    <main className="connections-screen" aria-label={t("nav.connections")}>
      <header className="product-page-header">
        <Text className="foundation-kicker" size="1" weight="bold">{t("connections.eyebrow")}</Text>
        <Heading as="h1">{t("nav.connections")}</Heading>
        <Text color="gray" size="2">{t("connections.subtitle")}</Text>
      </header>
      <div className="connections-readiness" aria-label={t("connections.readiness")}>
        <ReadinessCard
          icon={<Bot aria-hidden="true" size={19} />}
          onOpen={() => scrollToConnection("secondloop-model-connection")}
          state={model}
          type="model"
        />
        <ReadinessCard
          icon={<Mail aria-hidden="true" size={19} />}
          onOpen={() => scrollToConnection("secondloop-mail-connection")}
          state={mail}
          type="mail"
        />
        <ReadinessCard
          icon={<CalendarDays aria-hidden="true" size={19} />}
          onOpen={() => scrollToConnection("secondloop-workspace-oauth")}
          state={calendar}
          type="calendar"
        />
        <ReadinessCard
          icon={<ContactRound aria-hidden="true" size={19} />}
          onOpen={() => scrollToConnection("secondloop-workspace-oauth")}
          state={contacts}
          type="contacts"
        />
      </div>
      <WorkspaceOAuthPanel onBindingsChanged={() => setMailRevision((revision) => revision + 1)} />
      <div className="connections-model" id="secondloop-model-connection"><SettingsModel /></div>
      <div className="connections-mail" id="secondloop-mail-connection">
        <MailAccountOnboarding onChanged={() => setMailRevision((revision) => revision + 1)} />
        <Accounts embedded key={mailRevision} onBack={() => undefined} />
      </div>
    </main>
  );
}

function ReadinessCard({
  icon,
  onOpen,
  state,
  type,
}: {
  icon: React.ReactNode;
  onOpen: () => void;
  state: Readiness;
  type: "calendar" | "contacts" | "mail" | "model";
}): JSX.Element {
  const { t } = useI18n();
  const title = t(`connections.${type}Title`);
  const stateLabel = t(`connections.state.${state}`);
  return (
    <Card className="connections-readiness-card" size="3">
      <Flex align="start" gap="3" justify="between">
        <Flex align="center" gap="3">
          <span className="connections-readiness-icon">{icon}</span>
          <div>
            <Text as="div" weight="bold">{title}</Text>
            <Text as="div" color="gray" size="2">
              {t(`connections.${type}.${state}Hint`)}
            </Text>
          </div>
        </Flex>
        <Badge
          color={state === "ready" ? "green" : state === "error" ? "red" : "amber"}
          radius="full"
          variant="soft"
        >
          {state === "checking" ? <LoaderCircle aria-hidden="true" className="spin" size={12} /> : null}
          {state === "ready" ? <CheckCircle2 aria-hidden="true" size={12} /> : null}
          {state === "error" ? <CircleAlert aria-hidden="true" size={12} /> : null}
          {stateLabel}
        </Badge>
      </Flex>
      {state !== "ready" && state !== "checking" ? (
        <Button mt="4" onClick={onOpen} variant="soft">
          {t(`connections.${type}NextStep`)}
        </Button>
      ) : null}
    </Card>
  );
}

function scrollToConnection(id: string): void {
  document.getElementById(id)?.scrollIntoView({ behavior: "smooth", block: "start" });
}
