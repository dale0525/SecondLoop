import { Copy, Pencil, RefreshCw, Sparkles, Trash2 } from "lucide-react";
import { useState } from "react";

import { DevSkillInventory, DevSkillPackage, DevSkillPackageKind } from "../../api";
import { buildModifySkillPrompt } from "../../devSkillPrompts";
import {
  packageHasBlockingDiagnostics,
  packageValidationHeading
} from "./skillPackageDiagnostics";
import { useI18n } from "../../i18n/I18nProvider";

type SkillPackageDetailProps = {
  isBusy: boolean;
  inventory: DevSkillInventory | null;
  skillPackage: DevSkillPackage | null;
  onDelete: (skillPackage: DevSkillPackage) => void;
  onModify: (skillPackage: DevSkillPackage) => void;
  onReload: () => void;
};

const kindKey: Record<DevSkillPackageKind, string> = {
  combined: "developer.kindCombined",
  empty: "developer.kindEmpty",
  instruction: "developer.kindInstruction",
  invalid: "developer.kindInvalid",
  runtime: "developer.kindRuntime"
};

export function SkillPackageDetail({
  isBusy,
  inventory,
  skillPackage,
  onDelete,
  onModify,
  onReload
}: SkillPackageDetailProps): JSX.Element {
  const { t } = useI18n();
  const [copyState, setCopyState] = useState<"idle" | "copied" | "failed">("idle");
  const copyLabel = t(copyState === "copied" ? "common.copied" : copyState === "failed" ? "common.copyFailed" : "common.copyPrompt");

  if (!inventory || inventory.packages.length === 0 || !skillPackage) {
    return (
      <section className="developer-detail-pane">
        <div className="developer-empty-state developer-detail-empty-state">
          <h2>{t("developer.packageDetails")}</h2>
          <p>{t("developer.packageDetailsHint")}</p>
        </div>
      </section>
    );
  }

  const prompt = buildModifySkillPrompt(inventory.root, skillPackage);
  const diagnosticsCount =
    skillPackage.validation.errors.length + skillPackage.validation.warnings.length;
  const hasBlockingDiagnostics = packageHasBlockingDiagnostics(skillPackage);
  const validationHeading = packageValidationHeading(skillPackage, t);
  const editable = skillPackage.hasSkillMd
    && skillPackage.hasPackageMetadata
    && !skillPackage.hasRuntimeManifest
    && skillPackage.packageKind !== "invalid";

  const copyPrompt = async () => {
    try {
      if (navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(prompt);
        setCopyState("copied");
        window.setTimeout(() => setCopyState("idle"), 1200);
      }
    } catch {
      setCopyState("failed");
      window.setTimeout(() => setCopyState("idle"), 1200);
    }
  };

  return (
    <section className="developer-detail-pane">
      <div className="developer-detail-header">
        <div className="developer-detail-path">skills/{skillPackage.path}</div>
        <div className="developer-detail-title-row">
          <div className="developer-detail-title-copy">
            <h2>{skillPackage.name}</h2>
            <p>{skillPackage.description}</p>
          </div>
          <span className="developer-kind-badge">{t(kindKey[skillPackage.packageKind])}</span>
        </div>
      </div>

      <div className="developer-detail-grid">
        <section className="developer-detail-section">
          <header className="developer-section-heading">
            <h3>{t("developer.packageFiles")}</h3>
          </header>
          <div className="developer-file-list" role="list">
            <div className="developer-file-row" role="listitem">
              <span className="developer-file-name">skill.json</span>
              <span className="developer-file-state">
                {skillPackage.hasRuntimeManifest ? t("common.present") : t("common.missing")}
              </span>
            </div>
            <div className="developer-file-row" role="listitem">
              <span className="developer-file-name">SKILL.md</span>
              <span className="developer-file-state">
                {skillPackage.hasSkillMd ? t("common.present") : t("developer.skillMdMissing")}
              </span>
            </div>
          </div>
        </section>

        <section className="developer-detail-section">
          <header className="developer-section-heading">
            <h3>{t("developer.validation")}</h3>
          </header>
          <div
            className={`developer-validation-panel${
              hasBlockingDiagnostics ? "" : " developer-validation-panel-pass"
            }`}
          >
            <strong>{validationHeading}</strong>
            <p>
              {!hasBlockingDiagnostics
                ? t("developer.bundleReadiness", { state: t(skillPackage.bundleReady ? "developer.ready" : "developer.notReady") })
                : t("developer.diagnosticCount", { count: diagnosticsCount })}
            </p>
            {skillPackage.validation.errors.length > 0 ? (
              <ul className="developer-validation-list">
                {skillPackage.validation.errors.map((item) => (
                  <li key={item}>{item}</li>
                ))}
              </ul>
            ) : null}
            {skillPackage.validation.warnings.length > 0 ? (
              <ul className="developer-validation-list">
                {skillPackage.validation.warnings.map((item) => (
                  <li key={item}>{item}</li>
                ))}
              </ul>
            ) : null}
          </div>
        </section>

        <section className="developer-detail-section developer-detail-section-wide">
          <header className="developer-section-heading">
            <h3>{t("developer.exportedTools")}</h3>
          </header>
          {skillPackage.runtimeTools.length > 0 ? (
            <div className="developer-tool-list" role="list">
              {skillPackage.runtimeTools.map((toolName) => (
                <div className="developer-tool-row" key={toolName} role="listitem">
                  <span className="developer-tool-icon" aria-hidden="true">
                    <Sparkles size={16} />
                  </span>
                  <span className="developer-tool-copy">
                    <strong>{toolName}</strong>
                    <small>{t("developer.runtimeExport")}</small>
                  </span>
                </div>
              ))}
            </div>
          ) : (
            <div className="developer-inline-empty-state">
              <h3>{t("developer.noRuntimeTools")}</h3>
              <p>{t("developer.noRuntimeToolsHint")}</p>
            </div>
          )}
        </section>
      </div>

      <div className="developer-detail-actions">
        <button
          className="developer-primary-button"
          disabled={!editable || isBusy}
          onClick={() => onModify(skillPackage)}
          type="button"
        >
          <Pencil aria-hidden="true" size={16} />
          <span>{t(editable ? "developer.edit" : "developer.sourceReadOnly")}</span>
        </button>
        <button className="developer-secondary-button" onClick={() => void copyPrompt()} type="button">
          <Copy aria-hidden="true" size={16} />
          <span>{copyLabel}</span>
        </button>
        <button
          className="developer-secondary-button"
          disabled={isBusy}
          onClick={onReload}
          type="button"
        >
          <RefreshCw aria-hidden="true" size={16} />
          <span>{t("developer.reload")}</span>
        </button>
      </div>

      <section className="developer-danger-zone">
        <div>
          <h3>{t("developer.dangerZone")}</h3>
          <p>{t("developer.deleteWarning", { name: skillPackage.name })}</p>
        </div>
        <button
          className="developer-danger-button"
          disabled={!editable || isBusy}
          onClick={() => onDelete(skillPackage)}
          type="button"
        >
          <Trash2 aria-hidden="true" size={16} />
          <span>{t("developer.deletePackage")}</span>
        </button>
      </section>

      <aside className="developer-prompt-preview" aria-label={t("developer.promptPreview")}>
        <div className="developer-prompt-preview-header">
          <span>{t("developer.promptPreview")}</span>
        </div>
        <pre>{prompt}</pre>
      </aside>
    </section>
  );
}
