import { createHash } from "node:crypto";
import {
  existsSync,
  lstatSync,
  readFileSync,
  statSync,
} from "node:fs";
import { join } from "node:path";

export const AGENTWEAVE_PROJECT_SCHEMA_VERSION = 2;
export const DEPLOYMENT_LOCK_SCHEMA_VERSION = 2;
export const RUNTIME_PROVIDER_MANIFEST_SCHEMA_VERSION = 2;
export const AGENTWEAVE_PROJECT_FILE = "agentweave-project.json";
export const DEPLOYMENT_LOCK_RELATIVE_PATH = ".agentweave/deployment.lock";

const MAX_DOCUMENT_BYTES = 256 * 1024;
const MAX_PUBLIC_CONFIG_DEPTH = 16;
const MAX_PUBLIC_CONFIG_NODES = 2048;
const MAX_OBJECT_KEYS = 128;
const MAX_ARRAY_ITEMS = 256;
const MAX_STRING_BYTES = 8192;
const HASH_PATTERN = /^sha256:[0-9a-f]{64}$/;
const SEMVER_PATTERN = /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/;
const PLUGIN_ID_PATTERN = /^[a-z0-9]+(?:[._-][a-z0-9]+)*$/;
const WORKER_NAME_PATTERN = /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/;
const ENVIRONMENT_PATTERN = /^[a-z0-9](?:[a-z0-9-]{0,30}[a-z0-9])?$/;
const SECRET_FIELD_PATTERNS = [
  /apikey/,
  /credential/,
  /password/,
  /passphrase/,
  /privatekey/,
  /clientsecret/,
  /(?:access|refresh|bearer|identity|id|oauth)token(?:value|handle|secret)?$/,
  /^(?:secret|token)(?:value|handle)?$/,
];
const SECRET_VALUE_PATTERNS = [
  /-----BEGIN (?:EC |OPENSSH |RSA )?PRIVATE KEY-----/,
  /\bBearer\s+[A-Za-z0-9._~+/-]{12,}={0,2}\b/i,
  /\bsk[-_][A-Za-z0-9_-]{16,}\b/,
  /\bgh[pousr]_[A-Za-z0-9]{20,}\b/,
  /\bxox[baprs]-[A-Za-z0-9-]{16,}\b/,
  /\bAKIA[0-9A-Z]{16}\b/,
];

function fail(message) {
  throw new Error(message);
}

function hasOwn(value, key) {
  return Object.prototype.hasOwnProperty.call(value, key);
}

function isPlainObject(value) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return false;
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}

function requireObject(value, label) {
  if (!isPlainObject(value)) fail(`${label} must be an object`);
  return value;
}

function requireOnlyKeys(value, allowed, label) {
  const allowedKeys = new Set(allowed);
  for (const key of Object.keys(value)) {
    if (!allowedKeys.has(key)) fail(`${label} contains unknown field '${key}'`);
  }
}

function requireFields(value, required, label) {
  for (const field of required) {
    if (!hasOwn(value, field)) fail(`${label}.${field} is required`);
  }
}

function requireString(value, label, { maxBytes = MAX_STRING_BYTES } = {}) {
  if (
    typeof value !== "string"
    || value.trim() === ""
    || value !== value.trim()
    || /[\u0000-\u001f\u007f]/.test(value)
    || Buffer.byteLength(value, "utf8") > maxBytes
  ) {
    fail(`${label} must be a non-empty bounded string without control characters`);
  }
  return value;
}

function requireInteger(value, label) {
  if (!Number.isInteger(value)) fail(`${label} must be an integer`);
  return value;
}

function requireSchemaVersion(value, supported, label) {
  requireInteger(value, label);
  if (value > supported) fail(`${label} ${value} is newer than supported version ${supported}`);
  if (value !== supported) fail(`${label} ${value} is unsupported; expected ${supported}`);
}

function requireCompatibleSchemaVersion(value, supported, label) {
  requireInteger(value, label);
  if (value > supported) fail(`${label} ${value} is newer than supported version ${supported}`);
  if (value < 1) fail(`${label} ${value} is unsupported`);
  return value;
}

function requireSemver(value, label) {
  requireString(value, label, { maxBytes: 128 });
  if (!SEMVER_PATTERN.test(value)) fail(`${label} must be a semantic version`);
  return value;
}

function requirePluginId(value, label) {
  requireString(value, label, { maxBytes: 128 });
  if (!PLUGIN_ID_PATTERN.test(value)) {
    fail(`${label} must be a lowercase plugin identifier`);
  }
  return value;
}

function normalizeSensitiveFieldName(value) {
  return value.toLowerCase().replaceAll(/[^a-z0-9]/g, "");
}

export function isSensitiveProjectFieldName(value) {
  const normalized = normalizeSensitiveFieldName(value);
  return SECRET_FIELD_PATTERNS.some((pattern) => pattern.test(normalized));
}

function rejectKnownSecretValue(value, label) {
  if (SECRET_VALUE_PATTERNS.some((pattern) => pattern.test(value))) {
    fail(`${label} must not contain secret material`);
  }
}

