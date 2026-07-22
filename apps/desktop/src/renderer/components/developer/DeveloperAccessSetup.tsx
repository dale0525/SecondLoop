import {
  Badge,
  Button,
  Callout,
  Spinner,
} from "@radix-ui/themes";
import {
  ArrowLeft,
  ArrowRight,
  Check,
  KeyRound,
  PackageCheck,
  ShieldCheck,
  TriangleAlert,
} from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";

import type { DeveloperProjectSnapshot } from "../../../shared/developerProject";
import type { DeveloperAccessBundlePlan } from "../../../shared/developerAccess";
import {
  applyGateway,
  applyAccessBundle,
  cancelCloudflareConnection,
  cancelFirebaseConnection,
  configureFirebaseProject,
  connectCloudflareCustom,
  connectCloudflarePublic,
  connectFirebaseCustom,
  connectFirebasePublic,
  listCloudflareAccounts,
  listFirebaseProjects,
  loadDeveloperControlStatus,
  planGateway,
  planAccessBundle,
  saveDeveloperProject,
  selectCloudflareAccount,
  verifyGateway,
  verifyAccessBundle,
  type CloudflareAccount,
  type AccessBundleDestroyUpdate,
  type AccessBundleMutationUpdate,
  type DeveloperControlStatus,
  type GatewayDestroyUpdate,
  type GatewayMutationUpdate,
  type GatewayPlan,
  type FirebaseProject,
  type SensitivePlanInput,
} from "../../developerAccessApi";
import type { DeveloperProviderDescriptor } from "../../devProvidersApi";
import {
  managedProjectDraft,
  providerBySelection,
  selectionFromDescriptor,
  validateManagedDraft,
  type DeveloperProjectDocument,
  type ManagedProjectDraft,
} from "../../developerProjectModel";
import { useHostBootstrap } from "../../hostBootstrap";
import { useI18n } from "../../i18n/I18nProvider";
import { useIdentitySession } from "../../identitySession";
import { DeveloperConfigurationStep } from "./DeveloperConfigurationStep";
import { DeveloperAccessBundleOperations } from "./DeveloperAccessBundleOperations";
import { DeveloperCommerceVerificationGuide } from "./DeveloperCommerceVerificationGuide";
import { DeveloperConnectionStep } from "./DeveloperConnectionStep";
import { DeveloperDeploymentOperations } from "./DeveloperDeploymentOperations";
import { DeveloperFirebaseIdentitySetup } from "./DeveloperFirebaseIdentitySetup";
import { IdentityPasswordForm } from "../IdentityPasswordForm";
import { useCreemWebhookBootstrap } from "./useCreemWebhookBootstrap";

const STEP_COUNT = 3;

