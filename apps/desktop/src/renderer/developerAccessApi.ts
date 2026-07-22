import type {
  DeveloperAccessBundleDestroyPlan,
  DeveloperAccessBundleDestroyReceipt,
  DeveloperAccessBundleInspectReceipt,
  DeveloperAccessBundleLifecycleResourceReceipt,
  DeveloperAccessBundleMutationOutcome,
  DeveloperAccessBundleMutationReceipt,
  DeveloperAccessBundlePlan,
  DeveloperAccessBundleProjectUpdate,
  DeveloperAccessBundleReceipt,
  DeveloperAccessBundleTestReceipt,
  DeveloperAccessBundleVerificationUpdate,
  DeveloperAccessOperation,
  DeveloperDeploymentProjectUpdate,
  DeveloperPendingAccessBundle,
  DeveloperPendingDeployment,
  DeveloperGatewayTestProjectUpdate,
} from "../shared/developerAccess";
import type { DeveloperProjectSnapshot } from "../shared/developerProject";

export type CloudflareAuthorizationPhase =
  | "disconnected"
  | "awaiting_callback"
  | "select_account"
  | "ready"
  | "expired";

export type FirebaseAuthorizationPhase =
  | "disconnected"
  | "awaiting_callback"
  | "select_project"
  | "ready"
  | "expired";

export type FirebaseAuthorizationStatus = Readonly<{
  providerId: string;
  phase: FirebaseAuthorizationPhase;
  projectId: string | null;
  expiresAtUnixMs: number | null;
  publicOauthClientAvailable: boolean;
}>;

export type DeveloperControlStatus = Readonly<{
  authorization: Readonly<{
    providerId: string;
    phase: CloudflareAuthorizationPhase;
    accountId: string | null;
    expiresAtUnixMs: number | null;
    publicOauthClientAvailable: boolean;
  }>;
  firebaseAuthorization?: FirebaseAuthorizationStatus;
  gatewayTemplate: Readonly<{ version: string; sha256: string }> | null;
  entitlementTemplate: Readonly<{ version: string; sha256: string }> | null;
  sensitiveBindings: Readonly<Record<string, string>>;
  pendingDeployment: DeveloperPendingDeployment | null;
  pendingAccessBundle: DeveloperPendingAccessBundle | null;
}>;

export type CloudflareAccount = Readonly<{
  accountId: string;
  displayName: string | null;
  providerId: string;
}>;

export type FirebaseProject = Readonly<{
  projectId: string;
  projectNumber: string;
  displayName: string;
}>;

export type FirebaseConfigurationReceipt = Readonly<{
  projectId: string;
  displayName: string;
  publicConfig: Readonly<{
    projectId: string;
    firebaseWebKey: string;
    webApplicationId: string;
    authDomain?: string;
  }>;
}>;

export type GatewayTarget = Readonly<{
  accountId: string;
  deploymentId: string;
  workerName: string;
  environment?: string;
}>;

export type GatewayPlan = Readonly<{
  planHash: string;
  target: GatewayTarget;
  operations: readonly Readonly<{
    kind: string;
    resource: string;
    destructive: boolean;
  }>[];
  drift: Readonly<{
    status: string;
    differences: readonly unknown[];
  }>;
  expiresAtUnixMs: number;
}>;

export type GatewayObservation = Readonly<{
  target: GatewayTarget;
  reachability: string;
  remoteVersion: string | null;
  remoteEtag: string | null;
  observedDesiredHash: string | null;
  activeArtifactHash: string | null;
  endpoint: string | null;
  gatewayProtocolVersion: string | null;
  d1MigrationStatus: string | null;
  workersDevReady: boolean | null;
  observedAtUnixMs: number;
}>;

export type GatewayMutationUpdate = Readonly<{
  deployment: DeveloperDeploymentProjectUpdate["deployment"];
  project: DeveloperProjectSnapshot;
  operation: Readonly<{
    kind: "rotate" | "rollback";
    operationId: string;
    completedAtUnixMs: number;
    bindingName?: string;
    configuredRevision?: string;
    previousVersionId?: string;
    versionId?: string;
    boundary?: string;
  }>;
}>;

export type GatewayDestroyPlan = Readonly<{
  planHash: string;
  target: GatewayTarget;
  resources: readonly string[];
  expiresAtUnixMs: number;
}>;

