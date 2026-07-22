import type {
  DeveloperAccessBundleDestroyPlan,
  DeveloperAccessBundleDestroyReceipt,
  DeveloperAccessBundleInspectReceipt,
  DeveloperAccessBundleLifecycleResourceReceipt,
  DeveloperAccessBundleMutationOutcome,
  DeveloperAccessBundleMutationReceipt,
  DeveloperAccessBundleTestReceipt,
  DeveloperAccessRequest,
  DeveloperGatewayDeploymentReceipt,
  DeveloperGatewayTestReceipt,
} from "../shared/developerAccess";
import type { DeveloperProjectSnapshot } from "../shared/developerProject";

const PLAN_HASH = /^[a-f0-9]{64}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const OPERATIONS = new Set([
  "access.inspect",
  "access.rotate",
  "access.rollback",
  "access.destroyPlan",
  "access.destroyApply",
]);

type RequestDescription = Readonly<{
  body?: unknown;
  method: "POST";
  pathname: string;
}>;

export type DeveloperAccessBundleLifecycleCallbacks = Readonly<{
  invalidate: () => Promise<DeveloperProjectSnapshot>;
  record: (
    expectedRevision: string,
    mutation: DeveloperAccessBundleMutationReceipt,
  ) => Promise<DeveloperProjectSnapshot>;
}>;

export function createDeveloperAccessBundleLifecycleController(options: {
  callbacks?: DeveloperAccessBundleLifecycleCallbacks;
  loadProject: () => Promise<DeveloperProjectSnapshot>;
  requestJson: (description: RequestDescription) => Promise<unknown>;
}) {
  const destroyPlans = new Map<string, Readonly<{
    commerceConfirmation: boolean;
    revision: string;
  }>>();
  return Object.freeze({
    handles(operation: string): boolean {
      return OPERATIONS.has(operation);
    },
    clear(): void {
      destroyPlans.clear();
    },
    async handle(request: DeveloperAccessRequest): Promise<unknown> {
      const snapshot = await options.loadProject();
      const targets = verifiedTargets(snapshot);
      const expectedResources = expectedResourceVersions(snapshot);
      switch (request.operation) {
        case "access.inspect": {
          noInput(request.input);
          return parseInspect(await options.requestJson({
            body: targets,
            method: "POST",
            pathname: "/dev/control/access/inspect",
          }));
        }
        case "access.rotate": {
          noInput(request.input);
          const mutation = parseMutation(await options.requestJson({
            body: { targets, expectedResources, idempotencyKey: crypto.randomUUID() },
            method: "POST",
            pathname: "/dev/control/access/rotate",
          }), true);
          return finalizeMutation(snapshot, mutation, options.callbacks?.record);
        }
        case "access.rollback": {
          const input = exactRecord(request.input, ["entitlementVersionId", "gatewayVersionId"]);
          const rollbackTarget = snapshot.verifiedBundle?.rollbackTarget;
          const gatewayVersionId = requiredString(input.gatewayVersionId, "gatewayVersionId", 256);
          const entitlementVersionId = requiredString(
            input.entitlementVersionId,
            "entitlementVersionId",
            256,
          );
          if (!rollbackTarget
            || rollbackTarget.gatewayVersionId !== gatewayVersionId
            || rollbackTarget.entitlementVersionId !== entitlementVersionId) {
            throw new Error("Access rollback must use the previous verified bundle revision");
          }
          const mutation = parseMutation(await options.requestJson({
            body: {
              targets,
              restoreGatewayVersion: gatewayVersionId,
              restoreEntitlementVersion: entitlementVersionId,
              expectedResources,
              idempotencyKey: crypto.randomUUID(),
            },
            method: "POST",
            pathname: "/dev/control/access/rollback",
          }), false);
          return finalizeMutation(snapshot, mutation, options.callbacks?.record);
        }
        case "access.destroyPlan": {
          noInput(request.input);
          const plan = parseDestroyPlan(await options.requestJson({
            body: { targets, expectedResources, idempotencyKey: crypto.randomUUID() },
            method: "POST",
            pathname: "/dev/control/access/destroy/plan",
          }));
          const current = await options.loadProject();
          if (current.revision !== snapshot.revision) {
            throw new Error("Developer project changed while the access destroy plan was created");
          }
          destroyPlans.set(plan.planHash, Object.freeze({
            commerceConfirmation: plan.commerceDataLossRequiresConfirmation,
            revision: snapshot.revision,
          }));
          return plan;
        }
        case "access.destroyApply": {
          const input = exactRecord(request.input, [
            "confirmCommerceProjectionRebuild",
            "planHash",
          ]);
          const planHash = requiredString(input.planHash, "planHash", 64);
          const planned = destroyPlans.get(planHash);
          if (!PLAN_HASH.test(planHash)
            || planned?.revision !== snapshot.revision
            || typeof input.confirmCommerceProjectionRebuild !== "boolean") {
            throw new Error("Access destroy plan is unavailable or stale");
          }
          if (planned.commerceConfirmation && !input.confirmCommerceProjectionRebuild) {
            throw new Error("Commerce projection rebuild confirmation is required");
          }
          const destroy = parseDestroyReceipt(await options.requestJson({
            body: {
              planHash,
              confirmCommerceProjectionRebuild: input.confirmCommerceProjectionRebuild,
            },
            method: "POST",
            pathname: "/dev/control/access/destroy/apply",
          }));
          if (destroy.outcome !== "succeeded") {
            return Object.freeze({ destroy, project: snapshot });
          }
          if (!options.callbacks) throw new Error("Access deployment invalidation is unavailable");
          const project = await options.callbacks.invalidate();
          destroyPlans.delete(planHash);
          return Object.freeze({ destroy, project });
        }
        default:
          throw new Error("Access bundle lifecycle operation is invalid");
      }
    },
  });
}