export function DeveloperAccessSetup({
  snapshot,
  project,
  providers,
  initialControlStatus,
  onCancel,
  onControlStatus,
  onProjectSaved,
}: {
  snapshot: DeveloperProjectSnapshot;
  project: DeveloperProjectDocument;
  providers: readonly DeveloperProviderDescriptor[];
  initialControlStatus: DeveloperControlStatus | null;
  onCancel: () => void;
  onControlStatus: (status: DeveloperControlStatus) => void;
  onProjectSaved: (snapshot: DeveloperProjectSnapshot) => void;
}): JSX.Element {
  const { t } = useI18n();
  const bootstrap = useHostBootstrap();
  const identitySession = useIdentitySession();
  const appId = typeof snapshot.manifest.appId === "string" ? snapshot.manifest.appId : "agentweave-app";
  const initialDraft = useMemo(
    () => managedProjectDraft(project, providers, appId),
    [appId, project, providers],
  );
  const [step, setStep] = useState(() => initialStep(snapshot, initialControlStatus));
  const [draft, setDraft] = useState<ManagedProjectDraft>(initialDraft);
  const [workingSnapshot, setWorkingSnapshot] = useState(snapshot);
  const [controlStatus, setControlStatus] = useState(initialControlStatus);
  const [accounts, setAccounts] = useState<CloudflareAccount[]>([]);
  const [firebaseProjects, setFirebaseProjects] = useState<FirebaseProject[]>([]);
  const [firebaseProjectsFailed, setFirebaseProjectsFailed] = useState(false);
  const [firebaseProjectsLoading, setFirebaseProjectsLoading] = useState(false);
  const [secretValues, setSecretValues] = useState<Record<string, string>>({});
  const [secretRevisions, setSecretRevisions] = useState<Record<string, string>>({});
  const [customOauth, setCustomOauth] = useState(false);
  const [customClientId, setCustomClientId] = useState("");
  const [customScopeCatalog, setCustomScopeCatalog] = useState("");
  const [plan, setPlan] = useState<GatewayPlan | DeveloperAccessBundlePlan | null>(null);
  const [deploymentApplied, setDeploymentApplied] = useState(
    Boolean(
      initialControlStatus?.pendingDeployment
      || initialControlStatus?.pendingAccessBundle
      || snapshot.verifiedDeployment
      || snapshot.verifiedBundle,
    ),
  );
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [completed, setCompleted] = useState(false);
  const automaticAccountRef = useRef<string | null>(null);
  const previousAuthorizationPhaseRef = useRef(initialControlStatus?.authorization.phase);
  const onControlStatusRef = useRef(onControlStatus);

  const identityProviders = providers.filter((item) => item.kind === "identity");
  const entitlementProviders = providers.filter((item) => item.kind === "entitlement"
    && item.capabilities.some((capability) => [
      "gateway_policy_projection_v1", "gateway_policy_projection_v2",
    ].includes(capability)));
  const commerceProviders = providers.filter((item) => item.kind === "commerce");
  const gatewayProviders = providers.filter((item) => item.kind === "gateway_deployment");
  const identityDescriptor = providerBySelection(providers, draft.providers.identity);
  const entitlementDescriptor = providerBySelection(providers, draft.providers.entitlement);
  const gatewayDescriptor = providerBySelection(providers, draft.providers.gateway);
  const configuredSlots = useMemo(
    () => logicalConfiguredSlots(controlStatus?.sensitiveBindings ?? {}),
    [controlStatus],
  );
  const issues = validateManagedDraft(draft, providers);
  const visibleIssues = issues.map((issue) => (
    issue === "Model name is required" ? t("developer.release.modelNameRequired") : issue
  ));
  const authorizationReady = controlStatus?.authorization.phase === "ready";
  const effectiveCustomOauth = customOauth
    || controlStatus?.authorization.publicOauthClientAvailable === false;
  const lifecycleDeployment = controlStatus?.pendingDeployment?.deployment
    ? {
        target: controlStatus.pendingDeployment.deployment.target,
        versionId: controlStatus.pendingDeployment.deployment.versionId,
        endpoint: controlStatus.pendingDeployment.deployment.endpoint,
      }
    : workingSnapshot.verifiedDeployment ?? null;
  const managedAccess = draft.deployment.cloudflare.entitlement.mode === "managed_worker";
  const commerceEnvironment = draft.providers.commerce?.publicConfig.environment === "production"
    ? "production"
    : "test";
  const managedEntitlementEndpoint = controlStatus?.pendingAccessBundle?.bundle
    .resources["entitlement-policy"]?.endpoint
    ?? workingSnapshot.verifiedBundle?.entitlementPolicy.endpoint
    ?? null;

  const updateControlStatus = useCallback((status: DeveloperControlStatus) => {
    setControlStatus(status);
    onControlStatusRef.current(status);
  }, []);

  const refreshControl = useCallback(async () => {
    const status = await loadDeveloperControlStatus();
    updateControlStatus(status);
    return status;
  }, [updateControlStatus]);
  const acceptBootstrapProject = useCallback((saved: DeveloperProjectSnapshot) => {
    setWorkingSnapshot(saved);
    onProjectSaved(saved);
  }, [onProjectSaved]);
  const commerceBootstrap = useCreemWebhookBootstrap({
    authorizationReady,
    draft,
    onProjectSaved: acceptBootstrapProject,
    snapshot: workingSnapshot,
  });

  useEffect(() => {
    onControlStatusRef.current = onControlStatus;
  }, [onControlStatus]);

  useEffect(() => {
    let active = true;
    void loadDeveloperControlStatus()
      .then((status) => {
        if (active) updateControlStatus(status);
      })
      .catch(() => undefined);
    return () => {
      active = false;
    };
  }, [updateControlStatus]);

  useEffect(() => {
    setWorkingSnapshot(snapshot);
  }, [snapshot]);

  useEffect(() => {
    if (controlStatus?.pendingDeployment || controlStatus?.pendingAccessBundle) setDeploymentApplied(true);
  }, [controlStatus?.pendingAccessBundle, controlStatus?.pendingDeployment]);

  useEffect(() => {
    const accountId = controlStatus?.authorization.accountId;
    if (!accountId || draft.deployment.cloudflare.accountId === accountId) return;
    setDraft((current) => ({
      ...current,
      deployment: {
        ...current.deployment,
        cloudflare: { ...current.deployment.cloudflare, accountId },
      },
    }));
    setPlan(null);
  }, [controlStatus?.authorization.accountId, draft.deployment.cloudflare.accountId]);

  useEffect(() => {
    const cloudflarePhase = controlStatus?.authorization.phase;
    const firebasePhase = controlStatus?.firebaseAuthorization?.phase;
    if (cloudflarePhase !== "awaiting_callback" && firebasePhase !== "awaiting_callback") return;
    const timer = window.setInterval(() => {
      void refreshControl().catch(() => undefined);
    }, 1_500);
    return () => window.clearInterval(timer);
  }, [controlStatus?.authorization.phase, controlStatus?.firebaseAuthorization?.phase, refreshControl]);

  const loadFirebaseProjectOptions = useCallback(async () => {
    setFirebaseProjectsLoading(true);
    setFirebaseProjectsFailed(false);
    setError(null);
    try {
      setFirebaseProjects(await listFirebaseProjects());
    } catch {
      setFirebaseProjects([]);
      setFirebaseProjectsFailed(true);
      setError(t("developer.release.errorFirebaseProjects"));
    } finally {
      setFirebaseProjectsLoading(false);
    }
  }, [t]);

  useEffect(() => {
    if (controlStatus?.firebaseAuthorization?.phase !== "select_project") return;
    void loadFirebaseProjectOptions();
  }, [controlStatus?.firebaseAuthorization?.phase, loadFirebaseProjectOptions]);

  useEffect(() => {
    if (controlStatus?.authorization.phase !== "select_account") return;
    void listCloudflareAccounts()
      .then((availableAccounts) => {
        setAccounts(availableAccounts);
        const onlyAccount = availableAccounts.length === 1 ? availableAccounts[0] : null;
        if (!onlyAccount || automaticAccountRef.current === onlyAccount.accountId) return;
        automaticAccountRef.current = onlyAccount.accountId;
        void selectAccount(onlyAccount.accountId).then((succeeded) => {
          if (!succeeded && automaticAccountRef.current === onlyAccount.accountId) {
            automaticAccountRef.current = null;
          }
        });
      })
      .catch(() => setError(t("developer.release.errorAccounts")));
  }, [controlStatus?.authorization.phase, t]);

  useEffect(() => {
    const phase = controlStatus?.authorization.phase;
    const previousPhase = previousAuthorizationPhaseRef.current;
    previousAuthorizationPhaseRef.current = phase;
    if (step === 1 && phase === "ready" && previousPhase !== "ready") setStep(2);
  }, [controlStatus?.authorization.phase, step]);

  const mutateDraft = (next: ManagedProjectDraft) => {
    setDraft(next);
    setPlan(null);
    setDeploymentApplied(false);
    setCompleted(false);
  };

  const chooseProvider = (
    kind: "identity" | "entitlement" | "gateway",
    descriptor: DeveloperProviderDescriptor,
  ) => {
    mutateDraft({
      ...draft,
      providers: {
        ...draft.providers,
        [kind]: selectionFromDescriptor(descriptor, kind === "identity"
          && descriptor.provider_id !== "agentweave.identity.firebase" ? {
          scopes: ["openid", "profile", "offline_access"],
          redirectUri: "http://127.0.0.1:8978/agentweave/identity/callback",
          gatewayAlgorithm: "RS256",
          gatewayDeviceMode: "disabled",
          gatewayRequireNbf: false,
        } : {}),
      },
    });
  };

  const run = async (name: string, action: () => Promise<void>) => {
    if (busy) return;
    setBusy(name);
    setError(null);
    try {
      await action();
    } catch (cause) {
      setError(safeError(cause, t("developer.release.errorGeneric")));
    } finally {
      setBusy(null);
    }
  };

  const connect = () => run("oauth", async () => {
    if (effectiveCustomOauth) {
      const catalog = parseScopeCatalog(customScopeCatalog, t("developer.release.errorCustomOauth"));
      if (!customClientId.trim() || Object.keys(catalog).length === 0) {
        throw new Error(t("developer.release.errorCustomOauth"));
      }
      await connectCloudflareCustom({ clientId: customClientId.trim(), scopeCatalog: catalog });
    } else {
      await connectCloudflarePublic();
    }
    updateControlStatus({
      ...(controlStatus ?? emptyControlStatus()),
      authorization: {
        ...(controlStatus?.authorization ?? emptyControlStatus().authorization),
        phase: "awaiting_callback",
      },
    });
  });

  const connectFirebaseIdentity = (client: {
    clientId?: string;
    clientSecret?: string;
    publicClient: boolean;
  }) => run("firebase-oauth", async () => {
    if (client.publicClient) await connectFirebasePublic();
    else if (client.clientId) {
      await connectFirebaseCustom({
        clientId: client.clientId,
        ...(client.clientSecret ? { clientSecret: client.clientSecret } : {}),
      });
    } else {
      throw new Error(t("developer.release.errorFirebaseOauth"));
    }
    updateControlStatus({
      ...(controlStatus ?? emptyControlStatus()),
      firebaseAuthorization: {
        ...(controlStatus?.firebaseAuthorization ?? emptyFirebaseAuthorization()),
        phase: "awaiting_callback",
      },
    });
  });

  const configureFirebaseIdentity = (projectId: string) => run("firebase-configure", async () => {
    const receipt = await configureFirebaseProject(projectId);
    const descriptor = identityProviders.find(
      (provider) => provider.provider_id === "agentweave.identity.firebase",
    );
    if (!descriptor) throw new Error(t("developer.release.errorFirebaseProvider"));
    mutateDraft({
      ...draft,
      providers: {
        ...draft.providers,
        identity: selectionFromDescriptor(descriptor, { ...receipt.publicConfig }),
      },
    });
    await refreshControl();
  });

  const selectAccount = async (accountId: string): Promise<boolean> => {
    let succeeded = false;
    await run("account", async () => {
      await selectCloudflareAccount(accountId);
      const status = await refreshControl();
      if (status.authorization.phase !== "ready") {
        throw new Error(t("developer.release.errorAccountSelection"));
      }
      succeeded = true;
    });
    return succeeded;
  };

  const save = () => run("save", async () => {
    if (visibleIssues.length > 0) throw new Error(visibleIssues[0]);
    const saved = await saveDeveloperProject(workingSnapshot, draft);
    setWorkingSnapshot(saved);
    onProjectSaved(saved);
  });

  const createPlan = () => run("plan", async () => {
    const latest = await saveDeveloperProject(workingSnapshot, draft);
    setWorkingSnapshot(latest);
    onProjectSaved(latest);
    const sensitiveInputs = makeSensitiveInputs(
      draft,
      configuredSlots,
      controlStatus?.sensitiveBindings ?? {},
      secretValues,
      secretRevisions,
      t("developer.release.errorSecrets"),
    );
    setSecretRevisions(Object.fromEntries(
      Object.entries(sensitiveInputs).map(([slot, input]) => [slot, input.revision]),
    ));
    setPlan(managedAccess
      ? await planAccessBundle({ project: latest, sensitiveInputs })
      : await planGateway({ project: latest, sensitiveInputs }));
    await refreshControl();
  });

  const apply = () => run("apply", async () => {
    if (!plan) throw new Error(t("developer.release.errorPlanRequired"));
    const result = managedAccess
      ? await applyAccessBundle(plan.planHash)
      : await applyGateway(plan.planHash);
    setWorkingSnapshot(result.project);
    setDraft(result.project.project as ManagedProjectDraft);
    onProjectSaved(result.project);
    setPlan(null);
    setDeploymentApplied(true);
    await refreshControl();
  });

  const verify = () => run("verify", async () => {
    const result = managedAccess ? await verifyAccessBundle() : await verifyGateway();
    setWorkingSnapshot(result.project);
    setDraft(result.project.project as ManagedProjectDraft);
    onProjectSaved(result.project);
    setCompleted(true);
    await refreshControl();
  });

  const acceptLifecycleMutation = async (result: GatewayMutationUpdate) => {
    setWorkingSnapshot(result.project);
    setDraft(result.project.project as ManagedProjectDraft);
    onProjectSaved(result.project);
    setDeploymentApplied(true);
    setCompleted(false);
    await refreshControl();
  };

  const acceptDestroyedDeployment = async (result: GatewayDestroyUpdate) => {
    setWorkingSnapshot(result.project);
    setDraft(result.project.project as ManagedProjectDraft);
    onProjectSaved(result.project);
    setPlan(null);
    setDeploymentApplied(false);
    setCompleted(false);
    await refreshControl();
  };

  const acceptAccessBundleMutation = async (result: AccessBundleMutationUpdate) => {
    setWorkingSnapshot(result.project);
    setDraft(result.project.project as ManagedProjectDraft);
    onProjectSaved(result.project);
    setDeploymentApplied(true);
    setCompleted(result.project.deploymentStatus === "ready");
    await refreshControl();
  };

  const acceptDestroyedAccessBundle = async (result: AccessBundleDestroyUpdate) => {
    setWorkingSnapshot(result.project);
    setDraft(result.project.project as ManagedProjectDraft);
    onProjectSaved(result.project);
    setPlan(null);
    setDeploymentApplied(false);
    setCompleted(false);
    await refreshControl();
  };

  const canContinue = stepReady(step, draft, providers, controlStatus, configuredSlots, secretValues);

  return (
    <section className="release-setup" aria-labelledby="release-setup-title">
      <header className="release-setup-mobile-heading">
        <span>{t("developer.release.setupProgress", { current: step, total: STEP_COUNT })}</span>
        <strong>{stepTitle(step, t)}</strong>
        <div aria-hidden="true"><span style={{ width: `${(step / STEP_COUNT) * 100}%` }} /></div>
      </header>

      <nav aria-label={t("developer.release.setupSteps")} className="release-step-rail">
        <div className="release-step-rail-heading">
          <span className="release-eyebrow">{t("developer.release.accessEyebrow")}</span>
          <h2 id="release-setup-title">{t("developer.release.setupTitle")}</h2>
          <p>{t("developer.release.setupDescription")}</p>
        </div>
        {Array.from({ length: STEP_COUNT }, (_, index) => index + 1).map((item) => (
          <button
            aria-current={item === step ? "step" : undefined}
            className={`release-step${item === step ? " is-current" : ""}${item < step ? " is-complete" : ""}`}
            key={item}
            onClick={() => setStep(item)}
            type="button"
          >
            <span>{item < step ? <Check aria-hidden="true" size={14} /> : item}</span>
            <div><strong>{stepTitle(item, t)}</strong><small>{stepHint(item, t)}</small></div>
          </button>
        ))}
        <Button color="gray" onClick={onCancel} variant="ghost">
          <ArrowLeft aria-hidden="true" size={16} /> {t("developer.release.backToOverview")}
        </Button>
      </nav>

      <div className="release-setup-main">
        {error ? (
          <Callout.Root color="red" role="alert">
            <TriangleAlert aria-hidden="true" /><Callout.Text>{error}</Callout.Text>
          </Callout.Root>
        ) : null}
        {step === 1 ? (
          <DeveloperConnectionStep
            accounts={accounts}
            busy={busy}
            controlStatus={controlStatus}
            customClientId={customClientId}
            customOauth={effectiveCustomOauth}
            customScopeCatalog={customScopeCatalog}
            entitlementProviders={entitlementProviders}
            gatewayProviders={gatewayProviders}
            identityProviders={identityProviders}
            onCancel={() => run("cancel-oauth", async () => {
              await cancelCloudflareConnection();
              await refreshControl();
            })}
            onChooseEntitlement={(descriptor) => chooseProvider("entitlement", descriptor)}
            onChooseGateway={(descriptor) => chooseProvider("gateway", descriptor)}
            onChooseIdentity={(descriptor) => chooseProvider("identity", descriptor)}
            onConnect={connect}
            onCustomClientId={setCustomClientId}
            onCustomOauth={setCustomOauth}
            onCustomScopeCatalog={setCustomScopeCatalog}
            onSelectAccount={selectAccount}
            selections={draft.providers}
          />
        ) : null}
        {step === 2 && identityDescriptor && entitlementDescriptor && gatewayDescriptor ? (
          <DeveloperConfigurationStep
            commerceProviders={commerceProviders}
            commerceBootstrap={commerceBootstrap}
            configuredSlots={configuredSlots}
            draft={draft}
            entitlementDescriptor={entitlementDescriptor}
            gatewayDescriptor={gatewayDescriptor}
            identityDescriptor={identityDescriptor}
            identitySetup={identityDescriptor.provider_id === "agentweave.identity.firebase" ? (
              <DeveloperFirebaseIdentitySetup
                busy={busy}
                configuredProjectId={typeof draft.providers.identity.publicConfig.projectId === "string"
                  ? draft.providers.identity.publicConfig.projectId
                  : null}
                onCancel={() => run("firebase-cancel", async () => {
                  await cancelFirebaseConnection();
                  await refreshControl();
                })}
                onConfigure={configureFirebaseIdentity}
                onConnect={connectFirebaseIdentity}
                onRetryProjects={() => void loadFirebaseProjectOptions()}
                projects={firebaseProjects}
                projectsFailed={firebaseProjectsFailed}
                projectsLoading={firebaseProjectsLoading}
                status={controlStatus?.firebaseAuthorization}
              />
            ) : undefined}
            onDraft={mutateDraft}
            onProductsConnected={async () => { await refreshControl(); }}
            onSecret={(slot, value) => {
              setSecretValues((current) => ({ ...current, [slot]: value }));
              setSecretRevisions((current) => ({ ...current, [slot]: newRevision() }));
              setPlan(null);
            }}
            secretValues={secretValues}
            productionUnlocked={workingSnapshot.verifiedBundle?.commerce?.environment === "test"}
          />
        ) : null}
        {step === 3 ? (
          <>
            <DeployStep
              authorizationReady={authorizationReady}
              applied={deploymentApplied}
              bootstrapReady={bootstrap.discovery?.access.identity.mode === "required"}
              busy={busy}
              completed={completed || workingSnapshot.deploymentStatus === "ready"}
              identityState={identitySession.state}
              identityMethod={identitySession.method}
              issues={visibleIssues}
              onApply={apply}
              onPlan={createPlan}
              onSave={save}
              onSignIn={() => run("identity", identitySession.start)}
              onVerify={verify}
              plan={plan}
              snapshot={workingSnapshot}
            />
            {managedAccess && draft.providers.commerce && deploymentApplied ? (
              <DeveloperCommerceVerificationGuide
                entitlementEndpoint={managedEntitlementEndpoint}
                environment={commerceEnvironment}
                portalVerifiedAtUnixMs={workingSnapshot.verifiedBundle?.commerce?.portalVerifiedAtUnixMs ?? null}
                webhookVerifiedAtUnixMs={workingSnapshot.verifiedBundle?.commerce?.webhookVerifiedAtUnixMs ?? null}
              />
            ) : null}
            {!managedAccess ? (
              <DeveloperDeploymentOperations
                authorizationReady={authorizationReady}
                deployment={lifecycleDeployment}
                onDestroyed={acceptDestroyedDeployment}
                onDisconnected={async () => {
                  const status = await refreshControl();
                  setDeploymentApplied(Boolean(status.pendingDeployment));
                }}
                onMutation={acceptLifecycleMutation}
              />
            ) : (
              <DeveloperAccessBundleOperations
                authorizationReady={authorizationReady}
                onDestroyed={acceptDestroyedAccessBundle}
                onMutation={acceptAccessBundleMutation}
                snapshot={workingSnapshot}
              />
            )}
          </>
        ) : null}

        {step > 1 || canContinue ? (
          <footer className="release-step-actions">
            {step > 1 ? (
              <Button color="gray" disabled={busy !== null} onClick={() => setStep(step - 1)} variant="soft">
                <ArrowLeft aria-hidden="true" size={16} /> {t("common.back")}
              </Button>
            ) : null}
            {step < STEP_COUNT ? (
              <Button disabled={!canContinue || busy !== null} onClick={() => setStep(step + 1)}>
                {t("common.continue")} <ArrowRight aria-hidden="true" size={16} />
              </Button>
            ) : null}
          </footer>
        ) : null}
      </div>

      <ReleaseSummary
        controlStatus={controlStatus}
        draft={draft}
        issues={visibleIssues}
        snapshot={workingSnapshot}
      />
    </section>
  );
}