export type GatewayDestroyUpdate = Readonly<{
  deletedResources: readonly string[];
  operationId: string;
  completedAtUnixMs: number;
  project: DeveloperProjectSnapshot;
}>;

export type AccessBundleMutationUpdate = Readonly<{
  mutation: DeveloperAccessBundleMutationReceipt;
  project: DeveloperProjectSnapshot;
}>;

export type AccessBundleDestroyUpdate = Readonly<{
  destroy: DeveloperAccessBundleDestroyReceipt;
  project: DeveloperProjectSnapshot;
}>;

export type SensitivePlanInput = Readonly<{
  revision: string;
  value?: string;
}>;

export async function loadDeveloperControlStatus(): Promise<DeveloperControlStatus> {
  return parseControlStatus(await request("status"));
}

export async function connectCloudflarePublic(): Promise<void> {
  await request("cloudflare.connect", { client: { mode: "agent_weave_public" } });
}

export async function connectCloudflareCustom(input: {
  clientId: string;
  scopeCatalog: Record<string, string>;
}): Promise<void> {
  await request("cloudflare.connect", {
    client: { mode: "custom", clientId: input.clientId, scopeCatalog: input.scopeCatalog },
  });
}

export async function cancelCloudflareConnection(): Promise<void> {
  await request("cloudflare.cancel");
}

export async function disconnectCloudflare(): Promise<void> {
  await request("cloudflare.disconnect");
}

export async function listCloudflareAccounts(): Promise<CloudflareAccount[]> {
  const value = await request("cloudflare.accounts");
  if (!Array.isArray(value)) throw new Error("Cloudflare account response is invalid");
  return value.map(parseAccount);
}

export async function selectCloudflareAccount(accountId: string): Promise<void> {
  await request("cloudflare.selectAccount", { accountId });
}

export async function connectFirebasePublic(): Promise<void> {
  await request("firebase.connect", { client: { mode: "agent_weave_public" } });
}

export async function connectFirebaseCustom(input: {
  clientId: string;
  clientSecret?: string;
}): Promise<void> {
  await request("firebase.connect", {
    client: {
      mode: "custom",
      clientId: input.clientId,
      ...(input.clientSecret ? { clientSecret: input.clientSecret } : {}),
    },
  });
}

export async function cancelFirebaseConnection(): Promise<void> {
  await request("firebase.cancel");
}

export async function disconnectFirebase(): Promise<void> {
  await request("firebase.disconnect");
}

export async function listFirebaseProjects(): Promise<FirebaseProject[]> {
  const value = await request("firebase.projects");
  if (!Array.isArray(value)) throw new Error("Firebase project response is invalid");
  return value.map(parseFirebaseProject);
}

export async function configureFirebaseProject(
  projectId: string,
): Promise<FirebaseConfigurationReceipt> {
  return parseFirebaseReceipt(await request("firebase.configure", { projectId }));
}

export async function planGateway(input: {
  project: DeveloperProjectSnapshot;
  sensitiveInputs: Record<string, SensitivePlanInput>;
}): Promise<GatewayPlan> {
  return parsePlan(await request("gateway.plan", {
    expectedProjectRevision: input.project.revision,
    sensitiveInputs: input.sensitiveInputs,
    idempotencyKey: crypto.randomUUID(),
  }));
}

export async function applyGateway(planHash: string): Promise<DeveloperDeploymentProjectUpdate> {
  return parseDeploymentUpdate(await request("gateway.apply", { planHash }));
}

export async function verifyGateway(): Promise<DeveloperGatewayTestProjectUpdate> {
  return parseTestUpdate(await request("gateway.test"));
}

export async function planAccessBundle(input: {
  project: DeveloperProjectSnapshot;
  sensitiveInputs: Record<string, SensitivePlanInput>;
}): Promise<DeveloperAccessBundlePlan> {
  return parseAccessPlan(await request("access.plan", {
    expectedProjectRevision: input.project.revision,
    sensitiveInputs: input.sensitiveInputs,
    idempotencyKey: crypto.randomUUID(),
  }));
}

export async function applyAccessBundle(
  planHash: string,
): Promise<DeveloperAccessBundleProjectUpdate> {
  const update = record(await request("access.apply", { planHash }));
  return Object.freeze({
    bundle: parseAccessBundleReceipt(update.bundle),
    project: update.project as DeveloperProjectSnapshot,
  });
}