export function rejectNonPublicConfig(value, label = "public configuration") {
  const state = { nodes: 0 };
  function visit(current, path, depth) {
    state.nodes += 1;
    if (state.nodes > MAX_PUBLIC_CONFIG_NODES) {
      fail(`${label} exceeds ${MAX_PUBLIC_CONFIG_NODES} JSON values`);
    }
    if (depth > MAX_PUBLIC_CONFIG_DEPTH) {
      fail(`${label} exceeds nesting depth ${MAX_PUBLIC_CONFIG_DEPTH}`);
    }
    if (current === null || typeof current === "boolean") return;
    if (typeof current === "number") {
      if (!Number.isFinite(current)) fail(`${path} must be a finite JSON number`);
      return;
    }
    if (typeof current === "string") {
      if (Buffer.byteLength(current, "utf8") > MAX_STRING_BYTES) {
        fail(`${path} exceeds ${MAX_STRING_BYTES} UTF-8 bytes`);
      }
      rejectKnownSecretValue(current, path);
      return;
    }
    if (Array.isArray(current)) {
      if (current.length > MAX_ARRAY_ITEMS) {
        fail(`${path} exceeds ${MAX_ARRAY_ITEMS} array items`);
      }
      current.forEach((entry, index) => visit(entry, `${path}[${index}]`, depth + 1));
      return;
    }
    if (!isPlainObject(current)) fail(`${path} must contain only JSON values`);
    const keys = Object.keys(current);
    if (keys.length > MAX_OBJECT_KEYS) fail(`${path} exceeds ${MAX_OBJECT_KEYS} fields`);
    for (const [key, child] of Object.entries(current)) {
      if (
        key.trim() === ""
        || key !== key.trim()
        || /[\u0000-\u001f\u007f]/.test(key)
        || Buffer.byteLength(key, "utf8") > 128
        || ["__proto__", "constructor", "prototype"].includes(key)
      ) {
        fail(`${path} contains an invalid field name`);
      }
      if (isSensitiveProjectFieldName(key)) {
        fail(`${path}.${key} must not contain secret material`);
      }
      visit(child, `${path}.${key}`, depth + 1);
    }
  }
  visit(value, label, 0);
  return value;
}

function canonicalJson(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (isPlainObject(value)) {
    return `{${Object.keys(value).sort().map((key) => (
      `${JSON.stringify(key)}:${canonicalJson(value[key])}`
    )).join(",")}}`;
  }
  return JSON.stringify(value);
}

export function hashPublicValue(value) {
  return `sha256:${createHash("sha256").update(canonicalJson(value), "utf8").digest("hex")}`;
}

function cloneJson(value) {
  return JSON.parse(JSON.stringify(value));
}

function validateProviderSelection(value, label) {
  const provider = requireObject(value, label);
  requireOnlyKeys(provider, ["id", "version", "publicConfig"], label);
  requireFields(provider, ["id", "version", "publicConfig"], label);
  requirePluginId(provider.id, `${label}.id`);
  requireSemver(provider.version, `${label}.version`);
  requireObject(provider.publicConfig, `${label}.publicConfig`);
  rejectNonPublicConfig(provider.publicConfig, `${label}.publicConfig`);
  return provider;
}

function validateOptionalProviderSelection(value, label) {
  return value === null ? null : validateProviderSelection(value, label);
}

function parsePublicUrl(value, label, { allowLoopbackHttp = true } = {}) {
  requireString(value, label, { maxBytes: 2048 });
  let parsed;
  try {
    parsed = new URL(value);
  } catch {
    fail(`${label} must be an absolute URL`);
  }
  if (parsed.username || parsed.password || parsed.search || parsed.hash) {
    fail(`${label} must not contain credentials, a query, or a fragment`);
  }
  const loopback = parsed.hostname === "localhost"
    || parsed.hostname.endsWith(".localhost")
    || parsed.hostname === "127.0.0.1"
    || parsed.hostname === "::1";
  if (parsed.protocol !== "https:" && !(allowLoopbackHttp && loopback && parsed.protocol === "http:")) {
    fail(`${label} must use HTTPS, except for an HTTP loopback endpoint`);
  }
  return { parsed, loopback };
}