function StepHeading({
  description,
  icon,
  title,
}: {
  description: string;
  icon: ReactNode;
  title: string;
}): JSX.Element {
  return (
    <header className="release-step-heading">
      <span>{icon}</span><div><h2>{title}</h2><p>{description}</p></div>
    </header>
  );
}

function DeployStep({
  authorizationReady,
  applied,
  bootstrapReady,
  busy,
  completed,
  identityState,
  identityMethod,
  issues,
  onApply,
  onPlan,
  onSave,
  onSignIn,
  onVerify,
  plan,
  snapshot,
}: {
  authorizationReady: boolean;
  applied: boolean;
  bootstrapReady: boolean;
  busy: string | null;
  completed: boolean;
  identityState: string;
  identityMethod: "browser" | "password";
  issues: readonly string[];
  onApply: () => void;
  onPlan: () => void;
  onSave: () => void;
  onSignIn: () => void;
  onVerify: () => void;
  plan: GatewayPlan | DeveloperAccessBundlePlan | null;
  snapshot: DeveloperProjectSnapshot;
}) {
  const { t } = useI18n();
  return (
    <section className="release-step-content">
      <StepHeading description={t("developer.release.deployDescription")} icon={<PackageCheck aria-hidden="true" size={22} />} title={t("developer.release.deployTitle")} />
      {issues.length > 0 ? <Callout.Root color="orange"><TriangleAlert aria-hidden="true" /><Callout.Text>{issues[0]}</Callout.Text></Callout.Root> : null}
      {identityMethod === "password" && identityState !== "signed_in" ? (
        <div className="release-test-identity">
          <strong>{t("developer.release.firebaseTestLogin")}</strong>
          <IdentityPasswordForm />
        </div>
      ) : null}
      <div className="release-operation-list">
        <OperationRow action={<Button disabled={busy !== null || issues.length > 0} onClick={onSave} variant="soft">{busy === "save" ? <Spinner /> : null}{t("developer.release.saveProject")}</Button>} done={issues.length === 0} title={t("developer.release.operationSave")} />
        <OperationRow action={identityState === "signed_in" ? <Badge color="green">{t("identity.signedIn")}</Badge> : identityMethod === "password" ? <Badge color="orange">{t("developer.release.useLoginForm")}</Badge> : <Button disabled={busy !== null || !bootstrapReady} onClick={onSignIn} variant="soft">{busy === "identity" ? <Spinner /> : null}{t("developer.release.signInTestUser")}</Button>} done={identityState === "signed_in"} title={t("developer.release.operationIdentity")} />
        <OperationRow action={plan ? <Badge color="blue">{planOperationCount(plan)} {t("developer.release.operations")}</Badge> : <Button disabled={busy !== null || !authorizationReady || issues.length > 0} onClick={onPlan}>{busy === "plan" ? <Spinner /> : null}{t("developer.release.createPlan")}</Button>} done={plan !== null || applied || completed} title={t("developer.release.operationPlan")} />
        <OperationRow action={applied || completed ? <Badge color="green">{t("developer.release.deployed")}</Badge> : <Button disabled={busy !== null || !plan} onClick={onApply}>{busy === "apply" ? <Spinner /> : null}{t("developer.release.deployGateway")}</Button>} done={applied || completed} title={t("developer.release.operationDeploy")} />
        <OperationRow action={completed ? <Badge color="green">{t("developer.release.verified")}</Badge> : <Button disabled={busy !== null || !applied || identityState !== "signed_in"} onClick={onVerify}>{busy === "verify" ? <Spinner /> : null}{t("developer.release.verifyGateway")}</Button>} done={completed} title={t("developer.release.operationVerify")} />
      </div>
      {plan ? <DeploymentPlanPreview plan={plan} /> : null}
      {completed ? <Callout.Root color="green"><ShieldCheck aria-hidden="true" /><Callout.Text>{t("developer.release.verificationComplete")}</Callout.Text></Callout.Root> : null}
    </section>
  );
}

