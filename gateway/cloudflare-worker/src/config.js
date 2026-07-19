import { GatewayError } from "./errors.js";

const CONFIG_VERSION = 1;
const TOKEN_FIELDS = new Set(["max_output_tokens", "max_tokens", "max_completion_tokens"]);
const AUTH_KINDS = new Set(["oidc", "cloudflare_access"]);
const DEVICE_MODES = new Set(["required_verified", "optional_verified", "disabled"]);
const ENTITLEMENT_MODES = new Set(["static", "signed_http"]);
const WIRE_PROTOCOLS = new Set([
  "agentweave_responses_v1",
  "agentweave_chat_completions_v1",
  "agentweave_completion_v1",
]);
const SECRET_HEADERS = new Set(["authorization", "x-api-key", "api-key"]);
const FORBIDDEN_FORWARD_HEADERS = new Set([
  "authorization",
  "connection",
  "content-length",
  "cookie",
  "host",
  "idempotency-key",
  "proxy-authorization",
  "set-cookie",
  "transfer-encoding",
  "upgrade",
  "x-api-key",
  "x-agentweave-request-id",
]);

function invalid(message) {
  throw new GatewayError(503, "gateway_misconfigured", "The gateway is not configured for service.", {
    cause: new Error(message),
  });
}

function object(value, label) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    invalid(`${label} must be an object`);
  }
  return value;
}

function onlyKeys(value, allowed, label) {
  for (const key of Object.keys(value)) {
    if (!allowed.includes(key)) invalid(`${label} contains unknown field '${key}'`);
  }
}

function string(value, label) {
  if (typeof value !== "string" || value.trim() === "") invalid(`${label} must be a string`);
  return value.trim();
}

function integer(value, label, minimum, maximum) {
  if (!Number.isInteger(value) || value < minimum || value > maximum) {
    invalid(`${label} must be an integer between ${minimum} and ${maximum}`);
  }
  return value;
}

function boolean(value, label, defaultValue) {
  const candidate = value === undefined ? defaultValue : value;
  if (typeof candidate !== "boolean") invalid(`${label} must be a boolean`);
  return candidate;
}

function array(value, label, { defaultValue } = {}) {
  const candidate = value === undefined ? defaultValue : value;
  if (!Array.isArray(candidate)) invalid(`${label} must be an array`);
  return candidate;
}

function uniqueStrings(value, label, { nonEmpty = true, lowerCase = false } = {}) {
  if (!Array.isArray(value) || (nonEmpty && value.length === 0)) {
    invalid(`${label} must be ${nonEmpty ? "a non-empty" : "an"} array`);
  }
  const result = value.map((item, index) => {
    const normalized = string(item, `${label}[${index}]`);
    return lowerCase ? normalized.toLowerCase() : normalized;
  });
  if (new Set(result).size !== result.length) invalid(`${label} contains duplicates`);
  return result;
}

function bindingName(value, label) {
  const result = string(value, label);
  if (!/^[A-Z][A-Z0-9_]{0,63}$/.test(result)) invalid(`${label} is not a binding name`);
  return result;
}

function exactUrl(value, label, environment, { stripTrailingSlash = false } = {}) {
  const input = string(value, label);
  let url;
  try {
    url = new URL(input);
  } catch {
    invalid(`${label} must be an absolute URL`);
  }
  if (!url || !["https:", "http:"].includes(url.protocol)) invalid(`${label} must use HTTP(S)`);
  if (url.protocol === "http:") {
    const loopback = ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname);
    if (environment !== "development" || !loopback) {
      invalid(`${label} may use HTTP only for an explicit local loopback development endpoint`);
    }
  }
  if (url.username || url.password || url.search || url.hash) invalid(`${label} must not contain credentials, query, or fragment`);
  if (!stripTrailingSlash) return input;
  url.pathname = url.pathname.replace(/\/+$/, "") || "/";
  return url.toString().replace(/\/$/, "");
}

