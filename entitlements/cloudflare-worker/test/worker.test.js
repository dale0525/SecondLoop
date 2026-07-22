import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import { readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import test from "node:test";

import { parseEntitlementConfig } from "../src/config.js";
import { canonical, hmacKey } from "../src/crypto.js";
import { createEntitlementWorker, workerInternals } from "../src/index.js";
import { billingStatus, handleProjection, policyInternals } from "../src/policy.js";

const migration = ["0001_commerce.sql", "0002_portal_verification_nonce.sql"]
  .map((name) => readFileSync(new URL(`../migrations/${name}`, import.meta.url), "utf8"))
  .join("\n");
const NOW = 1_800_000_000;
const PROJECTION_SECRET = "projection-secret-with-at-least-32-bytes";
const WEBHOOK_SECRET = "webhook-secret-sentinel";
const SUBJECT_SECRET = "subject-binding-secret-sentinel";

class Statement {
  constructor(owner, sql) {
    this.owner = owner;
    this.sql = sql;
    this.values = [];
  }

  bind(...values) {
    this.values = values;
    return this;
  }

  async first() {
    return this.owner.database.prepare(this.sql).get(...this.values) ?? null;
  }

  async all() {
    return { results: this.owner.database.prepare(this.sql).all(...this.values) };
  }

  async run() {
    const result = this.owner.database.prepare(this.sql).run(...this.values);
    return { results: [], meta: { changes: Number(result.changes) } };
  }
}

class LocalD1 {
  constructor() {
    this.database = new DatabaseSync(":memory:");
    this.database.exec("PRAGMA foreign_keys = ON");
    this.database.exec(migration);
  }

  prepare(sql) {
    return new Statement(this, sql);
  }

  async batch(statements) {
    this.database.exec("BEGIN IMMEDIATE");
    try {
      const results = statements.map((statement) => {
        const result = this.database.prepare(statement.sql).run(...statement.values);
        return { results: [], meta: { changes: Number(result.changes) } };
      });
      this.database.exec("COMMIT");
      return results;
    } catch (error) {
      this.database.exec("ROLLBACK");
      throw error;
    }
  }
}

function identityProvider() {
  return {
    id: "oidc-test",
    kind: "oidc",
    issuer: "https://identity.example.test/",
    audience: "agentweave-test",
    jwksUrl: "https://identity.example.test/.well-known/jwks.json",
    algorithm: "RS256",
    header: "authorization",
    clockSkewSeconds: 0,
    projection: { tenantClaim: "org.id" },
  };
}

function commerceConfig() {
  return {
    schemaVersion: 1,
    environment: "production",
    appId: "com.example.agent",
    deploymentId: "deployment-test",
    configurationId: "configuration-test",
    auth: { mode: "required", providers: [identityProvider()] },
    policy: {
      sourceMode: "commerce_provider",
      tenantLimits: { maxRequests: 0, maxUnits: 0 },
      productPlans: [{
        id: "pro-monthly",
        displayName: "Pro monthly",
        productId: "prod_123",
        enabled: true,
        allowedModels: ["model-small"],
        limits: { maxRequests: 0, maxUnits: 100000, maxConcurrency: 0 },
      }],
    },
    commerce: {
      providerId: "agentweave.commerce.creem",
      environment: "test",
      successUrl: "https://example.test/billing/success",
    },
    bindings: { commerce: "COMMERCE" },
  };
}

function uniformConfig() {
  return {
    schemaVersion: 1,
    environment: "production",
    appId: "com.example.agent",
    deploymentId: "deployment-test",
    configurationId: "configuration-test",
    auth: { mode: "required", providers: [identityProvider()] },
    policy: {
      sourceMode: "uniform_bounded",
      tenantLimits: { maxRequests: 0, maxUnits: 0 },
      uniformPlan: {
        id: "uniform",
        displayName: "Included access",
        enabled: true,
        allowedModels: ["model-small"],
        limits: { maxRequests: 0, maxUnits: 100000, maxConcurrency: 0 },
      },
    },
    bindings: { commerce: "COMMERCE" },
  };
}

function webhookSetupConfig() {
  return {
    schemaVersion: 1,
    environment: "production",
    appId: "com.example.agent",
    deploymentId: "deployment-test",
    configurationId: "configuration-test",
    setup: {
      mode: "commerce_webhook",
      providerId: "agentweave.commerce.creem",
      environment: "test",
    },
  };
}

function environment(database, config = commerceConfig()) {
  return {
    ENTITLEMENT_CONFIG_JSON: JSON.stringify(config),
    ENTITLEMENT_PROJECTION_SECRET: PROJECTION_SECRET,
    CREEM_API_KEY: "creem-test-key-sentinel",
    CREEM_WEBHOOK_SECRET: WEBHOOK_SECRET,
    COMMERCE_SUBJECT_BINDING_SECRET: SUBJECT_SECRET,
    COMMERCE: database,
  };
}

const identity = Object.freeze({
  providerId: "oidc-test",
  issuer: "https://identity.example.test/",
  tenant: "tenant-7",
  subject: "user-123",
});

function authenticatorFactory() {
  return { async authenticate() { return identity; } };
}

async function projectionRequest(
  model = "model-small",
  secret = PROJECTION_SECRET,
  sourceId = "agentweave.entitlements.cloudflare_policy",
) {
  const body = new TextEncoder().encode(JSON.stringify({
    schemaVersion: 2,
    sourceId,
    nonce: "00000000-0000-4000-8000-000000000001",
    deploymentId: "deployment-test",
    providerId: identity.providerId,
    issuer: identity.issuer,
    tenant: identity.tenant,
    subject: identity.subject,
    model,
    requestedAt: NOW,
  }));
  const signature = await webcrypto.subtle.sign(
    "HMAC",
    await hmacKey(secret, webcrypto),
    canonical(policyInternals.REQUEST_DOMAIN_V2, [String(NOW), "00000000-0000-4000-8000-000000000001"], body),
  );
  return new Request("https://entitlements.example.test/agentweave/entitlements/projection", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-agentweave-entitlement-timestamp": String(NOW),
      "x-agentweave-entitlement-nonce": "00000000-0000-4000-8000-000000000001",
      "x-agentweave-entitlement-signature": `v2=${Buffer.from(signature).toString("base64url")}`,
    },
    body,
  });
}

