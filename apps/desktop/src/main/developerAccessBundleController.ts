import type {
  DeveloperAccessBundlePlan,
  DeveloperAccessBundleReceipt,
  DeveloperAccessBundleResourceReceipt,
  DeveloperAccessBundleTestReceipt,
  DeveloperAccessRequest,
  DeveloperPendingAccessBundle,
  DeveloperGatewayDeploymentReceipt,
  DeveloperGatewayTestReceipt,
} from "../shared/developerAccess";
import type { DeveloperProjectSnapshot } from "../shared/developerProject";

const PLAN_HASH = /^[a-f0-9]{64}$/;
const PROJECT_REVISION = /^[a-f0-9]{64}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const ACCESS_OPERATIONS = new Set([
  "access.plan", "access.apply", "access.test", "commerce.creem.products",
]);

type RequestDescription = Readonly<{
  body?: unknown;
  method: "POST";
  pathname: string;
}>;

export type DeveloperAccessBundleProjectCallbacks = Readonly<{
  record: (expectedRevision: string, receipt: DeveloperAccessBundleReceipt) => Promise<DeveloperProjectSnapshot>;
  verify: (
    bundle: DeveloperAccessBundleReceipt,
    expectedRevision: string,
    test: DeveloperAccessBundleTestReceipt,
  ) => Promise<DeveloperProjectSnapshot>;
}>;

export function createDeveloperAccessBundleController(options: {
  loadProject: () => Promise<DeveloperProjectSnapshot>;
  recordBundle?: (
    expectedRevision: string,
    receipt: DeveloperAccessBundleReceipt,
  ) => Promise<DeveloperProjectSnapshot>;
  requestJson: (description: RequestDescription) => Promise<unknown>;
  verifyBundle?: (
    bundle: DeveloperAccessBundleReceipt,
    expectedRevision: string,
    test: DeveloperAccessBundleTestReceipt,
  ) => Promise<DeveloperProjectSnapshot>;
}) {
  const planRevisions = new Map<string, string>();
  let pending: DeveloperPendingAccessBundle | null = null;

  return Object.freeze({
    handles(operation: string): boolean {
      return ACCESS_OPERATIONS.has(operation);
    },
    pending(): DeveloperPendingAccessBundle | null {
      return pending;
    },
    clear(): void {
      planRevisions.clear();
      pending = null;
    },
    async handle(request: DeveloperAccessRequest): Promise<unknown> {
      switch (request.operation) {
        case "access.plan": {
          const snapshot = await options.loadProject();
          const { body, revision } = planRequest(request.input, snapshot);
          const response = parsePlan(await options.requestJson({
            body,
            method: "POST",
            pathname: "/dev/control/access/plan",
          }));
          const current = await options.loadProject();
          if (current.revision !== revision) {
            throw new Error("Developer project changed while the access plan was created");
          }
          planRevisions.set(response.planHash, revision);
          return response;
        }
        case "access.apply": {
          const planHash = parsePlanHash(request.input);
          const expectedRevision = planRevisions.get(planHash);
          const current = await options.loadProject();
          if (!expectedRevision || current.revision !== expectedRevision) {
            throw new Error("Access plan is unavailable or stale; create a new plan");
          }
          const bundle = parseBundleReceipt(await options.requestJson({
            body: { planHash },
            method: "POST",
            pathname: "/dev/control/access/apply",
          }));
          if (bundle.outcome !== "succeeded") {
            return Object.freeze({ bundle, project: current });
          }
          if (!options.recordBundle) {
            throw new Error("Access bundle project recording is unavailable");
          }
          const project = await options.recordBundle(expectedRevision, bundle);
          pending = Object.freeze({ bundle, projectRevision: project.revision });
          planRevisions.delete(planHash);
          return Object.freeze({ bundle, project });
        }
        case "access.test": {
          noInput(request.input);
          if (!pending) throw new Error("A newly applied access bundle is required before verification");
          const targets = bundleTargets(pending.bundle);
          const test = parseBundleTestReceipt(await options.requestJson({
            body: targets,
            method: "POST",
            pathname: "/dev/control/access/test",
          }));
          if (!options.verifyBundle) {
            throw new Error("Access bundle project verification is unavailable");
          }
          const project = await options.verifyBundle(
            pending.bundle,
            pending.projectRevision,
            test,
          );
          pending = null;
          return Object.freeze({ project, test });
        }
        case "commerce.creem.products": {
          const input = exactRecord(request.input, ["apiKey", "environment", "revision"]);
          const environment = input.environment;
          if (environment !== "test" && environment !== "production") {
            throw new Error("Creem environment is invalid");
          }
          return parseProductDiscovery(await options.requestJson({
            body: {
              environment,
              revision: requiredString(input.revision, "revision", 256),
              apiKey: requiredString(input.apiKey, "apiKey", 64 * 1024),
            },
            method: "POST",
            pathname: "/dev/control/commerce/creem/products",
          }));
        }
        default:
          throw new Error("Developer access bundle operation is invalid");
      }
    },
  });
}