function path(value, label) {
  const result = string(value, label);
  if (!result.startsWith("/") || result.includes("?") || result.includes("#") || result.includes("\\")) {
    invalid(`${label} must be an absolute URL path`);
  }
  const parsed = new URL(result, "https://path.invalid");
  if (parsed.pathname !== result || /%2f|%5c/i.test(result)) invalid(`${label} is not canonical`);
  return result;
}

function validateProvider(raw, index, environment) {
  const provider = object(raw, `auth.providers[${index}]`);
  onlyKeys(provider, [
    "id",
    "kind",
    "issuer",
    "audience",
    "jwksUrl",
    "algorithm",
    "header",
    "requireNbf",
    "clockSkewSeconds",
    "projection",
  ], `auth.providers[${index}]`);
  if (provider.projection !== undefined) {
    onlyKeys(object(provider.projection, `auth.providers[${index}].projection`), [
      "subjectClaim",
      "tenantClaim",
      "deviceClaim",
      "deviceMode",
      "rolesClaim",
    ], `auth.providers[${index}].projection`);
  }
  const kind = string(provider.kind, `auth.providers[${index}].kind`);
  if (!AUTH_KINDS.has(kind)) invalid(`auth.providers[${index}].kind is unsupported`);
  const algorithm = string(provider.algorithm, `auth.providers[${index}].algorithm`);
  if (!["RS256", "ES256"].includes(algorithm)) invalid(`auth.providers[${index}].algorithm is unsupported`);
  const header = string(
    provider.header ?? (kind === "oidc" ? "authorization" : "cf-access-jwt-assertion"),
    `auth.providers[${index}].header`,
  ).toLowerCase();
  if (kind === "oidc" && header !== "authorization") invalid("OIDC tokens must use the Authorization header");
  if (kind === "cloudflare_access" && header !== "cf-access-jwt-assertion") {
    invalid("Cloudflare Access assertions must use the Cf-Access-Jwt-Assertion header");
  }
  const tenantClaim = provider.projection?.tenantClaim !== undefined
    ? string(provider.projection.tenantClaim, `auth.providers[${index}].projection.tenantClaim`)
    : null;
  const deviceClaim = provider.projection?.deviceClaim !== undefined
    ? string(provider.projection.deviceClaim, `auth.providers[${index}].projection.deviceClaim`)
    : null;
  const deviceMode = string(
    provider.projection?.deviceMode ?? (deviceClaim ? "required_verified" : "disabled"),
    `auth.providers[${index}].projection.deviceMode`,
  );
  if (!DEVICE_MODES.has(deviceMode)) invalid(`auth.providers[${index}].projection.deviceMode is unsupported`);
  if (deviceMode === "disabled" && deviceClaim !== null) {
    invalid(`auth.providers[${index}].projection.deviceClaim must be absent when deviceMode is disabled`);
  }
  if (deviceMode !== "disabled" && deviceClaim === null) {
    invalid(`auth.providers[${index}].projection.deviceClaim is required for verified device mode`);
  }
  return Object.freeze({
    id: string(provider.id, `auth.providers[${index}].id`),
    kind,
    issuer: exactUrl(provider.issuer, `auth.providers[${index}].issuer`, environment),
    audience: string(provider.audience, `auth.providers[${index}].audience`),
    jwksUrl: exactUrl(provider.jwksUrl, `auth.providers[${index}].jwksUrl`, environment),
    algorithm,
    header,
    requireNbf: boolean(provider.requireNbf, `auth.providers[${index}].requireNbf`, false),
    clockSkewSeconds: integer(provider.clockSkewSeconds ?? 30, `auth.providers[${index}].clockSkewSeconds`, 0, 300),
    projection: Object.freeze({
      subjectClaim: string(provider.projection?.subjectClaim ?? "sub", `auth.providers[${index}].projection.subjectClaim`),
      tenantClaim,
      deviceClaim,
      deviceMode,
      rolesClaim: provider.projection?.rolesClaim !== undefined
        ? string(provider.projection.rolesClaim, `auth.providers[${index}].projection.rolesClaim`)
        : null,
    }),
  });
}