async function finalizeMutation(
  snapshot: DeveloperProjectSnapshot,
  mutation: DeveloperAccessBundleMutationReceipt,
  record: DeveloperAccessBundleLifecycleCallbacks["record"] | undefined,
) {
  if (mutation.outcome !== "succeeded") {
    return Object.freeze({ mutation, project: snapshot });
  }
  if (!record) throw new Error("Access lifecycle lock recording is unavailable");
  const project = await record(snapshot.revision, mutation);
  return Object.freeze({ mutation, project });
}

function verifiedTargets(snapshot: DeveloperProjectSnapshot) {
  const bundle = snapshot.verifiedBundle;
  if (!bundle || snapshot.deploymentStatus !== "ready") {
    throw new Error("A verified managed access deployment is required");
  }
  return Object.freeze({
    gateway: bundle.gateway.target,
    entitlementPolicy: bundle.entitlementPolicy.target,
  });
}

function expectedResourceVersions(snapshot: DeveloperProjectSnapshot) {
  const bundle = snapshot.verifiedBundle;
  if (!bundle) throw new Error("A verified managed access deployment is required");
  return Object.freeze({
    "model-gateway": Object.freeze({ remoteVersion: bundle.gateway.versionId }),
    "entitlement-policy": Object.freeze({ remoteVersion: bundle.entitlementPolicy.versionId }),
  });
}

function parseInspect(value: unknown): DeveloperAccessBundleInspectReceipt {
  rejectSensitiveResponse(value);
  const receipt = exactRecord(value, [
    "bundleId", "inspectedAtUnixMs", "outcome", "resources", "schemaVersion",
  ]);
  if (!new Set(["ready", "partial", "unavailable"]).has(String(receipt.outcome))) {
    throw new Error("Access inspection outcome is invalid");
  }
  const resources = record(receipt.resources);
  return Object.freeze({
    schemaVersion: positiveInteger(receipt.schemaVersion),
    bundleId: requiredString(receipt.bundleId, "bundleId", 128),
    outcome: receipt.outcome as DeveloperAccessBundleInspectReceipt["outcome"],
    resources: Object.freeze(Object.fromEntries(Object.entries(resources).map(([id, candidate]) => {
      const resource = exactRecord(candidate, [
        "errorCode", "observation", "resourceId", "safeMessage",
      ]);
      return [id, Object.freeze({
        resourceId: requiredString(resource.resourceId, "resourceId", 128),
        observation: resource.observation === null ? null : parseObservation(resource.observation),
        errorCode: nullableString(resource.errorCode, 128),
        safeMessage: nullableString(resource.safeMessage, 500),
      })];
    }))),
    inspectedAtUnixMs: positiveInteger(receipt.inspectedAtUnixMs),
  });
}