function planRequest(value: unknown, snapshot: DeveloperProjectSnapshot) {
  const input = exactRecord(value, [
    "expectedProjectRevision",
    "expectedResources",
    "idempotencyKey",
    "sensitiveInputs",
  ], true);
  const revision = requiredString(input.expectedProjectRevision, "expectedProjectRevision", 64);
  if (!PROJECT_REVISION.test(revision) || snapshot.revision !== revision) {
    throw new Error("Developer project changed; reload before planning the access deployment");
  }
  const project = exactRecord(snapshot.project, [
    "deployment",
    "modelAccess",
    "providers",
    "schemaVersion",
  ]);
  if (project.schemaVersion !== 2) throw new Error("Managed access deployment requires project schema v2");
  const providers = exactRecord(project.providers, ["commerce", "entitlement", "gateway", "identity"]);
  const body = {
    project: {
      projectRevision: revision,
      appId: requiredString(snapshot.manifest.appId, "appId", 255),
      providers,
      modelAccess: project.modelAccess,
      deployment: project.deployment,
    },
    sensitiveInputs: boundedObject(input.sensitiveInputs),
    ...(input.idempotencyKey === undefined
      ? {}
      : { idempotencyKey: requiredString(input.idempotencyKey, "idempotencyKey", 256) }),
    ...(input.expectedResources === undefined
      ? {}
      : { expectedResources: boundedObject(input.expectedResources) }),
  };
  boundedJson(body);
  return { body, revision };
}

function parsePlan(value: unknown): DeveloperAccessBundlePlan {
  rejectSensitiveResponse(value);
  const plan = exactRecord(value, [
    "bundleId",
    "desiredHash",
    "expiresAtUnixMs",
    "planHash",
    "resources",
    "schemaVersion",
  ]);
  const planHash = hash(plan.planHash, "Access plan hash");
  const desiredHash = hash(plan.desiredHash, "Access desired hash");
  if (!Array.isArray(plan.resources) || plan.resources.length < 2 || plan.resources.length > 128) {
    throw new Error("Access deployment plan resources are invalid");
  }
  const resources = plan.resources.map((candidate) => {
    const resource = exactRecord(candidate, [
      "dependencies", "drift", "kind", "operations", "ownership", "purpose", "resourceId", "target",
    ]);
    if (!Array.isArray(resource.dependencies) || !Array.isArray(resource.operations)) {
      throw new Error("Access deployment plan resource is invalid");
    }
    return Object.freeze({
      resourceId: requiredString(resource.resourceId, "resourceId", 256),
      kind: requiredString(resource.kind, "kind", 64),
      purpose: requiredString(resource.purpose, "purpose", 64),
      dependencies: Object.freeze(resource.dependencies.map((entry) => requiredString(entry, "dependency", 256))),
      ownership: ownership(resource.ownership),
      target: parseTarget(resource.target),
      operations: Object.freeze(resource.operations.map(parseOperation)),
      drift: resource.drift ?? null,
    });
  });
  return Object.freeze({
    schemaVersion: safeInteger(plan.schemaVersion),
    bundleId: requiredString(plan.bundleId, "bundleId", 256),
    desiredHash,
    planHash,
    resources: Object.freeze(resources),
    expiresAtUnixMs: safeInteger(plan.expiresAtUnixMs),
  });
}