async function reconcileRequest(secret) {
  const timestamp = String(NOW);
  const body = new TextEncoder().encode(JSON.stringify({ subscriptionId: "sub_123" }));
  const signature = await webcrypto.subtle.sign(
    "HMAC",
    await hmacKey(secret, webcrypto),
    canonical(workerInternals.RECONCILE_DOMAIN, [timestamp], body),
  );
  return new Request("https://entitlements.example.test/agentweave/commerce/v1/reconcile", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-agentweave-reconcile-timestamp": timestamp,
      "x-agentweave-reconcile-signature": `v1=${Buffer.from(signature).toString("base64url")}`,
    },
    body,
  });
}

async function signedWebhook(value) {
  const body = new TextEncoder().encode(JSON.stringify(value));
  const signature = await webcrypto.subtle.sign(
    "HMAC",
    await hmacKey(WEBHOOK_SECRET, webcrypto),
    body,
  );
  return new Request("https://entitlements.example.test/agentweave/commerce/v1/webhooks/creem", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "creem-signature": Buffer.from(signature).toString("hex"),
    },
    body,
  });
}

function userRequest(path, body, method = "POST") {
  return new Request(`https://entitlements.example.test${path}`, {
    method,
    headers: { authorization: "Bearer identity-token", "content-type": "application/json" },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
}

test("configuration preserves explicit unlimited limits and requires subscription mappings", () => {
  const parsed = parseEntitlementConfig(commerceConfig());
  assert.equal(parsed.policy.productPlans[0].limits.maxRequests, 0);
  assert.equal(parsed.policy.productPlans[0].limits.maxConcurrency, 0);
  assert.throws(() => parseEntitlementConfig({
    ...commerceConfig(),
    policy: { ...commerceConfig().policy, productPlans: [] },
  }));
});

test("health binds the deployment and immutable Worker version", async () => {
  const worker = createEntitlementWorker();
  const response = await worker.fetch(new Request("https://entitlement.example/healthz"), {
    ENTITLEMENT_CONFIG_JSON: JSON.stringify(uniformConfig()),
    ENTITLEMENT_PROJECTION_SECRET: "projection-secret-that-is-at-least-32-bytes",
    CF_VERSION_METADATA: { id: "worker-version-7" },
  });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    status: "ready",
    service: "entitlement-policy",
    schema_version: 1,
    protocol_version: "2",
    deployment_id: "deployment-test",
    remote_version: "worker-version-7",
  });
});

