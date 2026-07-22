import {
  AlertDialog,
  Badge,
  Button,
  Callout,
  Checkbox,
  Dialog,
  Spinner,
} from "@radix-ui/themes";
import {
  Activity,
  History,
  KeyRound,
  RotateCw,
  ShieldAlert,
  Trash2,
} from "lucide-react";
import { useState } from "react";

import type { DeveloperAccessBundleDestroyPlan } from "../../../shared/developerAccess";
import type { DeveloperProjectSnapshot } from "../../../shared/developerProject";
import {
  destroyAccessBundle,
  inspectAccessBundle,
  planAccessBundleDestroy,
  rollbackAccessBundle,
  rotateAccessBundleProjectionSecret,
  type AccessBundleDestroyUpdate,
  type AccessBundleMutationUpdate,
} from "../../developerAccessApi";
import { useI18n } from "../../i18n/I18nProvider";

export function DeveloperAccessBundleOperations({
  authorizationReady,
  snapshot,
  onDestroyed,
  onMutation,
}: {
  authorizationReady: boolean;
  snapshot: DeveloperProjectSnapshot;
  onDestroyed: (update: AccessBundleDestroyUpdate) => Promise<void>;
  onMutation: (update: AccessBundleMutationUpdate) => Promise<void>;
}): JSX.Element {
  const { t } = useI18n();
  const bundle = snapshot.verifiedBundle ?? null;
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [inspectOutcome, setInspectOutcome] = useState<"ready" | "partial" | "unavailable" | null>(null);
  const [resourceStates, setResourceStates] = useState<Record<string, string>>({});
  const [resourceMessages, setResourceMessages] = useState<Record<string, string>>({});
  const [rotationOpen, setRotationOpen] = useState(false);
  const [rollbackOpen, setRollbackOpen] = useState(false);
  const [destroyPlan, setDestroyPlan] = useState<DeveloperAccessBundleDestroyPlan | null>(null);
  const [confirmCommerce, setConfirmCommerce] = useState(false);

  const run = async (name: string, action: () => Promise<void>) => {
    if (busy) return;
    setBusy(name);
    setError(null);
    try {
      await action();
    } catch (cause) {
      setError(cause instanceof Error && cause.message.trim()
        ? cause.message
        : t("developer.release.lifecycle.error"));
    } finally {
      setBusy(null);
    }
  };

  const inspect = () => run("inspect", async () => {
    const receipt = await inspectAccessBundle();
    setInspectOutcome(receipt.outcome);
    setResourceStates(Object.fromEntries(Object.entries(receipt.resources).map(([id, resource]) => [
      id,
      resource.observation?.reachability ?? resource.errorCode ?? "unavailable",
    ])));
    setResourceMessages(Object.fromEntries(Object.entries(receipt.resources).flatMap(([id, resource]) => (
      resource.safeMessage ? [[id, resource.safeMessage]] : []
    ))));
  });

  const rotate = () => run("rotate", async () => {
    const update = await rotateAccessBundleProjectionSecret();
    setRotationOpen(false);
    setInspectOutcome(null);
    await onMutation(update);
    if (update.mutation.outcome !== "succeeded") {
      setError(t("developer.release.bundleLifecycle.outcome", { value: update.mutation.outcome }));
    }
  });

  const rollback = () => run("rollback", async () => {
    if (!bundle?.rollbackTarget) {
      throw new Error(t("developer.release.bundleLifecycle.noRollbackTarget"));
    }
    const update = await rollbackAccessBundle({
      gatewayVersionId: bundle.rollbackTarget.gatewayVersionId,
      entitlementVersionId: bundle.rollbackTarget.entitlementVersionId,
    });
    setRollbackOpen(false);
    setInspectOutcome(null);
    await onMutation(update);
    if (update.mutation.outcome !== "succeeded") {
      setError(t("developer.release.bundleLifecycle.outcome", { value: update.mutation.outcome }));
    }
  });

  const createDestroyPlan = () => run("destroy-plan", async () => {
    const plan = await planAccessBundleDestroy();
    setConfirmCommerce(!plan.commerceDataLossRequiresConfirmation);
    setDestroyPlan(plan);
  });

  const destroy = () => run("destroy", async () => {
    if (!destroyPlan) throw new Error(t("developer.release.lifecycle.destroyPlanRequired"));
    if (destroyPlan.commerceDataLossRequiresConfirmation && !confirmCommerce) {
      throw new Error(t("developer.release.bundleLifecycle.commerceConfirmationRequired"));
    }
    const update = await destroyAccessBundle(destroyPlan.planHash, confirmCommerce);
    if (update.destroy.outcome === "succeeded") {
      setDestroyPlan(null);
      setInspectOutcome(null);
      await onDestroyed(update);
    } else {
      setError(t("developer.release.bundleLifecycle.outcome", { value: update.destroy.outcome }));
    }
  });

  return (
    <section className="release-lifecycle release-bundle-lifecycle" aria-labelledby="release-bundle-lifecycle-title">
      <header className="release-lifecycle-heading">
        <span><Activity aria-hidden="true" size={20} /></span>
        <div>
          <h3 id="release-bundle-lifecycle-title">{t("developer.release.bundleLifecycle.title")}</h3>
          <p>{t("developer.release.bundleLifecycle.description")}</p>
        </div>
        <Badge color={bundle ? "green" : "gray"}>
          {bundle ? t("developer.release.lifecycle.managed") : t("developer.release.lifecycle.notDeployed")}
        </Badge>
      </header>

      {error ? (
        <Callout.Root color="red" role="alert">
          <ShieldAlert aria-hidden="true" size={16} />
          <Callout.Text>{error}</Callout.Text>
        </Callout.Root>
      ) : null}

      <div className="release-bundle-workers">
        <WorkerFact
          label={t("developer.release.bundleLifecycle.gateway")}
          name={bundle?.gateway.target.workerName}
          message={resourceMessages["model-gateway"]}
          state={resourceStates["model-gateway"]}
          version={bundle?.gateway.versionId}
        />
        <WorkerFact
          label={t("developer.release.bundleLifecycle.entitlement")}
          name={bundle?.entitlementPolicy.target.workerName}
          message={resourceMessages["entitlement-policy"]}
          state={resourceStates["entitlement-policy"]}
          version={bundle?.entitlementPolicy.versionId}
        />
        <div className="release-bundle-inspect">
          <Badge color={inspectOutcome === "ready" ? "green" : inspectOutcome ? "orange" : "gray"}>
            {inspectOutcome ?? t("developer.release.lifecycle.unchecked")}
          </Badge>
          <Button
            disabled={!authorizationReady || !bundle || busy !== null}
            onClick={inspect}
            variant="soft"
          >
            {busy === "inspect" ? <Spinner /> : <RotateCw aria-hidden="true" size={15} />}
            {t("developer.release.lifecycle.inspect")}
          </Button>
        </div>
      </div>

      <div className="release-lifecycle-sections">
        <div className="release-lifecycle-group">
          <div>
            <strong>{t("developer.release.lifecycle.maintenance")}</strong>
            <small>{t("developer.release.bundleLifecycle.maintenanceHint")}</small>
          </div>
          <div className="release-lifecycle-actions">
            <Button disabled={!authorizationReady || !bundle || busy !== null} onClick={() => setRotationOpen(true)} variant="soft">
              <KeyRound aria-hidden="true" size={15} /> {t("developer.release.lifecycle.rotate")}
            </Button>
            <Button disabled={!authorizationReady || !bundle?.rollbackTarget || busy !== null} onClick={() => setRollbackOpen(true)} variant="soft">
              <History aria-hidden="true" size={15} /> {t("developer.release.lifecycle.rollback")}
            </Button>
          </div>
        </div>
        <div className="release-lifecycle-group is-danger">
          <div>
            <strong>{t("developer.release.lifecycle.danger")}</strong>
            <small>{t("developer.release.bundleLifecycle.dangerHint")}</small>
          </div>
          <Button color="red" disabled={!authorizationReady || !bundle || busy !== null} onClick={createDestroyPlan} variant="soft">
            {busy === "destroy-plan" ? <Spinner /> : <Trash2 aria-hidden="true" size={15} />}
            {t("developer.release.lifecycle.destroy")}
          </Button>
        </div>
      </div>

      <Dialog.Root onOpenChange={setRotationOpen} open={rotationOpen}>
        <Dialog.Content maxWidth="500px">
          <Dialog.Title>{t("developer.release.bundleLifecycle.rotateTitle")}</Dialog.Title>
          <Dialog.Description>{t("developer.release.bundleLifecycle.rotateDescription")}</Dialog.Description>
          <div className="release-dialog-actions">
            <Button color="gray" onClick={() => setRotationOpen(false)} variant="soft">{t("common.cancel")}</Button>
            <Button disabled={busy !== null} onClick={rotate}>
              {busy === "rotate" ? <Spinner /> : null}{t("developer.release.lifecycle.rotateConfirm")}
            </Button>
          </div>
        </Dialog.Content>
      </Dialog.Root>

      <AlertDialog.Root onOpenChange={setRollbackOpen} open={rollbackOpen}>
        <AlertDialog.Content maxWidth="520px">
          <AlertDialog.Title>{t("developer.release.bundleLifecycle.rollbackTitle")}</AlertDialog.Title>
          <AlertDialog.Description>{t("developer.release.bundleLifecycle.rollbackDescription")}</AlertDialog.Description>
          <dl className="release-rollback-target">
            <div><dt>{t("developer.release.bundleLifecycle.gateway")}</dt><dd><code>{bundle?.rollbackTarget?.gatewayVersionId ?? "—"}</code></dd></div>
            <div><dt>{t("developer.release.bundleLifecycle.entitlement")}</dt><dd><code>{bundle?.rollbackTarget?.entitlementVersionId ?? "—"}</code></dd></div>
          </dl>
          <div className="release-dialog-actions">
            <AlertDialog.Cancel><Button color="gray" variant="soft">{t("common.cancel")}</Button></AlertDialog.Cancel>
            <Button color="orange" disabled={!bundle?.rollbackTarget || busy !== null} onClick={rollback}>
              {busy === "rollback" ? <Spinner /> : null}{t("developer.release.lifecycle.rollbackConfirm")}
            </Button>
          </div>
        </AlertDialog.Content>
      </AlertDialog.Root>

      <AlertDialog.Root onOpenChange={(open) => { if (!open) setDestroyPlan(null); }} open={destroyPlan !== null}>
        <AlertDialog.Content maxWidth="560px">
          <AlertDialog.Title>{t("developer.release.bundleLifecycle.destroyTitle")}</AlertDialog.Title>
          <AlertDialog.Description>{t("developer.release.bundleLifecycle.destroyDescription")}</AlertDialog.Description>
          <ul className="release-destroy-resources">
            {destroyPlan?.resources.flatMap((resource) => resource.resources.map((item) => (
              <li key={`${resource.resourceId}:${item}`}><code>{item}</code></li>
            )))}
          </ul>
          {destroyPlan?.commerceDataLossRequiresConfirmation ? (
            <label className="release-commerce-destroy-confirmation">
              <Checkbox checked={confirmCommerce} onCheckedChange={(checked) => setConfirmCommerce(checked === true)} />
              <span>{t("developer.release.bundleLifecycle.commerceConfirmation")}</span>
            </label>
          ) : null}
          <div className="release-dialog-actions">
            <AlertDialog.Cancel><Button color="gray" variant="soft">{t("common.cancel")}</Button></AlertDialog.Cancel>
            <Button color="red" disabled={busy !== null || (destroyPlan?.commerceDataLossRequiresConfirmation && !confirmCommerce)} onClick={destroy}>
              {busy === "destroy" ? <Spinner /> : null}{t("developer.release.lifecycle.destroyConfirm")}
            </Button>
          </div>
        </AlertDialog.Content>
      </AlertDialog.Root>
    </section>
  );
}

function WorkerFact({ label, message, name, state, version }: {
  label: string;
  message?: string;
  name?: string;
  state?: string;
  version?: string;
}) {
  return (
    <div className="release-bundle-worker">
      <small>{label}</small>
      <strong>{name ?? "—"}</strong>
      <code>{version ?? "—"}</code>
      <Badge color={state === "reachable" ? "green" : state ? "orange" : "gray"}>{state ?? "—"}</Badge>
      {message ? <p className="release-bundle-worker-message">{message}</p> : null}
    </div>
  );
}