function parseBundleReceipt(value: unknown): DeveloperAccessBundleReceipt {
  rejectSensitiveResponse(value);
  const receipt = exactRecord(value, [
    "bundleId", "completedAtUnixMs", "operationId", "outcome", "planHash", "providerId",
    "providerVersion", "resources", "schemaVersion",
  ]);
  const resourcesValue = exactRecord(receipt.resources, [], true);
  const resources: Record<string, DeveloperAccessBundleResourceReceipt> = {};
  for (const [id, candidate] of Object.entries(resourcesValue)) {
    const resource = exactRecord(candidate, [
      "endpoint", "errorCode", "previousVersionId", "resourceId", "safeMessage", "status", "target", "versionId",
    ]);
    const resourceId = requiredString(resource.resourceId, "resourceId", 256);
    if (resourceId !== id) throw new Error("Access deployment resource receipt is misbound");
    resources[id] = Object.freeze({
      resourceId,
      status: resourceStatus(resource.status),
      target: parseTarget(resource.target),
      versionId: nullableString(resource.versionId, "versionId", 128),
      previousVersionId: nullableString(resource.previousVersionId, "previousVersionId", 128),
      endpoint: nullableHttpsUrl(resource.endpoint),
      errorCode: nullableString(resource.errorCode, "errorCode", 128),
      safeMessage: nullableString(resource.safeMessage, "safeMessage", 1024),
    });
  }
  if (!resources["model-gateway"] || !resources["entitlement-policy"]) {
    throw new Error("Access deployment Worker receipts are incomplete");
  }
  return Object.freeze({
    schemaVersion: safeInteger(receipt.schemaVersion),
    providerId: requiredString(receipt.providerId, "providerId", 128),
    providerVersion: requiredString(receipt.providerVersion, "providerVersion", 64),
    bundleId: requiredString(receipt.bundleId, "bundleId", 256),
    planHash: hash(receipt.planHash, "Access plan hash"),
    operationId: uuid(receipt.operationId),
    outcome: bundleOutcome(receipt.outcome),
    resources: Object.freeze(resources),
    completedAtUnixMs: safeInteger(receipt.completedAtUnixMs),
  });
}

function parseBundleTestReceipt(value: unknown): DeveloperAccessBundleTestReceipt {
  rejectSensitiveResponse(value);
  const receipt = exactRecord(value, [
    "commerce", "entitlementPolicy", "gateway", "projectionSecretRevision", "testedAtUnixMs",
  ]);
  const commerce = receipt.commerce === null ? null : (() => {
    const result = exactRecord(receipt.commerce, [
      "capabilities", "databaseId", "migrationHash", "portalVerifiedAtUnixMs", "webhookVerifiedAtUnixMs",
    ]);
    if (!Array.isArray(result.capabilities) || result.capabilities.length > 64) {
      throw new Error("Commerce verification capabilities are invalid");
    }
    return Object.freeze({
      databaseId: requiredString(result.databaseId, "databaseId", 128),
      migrationHash: hash(result.migrationHash, "Commerce migration hash"),
      capabilities: Object.freeze(result.capabilities.map((entry) => requiredString(entry, "capability", 128))),
      webhookVerifiedAtUnixMs: nullableInteger(result.webhookVerifiedAtUnixMs),
      portalVerifiedAtUnixMs: nullableInteger(result.portalVerifiedAtUnixMs),
    });
  })();
  return Object.freeze({
    gateway: parseTestReceipt(receipt.gateway),
    entitlementPolicy: parseTestReceipt(receipt.entitlementPolicy),
    commerce,
    projectionSecretRevision: requiredString(
      receipt.projectionSecretRevision,
      "projectionSecretRevision",
      256,
    ),
    testedAtUnixMs: safeInteger(receipt.testedAtUnixMs),
  });
}

