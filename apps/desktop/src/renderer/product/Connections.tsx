import { Heading, Text } from "@radix-ui/themes";

import { SettingsModel } from "../components/SettingsModel";
import { useI18n } from "../i18n/I18nProvider";
import { Accounts } from "../screens/Accounts";

export function Connections(): JSX.Element {
  const { t } = useI18n();
  return (
    <main className="connections-screen" aria-label={t("nav.connections")}>
      <header className="product-page-header">
        <Text className="foundation-kicker" size="1" weight="bold">{t("connections.eyebrow")}</Text>
        <Heading as="h1">{t("nav.connections")}</Heading>
        <Text color="gray" size="2">{t("connections.subtitle")}</Text>
      </header>
      <div className="connections-model"><SettingsModel /></div>
      <Accounts embedded onBack={() => undefined} />
    </main>
  );
}
