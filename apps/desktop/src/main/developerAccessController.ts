import {
  DEVELOPER_ACCESS_REQUEST_CHANNEL,
  type DeveloperAccessOperation,
  type DeveloperAccessRequest,
  type DeveloperDeploymentProjectUpdate,
  type DeveloperGatewayDeploymentReceipt,
  type DeveloperGatewayTestProjectUpdate,
  type DeveloperGatewayTestReceipt,
  type DeveloperPendingDeployment,
} from "../shared/developerAccess";
import type { DeveloperProjectSnapshot } from "../shared/developerProject";
import {
  prepareIdentityCallbackListener,
  type IdentityCallbackListener,
} from "./identityCallbackServer";
import type { SidecarRequest } from "./sidecarSupervisor";
import { connectDeveloperFirebase } from "./developerFirebaseController";

const MAX_RESPONSE_BYTES = 1024 * 1024;
const MAX_REQUEST_BYTES = 2 * 1024 * 1024;
const PLAN_HASH = /^[a-f0-9]{64}$/;
const PROJECT_REVISION = /^[a-f0-9]{64}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type IpcEvent = { sender: { id: number } };
type IpcMainLike = {
  handle(channel: string, handler: (event: IpcEvent, value: unknown) => unknown): void;
  removeHandler(channel: string): void;
};

type RequestDescription = Readonly<{
  body?: unknown;
  method: "DELETE" | "GET" | "POST";
  pathname: string;
  planRevision?: string;
}>;

type PendingDeployment = Readonly<{
  deployment: DeveloperGatewayDeploymentReceipt;
  projectRevision: string;
}>;