export async function verifyAccessBundle(): Promise<DeveloperAccessBundleVerificationUpdate> {
  const update = record(await request("access.test"));
  return Object.freeze({
    test: parseAccessBundleTest(update.test),
    project: update.project as DeveloperProjectSnapshot,
  });
}

export async function inspectAccessBundle(): Promise<DeveloperAccessBundleInspectReceipt> {
  return parseAccessBundleInspect(await request("access.inspect"));
}

export async function rotateAccessBundleProjectionSecret(): Promise<AccessBundleMutationUpdate> {
  return parseAccessBundleMutationUpdate(await request("access.rotate"), true);
}

export async function rollbackAccessBundle(input: {
  gatewayVersionId: string;
  entitlementVersionId: string;
}): Promise<AccessBundleMutationUpdate> {
  return parseAccessBundleMutationUpdate(await request("access.rollback", input), false);
}

export async function planAccessBundleDestroy(): Promise<DeveloperAccessBundleDestroyPlan> {
  return parseAccessBundleDestroyPlan(await request("access.destroyPlan"));
}

export async function destroyAccessBundle(
  planHash: string,
  confirmCommerceProjectionRebuild: boolean,
): Promise<AccessBundleDestroyUpdate> {
  const update = record(await request("access.destroyApply", {
    planHash,
    confirmCommerceProjectionRebuild,
  }));
  return Object.freeze({
    destroy: parseAccessBundleDestroyReceipt(update.destroy),
    project: update.project as DeveloperProjectSnapshot,
  });
}

export async function inspectGateway(target: GatewayTarget): Promise<GatewayObservation> {
  return parseObservation(await request("gateway.inspect", target));
}

export async function rotateGatewaySecret(input: {
  target: GatewayTarget;
  bindingName: string;
  value: string;
  expectedRemoteVersion?: string;
  expectedRemoteEtag?: string;
}): Promise<GatewayMutationUpdate> {
  return parseMutationUpdate(await request("gateway.rotate", {
    target: input.target,
    bindingName: input.bindingName,
    revision: `ui-${crypto.randomUUID()}`,
    value: input.value,
    idempotencyKey: crypto.randomUUID(),
    ...(input.expectedRemoteVersion ? { expectedRemoteVersion: input.expectedRemoteVersion } : {}),
    ...(input.expectedRemoteEtag ? { expectedRemoteEtag: input.expectedRemoteEtag } : {}),
  }));
}

export async function rollbackGateway(input: {
  target: GatewayTarget;
  restoreVersion: string;
  expectedRemoteVersion?: string;
  expectedRemoteEtag?: string;
}): Promise<GatewayMutationUpdate> {
  return parseMutationUpdate(await request("gateway.rollback", {
    target: input.target,
    restoreVersion: input.restoreVersion,
    idempotencyKey: crypto.randomUUID(),
    ...(input.expectedRemoteVersion ? { expectedRemoteVersion: input.expectedRemoteVersion } : {}),
    ...(input.expectedRemoteEtag ? { expectedRemoteEtag: input.expectedRemoteEtag } : {}),
  }));
}

export async function planGatewayDestroy(input: {
  target: GatewayTarget;
  expectedRemoteVersion?: string;
  expectedRemoteEtag?: string;
}): Promise<GatewayDestroyPlan> {
  return parseDestroyPlan(await request("gateway.destroyPlan", {
    target: input.target,
    idempotencyKey: crypto.randomUUID(),
    ...(input.expectedRemoteVersion ? { expectedRemoteVersion: input.expectedRemoteVersion } : {}),
    ...(input.expectedRemoteEtag ? { expectedRemoteEtag: input.expectedRemoteEtag } : {}),
  }));
}

export async function destroyGateway(planHash: string): Promise<GatewayDestroyUpdate> {
  return parseDestroyUpdate(await request("gateway.destroyApply", { planHash }));
}

export async function loadDeveloperProject(): Promise<DeveloperProjectSnapshot> {
  const api = window.agentWeave?.developerProject;
  if (!api) throw new Error("Developer project API is unavailable");
  return api.load();
}

export async function saveDeveloperProject(
  snapshot: DeveloperProjectSnapshot,
  project: unknown,
): Promise<DeveloperProjectSnapshot> {
  const api = window.agentWeave?.developerProject;
  if (!api) throw new Error("Developer project API is unavailable");
  return api.save({ expectedRevision: snapshot.revision, project });
}

