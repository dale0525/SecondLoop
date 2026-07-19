import {
  Badge,
  Button,
  Callout,
  RadioCards,
  Select,
  Spinner,
  Text,
  TextArea,
  TextField,
} from "@radix-ui/themes";
import {
  ArrowLeft,
  ArrowRight,
  Check,
  Cloud,
  ExternalLink,
  KeyRound,
  LockKeyhole,
  PackageCheck,
  RotateCcw,
  ShieldCheck,
  TriangleAlert,
} from "lucide-react";
import { useEffect, useMemo, useState, type ReactNode } from "react";

import type { DeveloperProjectSnapshot } from "../../../shared/developerProject";
import {
  applyGateway,
  cancelCloudflareConnection,
  connectCloudflareCustom,
  connectCloudflarePublic,
  listCloudflareAccounts,
  loadDeveloperControlStatus,
  planGateway,
  saveDeveloperProject,
  selectCloudflareAccount,
  verifyGateway,
  type CloudflareAccount,
  type DeveloperControlStatus,
  type GatewayDestroyUpdate,
  type GatewayMutationUpdate,
  type GatewayPlan,
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
  type ProviderSelection,
} from "../../developerProjectModel";
import { useHostBootstrap } from "../../hostBootstrap";
import { useI18n } from "../../i18n/I18nProvider";
import { useIdentitySession } from "../../identitySession";
import { DeveloperDeploymentOperations } from "./DeveloperDeploymentOperations";
import { ProviderSchemaForm, SensitiveSchemaFields } from "./ProviderSchemaForm";