export function registerDeveloperAccessController(options: {
  ensureCredentialVault: () => Promise<void>;
  ipcMain: IpcMainLike;
  invalidateDeployment?: () => Promise<DeveloperProjectSnapshot>;
  firebaseRedirectUri?: string;
  loadProject: () => Promise<DeveloperProjectSnapshot>;
  openExternal: (url: string) => Promise<unknown> | unknown;
  recordDeployment: (
    expectedRevision: string,
    receipt: DeveloperGatewayDeploymentReceipt,
  ) => Promise<DeveloperProjectSnapshot>;
  redirectUri: string;
  requesterWebContents: { id: number };
  sidecarRequest: SidecarRequest;
  verifyDeployment: (
    deployment: DeveloperGatewayDeploymentReceipt,
    expectedRevision: string,
    test: DeveloperGatewayTestReceipt,
  ) => Promise<DeveloperProjectSnapshot>;
}): () => void {
  let cloudflareListener: IdentityCallbackListener | null = null;
  let firebaseListener: IdentityCallbackListener | null = null;
  const planRevisions = new Map<string, string>();
  const destroyPlanRevisions = new Map<string, string>();
  const pendingDeployments = new Map<string, PendingDeployment>();
  const assertRequester = (event: IpcEvent) => {
    if (event.sender.id !== options.requesterWebContents.id) {
      throw new Error("Developer access is restricted to the requester window");
    }
  };
  const closeCloudflareListener = async () => {
    const active = cloudflareListener;
    cloudflareListener = null;
    await active?.close();
  };
  const closeFirebaseListener = async () => {
    const active = firebaseListener;
    firebaseListener = null;
    await active?.close();
  };

  options.ipcMain.handle(DEVELOPER_ACCESS_REQUEST_CHANNEL, async (event, value) => {
    assertRequester(event);
    const request = parseRequest(value);
    await options.ensureCredentialVault();
    if (request.operation === "cloudflare.connect") {
      return connectCloudflare(options, request.input, closeCloudflareListener, (active) => {
        cloudflareListener = active;
      });
    }
    if (request.operation === "firebase.connect") {
      return connectDeveloperFirebase({
        closeListener: closeFirebaseListener,
        input: request.input,
        openExternal: options.openExternal,
        redirectUri: options.firebaseRedirectUri,
        requestJson: (description) => requestSidecarJson(options.sidecarRequest, description),
        setListener: (active) => { firebaseListener = active; },
      });
    }
    const lifecycleProject = LIFECYCLE_TARGET_OPERATIONS.has(request.operation)
      ? await options.loadProject()
      : null;
    if (lifecycleProject) {
      validateLifecycleTarget(request, lifecycleProject, pendingDeployments);
    }
    if (request.operation === "gateway.destroyApply") {
      const planHash = planHashInput(request.input);
      const expectedRevision = destroyPlanRevisions.get(planHash);
      const current = await options.loadProject();
      if (!expectedRevision || current.revision !== expectedRevision) {
        throw new Error("Gateway destroy plan is unavailable or stale");
      }
    }
    const description = request.operation === "gateway.plan"
      ? describeGatewayPlan(request.input, await options.loadProject())
      : request.operation === "gateway.test"
        ? describeGatewayTest(request.input, pendingDeployments)
      : describeRequest(request);
    if (description.planRevision) {
      const project = await options.loadProject();
      if (project.revision !== description.planRevision) {
        throw new Error("Developer project changed; reload before planning the gateway");
      }
    }
    const response = await requestSidecarJson(options.sidecarRequest, description);
    if (request.operation === "status") {
      publicResponse(response);
      const status = exactRecord(response, [
        "authorization",
        "firebaseAuthorization",
        "gatewayTemplate",
        "sensitiveBindings",
      ], true);
      if (["authorization", "gatewayTemplate", "sensitiveBindings"]
        .some((key) => !Object.hasOwn(status, key))) {
        throw new Error("Developer control status is invalid");
      }
      const project = await options.loadProject();
      for (const [key, pending] of pendingDeployments) {
        if (pending.projectRevision !== project.revision) pendingDeployments.delete(key);
      }
      const pending = pendingDeployments.values().next().value;
      return Object.freeze({
        ...status,
        pendingDeployment: pending
          ? Object.freeze<DeveloperPendingDeployment>({
              deployment: pending.deployment,
              projectRevision: pending.projectRevision,
            })
          : null,
      });
    }
    if (request.operation === "gateway.rotate" || request.operation === "gateway.rollback") {
      if (!lifecycleProject) throw new Error("Gateway deployment state is unavailable");
      return finalizeLifecycleMutation({
        kind: request.operation === "gateway.rotate" ? "rotate" : "rollback",
        options,
        pendingDeployments,
        projectBefore: lifecycleProject,
        response,
      });
    }
    if (request.operation === "gateway.destroyPlan") {
      if (!lifecycleProject) throw new Error("Gateway deployment state is unavailable");
      const destroyPlan = parseDestroyPlan(response);
      destroyPlanRevisions.set(destroyPlan.planHash, lifecycleProject.revision);
      return destroyPlan;
    }
    if (request.operation === "gateway.destroyApply") {
      const destroy = parseDestroyReceipt(response);
      const invalidate = options.invalidateDeployment;
      if (!invalidate) throw new Error("Gateway deployment invalidation is unavailable");
      const project = await invalidate();
      pendingDeployments.clear();
      destroyPlanRevisions.delete(destroy.planHash);
      return Object.freeze({ destroy, project });
    }
    if (request.operation === "gateway.plan") {
      const planHash = requiredString(exactRecord(response, [
        "drift",
        "expiresAtUnixMs",
        "operations",
        "planHash",
        "target",
      ]), "planHash", 64);
      if (!PLAN_HASH.test(planHash) || !description.planRevision) {
        throw new Error("Gateway deployment plan is invalid");
      }
      planRevisions.set(planHash, description.planRevision);
      return publicResponse(response);
    }
    if (request.operation === "gateway.apply") {
      const planHash = planHashInput(request.input);
      const expectedRevision = planRevisions.get(planHash);
      if (!expectedRevision) throw new Error("Gateway plan is unavailable; create a new plan");
      const deployment = parseDeploymentReceipt(response);
      const project = await options.recordDeployment(expectedRevision, deployment);
      pendingDeployments.set(targetKey(deployment.target), {
        deployment,
        projectRevision: project.revision,
      });
      planRevisions.delete(planHash);
      return Object.freeze<DeveloperDeploymentProjectUpdate>({ deployment, project });
    }
    if (request.operation === "gateway.test") {
      const test = parseTestReceipt(response);
      const key = targetKey(test.target);
      const pending = pendingDeployments.get(key);
      if (!pending) return test;
      const project = await options.verifyDeployment(
        pending.deployment,
        pending.projectRevision,
        test,
      );
      pendingDeployments.delete(key);
      return Object.freeze<DeveloperGatewayTestProjectUpdate>({ project, test });
    }
    if (request.operation === "cloudflare.cancel") await closeCloudflareListener();
    if (request.operation === "firebase.cancel") await closeFirebaseListener();
    if (request.operation === "cloudflare.disconnect") {
      await closeCloudflareListener();
      planRevisions.clear();
      destroyPlanRevisions.clear();
      pendingDeployments.clear();
    }
    if (request.operation === "firebase.disconnect") await closeFirebaseListener();
    if (request.operation === "cloudflare.accounts") return parseAccounts(response);
    return publicResponse(response);
  });

  return () => {
    options.ipcMain.removeHandler(DEVELOPER_ACCESS_REQUEST_CHANNEL);
    void closeCloudflareListener();
    void closeFirebaseListener();
  };
}