export async function packageDeveloperProject(): Promise<{
  outputPath: string;
  summary: string;
}> {
  const api = window.agentWeave?.developerProject;
  if (!api) throw new Error("Developer project API is unavailable");
  return api.packageApp();
}

export async function showDeveloperPackage(): Promise<void> {
  const api = window.agentWeave?.developerProject;
  if (!api) throw new Error("Developer project API is unavailable");
  await api.showOutput();
}

async function request(operation: DeveloperAccessOperation, input?: unknown): Promise<unknown> {
  const api = window.agentWeave?.developerAccess;
  if (!api) throw new Error("Developer access API is unavailable");
  return api.request(operation, input);
}

function parseControlStatus(value: unknown): DeveloperControlStatus {
  const root = record(value);
  const authorization = record(root.authorization);
  const phase = text(authorization.phase);
  if (!new Set<CloudflareAuthorizationPhase>([
    "disconnected",
    "awaiting_callback",
    "select_account",
    "ready",
    "expired",
  ]).has(phase as CloudflareAuthorizationPhase)) throw new Error("Cloudflare status is invalid");
  const bindings = record(root.sensitiveBindings);
  const firebaseAuthorization = root.firebaseAuthorization === undefined
    ? undefined
    : parseFirebaseAuthorization(root.firebaseAuthorization);
  return Object.freeze({
    authorization: Object.freeze({
      providerId: text(authorization.providerId),
      phase: phase as CloudflareAuthorizationPhase,
      accountId: nullableText(authorization.accountId),
      expiresAtUnixMs: nullableInteger(authorization.expiresAtUnixMs),
      publicOauthClientAvailable: boolean(authorization.publicOauthClientAvailable),
    }),
    ...(firebaseAuthorization ? { firebaseAuthorization } : {}),
    gatewayTemplate: root.gatewayTemplate == null
      ? null
      : Object.freeze({
          version: text(record(root.gatewayTemplate).version),
          sha256: text(record(root.gatewayTemplate).sha256),
        }),
    entitlementTemplate: root.entitlementTemplate == null
      ? null
      : Object.freeze({
          version: text(record(root.entitlementTemplate).version),
          sha256: text(record(root.entitlementTemplate).sha256),
        }),
    sensitiveBindings: Object.freeze(Object.fromEntries(
      Object.entries(bindings).map(([name, revision]) => [name, text(revision)]),
    )),
    pendingDeployment: root.pendingDeployment == null
      ? null
      : parsePendingDeployment(root.pendingDeployment),
    pendingAccessBundle: root.pendingAccessBundle == null
      ? null
      : Object.freeze({
          bundle: parseAccessBundleReceipt(record(root.pendingAccessBundle).bundle),
          projectRevision: text(record(root.pendingAccessBundle).projectRevision),
        }),
  });
}

function parseAccessPlan(value: unknown): DeveloperAccessBundlePlan {
  const plan = record(value);
  if (!Array.isArray(plan.resources)) throw new Error("Access plan response is invalid");
  return Object.freeze({
    schemaVersion: integer(plan.schemaVersion),
    bundleId: text(plan.bundleId),
    desiredHash: text(plan.desiredHash),
    planHash: text(plan.planHash),
    resources: Object.freeze(plan.resources.map((candidate) => {
      const resource = record(candidate);
      const operations = Array.isArray(resource.operations) ? resource.operations : [];
      const dependencies = Array.isArray(resource.dependencies) ? resource.dependencies : [];
      return Object.freeze({
        resourceId: text(resource.resourceId),
        kind: text(resource.kind),
        purpose: text(resource.purpose),
        dependencies: Object.freeze(dependencies.map(text)),
        ownership: text(resource.ownership) as "exclusive" | "shared",
        target: parseTarget(resource.target),
        operations: Object.freeze(operations.map((entry) => {
          const operation = record(entry);
          return Object.freeze({
            kind: text(operation.kind),
            resource: text(operation.resource),
            destructive: boolean(operation.destructive),
          });
        })),
        drift: resource.drift ?? null,
      });
    })),
    expiresAtUnixMs: integer(plan.expiresAtUnixMs),
  });
}