function parseMutation(value: unknown, rotation: boolean): DeveloperAccessBundleMutationReceipt {
  rejectSensitiveResponse(value);
  const keys = [
    "completedAtUnixMs", "operationId", "outcome", "resources", "schemaVersion", "verification",
    ...(rotation ? ["configuredRevision"] : []),
  ];
  const receipt = exactRecord(value, keys);
  const outcome = mutationOutcome(receipt.outcome);
  return Object.freeze({
    schemaVersion: positiveInteger(receipt.schemaVersion),
    operationId: uuid(receipt.operationId),
    outcome,
    ...(rotation ? {
      configuredRevision: requiredString(receipt.configuredRevision, "configuredRevision", 256),
    } : {}),
    resources: parseLifecycleResources(receipt.resources),
    verification: receipt.verification === null ? null : parseBundleTest(receipt.verification),
    completedAtUnixMs: positiveInteger(receipt.completedAtUnixMs),
  });
}

function parseDestroyPlan(value: unknown): DeveloperAccessBundleDestroyPlan {
  rejectSensitiveResponse(value);
  const plan = exactRecord(value, [
    "bundleId", "commerceDataLossRequiresConfirmation", "expiresAtUnixMs", "planHash",
    "resources", "schemaVersion",
  ]);
  if (!Array.isArray(plan.resources)
    || typeof plan.commerceDataLossRequiresConfirmation !== "boolean") {
    throw new Error("Access destroy plan is invalid");
  }
  return Object.freeze({
    schemaVersion: positiveInteger(plan.schemaVersion),
    planHash: hash(plan.planHash),
    bundleId: requiredString(plan.bundleId, "bundleId", 128),
    resources: Object.freeze(plan.resources.map((candidate) => {
      const resource = exactRecord(candidate, [
        "deleteRequiresConfirmation", "ownership", "resourceId", "resources", "target",
      ]);
      if (!Array.isArray(resource.resources)
        || !["exclusive", "shared"].includes(String(resource.ownership))
        || typeof resource.deleteRequiresConfirmation !== "boolean") {
        throw new Error("Access destroy resource is invalid");
      }
      return Object.freeze({
        resourceId: requiredString(resource.resourceId, "resourceId", 128),
        target: parseTarget(resource.target),
        resources: Object.freeze(resource.resources.map((item) => requiredString(item, "resource", 512))),
        ownership: resource.ownership as "exclusive" | "shared",
        deleteRequiresConfirmation: resource.deleteRequiresConfirmation,
      });
    })),
    commerceDataLossRequiresConfirmation: plan.commerceDataLossRequiresConfirmation,
    expiresAtUnixMs: positiveInteger(plan.expiresAtUnixMs),
  });
}

function parseDestroyReceipt(value: unknown): DeveloperAccessBundleDestroyReceipt {
  rejectSensitiveResponse(value);
  const receipt = exactRecord(value, [
    "completedAtUnixMs", "operationId", "outcome", "planHash", "resources", "schemaVersion",
  ]);
  return Object.freeze({
    schemaVersion: positiveInteger(receipt.schemaVersion),
    planHash: hash(receipt.planHash),
    operationId: uuid(receipt.operationId),
    outcome: mutationOutcome(receipt.outcome),
    resources: parseLifecycleResources(receipt.resources),
    completedAtUnixMs: positiveInteger(receipt.completedAtUnixMs),
  });
}

