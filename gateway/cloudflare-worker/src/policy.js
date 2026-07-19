import { fail } from "./errors.js";
import { enforceWireProtocol } from "./wire.js";

const TOKEN_FIELDS = ["max_output_tokens", "max_tokens", "max_completion_tokens"];
const UPSTREAM_OVERRIDE_FIELDS = ["api_base", "baseURL", "base_url", "endpoint"];
const UNMETERED_FEATURE_FIELDS = ["web_search_options"];

function selectRoute(config, url, method) {
  if (url.search !== "") fail(400, "query_not_allowed", "Query parameters are not accepted by this route.");
  const pathRoutes = config.routes.filter((route) => route.path === url.pathname);
  if (pathRoutes.length === 0) fail(404, "route_not_allowed", "This model route is not enabled.");
  const route = pathRoutes.find((candidate) => candidate.methods.includes(method.toUpperCase()));
  if (!route) {
    fail(405, "method_not_allowed", "This method is not enabled for the model route.", {
      headers: { allow: [...new Set(pathRoutes.flatMap((candidate) => candidate.methods))].join(", ") },
    });
  }
  return route;
}

async function readBoundedBody(request, maximum) {
  const declared = request.headers.get("content-length");
  if (declared !== null) {
    if (!/^\d+$/.test(declared)) fail(400, "invalid_content_length", "The request length is invalid.");
    if (Number(declared) > maximum) fail(413, "body_too_large", "The model request is too large.");
  }
  if (!request.body) fail(400, "body_required", "A JSON model request is required.");
  const reader = request.body.getReader();
  const chunks = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > maximum) {
        await reader.cancel("body limit exceeded");
        fail(413, "body_too_large", "The model request is too large.");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
}

function parseBody(bytes) {
  let text;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    fail(400, "invalid_json", "The model request must be valid UTF-8 JSON.");
  }
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    fail(400, "invalid_json", "The model request must be valid JSON.");
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    fail(400, "invalid_body", "The model request must be a JSON object.");
  }
  return body;
}

function enforceModel(route, body) {
  if (typeof body.model !== "string" || !route.models.includes(body.model)) {
    fail(403, "model_not_allowed", "The requested model is not enabled.");
  }
  return body.model;
}

function enforceTokens(config, route, body) {
  const supplied = TOKEN_FIELDS.filter((field) => Object.hasOwn(body, field));
  if (supplied.length > 1 || (supplied.length === 1 && supplied[0] !== route.tokenField)) {
    fail(400, "ambiguous_token_limit", "The model request uses an unsupported token limit field.");
  }
  const value = supplied.length === 0 ? config.limits.maxOutputTokens : body[route.tokenField];
  if (!Number.isInteger(value) || value < 1 || value > config.limits.maxOutputTokens) {
    fail(400, "token_limit_exceeded", "The requested output token limit is invalid or too large.");
  }
  body[route.tokenField] = value;
  return value;
}

function enforceTools(config, route, body) {
  let count = 0;
  if (Object.hasOwn(body, "tools")) {
    if (!Array.isArray(body.tools)) fail(400, "invalid_tools", "Model tools must be an array.");
    for (const tool of body.tools) {
      if (!tool || typeof tool !== "object" || Array.isArray(tool)
        || typeof tool.type !== "string" || !route.allowedToolTypes.includes(tool.type)) {
        fail(400, "tool_type_not_allowed", "The model request contains an unmetered tool type.");
      }
    }
    count += body.tools.length;
  }
  if (Object.hasOwn(body, "functions")) {
    if (!Array.isArray(body.functions)
      || body.functions.some((item) => !item || typeof item !== "object" || Array.isArray(item))) {
      fail(400, "invalid_tools", "Model tools must be an array of objects.");
    }
    count += body.functions.length;
  }
  if (count > config.limits.maxTools) fail(400, "tool_limit_exceeded", "The model request contains too many tools.");
  return count;
}

function enforceSingleGeneration(body) {
  if ((Object.hasOwn(body, "n") && body.n !== 1)
    || (Object.hasOwn(body, "best_of") && body.best_of !== 1)) {
    fail(400, "generation_multiplier_not_allowed", "Only one model generation is allowed per request.");
  }
  if (UNMETERED_FEATURE_FIELDS.some((field) => Object.hasOwn(body, field))) {
    fail(400, "unmetered_feature_not_allowed", "The model request contains an unmetered server-side feature.");
  }
}