test("webhook bootstrap publishes the route without activating Commerce", async () => {
  const parsed = parseEntitlementConfig(webhookSetupConfig());
  assert.equal(parsed.setup.mode, "commerce_webhook");
  assert.equal(parsed.policy, null);
  const worker = createEntitlementWorker();
  const env = {
    ENTITLEMENT_CONFIG_JSON: JSON.stringify(webhookSetupConfig()),
    CF_VERSION_METADATA: { id: "worker-version-setup" },
  };
  const health = await worker.fetch(new Request("https://entitlement.example/healthz"), env);
  assert.equal(health.status, 200);
  assert.equal((await health.json()).status, "setup_required");
  const webhook = await worker.fetch(new Request(
    "https://entitlement.example/agentweave/commerce/v1/webhooks/creem",
    { method: "POST" },
  ), env);
  assert.equal(webhook.status, 503);
  assert.equal((await webhook.json()).error.code, "commerce_setup_required");
  const projection = await worker.fetch(new Request(
    "https://entitlement.example/agentweave/entitlements/projection",
    { method: "POST" },
  ), env);
  assert.equal(projection.status, 503);
  assert.equal((await projection.json()).error.code, "entitlement_setup_required");
});

test("webhook bootstrap rejects unsupported Commerce providers", () => {
  const config = webhookSetupConfig();
  config.setup.providerId = "agentweave.commerce.other";
  assert.throws(
    () => parseEntitlementConfig(config),
    (error) => error?.code === "entitlement_misconfigured",
  );
});

test("uniform policy returns a signed v2 projection with explicit unlimited fields", async () => {
  const worker = createEntitlementWorker({ cryptoImpl: webcrypto, nowSeconds: () => NOW });
  const response = await worker.fetch(
    await projectionRequest(),
    environment(null, uniformConfig()),
  );
  assert.equal(response.status, 200);
  assert.match(response.headers.get("x-agentweave-entitlement-signature"), /^v2=/);
  const projection = await response.json();
  assert.equal(projection.decision, "allow");
  assert.deepEqual(projection.tenantBudget.requests, { mode: "unlimited" });
  assert.deepEqual(projection.subjectBudget.concurrency, { mode: "unlimited" });
});

test("projection rotation accepts current and next secrets and signs with the matched secret", async () => {
  const nextSecret = "next-projection-secret-with-at-least-32-bytes";
  const worker = createEntitlementWorker({ cryptoImpl: webcrypto, nowSeconds: () => NOW });
  const env = {
    ...environment(null, uniformConfig()),
    ENTITLEMENT_PROJECTION_SECRET_NEXT: nextSecret,
  };
  for (const secret of [PROJECTION_SECRET, nextSecret]) {
    const response = await worker.fetch(await projectionRequest("model-small", secret), env);
    assert.equal(response.status, 200);
    const responseBody = new Uint8Array(await response.arrayBuffer());
    const signature = response.headers.get("x-agentweave-entitlement-signature");
    const valid = await webcrypto.subtle.verify(
      "HMAC",
      await hmacKey(secret, webcrypto),
      Buffer.from(signature.slice(3), "base64url"),
      canonical(
        policyInternals.RESPONSE_DOMAIN_V2,
        ["00000000-0000-4000-8000-000000000001"],
        responseBody,
      ),
    );
    assert.equal(valid, true);
  }
});

test("targeted reconciliation accepts both projection secrets during rotation", async () => {
  const nextSecret = "next-projection-secret-with-at-least-32-bytes";
  let providerCalls = 0;
  const worker = createEntitlementWorker({
    cryptoImpl: webcrypto,
    nowSeconds: () => NOW,
    fetchImpl: async () => {
      providerCalls += 1;
      return Response.json({ mode: "test" });
    },
  });
  const env = {
    ...environment(new LocalD1()),
    ENTITLEMENT_PROJECTION_SECRET_NEXT: nextSecret,
  };
  for (const secret of [PROJECTION_SECRET, nextSecret]) {
    const response = await worker.fetch(await reconcileRequest(secret), env);
    assert.equal(response.status, 400);
  }
  const rejected = await worker.fetch(
    await reconcileRequest("unrecognized-projection-secret-with-32-bytes"),
    env,
  );
  assert.equal(rejected.status, 401);
  assert.equal(providerCalls, 2);
});