function parseLifecycleResources(
  value: unknown,
): Readonly<Record<string, DeveloperAccessBundleLifecycleResourceReceipt>> {
  return Object.freeze(Object.fromEntries(Object.entries(record(value)).map(([id, candidate]) => {
    const resource = exactRecord(candidate, [
      "configuredRevision", "errorCode", "previousVersionId", "resourceId", "rollbackBoundary",
      "safeMessage", "status", "target", "versionId",
    ]);
    if (!new Set(["applied", "already_converged", "failed", "uncertain", "blocked"])
      .has(String(resource.status))) throw new Error("Access lifecycle resource status is invalid");
    return [id, Object.freeze({
      resourceId: requiredString(resource.resourceId, "resourceId", 128),
      target: parseTarget(resource.target),
      status: resource.status as DeveloperAccessBundleLifecycleResourceReceipt["status"],
      versionId: nullableString(resource.versionId, 256),
      previousVersionId: nullableString(resource.previousVersionId, 256),
      configuredRevision: nullableString(resource.configuredRevision, 256),
      rollbackBoundary: resource.rollbackBoundary,
      errorCode: nullableString(resource.errorCode, 128),
      safeMessage: nullableString(resource.safeMessage, 500),
    })];
  })));
}

function parseBundleTest(value: unknown): DeveloperAccessBundleTestReceipt {
  const receipt = exactRecord(value, [
    "commerce", "entitlementPolicy", "gateway", "projectionSecretRevision", "testedAtUnixMs",
  ]);
  const commerce = receipt.commerce === null ? null : (() => {
    const result = exactRecord(receipt.commerce, [
      "capabilities", "databaseId", "migrationHash", "portalVerifiedAtUnixMs", "webhookVerifiedAtUnixMs",
    ]);
    if (!Array.isArray(result.capabilities)) throw new Error("Commerce verification is invalid");
    return Object.freeze({
      databaseId: requiredString(result.databaseId, "databaseId", 128),
      migrationHash: hash(result.migrationHash),
      capabilities: Object.freeze(result.capabilities.map((item) => requiredString(item, "capability", 128))),
      webhookVerifiedAtUnixMs: nullableInteger(result.webhookVerifiedAtUnixMs),
      portalVerifiedAtUnixMs: nullableInteger(result.portalVerifiedAtUnixMs),
    });
  })();
  return Object.freeze({
    gateway: parseTest(receipt.gateway),
    entitlementPolicy: parseTest(receipt.entitlementPolicy),
    commerce,
    projectionSecretRevision: requiredString(
      receipt.projectionSecretRevision,
      "projectionSecretRevision",
      256,
    ),
    testedAtUnixMs: positiveInteger(receipt.testedAtUnixMs),
  });
}

function parseTest(value: unknown): DeveloperGatewayTestReceipt {
  const test = exactRecord(value, ["protocolVersion", "remoteVersion", "target", "testedAtUnixMs"]);
  return Object.freeze({
    target: parseTarget(test.target),
    protocolVersion: requiredString(test.protocolVersion, "protocolVersion", 64),
    remoteVersion: requiredString(test.remoteVersion, "remoteVersion", 256),
    testedAtUnixMs: positiveInteger(test.testedAtUnixMs),
  });
}

