import { Authenticator } from "../../../gateway/cloudflare-worker/src/auth.js";
import { loadEntitlementConfig } from "./config.js";
import { CreemApi, normalizeCreemEvent, verifyCreemWebhook } from "./creem.js";
import { boundedRequestBody, canonical, decodeBase64Url, hmacKey, sha256Hex, subjectRef } from "./crypto.js";
import { EntitlementWorkerError, errorResponse, fail } from "./errors.js";
import { billingStatus, handleProjection } from "./policy.js";
import { CommerceStore } from "./store.js";

const JSON_LIMIT = 64 * 1024;
const RECONCILE_DOMAIN = "agentweave-commerce-reconcile-v1";

function exactObject(value, allowed) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail(400, "commerce_invalid_request", "The billing request is invalid.");
  }
  for (const key of Object.keys(value)) {
    if (!allowed.includes(key)) fail(400, "commerce_invalid_request", "The billing request is invalid.");
  }
  return value;
}

function boundedText(value, maximum = 256) {
  if (typeof value !== "string" || value === "" || value !== value.trim()
    || value.length > maximum || /[\x00-\x1f\x7f]/.test(value)) {
    fail(400, "commerce_invalid_request", "The billing request is invalid.");
  }
  return value;
}

async function jsonBody(request, allowed) {
  const bytes = await boundedRequestBody(request, JSON_LIMIT);
  let value;
  try {
    value = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch {
    fail(400, "commerce_invalid_request", "The billing request is invalid.");
  }
  return { value: exactObject(value, allowed), bytes };
}

function json(value, status = 200) {
  return Response.json(value, { status, headers: { "cache-control": "no-store" } });
}

function requestId(request, cryptoImpl) {
  const candidate = request.headers.get("x-agentweave-request-id");
  return candidate && /^[A-Za-z0-9_-]{16,128}$/.test(candidate)
    ? candidate
    : cryptoImpl.randomUUID();
}

function commerceStore(config, env, nowSeconds) {
  if (config.policy.sourceMode !== "commerce_provider") return null;
  return new CommerceStore(env[config.bindings.commerce], {
    appId: config.appId,
    environment: config.commerce.environment,
    nowSeconds,
  });
}

async function authenticate(request, config, authenticatorFactory) {
  const identity = await authenticatorFactory(config).authenticate(request);
  const provider = config.auth.providers.find((candidate) => candidate.id === identity.providerId);
  if (!provider || provider.issuer !== identity.issuer) {
    fail(401, "authentication_failed", "A valid user identity is required.");
  }
  return identity;
}

function enabledPlan(config, planId) {
  const plan = config.policy.productPlans.find((candidate) => candidate.enabled && candidate.id === planId);
  if (!plan) fail(403, "commerce_plan_unavailable", "This subscription plan is unavailable.");
  return plan;
}

async function verifyReconcile(request, body, secrets, nowSeconds, cryptoImpl) {
  const timestamp = request.headers.get("x-agentweave-reconcile-timestamp");
  const signature = request.headers.get("x-agentweave-reconcile-signature");
  if (!/^\d{1,16}$/.test(timestamp ?? "") || !signature?.startsWith("v1=")) {
    fail(401, "commerce_reconcile_unauthorized", "Reconciliation authorization is invalid.");
  }
  const timestampValue = Number(timestamp);
  if (!Number.isSafeInteger(timestampValue) || Math.abs(timestampValue - nowSeconds()) > 300) {
    fail(401, "commerce_reconcile_unauthorized", "Reconciliation authorization is invalid.");
  }
  let signatureBytes;
  try {
    signatureBytes = decodeBase64Url(signature.slice(3));
  } catch {
    fail(401, "commerce_reconcile_unauthorized", "Reconciliation authorization is invalid.");
  }
  const signed = canonical(RECONCILE_DOMAIN, [timestamp], body);
  let valid = false;
  for (const secret of secrets) {
    const key = await hmacKey(secret, cryptoImpl);
    if (await cryptoImpl.subtle.verify("HMAC", key, signatureBytes, signed).catch(() => false)) {
      valid = true;
      break;
    }
  }
  if (!valid) fail(401, "commerce_reconcile_unauthorized", "Reconciliation authorization is invalid.");
}

async function reconcileSubscription(subscriptionId, config, store, api, nowSeconds, cryptoImpl) {
  const object = await api.getSubscription(subscriptionId);
  const bytes = new TextEncoder().encode(JSON.stringify(object));
  const bodyHash = await sha256Hex(bytes, cryptoImpl);
  const synthetic = {
    value: {
      id: `evt_reconcile_${bodyHash.slice(0, 32)}`,
      eventType: "subscription.update",
      created_at: nowSeconds() * 1000,
      object,
    },
    rawBody: bytes,
    bodyHash,
  };
  const normalized = await normalizeCreemEvent(synthetic, config, store, cryptoImpl);
  await store.applyEvent(normalized);
  return normalized;
}

async function allSettledInBatches(items, worker, batchSize = 4, onRejected = () => {}) {
  for (let start = 0; start < items.length; start += batchSize) {
    const batch = items.slice(start, start + batchSize);
    const results = await Promise.allSettled(batch.map(worker));
    results.forEach((result, index) => {
      if (result.status !== "rejected") return;
      try {
        onRejected(batch[index], result.reason);
      } catch {
        // Reporting must not prevent later subscriptions from reconciling.
      }
    });
  }
}

export function createEntitlementWorker({
  fetchImpl = globalThis.fetch,
  cryptoImpl = globalThis.crypto,
  nowSeconds = () => Math.floor(Date.now() / 1000),
  authenticatorFactory = (config) => new Authenticator(config),
  logger = console,
} = {}) {
  return {
    async fetch(request, env) {
      const id = requestId(request, cryptoImpl);
      try {
        const config = loadEntitlementConfig(env);
        const url = new URL(request.url);
        const store = commerceStore(config, env, nowSeconds);
        if (request.method === "GET" && url.pathname === "/healthz") {
          return json({
            status: "ready",
            service: "entitlement-policy",
            schema_version: 1,
            protocol_version: "2",
            deployment_id: config.deploymentId,
            remote_version: env.CF_VERSION_METADATA?.id ?? "local",
          });
        }
        if (request.method === "GET" && url.pathname === "/version") {
          return json({ serviceVersion: "0.1.0", projectionVersions: [2], commerceVersion: 1 });
        }
        if (request.method === "GET" && url.pathname === "/.well-known/agentweave-entitlement-policy") {
          return json({
            providerId: "agentweave.entitlements.cloudflare_policy",
            capabilities: ["gateway_policy_projection_v2", ...(config.commerce ? [
              "checkout_session_v1", "customer_portal_v1", "signed_webhook_v1",
              "subscription_reconciliation_v1", "product_discovery_v1", "test_environment_v1",
            ] : [])],
          });
        }
        if (request.method === "POST" && url.pathname === "/agentweave/entitlements/projection") {
          return handleProjection(request, config, store, env, { cryptoImpl, nowSeconds });
        }
        if (!config.commerce || !store) fail(404, "commerce_not_configured", "Commerce is not configured.");
        const api = new CreemApi(config, env.CREEM_API_KEY, { fetchImpl });
        if (request.method === "POST" && url.pathname === "/agentweave/commerce/v1/webhooks/creem") {
          const verified = await verifyCreemWebhook(request, env.CREEM_WEBHOOK_SECRET, cryptoImpl);
          const envelope = exactObject(verified.value, ["id", "eventType", "created_at", "object"]);
          const existing = await store.eventById(boundedText(envelope.id));
          if (existing && existing.body_hash !== verified.bodyHash) {
            fail(409, "commerce_event_conflict", "The webhook event conflicts with existing data.");
          }
          if (existing) return json({ accepted: true, replayed: true });
          const normalized = await normalizeCreemEvent(verified, config, store, cryptoImpl);
          await store.applyEvent(normalized);
          await store.recordVerification("signed_webhook_v1");
          return json({ accepted: true, replayed: false });
        }
        if (request.method === "POST" && url.pathname === "/agentweave/commerce/v1/reconcile") {
          const parsed = await jsonBody(request, ["subscriptionId"]);
          await verifyReconcile(
            request,
            parsed.bytes,
            [env.ENTITLEMENT_PROJECTION_SECRET, env.ENTITLEMENT_PROJECTION_SECRET_NEXT]
              .filter((secret) => typeof secret === "string"),
            nowSeconds,
            cryptoImpl,
          );
          const subscriptionId = boundedText(parsed.value.subscriptionId);
          const result = await reconcileSubscription(subscriptionId, config, store, api, nowSeconds, cryptoImpl);
          return json({ reconciled: true, subscriptionId: result.fact?.subscriptionId ?? subscriptionId });
        }
        const identity = await authenticate(request, config, authenticatorFactory);
        const reference = await subjectRef(config, identity, env.COMMERCE_SUBJECT_BINDING_SECRET, cryptoImpl);
        if (request.method === "GET" && url.pathname === "/agentweave/commerce/v1/status") {
          return json(await billingStatus(config, store, identity, env, { cryptoImpl, nowSeconds }));
        }
        if (request.method === "POST" && url.pathname === "/agentweave/commerce/v1/checkout") {
          const parsed = await jsonBody(request, ["planId", "requestId", "requestNonce"]);
          const planId = boundedText(parsed.value.planId, 128);
          const checkoutRequestId = boundedText(parsed.value.requestId, 256);
          const nonce = boundedText(parsed.value.requestNonce, 256);
          const plan = enabledPlan(config, planId);
          if (!/^request_[A-Za-z0-9_-]{16,240}$/.test(checkoutRequestId)
            || !/^[A-Za-z0-9_-]{16,256}$/.test(nonce)) {
            fail(400, "commerce_invalid_request", "The billing request is invalid.");
          }
          await store.consumeNonce(reference, "checkout", await sha256Hex(new TextEncoder().encode(nonce), cryptoImpl));
          const requestHash = await sha256Hex(new TextEncoder().encode([
            config.appId, config.commerce.environment, reference, plan.productId, plan.id,
          ].join("\0")), cryptoImpl);
          await store.recordCheckout({
            requestId: checkoutRequestId,
            subjectRef: reference,
            productId: plan.productId,
            planId: plan.id,
            requestHash,
          });
          const customer = await store.customerForSubject(reference);
          const session = await api.createCheckout({
            productId: plan.productId,
            requestId: checkoutRequestId,
            customerId: customer?.customer_id ?? null,
            metadata: {
              agentweaveAppId: config.appId,
              agentweaveSubjectRef: reference,
              agentweavePlanId: plan.id,
            },
          });
          return json(session, 201);
        }
        if (request.method === "POST" && url.pathname === "/agentweave/commerce/v1/customer-portal") {
          const parsed = await jsonBody(request, ["requestNonce"]);
          const nonce = boundedText(parsed.value.requestNonce, 256);
          if (!/^[A-Za-z0-9_-]{16,256}$/.test(nonce)) {
            fail(400, "commerce_invalid_request", "The billing request is invalid.");
          }
          await store.consumeNonce(reference, "customer_portal", await sha256Hex(new TextEncoder().encode(nonce), cryptoImpl));
          const customer = await store.customerForSubject(reference);
          if (!customer) fail(409, "commerce_customer_unbound", "There is no subscription to manage yet.");
          const session = await api.createCustomerPortal(customer.customer_id);
          return json(session);
        }
        if (request.method === "POST" && url.pathname === "/agentweave/commerce/v1/customer-portal/verified") {
          const parsed = await jsonBody(request, ["requestNonce"]);
          const nonce = boundedText(parsed.value.requestNonce, 256);
          if (!/^[A-Za-z0-9_-]{16,256}$/.test(nonce)) {
            fail(400, "commerce_invalid_request", "The billing request is invalid.");
          }
          await store.consumeNonce(
            reference,
            "customer_portal_verified",
            await sha256Hex(new TextEncoder().encode(nonce), cryptoImpl),
          );
          const customer = await store.customerForSubject(reference);
          if (!customer) fail(409, "commerce_customer_unbound", "There is no subscription to manage yet.");
          await store.recordVerification("customer_portal_v1");
          return json({ verified: true });
        }
        fail(404, "not_found", "The requested endpoint was not found.");
      } catch (error) {
        return errorResponse(error, id);
      }
    },

    async scheduled(_event, env, context) {
      const config = loadEntitlementConfig(env);
      if (!config.commerce) return;
      const store = commerceStore(config, env, nowSeconds);
      const api = new CreemApi(config, env.CREEM_API_KEY, { fetchImpl });
      const candidates = await store.reconciliationCandidates(50);
      const work = allSettledInBatches(
        candidates,
        (subscriptionId) => reconcileSubscription(subscriptionId, config, store, api, nowSeconds, cryptoImpl),
        4,
        (subscriptionId, error) => logger.error("Subscription reconciliation failed.", {
          subscriptionId,
          code: error instanceof EntitlementWorkerError ? error.code : "entitlement_service_unavailable",
        }),
      );
      context.waitUntil(work);
    },
  };
}

export default createEntitlementWorker();

export const workerInternals = Object.freeze({
  RECONCILE_DOMAIN,
  allSettledInBatches,
  reconcileSubscription,
});