function validateRoute(raw, index) {
  const route = object(raw, `routes[${index}]`);
  onlyKeys(route, [
    "id",
    "path",
    "upstreamPath",
    "methods",
    "models",
    "tokenField",
    "allowedToolTypes",
    "wireProtocol",
    "modelUnitWeights",
  ], `routes[${index}]`);
  const methods = uniqueStrings(route.methods, `routes[${index}].methods`).map((method) => method.toUpperCase());
  if (methods.some((method) => method !== "POST")) invalid("model routes currently support POST only");
  const tokenField = string(route.tokenField, `routes[${index}].tokenField`);
  if (!TOKEN_FIELDS.has(tokenField)) invalid(`routes[${index}].tokenField is unsupported`);
  const wireProtocol = string(route.wireProtocol, `routes[${index}].wireProtocol`);
  if (!WIRE_PROTOCOLS.has(wireProtocol)) invalid(`routes[${index}].wireProtocol is unsupported`);
  const allowedToolTypes = uniqueStrings(
    route.allowedToolTypes ?? ["function"],
    `routes[${index}].allowedToolTypes`,
    { nonEmpty: false },
  );
  if (allowedToolTypes.some((type) => type !== "function")) {
    invalid(`routes[${index}].allowedToolTypes contains an unmetered server-side tool`);
  }
  if (wireProtocol === "agentweave_responses_v1" && tokenField !== "max_output_tokens") {
    invalid(`routes[${index}] has an incompatible Responses token field`);
  }
  if (wireProtocol === "agentweave_chat_completions_v1"
    && !["max_tokens", "max_completion_tokens"].includes(tokenField)) {
    invalid(`routes[${index}] has an incompatible Chat Completions token field`);
  }
  if (wireProtocol === "agentweave_completion_v1"
    && (tokenField !== "max_tokens" || allowedToolTypes.length !== 0)) {
    invalid(`routes[${index}] has an incompatible Completion policy`);
  }
  const models = uniqueStrings(route.models, `routes[${index}].models`);
  const modelUnitWeights = object(route.modelUnitWeights, `routes[${index}].modelUnitWeights`);
  if (Object.keys(modelUnitWeights).length !== models.length
    || models.some((model) => !Object.hasOwn(modelUnitWeights, model))) {
    invalid(`routes[${index}].modelUnitWeights must cover exactly the allowed models`);
  }
  const normalizedWeights = Object.fromEntries(models.map((model) => [
    model,
    integer(modelUnitWeights[model], `routes[${index}].modelUnitWeights.${model}`, 1, 1_000_000),
  ]));
  return Object.freeze({
    id: string(route.id, `routes[${index}].id`),
    path: path(route.path, `routes[${index}].path`),
    upstreamPath: path(route.upstreamPath, `routes[${index}].upstreamPath`),
    methods,
    models,
    tokenField,
    allowedToolTypes,
    wireProtocol,
    modelUnitWeights: Object.freeze(normalizedWeights),
  });
}

function validateForwardHeaders(value, label) {
  const headers = uniqueStrings(value ?? [], label, { nonEmpty: false, lowerCase: true });
  if (headers.length > 32) invalid(`${label} contains too many headers`);
  for (const header of headers) {
    if (header.length > 128 || !/^[a-z0-9-]+$/.test(header)
      || header.startsWith("cf-") || header.startsWith("x-forwarded-")
      || SECRET_HEADERS.has(header)
      || FORBIDDEN_FORWARD_HEADERS.has(header)) {
      invalid(`${label} contains forbidden header '${header}'`);
    }
  }
  return headers;
}