function parseAccessBundleReceipt(value: unknown): DeveloperAccessBundleReceipt {
  const receipt = record(value);
  const resources = record(receipt.resources);
  return Object.freeze({
    schemaVersion: integer(receipt.schemaVersion),
    providerId: text(receipt.providerId),
    providerVersion: text(receipt.providerVersion),
    bundleId: text(receipt.bundleId),
    planHash: text(receipt.planHash),
    operationId: text(receipt.operationId),
    outcome: text(receipt.outcome) as DeveloperAccessBundleReceipt["outcome"],
    resources: Object.freeze(Object.fromEntries(Object.entries(resources).map(([id, candidate]) => {
      const resource = record(candidate);
      return [id, Object.freeze({
        resourceId: text(resource.resourceId),
        status: text(resource.status) as DeveloperAccessBundleReceipt["resources"][string]["status"],
        target: parseTarget(resource.target),
        versionId: nullableText(resource.versionId),
        previousVersionId: nullableText(resource.previousVersionId),
        endpoint: nullableText(resource.endpoint),
        errorCode: nullableText(resource.errorCode),
        safeMessage: nullableText(resource.safeMessage),
      })];
    }))),
    completedAtUnixMs: integer(receipt.completedAtUnixMs),
  });
}

function parseAccessBundleTest(value: unknown): DeveloperAccessBundleTestReceipt {
  const receipt = record(value);
  const parseGatewayTest = (candidate: unknown) => {
    const test = record(candidate);
    return Object.freeze({
      target: parseTarget(test.target),
      protocolVersion: text(test.protocolVersion),
      remoteVersion: text(test.remoteVersion),
      testedAtUnixMs: integer(test.testedAtUnixMs),
    });
  };
  const commerce = receipt.commerce === null ? null : (() => {
    const verification = record(receipt.commerce);
    if (!Array.isArray(verification.capabilities)) {
      throw new Error("Commerce verification response is invalid");
    }
    return Object.freeze({
      databaseId: text(verification.databaseId),
      migrationHash: text(verification.migrationHash),
      capabilities: Object.freeze(verification.capabilities.map(text)),
      webhookVerifiedAtUnixMs: nullableInteger(verification.webhookVerifiedAtUnixMs),
      portalVerifiedAtUnixMs: nullableInteger(verification.portalVerifiedAtUnixMs),
    });
  })();
  return Object.freeze({
    gateway: parseGatewayTest(receipt.gateway),
    entitlementPolicy: parseGatewayTest(receipt.entitlementPolicy),
    commerce,
    projectionSecretRevision: text(receipt.projectionSecretRevision),
    testedAtUnixMs: integer(receipt.testedAtUnixMs),
  });
}

function parseFirebaseAuthorization(value: unknown): FirebaseAuthorizationStatus {
  const authorization = record(value);
  const phase = text(authorization.phase);
  if (!new Set<FirebaseAuthorizationPhase>([
    "disconnected",
    "awaiting_callback",
    "select_project",
    "ready",
    "expired",
  ]).has(phase as FirebaseAuthorizationPhase)) throw new Error("Firebase status is invalid");
  return Object.freeze({
    providerId: text(authorization.providerId),
    phase: phase as FirebaseAuthorizationPhase,
    projectId: nullableText(authorization.projectId),
    expiresAtUnixMs: nullableInteger(authorization.expiresAtUnixMs),
    publicOauthClientAvailable: boolean(authorization.publicOauthClientAvailable),
  });
}

function parseFirebaseProject(value: unknown): FirebaseProject {
  const project = record(value);
  return Object.freeze({
    projectId: text(project.projectId),
    projectNumber: text(project.projectNumber),
    displayName: text(project.displayName),
  });
}

function parseFirebaseReceipt(value: unknown): FirebaseConfigurationReceipt {
  const receipt = record(value);
  const config = record(receipt.publicConfig);
  return Object.freeze({
    projectId: text(receipt.projectId),
    displayName: text(receipt.displayName),
    publicConfig: Object.freeze({
      projectId: text(config.projectId),
      firebaseWebKey: text(config.firebaseWebKey),
      webApplicationId: text(config.webApplicationId),
      ...(config.authDomain === undefined ? {} : { authDomain: text(config.authDomain) }),
    }),
  });
}

function parsePendingDeployment(value: unknown): DeveloperPendingDeployment {
  const pending = record(value);
  return Object.freeze({
    deployment: parseDeployment(pending.deployment),
    projectRevision: text(pending.projectRevision),
  });
}