const STEP_COUNT = 6;

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
  const [step, setStep] = useState(1);
  const [draft, setDraft] = useState<ManagedProjectDraft>(initialDraft);
  const [workingSnapshot, setWorkingSnapshot] = useState(snapshot);
  const [controlStatus, setControlStatus] = useState(initialControlStatus);
  const [accounts, setAccounts] = useState<CloudflareAccount[]>([]);
  const [secretValues, setSecretValues] = useState<Record<string, string>>({});
  const [secretRevisions, setSecretRevisions] = useState<Record<string, string>>({});
  const [customOauth, setCustomOauth] = useState(false);
  const [customClientId, setCustomClientId] = useState("");
  const [customScopeCatalog, setCustomScopeCatalog] = useState("");
  const [plan, setPlan] = useState<GatewayPlan | null>(null);
  const [deploymentApplied, setDeploymentApplied] = useState(
    Boolean(initialControlStatus?.pendingDeployment),
  );
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [completed, setCompleted] = useState(false);

  const identityProviders = providers.filter((item) => item.kind === "identity");
  const entitlementProviders = providers.filter((item) => item.kind === "entitlement"
    && item.capabilities.includes("gateway_policy_projection_v1"));
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
  const lifecycleDeployment = controlStatus?.pendingDeployment?.deployment
    ? {
        target: controlStatus.pendingDeployment.deployment.target,
        versionId: controlStatus.pendingDeployment.deployment.versionId,
        endpoint: controlStatus.pendingDeployment.deployment.endpoint,
      }
    : workingSnapshot.verifiedDeployment ?? null;

  const updateControlStatus = (status: DeveloperControlStatus) => {
    setControlStatus(status);
    onControlStatus(status);
  };

  const refreshControl = async () => {
    const status = await loadDeveloperControlStatus();
    updateControlStatus(status);
    return status;
  };

  useEffect(() => {
    setWorkingSnapshot(snapshot);
  }, [snapshot]);

  useEffect(() => {
    if (controlStatus && !controlStatus.authorization.publicOauthClientAvailable) {
      setCustomOauth(true);
    }
  }, [controlStatus]);

  useEffect(() => {
    if (controlStatus?.pendingDeployment) setDeploymentApplied(true);
  }, [controlStatus?.pendingDeployment]);

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
    const phase = controlStatus?.authorization.phase;
    if (phase !== "awaiting_callback") return;
    const timer = window.setInterval(() => {
      void refreshControl().catch(() => undefined);
    }, 1_500);
    return () => window.clearInterval(timer);
  }, [controlStatus?.authorization.phase]);

  useEffect(() => {
    if (controlStatus?.authorization.phase !== "select_account") return;
    void listCloudflareAccounts()
      .then(setAccounts)
      .catch(() => setError(t("developer.release.errorAccounts")));
  }, [controlStatus?.authorization.phase, t]);

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
        [kind]: selectionFromDescriptor(descriptor, kind === "identity" ? {
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
    if (customOauth) {
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

  const selectAccount = (accountId: string) => run("account", async () => {
    await selectCloudflareAccount(accountId);
    const status = await refreshControl();
    if (status.authorization.phase !== "ready") {
      throw new Error(t("developer.release.errorAccountSelection"));
    }
  });

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
      configuredSlots,
      controlStatus?.sensitiveBindings ?? {},
      secretValues,
      secretRevisions,
      t("developer.release.errorSecrets"),
    );
    setSecretRevisions(Object.fromEntries(
      Object.entries(sensitiveInputs).map(([slot, input]) => [slot, input.revision]),
    ));
    setPlan(await planGateway({ project: latest, sensitiveInputs }));
    await refreshControl();
  });

  const apply = () => run("apply", async () => {
    if (!plan) throw new Error(t("developer.release.errorPlanRequired"));
    const result = await applyGateway(plan.planHash);
    setWorkingSnapshot(result.project);
    setDraft(result.project.project as ManagedProjectDraft);
    onProjectSaved(result.project);
    setPlan(null);
    setDeploymentApplied(true);
    await refreshControl();
  });

  const verify = () => run("verify", async () => {
    const result = await verifyGateway();
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
          <ProviderStep
            description={t("developer.release.identityStepDescription")}
            icon={<LockKeyhole aria-hidden="true" size={22} />}
            onChoose={(descriptor) => chooseProvider("identity", descriptor)}
            providers={identityProviders}
            selected={draft.providers.identity}
            title={t("developer.release.identityStepTitle")}
          />
        ) : null}
        {step === 2 && identityDescriptor ? (
          <section className="release-step-content">
            <StepHeading
              description={t("developer.release.identityConfigDescription")}
              icon={<ShieldCheck aria-hidden="true" size={22} />}
              title={t("developer.release.identityConfigTitle")}
            />
            <ProviderSchemaForm
              descriptor={identityDescriptor}
              onChange={(identity) => mutateDraft({
                ...draft,
                providers: { ...draft.providers, identity },
              })}
              selection={draft.providers.identity}
            />
            <AdvancedFields
              descriptor={identityDescriptor}
              selection={draft.providers.identity}
              onChange={(identity) => mutateDraft({
                ...draft,
                providers: { ...draft.providers, identity },
              })}
            />
            <div className="release-step-divider" />
            <h3>{t("developer.release.entitlementPlugin")}</h3>
            <p className="release-muted">{t("developer.release.entitlementDescription")}</p>
            <ProviderCards
              onChoose={(descriptor) => chooseProvider("entitlement", descriptor)}
              providers={entitlementProviders}
              selected={draft.providers.entitlement}
            />
          </section>
        ) : null}
        {step === 3 ? (
          <ProviderStep
            description={t("developer.release.gatewayStepDescription")}
            icon={<Cloud aria-hidden="true" size={22} />}
            onChoose={(descriptor) => chooseProvider("gateway", descriptor)}
            providers={gatewayProviders}
            selected={draft.providers.gateway}
            title={t("developer.release.gatewayStepTitle")}
          />
        ) : null}
        {step === 4 ? (
          <CloudflareAuthorizationStep
            accounts={accounts}
            busy={busy}
            controlStatus={controlStatus}
            customClientId={customClientId}
            customOauth={customOauth}
            customScopeCatalog={customScopeCatalog}
            onCancel={() => run("cancel-oauth", async () => {
              await cancelCloudflareConnection();
              await refreshControl();
            })}
            onConnect={connect}
            onCustomClientId={setCustomClientId}
            onCustomOauth={setCustomOauth}
            onCustomScopeCatalog={setCustomScopeCatalog}
            onSelectAccount={selectAccount}
          />
        ) : null}
        {step === 5 && entitlementDescriptor && gatewayDescriptor ? (
          <ModelAndLimitsStep
            configuredSlots={configuredSlots}
            draft={draft}
            entitlementDescriptor={entitlementDescriptor}
            gatewayDescriptor={gatewayDescriptor}
            onDraft={mutateDraft}
            onSecret={(slot, value) => {
              setSecretValues((current) => ({ ...current, [slot]: value }));
              setSecretRevisions((current) => ({ ...current, [slot]: newRevision() }));
              setPlan(null);
            }}
            secretValues={secretValues}
          />
        ) : null}
        {step === 6 ? (
          <>
            <DeployStep
              authorizationReady={authorizationReady}
              applied={deploymentApplied}
              bootstrapReady={bootstrap.discovery?.access.identity.mode === "required"}
              busy={busy}
              completed={completed || workingSnapshot.deploymentStatus === "ready"}
              identityState={identitySession.state}
              issues={visibleIssues}
              onApply={apply}
              onPlan={createPlan}
              onSave={save}
              onSignIn={() => run("identity", identitySession.start)}
              onVerify={verify}
              plan={plan}
              snapshot={workingSnapshot}
            />
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
          </>
        ) : null}

        <footer className="release-step-actions">
          <Button color="gray" disabled={step === 1 || busy !== null} onClick={() => setStep(step - 1)} variant="soft">
            <ArrowLeft aria-hidden="true" size={16} /> {t("common.back")}
          </Button>
          {step < STEP_COUNT ? (
            <Button disabled={!canContinue || busy !== null} onClick={() => setStep(step + 1)}>
              {t("common.continue")} <ArrowRight aria-hidden="true" size={16} />
            </Button>
          ) : null}
        </footer>
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

