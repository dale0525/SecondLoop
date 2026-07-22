import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import test from "node:test";

import { parseGatewayConfig, validateRuntimeBindings } from "../src/config.js";
import { GatewayError } from "../src/errors.js";
import { EntitlementProjectionResolver, projectionInternals } from "../src/projection.js";
import { gatewayConfig, NOW_SECONDS } from "./fixtures.js";

const SECRET = "projection-secret-with-at-least-32-bytes";
const identity = Object.freeze({
  providerId: "oidc-test",
  issuer: "https://identity.example.test/",
  tenant: "tenant-7",
  subject: "user-123",
});

class FakeStatement {
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
    this.owner.reads.push({ sql: this.sql, values: this.values });
    return this.owner.states.shift();
  }
}

class FakeD1 {
  constructor(states) {
    this.states = [...states];
    this.reads = [];
    this.batches = [];
  }

  prepare(sql) {
    return new FakeStatement(this, sql);
  }

  async batch(statements) {
    this.batches.push(statements.map((statement) => ({
      sql: statement.sql,
      values: statement.values,
    })));
    return statements.map(() => ({ results: [], meta: { changes: 1 } }));
  }
}

function state({ fresh = false, allowed = true } = {}) {
  return {
    tenant_rows: fresh ? 1 : 0,
    tenant_active: fresh ? 1 : 0,
    subject_rows: fresh ? 1 : 0,
    subject_active: fresh ? 1 : 0,
    model_rows: fresh ? 1 : 0,
    model_active: fresh && allowed ? 1 : 0,
  };
}

function config(schemaVersion = 1) {
  return parseGatewayConfig(gatewayConfig({
    entitlements: {
      mode: "signed_http",
      projection: {
        schemaVersion,
        sourceId: "developer-backend-v1",
        url: "https://entitlements.example.test/v1/projection",
        secretBinding: "ENTITLEMENT_PROJECTION_SECRET",
        timeoutMilliseconds: 1000,
        maxResponseBytes: 8192,
        refreshBeforeSeconds: 30,
        maxClockSkewSeconds: 60,
      },
    },
  }));
}

function environment(database, overrides = {}) {
  return {
    ENTITLEMENTS: database,
    ENTITLEMENT_PROJECTION_SECRET: SECRET,
    ...overrides,
  };
}

function concat(...values) {
  const result = new Uint8Array(values.reduce((sum, value) => sum + value.byteLength, 0));
  let offset = 0;
  for (const value of values) {
    result.set(value, offset);
    offset += value.byteLength;
  }
  return result;
}

function canonical(domain, fields, body) {
  return concat(new TextEncoder().encode(`${domain}\n${fields.join("\n")}\n`), body);
}

async function hmacKey(secret = SECRET) {
  return webcrypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}

async function signedResponse(request, { decision = "allow", secret = SECRET, mutate } = {}) {
  const value = {
    schemaVersion: request.schemaVersion,
    sourceId: request.sourceId,
    projectionId: "projection-42",
    revision: "revision-7",
    nonce: request.nonce,
    deploymentId: request.deploymentId,
    providerId: request.providerId,
    issuer: request.issuer,
    tenant: request.tenant,
    subject: request.subject,
    model: request.model,
    issuedAt: NOW_SECONDS,
    expiresAt: NOW_SECONDS + 300,
    decision,
    reasonCode: decision === "allow" ? null : "subscription_required",
    tenantBudget: request.schemaVersion === 2 ? {
      periodStart: NOW_SECONDS - 60,
      periodEnd: NOW_SECONDS + 3600,
      requests: { mode: "unlimited" },
      units: { mode: "limited", value: 1_000_000 },
    } : {
      periodStart: NOW_SECONDS - 60,
      periodEnd: NOW_SECONDS + 3600,
      maxRequests: 1000,
      maxUnits: 1_000_000,
    },
    subjectBudget: request.schemaVersion === 2 ? {
      periodStart: NOW_SECONDS - 60,
      periodEnd: NOW_SECONDS + 3600,
      requests: { mode: "limited", value: 100 },
      units: { mode: "unlimited" },
      concurrency: { mode: "unlimited" },
    } : {
      periodStart: NOW_SECONDS - 60,
      periodEnd: NOW_SECONDS + 3600,
      maxRequests: 100,
      maxUnits: 100_000,
      maxConcurrency: 2,
    },
  };
  mutate?.(value);
  const body = new TextEncoder().encode(JSON.stringify(value));
  const signature = await webcrypto.subtle.sign(
    "HMAC",
    await hmacKey(secret),
    canonical(
      request.schemaVersion === 2
        ? projectionInternals.RESPONSE_DOMAIN_V2
        : projectionInternals.RESPONSE_DOMAIN,
      [request.nonce],
      body,
    ),
  );
  return new Response(body, {
    status: 200,
    headers: {
      "content-type": "application/json",
      [projectionInternals.SIGNATURE_HEADER]: `v${request.schemaVersion}=${Buffer.from(signature).toString("base64url")}`,
    },
  });
}

function resolver(database, fetchImpl, schemaVersion = 1) {
  return new EntitlementProjectionResolver(config(schemaVersion), environment(database), {
    fetchImpl,
    cryptoImpl: webcrypto,
    nowMilliseconds: () => NOW_SECONDS * 1000,
  });
}

