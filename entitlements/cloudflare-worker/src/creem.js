import { boundedRequestBody, decodeBase64Url, hmacKey, sha256Hex } from "./crypto.js";
import { fail } from "./errors.js";

const MAX_RESPONSE_BYTES = 512 * 1024;
const MAX_WEBHOOK_BYTES = 256 * 1024;
const REVOKE_EVENTS = new Set([
  "subscription.expired",
  "subscription.unpaid",
  "refund.created",
  "dispute.created",
]);

function exactObject(value, allowed, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail(400, "commerce_invalid_payload", "The commerce payload is invalid.");
  }
  for (const key of Object.keys(value)) {
    if (!allowed.includes(key)) fail(400, "commerce_invalid_payload", "The commerce payload is invalid.");
  }
  return value;
}

function text(value, label, maximum = 2048) {
  if (typeof value !== "string" || value === "" || value.length > maximum || /[\x00-\x1f\x7f]/.test(value)) {
    fail(400, "commerce_invalid_payload", `The ${label} value is invalid.`);
  }
  return value;
}

function providerId(value, prefix) {
  const result = text(value, "provider identifier", 256);
  if (!result.startsWith(prefix) || !/^[A-Za-z0-9_]+$/.test(result)) {
    fail(400, "commerce_invalid_payload", "The commerce provider identifier is invalid.");
  }
  return result;
}

function environmentMode(value) {
  if (["test", "sandbox", "local"].includes(value)) return "test";
  if (value === "prod") return "production";
  fail(400, "commerce_environment_mismatch", "The commerce environment does not match.");
}

function valueId(value, prefix) {
  if (typeof value === "string") return providerId(value, prefix);
  if (value && typeof value === "object" && !Array.isArray(value)) return providerId(value.id, prefix);
  fail(400, "commerce_invalid_payload", "The commerce provider identifier is invalid.");
}

function dateSeconds(value) {
  if (value === undefined || value === null) return null;
  if (Number.isSafeInteger(value) && value >= 0) return value > 10_000_000_000 ? Math.floor(value / 1000) : value;
  if (typeof value === "string") {
    const millis = Date.parse(value);
    if (Number.isFinite(millis) && millis >= 0) return Math.floor(millis / 1000);
  }
  fail(400, "commerce_invalid_payload", "The commerce timestamp is invalid.");
}

async function boundedResponse(response) {
  const declared = Number(response.headers.get("content-length"));
  if (Number.isFinite(declared) && declared > MAX_RESPONSE_BYTES) {
    fail(502, "commerce_invalid_response", "The commerce provider response is invalid.");
  }
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes.byteLength === 0 || bytes.byteLength > MAX_RESPONSE_BYTES) {
    fail(502, "commerce_invalid_response", "The commerce provider response is invalid.");
  }
  try {
    return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch {
    fail(502, "commerce_invalid_response", "The commerce provider response is invalid.");
  }
}

export function trustedCreemUrl(value) {
  let url;
  try {
    url = new URL(value);
  } catch {
    fail(502, "commerce_invalid_response", "The commerce provider returned an invalid link.");
  }
  const host = url?.hostname ?? "";
  if (url.protocol !== "https:" || url.username || url.password || url.hash
    || (host !== "creem.io" && !host.endsWith(".creem.io"))) {
    fail(502, "commerce_invalid_response", "The commerce provider returned an invalid link.");
  }
  return url.toString();
}

export class CreemApi {
  constructor(config, apiKey, {
    fetchImpl = globalThis.fetch,
    setTimeoutImpl = globalThis.setTimeout,
    clearTimeoutImpl = globalThis.clearTimeout,
  } = {}) {
    this.config = config;
    this.apiKey = apiKey;
    this.fetchImpl = fetchImpl;
    this.setTimeoutImpl = setTimeoutImpl;
    this.clearTimeoutImpl = clearTimeoutImpl;
  }