function validateStaticHeaders(value, label) {
  const source = object(value ?? {}, label);
  if (Object.keys(source).length > 32) invalid(`${label} contains too many headers`);
  const result = {};
  let totalBytes = 0;
  for (const [rawName, rawValue] of Object.entries(source)) {
    const name = string(rawName, `${label} header name`).toLowerCase();
    if (name.length > 128 || !/^[a-z0-9-]+$/.test(name)
      || name.startsWith("cf-") || name.startsWith("x-forwarded-")
      || SECRET_HEADERS.has(name) || FORBIDDEN_FORWARD_HEADERS.has(name)) {
      invalid(`${label} contains forbidden header '${name}'`);
    }
    if (Object.hasOwn(result, name)) invalid(`${label} contains duplicate header '${name}'`);
    if (typeof rawValue !== "string" || rawValue.length > 4096 || /\r|\n/.test(rawValue)) {
      invalid(`${label}.${name} is not a bounded header value`);
    }
    totalBytes += new TextEncoder().encode(`${name}:${rawValue}`).byteLength;
    if (totalBytes > 16 * 1024) invalid(`${label} exceeds its total byte limit`);
    result[name] = rawValue;
  }
  return Object.freeze(result);
}

function validateEntitlements(raw, environment) {
  const value = object(raw ?? { mode: "static" }, "entitlements");
  onlyKeys(value, ["mode", "projection"], "entitlements");
  const mode = string(value.mode, "entitlements.mode");
  if (!ENTITLEMENT_MODES.has(mode)) invalid("entitlements.mode is unsupported");
  if (mode === "static") {
    if (value.projection !== undefined) invalid("static entitlements cannot configure a projection resolver");
    return Object.freeze({ mode, policySource: "static", projection: null });
  }
  const projection = object(value.projection, "entitlements.projection");
  onlyKeys(projection, [
    "sourceId",
    "url",
    "secretBinding",
    "timeoutMilliseconds",
    "maxResponseBytes",
    "refreshBeforeSeconds",
    "maxClockSkewSeconds",
  ], "entitlements.projection");
  const sourceId = string(projection.sourceId, "entitlements.projection.sourceId");
  if (sourceId === "static" || sourceId.length > 128 || /[\x00-\x1f\x7f]/.test(sourceId)) {
    invalid("entitlements.projection.sourceId is invalid");
  }
  return Object.freeze({
    mode,
    policySource: sourceId,
    projection: Object.freeze({
      sourceId,
      url: exactUrl(projection.url, "entitlements.projection.url", environment),
      secretBinding: bindingName(
        projection.secretBinding ?? "ENTITLEMENT_PROJECTION_SECRET",
        "entitlements.projection.secretBinding",
      ),
      timeoutMilliseconds: integer(
        projection.timeoutMilliseconds ?? 5_000,
        "entitlements.projection.timeoutMilliseconds",
        100,
        30_000,
      ),
      maxResponseBytes: integer(
        projection.maxResponseBytes ?? 65_536,
        "entitlements.projection.maxResponseBytes",
        1_024,
        1_048_576,
      ),
      refreshBeforeSeconds: integer(
        projection.refreshBeforeSeconds ?? 30,
        "entitlements.projection.refreshBeforeSeconds",
        0,
        3_600,
      ),
      maxClockSkewSeconds: integer(
        projection.maxClockSkewSeconds ?? 300,
        "entitlements.projection.maxClockSkewSeconds",
        0,
        300,
      ),
    }),
  });
}