async function connectCloudflare(
  options: Parameters<typeof registerDeveloperAccessController>[0],
  input: unknown,
  closeListener: () => Promise<void>,
  setListener: (listener: IdentityCallbackListener) => void,
): Promise<unknown> {
  const client = cloudflareClient(input);
  await closeListener();
  const prepared = await prepareIdentityCallbackListener({
    redirectUri: options.redirectUri,
    callback: async (callbackUrl) => {
      await requestSidecarJson(options.sidecarRequest, {
        body: { callbackUrl },
        method: "POST",
        pathname: "/dev/control/cloudflare/authorization/callback",
      });
    },
  });
  setListener(prepared);
  try {
    const start = exactRecord(
      await requestSidecarJson(options.sidecarRequest, {
        body: { client, redirectUri: options.redirectUri },
        method: "POST",
        pathname: "/dev/control/cloudflare/authorization",
      }),
      ["authorizationUrl", "expiresAtUnixMs"],
    );
    const expiresAtUnixMs = safeInteger(start.expiresAtUnixMs, 1, Number.MAX_SAFE_INTEGER);
    prepared.setExpiresAt(new Date(expiresAtUnixMs).toISOString());
    await options.openExternal(cloudflareAuthorizationUrl(start.authorizationUrl));
    return Object.freeze({ expiresAtUnixMs, phase: "awaiting_callback" });
  } catch {
    await requestSidecarJson(options.sidecarRequest, {
      method: "DELETE",
      pathname: "/dev/control/cloudflare/authorization/pending",
    }).catch(() => undefined);
    await closeListener();
    throw new Error("Cloudflare authorization could not be started");
  }
}

function parseRequest(value: unknown): DeveloperAccessRequest {
  const request = exactRecord(value, ["input", "operation"], true);
  if (typeof request.operation !== "string" || !OPERATIONS.has(request.operation as DeveloperAccessOperation)) {
    throw new Error("Developer access operation is invalid");
  }
  return {
    operation: request.operation as DeveloperAccessOperation,
    ...(Object.hasOwn(request, "input") ? { input: request.input } : {}),
  };
}

function describeRequest(request: DeveloperAccessRequest): RequestDescription {
  switch (request.operation) {
    case "status":
      noInput(request.input);
      return get("/dev/control/status");
    case "cloudflare.cancel":
      noInput(request.input);
      return { method: "DELETE", pathname: "/dev/control/cloudflare/authorization/pending" };
    case "cloudflare.disconnect":
      noInput(request.input);
      return { method: "DELETE", pathname: "/dev/control/cloudflare/authorization" };
    case "cloudflare.accounts":
      noInput(request.input);
      return get("/dev/control/cloudflare/accounts");
    case "cloudflare.selectAccount":
      return json("POST", "/dev/control/cloudflare/accounts", {
        accountId: requiredString(exactRecord(request.input, ["accountId"]), "accountId", 256),
      });
    case "firebase.cancel":
      noInput(request.input);
      return { method: "DELETE", pathname: "/dev/control/firebase/authorization/pending" };
    case "firebase.disconnect":
      noInput(request.input);
      return { method: "DELETE", pathname: "/dev/control/firebase/authorization" };
    case "firebase.projects":
      noInput(request.input);
      return get("/dev/control/firebase/projects");
    case "firebase.configure":
      return json("POST", "/dev/control/firebase/projects", {
        projectId: requiredString(
          exactRecord(request.input, ["projectId"]),
          "projectId",
          30,
        ),
      });
    case "gateway.plan": {
      throw new Error("Gateway planning requires the trusted developer project snapshot");
    }
    case "gateway.apply":
      return json("POST", "/dev/control/gateway/apply", { planHash: planHashInput(request.input) });
    case "gateway.inspect":
      return json("POST", "/dev/control/gateway/inspect", boundedObject(request.input));
    case "gateway.test":
      throw new Error("Gateway verification requires a pending deployment");
    case "gateway.rotate":
      return json("POST", "/dev/control/gateway/rotate", boundedObject(request.input));
    case "gateway.rollback":
      return json("POST", "/dev/control/gateway/rollback", boundedObject(request.input));
    case "gateway.destroyPlan":
      return json("POST", "/dev/control/gateway/destroy/plan", boundedObject(request.input));
    case "gateway.destroyApply":
      return json("POST", "/dev/control/gateway/destroy/apply", {
        planHash: planHashInput(request.input),
      });
    case "cloudflare.connect":
      throw new Error("Cloudflare connect must use the protected authorization flow");
    case "firebase.connect":
      throw new Error("Firebase connect must use the protected authorization flow");
  }
}