function parseAccount(value: unknown): CloudflareAccount {
  const item = record(value);
  return Object.freeze({
    accountId: text(item.accountId),
    displayName: nullableText(item.displayName),
    providerId: text(item.providerId),
  });
}

function parsePlan(value: unknown): GatewayPlan {
  const plan = record(value);
  const operations = Array.isArray(plan.operations) ? plan.operations : null;
  if (!operations) throw new Error("Gateway plan response is invalid");
  return Object.freeze({
    planHash: text(plan.planHash),
    target: parseTarget(plan.target),
    operations: Object.freeze(operations.map((operation) => {
      const item = record(operation);
      return Object.freeze({
        kind: text(item.kind),
        resource: text(item.resource),
        destructive: boolean(item.destructive),
      });
    })),
    drift: Object.freeze({
      status: text(record(plan.drift).status),
      differences: Object.freeze(Array.isArray(record(plan.drift).differences)
        ? [...record(plan.drift).differences as unknown[]]
        : []),
    }),
    expiresAtUnixMs: integer(plan.expiresAtUnixMs),
  });
}

function parseObservation(value: unknown): GatewayObservation {
  const observation = record(value);
  return Object.freeze({
    target: parseTarget(observation.target),
    reachability: text(observation.reachability),
    remoteVersion: nullableText(observation.remoteVersion),
    remoteEtag: nullableText(observation.remoteEtag),
    observedDesiredHash: nullableText(observation.observedDesiredHash),
    activeArtifactHash: nullableText(observation.activeArtifactHash),
    endpoint: nullableText(observation.endpoint),
    gatewayProtocolVersion: nullableText(observation.gatewayProtocolVersion),
    d1MigrationStatus: nullableText(observation.d1MigrationStatus),
    workersDevReady: nullableBoolean(observation.workersDevReady),
    observedAtUnixMs: integer(observation.observedAtUnixMs),
  });
}

function parseMutationUpdate(value: unknown): GatewayMutationUpdate {
  const update = record(value);
  const operation = record(update.operation);
  const kind = text(operation.kind);
  if (kind !== "rotate" && kind !== "rollback") {
    throw new Error("Gateway mutation response is invalid");
  }
  return Object.freeze({
    deployment: parseDeployment(update.deployment),
    project: update.project as DeveloperProjectSnapshot,
    operation: Object.freeze({
      kind,
      operationId: text(operation.operationId),
      completedAtUnixMs: integer(operation.completedAtUnixMs),
      ...(operation.bindingName === undefined ? {} : { bindingName: text(operation.bindingName) }),
      ...(operation.configuredRevision === undefined
        ? {}
        : { configuredRevision: text(operation.configuredRevision) }),
      ...(operation.previousVersionId === undefined
        ? {}
        : { previousVersionId: text(operation.previousVersionId) }),
      ...(operation.versionId === undefined ? {} : { versionId: text(operation.versionId) }),
      ...(operation.boundary === undefined ? {} : { boundary: text(operation.boundary) }),
    }),
  });
}

function parseDestroyPlan(value: unknown): GatewayDestroyPlan {
  const plan = record(value);
  if (!Array.isArray(plan.resources)) throw new Error("Gateway destroy plan is invalid");
  return Object.freeze({
    planHash: text(plan.planHash),
    target: parseTarget(plan.target),
    resources: Object.freeze(plan.resources.map(text)),
    expiresAtUnixMs: integer(plan.expiresAtUnixMs),
  });
}

function parseDestroyUpdate(value: unknown): GatewayDestroyUpdate {
  const update = record(value);
  const receipt = record(update.destroy);
  if (!Array.isArray(receipt.deletedResources)) {
    throw new Error("Gateway destroy response is invalid");
  }
  return Object.freeze({
    deletedResources: Object.freeze(receipt.deletedResources.map(text)),
    operationId: text(receipt.operationId),
    completedAtUnixMs: integer(receipt.completedAtUnixMs),
    project: update.project as DeveloperProjectSnapshot,
  });
}

function parseDeploymentUpdate(value: unknown): DeveloperDeploymentProjectUpdate {
  const update = record(value);
  return {
    deployment: parseDeployment(update.deployment),
    project: update.project as DeveloperProjectSnapshot,
  };
}