function ProviderStep({
  icon,
  title,
  description,
  providers,
  selected,
  onChoose,
}: {
  icon: ReactNode;
  title: string;
  description: string;
  providers: readonly DeveloperProviderDescriptor[];
  selected: ProviderSelection;
  onChoose: (descriptor: DeveloperProviderDescriptor) => void;
}) {
  return (
    <section className="release-step-content">
      <StepHeading description={description} icon={icon} title={title} />
      <ProviderCards onChoose={onChoose} providers={providers} selected={selected} />
    </section>
  );
}

function ProviderCards({ providers, selected, onChoose }: {
  providers: readonly DeveloperProviderDescriptor[];
  selected: ProviderSelection;
  onChoose: (descriptor: DeveloperProviderDescriptor) => void;
}) {
  const { t } = useI18n();
  return (
    <RadioCards.Root
      className="release-provider-cards"
      onValueChange={(id) => {
        const descriptor = providers.find((item) => item.provider_id === id);
        if (descriptor) onChoose(descriptor);
      }}
      value={selected.id}
    >
      {providers.map((provider) => (
        <RadioCards.Item key={provider.provider_id} value={provider.provider_id}>
          <div className="release-provider-choice">
            <div>
              <strong>{provider.display_name}</strong>
              <Badge color="gray" size="1">v{provider.provider_version}</Badge>
            </div>
            <Text as="p" color="gray" size="2">{provider.description}</Text>
            <span>{provider.capabilities.slice(0, 3).map((capability) => (
              <Badge color="blue" key={capability} size="1" variant="soft">
                {capability.replaceAll("_", " ")}
              </Badge>
            ))}</span>
            {provider.risk_notice ? <small>{t("developer.release.risk", { risk: provider.risk_notice })}</small> : null}
          </div>
        </RadioCards.Item>
      ))}
    </RadioCards.Root>
  );
}

function StepHeading({ icon, title, description }: { icon: ReactNode; title: string; description: string }) {
  return (
    <header className="release-step-heading">
      <span>{icon}</span><div><h2>{title}</h2><p>{description}</p></div>
    </header>
  );
}

