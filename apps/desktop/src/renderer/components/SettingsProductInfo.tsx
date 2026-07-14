import { Badge, Flex, Text } from "@radix-ui/themes";
import { Bell, CheckCircle2, Info, LockKeyhole } from "lucide-react";

import { useHostBootstrap } from "../hostBootstrap";
import { useI18n } from "../i18n/I18nProvider";

export function SettingsNotifications(): JSX.Element {
  const { t } = useI18n();
  const bootstrap = useHostBootstrap();
  const enabled = bootstrap.discovery?.requirements.capabilities.includes("scheduler")
    && bootstrap.discovery.requirements.runtimeTools.includes("notification_enqueue")
    && bootstrap.discovery.policy.backgroundExecution !== "disabled";

  return (
    <section className="settings-panel" aria-labelledby="settings-notifications-title">
      <div className="settings-panel-heading">
        <h2 id="settings-notifications-title">{t("settings.notifications.title")}</h2>
        <p>{t("settings.notifications.description")}</p>
      </div>
      <Flex align="center" className="settings-info-row" gap="3" justify="between" wrap="wrap">
        <Flex align="center" gap="3">
          <span className="settings-info-icon"><Bell aria-hidden="true" size={18} /></span>
          <div>
            <Text as="div" weight="bold">{t("settings.notifications.local")}</Text>
            <Text as="div" color="gray" size="2">{t("settings.notifications.localHint")}</Text>
          </div>
        </Flex>
        <Badge color={enabled ? "green" : "gray"} radius="full" variant="soft">
          {enabled ? t("settings.notifications.enabled") : t("settings.notifications.unavailable")}
        </Badge>
      </Flex>
      <Flex align="center" className="settings-info-row" gap="3">
        <span className="settings-info-icon"><LockKeyhole aria-hidden="true" size={18} /></span>
        <Text color="gray" size="2">{t("settings.notifications.approvalNote")}</Text>
      </Flex>
    </section>
  );
}

export function SettingsAbout(): JSX.Element {
  const { t } = useI18n();
  const bootstrap = useHostBootstrap();
  const identity = bootstrap.discovery?.identity;

  return (
    <section className="settings-panel" aria-labelledby="settings-about-title">
      <div className="settings-panel-heading">
        <h2 id="settings-about-title">{t("settings.about.title")}</h2>
        <p>{t("settings.about.description")}</p>
      </div>
      <div className="settings-about-grid">
        <AboutFact icon={<Info size={17} />} label={t("settings.about.version")} value={identity?.version ?? "—"} />
        <AboutFact icon={<CheckCircle2 size={17} />} label={t("settings.about.runtime")} value={bootstrap.discovery?.runtimeVersion ?? "—"} />
        <AboutFact icon={<LockKeyhole size={17} />} label={t("settings.about.license")} value="Apache-2.0 OR MIT" />
      </div>
      <Text color="gray" size="2">{t("settings.about.localFirst")}</Text>
    </section>
  );
}

function AboutFact({
  icon,
  label,
  value,
}: {
  icon: React.ReactNode;
  label: string;
  value: string;
}): JSX.Element {
  return (
    <div className="settings-about-fact">
      <span aria-hidden="true">{icon}</span>
      <div>
        <Text as="div" color="gray" size="1">{label}</Text>
        <Text as="div" weight="bold">{value}</Text>
      </div>
    </div>
  );
}
