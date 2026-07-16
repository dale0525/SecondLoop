import * as Tabs from "@radix-ui/react-tabs";
import { ArrowLeft, Bot, Boxes, PackageCheck, RefreshCw, ShieldCheck } from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";

import {
  deleteDevSkill,
  type DevSkillInventory,
  type DevSkillPackage,
  listDevSkills,
  reloadDevSkills,
  validateDevSkills,
} from "../api";
import { AppIconButton } from "../components/AppIconButton";
import { DeleteSkillDialog } from "../components/developer/DeleteSkillDialog";
import { DeveloperBuildPanel } from "../components/developer/DeveloperBuildPanel";
import {
  SkillEditorDialog,
  type SkillEditorSaveResult,
} from "../components/developer/SkillEditorDialog";
import { SkillPackageDetail } from "../components/developer/SkillPackageDetail";
import { SkillPackageList } from "../components/developer/SkillPackageList";
import { SettingsModel } from "../components/SettingsModel";
import { useHostBootstrap } from "../hostBootstrap";
import { useI18n } from "../i18n/I18nProvider";

export type DevApiProbeStatus = "available" | "loading" | "unavailable";

type DeveloperToolsProps = {
  initialInventory?: DevSkillInventory | null;
  initialStatus?: DevApiProbeStatus;
  onBack: () => void;
  onInventoryChange?: (inventory: DevSkillInventory) => void;
};

type DeveloperTab = "model" | "skills" | "build";