function validatePublicHeaders(value, label) {
  const headers = requireObject(value, label);
  if (Object.keys(headers).length > 32) fail(`${label} must contain at most 32 headers`);
  for (const [name, headerValue] of Object.entries(headers)) {
    if (!/^[!#$%&'*+.^_`|~0-9A-Za-z-]+$/.test(name)) fail(`${label} contains an invalid header name`);
    const normalized = name.toLowerCase();
    if (
      normalized === "authorization"
      || normalized === "proxy-authorization"
      || normalized === "cookie"
      || normalized === "set-cookie"
      || isSensitiveProjectFieldName(name)
    ) {
      fail(`${label}.${name} must not carry credentials`);
    }
    requireString(headerValue, `${label}.${name}`, { maxBytes: 2048 });
  }
}

function validateModelAccess(value, label) {
  const modelAccess = requireObject(value, label);
  requireOnlyKeys(modelAccess, ["configurationPolicy", "profile"], label);
  requireFields(modelAccess, ["configurationPolicy"], label);
  if (!["user_configurable", "app_managed"].includes(modelAccess.configurationPolicy)) {
    fail(`${label}.configurationPolicy is unsupported`);
  }
  if (modelAccess.profile !== undefined) {
    const profile = requireObject(modelAccess.profile, `${label}.profile`);
    requireOnlyKeys(
      profile,
      ["providerId", "endpointType", "baseUrl", "modelName", "authentication", "headers"],
      `${label}.profile`,
    );
    requireFields(
      profile,
      ["providerId", "endpointType", "baseUrl", "modelName", "authentication"],
      `${label}.profile`,
    );
    requirePluginId(profile.providerId, `${label}.profile.providerId`);
    if (!["responses", "chat_completions", "completion"].includes(profile.endpointType)) {
      fail(`${label}.profile.endpointType is unsupported`);
    }
    parsePublicUrl(profile.baseUrl, `${label}.profile.baseUrl`);
    requireString(profile.modelName, `${label}.profile.modelName`, { maxBytes: 256 });
    if (!["none", "user_identity"].includes(profile.authentication)) {
      fail(`${label}.profile.authentication is unsupported`);
    }
    if (profile.headers !== undefined) validatePublicHeaders(profile.headers, `${label}.profile.headers`);
    rejectNonPublicConfig(profile, `${label}.profile`);
  }
  if (modelAccess.configurationPolicy === "app_managed" && modelAccess.profile === undefined) {
    fail(`${label}.profile is required for app_managed configuration`);
  }
  return modelAccess;
}

function validateIdentity(value, label) {
  const identity = requireObject(value, label);
  requireOnlyKeys(identity, ["mode", "provider"], label);
  requireFields(identity, ["mode"], label);
  if (!["local_single_user", "required"].includes(identity.mode)) fail(`${label}.mode is unsupported`);
  if (identity.mode === "required") {
    if (!hasOwn(identity, "provider")) fail(`${label}.provider is required`);
    validateProviderSelection(identity.provider, `${label}.provider`);
  } else if (hasOwn(identity, "provider")) {
    fail(`${label}.provider is not allowed in local_single_user mode`);
  }
  return identity;
}

function validateEntitlements(value, label) {
  const entitlements = requireObject(value, label);
  requireOnlyKeys(entitlements, ["mode", "provider"], label);
  requireFields(entitlements, ["mode"], label);
  if (!["disabled", "required"].includes(entitlements.mode)) fail(`${label}.mode is unsupported`);
  if (entitlements.mode === "required") {
    if (!hasOwn(entitlements, "provider")) fail(`${label}.provider is required`);
    validateProviderSelection(entitlements.provider, `${label}.provider`);
  } else if (hasOwn(entitlements, "provider")) {
    fail(`${label}.provider is not allowed in disabled mode`);
  }
  return entitlements;
}

function validateManagedRemotePolicy(projection, label) {
  const { modelAccess, identity, entitlements } = projection;
  if (modelAccess.configurationPolicy !== "app_managed") return;
  const { loopback } = parsePublicUrl(modelAccess.profile.baseUrl, `${label}.modelAccess.profile.baseUrl`);
  if (modelAccess.profile.authentication === "user_identity" && identity.mode !== "required") {
    fail(`${label}.identity must be required when model authentication uses user_identity`);
  }
  if (!loopback) {
    if (modelAccess.profile.authentication !== "user_identity") {
      fail(`${label}.modelAccess must use user_identity for a non-loopback app-managed endpoint`);
    }
    if (identity.mode !== "required" || entitlements.mode !== "required") {
      fail(`${label} must require identity and entitlements for a non-loopback app-managed endpoint`);
    }
  }
}

export function validateRuntimeProviderProjection(app, label = "agent app manifest") {
  requireObject(app, label);
  requireInteger(app.schemaVersion, `${label}.schemaVersion`);
  if (app.schemaVersion > RUNTIME_PROVIDER_MANIFEST_SCHEMA_VERSION) {
    fail(
      `${label}.schemaVersion ${app.schemaVersion} is newer than supported version ${RUNTIME_PROVIDER_MANIFEST_SCHEMA_VERSION}`,
    );
  }
  if (![1, RUNTIME_PROVIDER_MANIFEST_SCHEMA_VERSION].includes(app.schemaVersion)) {
    fail(`${label}.schemaVersion ${app.schemaVersion} is unsupported`);
  }
  const fields = ["modelAccess", "identity", "entitlements"];
  if (app.schemaVersion === 1) {
    const unexpected = fields.find((field) => hasOwn(app, field));
    if (unexpected) fail(`${label}.${unexpected} requires schemaVersion 2`);
    return {};
  }
  requireFields(app, fields, label);
  const projection = {
    modelAccess: validateModelAccess(app.modelAccess, `${label}.modelAccess`),
    identity: validateIdentity(app.identity, `${label}.identity`),
    entitlements: validateEntitlements(app.entitlements, `${label}.entitlements`),
  };
  rejectNonPublicConfig(projection, `${label} public provider projection`);
  validateManagedRemotePolicy(projection, label);
  return projection;
}

export function runtimeProviderProjection(app, label = "agent app manifest") {
  return cloneJson(validateRuntimeProviderProjection(app, label));
}

function validatePlanLimits(value, label) {
  const limits = requireObject(value, label);
  requireOnlyKeys(limits, ["maxRequests", "maxUnits", "maxConcurrency"], label);
  requireFields(limits, ["maxRequests", "maxUnits", "maxConcurrency"], label);
  for (const field of ["maxRequests", "maxUnits", "maxConcurrency"]) {
    requireInteger(limits[field], `${label}.${field}`);
    if (limits[field] < 0 || !Number.isSafeInteger(limits[field])) {
      fail(`${label}.${field} must be a non-negative safe integer; 0 means plan-level unlimited`);
    }
    if (field === "maxConcurrency" && limits[field] > 1000) {
      fail(`${label}.${field} must not exceed the gateway system ceiling`);
    }
  }
}

function validatePolicyPlan(value, label, { productRequired }) {
  const plan = requireObject(value, label);
  const keys = ["id", "displayName", "enabled", "allowedModels", "limits"];
  if (productRequired) keys.push("productId");
  requireOnlyKeys(plan, keys, label);
  requireFields(plan, productRequired ? keys : ["id", "displayName", "allowedModels", "limits"], label);
  requirePluginId(plan.id, `${label}.id`);
  requireString(plan.displayName, `${label}.displayName`, { maxBytes: 256 });
  if (plan.enabled !== undefined && typeof plan.enabled !== "boolean") {
    fail(`${label}.enabled must be a boolean`);
  }
  if (productRequired) {
    requireString(plan.productId, `${label}.productId`, { maxBytes: 256 });
    if (!/^prod_[A-Za-z0-9_]+$/.test(plan.productId)) fail(`${label}.productId is invalid`);
  }
  if (!Array.isArray(plan.allowedModels) || plan.allowedModels.length === 0 || plan.allowedModels.length > 128) {
    fail(`${label}.allowedModels must be a non-empty bounded array`);
  }
  plan.allowedModels.forEach((model, index) => {
    requireString(model, `${label}.allowedModels[${index}]`, { maxBytes: 256 });
  });
  if (new Set(plan.allowedModels).size !== plan.allowedModels.length) {
    fail(`${label}.allowedModels must not contain duplicates`);
  }
  validatePlanLimits(plan.limits, `${label}.limits`);
}

function validateManagedEntitlement(value, label) {
  const entitlement = requireObject(value, label);
  requireOnlyKeys(entitlement, ["mode", "workerName", "policy"], label);
  requireFields(entitlement, ["mode"], label);
  if (!["managed_worker", "external_service"].includes(entitlement.mode)) {
    fail(`${label}.mode is unsupported`);
  }
  if (entitlement.mode === "external_service") {
    if (entitlement.workerName !== undefined || entitlement.policy !== undefined) {
      fail(`${label} external_service mode cannot declare managed Worker state`);
    }
    return entitlement;
  }
  requireFields(entitlement, ["workerName", "policy"], label);
  requireString(entitlement.workerName, `${label}.workerName`, { maxBytes: 63 });
  if (!WORKER_NAME_PATTERN.test(entitlement.workerName)) {
    fail(`${label}.workerName must be a lowercase Worker name`);
  }
  const policy = requireObject(entitlement.policy, `${label}.policy`);
  requireOnlyKeys(policy, ["sourceMode", "tenantLimits", "uniformPlan", "productPlans"], `${label}.policy`);
  requireFields(policy, ["sourceMode", "tenantLimits"], `${label}.policy`);
  if (!["uniform_bounded", "commerce_provider"].includes(policy.sourceMode)) {
    fail(`${label}.policy.sourceMode is unsupported`);
  }
  const tenantLimits = requireObject(policy.tenantLimits, `${label}.policy.tenantLimits`);
  requireOnlyKeys(tenantLimits, ["maxRequests", "maxUnits"], `${label}.policy.tenantLimits`);
  requireFields(tenantLimits, ["maxRequests", "maxUnits"], `${label}.policy.tenantLimits`);
  for (const field of ["maxRequests", "maxUnits"]) {
    requireInteger(tenantLimits[field], `${label}.policy.tenantLimits.${field}`);
    if (tenantLimits[field] < 0 || !Number.isSafeInteger(tenantLimits[field])) {
      fail(`${label}.policy.tenantLimits.${field} must be a non-negative safe integer`);
    }
  }
  if (policy.sourceMode === "uniform_bounded") {
    if (policy.productPlans !== undefined) fail(`${label}.policy.productPlans requires commerce_provider`);
    validatePolicyPlan(policy.uniformPlan, `${label}.policy.uniformPlan`, { productRequired: false });
  } else {
    if (policy.uniformPlan !== undefined) fail(`${label}.policy.uniformPlan requires uniform_bounded`);
    if (!Array.isArray(policy.productPlans) || policy.productPlans.length === 0 || policy.productPlans.length > 256) {
      fail(`${label}.policy.productPlans must contain configured subscription products`);
    }
    policy.productPlans.forEach((plan, index) => {
      validatePolicyPlan(plan, `${label}.policy.productPlans[${index}]`, { productRequired: true });
    });
    const enabled = policy.productPlans.filter((plan) => plan.enabled !== false);
    if (enabled.length === 0) fail(`${label}.policy.productPlans must enable at least one product`);
    if (new Set(policy.productPlans.map((plan) => plan.productId)).size !== policy.productPlans.length
      || new Set(policy.productPlans.map((plan) => plan.id)).size !== policy.productPlans.length) {
      fail(`${label}.policy.productPlans must use unique product and plan identifiers`);
    }
  }
  return entitlement;
}

function validateCloudflareDesiredState(value, label, schemaVersion = AGENTWEAVE_PROJECT_SCHEMA_VERSION) {
  const deployment = requireObject(value, label);
  requireOnlyKeys(deployment, ["provider", "cloudflare"], label);
  requireFields(deployment, ["provider", "cloudflare"], label);
  if (deployment.provider !== "cloudflare") fail(`${label}.provider must be 'cloudflare'`);
  const cloudflare = requireObject(deployment.cloudflare, `${label}.cloudflare`);
  const workerField = schemaVersion === 1 ? "workerName" : "gatewayWorkerName";
  requireOnlyKeys(
    cloudflare,
    schemaVersion === 1
      ? ["accountId", "workerName", "environment"]
      : ["accountId", "gatewayWorkerName", "environment", "entitlement"],
    `${label}.cloudflare`,
  );
  requireFields(
    cloudflare,
    schemaVersion === 1 ? ["accountId", "workerName"] : ["accountId", "gatewayWorkerName", "entitlement"],
    `${label}.cloudflare`,
  );
  requireString(cloudflare.accountId, `${label}.cloudflare.accountId`, { maxBytes: 32 });
  if (!/^[0-9a-fA-F]{32}$/.test(cloudflare.accountId)) {
    fail(`${label}.cloudflare.accountId must be a 32-character Cloudflare account ID`);
  }
  requireString(cloudflare[workerField], `${label}.cloudflare.${workerField}`, { maxBytes: 63 });
  if (!WORKER_NAME_PATTERN.test(cloudflare[workerField])) {
    fail(`${label}.cloudflare.${workerField} must be a lowercase Worker name`);
  }
  if (cloudflare.environment !== undefined) {
    requireString(cloudflare.environment, `${label}.cloudflare.environment`, { maxBytes: 32 });
    if (!ENVIRONMENT_PATTERN.test(cloudflare.environment)) {
      fail(`${label}.cloudflare.environment must be a lowercase environment name`);
    }
  }
  if (schemaVersion === 2) {
    validateManagedEntitlement(cloudflare.entitlement, `${label}.cloudflare.entitlement`);
    if (
      cloudflare.entitlement.mode === "managed_worker"
      && cloudflare.entitlement.workerName === cloudflare.gatewayWorkerName
    ) {
      fail(`${label}.cloudflare entitlement and gateway Worker names must differ`);
    }
  }
  return deployment;
}

export function projectRuntimeProjection(project, label = "agentweave-project.json") {
  const validated = validateAgentWeaveProjectData(project, label);
  return {
    modelAccess: cloneJson(validated.modelAccess),
    identity: validated.providers.identity === null
      ? { mode: "local_single_user" }
      : { mode: "required", provider: cloneJson(validated.providers.identity) },
    entitlements: validated.providers.entitlement === null
      ? { mode: "disabled" }
      : { mode: "required", provider: cloneJson(validated.providers.entitlement) },
  };
}

export function validateAgentWeaveProjectData(project, label = AGENTWEAVE_PROJECT_FILE) {
  const document = requireObject(project, label);
  requireOnlyKeys(document, ["schemaVersion", "providers", "modelAccess", "deployment"], label);
  requireFields(document, ["schemaVersion", "providers", "modelAccess", "deployment"], label);
  const schemaVersion = requireCompatibleSchemaVersion(
    document.schemaVersion,
    AGENTWEAVE_PROJECT_SCHEMA_VERSION,
    `${label}.schemaVersion`,
  );
  rejectNonPublicConfig(document, label);
  const providers = requireObject(document.providers, `${label}.providers`);
  const providerKinds = schemaVersion === 1
    ? ["identity", "entitlement", "gateway"]
    : ["identity", "entitlement", "commerce", "gateway"];
  requireOnlyKeys(providers, providerKinds, `${label}.providers`);
  requireFields(providers, providerKinds, `${label}.providers`);
  for (const kind of providerKinds) {
    validateOptionalProviderSelection(providers[kind], `${label}.providers.${kind}`);
  }
  validateModelAccess(document.modelAccess, `${label}.modelAccess`);
  if (document.deployment !== null) {
    validateCloudflareDesiredState(document.deployment, `${label}.deployment`, schemaVersion);
  }
  if (document.modelAccess.configurationPolicy === "user_configurable") {
    if (providers.gateway !== null || document.deployment !== null) {
      fail(`${label} must not select a gateway or deployment in user_configurable mode`);
    }
  } else if (providers.gateway === null || document.deployment === null) {
    fail(`${label} must select a gateway and deployment in app_managed mode`);
  }
  if (schemaVersion === 2 && document.deployment !== null) {
    const entitlement = document.deployment.cloudflare.entitlement;
    const commerceMode = entitlement.mode === "managed_worker"
      && entitlement.policy.sourceMode === "commerce_provider";
    if (commerceMode !== (providers.commerce !== null)) {
      fail(`${label}.providers.commerce must match the managed entitlement policy source`);
    }
  }
  const projection = {
    modelAccess: document.modelAccess,
    identity: providers.identity === null
      ? { mode: "local_single_user" }
      : { mode: "required", provider: providers.identity },
    entitlements: providers.entitlement === null
      ? { mode: "disabled" }
      : { mode: "required", provider: providers.entitlement },
  };
  validateRuntimeProviderProjection(
    { schemaVersion: RUNTIME_PROVIDER_MANIFEST_SCHEMA_VERSION, ...projection },
    `${label} runtime projection`,
  );
  return document;
}

export function computeProjectDesiredHash(project) {
  return hashPublicValue(validateAgentWeaveProjectData(project));
}

export function computeRuntimeProjectionHash(app) {
  return hashPublicValue(runtimeProviderProjection(app));
}

export function computeProviderPublicConfigHash(provider) {
  const selection = validateProviderSelection(provider, "provider selection");
  return hashPublicValue(selection.publicConfig);
}

export function validateProjectMatchesRuntime(project, app) {
  const desiredProjection = projectRuntimeProjection(project);
  const runtimeProjection = runtimeProviderProjection(app);
  if (app.schemaVersion === 1) {
    const legacyDefault = {
      modelAccess: { configurationPolicy: "user_configurable" },
      identity: { mode: "local_single_user" },
      entitlements: { mode: "disabled" },
    };
    if (canonicalJson(desiredProjection) !== canonicalJson(legacyDefault)) {
      fail("schemaVersion 1 Agent Apps cannot project configured providers");
    }
    return true;
  }
  if (canonicalJson(desiredProjection) !== canonicalJson(runtimeProjection)) {
    fail("agentweave-project.json public provider projection does not match agent-app.json");
  }
  return true;
}

function requireHash(value, label) {
  requireString(value, label, { maxBytes: 71 });
  if (!HASH_PATTERN.test(value)) fail(`${label} must be a sha256:<hex> digest`);
  return value;
}

function validateCloudflareReference(value, label) {
  const reference = requireObject(value, label);
  requireOnlyKeys(
    reference,
    ["accountId", "workerName", "environment", "versionId", "deploymentId", "endpoint"],
    label,
  );
  requireFields(reference, ["accountId", "workerName", "versionId", "deploymentId", "endpoint"], label);
  validateCloudflareDesiredState(
    {
      provider: "cloudflare",
      cloudflare: {
        accountId: reference.accountId,
        workerName: reference.workerName,
        ...(reference.environment === undefined ? {} : { environment: reference.environment }),
      },
    },
    `${label} desired reference`,
    1,
  );
  requireString(reference.versionId, `${label}.versionId`, { maxBytes: 128 });
  requireString(reference.deploymentId, `${label}.deploymentId`, { maxBytes: 128 });
  parsePublicUrl(reference.endpoint, `${label}.endpoint`, { allowLoopbackHttp: false });
  return reference;
}

function validateLockedProvider(value, label) {
  const provider = requireObject(value, label);
  requireOnlyKeys(provider, ["id", "version", "publicConfigHash"], label);
  requireFields(provider, ["id", "version", "publicConfigHash"], label);
  requirePluginId(provider.id, `${label}.id`);
  requireSemver(provider.version, `${label}.version`);
  requireHash(provider.publicConfigHash, `${label}.publicConfigHash`);
  return provider;
}

function validateCommerceProjection(value, label) {
  if (value === null) return null;
  const projection = requireObject(value, label);
  requireOnlyKeys(
    projection,
    [
      "providerId", "providerVersion", "environment", "databaseId", "migrationHash",
      "capabilities", "portalVerifiedAtUnixMs", "webhookVerifiedAtUnixMs",
    ],
    label,
  );
  requireFields(
    projection,
    [
      "providerId", "providerVersion", "environment", "databaseId", "migrationHash",
      "capabilities", "portalVerifiedAtUnixMs", "webhookVerifiedAtUnixMs",
    ],
    label,
  );
  requirePluginId(projection.providerId, `${label}.providerId`);
  requireSemver(projection.providerVersion, `${label}.providerVersion`);
  if (!["test", "production"].includes(projection.environment)) {
    fail(`${label}.environment is unsupported`);
  }
  requireString(projection.databaseId, `${label}.databaseId`, { maxBytes: 128 });
  requireHash(projection.migrationHash, `${label}.migrationHash`);
  if (!Array.isArray(projection.capabilities) || projection.capabilities.length === 0) {
    fail(`${label}.capabilities must be a non-empty array`);
  }
  projection.capabilities.forEach((capability, index) => {
    requirePluginId(capability, `${label}.capabilities[${index}]`);
  });
  const required = [
    "checkout_session_v1",
    "customer_portal_v1",
    "product_discovery_v1",
    "signed_webhook_v1",
    "subscription_reconciliation_v1",
    "test_environment_v1",
  ];
  for (const capability of required) {
    if (!projection.capabilities.includes(capability)) {
      fail(`${label}.capabilities is missing ${capability}`);
    }
  }
  for (const field of ["portalVerifiedAtUnixMs", "webhookVerifiedAtUnixMs"]) {
    requireInteger(projection[field], `${label}.${field}`);
    if (projection[field] <= 0) fail(`${label}.${field} must record a successful verification`);
  }
  return projection;
}

function validateDeploymentBundleLockV2(document, { project, app }, label) {
  requireOnlyKeys(
    document,
    ["schemaVersion", "desiredHash", "runtimeProjectionHash", "providers", "bundle"],
    label,
  );
  requireFields(
    document,
    ["schemaVersion", "desiredHash", "runtimeProjectionHash", "providers", "bundle"],
    label,
  );
  rejectNonPublicConfig(document, label);
  requireHash(document.desiredHash, `${label}.desiredHash`);
  requireHash(document.runtimeProjectionHash, `${label}.runtimeProjectionHash`);
  const providers = requireObject(document.providers, `${label}.providers`);
  requireOnlyKeys(providers, ["gateway", "entitlement", "commerce"], `${label}.providers`);
  requireFields(providers, ["gateway", "entitlement", "commerce"], `${label}.providers`);
  const gateway = validateLockedProvider(providers.gateway, `${label}.providers.gateway`);
  const entitlement = validateLockedProvider(
    providers.entitlement,
    `${label}.providers.entitlement`,
  );
  const commerce = providers.commerce === null
    ? null
    : validateLockedProvider(providers.commerce, `${label}.providers.commerce`);
  const bundle = requireObject(document.bundle, `${label}.bundle`);
  requireOnlyKeys(bundle, ["provider", "bundleRevision", "rollbackTarget", "bindings", "resources", "verification"], `${label}.bundle`);
  requireFields(bundle, ["provider", "bundleRevision", "rollbackTarget", "bindings", "resources", "verification"], `${label}.bundle`);
  if (bundle.provider !== "cloudflare") fail(`${label}.bundle.provider must be 'cloudflare'`);
  requireHash(bundle.bundleRevision, `${label}.bundle.bundleRevision`);
  if (bundle.rollbackTarget !== null) {
    const rollbackTarget = requireObject(bundle.rollbackTarget, `${label}.bundle.rollbackTarget`);
    requireOnlyKeys(
      rollbackTarget,
      ["gatewayVersionId", "entitlementVersionId"],
      `${label}.bundle.rollbackTarget`,
    );
    requireFields(
      rollbackTarget,
      ["gatewayVersionId", "entitlementVersionId"],
      `${label}.bundle.rollbackTarget`,
    );
    requireString(rollbackTarget.gatewayVersionId, `${label}.bundle.rollbackTarget.gatewayVersionId`, { maxBytes: 256 });
    requireString(rollbackTarget.entitlementVersionId, `${label}.bundle.rollbackTarget.entitlementVersionId`, { maxBytes: 256 });
  }
  const bindings = requireObject(bundle.bindings, `${label}.bundle.bindings`);
  requireOnlyKeys(bindings, ["entitlementProjection"], `${label}.bundle.bindings`);
  requireFields(bindings, ["entitlementProjection"], `${label}.bundle.bindings`);
  const projectionBinding = requireObject(
    bindings.entitlementProjection,
    `${label}.bundle.bindings.entitlementProjection`,
  );
  requireOnlyKeys(
    projectionBinding,
    ["configured", "revision"],
    `${label}.bundle.bindings.entitlementProjection`,
  );
  requireFields(
    projectionBinding,
    ["configured", "revision"],
    `${label}.bundle.bindings.entitlementProjection`,
  );
  if (projectionBinding.configured !== true) {
    fail(`${label}.bundle.bindings.entitlementProjection must be configured`);
  }
  requireString(
    projectionBinding.revision,
    `${label}.bundle.bindings.entitlementProjection.revision`,
    { maxBytes: 256 },
  );
  const resources = requireObject(bundle.resources, `${label}.bundle.resources`);
  requireOnlyKeys(resources, ["gateway", "entitlementPolicy", "commerceProjection"], `${label}.bundle.resources`);
  requireFields(resources, ["gateway", "entitlementPolicy", "commerceProjection"], `${label}.bundle.resources`);
  const gatewayReference = validateCloudflareReference(
    resources.gateway,
    `${label}.bundle.resources.gateway`,
  );
  const entitlementReference = validateCloudflareReference(
    resources.entitlementPolicy,
    `${label}.bundle.resources.entitlementPolicy`,
  );
  const commerceProjection = validateCommerceProjection(
    resources.commerceProjection,
    `${label}.bundle.resources.commerceProjection`,
  );
  if (
    gatewayReference.accountId !== entitlementReference.accountId
    || gatewayReference.deploymentId !== entitlementReference.deploymentId
    || gatewayReference.workerName === entitlementReference.workerName
  ) {
    fail(`${label}.bundle Worker references do not form one access deployment`);
  }
  const verification = requireObject(bundle.verification, `${label}.bundle.verification`);
  requireOnlyKeys(
    verification,
    ["protocolVersion", "testedAtUnixMs", "hostCapabilities", "userEntrypoints"],
    `${label}.bundle.verification`,
  );
  requireFields(
    verification,
    ["protocolVersion", "testedAtUnixMs", "hostCapabilities", "userEntrypoints"],
    `${label}.bundle.verification`,
  );
  requireString(verification.protocolVersion, `${label}.bundle.verification.protocolVersion`, { maxBytes: 32 });
  requireInteger(verification.testedAtUnixMs, `${label}.bundle.verification.testedAtUnixMs`);
  if (verification.testedAtUnixMs <= 0) fail(`${label}.bundle.verification must be complete`);
  for (const field of ["hostCapabilities", "userEntrypoints"]) {
    if (!Array.isArray(verification[field]) || verification[field].length > 32) {
      fail(`${label}.bundle.verification.${field} must be a bounded array`);
    }
    verification[field].forEach((entry, index) => {
      requirePluginId(entry, `${label}.bundle.verification.${field}[${index}]`);
    });
  }
  if (commerceProjection !== null) {
    for (const capability of ["commerce_checkout_v1", "commerce_customer_portal_v1"]) {
      if (!verification.hostCapabilities.includes(capability)) {
        fail(`${label}.bundle.verification.hostCapabilities is missing ${capability}`);
      }
    }
    if (!verification.userEntrypoints.includes("settings.billing")) {
      fail(`${label}.bundle.verification.userEntrypoints is missing settings.billing`);
    }
  }
  if (project !== undefined) {
    const desired = validateAgentWeaveProjectData(project);
    if (desired.schemaVersion !== 2 || desired.providers.gateway === null || desired.deployment === null) {
      fail(`${label} v2 requires an app-managed project schemaVersion 2 desired state`);
    }
    if (document.desiredHash !== hashPublicValue(desired)) fail(`${label}.desiredHash is stale`);
    for (const [locked, selected, field] of [
      [gateway, desired.providers.gateway, "gateway"],
      [entitlement, desired.providers.entitlement, "entitlement"],
      [commerce, desired.providers.commerce, "commerce"],
    ]) {
      if ((locked === null) !== (selected === null)) fail(`${label}.providers.${field} selection is stale`);
      if (locked !== null && (
        locked.id !== selected.id
        || locked.version !== selected.version
        || locked.publicConfigHash !== hashPublicValue(selected.publicConfig)
      )) {
        fail(`${label}.providers.${field} does not match agentweave-project.json`);
      }
    }
    const desiredCloudflare = desired.deployment.cloudflare;
    if (
      gatewayReference.accountId !== desiredCloudflare.accountId
      || gatewayReference.workerName !== desiredCloudflare.gatewayWorkerName
      || gatewayReference.environment !== desiredCloudflare.environment
      || entitlementReference.workerName !== desiredCloudflare.entitlement.workerName
    ) {
      fail(`${label}.bundle references do not match desired Cloudflare resources`);
    }
    if ((commerceProjection !== null) !== (desired.providers.commerce !== null)) {
      fail(`${label}.bundle Commerce projection does not match desired policy source`);
    }
  }
  if (app !== undefined) {
    const projection = runtimeProviderProjection(app);
    if (document.runtimeProjectionHash !== hashPublicValue(projection)) {
      fail(`${label}.runtimeProjectionHash is stale`);
    }
    if (app.schemaVersion === 2 && app.modelAccess?.profile?.baseUrl !== gatewayReference.endpoint) {
      fail(`${label}.bundle gateway endpoint does not match agent-app.json model baseUrl`);
    }
  }
  if (project !== undefined && app !== undefined) validateProjectMatchesRuntime(project, app);
  return document;
}

export function validateDeploymentLockData(lock, { project, app } = {}) {
  const label = DEPLOYMENT_LOCK_RELATIVE_PATH;
  const document = requireObject(lock, label);
  const schemaVersion = requireCompatibleSchemaVersion(
    document.schemaVersion,
    DEPLOYMENT_LOCK_SCHEMA_VERSION,
    `${label}.schemaVersion`,
  );
  if (schemaVersion === 2) {
    return validateDeploymentBundleLockV2(document, { project, app }, label);
  }
  requireOnlyKeys(
    document,
    ["schemaVersion", "desiredHash", "runtimeProjectionHash", "gateway", "deployment"],
    label,
  );
  requireFields(
    document,
    ["schemaVersion", "desiredHash", "runtimeProjectionHash", "gateway", "deployment"],
    label,
  );
  rejectNonPublicConfig(document, label);
  requireHash(document.desiredHash, `${label}.desiredHash`);
  requireHash(document.runtimeProjectionHash, `${label}.runtimeProjectionHash`);
  const gateway = requireObject(document.gateway, `${label}.gateway`);
  requireOnlyKeys(gateway, ["id", "version", "publicConfigHash"], `${label}.gateway`);
  requireFields(gateway, ["id", "version", "publicConfigHash"], `${label}.gateway`);
  requirePluginId(gateway.id, `${label}.gateway.id`);
  requireSemver(gateway.version, `${label}.gateway.version`);
  requireHash(gateway.publicConfigHash, `${label}.gateway.publicConfigHash`);
  const deployment = requireObject(document.deployment, `${label}.deployment`);
  requireOnlyKeys(deployment, ["provider", "reference"], `${label}.deployment`);
  requireFields(deployment, ["provider", "reference"], `${label}.deployment`);
  if (deployment.provider !== "cloudflare") {
    fail(`${label}.deployment.provider must be 'cloudflare'`);
  }
  const reference = validateCloudflareReference(deployment.reference, `${label}.deployment.reference`);
  if (project !== undefined) {
    const desired = validateAgentWeaveProjectData(project);
    if (desired.providers.gateway === null || desired.deployment === null) {
      fail(`${label} requires an app-managed gateway desired state`);
    }
    if (document.desiredHash !== hashPublicValue(desired)) fail(`${label}.desiredHash is stale`);
    if (
      gateway.id !== desired.providers.gateway.id
      || gateway.version !== desired.providers.gateway.version
      || gateway.publicConfigHash !== hashPublicValue(desired.providers.gateway.publicConfig)
    ) {
      fail(`${label}.gateway does not match agentweave-project.json`);
    }
    const desiredCloudflare = desired.deployment.cloudflare;
    for (const field of ["accountId", "workerName", "environment"]) {
      if (reference[field] !== desiredCloudflare[field]) {
        fail(`${label}.deployment.reference.${field} does not match desired state`);
      }
    }
  }
  if (app !== undefined) {
    const projection = runtimeProviderProjection(app);
    if (document.runtimeProjectionHash !== hashPublicValue(projection)) {
      fail(`${label}.runtimeProjectionHash is stale`);
    }
    if (app.schemaVersion === 2) {
      const baseUrl = app.modelAccess?.profile?.baseUrl;
      if (baseUrl !== reference.endpoint) {
        fail(`${label}.deployment.reference.endpoint does not match agent-app.json model baseUrl`);
      }
    }
  }
  if (project !== undefined && app !== undefined) validateProjectMatchesRuntime(project, app);
  return document;
}

function readJsonFile(path, label) {
  if (!existsSync(path)) return null;
  if (lstatSync(path).isSymbolicLink() || !statSync(path).isFile()) {
    fail(`${label} must be a regular file`);
  }
  if (statSync(path).size > MAX_DOCUMENT_BYTES) {
    fail(`${label} exceeds ${MAX_DOCUMENT_BYTES} bytes`);
  }
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    fail(`${label} is invalid JSON: ${error instanceof Error ? error.message : String(error)}`);
  }
}

export function validateAgentWeaveProjectWorkspace(
  appRoot,
  { app, requireDeploymentLock = false } = {},
) {
  const projectPath = join(appRoot, AGENTWEAVE_PROJECT_FILE);
  const lockPath = join(appRoot, ...DEPLOYMENT_LOCK_RELATIVE_PATH.split("/"));
  const projectDocument = readJsonFile(projectPath, AGENTWEAVE_PROJECT_FILE);
  const lockDocument = readJsonFile(lockPath, DEPLOYMENT_LOCK_RELATIVE_PATH);
  if (projectDocument === null) {
    if (lockDocument !== null) fail(`${DEPLOYMENT_LOCK_RELATIVE_PATH} requires ${AGENTWEAVE_PROJECT_FILE}`);
    if (app?.schemaVersion === 2) fail(`${AGENTWEAVE_PROJECT_FILE} is required for schemaVersion 2 Agent Apps`);
    return { lock: null, project: null };
  }
  const project = validateAgentWeaveProjectData(projectDocument);
  if (app !== undefined) validateProjectMatchesRuntime(project, app);
  if (lockDocument !== null && project.providers.gateway === null) {
    fail(`${DEPLOYMENT_LOCK_RELATIVE_PATH} must not exist without a gateway desired state`);
  }
  const lock = lockDocument === null
    ? null
    : validateDeploymentLockData(lockDocument, { project, app });
  if (requireDeploymentLock && lock === null) {
    fail(`${DEPLOYMENT_LOCK_RELATIVE_PATH} is required before packaging an app-managed model gateway`);
  }
  return { lock, project };
}