export function parseGatewayConfig(rawValue) {
  let raw;
  try {
    raw = typeof rawValue === "string" ? JSON.parse(rawValue) : rawValue;
  } catch {
    invalid("GATEWAY_CONFIG_JSON is not valid JSON");
  }
  const value = object(raw, "gateway config");
  onlyKeys(value, [
    "schemaVersion",
    "environment",
    "deploymentId",
    "configurationId",
    "auth",
    "entitlements",
    "upstream",
    "routes",
    "limits",
    "bindings",
    "rateLimit",
    "controls",
    "concurrency",
  ], "gateway config");
  if (value.schemaVersion !== CONFIG_VERSION) invalid(`schemaVersion must be ${CONFIG_VERSION}`);
  const environment = string(value.environment, "environment");
  if (!["development", "staging", "production"].includes(environment)) invalid("environment is unsupported");

  const auth = object(value.auth, "auth");
  onlyKeys(auth, ["mode", "providers"], "auth");
  const authMode = string(auth.mode, "auth.mode");
  if (!["required", "anonymous"].includes(authMode)) invalid("auth.mode is unsupported");
  if (environment !== "development" && authMode !== "required") {
    invalid("only local development may use anonymous identity");
  }
  const providers = array(auth.providers, "auth.providers", { defaultValue: [] })
    .map((provider, index) => validateProvider(provider, index, environment));
  if (authMode === "required" && providers.length === 0) invalid("required auth needs at least one provider");
  if (new Set(providers.map((provider) => provider.id)).size !== providers.length) invalid("auth provider IDs must be unique");
  const providerKeys = providers.map((provider) => `${provider.header}\0${provider.issuer}\0${provider.audience}`);
  if (new Set(providerKeys).size !== providerKeys.length) invalid("auth provider claim boundaries must be unique");
  const entitlements = validateEntitlements(value.entitlements, environment);

  const upstream = object(value.upstream, "upstream");
  onlyKeys(upstream, [
    "baseUrl",
    "allowedBaseUrls",
    "secretBinding",
    "secretHeader",
    "secretPrefix",
    "requestHeaders",
    "staticHeaders",
    "responseHeaders",
  ], "upstream");
  const baseUrl = exactUrl(upstream.baseUrl, "upstream.baseUrl", environment, { stripTrailingSlash: true });
  const allowedBaseUrls = uniqueStrings(upstream.allowedBaseUrls, "upstream.allowedBaseUrls")
    .map((url, index) => exactUrl(url, `upstream.allowedBaseUrls[${index}]`, environment, { stripTrailingSlash: true }));
  if (!allowedBaseUrls.includes(baseUrl)) invalid("upstream.baseUrl is not in allowedBaseUrls");
  const secretHeader = string(upstream.secretHeader ?? "authorization", "upstream.secretHeader").toLowerCase();
  if (!SECRET_HEADERS.has(secretHeader)) invalid("upstream.secretHeader is unsupported");
  const secretPrefix = upstream.secretPrefix === undefined ? "Bearer " : upstream.secretPrefix;
  if (typeof secretPrefix !== "string") invalid("upstream.secretPrefix must be a string");
  if (/\r|\n/.test(secretPrefix) || secretPrefix.length > 32) invalid("upstream.secretPrefix is invalid");
  const requestHeaders = validateForwardHeaders(upstream.requestHeaders, "upstream.requestHeaders");
  const staticHeaders = validateStaticHeaders(upstream.staticHeaders, "upstream.staticHeaders");
  if (requestHeaders.some((header) => Object.hasOwn(staticHeaders, header))) {
    invalid("upstream requestHeaders and staticHeaders must not overlap");
  }

  const routes = array(value.routes, "routes", { defaultValue: [] }).map(validateRoute);
  if (routes.length === 0) invalid("routes must not be empty");
  const routeKeys = routes.flatMap((route) => route.methods.map((method) => `${method} ${route.path}`));
  if (new Set(routeKeys).size !== routeKeys.length) invalid("routes contain duplicate method/path pairs");

  const limits = object(value.limits, "limits");
  onlyKeys(limits, [
    "maxBodyBytes",
    "maxOutputTokens",
    "maxTools",
    "reservationTtlSeconds",
    "requestBaseUnits",
    "reservationRetentionSeconds",
    "idempotencyRetentionSeconds",
    "maintenanceBatchSize",
  ], "limits");
  const rateLimit = object(value.rateLimit ?? { required: false }, "rateLimit");
  onlyKeys(rateLimit, [
    "required",
    "binding",
    "deploymentBinding",
    "tenantBinding",
    "subjectBinding",
    "deviceBinding",
  ], "rateLimit");
  const rateLimitRequired = boolean(rateLimit.required, "rateLimit.required", false);
  if (environment !== "development" && !rateLimitRequired) {
    invalid("remote environments require identity rate limiting");
  }
  const bindings = object(value.bindings ?? {}, "bindings");
  onlyKeys(bindings, ["entitlements", "concurrency"], "bindings");
  const controls = object(value.controls ?? { modelRequestsEnabled: true }, "controls");
  onlyKeys(controls, ["modelRequestsEnabled"], "controls");
  const concurrency = object(value.concurrency ?? {}, "concurrency");
  onlyKeys(concurrency, ["deploymentLimit", "tenantLimit", "deviceLimit"], "concurrency");
  if (rateLimit.binding !== undefined && rateLimit.subjectBinding !== undefined
    && rateLimit.binding !== rateLimit.subjectBinding) {
    invalid("rateLimit.binding and rateLimit.subjectBinding conflict");
  }
  const rateLimitBindings = Object.freeze({
    deployment: bindingName(
      rateLimit.deploymentBinding ?? "GATEWAY_DEPLOYMENT_RATE_LIMITER",
      "rateLimit.deploymentBinding",
    ),
    tenant: bindingName(
      rateLimit.tenantBinding ?? "GATEWAY_TENANT_RATE_LIMITER",
      "rateLimit.tenantBinding",
    ),
    subject: bindingName(
      rateLimit.subjectBinding ?? rateLimit.binding ?? "GATEWAY_RATE_LIMITER",
      "rateLimit.subjectBinding",
    ),
    device: bindingName(
      rateLimit.deviceBinding ?? "GATEWAY_DEVICE_RATE_LIMITER",
      "rateLimit.deviceBinding",
    ),
  });
  const deviceControlsRequired = providers.some(
    (provider) => provider.projection.deviceMode !== "disabled",
  );
  const reservationRetentionSeconds = integer(
    limits.reservationRetentionSeconds ?? 2_592_000,
    "limits.reservationRetentionSeconds",
    3600,
    7_776_000,
  );
  const idempotencyRetentionSeconds = integer(
    limits.idempotencyRetentionSeconds ?? 31_536_000,
    "limits.idempotencyRetentionSeconds",
    reservationRetentionSeconds,
    63_072_000,
  );
  const config = {
    schemaVersion: CONFIG_VERSION,
    environment,
    deploymentId: string(value.deploymentId, "deploymentId"),
    configurationId: string(value.configurationId, "configurationId"),
    auth: Object.freeze({ mode: authMode, providers }),
    entitlements,
    upstream: Object.freeze({
      baseUrl,
      allowedBaseUrls,
      secretBinding: bindingName(upstream.secretBinding, "upstream.secretBinding"),
      secretHeader,
      secretPrefix,
      requestHeaders,
      staticHeaders,
      responseHeaders: validateForwardHeaders(upstream.responseHeaders ?? ["content-type", "retry-after"], "upstream.responseHeaders"),
    }),
    routes,
    limits: Object.freeze({
      maxBodyBytes: integer(limits.maxBodyBytes, "limits.maxBodyBytes", 1, 10 * 1024 * 1024),
      maxOutputTokens: integer(limits.maxOutputTokens, "limits.maxOutputTokens", 1, 1_000_000),
      maxTools: integer(limits.maxTools, "limits.maxTools", 0, 1024),
      reservationTtlSeconds: integer(limits.reservationTtlSeconds ?? 900, "limits.reservationTtlSeconds", 30, 3600),
      requestBaseUnits: integer(limits.requestBaseUnits ?? 0, "limits.requestBaseUnits", 0, 1_000_000_000),
      reservationRetentionSeconds,
      idempotencyRetentionSeconds,
      maintenanceBatchSize: integer(
        limits.maintenanceBatchSize ?? 250,
        "limits.maintenanceBatchSize",
        1,
        1000,
      ),
    }),
    bindings: Object.freeze({
      entitlements: bindingName(bindings.entitlements ?? "ENTITLEMENTS", "bindings.entitlements"),
      concurrency: bindingName(bindings.concurrency ?? "CONCURRENCY", "bindings.concurrency"),
    }),
    rateLimit: Object.freeze({
      required: rateLimitRequired,
      bindings: rateLimitBindings,
      deviceRequired: deviceControlsRequired,
    }),
    concurrency: Object.freeze({
      deploymentLimit: integer(
        concurrency.deploymentLimit ?? 1000,
        "concurrency.deploymentLimit",
        1,
        1000,
      ),
      tenantLimit: integer(concurrency.tenantLimit ?? 100, "concurrency.tenantLimit", 1, 1000),
      deviceLimit: integer(concurrency.deviceLimit ?? 2, "concurrency.deviceLimit", 1, 1000),
    }),
    controls: Object.freeze({
      modelRequestsEnabled: boolean(controls.modelRequestsEnabled, "controls.modelRequestsEnabled", true),
    }),
  };
  return Object.freeze(config);
}