function describeGatewayTest(
  value: unknown,
  pendingDeployments: ReadonlyMap<string, PendingDeployment>,
): RequestDescription {
  noInput(value);
  if (pendingDeployments.size !== 1) {
    throw new Error("A newly applied gateway deployment is required before verification");
  }
  const pending = pendingDeployments.values().next().value;
  if (!pending) throw new Error("Gateway deployment verification is unavailable");
  return json("POST", "/dev/control/gateway/test", {
    target: pending.deployment.target,
  });
}

function describeGatewayPlan(
  value: unknown,
  snapshot: DeveloperProjectSnapshot,
): RequestDescription {
  const input = exactRecord(value, [
    "expectedProjectRevision",
    "expectedRemoteEtag",
    "expectedRemoteVersion",
    "idempotencyKey",
    "sensitiveInputs",
  ], true);
  const planRevision = requiredString(input, "expectedProjectRevision", 64);
  if (!PROJECT_REVISION.test(planRevision) || snapshot.revision !== planRevision) {
    throw new Error("Developer project changed; reload before planning the gateway");
  }
  const document = exactRecord(snapshot.project, [
    "deployment",
    "modelAccess",
    "providers",
    "schemaVersion",
  ]);
  const providers = exactRecord(document.providers, ["entitlement", "gateway", "identity"]);
  const manifest = snapshot.manifest;
  const body = {
    project: {
      projectRevision: planRevision,
      appId: requiredString(manifest, "appId", 255),
      providers: {
        identity: providers.identity,
        entitlement: providers.entitlement,
        gateway: providers.gateway,
      },
      modelAccess: document.modelAccess,
      deployment: document.deployment,
    },
    sensitiveInputs: boundedObject(input.sensitiveInputs),
    ...(Object.hasOwn(input, "idempotencyKey")
      ? { idempotencyKey: input.idempotencyKey }
      : {}),
    ...(Object.hasOwn(input, "expectedRemoteVersion")
      ? { expectedRemoteVersion: input.expectedRemoteVersion }
      : {}),
    ...(Object.hasOwn(input, "expectedRemoteEtag")
      ? { expectedRemoteEtag: input.expectedRemoteEtag }
      : {}),
  };
  return { ...json("POST", "/dev/control/gateway/plan", body), planRevision };
}

function validateLifecycleTarget(
  request: DeveloperAccessRequest,
  project: DeveloperProjectSnapshot,
  pendingDeployments: ReadonlyMap<string, PendingDeployment>,
): void {
  let supplied: DeveloperGatewayDeploymentReceipt["target"];
  if (request.operation === "gateway.inspect") {
    supplied = parseGatewayTarget(request.input);
  } else if (request.operation === "gateway.rotate") {
    const input = exactRecord(request.input, [
      "bindingName",
      "expectedRemoteEtag",
      "expectedRemoteVersion",
      "idempotencyKey",
      "revision",
      "target",
      "value",
    ], true);
    supplied = parseGatewayTarget(input.target);
    const bindingName = requiredString(input, "bindingName", 128);
    if (!new Set(["UPSTREAM_API_KEY", "ENTITLEMENT_PROJECTION_SECRET"]).has(bindingName)) {
      throw new Error("Gateway secret binding is not managed by this project");
    }
    requiredString(input, "revision", 256);
    requiredString(input, "value", MAX_REQUEST_BYTES);
    validateMutationControl(input);
  } else if (request.operation === "gateway.rollback") {
    const input = exactRecord(request.input, [
      "expectedRemoteEtag",
      "expectedRemoteVersion",
      "idempotencyKey",
      "restoreVersion",
      "target",
    ], true);
    supplied = parseGatewayTarget(input.target);
    requiredString(input, "restoreVersion", 128);
    validateMutationControl(input);
  } else {
    const input = exactRecord(request.input, [
      "expectedRemoteEtag",
      "expectedRemoteVersion",
      "idempotencyKey",
      "target",
    ], true);
    supplied = parseGatewayTarget(input.target);
    validateMutationControl(input);
  }
  const candidates = [
    ...[...pendingDeployments.values()]
      .filter((pending) => pending.projectRevision === project.revision)
      .map((pending) => pending.deployment.target),
    ...(project.verifiedDeployment ? [project.verifiedDeployment.target] : []),
  ];
  if (!candidates.some((target) => sameGatewayTarget(target, supplied))) {
    throw new Error("Gateway lifecycle operation is not bound to the verified developer project");
  }
}