export function DeveloperTools({
  initialInventory = null,
  initialStatus,
  onBack,
  onInventoryChange,
}: DeveloperToolsProps): JSX.Element {
  const { t } = useI18n();
  const bootstrap = useHostBootstrap();
  const actionFailureMessage = t("developer.actionFailed");
  const [activeTab, setActiveTab] = useState<DeveloperTab>("skills");
  const [inventory, setInventory] = useState<DevSkillInventory | null>(initialInventory);
  const [selectedId, setSelectedId] = useState<string | null>(initialInventory?.packages?.[0]?.id ?? null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(initialStatus !== "available");
  const [activeSnapshotGeneration, setActiveSnapshotGeneration] = useState<number | null>(null);
  const [editorTarget, setEditorTarget] = useState<DevSkillPackage | "new" | null>(null);
  const [deletePackage, setDeletePackage] = useState<DevSkillPackage | null>(null);
  const inventoryRef = useRef<DevSkillInventory | null>(initialInventory);
  const operationSequenceRef = useRef(0);
  const operationInFlightRef = useRef(false);

  useEffect(() => {
    inventoryRef.current = inventory;
  }, [inventory]);

  const selectedPackage = useMemo(
    () => inventory?.packages.find((item) => item.id === selectedId) ?? inventory?.packages[0] ?? null,
    [inventory, selectedId],
  );

  const beginOperation = useCallback(() => {
    if (operationInFlightRef.current) return null;
    operationInFlightRef.current = true;
    const operationId = ++operationSequenceRef.current;
    setIsLoading(true);
    setActionError(null);
    return operationId;
  }, []);

  const finishOperation = useCallback((operationId: number) => {
    if (operationId !== operationSequenceRef.current) return;
    operationInFlightRef.current = false;
    setIsLoading(false);
  }, []);

  const adoptInventory = useCallback((nextInventory: DevSkillInventory) => {
    setInventory(nextInventory);
    onInventoryChange?.(nextInventory);
    setLoadError(null);
    setSelectedId((current) => {
      if (current && nextInventory.packages.some((item) => item.id === current)) return current;
      return nextInventory.packages[0]?.id ?? null;
    });
  }, [onInventoryChange]);

  const loadInventory = useCallback(async (
    loader: () => Promise<DevSkillInventory> = listDevSkills,
    options?: { failureMessage?: string; preserveInventoryOnError?: boolean },
  ) => {
    const operationId = beginOperation();
    if (operationId === null) return;
    if (!options?.preserveInventoryOnError) setLoadError(null);
    try {
      const nextInventory = await loader();
      if (operationId !== operationSequenceRef.current) return;
      adoptInventory(nextInventory);
    } catch {
      if (operationId !== operationSequenceRef.current) return;
      if (options?.preserveInventoryOnError && inventoryRef.current) {
        setActionError(options.failureMessage ?? actionFailureMessage);
        return;
      }
      setInventory(null);
      setSelectedId(null);
      setLoadError(t("developer.apiUnavailable"));
    } finally {
      finishOperation(operationId);
    }
  }, [actionFailureMessage, adoptInventory, beginOperation, finishOperation, t]);

  useEffect(() => {
    if (initialStatus === undefined) {
      void loadInventory();
      return;
    }
    if (initialStatus === "loading") {
      setIsLoading(true);
      return;
    }
    setIsLoading(false);
    if (initialStatus === "unavailable") {
      setInventory(null);
      setSelectedId(null);
      setLoadError(t("developer.apiUnavailable"));
      return;
    }
    if (initialInventory && !inventoryRef.current) adoptInventory(initialInventory);
  }, [adoptInventory, initialInventory, initialStatus, loadInventory, t]);

  const handleDelete = useCallback(async (skillPackage: DevSkillPackage) => {
    const operationId = beginOperation();
    if (operationId === null) return;
    try {
      const nextInventory = await deleteDevSkill(skillPackage.id);
      if (operationId !== operationSequenceRef.current) return;
      adoptInventory(nextInventory);
      setDeletePackage(null);
    } catch {
      if (operationId !== operationSequenceRef.current) return;
      setActionError(actionFailureMessage);
      setDeletePackage(null);
    } finally {
      finishOperation(operationId);
    }
  }, [actionFailureMessage, adoptInventory, beginOperation, finishOperation]);

  const handleReload = useCallback(async () => {
    const operationId = beginOperation();
    if (operationId === null) return;
    try {
      const response = await reloadDevSkills();
      if (operationId !== operationSequenceRef.current) return;
      adoptInventory(response.inventory);
      setActiveSnapshotGeneration(response.activeGeneration);
    } catch {
      if (operationId !== operationSequenceRef.current) return;
      setActionError(actionFailureMessage);
    } finally {
      finishOperation(operationId);
    }
  }, [actionFailureMessage, adoptInventory, beginOperation, finishOperation]);

  const handleEditorSaved = useCallback((result: SkillEditorSaveResult) => {
    adoptInventory(result.inventory);
    setSelectedId(result.directory);
    if (result.activeGeneration !== null) setActiveSnapshotGeneration(result.activeGeneration);
    setActionError(result.reloadFailed ? t("developer.editor.reloadFailed") : null);
  }, [adoptInventory, t]);

  const appId = bootstrap.discovery?.identity.appId ?? "app.local";

  return (
    <main className="developer-screen" aria-label={t("developer.ariaLabel")}>
      <header className="top-bar developer-top-bar">
        <AppIconButton label={t("common.backToSettings")} onClick={onBack}>
          <ArrowLeft aria-hidden="true" size={18} />
        </AppIconButton>
        <div className="top-bar-title">
          <h1>{t("developer.title")}</h1>
          <p>{loadError ? t("developer.apiDisconnected") : t("developer.apiConnected")}</p>
        </div>
        {activeTab === "skills" ? (
          <div className="developer-top-bar-actions">
            <AppIconButton
              disabled={isLoading}
              label={t("developer.refresh")}
              onClick={() => void loadInventory(listDevSkills, {
                failureMessage: actionFailureMessage,
                preserveInventoryOnError: inventory !== null,
              })}
            >
              <RefreshCw aria-hidden="true" size={18} />
            </AppIconButton>
            <AppIconButton
              disabled={isLoading}
              label={t("developer.validateAll")}
              onClick={() => void loadInventory(validateDevSkills, {
                failureMessage: actionFailureMessage,
                preserveInventoryOnError: true,
              })}
            >
              <ShieldCheck aria-hidden="true" size={18} />
            </AppIconButton>
          </div>
        ) : <span className="top-bar-spacer" aria-hidden="true" />}
      </header>

      <Tabs.Root
        className="developer-tabs"
        onValueChange={(value) => setActiveTab(value as DeveloperTab)}
        value={activeTab}
      >
        <Tabs.List aria-label={t("developer.tabsLabel")} className="developer-tab-list">
          <Tabs.Trigger className="developer-tab" value="model">
            <Bot aria-hidden="true" size={17} /> {t("developer.tabModel")}
          </Tabs.Trigger>
          <Tabs.Trigger className="developer-tab" value="skills">
            <Boxes aria-hidden="true" size={17} /> {t("developer.tabSkills")}
          </Tabs.Trigger>
          <Tabs.Trigger className="developer-tab" value="build">
            <PackageCheck aria-hidden="true" size={17} /> {t("developer.tabBuild")}
          </Tabs.Trigger>
        </Tabs.List>

        <Tabs.Content className="developer-tab-content developer-model-content" value="model">
          <SettingsModel />
        </Tabs.Content>

        <Tabs.Content className="developer-tab-content developer-skills-content" value="skills">
          {actionError || activeSnapshotGeneration !== null ? (
            <div
              aria-live="polite"
              className={`developer-status-banner${actionError ? " developer-status-banner-error" : ""}`}
              role="status"
            >
              {activeSnapshotGeneration !== null
                ? <span>{t("developer.activeSnapshot", { generation: activeSnapshotGeneration })}</span>
                : null}
              {actionError ? <span>{actionError}</span> : null}
            </div>
          ) : null}

          <section className="developer-workbench" aria-busy={isLoading}>
            {loadError ? (
              <div className="developer-empty-state">
                <h2>{t("developer.apiUnavailable")}</h2>
                <p>{t("developer.apiUnavailableHint")}</p>
              </div>
            ) : (
              <>
                <SkillPackageList
                  inventory={inventory}
                  onCreate={() => setEditorTarget("new")}
                  onSelect={setSelectedId}
                  selectedId={selectedPackage?.id ?? null}
                />
                <SkillPackageDetail
                  inventory={inventory}
                  isBusy={isLoading}
                  onDelete={setDeletePackage}
                  onModify={setEditorTarget}
                  onReload={() => void handleReload()}
                  skillPackage={selectedPackage}
                />
              </>
            )}
          </section>
        </Tabs.Content>

        <Tabs.Content className="developer-tab-content developer-build-content" value="build">
          <DeveloperBuildPanel inventory={inventory} />
        </Tabs.Content>
      </Tabs.Root>

      <SkillEditorDialog
        appId={appId}
        onOpenChange={(open) => {
          if (!open) setEditorTarget(null);
        }}
        onSaved={handleEditorSaved}
        target={editorTarget}
      />
      <DeleteSkillDialog
        disabled={isLoading}
        onConfirm={handleDelete}
        onOpenChange={(open) => {
          if (!open) setDeletePackage(null);
        }}
        skillPackage={deletePackage}
      />
    </main>
  );
}
