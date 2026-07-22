import { base64Url, boundedRequestBody, canonical, decodeBase64Url, hmacKey, sha256Hex, subjectRef } from "./crypto.js";
import { EntitlementWorkerError, fail } from "./errors.js";

const REQUEST_DOMAIN_V2 = "agentweave-entitlement-projection-request-v2";
const RESPONSE_DOMAIN_V2 = "agentweave-entitlement-projection-response-v2";
const SIGNATURE_HEADER = "x-agentweave-entitlement-signature";
const TIMESTAMP_HEADER = "x-agentweave-entitlement-timestamp";
const NONCE_HEADER = "x-agentweave-entitlement-nonce";
const MAX_REQUEST_BYTES = 64 * 1024;

function exactObject(value, allowed, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new TypeError(`${label} is invalid`);
  for (const key of Object.keys(value)) {
    if (!allowed.includes(key)) throw new TypeError(`${label} contains an unknown field`);
  }
  return value;
}

function text(value, label, maximum = 2048) {
  if (typeof value !== "string" || value === "" || value.length > maximum
    || value !== value.trim() || /[\x00-\x1f\x7f]/.test(value)) {
    throw new TypeError(`${label} is invalid`);
  }
  return value;
}

function integer(value, label, minimum, maximum) {
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) {
    throw new TypeError(`${label} is invalid`);
  }
  return value;
}

function sourceId(config) {
  return config.policy.sourceMode === "commerce_provider"
    ? config.commerce.providerId
    : "agentweave.entitlements.cloudflare_policy";
}

function budgetLimit(value) {
  return value === 0
    ? Object.freeze({ mode: "unlimited" })
    : Object.freeze({ mode: "limited", value });
}

function budget(plan, periodStart, periodEnd, subject) {
  return Object.freeze({
    periodStart,
    periodEnd,
    requests: budgetLimit(plan.maxRequests),
    units: budgetLimit(plan.maxUnits),
    ...(subject ? { concurrency: budgetLimit(plan.maxConcurrency) } : {}),
  });
}

function uniformPeriod(now) {
  const date = new Date(now * 1000);
  const periodStart = Math.floor(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), 1) / 1000);
  const periodEnd = Math.floor(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 1) / 1000);
  return { periodStart, periodEnd };
}

function subscriptionPermits(row, now) {
  if (!row || row.revoked_at !== null && row.revoked_at !== undefined) return false;
  if (new Set(["expired", "unpaid", "refunded", "disputed"]).has(row.normalized_status)) return false;
  return Number.isSafeInteger(Number(row.paid_through)) && Number(row.paid_through) > now;
}

function selectSubscription(subscriptions, now) {
  const eligible = subscriptions.filter((row) => subscriptionPermits(row, now));
  return Object.freeze({
    eligible,
    subscription: eligible.length === 1 ? eligible[0] : subscriptions[0] ?? null,
  });
}

async function planFor(config, store, identity, model, now, cryptoImpl, env) {
  if (config.policy.sourceMode === "uniform_bounded") {
    const plan = config.policy.uniformPlan;
    const period = uniformPeriod(now);
    return {
      plan,
      ...period,
      reasonCode: plan.allowedModels.includes(model) ? null : "model_not_allowed",
      subjectRef: null,
      subscription: null,
    };
  }
  const reference = await subjectRef(config, identity, env.COMMERCE_SUBJECT_BINDING_SECRET, cryptoImpl);
  const subscriptions = await store.subscriptionForSubject(reference, now);
  if (!Array.isArray(subscriptions) || subscriptions.length === 0) {
    return { plan: null, ...uniformPeriod(now), reasonCode: "subscription_required", subjectRef: reference, subscription: null };
  }
  const { eligible, subscription } = selectSubscription(subscriptions, now);
  if (eligible.length > 1) {
    return { plan: null, ...uniformPeriod(now), reasonCode: "subscription_conflict", subjectRef: reference, subscription: null };
  }
  if (eligible.length !== 1) {
    return {
      plan: null,
      periodStart: Number(subscription.current_period_start ?? now),
      periodEnd: Math.max(now + 1, Number(subscription.current_period_end ?? now + 300)),
      reasonCode: subscription.revoked_at ? "subscription_revoked" : "subscription_inactive",
      subjectRef: reference,
      subscription,
    };
  }
  const plan = config.policy.productPlans.find((candidate) => candidate.enabled
    && candidate.id === subscription.plan_id && candidate.productId === subscription.product_id);
  if (!plan) {
    return { plan: null, ...uniformPeriod(now), reasonCode: "plan_unavailable", subjectRef: reference, subscription };
  }
  return {
    plan,
    periodStart: Number(subscription.current_period_start),
    periodEnd: Number(subscription.paid_through),
    reasonCode: plan.allowedModels.includes(model) ? null : "model_not_allowed",
    subjectRef: reference,
    subscription,
  };
}