function validateMutationControl(input: Record<string, unknown>): void {
  if (Object.hasOwn(input, "idempotencyKey")) operationUuid(input.idempotencyKey);
  for (const field of ["expectedRemoteVersion", "expectedRemoteEtag"] as const) {
    if (Object.hasOwn(input, field)) requiredString(input, field, 256);
  }
}

async function finalizeLifecycleMutation(options: {
  kind: "rotate" | "rollback";
  options: Parameters<typeof registerDeveloperAccessController>[0];
  pendingDeployments: Map<string, PendingDeployment>;
  projectBefore: DeveloperProjectSnapshot;
  response: unknown;
}): Promise<unknown> {
  const operation = options.kind === "rotate"
    ? parseRotationReceipt(options.response)
    : parseRollbackReceipt(options.response);
  const invalidate = options.options.invalidateDeployment;
  if (!invalidate) throw new Error("Gateway deployment invalidation is unavailable");
  const project = await invalidate();
  const observation = parseDeploymentObservation(await requestSidecarJson(
    options.options.sidecarRequest,
    json("POST", "/dev/control/gateway/inspect", operation.target),
  ));
  if (
    !sameGatewayTarget(operation.target, observation.target)
    || !observation.remoteVersion
    || !observation.endpoint
    || (options.kind === "rollback"
      && operation.versionId !== observation.remoteVersion)
  ) {
    throw new Error("Gateway mutation could not be verified against the active deployment");
  }
  const gateway = projectGatewayProvider(options.projectBefore);
  const deployment = Object.freeze<DeveloperGatewayDeploymentReceipt>({
    providerId: gateway.id,
    providerVersion: gateway.version,
    target: operation.target,
    outcome: "applied",
    previousVersionId: operation.previousVersionId ?? null,
    versionId: observation.remoteVersion,
    endpoint: observation.endpoint,
    operationId: operation.operationId,
    completedAtUnixMs: operation.completedAtUnixMs,
  });
  options.pendingDeployments.clear();
  options.pendingDeployments.set(targetKey(deployment.target), {
    deployment,
    projectRevision: project.revision,
  });
  return Object.freeze({
    deployment,
    project,
    operation: Object.freeze({ kind: options.kind, ...operation.publicFacts }),
  });
}

function parseRotationReceipt(value: unknown) {
  publicResponse(value);
  const receipt = exactRecord(value, [
    "bindingName",
    "completedAtUnixMs",
    "configuredRevision",
    "operationId",
    "target",
  ]);
  const operationId = operationUuid(receipt.operationId);
  const bindingName = requiredString(receipt, "bindingName", 128);
  if (!new Set(["UPSTREAM_API_KEY", "ENTITLEMENT_PROJECTION_SECRET"]).has(bindingName)) {
    throw new Error("Gateway secret rotation receipt is invalid");
  }
  const configuredRevision = requiredString(receipt, "configuredRevision", 256);
  const completedAtUnixMs = safeInteger(receipt.completedAtUnixMs, 1, Number.MAX_SAFE_INTEGER);
  return {
    target: parseGatewayTarget(receipt.target),
    operationId,
    completedAtUnixMs,
    previousVersionId: null,
    versionId: undefined,
    publicFacts: { bindingName, configuredRevision, operationId, completedAtUnixMs },
  };
}

function parseRollbackReceipt(value: unknown) {
  publicResponse(value);
  const receipt = exactRecord(value, [
    "boundary",
    "completedAtUnixMs",
    "operationId",
    "previousVersionId",
    "target",
    "versionId",
  ]);
  const operationId = operationUuid(receipt.operationId);
  const previousVersionId = requiredString(receipt, "previousVersionId", 128);
  const versionId = requiredString(receipt, "versionId", 128);
  const boundary = requiredString(receipt, "boundary", 64);
  const completedAtUnixMs = safeInteger(receipt.completedAtUnixMs, 1, Number.MAX_SAFE_INTEGER);
  return {
    target: parseGatewayTarget(receipt.target),
    operationId,
    completedAtUnixMs,
    previousVersionId,
    versionId,
    publicFacts: {
      previousVersionId,
      versionId,
      boundary,
      operationId,
      completedAtUnixMs,
    },
  };
}

function parseDestroyPlan(value: unknown) {
  publicResponse(value);
  const plan = exactRecord(value, ["expiresAtUnixMs", "planHash", "resources", "target"]);
  const planHash = requiredString(plan, "planHash", 64);
  if (!PLAN_HASH.test(planHash) || !Array.isArray(plan.resources) || plan.resources.length > 128) {
    throw new Error("Gateway destroy plan is invalid");
  }
  return Object.freeze({
    planHash,
    target: parseGatewayTarget(plan.target),
    resources: Object.freeze(plan.resources.map((resource) => {
      if (!safePublicString(resource, 512)) throw new Error("Gateway destroy plan is invalid");
      return resource;
    })),
    expiresAtUnixMs: safeInteger(plan.expiresAtUnixMs, 1, Number.MAX_SAFE_INTEGER),
  });
}

