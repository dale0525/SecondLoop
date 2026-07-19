import { Authenticator, JwksResolver, JwtVerifier } from "./auth.js";
import { loadGatewayConfig, validateRuntimeBindings } from "./config.js";
import { D1EntitlementStore } from "./entitlements.js";
import { errorResponse, fail, safeErrorCode } from "./errors.js";
import {
  authenticatedHealthResponse,
  deploymentFactsResponse,
  healthResponse,
  unhealthyResponse,
  versionResponse,
} from "./facts.js";
import { prepareModelRequest } from "./policy.js";
import { EntitlementProjectionResolver } from "./projection.js";
import { fetchModelUpstream, streamingResponse } from "./proxy.js";
import { checkEdgeAdmission, ConcurrencyLimiter, QuotaCoordinator } from "./quota.js";

const PUBLIC_ROUTES = new Set(["/healthz", "/version", "/.well-known/agentweave-gateway"]);
const AUTHENTICATED_HEALTH_ROUTE = "/.well-known/agentweave/gateway-health";
const IDEMPOTENCY_HEADER = "x-agentweave-request-id";

function requestId(cryptoImpl) {
  try {
    return cryptoImpl.randomUUID();
  } catch {
    return `gateway-${Date.now()}`;
  }
}

function audit(logger, level, event) {
  const method = typeof logger?.[level] === "function" ? logger[level].bind(logger) : null;
  if (method) method(event);
}

function idempotencyKey(request) {
  const value = request.headers.get(IDEMPOTENCY_HEADER);
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]{16,128}$/.test(value)) {
    fail(400, "idempotency_key_required", `A valid ${IDEMPOTENCY_HEADER} header is required.`);
  }
  return value;
}

async function requestHash(prepared, cryptoImpl) {
  const prefix = new TextEncoder().encode(`${prepared.route.id}\0${prepared.upstreamUrl}\0`);
  const input = new Uint8Array(prefix.byteLength + prepared.canonicalBody.byteLength);
  input.set(prefix);
  input.set(prepared.canonicalBody, prefix.byteLength);
  const digest = await cryptoImpl.subtle.digest("SHA-256", input);
  return [...new Uint8Array(digest)].map((value) => value.toString(16).padStart(2, "0")).join("");
}

async function publicRouteResponse(path, config, env, request) {
  if (request.method !== "GET") {
    return new Response(null, { status: 405, headers: { allow: "GET", "cache-control": "no-store" } });
  }
  if (path === "/healthz") return healthResponse(config, env, request);
  if (path === "/version") return versionResponse();
  return deploymentFactsResponse(config, env);
}