function OperationRow({ title, done, action }: { title: string; done: boolean; action: ReactNode }) {
  return <div className="release-operation-row"><span className={done ? "is-done" : ""}>{done ? <Check aria-hidden="true" size={15} /> : null}</span><strong>{title}</strong><div>{action}</div></div>;
}

function planOperationCount(plan: GatewayPlan | DeveloperAccessBundlePlan): number {
  return "resources" in plan
    ? plan.resources.reduce((count, resource) => count + Math.max(1, resource.operations.length), 0)
    : plan.operations.length;
}

function DeploymentPlanPreview({
  plan,
}: {
  plan: GatewayPlan | DeveloperAccessBundlePlan;
}): JSX.Element {
  const { t } = useI18n();
  if (!("resources" in plan)) {
    return (
      <div className="release-plan-preview">
        <div><strong>{t("developer.release.planPreview")}</strong><Badge color={plan.drift.status === "in_sync" ? "green" : "orange"}>{plan.drift.status.replaceAll("_", " ")}</Badge></div>
        <ul>{plan.operations.map((operation, index) => <li key={`${operation.kind}-${operation.resource}-${index}`}><span>{operation.kind.replaceAll("_", " ")}</span><code>{operation.resource}</code>{operation.destructive ? <Badge color="red">{t("developer.release.destructive")}</Badge> : null}</li>)}</ul>
      </div>
    );
  }
  return (
    <div className="release-plan-preview release-bundle-plan">
      <div><strong>{t("developer.release.accessResourcePlan")}</strong><Badge color="blue">{plan.resources.length} {t("developer.release.resources")}</Badge></div>
      <ol className="release-resource-timeline">
        {plan.resources.map((resource) => (
          <li key={resource.resourceId}>
            <span aria-hidden="true" />
            <div>
              <strong>{resource.purpose.replaceAll("_", " ")}</strong>
              <code>{resource.target.workerName}</code>
              {resource.dependencies.length > 0 ? <small>{t("developer.release.dependsOn", { value: resource.dependencies.join(", ") })}</small> : null}
            </div>
            <Badge color={resource.operations.some((operation) => operation.destructive) ? "red" : "gray"}>{resource.kind.replaceAll("_", " ")}</Badge>
          </li>
        ))}
      </ol>
    </div>
  );
}