function parseObservation(value: unknown) {
  const observation = exactRecord(value, [
    "activeArtifactHash", "d1MigrationStatus", "endpoint", "gatewayProtocolVersion",
    "observedAtUnixMs", "observedDesiredHash", "reachability", "remoteEtag", "remoteVersion",
    "target", "workersDevReady",
  ]);
  if (!new Set(["reachable", "missing", "unauthorized", "unreachable"])
    .has(String(observation.reachability))
    || (observation.workersDevReady !== null && typeof observation.workersDevReady !== "boolean")) {
    throw new Error("Access observation is invalid");
  }
  return Object.freeze({
    target: parseTarget(observation.target),
    reachability: observation.reachability as "reachable" | "missing" | "unauthorized" | "unreachable",
    remoteVersion: nullableString(observation.remoteVersion, 256),
    remoteEtag: nullableString(observation.remoteEtag, 512),
    observedDesiredHash: nullableString(observation.observedDesiredHash, 128),
    activeArtifactHash: nullableString(observation.activeArtifactHash, 128),
    endpoint: nullableString(observation.endpoint, 2048),
    gatewayProtocolVersion: nullableString(observation.gatewayProtocolVersion, 64),
    d1MigrationStatus: nullableString(observation.d1MigrationStatus, 128),
    workersDevReady: observation.workersDevReady as boolean | null,
    observedAtUnixMs: positiveInteger(observation.observedAtUnixMs),
  });
}

function parseTarget(value: unknown): DeveloperGatewayDeploymentReceipt["target"] {
  const target = exactRecord(value, ["accountId", "deploymentId", "environment", "workerName"], true);
  return Object.freeze({
    accountId: requiredString(target.accountId, "accountId", 64),
    deploymentId: requiredString(target.deploymentId, "deploymentId", 128),
    workerName: requiredString(target.workerName, "workerName", 63),
    ...(target.environment === undefined
      ? {}
      : { environment: requiredString(target.environment, "environment", 32) }),
  });
}

function mutationOutcome(value: unknown): DeveloperAccessBundleMutationOutcome {
  const outcomes = new Set<DeveloperAccessBundleMutationOutcome>([
    "succeeded", "failed_before_activation", "entitlement_ready_gateway_failed",
    "verification_failed", "partial", "uncertain_remote_state",
  ]);
  if (!outcomes.has(value as DeveloperAccessBundleMutationOutcome)) {
    throw new Error("Access lifecycle outcome is invalid");
  }
  return value as DeveloperAccessBundleMutationOutcome;
}

function noInput(value: unknown): void {
  if (value !== undefined) throw new Error("Access lifecycle operation does not accept input");
}

function hash(value: unknown): string {
  const result = requiredString(value, "hash", 71).replace(/^sha256:/, "");
  if (!PLAN_HASH.test(result)) throw new Error("Access lifecycle hash is invalid");
  return result;
}

function uuid(value: unknown): string {
  const result = requiredString(value, "operationId", 36);
  if (!UUID.test(result)) throw new Error("Access lifecycle operation ID is invalid");
  return result;
}

function positiveInteger(value: unknown): number {
  if (!Number.isSafeInteger(value) || Number(value) <= 0) {
    throw new Error("Access lifecycle integer is invalid");
  }
  return Number(value);
}

function nullableInteger(value: unknown): number | null {
  return value === null ? null : positiveInteger(value);
}

function nullableString(value: unknown, maximum: number): string | null {
  return value === null ? null : requiredString(value, "value", maximum);
}

function requiredString(value: unknown, label: string, maximum: number): string {
  if (typeof value !== "string" || value === "" || value !== value.trim()
    || value.length > maximum || /[\x00-\x1f\x7f]/.test(value)) {
    throw new Error(`Access lifecycle ${label} is invalid`);
  }
  return value;
}

function exactRecord(value: unknown, keys: readonly string[], optional = false): Record<string, unknown> {
  const result = record(value);
  const actual = Object.keys(result);
  if (actual.some((key) => !keys.includes(key))
    || (!optional && keys.some((key) => !Object.hasOwn(result, key)))) {
    throw new Error("Access lifecycle response is invalid");
  }
  return result;
}

function record(value: unknown): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error("Access lifecycle response is invalid");
  }
  return value as Record<string, unknown>;
}

function rejectSensitiveResponse(value: unknown): void {
  const serialized = JSON.stringify(value);
  if (serialized.length > 1024 * 1024
    || /(?:apiKey|secretValue|accessToken|refreshToken|authorization)\s*["']/i.test(serialized)) {
    throw new Error("Access lifecycle response contains prohibited data");
  }
}