export function loadGatewayConfig(env) {
  if (!env || typeof env.GATEWAY_CONFIG_JSON !== "string") invalid("GATEWAY_CONFIG_JSON binding is missing");
  return parseGatewayConfig(env.GATEWAY_CONFIG_JSON);
}

export function validateRuntimeBindings(config, env, { remoteRequest = false } = {}) {
  const missing = [];
  if (remoteRequest && !config.rateLimit.required) {
    invalid("remote runtimes require identity rate limiting");
  }
  if (config.auth.mode === "anonymous"
    && (remoteRequest || env?.LOCAL_DEV_ANONYMOUS !== "true")) {
    invalid("anonymous identity is restricted to an explicit local development runtime");
  }
  if (remoteRequest) {
    const urls = [
      config.upstream.baseUrl,
      ...config.upstream.allowedBaseUrls,
      ...config.auth.providers.flatMap((provider) => [provider.issuer, provider.jwksUrl]),
      ...(config.entitlements.projection ? [config.entitlements.projection.url] : []),
    ];
    if (urls.some((url) => new URL(url).protocol !== "https:")) {
      invalid("remote runtimes may not use loopback HTTP endpoints");
    }
  }
  if ((remoteRequest || config.environment !== "development") && !env?.GATEWAY_EDGE_RATE_LIMITER) {
    missing.push("GATEWAY_EDGE_RATE_LIMITER");
  }
  if (!env?.[config.bindings.entitlements]) missing.push(config.bindings.entitlements);
  if (!env?.[config.bindings.concurrency]) missing.push(config.bindings.concurrency);
  if (config.rateLimit.required) {
    for (const [axis, binding] of Object.entries(config.rateLimit.bindings)) {
      if (axis !== "device" || config.rateLimit.deviceRequired) {
        if (!env?.[binding]) missing.push(binding);
      }
    }
  }
  if (typeof env?.[config.upstream.secretBinding] !== "string" || env[config.upstream.secretBinding] === "") {
    missing.push(config.upstream.secretBinding);
  }
  if (config.entitlements.projection) {
    const secret = env?.[config.entitlements.projection.secretBinding];
    if (typeof secret !== "string" || new TextEncoder().encode(secret).byteLength < 32
      || new TextEncoder().encode(secret).byteLength > 4096) {
      missing.push(config.entitlements.projection.secretBinding);
    }
  }
  if (missing.length > 0) invalid(`missing runtime bindings: ${missing.join(", ")}`);
}

export const gatewayConfigInternals = Object.freeze({ TOKEN_FIELDS });