function ReleaseSummary({ draft, snapshot, controlStatus, issues }: {
  draft: ManagedProjectDraft;
  snapshot: DeveloperProjectSnapshot;
  controlStatus: DeveloperControlStatus | null;
  issues: readonly string[];
}) {
  const { t } = useI18n();
  return (
    <aside className="release-summary">
      <span className="release-eyebrow">{t("developer.release.summaryEyebrow")}</span>
      <h3>{t("developer.release.summaryTitle")}</h3>
      <dl>
        <Fact label={t("developer.release.identity")} value={draft.providers.identity.id} />
        <Fact label={t("developer.release.entitlements")} value={draft.providers.entitlement.id} />
        <Fact label={t("developer.release.gateway")} value={draft.providers.gateway.id} />
        <Fact label={t("developer.release.modelName")} value={draft.modelAccess.profile.modelName || "—"} />
        <Fact label={t("developer.release.environment")} value={draft.deployment.cloudflare.environment} />
        <Fact label={t("developer.release.accountId")} value={controlStatus?.authorization.accountId ?? "—"} />
      </dl>
      <div className={`release-summary-readiness${snapshot.deploymentStatus === "ready" ? " is-ready" : ""}`}>
        {snapshot.deploymentStatus === "ready" ? <ShieldCheck aria-hidden="true" size={19} /> : <TriangleAlert aria-hidden="true" size={19} />}
        <div><strong>{snapshot.deploymentStatus === "ready" ? t("developer.release.readyToPackage") : t("developer.release.notReady")}</strong><small>{issues.length > 0 ? t("developer.release.issueCount", { count: issues.length }) : snapshot.deploymentMessage ?? t("developer.release.finishVerification")}</small></div>
      </div>
      <Callout.Root color="gray" size="1"><KeyRound aria-hidden="true" /><Callout.Text>{t("developer.release.noSecretsInPackage")}</Callout.Text></Callout.Root>
    </aside>
  );
}