function parseDestroyReceipt(value: unknown) {
  publicResponse(value);
  const receipt = exactRecord(value, [
    "completedAtUnixMs",
    "deletedResources",
    "operationId",
    "planHash",
    "target",
  ]);
  const planHash = requiredString(receipt, "planHash", 64);
  if (!PLAN_HASH.test(planHash)
    || !Array.isArray(receipt.deletedResources)
    || receipt.deletedResources.length > 128) {
    throw new Error("Gateway destroy receipt is invalid");
  }
  return Object.freeze({
    planHash,
    target: parseGatewayTarget(receipt.target),
    deletedResources: Object.freeze(receipt.deletedResources.map((resource) => {
      if (!safePublicString(resource, 512)) throw new Error("Gateway destroy receipt is invalid");
      return resource;
    })),
    operationId: operationUuid(receipt.operationId),
    completedAtUnixMs: safeInteger(receipt.completedAtUnixMs, 1, Number.MAX_SAFE_INTEGER),
  });
}

function parseDeploymentObservation(value: unknown): {
  target: DeveloperGatewayDeploymentReceipt["target"];
  remoteVersion: string | null;
  endpoint: string | null;
} {
  publicResponse(value);
  const observation = exactRecord(value, [
    "activeArtifactHash",
    "d1MigrationStatus",
    "endpoint",
    "gatewayProtocolVersion",
    "observedAtUnixMs",
    "observedDesiredHash",
    "reachability",
    "remoteEtag",
    "remoteVersion",
    "target",
    "workersDevReady",
  ]);
  return {
    target: parseGatewayTarget(observation.target),
    remoteVersion: observation.remoteVersion === null
      ? null
      : requiredString(observation, "remoteVersion", 128),
    endpoint: observation.endpoint === null ? null : safeHttpsUrl(observation.endpoint),
  };
}

function parseGatewayTarget(value: unknown): DeveloperGatewayDeploymentReceipt["target"] {
  const target = exactRecord(value, ["accountId", "deploymentId", "environment", "workerName"], true);
  return Object.freeze({
    accountId: requiredString(target, "accountId", 256),
    deploymentId: requiredString(target, "deploymentId", 128),
    workerName: requiredString(target, "workerName", 128),
    ...(Object.hasOwn(target, "environment")
      ? { environment: requiredString(target, "environment", 32) }
      : {}),
  });
}

function sameGatewayTarget(
  left: DeveloperGatewayDeploymentReceipt["target"],
  right: DeveloperGatewayDeploymentReceipt["target"],
): boolean {
  return left.accountId === right.accountId
    && left.deploymentId === right.deploymentId
    && left.workerName === right.workerName
    && left.environment === right.environment;
}

function projectGatewayProvider(project: DeveloperProjectSnapshot): { id: string; version: string } {
  const document = exactRecord(project.project, [
    "deployment",
    "modelAccess",
    "providers",
    "schemaVersion",
  ]);
  const providers = exactRecord(document.providers, ["entitlement", "gateway", "identity"]);
  const gateway = exactRecord(providers.gateway, ["id", "publicConfig", "version"]);
  return {
    id: requiredString(gateway, "id", 128),
    version: requiredString(gateway, "version", 64),
  };
}

function operationUuid(value: unknown): string {
  if (!safePublicString(value, 64) || !UUID.test(value)) {
    throw new Error("Gateway operation receipt is invalid");
  }
  return value;
}

function cloudflareClient(value: unknown): unknown {
  const input = exactRecord(value, ["client"]);
  const client = exactRecord(input.client, ["clientId", "mode", "scopeCatalog"], true);
  if (client.mode === "agent_weave_public") {
    if (Object.keys(client).length !== 1) throw new Error("Cloudflare OAuth client is invalid");
    return { mode: client.mode };
  }
  if (client.mode !== "custom") throw new Error("Cloudflare OAuth client is invalid");
  const clientId = requiredString(client, "clientId", 2_048);
  const scopeCatalog = exactRecord(client.scopeCatalog, [], true);
  const entries = Object.entries(scopeCatalog);
  if (entries.length === 0 || entries.length > 64 || entries.some(([name, id]) => (
    !safePublicString(name, 256) || !safePublicString(id, 256)
  ))) throw new Error("Cloudflare OAuth scope catalog is invalid");
  return { clientId, mode: client.mode, scopeCatalog };
}

