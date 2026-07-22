import { fail } from "./errors.js";

const ENVIRONMENTS = new Set(["development", "staging", "production"]);
const COMMERCE_ENVIRONMENTS = new Set(["test", "production"]);
const SOURCE_MODES = new Set(["uniform_bounded", "commerce_provider"]);

function invalid(message) {
  fail(503, "entitlement_misconfigured", "The entitlement service is not configured.", {
    cause: new Error(message),
  });
}

function object(value, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) invalid(`${label} must be an object`);
  return value;
}

function onlyKeys(value, allowed, label) {
  for (const key of Object.keys(value)) {
    if (!allowed.includes(key)) invalid(`${label} contains unknown field '${key}'`);
  }
}

function string(value, label, maximum = 2048) {
  if (typeof value !== "string" || value === "" || value !== value.trim()
    || value.length > maximum || /[\x00-\x1f\x7f]/.test(value)) {
    invalid(`${label} must be bounded text`);
  }
  return value;
}

function integer(value, label, minimum, maximum) {
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) {
    invalid(`${label} must be an integer between ${minimum} and ${maximum}`);
  }
  return value;
}

function exactUrl(value, label) {
  let url;
  try {
    url = new URL(string(value, label));
  } catch {
    invalid(`${label} must be a URL`);
  }
  if (url.protocol !== "https:" || url.username || url.password || url.search || url.hash) {
    invalid(`${label} must be an exact HTTPS URL`);
  }
  return url.toString();
}

function binding(value, label) {
  const result = string(value, label, 64);
  if (!/^[A-Z][A-Z0-9_]{0,63}$/.test(result)) invalid(`${label} must be a binding name`);
  return result;
}

function identityProvider(raw, index) {
  const value = object(raw, `auth.providers[${index}]`);
  onlyKeys(value, [
    "id", "kind", "issuer", "audience", "jwksUrl", "algorithm", "header",
    "requireNbf", "clockSkewSeconds", "projection",
  ], `auth.providers[${index}]`);
  const kind = string(value.kind, `auth.providers[${index}].kind`, 32);
  if (!new Set(["oidc", "cloudflare_access"]).has(kind)) invalid("identity kind is unsupported");
  const algorithm = string(value.algorithm, `auth.providers[${index}].algorithm`, 16);
  if (!new Set(["RS256", "ES256"]).has(algorithm)) invalid("identity algorithm is unsupported");
  const header = string(value.header ?? (kind === "oidc" ? "authorization" : "cf-access-jwt-assertion"), `auth.providers[${index}].header`, 128).toLowerCase();
  if ((kind === "oidc" && header !== "authorization")
    || (kind === "cloudflare_access" && header !== "cf-access-jwt-assertion")) {
    invalid("identity header is invalid");
  }
  const projection = object(value.projection ?? {}, `auth.providers[${index}].projection`);
  onlyKeys(projection, ["subjectClaim", "tenantClaim", "deviceClaim", "deviceMode", "rolesClaim"], `auth.providers[${index}].projection`);
  const deviceClaim = projection.deviceClaim === undefined
    ? null : string(projection.deviceClaim, "identity device claim", 256);
  const deviceMode = string(projection.deviceMode ?? (deviceClaim ? "required_verified" : "disabled"), "identity device mode", 64);
  if (!new Set(["required_verified", "optional_verified", "disabled"]).has(deviceMode)) {
    invalid("identity device mode is unsupported");
  }
  return Object.freeze({
    id: string(value.id, `auth.providers[${index}].id`, 128),
    kind,
    issuer: exactUrl(value.issuer, `auth.providers[${index}].issuer`),
    audience: string(value.audience, `auth.providers[${index}].audience`),
    jwksUrl: exactUrl(value.jwksUrl, `auth.providers[${index}].jwksUrl`),
    algorithm,
    header,
    requireNbf: value.requireNbf === true,
    clockSkewSeconds: integer(value.clockSkewSeconds ?? 30, "identity clock skew", 0, 300),
    projection: Object.freeze({
      subjectClaim: string(projection.subjectClaim ?? "sub", "identity subject claim", 256),
      tenantClaim: projection.tenantClaim === undefined
        ? null : string(projection.tenantClaim, "identity tenant claim", 256),
      deviceClaim,
      deviceMode,
      rolesClaim: projection.rolesClaim === undefined
        ? null : string(projection.rolesClaim, "identity roles claim", 256),
    }),
  });
}