function Fact({ label, value }: { label: string; value: string }) {
  return <div className="release-fact"><dt>{label}</dt><dd>{value}</dd></div>;
}

function initialStep(
  snapshot: DeveloperProjectSnapshot,
  status: DeveloperControlStatus | null,
): number {
  if (snapshot.deploymentStatus === "ready" || status?.pendingDeployment || status?.pendingAccessBundle) return 3;
  if (status?.authorization.phase === "ready") return 2;
  return 1;
}

function stepReady(
  step: number,
  draft: ManagedProjectDraft,
  providers: readonly DeveloperProviderDescriptor[],
  status: DeveloperControlStatus | null,
  configured: ReadonlySet<string>,
  values: Readonly<Record<string, string>>,
): boolean {
  if (step === 1) return status?.authorization.phase === "ready"
    && Boolean(draft.deployment.cloudflare.accountId)
    && providerBySelection(providers, draft.providers.identity) !== null
    && providerBySelection(providers, draft.providers.entitlement) !== null
    && providerBySelection(providers, draft.providers.gateway) !== null;
  if (step === 2) return validateManagedDraft(draft, providers).length === 0
    && requiredSensitiveSlots(draft)
      .every((slot) => configured.has(slot) || Boolean(values[slot]?.trim()));
  return true;
}

