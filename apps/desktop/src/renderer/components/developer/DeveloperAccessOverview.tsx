import { Badge, Button, Callout, Text } from "@radix-ui/themes";
import {
  Cloud,
  Gauge,
  KeyRound,
  LockKeyhole,
  ShieldCheck,
  TriangleAlert,
} from "lucide-react";

import type { DeveloperProjectSnapshot } from "../../../shared/developerProject";
import type { DeveloperControlStatus } from "../../developerAccessApi";
import type { DeveloperProviderDescriptor } from "../../devProvidersApi";
import type { DeveloperProjectDocument, ProviderSelection } from "../../developerProjectModel";
import { useI18n } from "../../i18n/I18nProvider";

export function DeveloperAccessOverview({
  snapshot,
  project,
  providers,
  controlStatus,
  onOpenModel,
  onSetup,
}: {
  snapshot: DeveloperProjectSnapshot;
  project: DeveloperProjectDocument;
  providers: readonly DeveloperProviderDescriptor[];
  controlStatus: DeveloperControlStatus | null;
  onOpenModel: () => void;
  onSetup: () => void;
}): JSX.Element {
  const { t } = useI18n();
  if (project.modelAccess.configurationPolicy === "user_configurable") {
    return (
      <section className="release-page release-access-overview">
        <header className="release-page-heading">
          <div>
            <span className="release-eyebrow">{t("developer.release.accessEyebrow")}</span>
            <h2>{t("developer.release.accessNotRequiredTitle")}</h2>
            <p>{t("developer.release.accessNotRequiredDescription")}</p>
          </div>
        </header>
        <Callout.Root color="gray" size="2">
          <KeyRound aria-hidden="true" />
          <Callout.Text>{t("developer.release.switchManagedHint")}</Callout.Text>
        </Callout.Root>
        <div><Button onClick={onOpenModel} size="3">{t("developer.release.openModelDelivery")}</Button></div>
      </section>
    );
  }
  const ready = snapshot.deploymentStatus === "ready";
  return (
    <section className="release-page release-access-overview" aria-labelledby="release-access-title">
      <header className="release-page-heading">
        <div>
          <span className="release-eyebrow">{t("developer.release.accessEyebrow")}</span>
          <h2 id="release-access-title">{t("developer.release.accessTitle")}</h2>
          <p>{t("developer.release.accessDescription")}</p>
        </div>
        <Badge color={ready ? "green" : "orange"} size="2">
          {ready ? t("developer.release.verified") : t("developer.release.setupRequired")}
        </Badge>
      </header>

      <div className="release-provider-status-grid">
        <ProviderStatus
          icon={<LockKeyhole aria-hidden="true" size={21} />}
          label={t("developer.release.identity")}
          providers={providers}
          selection={project.providers.identity}
          status={project.providers.identity ? t("developer.release.configured") : t("common.missing")}
          unavailableLabel={t("developer.release.notSelected")}
        />
        <ProviderStatus
          icon={<Gauge aria-hidden="true" size={21} />}
          label={t("developer.release.entitlements")}
          providers={providers}
          selection={project.providers.entitlement}
          status={project.providers.entitlement ? t("developer.release.configured") : t("common.missing")}
          unavailableLabel={t("developer.release.notSelected")}
        />
        <ProviderStatus
          icon={<Cloud aria-hidden="true" size={21} />}
          label={t("developer.release.gateway")}
          providers={providers}
          selection={project.providers.gateway}
          status={ready ? t("developer.release.deployedVerified") : t(`developer.release.deployment.${snapshot.deploymentStatus}`)}
          unavailableLabel={t("developer.release.notSelected")}
        />
      </div>

      <div className={ready ? "release-readiness-line is-ready" : "release-readiness-line is-blocked"}>
        {ready ? <ShieldCheck aria-hidden="true" size={22} /> : <TriangleAlert aria-hidden="true" size={22} />}
        <div>
          <strong>{ready ? t("developer.release.runtimeReady") : t("developer.release.packagingBlocked")}</strong>
          <Text as="p" color="gray" size="2">
            {ready
              ? t("developer.release.runtimeReadyHint")
              : snapshot.deploymentMessage ?? t("developer.release.finishVerification")}
          </Text>
        </div>
      </div>

      <dl className="release-facts release-overview-facts">
        <Fact label={t("developer.release.cloudflareAccount")} value={controlStatus?.authorization.accountId ?? t("developer.release.notConnected")} />
        <Fact label={t("developer.release.oauthState")} value={controlStatus ? t(`developer.release.oauth.${controlStatus.authorization.phase}.label`) : t("developer.release.unavailableShort")} />
        <Fact label={t("developer.release.gatewayTemplate")} value={controlStatus?.gatewayTemplate?.version ?? t("developer.release.unavailableShort")} />
        <Fact label={t("developer.release.storedSecrets")} value={String(Object.keys(controlStatus?.sensitiveBindings ?? {}).length)} />
      </dl>

      <div className="release-page-actions">
        <Button onClick={onSetup} size="3">{ready ? t("developer.release.reviewSetup") : t("developer.release.startSetup")}</Button>
      </div>
    </section>
  );
}

function ProviderStatus({
  icon,
  label,
  selection,
  providers,
  status,
  unavailableLabel,
}: {
  icon: JSX.Element;
  label: string;
  selection: ProviderSelection | null;
  providers: readonly DeveloperProviderDescriptor[];
  status: string;
  unavailableLabel: string;
}): JSX.Element {
  const descriptor = providers.find((provider) => provider.provider_id === selection?.id);
  return (
    <article className="release-provider-status-card">
      <span className="release-provider-status-icon">{icon}</span>
      <div>
        <span>{label}</span>
        <strong>{descriptor?.display_name ?? selection?.id ?? unavailableLabel}</strong>
      </div>
      <Badge color={selection ? "green" : "orange"} size="1">{status}</Badge>
    </article>
  );
}

function Fact({ label, value }: { label: string; value: string }) {
  return <div className="release-fact"><dt>{label}</dt><dd>{value}</dd></div>;
}