function rejectUpstreamOverrides(body) {
  if (UPSTREAM_OVERRIDE_FIELDS.some((field) => Object.hasOwn(body, field))) {
    fail(400, "upstream_override_forbidden", "The model service endpoint cannot be overridden.");
  }
}

function upstreamUrl(config, route) {
  if (!config.upstream.allowedBaseUrls.includes(config.upstream.baseUrl)) {
    fail(503, "gateway_misconfigured", "The gateway is not configured for service.");
  }
  let result;
  try {
    result = new URL(`${config.upstream.baseUrl}${route.upstreamPath}`);
  } catch {
    fail(503, "gateway_misconfigured", "The gateway is not configured for service.");
  }
  const base = new URL(config.upstream.baseUrl);
  if (result.origin !== base.origin || result.username || result.password || result.search || result.hash) {
    fail(503, "gateway_misconfigured", "The gateway is not configured for service.");
  }
  const basePath = base.pathname.replace(/\/$/, "");
  if (basePath && basePath !== "/" && !result.pathname.startsWith(`${basePath}/`)) {
    fail(503, "gateway_misconfigured", "The gateway is not configured for service.");
  }
  return result.toString();
}

function upstreamHeaders(config, request, secret) {
  const headers = new Headers();
  for (const name of config.upstream.requestHeaders) {
    const value = request.headers.get(name);
    if (value !== null) headers.set(name, value);
  }
  for (const [name, value] of Object.entries(config.upstream.staticHeaders)) headers.set(name, value);
  headers.set("content-type", "application/json");
  headers.set(config.upstream.secretHeader, `${config.upstream.secretPrefix}${secret}`);
  return headers;
}

function canonicalValue(value) {
  if (Array.isArray(value)) return value.map(canonicalValue);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value).sort().map((key) => [key, canonicalValue(value[key])]),
    );
  }
  return value;
}

export async function prepareModelRequest(config, request, secret) {
  const url = new URL(request.url);
  const route = selectRoute(config, url, request.method);
  const contentType = request.headers.get("content-type") ?? "";
  if (!/^application\/json(?:\s*;|$)/i.test(contentType)) {
    fail(415, "content_type_not_allowed", "The model request must use application/json.");
  }
  const input = await readBoundedBody(request, config.limits.maxBodyBytes);
  const body = parseBody(input);
  rejectUpstreamOverrides(body);
  enforceSingleGeneration(body);
  const model = enforceModel(route, body);
  const outputTokenLimit = enforceTokens(config, route, body);
  const toolCount = enforceTools(config, route, body);
  enforceWireProtocol(route, body);
  const encoded = new TextEncoder().encode(JSON.stringify(body));
  const canonicalBody = new TextEncoder().encode(JSON.stringify(canonicalValue(body)));
  const reservedUnits = config.limits.requestBaseUnits
    + route.modelUnitWeights[model] * (encoded.byteLength + outputTokenLimit);
  if (!Number.isSafeInteger(reservedUnits)) {
    fail(503, "gateway_misconfigured", "The gateway is not configured for service.");
  }
  return Object.freeze({
    route,
    model,
    reservedUnits,
    outputTokenLimit,
    toolCount,
    body: encoded,
    canonicalBody,
    upstreamUrl: upstreamUrl(config, route),
    headers: upstreamHeaders(config, request, secret),
  });
}

export function allowedResponseHeaders(config, upstreamHeaders) {
  const result = new Headers({
    "cache-control": "no-store",
    "x-content-type-options": "nosniff",
  });
  const contentType = upstreamHeaders.get("content-type");
  if (contentType !== null) result.set("content-type", contentType);
  for (const name of config.upstream.responseHeaders) {
    const value = upstreamHeaders.get(name);
    if (value !== null) result.set(name, value);
  }
  return result;
}

export const policyInternals = Object.freeze({
  enforceModel,
  enforceSingleGeneration,
  enforceTokens,
  enforceTools,
  readBoundedBody,
  selectRoute,
  upstreamUrl,
});