test("signed HTTP projection is identity-bound, HMAC verified, and atomically written to D1", async () => {
  const database = new FakeD1([state(), state({ fresh: true })]);
  let captured;
  const target = resolver(database, async (url, init) => {
    captured = { url, init };
    const request = JSON.parse(new TextDecoder().decode(init.body));
    return signedResponse(request);
  });

  await target.ensure(identity, { model: "model-small" });
  assert.equal(captured.url, "https://entitlements.example.test/v1/projection");
  assert.equal(captured.init.redirect, "error");
  const request = JSON.parse(new TextDecoder().decode(captured.init.body));
  assert.deepEqual({
    deploymentId: request.deploymentId,
    providerId: request.providerId,
    issuer: request.issuer,
    tenant: request.tenant,
    subject: request.subject,
    model: request.model,
  }, {
    deploymentId: "deployment-test",
    ...identity,
    model: "model-small",
  });
  const requestSignature = captured.init.headers[projectionInternals.SIGNATURE_HEADER].slice(3);
  const requestValid = await webcrypto.subtle.verify(
    "HMAC",
    await hmacKey(),
    Buffer.from(requestSignature, "base64url"),
    canonical(
      projectionInternals.REQUEST_DOMAIN,
      [String(NOW_SECONDS), request.nonce],
      captured.init.body,
    ),
  );
  assert.equal(requestValid, true);
  assert.equal(database.batches.length, 1);
  assert.equal(database.batches[0].length, 6);
  assert.match(database.batches[0][3].sql, /gateway_tenant_budgets/);
  assert.match(database.batches[0][4].sql, /gateway_entitlements/);
  assert.match(database.batches[0][5].sql, /gateway_entitlement_models/);
  assert.doesNotMatch(JSON.stringify({ request, batches: database.batches }), new RegExp(SECRET));
});

test("a fresh signed projection avoids the remote resolver", async () => {
  const database = new FakeD1([state({ fresh: true })]);
  const target = resolver(database, async () => {
    throw new Error("resolver must not be called");
  });
  await target.ensure(identity, { model: "model-small" });
  assert.equal(database.batches.length, 0);
  assert.equal(database.reads.length, 1);
});

test("projection v2 stores explicit unlimited flags without magic numeric budgets", async () => {
  const database = new FakeD1([state(), state({ fresh: true })]);
  let captured;
  const target = resolver(database, async (url, init) => {
    captured = init;
    return signedResponse(JSON.parse(new TextDecoder().decode(init.body)));
  }, 2);
  await target.ensure(identity, { model: "model-small" });
  const request = JSON.parse(new TextDecoder().decode(captured.body));
  assert.equal(request.schemaVersion, 2);
  assert.equal(captured.headers["x-agentweave-entitlement-version"], "2");
  assert.match(captured.headers[projectionInternals.SIGNATURE_HEADER], /^v2=/);
  const tenantValues = database.batches[0][3].values;
  const subjectValues = database.batches[0][4].values;
  assert.deepEqual(tenantValues.slice(6, 10), [0, 1_000_000, 1, 0]);
  assert.deepEqual(subjectValues.slice(7, 13), [100, 0, 1000, 0, 1, 1]);
});

test("invalid signatures, stale bindings, and resolver failures fail closed without D1 writes", async () => {
  const cases = [
    async (request) => signedResponse(request, { secret: "wrong-secret-with-at-least-32-bytes" }),
    async (request) => signedResponse(request, {
      mutate(value) { value.subject = "another-user"; },
    }),
    async () => { throw new Error("timeout or connection failure"); },
  ];
  for (const fetchImpl of cases) {
    const database = new FakeD1([state()]);
    const target = resolver(database, async (url, init) => {
      const request = JSON.parse(new TextDecoder().decode(init.body));
      return fetchImpl(request, url, init);
    });
    await assert.rejects(
      target.ensure(identity, { model: "model-small" }),
      (error) => error instanceof GatewayError
        && error.code === "entitlement_projection_unavailable",
    );
    assert.equal(database.batches.length, 0);
  }
});

test("a signed deny is cached as a model policy and blocks before D1 reservation", async () => {
  const database = new FakeD1([state(), state({ fresh: true, allowed: false })]);
  const target = resolver(database, async (url, init) => {
    const request = JSON.parse(new TextDecoder().decode(init.body));
    return signedResponse(request, { decision: "deny" });
  });
  await assert.rejects(
    target.ensure(identity, { model: "model-large" }),
    (error) => error instanceof GatewayError && error.code === "entitlement_denied",
  );
  assert.equal(database.batches.length, 1);
  const modelValues = database.batches[0][5].values;
  assert.ok(modelValues.includes("denied"));
  assert.ok(modelValues.includes("subscription_required"));
});

test("signed projection configuration requires an exact HTTPS resolver and a server secret", () => {
  const parsed = config();
  assert.equal(parsed.entitlements.policySource, "developer-backend-v1");
  assert.throws(() => validateRuntimeBindings(parsed, {
    ENTITLEMENTS: {},
    CONCURRENCY: {},
    UPSTREAM_API_KEY: "model-secret",
    GATEWAY_EDGE_RATE_LIMITER: {},
    GATEWAY_DEPLOYMENT_RATE_LIMITER: {},
    GATEWAY_TENANT_RATE_LIMITER: {},
    GATEWAY_RATE_LIMITER: {},
    GATEWAY_DEVICE_RATE_LIMITER: {},
  }));
  assert.throws(() => parseGatewayConfig(gatewayConfig({
    entitlements: {
      mode: "signed_http",
      projection: {
        sourceId: "developer-backend-v1",
        url: "http://entitlements.example.test/projection",
      },
    },
  })));
});