function AdvancedFields({ descriptor, selection, onChange }: {
  descriptor: DeveloperProviderDescriptor;
  selection: ProviderSelection;
  onChange: (selection: ProviderSelection) => void;
}) {
  const { t } = useI18n();
  if (!descriptor.configuration_schema.public_fields.some((field) => field.advanced)) return null;
  return (
    <details className="release-advanced">
      <summary>{t("developer.release.advanced")}</summary>
      <ProviderSchemaForm advanced descriptor={descriptor} onChange={onChange} selection={selection} />
    </details>
  );
}

function CloudflareAuthorizationStep({
  accounts,
  busy,
  controlStatus,
  customClientId,
  customOauth,
  customScopeCatalog,
  onCancel,
  onConnect,
  onCustomClientId,
  onCustomOauth,
  onCustomScopeCatalog,
  onSelectAccount,
}: {
  accounts: readonly CloudflareAccount[];
  busy: string | null;
  controlStatus: DeveloperControlStatus | null;
  customClientId: string;
  customOauth: boolean;
  customScopeCatalog: string;
  onCancel: () => void;
  onConnect: () => void;
  onCustomClientId: (value: string) => void;
  onCustomOauth: (value: boolean) => void;
  onCustomScopeCatalog: (value: string) => void;
  onSelectAccount: (accountId: string) => void;
}) {
  const { t } = useI18n();
  const phase = controlStatus?.authorization.phase ?? "disconnected";
  return (
    <section className="release-step-content">
      <StepHeading
        description={t("developer.release.cloudflareDescription")}
        icon={<Cloud aria-hidden="true" size={22} />}
        title={t("developer.release.cloudflareTitle")}
      />
      <div className="release-oauth-card">
        <div className="release-oauth-status">
          <span className={`release-provider-status-icon ${phase === "ready" ? "is-ready" : ""}`}>
            {phase === "ready" ? <Check aria-hidden="true" size={18} /> : <ExternalLink aria-hidden="true" size={18} />}
          </span>
          <div><strong>{oauthTitle(phase, t)}</strong><Text as="p" color="gray" size="2">{oauthHint(phase, t)}</Text></div>
          <Badge color={phase === "ready" ? "green" : phase === "expired" ? "red" : "blue"}>{t(`developer.release.oauth.${phase}.label`)}</Badge>
        </div>
        {phase === "disconnected" || phase === "expired" ? (
          <>
            <label className="release-inline-toggle">
              <input checked={customOauth} onChange={(event) => onCustomOauth(event.target.checked)} type="checkbox" />
              <span><strong>{t("developer.release.customOauth")}</strong><small>{t("developer.release.customOauthHint")}</small></span>
            </label>
            {customOauth ? (
              <div className="release-schema-fields">
                <label className="release-field"><Text size="2" weight="medium">{t("developer.release.oauthClientId")}</Text><TextField.Root onChange={(event) => onCustomClientId(event.target.value)} value={customClientId} /></label>
                <label className="release-field"><Text size="2" weight="medium">{t("developer.release.scopeCatalog")}</Text><TextArea onChange={(event) => onCustomScopeCatalog(event.target.value)} placeholder="Workers Scripts Read=scope-id" value={customScopeCatalog} /><Text color="gray" size="1">{t("developer.release.scopeCatalogHint")}</Text></label>
              </div>
            ) : null}
            <Button disabled={busy !== null} onClick={onConnect} size="3">
              {busy === "oauth" ? <Spinner /> : <ExternalLink aria-hidden="true" size={16} />}
              {t("developer.release.connectCloudflare")}
            </Button>
          </>
        ) : null}
        {phase === "awaiting_callback" ? (
          <Button color="gray" disabled={busy !== null} onClick={onCancel} variant="soft">
            {busy === "cancel-oauth" ? <Spinner /> : <RotateCcw aria-hidden="true" size={16} />}
            {t("developer.release.cancelAuthorization")}
          </Button>
        ) : null}
        {phase === "select_account" ? (
          <label className="release-field">
            <Text size="2" weight="medium">{t("developer.release.cloudflareAccount")}</Text>
            <Select.Root disabled={busy !== null} onValueChange={onSelectAccount}>
              <Select.Trigger placeholder={t("developer.release.selectAccount")} />
              <Select.Content>{accounts.map((account) => (
                <Select.Item key={account.accountId} value={account.accountId}>
                  {account.displayName ?? account.accountId}
                </Select.Item>
              ))}</Select.Content>
            </Select.Root>
          </label>
        ) : null}
        {phase === "ready" ? (
          <dl className="release-facts"><Fact label={t("developer.release.accountId")} value={controlStatus?.authorization.accountId ?? "—"} /></dl>
        ) : null}
      </div>
    </section>
  );
}

