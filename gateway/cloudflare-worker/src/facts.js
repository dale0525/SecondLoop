export const WORKER_VERSION = "0.3.0";
export const GATEWAY_CONTRACT_VERSION = 1;
export const D1_SCHEMA_VERSION = 3;

const readinessCache = new WeakMap();
const READINESS_CACHE_MILLISECONDS = 15_000;

function json(value, status = 200) {
  return Response.json(value, {
    status,
    headers: {
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
    },
  });
}

export async function readinessProbe(config, env, nowMilliseconds = Date.now()) {
  const cacheKey = `${config.deploymentId}\0${config.configurationId}`;
  const database = env[config.bindings.entitlements];
  const cache = readinessCache.get(database);
  const cached = cache?.get(cacheKey);
  if (cached && cached.expiresAt > nowMilliseconds) return cached.value;
  try {
    const metadata = await env[config.bindings.entitlements].prepare(`
      SELECT
        (SELECT value FROM gateway_schema_metadata WHERE key = 'schema_version') AS schema_version,
        (SELECT value FROM gateway_schema_metadata WHERE key = 'last_cleanup_at') AS last_cleanup_at,
        EXISTS(
          SELECT 1 FROM gateway_entitlements
          WHERE deployment_id IS NOT NULL AND tenant IS NOT NULL AND reserved_units >= 0
            AND policy_source IS NOT NULL AND policy_expires_at >= 0
          LIMIT 1
        ) AS entitlement_schema_probe,
        (SELECT COUNT(*) >= 0 FROM gateway_entitlement_models
          WHERE policy_source IS NOT NULL AND policy_expires_at >= 0
        ) AS entitlement_model_schema_probe,
        EXISTS(
          SELECT 1 FROM gateway_reservations
          WHERE finalized IN (0, 1) AND device_id IS NOT NULL
            AND dispatched_at IS NULL AND reservation_fence IS NOT NULL
          LIMIT 1
        ) AS reservation_schema_probe,
        EXISTS(
          SELECT 1 FROM gateway_idempotency_tombstones
          WHERE retain_until >= 0 AND request_hash IS NOT NULL
          LIMIT 1
        ) AS tombstone_schema_probe,
        (SELECT COUNT(*) FROM gateway_deployment_budgets
          WHERE deployment_id = ?1 AND period_start <= ?2 AND period_end > ?2
        ) AS deployment_budget_rows
    `).bind(config.deploymentId, Math.floor(nowMilliseconds / 1000)).first();
    if (metadata?.schema_version !== String(D1_SCHEMA_VERSION)
      || Number(metadata.deployment_budget_rows) !== 1) {
      return { ready: false, lastCleanupAt: null };
    }
    const namespace = env[config.bindings.concurrency];
    const id = namespace.idFromName("agentweave-gateway-readiness-v1");
    const response = await namespace.get(id).fetch("https://quota.internal/health", { method: "GET" });
    if (!response.ok) return { ready: false, lastCleanupAt: null };
    const durableObject = await response.json();
    if (durableObject?.contract_version !== 1) return { ready: false, lastCleanupAt: null };
    const lastCleanupAt = Number(metadata.last_cleanup_at);
    const value = {
      ready: true,
      lastCleanupAt: Number.isInteger(lastCleanupAt) && lastCleanupAt > 0 ? lastCleanupAt : null,
    };
    const target = cache ?? new Map();
    target.set(cacheKey, {
      value,
      expiresAt: nowMilliseconds + READINESS_CACHE_MILLISECONDS,
    });
    if (!cache) readinessCache.set(database, target);
    return value;
  } catch {
    return { ready: false, lastCleanupAt: null };
  }
}

export async function healthResponse(config, env, request) {
  const readiness = await readinessProbe(config, env);
  if (!readiness.ready) return unhealthyResponse();
  return json({
    status: "ready",
    contract_version: GATEWAY_CONTRACT_VERSION,
    worker_version: WORKER_VERSION,
    deployment_id: config.deploymentId,
    configuration_id: config.configurationId,
    environment: config.environment,
    region: request.cf?.colo ?? null,
    version_id: env.CF_VERSION_METADATA?.id ?? null,
    maintenance_last_run: readiness.lastCleanupAt,
  });
}

export async function authenticatedHealthResponse(config, env) {
  const readiness = await readinessProbe(config, env);
  const remoteVersion = env.CF_VERSION_METADATA?.id;
  if (!readiness.ready || typeof remoteVersion !== "string" || remoteVersion === "") {
    return unhealthyResponse();
  }
  return json({
    status: "ready",
    protocol_version: String(GATEWAY_CONTRACT_VERSION),
    deployment_id: config.deploymentId,
    remote_version: remoteVersion,
  });
}

export function unhealthyResponse() {
  return json({
    status: "misconfigured",
    contract_version: GATEWAY_CONTRACT_VERSION,
    worker_version: WORKER_VERSION,
  }, 503);
}

export function versionResponse() {
  return json({
    contract_version: GATEWAY_CONTRACT_VERSION,
    worker_version: WORKER_VERSION,
  });
}

export function deploymentFactsResponse(config, env) {
  return json({
    kind: "agentweave.model-gateway",
    contract_version: GATEWAY_CONTRACT_VERSION,
    worker_version: WORKER_VERSION,
    deployment: {
      id: config.deploymentId,
      configuration_id: config.configurationId,
      environment: config.environment,
      platform: "cloudflare-workers",
      version_id: env.CF_VERSION_METADATA?.id ?? null,
      version_tag: env.CF_VERSION_METADATA?.tag ?? null,
    },
    authentication: {
      mode: config.auth.mode,
      providers: config.auth.providers.map((provider) => ({
        id: provider.id,
        kind: provider.kind,
        tenant_scope: provider.projection.tenantClaim ? "verified-claim" : "configured-provider",
        device_mode: provider.projection.deviceMode,
      })),
    },
    policy: {
      routes: config.routes.map((route) => ({
        id: route.id,
        path: route.path,
        methods: route.methods,
        models: route.models,
        allowed_tool_types: route.allowedToolTypes,
        wire_protocol: route.wireProtocol,
        model_unit_weights: route.modelUnitWeights,
      })),
      max_body_bytes: config.limits.maxBodyBytes,
      max_output_tokens: config.limits.maxOutputTokens,
      max_tools: config.limits.maxTools,
      single_generation: true,
      idempotency_header: "x-agentweave-request-id",
      usage_units: "request_base + model_weight * (canonical_request_bytes + max_output_tokens)",
      entitlements: "d1-authoritative",
      entitlement_policy: {
        mode: config.entitlements.mode,
        source_id: config.entitlements.projection?.sourceId ?? null,
        signed_projection: config.entitlements.mode === "signed_http",
      },
      concurrency: {
        enforcement: "durable-object-strict",
        deployment_limit: config.concurrency.deploymentLimit,
        tenant_limit: config.concurrency.tenantLimit,
        subject_limit: "entitlement-row",
        device_limit: config.rateLimit.deviceRequired ? config.concurrency.deviceLimit : null,
      },
      rate_limit: config.rateLimit.required ? "required-multi-axis" : "optional",
      request_body_logging: false,
      reservation_retention_seconds: config.limits.reservationRetentionSeconds,
      idempotency_retention_seconds: config.limits.idempotencyRetentionSeconds,
      maintenance_batch_size: config.limits.maintenanceBatchSize,
      model_requests_enabled: config.controls.modelRequestsEnabled,
      budget_axes: ["deployment", "tenant", "subject"],
      device_isolation: config.rateLimit.deviceRequired ? "signed-identity-claim" : "disabled",
    },
  });
}