function plan(raw, label, { productRequired }) {
  const value = object(raw, label);
  onlyKeys(value, [
    "id", "displayName", "productId", "enabled", "allowedModels", "limits",
  ], label);
  const models = value.allowedModels;
  if (!Array.isArray(models) || models.length === 0 || models.length > 128) {
    invalid(`${label}.allowedModels must be a non-empty array`);
  }
  const allowedModels = models.map((model, index) => string(model, `${label}.allowedModels[${index}]`, 256));
  if (new Set(allowedModels).size !== allowedModels.length) invalid(`${label}.allowedModels contains duplicates`);
  const limits = object(value.limits, `${label}.limits`);
  onlyKeys(limits, ["maxRequests", "maxUnits", "maxConcurrency"], `${label}.limits`);
  const productId = value.productId === undefined ? null : string(value.productId, `${label}.productId`, 256);
  if (productRequired && (!productId || !productId.startsWith("prod_"))) invalid(`${label}.productId is required`);
  return Object.freeze({
    id: string(value.id, `${label}.id`, 128),
    displayName: string(value.displayName, `${label}.displayName`, 256),
    productId,
    enabled: value.enabled !== false,
    allowedModels: Object.freeze(allowedModels),
    limits: Object.freeze({
      maxRequests: integer(limits.maxRequests, `${label}.limits.maxRequests`, 0, Number.MAX_SAFE_INTEGER),
      maxUnits: integer(limits.maxUnits, `${label}.limits.maxUnits`, 0, Number.MAX_SAFE_INTEGER),
      maxConcurrency: integer(limits.maxConcurrency, `${label}.limits.maxConcurrency`, 0, 1000),
    }),
  });
}