function parseDeployment(value: unknown): DeveloperDeploymentProjectUpdate["deployment"] {
  const deployment = record(value);
  return Object.freeze({
    providerId: text(deployment.providerId),
    providerVersion: text(deployment.providerVersion),
    target: parseTarget(deployment.target),
    outcome: text(deployment.outcome) as DeveloperDeploymentProjectUpdate["deployment"]["outcome"],
    previousVersionId: nullableText(deployment.previousVersionId),
    versionId: text(deployment.versionId),
    endpoint: text(deployment.endpoint),
    operationId: text(deployment.operationId),
    completedAtUnixMs: integer(deployment.completedAtUnixMs),
  });
}

function parseTestUpdate(value: unknown): DeveloperGatewayTestProjectUpdate {
  const update = record(value);
  const test = record(update.test);
  return {
    test: {
      target: parseTarget(test.target),
      protocolVersion: text(test.protocolVersion),
      remoteVersion: text(test.remoteVersion),
      testedAtUnixMs: integer(test.testedAtUnixMs),
    },
    project: update.project as DeveloperProjectSnapshot,
  };
}

function parseAccessBundleInspect(value: unknown): DeveloperAccessBundleInspectReceipt {
  const receipt = record(value);
  const outcome = text(receipt.outcome);
  if (!new Set(["ready", "partial", "unavailable"]).has(outcome)) {
    throw new Error("Access bundle inspection response is invalid");
  }
  const resources = record(receipt.resources);
  return Object.freeze({
    schemaVersion: integer(receipt.schemaVersion),
    bundleId: text(receipt.bundleId),
    outcome: outcome as DeveloperAccessBundleInspectReceipt["outcome"],
    resources: Object.freeze(Object.fromEntries(Object.entries(resources).map(([id, candidate]) => {
      const resource = record(candidate);
      return [id, Object.freeze({
        resourceId: text(resource.resourceId),
        observation: resource.observation === null ? null : parseAccessObservation(resource.observation),
        errorCode: nullableText(resource.errorCode),
        safeMessage: nullableText(resource.safeMessage),
      })];
    }))),
    inspectedAtUnixMs: integer(receipt.inspectedAtUnixMs),
  });
}

function parseAccessObservation(value: unknown) {
  const observation = record(value);
  const reachability = text(observation.reachability);
  if (!new Set(["reachable", "missing", "unauthorized", "unreachable"]).has(reachability)) {
    throw new Error("Access bundle observation is invalid");
  }
  return Object.freeze({
    target: parseTarget(observation.target),
    reachability: reachability as "reachable" | "missing" | "unauthorized" | "unreachable",
    remoteVersion: nullableText(observation.remoteVersion),
    remoteEtag: nullableText(observation.remoteEtag),
    observedDesiredHash: nullableText(observation.observedDesiredHash),
    activeArtifactHash: nullableText(observation.activeArtifactHash),
    endpoint: nullableText(observation.endpoint),
    gatewayProtocolVersion: nullableText(observation.gatewayProtocolVersion),
    d1MigrationStatus: nullableText(observation.d1MigrationStatus),
    workersDevReady: nullableBoolean(observation.workersDevReady),
    observedAtUnixMs: integer(observation.observedAtUnixMs),
  });
}

function parseAccessBundleMutationUpdate(
  value: unknown,
  rotation: boolean,
): AccessBundleMutationUpdate {
  const update = record(value);
  return Object.freeze({
    mutation: parseAccessBundleMutation(update.mutation, rotation),
    project: update.project as DeveloperProjectSnapshot,
  });
}

function parseAccessBundleMutation(
  value: unknown,
  rotation: boolean,
): DeveloperAccessBundleMutationReceipt {
  const mutation = record(value);
  return Object.freeze({
    schemaVersion: integer(mutation.schemaVersion),
    operationId: text(mutation.operationId),
    outcome: parseAccessBundleMutationOutcome(mutation.outcome),
    ...(rotation ? { configuredRevision: text(mutation.configuredRevision) } : {}),
    resources: parseAccessLifecycleResources(mutation.resources),
    verification: mutation.verification === null
      ? null
      : parseAccessBundleTest(mutation.verification),
    completedAtUnixMs: integer(mutation.completedAtUnixMs),
  });
}

