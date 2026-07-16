import { CheckCircle2, PackageCheck, Terminal, TriangleAlert } from "lucide-react";

import type { DevSkillInventory } from "../../api";
import { useHostBootstrap } from "../../hostBootstrap";
import { useI18n } from "../../i18n/I18nProvider";

export function DeveloperBuildPanel({
  inventory,
}: {
  inventory: DevSkillInventory | null;
}): JSX.Element {
  const { t } = useI18n();
  const bootstrap = useHostBootstrap();
  const identity = bootstrap.discovery?.identity;
  const packages = inventory?.packages ?? [];
  const issues = packages.filter((item) => !item.releaseReady);
  const appRoot = inventory?.root.replace(/[\\/]packages[\\/]?$/, "") ?? "—";

  return (
    <section className="developer-build-panel" aria-labelledby="developer-build-title">
      <header className="developer-tool-panel-heading">
        <span className="developer-tool-panel-icon"><PackageCheck aria-hidden="true" size={20} /></span>
        <div>
          <h2 id="developer-build-title">{t("developer.build.title")}</h2>
          <p>{t("developer.build.description")}</p>
        </div>
      </header>

      <div className="developer-build-grid">
        <BuildFact label={t("developer.build.appName")} value={identity?.displayName ?? "—"} />
        <BuildFact label={t("developer.build.appId")} value={identity?.appId ?? "—"} />
        <BuildFact label={t("developer.build.version")} value={identity?.version ?? "—"} />
        <BuildFact label={t("developer.build.appRoot")} value={appRoot} wide />
      </div>

      <div className={`developer-build-status${issues.length > 0 ? " developer-build-status-warning" : ""}`}>
        {issues.length > 0
          ? <TriangleAlert aria-hidden="true" size={20} />
          : <CheckCircle2 aria-hidden="true" size={20} />}
        <div>
          <strong>{issues.length > 0
            ? t("developer.build.needsAttention")
            : t("developer.build.ready")}</strong>
          <p>{issues.length > 0
            ? t("developer.build.issueCount", { count: issues.length })
            : t("developer.build.readyHint", { count: packages.length })}</p>
        </div>
      </div>

      <section className="developer-build-command">
        <div>
          <Terminal aria-hidden="true" size={18} />
          <div>
            <h3>{t("developer.build.command")}</h3>
            <p>{t("developer.build.commandHint")}</p>
          </div>
        </div>
        <code>pixi run app-package</code>
      </section>
    </section>
  );
}

function BuildFact({
  label,
  value,
  wide = false,
}: {
  label: string;
  value: string;
  wide?: boolean;
}): JSX.Element {
  return (
    <div className={`developer-build-fact${wide ? " developer-build-fact-wide" : ""}`}>
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  );
}