  async createCheckout({ productId, requestId, customerId, metadata }) {
    return this.#request("v1/checkouts", {
      method: "POST",
      body: {
        request_id: requestId,
        product_id: productId,
        units: 1,
        success_url: this.config.commerce.successUrl,
        ...(customerId ? { customer: { id: customerId } } : {}),
        metadata,
      },
    }).then((value) => {
      this.#assertMode(value.mode);
      return Object.freeze({
        checkoutId: providerId(value.id, "ch_"),
        checkoutUrl: trustedCreemUrl(value.checkout_url),
      });
    });
  }

  async createCustomerPortal(customerId) {
    const value = await this.#request("v1/customers/billing", {
      method: "POST",
      body: { customer_id: providerId(customerId, "cust_") },
    });
    return Object.freeze({ portalUrl: trustedCreemUrl(value.customer_portal_link) });
  }

  async getSubscription(subscriptionId) {
    const query = new URLSearchParams({ subscription_id: providerId(subscriptionId, "sub_") });
    const value = await this.#request(`v1/subscriptions?${query}`, { method: "GET" });
    this.#assertMode(value.mode);
    return value;
  }

  async #request(path, { method, body }) {
    const base = this.config.commerce.environment === "test"
      ? "https://test-api.creem.io/"
      : "https://api.creem.io/";
    const url = new URL(path, base);
    const controller = new AbortController();
    const timeout = this.setTimeoutImpl(() => controller.abort("Creem timeout"), 15_000);
    timeout?.unref?.();
    let response;
    try {
      response = await this.fetchImpl(url, {
        method,
        redirect: "error",
        signal: controller.signal,
        headers: {
          accept: "application/json",
          "content-type": "application/json",
          "x-api-key": this.apiKey,
        },
        ...(body ? { body: JSON.stringify(body) } : {}),
      });
    } catch {
      fail(503, "commerce_provider_unavailable", "The commerce provider is temporarily unavailable.", {
        headers: { "retry-after": "30" },
      });
    } finally {
      this.clearTimeoutImpl(timeout);
    }
    if (response.redirected) fail(502, "commerce_invalid_response", "The commerce provider response is invalid.");
    if (response.status === 429 || response.status >= 500) {
      fail(503, "commerce_provider_unavailable", "The commerce provider is temporarily unavailable.", {
        headers: { "retry-after": response.headers.get("retry-after") ?? "30" },
      });
    }
    if (!response.ok) fail(502, "commerce_provider_rejected", "The commerce provider rejected the request.");
    return boundedResponse(response);
  }

  #assertMode(value) {
    if (environmentMode(value) !== this.config.commerce.environment) {
      fail(409, "commerce_environment_mismatch", "The commerce environment does not match.");
    }
  }
}

export async function verifyCreemWebhook(request, secret, cryptoImpl = globalThis.crypto) {
  const rawBody = await boundedRequestBody(request, MAX_WEBHOOK_BYTES);
  const presented = request.headers.get("creem-signature");
  if (!presented || !/^[a-fA-F0-9]{64}$/.test(presented)) {
    fail(401, "commerce_webhook_signature_invalid", "The webhook signature is invalid.");
  }
  const signature = Uint8Array.from(presented.match(/.{2}/g), (value) => Number.parseInt(value, 16));
  const valid = await cryptoImpl.subtle.verify(
    "HMAC",
    await hmacKey(secret, cryptoImpl),
    signature,
    rawBody,
  ).catch(() => false);
  if (!valid) fail(401, "commerce_webhook_signature_invalid", "The webhook signature is invalid.");
  let value;
  try {
    value = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(rawBody));
  } catch {
    fail(400, "commerce_invalid_payload", "The webhook payload is invalid.");
  }
  exactObject(value, ["id", "eventType", "created_at", "object"], "webhook");
  return { value, rawBody, bodyHash: await sha256Hex(rawBody, cryptoImpl) };
}