function parseAccessBundleDestroyPlan(value: unknown): DeveloperAccessBundleDestroyPlan {
  const plan = record(value);
  if (!Array.isArray(plan.resources)) throw new Error("Access bundle destroy plan is invalid");
  return Object.freeze({
    schemaVersion: integer(plan.schemaVersion),
    planHash: text(plan.planHash),
    bundleId: text(plan.bundleId),
    resources: Object.freeze(plan.resources.map((candidate) => {
      const resource = record(candidate);
      if (!Array.isArray(resource.resources)
        || (resource.ownership !== "exclusive" && resource.ownership !== "shared")) {
        throw new Error("Access bundle destroy resource is invalid");
      }
      return Object.freeze({
        resourceId: text(resource.resourceId),
        target: parseTarget(resource.target),
        resources: Object.freeze(resource.resources.map(text)),
        ownership: resource.ownership,
        deleteRequiresConfirmation: boolean(resource.deleteRequiresConfirmation),
      });
    })),
    commerceDataLossRequiresConfirmation: boolean(plan.commerceDataLossRequiresConfirmation),
    expiresAtUnixMs: integer(plan.expiresAtUnixMs),
  });
}

function parseAccessBundleDestroyReceipt(value: unknown): DeveloperAccessBundleDestroyReceipt {
  const receipt = record(value);
  return Object.freeze({
    schemaVersion: integer(receipt.schemaVersion),
    planHash: text(receipt.planHash),
    operationId: text(receipt.operationId),
    outcome: parseAccessBundleMutationOutcome(receipt.outcome),
    resources: parseAccessLifecycleResources(receipt.resources),
    completedAtUnixMs: integer(receipt.completedAtUnixMs),
  });
}

function parseAccessLifecycleResources(
  value: unknown,
): Readonly<Record<string, DeveloperAccessBundleLifecycleResourceReceipt>> {
  return Object.freeze(Object.fromEntries(Object.entries(record(value)).map(([id, candidate]) => {
    const resource = record(candidate);
    const status = text(resource.status);
    if (!new Set(["applied", "already_converged", "failed", "uncertain", "blocked"])
      .has(status)) throw new Error("Access bundle lifecycle resource is invalid");
    return [id, Object.freeze({
      resourceId: text(resource.resourceId),
      target: parseTarget(resource.target),
      status: status as DeveloperAccessBundleLifecycleResourceReceipt["status"],
      versionId: nullableText(resource.versionId),
      previousVersionId: nullableText(resource.previousVersionId),
      configuredRevision: nullableText(resource.configuredRevision),
      rollbackBoundary: resource.rollbackBoundary,
      errorCode: nullableText(resource.errorCode),
      safeMessage: nullableText(resource.safeMessage),
    })];
  })));
}

function parseAccessBundleMutationOutcome(value: unknown): DeveloperAccessBundleMutationOutcome {
  const outcome = text(value) as DeveloperAccessBundleMutationOutcome;
  if (!new Set<DeveloperAccessBundleMutationOutcome>([
    "succeeded",
    "failed_before_activation",
    "entitlement_ready_gateway_failed",
    "verification_failed",
    "partial",
    "uncertain_remote_state",
  ]).has(outcome)) throw new Error("Access bundle lifecycle outcome is invalid");
  return outcome;
}

function parseTarget(value: unknown): GatewayTarget {
  const target = record(value);
  return Object.freeze({
    accountId: text(target.accountId),
    deploymentId: text(target.deploymentId),
    workerName: text(target.workerName),
    ...(target.environment === undefined ? {} : { environment: text(target.environment) }),
  });
}

function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Developer API response is invalid");
  }
  return value as Record<string, unknown>;
}

function text(value: unknown): string {
  if (typeof value !== "string" || value.length === 0 || value.length > 16_384) {
    throw new Error("Developer API response is invalid");
  }
  return value;
}

function nullableText(value: unknown): string | null {
  return value === null ? null : text(value);
}

function integer(value: unknown): number {
  if (!Number.isSafeInteger(value)) throw new Error("Developer API response is invalid");
  return Number(value);
}

function nullableInteger(value: unknown): number | null {
  return value === null ? null : integer(value);
}

function boolean(value: unknown): boolean {
  if (typeof value !== "boolean") throw new Error("Developer API response is invalid");
  return value;
}

function nullableBoolean(value: unknown): boolean | null {
  return value === null ? null : boolean(value);
}