test("the unique eligible subscription wins when a newer inactive row sorts first", async () => {
  const inactive = {
    subscription_id: "sub_expired",
    normalized_status: "expired",
    plan_id: "pro-monthly",
    product_id: "prod_123",
    current_period_start: NOW - 7200,
    current_period_end: NOW - 3600,
    paid_through: NOW - 3600,
    provider_updated_at: NOW - 10,
    revoked_at: null,
    projection_revision: "expired-revision",
  };
  const active = {
    subscription_id: "sub_active",
    normalized_status: "active",
    plan_id: "pro-monthly",
    product_id: "prod_123",
    current_period_start: NOW - 3600,
    current_period_end: NOW + 3600,
    paid_through: NOW + 3600,
    provider_updated_at: NOW - 100,
    revoked_at: null,
    projection_revision: "active-revision",
  };
  const store = {
    subscriptionForSubject: async () => [inactive, active],
    customerForSubject: async () => ({ customer_id: "cust_123" }),
  };
  const env = environment(null);

  const response = await handleProjection(
    await projectionRequest("model-small", PROJECTION_SECRET, "agentweave.commerce.creem"),
    commerceConfig(),
    store,
    env,
    { cryptoImpl: webcrypto, nowSeconds: () => NOW },
  );
  assert.equal(response.status, 200);
  assert.deepEqual(
    { decision: (await response.json()).decision, selected: policyInternals.selectSubscription([inactive, active], NOW).subscription.subscription_id },
    { decision: "allow", selected: "sub_active" },
  );

  const status = await billingStatus(
    commerceConfig(),
    store,
    identity,
    env,
    { cryptoImpl: webcrypto, nowSeconds: () => NOW },
  );
  assert.equal(status.plan.id, "pro-monthly");
  assert.equal(status.subscription.status, "active");

  const mismatched = await billingStatus(
    {
      ...commerceConfig(),
      policy: {
        ...commerceConfig().policy,
        productPlans: [{
          ...commerceConfig().policy.productPlans[0],
          productId: "prod_other",
        }],
      },
    },
    store,
    identity,
    env,
    { cryptoImpl: webcrypto, nowSeconds: () => NOW },
  );
  assert.equal(mismatched.plan, null);
});

test("scheduled reconciliation bounds parallel Creem requests", async () => {
  let active = 0;
  let maximum = 0;
  const completed = [];
  const failures = [];
  await workerInternals.allSettledInBatches(
    Array.from({ length: 11 }, (_, index) => index),
    async (index) => {
      active += 1;
      maximum = Math.max(maximum, active);
      try {
        await new Promise((resolve) => setImmediate(resolve));
        if (index === 5) throw new Error("provider unavailable");
        completed.push(index);
      } finally {
        active -= 1;
      }
    },
    4,
    (index, error) => failures.push({ index, message: error.message }),
  );
  assert.equal(maximum, 4);
  assert.deepEqual(completed.sort((left, right) => left - right), [0, 1, 2, 3, 4, 6, 7, 8, 9, 10]);
  assert.deepEqual(failures, [{ index: 5, message: "provider unavailable" }]);
});

test("checkout binds a verified subject and customer portal never accepts a client customer id", async () => {
  const database = new LocalD1();
  const calls = [];
  const worker = createEntitlementWorker({
    cryptoImpl: webcrypto,
    nowSeconds: () => NOW,
    authenticatorFactory,
    fetchImpl: async (url, init) => {
      calls.push({ url: url.toString(), init });
      if (url.pathname === "/v1/checkouts") {
        return Response.json({
          id: "ch_123", mode: "test", checkout_url: "https://checkout.creem.io/ch_123",
        });
      }
      if (url.pathname === "/v1/customers/billing") {
        return Response.json({ customer_portal_link: "https://app.creem.io/customer/token" });
      }
      throw new Error("unexpected Creem request");
    },
  });
  const env = environment(database);
  const checkout = await worker.fetch(userRequest("/agentweave/commerce/v1/checkout", {
    planId: "pro-monthly",
    requestId: "request_0000000000000001",
    requestNonce: "nonce_0000000000000001",
  }), env);
  assert.equal(checkout.status, 201);
  const checkoutBody = JSON.parse(calls[0].init.body);
  assert.equal(checkoutBody.product_id, "prod_123");
  assert.equal(checkoutBody.metadata.agentweavePlanId, "pro-monthly");
  assert.equal(checkoutBody.customer, undefined);

  const binding = await worker.fetch(await signedWebhook({
    id: "evt_checkout_1",
    eventType: "checkout.completed",
    created_at: NOW * 1000,
    object: {
      id: "ch_123", mode: "test", customer: "cust_123", product: "prod_123",
      metadata: checkoutBody.metadata,
    },
  }), env);
  assert.equal(binding.status, 200);

  const portal = await worker.fetch(userRequest("/agentweave/commerce/v1/customer-portal", {
    requestNonce: "nonce_0000000000000002",
  }), env);
  assert.equal(portal.status, 200);
  assert.equal((await portal.json()).portalUrl, "https://app.creem.io/customer/token");
  assert.deepEqual(JSON.parse(calls[1].init.body), { customer_id: "cust_123" });
  assert.equal(database.database.prepare(`
    SELECT COUNT(*) AS count FROM commerce_events
    WHERE body_hash LIKE '%app.creem.io%'
  `).get().count, 0);
  assert.equal(database.database.prepare(`
    SELECT COUNT(*) AS count FROM commerce_verifications
    WHERE capability = 'customer_portal_v1'
  `).get().count, 0);

  const portalVerified = await worker.fetch(userRequest(
    "/agentweave/commerce/v1/customer-portal/verified",
    { requestNonce: "nonce_0000000000000002" },
  ), env);
  assert.equal(portalVerified.status, 200);
  assert.deepEqual(await portalVerified.json(), { verified: true });
  assert.equal(database.database.prepare(`
    SELECT COUNT(*) AS count FROM commerce_verifications
    WHERE capability = 'customer_portal_v1'
  `).get().count, 1);

  const injected = await worker.fetch(userRequest("/agentweave/commerce/v1/customer-portal", {
    requestNonce: "nonce_0000000000000003",
    customerId: "cust_attacker",
  }), env);
  assert.equal(injected.status, 400);
});