export function createGateway({
  fetchImpl = globalThis.fetch,
  cryptoImpl = globalThis.crypto,
  nowMilliseconds = () => Date.now(),
  setTimeoutImpl = globalThis.setTimeout,
  clearTimeoutImpl = globalThis.clearTimeout,
  logger = console,
  authenticatorFactory,
  entitlementStoreFactory,
  projectionResolverFactory,
  quotaCoordinatorFactory,
} = {}) {
  const jwksResolver = new JwksResolver({ fetchImpl, nowMilliseconds });
  const verifier = new JwtVerifier({
    cryptoImpl,
    jwksResolver,
    nowSeconds: () => Math.floor(nowMilliseconds() / 1000),
  });

  return Object.freeze({
    async fetch(request, env, context = {}) {
      const id = requestId(cryptoImpl);
      const startedAt = nowMilliseconds();
      const path = new URL(request.url).pathname;
      let config;
      try {
        await checkEdgeAdmission(request, env, cryptoImpl);
        config = loadGatewayConfig(env);
        validateRuntimeBindings(config, env, { remoteRequest: request.cf !== undefined });
      } catch (error) {
        audit(logger, "error", {
          event: "gateway.configuration_error",
          request_id: id,
          error_code: safeErrorCode(error),
        });
        if (path === "/healthz" && safeErrorCode(error) === "gateway_misconfigured") {
          return unhealthyResponse();
        }
        return errorResponse(error, id);
      }

      if (PUBLIC_ROUTES.has(path)) return publicRouteResponse(path, config, env, request);

      if (path === AUTHENTICATED_HEALTH_ROUTE) {
        if (request.method !== "GET") {
          return new Response(null, {
            status: 405,
            headers: { allow: "GET", "cache-control": "no-store" },
          });
        }
        try {
          const authenticator = authenticatorFactory
            ? authenticatorFactory(config, env)
            : new Authenticator(config, verifier);
          const identity = await authenticator.authenticate(request);
          const quota = quotaCoordinatorFactory
            ? quotaCoordinatorFactory(config, env)
            : new QuotaCoordinator(config, env, { cryptoImpl, nowMilliseconds });
          await quota.checkIdentityRate(identity);
          return authenticatedHealthResponse(config, env);
        } catch (error) {
          audit(logger, "error", {
            event: "gateway.authenticated_health_failed",
            request_id: id,
            error_code: safeErrorCode(error),
          });
          return errorResponse(error, id);
        }
      }

      let reservation = null;
      let lease = null;
      let entitlements = null;
      let quota = null;
      let routeId = null;
      let model = null;
      let deadline = null;
      try {
        if (!config.controls.modelRequestsEnabled) {
          fail(503, "gateway_disabled", "Model requests are temporarily disabled.");
        }
        quota = quotaCoordinatorFactory
          ? quotaCoordinatorFactory(config, env)
          : new QuotaCoordinator(config, env, { cryptoImpl, nowMilliseconds });
        entitlements = entitlementStoreFactory
          ? entitlementStoreFactory(config, env)
          : new D1EntitlementStore(env[config.bindings.entitlements], {
            deploymentId: config.deploymentId,
            policySource: config.entitlements.policySource,
            randomUUID: () => cryptoImpl.randomUUID(),
            nowSeconds: () => Math.floor(nowMilliseconds() / 1000),
            cryptoImpl,
          });
        await entitlements.assertDeploymentEnabled();
        const authenticator = authenticatorFactory
          ? authenticatorFactory(config, env)
          : new Authenticator(config, verifier);
        const identity = await authenticator.authenticate(request);
        await quota.checkIdentityRate(identity);
        const secret = env[config.upstream.secretBinding];
        const prepared = await prepareModelRequest(config, request, secret);
        routeId = prepared.route.id;
        model = prepared.model;
        const requestIdempotencyKey = idempotencyKey(request);
        const preparedRequestHash = await requestHash(prepared, cryptoImpl);
        const projection = projectionResolverFactory
          ? projectionResolverFactory(config, env)
          : new EntitlementProjectionResolver(config, env, {
            fetchImpl,
            cryptoImpl,
            nowMilliseconds,
            setTimeoutImpl,
            clearTimeoutImpl,
          });
        await projection.ensure(identity, { model: prepared.model });

        reservation = await entitlements.reserve(identity, {
          model: prepared.model,
          units: prepared.reservedUnits,
          ttlSeconds: config.limits.reservationTtlSeconds,
          idempotencyKey: requestIdempotencyKey,
          requestHash: preparedRequestHash,
          idempotencyRetentionSeconds: config.limits.idempotencyRetentionSeconds,
          cleanupBatchSize: config.limits.maintenanceBatchSize,
        });
        if (!Number.isInteger(reservation?.expiresAt)) {
          fail(503, "entitlement_service_unavailable", "Usage authorization is temporarily unavailable.");
        }
        try {
          lease = await quota.acquireConcurrency(
            identity,
            reservation.maxConcurrency,
            config.limits.reservationTtlSeconds,
          );
        } catch (error) {
          await entitlements.settle(reservation, { outcome: "failed", actualUnits: 0 });
          reservation = null;
          throw error;
        }

        let upstream;
        const abortController = new AbortController();
        const entitlementDeadline = reservation.expiresAt * 1000;
        const concurrencyDeadline = Number.isInteger(lease.expiresAt)
          ? lease.expiresAt
          : entitlementDeadline;
        const responseDeadlineMilliseconds = Math.min(entitlementDeadline, concurrencyDeadline)
          - nowMilliseconds() - 5_000;
        if (responseDeadlineMilliseconds <= 0) {
          fail(503, "entitlement_reservation_expired", "Usage authorization expired before the model request started.");
        }
        deadline = setTimeoutImpl(
          () => abortController.abort("gateway request deadline exceeded"),
          responseDeadlineMilliseconds,
        );
        deadline?.unref?.();
        reservation = await entitlements.markDispatched(reservation);
        try {
          upstream = await fetchModelUpstream(fetchImpl, prepared, { signal: abortController.signal });
        } catch (error) {
          clearTimeoutImpl(deadline);
          deadline = null;
          const rejected = error?.dispatchOutcome === "rejected";
          await entitlements.settle(reservation, rejected
            ? { outcome: "rejected", actualUnits: 0 }
            : { outcome: "uncertain", actualUnits: reservation.reservedUnits });
          reservation = null;
          await quota.releaseConcurrency(lease);
          lease = null;
          throw error;
        }

        try {
          const settlement = await entitlements.settle(reservation, {
            outcome: "completed",
            // Committing the enforced maximum before exposing the stream keeps
            // D1 authoritative even when a later waitUntil task or client fails.
            actualUnits: reservation.reservedUnits,
          });
          if (!settlement?.applied && !settlement?.alreadyApplied) {
            fail(503, "entitlement_settlement_failed", "Usage authorization could not be committed.");
          }
          reservation = null;
        } catch (error) {
          try {
            await upstream.body?.cancel("entitlement settlement failed");
          } catch {
            // The response is not exposed, and cancellation errors are redacted.
          }
          throw error;
        }

        const finalize = async (outcome) => {
          clearTimeoutImpl(deadline);
          deadline = null;
          await quota.releaseConcurrency(lease);
          audit(logger, "info", {
            event: "gateway.request_completed",
            request_id: id,
            route_id: routeId,
            model,
            outcome,
            duration_ms: Math.max(0, nowMilliseconds() - startedAt),
          });
        };
        return streamingResponse(config, upstream, id, context, finalize);
      } catch (error) {
        if (deadline !== null) clearTimeoutImpl(deadline);
        if (reservation) {
          try {
            await entitlements?.settle(reservation, reservation.dispatched
              ? { outcome: "uncertain", actualUnits: reservation.reservedUnits }
              : { outcome: "failed", actualUnits: 0 });
          } catch {
            // The reservation expires and is reclaimed by the next authoritative D1 transaction.
          }
        }
        if (lease) await quota?.releaseConcurrency(lease);
        audit(logger, "error", {
          event: "gateway.request_failed",
          request_id: id,
          route_id: routeId,
          model,
          error_code: safeErrorCode(error),
          duration_ms: Math.max(0, nowMilliseconds() - startedAt),
        });
        return errorResponse(error, id);
      }
    },
    async scheduled(_controller, env) {
      const id = requestId(cryptoImpl);
      try {
        const config = loadGatewayConfig(env);
        validateRuntimeBindings(config, env, { remoteRequest: true });
        const entitlements = entitlementStoreFactory
          ? entitlementStoreFactory(config, env)
          : new D1EntitlementStore(env[config.bindings.entitlements], {
            deploymentId: config.deploymentId,
            randomUUID: () => cryptoImpl.randomUUID(),
            nowSeconds: () => Math.floor(nowMilliseconds() / 1000),
            cryptoImpl,
          });
        const result = await entitlements.cleanup({
          retentionSeconds: config.limits.reservationRetentionSeconds,
          batchSize: config.limits.maintenanceBatchSize,
        });
        audit(logger, "info", {
          event: "gateway.maintenance_completed",
          request_id: id,
          reservations_expired: result.reservationsExpired,
          reservations_deleted: result.reservationsDeleted,
        });
      } catch (error) {
        audit(logger, "error", {
          event: "gateway.maintenance_failed",
          request_id: id,
          error_code: safeErrorCode(error),
        });
        throw error;
      }
    },
  });
}

const gateway = createGateway();

export { ConcurrencyLimiter };

export default {
  fetch: gateway.fetch,
  scheduled: gateway.scheduled,
};