function parseDeploymentReceipt(value: unknown): DeveloperGatewayDeploymentReceipt {
  const receipt = exactRecord(value, [
    "completedAtUnixMs",
    "endpoint",
    "operationId",
    "outcome",
    "previousVersionId",
    "providerId",
    "providerVersion",
    "target",
    "versionId",
  ]);
  const target = exactRecord(receipt.target, [
    "accountId",
    "deploymentId",
    "environment",
    "workerName",
  ], true);
  const endpoint = safeHttpsUrl(receipt.endpoint);
  const operationId = requiredString(receipt, "operationId", 64);
  if (!UUID.test(operationId)) throw new Error("Gateway deployment receipt is invalid");
  const outcome = receipt.outcome;
  if (!new Set(["applied", "already_converged", "recovered_after_uncertain_write"]).has(String(outcome))) {
    throw new Error("Gateway deployment receipt is invalid");
  }
  return Object.freeze({
    providerId: requiredString(receipt, "providerId", 128),
    providerVersion: requiredString(receipt, "providerVersion", 64),
    target: Object.freeze({
      accountId: requiredString(target, "accountId", 256),
      deploymentId: requiredString(target, "deploymentId", 128),
      workerName: requiredString(target, "workerName", 128),
      ...(Object.hasOwn(target, "environment")
        ? { environment: requiredString(target, "environment", 32) }
        : {}),
    }),
    outcome: outcome as DeveloperGatewayDeploymentReceipt["outcome"],
    previousVersionId: receipt.previousVersionId === null
      ? null
      : requiredString(receipt, "previousVersionId", 128),
    versionId: requiredString(receipt, "versionId", 128),
    endpoint,
    operationId,
    completedAtUnixMs: safeInteger(receipt.completedAtUnixMs, 1, Number.MAX_SAFE_INTEGER),
  });
}

function parseTestReceipt(value: unknown): DeveloperGatewayTestReceipt {
  const receipt = exactRecord(value, [
    "protocolVersion",
    "remoteVersion",
    "target",
    "testedAtUnixMs",
  ]);
  const target = exactRecord(receipt.target, [
    "accountId",
    "deploymentId",
    "environment",
    "workerName",
  ], true);
  return Object.freeze({
    target: Object.freeze({
      accountId: requiredString(target, "accountId", 256),
      deploymentId: requiredString(target, "deploymentId", 128),
      workerName: requiredString(target, "workerName", 128),
      ...(Object.hasOwn(target, "environment")
        ? { environment: requiredString(target, "environment", 32) }
        : {}),
    }),
    protocolVersion: requiredString(receipt, "protocolVersion", 64),
    remoteVersion: requiredString(receipt, "remoteVersion", 128),
    testedAtUnixMs: safeInteger(receipt.testedAtUnixMs, 1, Number.MAX_SAFE_INTEGER),
  });
}

function targetKey(target: DeveloperGatewayDeploymentReceipt["target"]): string {
  return [
    target.accountId,
    target.deploymentId,
    target.workerName,
    target.environment ?? "",
  ].map((part) => `${part.length}:${part}`).join("|");
}

function parseAccounts(value: unknown): unknown {
  if (!Array.isArray(value) || value.length > 100) throw new Error("Cloudflare accounts are invalid");
  return value.map((candidate) => {
    const account = exactRecord(candidate, ["account_id", "display_name", "provider_id"]);
    return Object.freeze({
      accountId: requiredString(account, "account_id", 256),
      displayName: account.display_name === null
        ? null
        : requiredString(account, "display_name", 512),
      providerId: requiredString(account, "provider_id", 128),
    });
  });
}

async function requestSidecarJson(
  request: SidecarRequest,
  description: RequestDescription,
): Promise<unknown> {
  const body = description.body === undefined ? undefined : JSON.stringify(description.body);
  if (body && Buffer.byteLength(body, "utf8") > MAX_REQUEST_BYTES) {
    throw new Error("Developer access request is too large");
  }
  const response = await request(description.pathname, {
    method: description.method,
    ...(body === undefined
      ? {}
      : { body, headers: { "content-type": "application/json" } }),
  });
  const length = response.headers.get("content-length");
  if (length && Number(length) > MAX_RESPONSE_BYTES) {
    throw new Error("Developer access response is too large");
  }
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes.byteLength > MAX_RESPONSE_BYTES) throw new Error("Developer access response is too large");
  let value: unknown;
  try {
    value = JSON.parse(new TextDecoder().decode(bytes)) as unknown;
  } catch {
    throw new Error("Developer access response is invalid");
  }
  if (!response.ok) {
    const error = exactRecord(value, ["code", "message", "remoteMutationPossible", "retryAfterMs"]);
    const code = requiredString(error, "code", 128);
    throw new Error(`Developer access operation failed (${code})`);
  }
  return value;
}