function parseProductDiscovery(value: unknown) {
  rejectSensitiveResponse(value);
  const receipt = exactRecord(value, ["configuredRevision", "environment", "products"]);
  if (receipt.environment !== "test" && receipt.environment !== "production") {
    throw new Error("Creem product discovery environment is invalid");
  }
  if (!Array.isArray(receipt.products) || receipt.products.length > 1024) {
    throw new Error("Creem product discovery response is invalid");
  }
  return Object.freeze({
    environment: receipt.environment,
    configuredRevision: requiredString(receipt.configuredRevision, "configuredRevision", 256),
    products: Object.freeze(receipt.products.map((candidate) => {
      const product = exactRecord(candidate, [
        "active", "billingPeriod", "billingType", "currency", "description", "environment",
        "id", "name", "priceMinor",
      ]);
      if (typeof product.active !== "boolean" || product.environment !== receipt.environment) {
        throw new Error("Creem product is invalid");
      }
      return Object.freeze({
        id: requiredString(product.id, "productId", 256),
        name: requiredString(product.name, "productName", 512),
        description: boundedText(product.description, "productDescription", 2048),
        environment: receipt.environment,
        priceMinor: nonNegativeInteger(product.priceMinor),
        currency: requiredString(product.currency, "currency", 16),
        billingType: requiredString(product.billingType, "billingType", 64),
        billingPeriod: requiredString(product.billingPeriod, "billingPeriod", 64),
        active: product.active,
      });
    })),
  });
}

function bundleTargets(bundle: DeveloperAccessBundleReceipt) {
  const gateway = bundle.resources["model-gateway"];
  const entitlement = bundle.resources["entitlement-policy"];
  if (!gateway || !entitlement) throw new Error("Access bundle targets are unavailable");
  return { gateway: gateway.target, entitlementPolicy: entitlement.target };
}

function parseTestReceipt(value: unknown): DeveloperGatewayTestReceipt {
  const receipt = exactRecord(value, ["protocolVersion", "remoteVersion", "target", "testedAtUnixMs"]);
  return Object.freeze({
    target: parseTarget(receipt.target),
    protocolVersion: requiredString(receipt.protocolVersion, "protocolVersion", 64),
    remoteVersion: requiredString(receipt.remoteVersion, "remoteVersion", 128),
    testedAtUnixMs: safeInteger(receipt.testedAtUnixMs),
  });
}

function parseTarget(value: unknown): DeveloperGatewayDeploymentReceipt["target"] {
  const target = exactRecord(value, ["accountId", "deploymentId", "environment", "workerName"], true);
  return Object.freeze({
    accountId: requiredString(target.accountId, "accountId", 256),
    deploymentId: requiredString(target.deploymentId, "deploymentId", 128),
    workerName: requiredString(target.workerName, "workerName", 128),
    ...(target.environment === undefined
      ? {}
      : { environment: requiredString(target.environment, "environment", 32) }),
  });
}

function parseOperation(value: unknown) {
  const operation = exactRecord(value, ["destructive", "kind", "resource"]);
  if (typeof operation.destructive !== "boolean") throw new Error("Access plan operation is invalid");
  return Object.freeze({
    destructive: operation.destructive,
    kind: requiredString(operation.kind, "kind", 64),
    resource: requiredString(operation.resource, "resource", 512),
  });
}

function parsePlanHash(value: unknown): string {
  const input = exactRecord(value, ["planHash"]);
  return hash(input.planHash, "Access plan hash");
}

function boundedObject(value: unknown): Record<string, unknown> {
  const result = exactRecord(value, [], true);
  boundedJson(result);
  return result;
}

function boundedJson(value: unknown): void {
  const text = JSON.stringify(value);
  if (text.length > 2 * 1024 * 1024) throw new Error("Developer access request is too large");
}

