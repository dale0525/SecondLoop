import * as Dialog from "@radix-ui/react-dialog";
import { AlertTriangle, Check, LoaderCircle, Save, X } from "lucide-react";
import { useEffect, useMemo, useState } from "react";

import {
  createDevSkill,
  type DevSkillInventory,
  type DevSkillPackage,
  type DevSkillSource,
  readDevSkill,
  reloadDevSkills,
  updateDevSkill,
} from "../../api";
import {
  type DevSkillDraftIssue,
  type DevSkillEditorDraft,
  draftFromDevSkillSource,
  emptyDevSkillDraft,
  prepareDevSkillSource,
  suggestedDirectory,
  suggestedPackageId,
  validateDevSkillDraft,
} from "../../devSkillEditorModel";
import { useI18n } from "../../i18n/I18nProvider";
import { AppIconButton } from "../AppIconButton";

export type SkillEditorSaveResult = {
  activeGeneration: number | null;
  directory: string;
  inventory: DevSkillInventory;
  reloadFailed: boolean;
};

type SkillEditorDialogProps = {
  appId: string;
  onOpenChange: (open: boolean) => void;
  onSaved: (result: SkillEditorSaveResult) => void;
  target: DevSkillPackage | "new" | null;
};

const issueKeys: Record<DevSkillDraftIssue, string> = {
  description: "developer.editor.issueDescription",
  directory: "developer.editor.issueDirectory",
  displayName: "developer.editor.issueDisplayName",
  hostRequirements: "developer.editor.issueHostRequirements",
  instructions: "developer.editor.issueInstructions",
  packageId: "developer.editor.issuePackageId",
  skillName: "developer.editor.issueSkillName",
};

