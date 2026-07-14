import { Button, Card, Flex, Text } from "@radix-ui/themes";
import { Brain, ChevronRight, Mail, ShieldCheck } from "lucide-react";
import { useI18n } from "../i18n/I18nProvider";

type SettingsFoundationProps = {
  features: {
    accounts: boolean;
    actions: boolean;
    memory: boolean;
  };
  onOpenAccounts: () => void;
  onOpenMemory: () => void;
  onOpenActions: () => void;
};

export function SettingsFoundation({
  features,
  onOpenAccounts,
  onOpenActions,
  onOpenMemory
}: SettingsFoundationProps): JSX.Element | null {
  const { t } = useI18n();
  if (!features.accounts && !features.actions && !features.memory) {
    return null;
  }
  return (
    <section className="settings-panel foundation-settings-panel" aria-labelledby="foundation-title">
      <div className="settings-panel-heading">
        <p className="foundation-kicker">{t("foundation.kicker")}</p>
        <h2 id="foundation-title">{t("foundation.accountsAndData")}</h2>
        <p>{t("foundation.description")}</p>
      </div>
      <Flex direction={{ initial: "column", sm: "row" }} gap="3">
        {features.accounts ? <Card className="foundation-entry-card" size="2">
          <Flex align="center" gap="3">
            <span className="foundation-entry-icon" aria-hidden="true"><Mail size={18} /></span>
            <Flex direction="column" gap="1" style={{ flex: 1 }}>
              <Text weight="bold">{t("foundation.mailAccounts")}</Text>
              <Text color="gray" size="2">{t("foundation.mailAccountsDescription")}</Text>
            </Flex>
            <Button aria-label={t("foundation.openNamed", { name: t("foundation.mailAccounts") })} onClick={onOpenAccounts} variant="ghost">
              {t("foundation.open")} <ChevronRight aria-hidden="true" size={15} />
            </Button>
          </Flex>
        </Card> : null}
        {features.actions ? <Card className="foundation-entry-card" size="2">
          <Flex align="center" gap="3">
            <span className="foundation-entry-icon approval" aria-hidden="true"><ShieldCheck size={18} /></span>
            <Flex direction="column" gap="1" style={{ flex: 1 }}>
              <Text weight="bold">{t("foundation.pendingActions")}</Text>
              <Text color="gray" size="2">{t("foundation.pendingActionsDescription")}</Text>
            </Flex>
            <Button aria-label={t("foundation.openNamed", { name: t("foundation.pendingActions") })} onClick={onOpenActions} variant="ghost">
              {t("foundation.open")} <ChevronRight aria-hidden="true" size={15} />
            </Button>
          </Flex>
        </Card> : null}
        {features.memory ? <Card className="foundation-entry-card" size="2">
          <Flex align="center" gap="3">
            <span className="foundation-entry-icon memory" aria-hidden="true"><Brain size={18} /></span>
            <Flex direction="column" gap="1" style={{ flex: 1 }}>
              <Text weight="bold">{t("foundation.memoryLedger")}</Text>
              <Text color="gray" size="2">{t("foundation.memoryLedgerDescription")}</Text>
            </Flex>
            <Button aria-label={t("foundation.openNamed", { name: t("foundation.memoryLedger") })} onClick={onOpenMemory} variant="ghost">
              {t("foundation.open")} <ChevronRight aria-hidden="true" size={15} />
            </Button>
          </Flex>
        </Card> : null}
      </Flex>
    </section>
  );
}