export async function handleProjection(request, config, store, env, {
  cryptoImpl = globalThis.crypto,
  nowSeconds = () => Math.floor(Date.now() / 1000),
} = {}) {
  const body = await boundedRequestBody(request, MAX_REQUEST_BYTES);
  const timestampText = request.headers.get(TIMESTAMP_HEADER);
  const nonce = request.headers.get(NONCE_HEADER);
  const signature = request.headers.get(SIGNATURE_HEADER);
  try {
    text(timestampText, "timestamp", 32);
    text(nonce, "nonce", 128);
    if (!signature?.startsWith("v2=")) throw new TypeError("signature is invalid");
    const timestamp = integer(Number(timestampText), "timestamp", 0, Number.MAX_SAFE_INTEGER);
    const now = nowSeconds();
    if (Math.abs(timestamp - now) > 300) throw new TypeError("timestamp is stale");
    const signatureBytes = decodeBase64Url(signature.slice(3));
    const signedRequest = canonical(REQUEST_DOMAIN_V2, [timestampText, nonce], body);
    let key = null;
    for (const secret of [
      env.ENTITLEMENT_PROJECTION_SECRET,
      env.ENTITLEMENT_PROJECTION_SECRET_NEXT,
    ].filter((candidate) => typeof candidate === "string")) {
      const candidate = await hmacKey(secret, cryptoImpl);
      if (await cryptoImpl.subtle.verify("HMAC", candidate, signatureBytes, signedRequest)) {
        key = candidate;
        break;
      }
    }
    if (!key) throw new TypeError("signature is invalid");
    const value = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(body));
    exactObject(value, [
      "schemaVersion", "sourceId", "nonce", "deploymentId", "providerId", "issuer",
      "tenant", "subject", "model", "requestedAt",
    ], "projection request");
    if (value.schemaVersion !== 2 || value.sourceId !== sourceId(config)
      || value.nonce !== nonce || value.deploymentId !== config.deploymentId
      || value.requestedAt !== timestamp) throw new TypeError("projection binding is invalid");
    for (const field of ["providerId", "issuer", "tenant", "subject", "model"]) text(value[field], field);
    const provider = config.auth.providers.find((candidate) => candidate.id === value.providerId
      && candidate.issuer === value.issuer);
    if (!provider) throw new TypeError("identity provider is not configured");
    const identity = {
      providerId: value.providerId,
      issuer: value.issuer,
      tenant: value.tenant,
      subject: value.subject,
    };
    const decision = await planFor(config, store, identity, value.model, now, cryptoImpl, env);
    const planLimits = decision.plan?.limits ?? { maxRequests: 0, maxUnits: 0, maxConcurrency: 0 };
    const periodStart = Math.min(decision.periodStart, now);
    const periodEnd = Math.max(now + 1, decision.periodEnd);
    const expiresAt = Math.min(periodEnd, now + 300);
    const revision = decision.subscription?.projection_revision ?? config.configurationId;
    const projectionId = await sha256Hex(new TextEncoder().encode([
      sourceId(config), revision, value.tenant, value.subject, periodStart, value.model,
    ].join("\0")), cryptoImpl);
    const projection = {
      schemaVersion: 2,
      sourceId: sourceId(config),
      projectionId,
      revision,
      nonce,
      deploymentId: config.deploymentId,
      providerId: value.providerId,
      issuer: value.issuer,
      tenant: value.tenant,
      subject: value.subject,
      model: value.model,
      issuedAt: now,
      expiresAt,
      decision: decision.reasonCode === null ? "allow" : "deny",
      reasonCode: decision.reasonCode,
      tenantBudget: budget(config.policy.tenantLimits, periodStart, periodEnd, false),
      subjectBudget: budget(planLimits, periodStart, periodEnd, true),
    };
    const responseBody = new TextEncoder().encode(JSON.stringify(projection));
    const responseSignature = await cryptoImpl.subtle.sign(
      "HMAC",
      key,
      canonical(RESPONSE_DOMAIN_V2, [nonce], responseBody),
    );
    return new Response(responseBody, {
      status: 200,
      headers: {
        "cache-control": "no-store",
        "content-type": "application/json",
        [SIGNATURE_HEADER]: `v2=${base64Url(responseSignature)}`,
      },
    });
  } catch (error) {
    if (error instanceof EntitlementWorkerError) throw error;
    fail(401, "entitlement_projection_invalid", "The entitlement projection request is invalid.");
  }
}

export async function billingStatus(config, store, identity, env, {
  cryptoImpl = globalThis.crypto,
  nowSeconds = () => Math.floor(Date.now() / 1000),
} = {}) {
  if (config.policy.sourceMode !== "commerce_provider") {
    return Object.freeze({
      mode: "uniform_bounded",
      plan: config.policy.uniformPlan,
      subscription: null,
      customerBound: false,
      availablePlans: [],
    });
  }
  const reference = await subjectRef(config, identity, env.COMMERCE_SUBJECT_BINDING_SECRET, cryptoImpl);
  const now = nowSeconds();
  const subscriptions = await store.subscriptionForSubject(reference, now);
  const customer = await store.customerForSubject(reference);
  const { eligible, subscription } = selectSubscription(subscriptions, now);
  if (eligible.length > 1) {
    fail(409, "commerce_subscription_conflict", "Multiple active subscriptions require support.");
  }
  const plan = subscription
    ? config.policy.productPlans.find((candidate) => candidate.enabled
      && candidate.id === subscription.plan_id
      && candidate.productId === subscription.product_id) ?? null
    : null;
  return Object.freeze({
    mode: "commerce_provider",
    plan,
    subscription: subscription ? Object.freeze({
      status: subscription.normalized_status,
      paidThrough: subscription.paid_through,
      periodStart: subscription.current_period_start,
      periodEnd: subscription.current_period_end,
      revoked: subscription.revoked_at !== null && subscription.revoked_at !== undefined,
    }) : null,
    customerBound: Boolean(customer),
    availablePlans: config.policy.productPlans.filter((candidate) => candidate.enabled),
  });
}

export const policyInternals = Object.freeze({
  REQUEST_DOMAIN_V2,
  RESPONSE_DOMAIN_V2,
  SIGNATURE_HEADER,
  selectSubscription,
  sourceId,
  subscriptionPermits,
  uniformPeriod,
});