export function SkillEditorDialog({
  appId,
  onOpenChange,
  onSaved,
  target,
}: SkillEditorDialogProps): JSX.Element {
  const { t } = useI18n();
  const [draft, setDraft] = useState<DevSkillEditorDraft>(() => emptyDevSkillDraft(appId));
  const [source, setSource] = useState<DevSkillSource | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [dirty, setDirty] = useState(false);
  const [loadError, setLoadError] = useState(false);
  const [saveError, setSaveError] = useState<"conflict" | "failed" | null>(null);
  const [showIssues, setShowIssues] = useState(false);
  const open = target !== null;
  const editing = target !== null && target !== "new";
  const issues = useMemo(() => validateDevSkillDraft(draft), [draft]);

  useEffect(() => {
    let active = true;
    setLoadError(false);
    setSaveError(null);
    setShowIssues(false);
    setDirty(false);
    if (target === null) return () => { active = false; };
    if (target === "new") {
      setSource(null);
      setDraft(emptyDevSkillDraft(appId));
      setIsLoading(false);
      return () => { active = false; };
    }

    setSource(null);
    setIsLoading(true);
    void readDevSkill(target.path)
      .then((nextSource) => {
        if (!active) return;
        setSource(nextSource);
        setDraft(draftFromDevSkillSource(nextSource));
      })
      .catch(() => {
        if (active) setLoadError(true);
      })
      .finally(() => {
        if (active) setIsLoading(false);
      });
    return () => { active = false; };
  }, [appId, target]);

  const update = <Key extends keyof DevSkillEditorDraft>(
    key: Key,
    value: DevSkillEditorDraft[Key],
  ) => {
    setDraft((current) => ({ ...current, [key]: value }));
    setDirty(true);
    setSaveError(null);
  };

  const updateDisplayName = (displayName: string) => {
    setDraft((current) => {
      if (editing) return { ...current, displayName };
      const previousSuggestion = suggestedDirectory(current.displayName);
      const directory = !current.directory || current.directory === previousSuggestion
        ? suggestedDirectory(displayName)
        : current.directory;
      const packageId = current.packageId === suggestedPackageId(appId, current.directory)
        || current.packageId === suggestedPackageId(appId, "skill")
        ? suggestedPackageId(appId, directory)
        : current.packageId;
      const skillName = !current.skillName || current.skillName === current.directory
        ? directory
        : current.skillName;
      return { ...current, directory, displayName, packageId, skillName };
    });
    setDirty(true);
    setSaveError(null);
  };

  const updateDirectory = (directory: string) => {
    setDraft((current) => {
      const packageId = current.packageId === suggestedPackageId(appId, current.directory)
        ? suggestedPackageId(appId, directory)
        : current.packageId;
      const skillName = !current.skillName || current.skillName === current.directory
        ? directory
        : current.skillName;
      return { ...current, directory, packageId, skillName };
    });
    setDirty(true);
    setSaveError(null);
  };

  const save = async () => {
    setShowIssues(true);
    setSaveError(null);
    if (issues.length > 0 || (editing && !source)) return;
    setIsSaving(true);
    try {
      const prepared = prepareDevSkillSource(draft, source ?? undefined);
      const mutation = editing && source
        ? await updateDevSkill(target.path, {
          expectedRevision: source.sourceRevision,
          manifest: prepared.manifest,
          skillMd: prepared.skillMd,
        })
        : await createDevSkill({
          directory: prepared.directory,
          manifest: prepared.manifest,
          skillMd: prepared.skillMd,
        });
      let inventory = mutation.inventory;
      let activeGeneration: number | null = null;
      let reloadFailed = false;
      try {
        const reloaded = await reloadDevSkills();
        inventory = reloaded.inventory;
        activeGeneration = reloaded.activeGeneration;
      } catch {
        reloadFailed = true;
      }
      onSaved({ activeGeneration, directory: prepared.directory, inventory, reloadFailed });
      onOpenChange(false);
    } catch (error) {
      const message = error instanceof Error ? error.message.toLowerCase() : "";
      setSaveError(message.includes("conflict") || message.includes("409") ? "conflict" : "failed");
    } finally {
      setIsSaving(false);
    }
  };

  return (
    <Dialog.Root open={open} onOpenChange={(nextOpen) => {
      if (!isSaving) onOpenChange(nextOpen);
    }}>
      <Dialog.Portal>
        <Dialog.Overlay className="developer-dialog-overlay" />
        <Dialog.Content
          aria-label={editing ? t("developer.editor.editTitle") : t("developer.editor.createTitle")}
          className="developer-dialog-content developer-editor-dialog"
        >
          <header className="developer-dialog-header">
            <div>
              <Dialog.Title>
                {editing ? t("developer.editor.editTitle") : t("developer.editor.createTitle")}
              </Dialog.Title>
              <Dialog.Description>
                {editing ? t("developer.editor.editDescription") : t("developer.editor.createDescription")}
              </Dialog.Description>
            </div>
            <AppIconButton
              disabled={isSaving}
              label={t("developer.editor.close")}
              onClick={() => onOpenChange(false)}
            >
              <X aria-hidden="true" size={16} />
            </AppIconButton>
          </header>

          <div className="developer-dialog-body developer-editor-body">
            {isLoading ? (
              <div className="developer-editor-state" role="status">
                <LoaderCircle aria-hidden="true" className="spin" size={20} />
                <span>{t("developer.editor.loading")}</span>
              </div>
            ) : loadError ? (
              <div className="developer-editor-state developer-editor-state-error" role="alert">
                <AlertTriangle aria-hidden="true" size={20} />
                <span>{t("developer.editor.loadFailed")}</span>
              </div>
            ) : (
              <form className="developer-editor-form" onSubmit={(event) => {
                event.preventDefault();
                void save();
              }}>
                <div className="developer-editor-grid">
                  <label className="settings-field developer-editor-field-wide">
                    <span>{t("developer.editor.displayName")}</span>
                    <input
                      autoFocus
                      disabled={isSaving}
                      onChange={(event) => updateDisplayName(event.target.value)}
                      placeholder={t("developer.editor.displayNamePlaceholder")}
                      value={draft.displayName}
                    />
                  </label>
                  <label className="settings-field">
                    <span>{t("developer.editor.directory")}</span>
                    <input
                      disabled={editing || isSaving}
                      onChange={(event) => updateDirectory(event.target.value)}
                      placeholder="daily-briefing"
                      value={draft.directory}
                    />
                  </label>
                  <label className="settings-field">
                    <span>{t("developer.editor.packageId")}</span>
                    <input
                      disabled={isSaving}
                      onChange={(event) => update("packageId", event.target.value)}
                      placeholder="com.example.app.daily-briefing"
                      value={draft.packageId}
                    />
                  </label>
                  <label className="settings-field">
                    <span>{t("developer.editor.skillName")}</span>
                    <input
                      disabled={isSaving}
                      onChange={(event) => update("skillName", event.target.value)}
                      placeholder="daily-briefing"
                      value={draft.skillName}
                    />
                  </label>
                  <label className="settings-field">
                    <span>{t("developer.editor.kind")}</span>
                    <select
                      disabled={isSaving}
                      onChange={(event) => update("kind", event.target.value as DevSkillEditorDraft["kind"])}
                      value={draft.kind}
                    >
                      <option value="instruction_only">{t("developer.editor.kindInstruction")}</option>
                      <option value="host_tools_only">{t("developer.editor.kindHostTools")}</option>
                    </select>
                  </label>
                  <label className="settings-field developer-editor-field-wide">
                    <span>{t("developer.editor.description")}</span>
                    <input
                      disabled={isSaving}
                      onChange={(event) => update("description", event.target.value)}
                      placeholder={t("developer.editor.descriptionPlaceholder")}
                      value={draft.description}
                    />
                  </label>
                  {draft.kind === "host_tools_only" ? (
                    <>
                      <label className="settings-field">
                        <span>{t("developer.editor.runtimeTools")}</span>
                        <textarea
                          disabled={isSaving}
                          onChange={(event) => update("requiredRuntimeTools", event.target.value)}
                          placeholder="schedule_create\nnotification_enqueue"
                          rows={4}
                          value={draft.requiredRuntimeTools}
                        />
                      </label>
                      <label className="settings-field">
                        <span>{t("developer.editor.connectors")}</span>
                        <textarea
                          disabled={isSaving}
                          onChange={(event) => update("requiredConnectors", event.target.value)}
                          placeholder="agentweave-calendar"
                          rows={4}
                          value={draft.requiredConnectors}
                        />
                      </label>
                    </>
                  ) : null}
                  <label className="settings-field developer-editor-field-wide">
                    <span>{t("developer.editor.instructions")}</span>
                    <textarea
                      className="developer-editor-instructions"
                      disabled={isSaving}
                      onChange={(event) => update("instructions", event.target.value)}
                      placeholder={t("developer.editor.instructionsPlaceholder")}
                      rows={12}
                      value={draft.instructions}
                    />
                  </label>
                </div>
              </form>
            )}

            {showIssues && issues.length > 0 ? (
              <div className="developer-editor-validation" role="alert">
                <strong>{t("developer.editor.checkFields")}</strong>
                <ul>
                  {issues.map((issue) => <li key={issue}>{t(issueKeys[issue])}</li>)}
                </ul>
              </div>
            ) : null}
            {saveError ? (
              <div className="developer-editor-validation" role="alert">
                <strong>{t(saveError === "conflict"
                  ? "developer.editor.conflict"
                  : "developer.editor.saveFailed")}</strong>
              </div>
            ) : null}
          </div>

          <footer className="developer-dialog-footer">
            <span className="developer-editor-dirty" role="status">
              {dirty ? t("developer.editor.unsaved") : editing && source ? (
                <><Check aria-hidden="true" size={14} /> {t("developer.editor.loaded")}</>
              ) : null}
            </span>
            <button
              className="developer-primary-button"
              disabled={isLoading || loadError || isSaving}
              onClick={() => void save()}
              type="button"
            >
              {isSaving
                ? <LoaderCircle aria-hidden="true" className="spin" size={16} />
                : <Save aria-hidden="true" size={16} />}
              <span>{isSaving ? t("developer.editor.saving") : t("developer.editor.saveReload")}</span>
            </button>
          </footer>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