function ModelAndLimitsStep({
  configuredSlots,
  draft,
  entitlementDescriptor,
  gatewayDescriptor,
  onDraft,
  onSecret,
  secretValues,
}: {
  configuredSlots: ReadonlySet<string>;
  draft: ManagedProjectDraft;
  entitlementDescriptor: DeveloperProviderDescriptor;
  gatewayDescriptor: DeveloperProviderDescriptor;
  onDraft: (draft: ManagedProjectDraft) => void;
  onSecret: (slot: string, value: string) => void;
  secretValues: Readonly<Record<string, string>>;
}) {
  const { t } = useI18n();
  const setProfile = (field: "endpointType" | "modelName", value: string) => onDraft({
    ...draft,
    modelAccess: { ...draft.modelAccess, profile: { ...draft.modelAccess.profile, [field]: value } },
  });
  return (
    <section className="release-step-content">
      <StepHeading
        description={t("developer.release.modelConfigDescription")}
        icon={<KeyRound aria-hidden="true" size={22} />}
        title={t("developer.release.modelConfigTitle")}
      />
      <div className="release-section-label"><strong>{t("developer.release.modelProfile")}</strong><span>{t("developer.release.publicConfiguration")}</span></div>
      <div className="release-schema-fields release-two-columns">
        <label className="release-field"><Text size="2" weight="medium">{t("developer.release.endpointType")}</Text><Select.Root onValueChange={(value) => setProfile("endpointType", value)} value={draft.modelAccess.profile.endpointType}><Select.Trigger /><Select.Content><Select.Item value="responses">Responses API</Select.Item><Select.Item value="chat_completions">Chat Completions</Select.Item><Select.Item value="completion">Completions</Select.Item></Select.Content></Select.Root></label>
        <label className="release-field">
          <span className="release-field-label">
            <Text size="2" weight="medium">{t("developer.release.modelName")}</Text>
            <Badge color="gray" size="1">{t("developer.release.required")}</Badge>
          </span>
          <TextField.Root
            aria-invalid={!draft.modelAccess.profile.modelName.trim()}
            onChange={(event) => setProfile("modelName", event.target.value)}
            required
            value={draft.modelAccess.profile.modelName}
          />
          {!draft.modelAccess.profile.modelName.trim() ? (
            <Text color="red" role="alert" size="1">
              {t("developer.release.modelNameRequired")}
            </Text>
          ) : null}
        </label>
      </div>
      <ProviderSchemaForm descriptor={gatewayDescriptor} onChange={(gateway) => onDraft({ ...draft, providers: { ...draft.providers, gateway } })} selection={draft.providers.gateway} />
      <AdvancedFields descriptor={gatewayDescriptor} onChange={(gateway) => onDraft({ ...draft, providers: { ...draft.providers, gateway } })} selection={draft.providers.gateway} />
      <div className="release-step-divider" />
      <div className="release-section-label"><strong>{t("developer.release.entitlementService")}</strong><span>{entitlementDescriptor.display_name}</span></div>
      <ProviderSchemaForm descriptor={entitlementDescriptor} onChange={(entitlement) => onDraft({ ...draft, providers: { ...draft.providers, entitlement } })} selection={draft.providers.entitlement} />
      <AdvancedFields descriptor={entitlementDescriptor} onChange={(entitlement) => onDraft({ ...draft, providers: { ...draft.providers, entitlement } })} selection={draft.providers.entitlement} />
      <div className="release-step-divider" />
      <div className="release-section-label"><strong>{t("developer.release.secrets")}</strong><span>{t("developer.release.secretsHint")}</span></div>
      <SensitiveSchemaFields fields={gatewayDescriptor.configuration_schema.sensitive_fields.map((field) => ({ ...field, id: `gateway.${field.id}` }))} configured={configuredSlots} onChange={onSecret} values={secretValues} />
      <SensitiveSchemaFields fields={entitlementDescriptor.configuration_schema.sensitive_fields.map((field) => ({ ...field, id: `entitlement.${field.id}` }))} configured={configuredSlots} onChange={onSecret} values={secretValues} />
    </section>
  );
}