export function parseEntitlementConfig(rawValue) {
  let raw;
  try {
    raw = typeof rawValue === "string" ? JSON.parse(rawValue) : rawValue;
  } catch {
    invalid("ENTITLEMENT_CONFIG_JSON is invalid JSON");
  }
  const value = object(raw, "entitlement config");
  onlyKeys(value, [
    "schemaVersion", "environment", "appId", "deploymentId", "configurationId",
    "auth", "policy", "commerce", "bindings",
  ], "entitlement config");
  if (value.schemaVersion !== 1) invalid("schemaVersion must be 1");
  const environment = string(value.environment, "environment", 32);
  if (!ENVIRONMENTS.has(environment)) invalid("environment is unsupported");
  const auth = object(value.auth, "auth");
  onlyKeys(auth, ["mode", "providers"], "auth");
  if (auth.mode !== "required" || !Array.isArray(auth.providers) || auth.providers.length === 0) {
    invalid("entitlement identity is required");
  }
  const providers = auth.providers.map(identityProvider);
  const policy = object(value.policy, "policy");
  onlyKeys(policy, ["sourceMode", "tenantLimits", "uniformPlan", "productPlans"], "policy");
  const sourceMode = string(policy.sourceMode, "policy.sourceMode", 64);
  if (!SOURCE_MODES.has(sourceMode)) invalid("policy source mode is unsupported");
  const tenantLimits = object(policy.tenantLimits, "policy.tenantLimits");
  onlyKeys(tenantLimits, ["maxRequests", "maxUnits"], "policy.tenantLimits");
  const productPlans = Array.isArray(policy.productPlans)
    ? policy.productPlans.map((item, index) => plan(item, `policy.productPlans[${index}]`, { productRequired: true }))
    : [];
  if (new Set(productPlans.map((item) => item.productId)).size !== productPlans.length
    || new Set(productPlans.map((item) => item.id)).size !== productPlans.length) {
    invalid("product plans contain duplicate identifiers");
  }
  const uniformPlan = policy.uniformPlan === undefined
    ? null : plan(policy.uniformPlan, "policy.uniformPlan", { productRequired: false });
  if (sourceMode === "uniform_bounded" && !uniformPlan) invalid("uniform policy needs a plan");
  if (sourceMode === "commerce_provider" && productPlans.length === 0) invalid("commerce policy needs product plans");
  let commerce = null;
  if (sourceMode === "commerce_provider") {
    const rawCommerce = object(value.commerce, "commerce");
    onlyKeys(rawCommerce, ["providerId", "environment", "successUrl"], "commerce");
    const commerceEnvironment = string(rawCommerce.environment, "commerce.environment", 32);
    if (!COMMERCE_ENVIRONMENTS.has(commerceEnvironment)) invalid("commerce environment is unsupported");
    commerce = Object.freeze({
      providerId: string(rawCommerce.providerId, "commerce.providerId", 128),
      environment: commerceEnvironment,
      successUrl: exactUrl(rawCommerce.successUrl, "commerce.successUrl"),
    });
  } else if (value.commerce !== undefined) {
    invalid("uniform policy cannot configure commerce");
  }
  const bindings = object(value.bindings ?? {}, "bindings");
  onlyKeys(bindings, ["commerce"], "bindings");
  return Object.freeze({
    schemaVersion: 1,
    environment,
    appId: string(value.appId, "appId", 128),
    deploymentId: string(value.deploymentId, "deploymentId", 128),
    configurationId: string(value.configurationId, "configurationId", 256),
    auth: Object.freeze({ mode: "required", providers: Object.freeze(providers) }),
    policy: Object.freeze({
      sourceMode,
      tenantLimits: Object.freeze({
        maxRequests: integer(tenantLimits.maxRequests, "policy.tenantLimits.maxRequests", 0, Number.MAX_SAFE_INTEGER),
        maxUnits: integer(tenantLimits.maxUnits, "policy.tenantLimits.maxUnits", 0, Number.MAX_SAFE_INTEGER),
      }),
      uniformPlan,
      productPlans: Object.freeze(productPlans),
    }),
    commerce,
    bindings: Object.freeze({ commerce: binding(bindings.commerce ?? "COMMERCE", "bindings.commerce") }),
  });
}

export function loadEntitlementConfig(env) {
  if (typeof env?.ENTITLEMENT_CONFIG_JSON !== "string") invalid("ENTITLEMENT_CONFIG_JSON is missing");
  const config = parseEntitlementConfig(env.ENTITLEMENT_CONFIG_JSON);
  const missing = [];
  if (typeof env.ENTITLEMENT_PROJECTION_SECRET !== "string" || env.ENTITLEMENT_PROJECTION_SECRET.length < 32) {
    missing.push("ENTITLEMENT_PROJECTION_SECRET");
  }
  if (env.ENTITLEMENT_PROJECTION_SECRET_NEXT !== undefined
    && (typeof env.ENTITLEMENT_PROJECTION_SECRET_NEXT !== "string"
      || env.ENTITLEMENT_PROJECTION_SECRET_NEXT.length < 32)) {
    missing.push("ENTITLEMENT_PROJECTION_SECRET_NEXT");
  }
  if (config.policy.sourceMode === "commerce_provider") {
    if (!env[config.bindings.commerce]) missing.push(config.bindings.commerce);
    for (const name of ["CREEM_API_KEY", "CREEM_WEBHOOK_SECRET", "COMMERCE_SUBJECT_BINDING_SECRET"]) {
      if (typeof env[name] !== "string" || env[name].length < 16) missing.push(name);
    }
  }
  if (missing.length > 0) invalid(`runtime bindings are missing: ${missing.join(", ")}`);
  return config;
}
