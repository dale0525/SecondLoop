import { Wrench } from "lucide-react";
import { useEffect, useState } from "react";

import { listDevSkills } from "../api";
import { useI18n } from "../i18n/I18nProvider";

type SettingsDeveloperToolsProps = {
  enabled: boolean;
  onOpenDeveloperTools: () => void;
};

export function SettingsDeveloperTools({
  enabled,
  onOpenDeveloperTools
}: SettingsDeveloperToolsProps): JSX.Element | null {
  const { t } = useI18n();
  const [isAvailable, setIsAvailable] = useState(false);

  useEffect(() => {
    let active = true;

    if (!enabled) {
      setIsAvailable(false);
      return () => {
        active = false;
      };
    }

    listDevSkills()
      .then(() => {
        if (active) {
          setIsAvailable(true);
        }
      })
      .catch(() => {
        if (active) {
          setIsAvailable(false);
        }
      });

    return () => {
      active = false;
    };
  }, [enabled]);

  if (!isAvailable) {
    return null;
  }

  return (
    <section className="settings-panel" aria-labelledby="settings-developer-title">
      <div className="settings-panel-heading">
        <h2 id="settings-developer-title">{t("settings.developerTools")}</h2>
        <p>{t("settings.developerToolsDescription")}</p>
      </div>
      <button
        className="settings-primary-action settings-developer-action"
        onClick={onOpenDeveloperTools}
        type="button"
      >
        <Wrench aria-hidden="true" size={16} /> {t("settings.openDeveloperTools")}
      </button>
    </section>
  );
}