function DeployStep({
  authorizationReady,
  applied,
  bootstrapReady,
  busy,
  completed,
  identityState,
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
  issues: readonly string[];
  onApply: () => void;
  onPlan: () => void;
  onSave: () => void;
  onSignIn: () => void;
  onVerify: () => void;
  plan: GatewayPlan | null;
  snapshot: DeveloperProjectSnapshot;
}) {
  const { t } = useI18n();
  return (
    <section className="release-step-content">
      <StepHeading description={t("developer.release.deployDescription")} icon={<PackageCheck aria-hidden="true" size={22} />} title={t("developer.release.deployTitle")} />
      {issues.length > 0 ? <Callout.Root color="orange"><TriangleAlert aria-hidden="true" /><Callout.Text>{issues[0]}</Callout.Text></Callout.Root> : null}
      <div className="release-operation-list">
        <OperationRow action={<Button disabled={busy !== null || issues.length > 0} onClick={onSave} variant="soft">{busy === "save" ? <Spinner /> : null}{t("developer.release.saveProject")}</Button>} done={issues.length === 0} title={t("developer.release.operationSave")} />
        <OperationRow action={identityState === "signed_in" ? <Badge color="green">{t("identity.signedIn")}</Badge> : <Button disabled={busy !== null || !bootstrapReady} onClick={onSignIn} variant="soft">{busy === "identity" ? <Spinner /> : null}{t("developer.release.signInTestUser")}</Button>} done={identityState === "signed_in"} title={t("developer.release.operationIdentity")} />
        <OperationRow action={plan ? <Badge color="blue">{plan.operations.length} {t("developer.release.operations")}</Badge> : <Button disabled={busy !== null || !authorizationReady || issues.length > 0} onClick={onPlan}>{busy === "plan" ? <Spinner /> : null}{t("developer.release.createPlan")}</Button>} done={plan !== null || applied || completed} title={t("developer.release.operationPlan")} />
        <OperationRow action={applied || completed ? <Badge color="green">{t("developer.release.deployed")}</Badge> : <Button disabled={busy !== null || !plan} onClick={onApply}>{busy === "apply" ? <Spinner /> : null}{t("developer.release.deployGateway")}</Button>} done={applied || completed} title={t("developer.release.operationDeploy")} />
        <OperationRow action={completed ? <Badge color="green">{t("developer.release.verified")}</Badge> : <Button disabled={busy !== null || !applied || identityState !== "signed_in"} onClick={onVerify}>{busy === "verify" ? <Spinner /> : null}{t("developer.release.verifyGateway")}</Button>} done={completed} title={t("developer.release.operationVerify")} />
      </div>
      {plan ? (
        <div className="release-plan-preview"><div><strong>{t("developer.release.planPreview")}</strong><Badge color={plan.drift.status === "in_sync" ? "green" : "orange"}>{plan.drift.status.replaceAll("_", " ")}</Badge></div><ul>{plan.operations.map((operation, index) => <li key={`${operation.kind}-${operation.resource}-${index}`}><span>{operation.kind.replaceAll("_", " ")}</span><code>{operation.resource}</code>{operation.destructive ? <Badge color="red">{t("developer.release.destructive")}</Badge> : null}</li>)}</ul></div>
      ) : null}
      {completed ? <Callout.Root color="green"><ShieldCheck aria-hidden="true" /><Callout.Text>{t("developer.release.verificationComplete")}</Callout.Text></Callout.Root> : null}
    </section>
  );
}

