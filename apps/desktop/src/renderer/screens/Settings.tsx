import { ArrowLeft, ShieldCheck } from "lucide-react";

import { AppIconButton } from "../components/AppIconButton";
import { SettingsAppearance } from "../components/SettingsAppearance";
import { SettingsDeveloperTools } from "../components/SettingsDeveloperTools";
import { SettingsModel } from "../components/SettingsModel";
import { SettingsFoundation } from "../components/SettingsFoundation";
import { SettingsHostBootstrap } from "../components/SettingsHostBootstrap";
import { SettingsIdentity } from "../components/SettingsIdentity";
import { SettingsBilling } from "../components/SettingsBilling";
import { useHostBootstrap } from "../hostBootstrap";
import { SettingsLanguage } from "../components/SettingsLanguage";
import { useI18n } from "../i18n/I18nProvider";
import { OwnerPolicy, canInspectOwnerSkills } from "../ownerBridge";

type SettingsProps = {
  developerToolsAvailable: boolean;
  onBack: () => void;
  onOpenDeveloperTools: () => void;
  onOpenOwnerSkills: () => void;
  onOpenAccounts: () => void;
  onOpenMemory: () => void;
  onOpenActions: () => void;
  ownerPolicy: OwnerPolicy | null;
};

export function Settings({
  developerToolsAvailable,
  onBack,
  onOpenDeveloperTools,
  onOpenOwnerSkills,
  onOpenAccounts,
  onOpenMemory,
  onOpenActions,
  ownerPolicy
}: SettingsProps): JSX.Element {
  const { t } = useI18n();
  const bootstrap = useHostBootstrap();
  const userCanConfigureModel = bootstrap.status === "unavailable"
    || bootstrap.discovery?.access.modelAccess.configurationPolicy === "user_configurable";
  return (
    <main className="settings-screen" aria-label={t("settings.title")}>
      <header className="top-bar settings-top-bar">
        <AppIconButton label={t("common.backToChat")} onClick={onBack}>
          <ArrowLeft size={18} aria-hidden="true" />
        </AppIconButton>
        <div className="top-bar-title">
          <h1>{t("settings.title")}</h1>
        </div>
        <span className="top-bar-spacer" aria-hidden="true" />
      </header>
      <div className="settings-shell">
        <SettingsHostBootstrap />
        {bootstrap.discovery?.access.identity.mode === "required" ? <SettingsIdentity /> : null}
        <SettingsBilling />
        <SettingsAppearance />
        <SettingsLanguage />
        <SettingsFoundation
          features={bootstrap.features}
          onOpenAccounts={onOpenAccounts}
          onOpenActions={onOpenActions}
          onOpenMemory={onOpenMemory}
        />
        {userCanConfigureModel ? <SettingsModel /> : null}
        {bootstrap.features.skillManagement && canInspectOwnerSkills(ownerPolicy) ? (
          <section className="settings-panel" aria-labelledby="settings-owner-title">
            <div className="settings-panel-heading">
              <h2 id="settings-owner-title">{t("settings.ownerSkills")}</h2>
              <p>{t("settings.ownerSkillsDescription")}</p>
            </div>
            <button
              className="settings-primary-action settings-developer-action"
              onClick={onOpenOwnerSkills}
              type="button"
            >
              <ShieldCheck aria-hidden="true" size={16} /> {t("settings.manageSkills")}
            </button>
          </section>
        ) : null}
        <SettingsDeveloperTools
          enabled={developerToolsAvailable}
          onOpenDeveloperTools={onOpenDeveloperTools}
        />
      </div>
    </main>
  );
}
