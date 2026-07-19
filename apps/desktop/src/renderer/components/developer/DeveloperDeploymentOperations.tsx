import {
  AlertDialog,
  Badge,
  Button,
  Callout,
  Dialog,
  Select,
  Spinner,
  Text,
  TextField,
} from "@radix-ui/themes";
import {
  Activity,
  History,
  KeyRound,
  RotateCw,
  ShieldAlert,
  Trash2,
  Unplug,
} from "lucide-react";
import { useMemo, useState } from "react";

import type { DeveloperVerifiedDeployment } from "../../../shared/developerProject";
import {
  destroyGateway,
  disconnectCloudflare,
  inspectGateway,
  planGatewayDestroy,
  rollbackGateway,
  rotateGatewaySecret,
  type GatewayDestroyPlan,
  type GatewayDestroyUpdate,
  type GatewayMutationUpdate,
  type GatewayObservation,
} from "../../developerAccessApi";
import { useI18n } from "../../i18n/I18nProvider";

type LifecycleDeployment = DeveloperVerifiedDeployment;

export function DeveloperDeploymentOperations({
  authorizationReady,
  deployment,
  onDestroyed,
  onDisconnected,
  onMutation,
}: {
  authorizationReady: boolean;
  deployment: LifecycleDeployment | null;
  onDestroyed: (update: GatewayDestroyUpdate) => Promise<void>;
  onDisconnected: () => Promise<void>;
  onMutation: (update: GatewayMutationUpdate) => Promise<void>;
}): JSX.Element {
  const { t } = useI18n();
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [observation, setObservation] = useState<GatewayObservation | null>(null);
  const [rotationBinding, setRotationBinding] = useState("UPSTREAM_API_KEY");
  const [rotationValue, setRotationValue] = useState("");
  const [rotationOpen, setRotationOpen] = useState(false);
  const [restoreVersion, setRestoreVersion] = useState("");
  const [rollbackOpen, setRollbackOpen] = useState(false);
  const [destroyPlan, setDestroyPlan] = useState<GatewayDestroyPlan | null>(null);
  const [disconnectOpen, setDisconnectOpen] = useState(false);
  const drift = useMemo(() => deploymentDrift(deployment, observation), [deployment, observation]);

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
    if (!deployment) throw new Error(t("developer.release.lifecycle.noDeployment"));
    setObservation(await inspectGateway(deployment.target));
  });

  const rotate = () => run("rotate", async () => {
    if (!deployment || !rotationValue.trim()) {
      throw new Error(t("developer.release.lifecycle.rotationRequired"));
    }
    const update = await rotateGatewaySecret({
      target: deployment.target,
      bindingName: rotationBinding,
      value: rotationValue.trim(),
      ...(observation?.remoteVersion ? { expectedRemoteVersion: observation.remoteVersion } : {}),
      ...(observation?.remoteEtag ? { expectedRemoteEtag: observation.remoteEtag } : {}),
    });
    setRotationValue("");
    setRotationOpen(false);
    setObservation(null);
    await onMutation(update);
  });

  const rollback = () => run("rollback", async () => {
    if (!deployment || !restoreVersion.trim()) {
      throw new Error(t("developer.release.lifecycle.rollbackRequired"));
    }
    const update = await rollbackGateway({
      target: deployment.target,
      restoreVersion: restoreVersion.trim(),
      ...(observation?.remoteVersion ? { expectedRemoteVersion: observation.remoteVersion } : {}),
      ...(observation?.remoteEtag ? { expectedRemoteEtag: observation.remoteEtag } : {}),
    });
    setRestoreVersion("");
    setRollbackOpen(false);
    setObservation(null);
    await onMutation(update);
  });

  const createDestroyPlan = () => run("destroy-plan", async () => {
    if (!deployment) throw new Error(t("developer.release.lifecycle.noDeployment"));
    setDestroyPlan(await planGatewayDestroy({
      target: deployment.target,
      ...(observation?.remoteVersion ? { expectedRemoteVersion: observation.remoteVersion } : {}),
      ...(observation?.remoteEtag ? { expectedRemoteEtag: observation.remoteEtag } : {}),
    }));
  });

  const applyDestroy = () => run("destroy", async () => {
    if (!destroyPlan) throw new Error(t("developer.release.lifecycle.destroyPlanRequired"));
    const update = await destroyGateway(destroyPlan.planHash);
    setDestroyPlan(null);
    setObservation(null);
    await onDestroyed(update);
  });

  const disconnect = () => run("disconnect", async () => {
    await disconnectCloudflare();
    setDisconnectOpen(false);
    setObservation(null);
    await onDisconnected();
  });

  return (
    <section className="release-lifecycle" aria-labelledby="release-lifecycle-title">
      <header className="release-lifecycle-heading">
        <span><Activity aria-hidden="true" size={20} /></span>
        <div>
          <h3 id="release-lifecycle-title">{t("developer.release.lifecycle.title")}</h3>
          <p>{t("developer.release.lifecycle.description")}</p>
        </div>
        <Badge color={deployment ? "green" : "gray"}>
          {deployment
            ? t("developer.release.lifecycle.managed")
            : t("developer.release.lifecycle.notDeployed")}
        </Badge>
      </header>

      {error ? (
        <Callout.Root color="red" role="alert">
          <ShieldAlert aria-hidden="true" size={16} />
          <Callout.Text>{error}</Callout.Text>
        </Callout.Root>
      ) : null}

      <div className="release-lifecycle-status">
        <div>
          <small>{t("developer.release.lifecycle.target")}</small>
          <strong>{deployment?.target.workerName ?? "—"}</strong>
          <code>{deployment?.versionId ?? "—"}</code>
        </div>
        <div>
          <small>{t("developer.release.lifecycle.drift")}</small>
          <Badge color={drift === "in_sync" ? "green" : drift === "unchecked" ? "gray" : "orange"}>
            {t(`developer.release.lifecycle.${drift}`)}
          </Badge>
          <Text color="gray" size="1">
            {observation?.gatewayProtocolVersion
              ? t("developer.release.lifecycle.protocol", {
                  version: observation.gatewayProtocolVersion,
                })
              : t("developer.release.lifecycle.inspectHint")}
          </Text>
        </div>
        <Button
          disabled={!authorizationReady || !deployment || busy !== null}
          onClick={inspect}
          variant="soft"
        >
          {busy === "inspect" ? <Spinner /> : <RotateCw aria-hidden="true" size={15} />}
          {t("developer.release.lifecycle.inspect")}
        </Button>
      </div>

      <div className="release-lifecycle-sections">
        <div className="release-lifecycle-group">
          <div><strong>{t("developer.release.lifecycle.maintenance")}</strong><small>{t("developer.release.lifecycle.maintenanceHint")}</small></div>
          <div className="release-lifecycle-actions">
            <Button disabled={!authorizationReady || !deployment || busy !== null} onClick={() => setRotationOpen(true)} variant="soft">
              <KeyRound aria-hidden="true" size={15} /> {t("developer.release.lifecycle.rotate")}
            </Button>
            <Button disabled={!authorizationReady || !deployment || busy !== null} onClick={() => setRollbackOpen(true)} variant="soft">
              <History aria-hidden="true" size={15} /> {t("developer.release.lifecycle.rollback")}
            </Button>
          </div>
        </div>
        <div className="release-lifecycle-group is-danger">
          <div><strong>{t("developer.release.lifecycle.danger")}</strong><small>{t("developer.release.lifecycle.dangerHint")}</small></div>
          <div className="release-lifecycle-actions">
            <Button color="red" disabled={!authorizationReady || !deployment || busy !== null} onClick={createDestroyPlan} variant="soft">
              {busy === "destroy-plan" ? <Spinner /> : <Trash2 aria-hidden="true" size={15} />}
              {t("developer.release.lifecycle.destroy")}
            </Button>
            <Button color="gray" disabled={!authorizationReady || busy !== null} onClick={() => setDisconnectOpen(true)} variant="soft">
              <Unplug aria-hidden="true" size={15} /> {t("developer.release.lifecycle.disconnect")}
            </Button>
          </div>
        </div>
      </div>

      <Dialog.Root onOpenChange={setRotationOpen} open={rotationOpen}>
        <Dialog.Content maxWidth="480px">
          <Dialog.Title>{t("developer.release.lifecycle.rotateTitle")}</Dialog.Title>
          <Dialog.Description>{t("developer.release.lifecycle.rotateDescription")}</Dialog.Description>
          <label className="release-field">
            <Text size="2" weight="medium">{t("developer.release.lifecycle.binding")}</Text>
            <Select.Root onValueChange={setRotationBinding} value={rotationBinding}>
              <Select.Trigger />
              <Select.Content>
                <Select.Item value="UPSTREAM_API_KEY">UPSTREAM_API_KEY</Select.Item>
                <Select.Item value="ENTITLEMENT_PROJECTION_SECRET">ENTITLEMENT_PROJECTION_SECRET</Select.Item>
              </Select.Content>
            </Select.Root>
          </label>
          <label className="release-field">
            <Text size="2" weight="medium">{t("developer.release.lifecycle.newSecret")}</Text>
            <TextField.Root onChange={(event) => setRotationValue(event.target.value)} type="password" value={rotationValue} />
          </label>
          <div className="release-dialog-actions">
            <Button color="gray" onClick={() => setRotationOpen(false)} variant="soft">{t("common.cancel")}</Button>
            <Button disabled={!rotationValue.trim() || busy !== null} onClick={rotate}>
              {busy === "rotate" ? <Spinner /> : null}{t("developer.release.lifecycle.rotateConfirm")}
            </Button>
          </div>
        </Dialog.Content>
      </Dialog.Root>

      <AlertDialog.Root onOpenChange={setRollbackOpen} open={rollbackOpen}>
        <AlertDialog.Content maxWidth="480px">
          <AlertDialog.Title>{t("developer.release.lifecycle.rollbackTitle")}</AlertDialog.Title>
          <AlertDialog.Description>{t("developer.release.lifecycle.rollbackDescription")}</AlertDialog.Description>
          <label className="release-field">
            <Text size="2" weight="medium">{t("developer.release.lifecycle.restoreVersion")}</Text>
            <TextField.Root onChange={(event) => setRestoreVersion(event.target.value)} value={restoreVersion} />
          </label>
          <div className="release-dialog-actions">
            <AlertDialog.Cancel><Button color="gray" variant="soft">{t("common.cancel")}</Button></AlertDialog.Cancel>
            <Button color="orange" disabled={!restoreVersion.trim() || busy !== null} onClick={rollback}>
              {busy === "rollback" ? <Spinner /> : null}{t("developer.release.lifecycle.rollbackConfirm")}
            </Button>
          </div>
        </AlertDialog.Content>
      </AlertDialog.Root>

      <AlertDialog.Root onOpenChange={(open) => { if (!open) setDestroyPlan(null); }} open={destroyPlan !== null}>
        <AlertDialog.Content maxWidth="520px">
          <AlertDialog.Title>{t("developer.release.lifecycle.destroyTitle")}</AlertDialog.Title>
          <AlertDialog.Description>{t("developer.release.lifecycle.destroyDescription")}</AlertDialog.Description>
          <ul className="release-destroy-resources">
            {destroyPlan?.resources.map((resource) => <li key={resource}><code>{resource}</code></li>)}
          </ul>
          <div className="release-dialog-actions">
            <AlertDialog.Cancel><Button color="gray" variant="soft">{t("common.cancel")}</Button></AlertDialog.Cancel>
            <Button color="red" disabled={busy !== null} onClick={applyDestroy}>
              {busy === "destroy" ? <Spinner /> : null}{t("developer.release.lifecycle.destroyConfirm")}
            </Button>
          </div>
        </AlertDialog.Content>
      </AlertDialog.Root>

      <AlertDialog.Root onOpenChange={setDisconnectOpen} open={disconnectOpen}>
        <AlertDialog.Content maxWidth="480px">
          <AlertDialog.Title>{t("developer.release.lifecycle.disconnectTitle")}</AlertDialog.Title>
          <AlertDialog.Description>{t("developer.release.lifecycle.disconnectDescription")}</AlertDialog.Description>
          <div className="release-dialog-actions">
            <AlertDialog.Cancel><Button color="gray" variant="soft">{t("common.cancel")}</Button></AlertDialog.Cancel>
            <Button color="red" disabled={busy !== null} onClick={disconnect}>
              {busy === "disconnect" ? <Spinner /> : null}{t("developer.release.lifecycle.disconnectConfirm")}
            </Button>
          </div>
        </AlertDialog.Content>
      </AlertDialog.Root>
    </section>
  );
}

function deploymentDrift(
  deployment: LifecycleDeployment | null,
  observation: GatewayObservation | null,
): "unchecked" | "in_sync" | "drift_detected" {
  if (!deployment || !observation) return "unchecked";
  return observation.reachability === "reachable"
    && observation.remoteVersion === deployment.versionId
    ? "in_sync"
    : "drift_detected";
}