function OperationRow({ title, done, action }: { title: string; done: boolean; action: ReactNode }) {
  return <div className="release-operation-row"><span className={done ? "is-done" : ""}>{done ? <Check aria-hidden="true" size={15} /> : null}</span><strong>{title}</strong><div>{action}</div></div>;
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

function stepReady(
  step: number,
  draft: ManagedProjectDraft,
  providers: readonly DeveloperProviderDescriptor[],
  status: DeveloperControlStatus | null,
  configured: ReadonlySet<string>,
  values: Readonly<Record<string, string>>,
): boolean {
  if (step === 1) return providerBySelection(providers, draft.providers.identity) !== null;
  if (step === 2) return selectionComplete(draft.providers.identity, providers)
    && selectionComplete(draft.providers.entitlement, providers);
  if (step === 3) return selectionComplete(draft.providers.gateway, providers);
  if (step === 4) return status?.authorization.phase === "ready"
    && Boolean(draft.deployment.cloudflare.accountId);
  if (step === 5) return validateManagedDraft(draft, providers).length === 0
    && ["gateway.upstreamApiKey", "entitlement.serviceCredential"]
      .every((slot) => configured.has(slot) || Boolean(values[slot]?.trim()));
  return true;
}

function selectionComplete(
  selection: ProviderSelection,
  providers: readonly DeveloperProviderDescriptor[],
): boolean {
  const descriptor = providerBySelection(providers, selection);
  if (!descriptor) return false;
  return descriptor.configuration_schema.public_fields
    .filter((field) => field.required && (!field.visible_when
      || selection.publicConfig[field.visible_when.field_id] === field.visible_when.equals))
    .every((field) => present(selection.publicConfig[field.id]));
}

function present(value: unknown): boolean {
  if (typeof value === "string") return value.trim().length > 0;
  if (Array.isArray(value)) return value.length > 0;
  if (value && typeof value === "object") return Object.keys(value).length > 0;
  return value !== undefined && value !== null;
}

function logicalConfiguredSlots(bindings: Readonly<Record<string, string>>): ReadonlySet<string> {
  const slots = new Set(Object.keys(bindings));
  if (bindings.UPSTREAM_API_KEY) slots.add("gateway.upstreamApiKey");
  if (bindings.ENTITLEMENT_PROJECTION_SECRET) slots.add("entitlement.serviceCredential");
  return slots;
}

function makeSensitiveInputs(
  configured: ReadonlySet<string>,
  bindings: Readonly<Record<string, string>>,
  values: Readonly<Record<string, string>>,
  revisions: Readonly<Record<string, string>>,
  missingMessage: string,
): Record<string, SensitivePlanInput> {
  const physicalRevision = (slot: string) => slot === "gateway.upstreamApiKey"
    ? bindings[slot] ?? bindings.UPSTREAM_API_KEY
    : bindings[slot] ?? bindings.ENTITLEMENT_PROJECTION_SECRET;
  return Object.fromEntries(["gateway.upstreamApiKey", "entitlement.serviceCredential"].map((slot) => {
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
    sensitiveBindings: {},
    pendingDeployment: null,
  };
}

function stepTitle(step: number, t: (key: string) => string): string {
  return t(`developer.release.step${step}Title`);
}

function stepHint(step: number, t: (key: string) => string): string {
  return t(`developer.release.step${step}Hint`);
}

function oauthTitle(phase: string, t: (key: string) => string): string {
  return t(`developer.release.oauth.${phase}.title`);
}

function oauthHint(phase: string, t: (key: string) => string): string {
  return t(`developer.release.oauth.${phase}.hint`);
}