test("paid, scheduled cancellation, and refund converge to paid-through semantics", async () => {
  const database = new LocalD1();
  const worker = createEntitlementWorker({
    cryptoImpl: webcrypto,
    nowSeconds: () => NOW,
    authenticatorFactory,
    fetchImpl: async () => { throw new Error("Creem API should not be called"); },
  });
  const env = environment(database);
  const metadata = {
    agentweaveAppId: "com.example.agent",
    agentweaveSubjectRef: "v1_subject_ref",
    agentweavePlanId: "pro-monthly",
  };
  await worker.fetch(await signedWebhook({
    id: "evt_checkout_2", eventType: "checkout.completed", created_at: (NOW - 30) * 1000,
    object: { id: "ch_2", mode: "test", customer: "cust_123", product: "prod_123", metadata },
  }), env);
  const paid = await worker.fetch(await signedWebhook({
    id: "evt_paid_1", eventType: "subscription.paid", created_at: (NOW - 20) * 1000,
    object: {
      id: "sub_123", mode: "test", status: "active", customer: "cust_123", product: "prod_123",
      current_period_start_date: new Date((NOW - 60) * 1000).toISOString(),
      current_period_end_date: new Date((NOW + 3600) * 1000).toISOString(),
      updated_at: new Date((NOW - 20) * 1000).toISOString(), metadata,
    },
  }), env);
  assert.equal(paid.status, 200);
  const rowAfterPaid = database.database.prepare(`
    SELECT normalized_status, paid_through, revoked_at FROM commerce_subscriptions
  `).get();
  assert.deepEqual({ ...rowAfterPaid }, { normalized_status: "active", paid_through: NOW + 3600, revoked_at: null });

  await worker.fetch(await signedWebhook({
    id: "evt_cancel_1", eventType: "subscription.scheduled_cancel", created_at: (NOW - 10) * 1000,
    object: {
      id: "sub_123", mode: "test", status: "scheduled_cancel", customer: "cust_123", product: "prod_123",
      current_period_start_date: new Date((NOW - 60) * 1000).toISOString(),
      current_period_end_date: new Date((NOW + 3600) * 1000).toISOString(),
      updated_at: new Date((NOW - 10) * 1000).toISOString(), metadata,
    },
  }), env);
  const canceled = database.database.prepare(`
    SELECT normalized_status, paid_through, revoked_at FROM commerce_subscriptions
  `).get();
  assert.deepEqual({ ...canceled }, { normalized_status: "scheduled_cancel", paid_through: NOW + 3600, revoked_at: null });

  await worker.fetch(await signedWebhook({
    id: "evt_refund_1", eventType: "refund.created", created_at: NOW * 1000,
    object: { id: "tran_123", mode: "test", subscription: "sub_123" },
  }), env);
  const refunded = database.database.prepare(`
    SELECT normalized_status, paid_through, revoked_at FROM commerce_subscriptions
  `).get();
  assert.deepEqual({ ...refunded }, { normalized_status: "refunded", paid_through: NOW + 3600, revoked_at: NOW });
  const revocation = database.database.prepare("SELECT reason FROM commerce_revocations").get();
  assert.equal(revocation.reason, "refund");
});