function logicalConfiguredSlots(bindings: Readonly<Record<string, string>>): ReadonlySet<string> {
  const slots = new Set(Object.keys(bindings));
  if (bindings.UPSTREAM_API_KEY) slots.add("gateway.upstreamApiKey");
  if (bindings.ENTITLEMENT_PROJECTION_SECRET) slots.add("entitlement.serviceCredential");
  if (bindings.CREEM_API_KEY) slots.add("commerce.apiKey");
  if (bindings.CREEM_WEBHOOK_SECRET) slots.add("commerce.webhookSecret");
  return slots;
}

function requiredSensitiveSlots(draft: ManagedProjectDraft): string[] {
  const slots = ["gateway.upstreamApiKey"];
  const entitlement = draft.deployment.cloudflare.entitlement;
  if (entitlement.mode === "external_service") slots.push("entitlement.serviceCredential");
  if (draft.providers.commerce) slots.push("commerce.apiKey", "commerce.webhookSecret");
  return slots;
}

function makeSensitiveInputs(
  draft: ManagedProjectDraft,
  configured: ReadonlySet<string>,
  bindings: Readonly<Record<string, string>>,
  values: Readonly<Record<string, string>>,
  revisions: Readonly<Record<string, string>>,
  missingMessage: string,
): Record<string, SensitivePlanInput> {
  const physicalRevision = (slot: string) => bindings[slot] ?? ({
    "gateway.upstreamApiKey": bindings.UPSTREAM_API_KEY,
    "entitlement.serviceCredential": bindings.ENTITLEMENT_PROJECTION_SECRET,
    "commerce.apiKey": bindings.CREEM_API_KEY,
    "commerce.webhookSecret": bindings.CREEM_WEBHOOK_SECRET,
  } as Record<string, string | undefined>)[slot];
  return Object.fromEntries(requiredSensitiveSlots(draft).map((slot) => {
    const value = values[slot]?.trim();
    const revision = value ? revisions[slot] ?? newRevision() : physicalRevision(slot);
    if (!revision || (!value && !configured.has(slot))) throw new Error(missingMessage);
    return [slot, { revision, ...(value ? { value } : {}) }];
  }));
}

