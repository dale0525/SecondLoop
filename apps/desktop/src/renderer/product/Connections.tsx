import { Badge, Button, Card, Flex, Heading, Text } from "@radix-ui/themes";
import { Bot, CheckCircle2, CircleAlert, LoaderCircle, Mail } from "lucide-react";
import { useEffect, useState } from "react";

import { getMailAccountStatus, listMailAccounts } from "../api";
import { SettingsModel } from "../components/SettingsModel";
import { useI18n } from "../i18n/I18nProvider";
import { loadModelSettings } from "../modelSettings";
import { Accounts } from "../screens/Accounts";

type Readiness = "checking" | "error" | "missing" | "ready";

export function Connections(): JSX.Element {
  const { t } = useI18n();
  const [model, setModel] = useState<Readiness>("checking");
  const [mail, setMail] = useState<Readiness>("checking");

  useEffect(() => {
    let active = true;
    void loadModelSettings()
      .then((snapshot) => {
        if (active) setModel(snapshot.saved || snapshot.apiKeyConfigured ? "ready" : "missing");
      })
      .catch(() => {
        if (active) setModel("error");
      });
    void listMailAccounts()
      .then(async (accounts) => {
        if (accounts.length === 0) return "missing" as const;
        const statuses = await Promise.all(
          accounts.map((account) => getMailAccountStatus(account.id)),
        );
        return statuses.some((status) => status.state === "connected")
          ? "ready" as const
          : "missing" as const;
      })
      .then((state) => {
        if (active) setMail(state);
      })
      .catch(() => {
        if (active) setMail("error");
      });
    return () => {
      active = false;
    };
  }, []);

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
      </div>
      <div className="connections-model" id="secondloop-model-connection"><SettingsModel /></div>
      <div className="connections-mail" id="secondloop-mail-connection">
        <Accounts embedded onBack={() => undefined} />
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
  type: "mail" | "model";
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