function exactRecord(value: unknown, keys: string[], allowOptional = false): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Developer access value is invalid");
  const result = value as Record<string, unknown>;
  const allowed = new Set(keys);
  if ((!allowOptional && Object.keys(result).length !== keys.length)
    || Object.keys(result).some((key) => !allowed.has(key))) {
    throw new Error("Developer access value has unexpected fields");
  }
  return result;
}

function requiredString(value: unknown, label: string, max: number): string {
  if (typeof value !== "string" || !value || value.length > max || /[\r\n\0]/.test(value)) {
    throw new Error(`${label} is invalid`);
  }
  return value;
}

function boundedText(value: unknown, label: string, max: number): string {
  if (typeof value !== "string" || value.length > max || /[\r\0]/.test(value)) {
    throw new Error(`${label} is invalid`);
  }
  return value;
}

function nullableString(value: unknown, label: string, max: number): string | null {
  return value === null ? null : requiredString(value, label, max);
}

function nullableHttpsUrl(value: unknown): string | null {
  if (value === null) return null;
  const text = requiredString(value, "endpoint", 2048);
  const parsed = new URL(text);
  if (parsed.protocol !== "https:" || parsed.username || parsed.password) throw new Error("Endpoint is invalid");
  return text;
}

function safeInteger(value: unknown): number {
  if (!Number.isSafeInteger(value) || Number(value) <= 0) throw new Error("Developer access integer is invalid");
  return Number(value);
}

function nonNegativeInteger(value: unknown): number {
  if (!Number.isSafeInteger(value) || Number(value) < 0) {
    throw new Error("Developer access integer is invalid");
  }
  return Number(value);
}

function nullableInteger(value: unknown): number | null {
  return value === null ? null : safeInteger(value);
}

function hash(value: unknown, label: string): string {
  const result = requiredString(value, label, 71);
  if (!/^(?:sha256:)?[a-f0-9]{64}$/.test(result)) throw new Error(`${label} is invalid`);
  return result.replace(/^sha256:/, "");
}

function uuid(value: unknown): string {
  const result = requiredString(value, "operationId", 64);
  if (!UUID.test(result)) throw new Error("Access operation receipt is invalid");
  return result;
}

function ownership(value: unknown): "exclusive" | "shared" {
  if (value !== "exclusive" && value !== "shared") throw new Error("Access resource ownership is invalid");
  return value;
}

function resourceStatus(value: unknown): DeveloperAccessBundleResourceReceipt["status"] {
  if (!["applied", "already_converged", "failed", "uncertain", "blocked"].includes(String(value))) {
    throw new Error("Access resource status is invalid");
  }
  return value as DeveloperAccessBundleResourceReceipt["status"];
}

function bundleOutcome(value: unknown): DeveloperAccessBundleReceipt["outcome"] {
  if (![
    "succeeded", "failed_before_activation", "entitlement_ready_gateway_failed",
    "gateway_active_verification_failed", "uncertain_remote_state",
  ].includes(String(value))) throw new Error("Access bundle outcome is invalid");
  return value as DeveloperAccessBundleReceipt["outcome"];
}

function noInput(value: unknown): void {
  if (value !== undefined) throw new Error("Developer access operation does not accept input");
}

function rejectSensitiveResponse(value: unknown): void {
  const stack: unknown[] = [value];
  while (stack.length > 0) {
    const current = stack.pop();
    if (!current || typeof current !== "object") continue;
    if (Array.isArray(current)) {
      stack.push(...current);
      continue;
    }
    for (const [key, child] of Object.entries(current as Record<string, unknown>)) {
      const normalized = key.toLowerCase().replaceAll(/[^a-z0-9]/g, "");
      if (/(?:apikey|password|credential|secretvalue|tokenvalue)/.test(normalized)) {
        throw new Error("Developer access response exposed sensitive material");
      }
      stack.push(child);
    }
  }
}