function publicResponse(value: unknown): unknown {
  rejectSensitiveResponse(value);
  return value;
}

function rejectSensitiveResponse(value: unknown): void {
  if (Array.isArray(value)) {
    for (const item of value) rejectSensitiveResponse(item);
    return;
  }
  if (!isRecord(value)) return;
  for (const [name, child] of Object.entries(value)) {
    if (/token|secret|credential|handle|authorizationUrl|callbackUrl/i.test(name)) {
      throw new Error("Developer access response crossed a sensitive boundary");
    }
    rejectSensitiveResponse(child);
  }
}

function cloudflareAuthorizationUrl(value: unknown): string {
  if (typeof value !== "string" || value.length > 16 * 1024) {
    throw new Error("Cloudflare authorization URL is invalid");
  }
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw new Error("Cloudflare authorization URL is invalid");
  }
  if (
    url.protocol !== "https:"
    || url.hostname !== "dash.cloudflare.com"
    || url.pathname !== "/oauth2/auth"
    || url.username
    || url.password
    || url.hash
  ) throw new Error("Cloudflare authorization URL is invalid");
  return url.toString();
}

function safeHttpsUrl(value: unknown): string {
  if (typeof value !== "string" || value.length > 2_048) throw new Error("Public URL is invalid");
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw new Error("Public URL is invalid");
  }
  if (url.protocol !== "https:" || url.username || url.password || url.search || url.hash) {
    throw new Error("Public URL is invalid");
  }
  return url.toString().replace(/\/$/, "");
}

function planHashInput(value: unknown): string {
  const planHash = requiredString(exactRecord(value, ["planHash"]), "planHash", 64);
  if (!PLAN_HASH.test(planHash)) throw new Error("Gateway deployment plan hash is invalid");
  return planHash;
}

function boundedObject(value: unknown): Record<string, unknown> {
  if (!isRecord(value)) throw new Error("Developer access payload is invalid");
  const object = value;
  if (Buffer.byteLength(JSON.stringify(object), "utf8") > MAX_REQUEST_BYTES) {
    throw new Error("Developer access request is too large");
  }
  return object;
}

function get(pathname: string): RequestDescription {
  return { method: "GET", pathname };
}

function json(method: "POST", pathname: string, body: unknown): RequestDescription {
  return { body, method, pathname };
}

function noInput(value: unknown): void {
  if (value !== undefined) throw new Error("Developer access operation does not accept input");
}

function requiredString(value: Record<string, unknown>, field: string, maximum: number): string {
  const candidate = value[field];
  if (!safePublicString(candidate, maximum)) throw new Error("Developer access payload is invalid");
  return candidate;
}

function safePublicString(value: unknown, maximum: number): value is string {
  return typeof value === "string"
    && value.length > 0
    && value.length <= maximum
    && !/[\x00-\x1f\x7f]/.test(value);
}

function safeInteger(value: unknown, minimum: number, maximum: number): number {
  if (!Number.isSafeInteger(value) || Number(value) < minimum || Number(value) > maximum) {
    throw new Error("Developer access payload is invalid");
  }
  return Number(value);
}

function exactRecord(
  value: unknown,
  keys: readonly string[],
  optionalKeys = false,
): Record<string, unknown> {
  if (!isRecord(value)) throw new Error("Developer access payload is invalid");
  if (
    Object.keys(value).some((key) => !keys.includes(key))
    || (!optionalKeys && keys.some((key) => !Object.hasOwn(value, key)))
  ) throw new Error("Developer access payload is invalid");
  return value;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

const OPERATIONS = new Set<DeveloperAccessOperation>([
  "status", "cloudflare.connect", "cloudflare.cancel", "cloudflare.disconnect",
  "cloudflare.accounts", "cloudflare.selectAccount",
  "firebase.connect", "firebase.cancel", "firebase.disconnect",
  "firebase.projects", "firebase.configure",
  "gateway.plan",
  "gateway.apply",
  "gateway.inspect",
  "gateway.test",
  "gateway.rotate",
  "gateway.rollback",
  "gateway.destroyPlan",
  "gateway.destroyApply",
]);

const LIFECYCLE_TARGET_OPERATIONS = new Set<DeveloperAccessOperation>([
  "gateway.inspect",
  "gateway.rotate",
  "gateway.rollback",
  "gateway.destroyPlan",
]);