export async function normalizeCreemEvent(verified, config, store, cryptoImpl = globalThis.crypto) {
  const { value, rawBody, bodyHash } = verified;
  const eventId = providerId(value.id, "evt_");
  const eventType = text(value.eventType, "event type", 128);
  const providerCreatedAt = dateSeconds(value.created_at);
  const object = value.object;
  if (!object || typeof object !== "object" || Array.isArray(object)) {
    fail(400, "commerce_invalid_payload", "The webhook payload is invalid.");
  }
  const environment = environmentMode(object.mode);
  if (environment !== config.commerce.environment) {
    fail(409, "commerce_environment_mismatch", "The commerce environment does not match.");
  }
  const subscription = object.subscription && typeof object.subscription === "object"
    ? object.subscription
    : object;
  const subscriptionId = findSubscriptionId(object, subscription);
  const current = subscriptionId ? await store.subscriptionById(subscriptionId) : null;
  const customerId = findId(subscription.customer ?? object.customer ?? current?.customer_id, "cust_");
  const productId = findId(subscription.product ?? object.product ?? current?.product_id, "prod_");
  const metadata = metadataObject(subscription.metadata ?? object.metadata);
  const subjectRef = metadata?.agentweaveSubjectRef ?? current?.subject_ref ?? null;
  const requestedPlan = metadata?.agentweavePlanId ?? current?.plan_id ?? null;
  if (subjectRef !== null) text(subjectRef, "subject reference", 256);
  const mapping = productId
    ? config.policy.productPlans.find((plan) => plan.enabled && plan.productId === productId)
    : null;
  if (productId && !mapping) fail(403, "commerce_product_unmapped", "This product is not enabled for the App.");
  if (mapping && requestedPlan && mapping.id !== requestedPlan) {
    fail(409, "commerce_plan_mismatch", "The subscription plan does not match the configured product.");
  }
  if (eventType !== "checkout.completed" && (!subscriptionId || !customerId || !productId || !subjectRef || !mapping)) {
    fail(400, "commerce_invalid_payload", "The subscription event is missing a trusted binding.");
  }
  const status = normalizedStatus(eventType, subscription.status, current?.normalized_status);
  const providerUpdatedAt = dateSeconds(subscription.updated_at) ?? providerCreatedAt;
  const old = current && providerUpdatedAt < Number(current.provider_updated_at) && !REVOKE_EVENTS.has(eventType);
  const paidEvent = eventType === "subscription.paid" || status === "trialing";
  const periodStart = dateSeconds(subscription.current_period_start_date) ?? current?.current_period_start ?? null;
  const periodEnd = dateSeconds(subscription.current_period_end_date) ?? current?.current_period_end ?? null;
  let paidThrough = current?.paid_through ?? null;
  if (paidEvent) {
    if (!periodEnd || periodEnd <= providerUpdatedAt) {
      fail(400, "commerce_invalid_payload", "The paid subscription period is invalid.");
    }
    paidThrough = Math.max(Number(paidThrough ?? 0), periodEnd);
  }
  const revoked = REVOKE_EVENTS.has(eventType);
  const revokedAt = revoked ? providerCreatedAt : current?.revoked_at ?? null;
  const revision = await sha256Hex(new TextEncoder().encode([
    subscriptionId, eventId, eventType, providerUpdatedAt, paidThrough, revokedAt,
  ].join("\0")), cryptoImpl);
  const fact = eventType === "checkout.completed" || old ? null : {
    subscriptionId,
    customerId,
    productId,
    planId: mapping.id,
    status,
    periodStart,
    periodEnd,
    paidThrough,
    providerUpdatedAt,
    lastPaidTransactionId: subscription.last_transaction_id ?? current?.last_paid_transaction_id ?? null,
    revokedAt,
    revokeReason: revokeReason(eventType),
    revision,
  };
  return Object.freeze({
    eventId,
    eventType,
    bodyHash,
    providerCreatedAt,
    subjectRef,
    customerId,
    fact,
    outcome: old ? "ignored_old" : "applied",
    rawBytes: rawBody.byteLength,
  });
}

function findSubscriptionId(object, subscription) {
  const candidate = subscription?.id?.startsWith?.("sub_")
    ? subscription.id
    : typeof object.subscription === "string"
      ? object.subscription
      : object.subscription?.id;
  return candidate ? providerId(candidate, "sub_") : null;
}

function findId(value, prefix) {
  if (value === undefined || value === null) return null;
  return valueId(value, prefix);
}

function metadataObject(value) {
  if (value === undefined || value === null) return null;
  if (typeof value !== "object" || Array.isArray(value)) {
    fail(400, "commerce_invalid_payload", "The commerce metadata is invalid.");
  }
  return value;
}

function normalizedStatus(eventType, providerStatus, current) {
  const direct = {
    "subscription.trialing": "trialing",
    "subscription.scheduled_cancel": "scheduled_cancel",
    "subscription.past_due": "past_due",
    "subscription.paused": "paused",
    "subscription.canceled": "canceled",
    "subscription.expired": "expired",
    "subscription.unpaid": "unpaid",
    "refund.created": "refunded",
    "dispute.created": "disputed",
  }[eventType];
  if (direct) return direct;
  if (new Set(["subscription.active", "subscription.paid", "subscription.update"]).has(eventType)) {
    if (new Set(["trialing", "active", "scheduled_cancel", "past_due", "paused", "canceled", "expired", "unpaid"]).has(providerStatus)) {
      return providerStatus;
    }
  }
  if (eventType === "checkout.completed") return current ?? "active";
  fail(400, "commerce_event_unsupported", "The webhook event type is unsupported.");
}

function revokeReason(eventType) {
  if (eventType === "subscription.expired") return "expired";
  if (eventType === "subscription.unpaid") return "unpaid";
  if (eventType === "refund.created") return "refund";
  if (eventType === "dispute.created") return "dispute";
  return null;
}

export const creemInternals = Object.freeze({
  dateSeconds,
  environmentMode,
  normalizedStatus,
});