function parseScopeCatalog(value: string, invalidMessage: string): Record<string, string> {
  return Object.fromEntries(value.split(/\r?\n/).map((line) => line.trim()).filter(Boolean).map((line) => {
    const separator = line.indexOf("=");
    if (separator <= 0 || separator === line.length - 1) throw new Error(invalidMessage);
    return [line.slice(0, separator).trim(), line.slice(separator + 1).trim()];
  }));
}

function newRevision(): string {
  return `ui-${crypto.randomUUID()}`;
}

function safeError(error: unknown, fallback: string): string {
  return error instanceof Error && error.message.trim() ? error.message : fallback;
}

function emptyControlStatus(): DeveloperControlStatus {
  return {
    authorization: {
      providerId: "cloudflare-workers",
      phase: "disconnected",
      accountId: null,
      expiresAtUnixMs: null,
      publicOauthClientAvailable: false,
    },
    gatewayTemplate: null,
    entitlementTemplate: null,
    sensitiveBindings: {},
    pendingDeployment: null,
    pendingAccessBundle: null,
  };
}

function emptyFirebaseAuthorization(): NonNullable<DeveloperControlStatus["firebaseAuthorization"]> {
  return {
    providerId: "google.firebase",
    phase: "disconnected",
    projectId: null,
    expiresAtUnixMs: null,
    publicOauthClientAvailable: false,
  };
}

function stepTitle(step: number, t: (key: string) => string): string {
  return t(`developer.release.step${step}Title`);
}

function stepHint(step: number, t: (key: string) => string): string {
  return t(`developer.release.step${step}Hint`);
}
