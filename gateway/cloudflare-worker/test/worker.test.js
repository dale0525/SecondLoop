import assert from "node:assert/strict";
import test from "node:test";

import { createGateway } from "../src/index.js";
import { fakeCrypto, gatewayConfig, runtimeEnv } from "./fixtures.js";

const identity = Object.freeze({
  providerId: "oidc-test",
  kind: "oidc",
  issuer: "https://identity.example.test/",
  subject: "user-123",
  tenant: "tenant-7",
  device: "device-9",
  deviceVerified: true,
  roles: Object.freeze([]),
});

function context() {
  return {
    promises: [],
    waitUntil(promise) {
      this.promises.push(promise);
    },
    async drain() {
      await Promise.all(this.promises);
    },
  };
}

function modelRequest(body = {}) {
  return new Request("https://gateway.example.test/v1/responses", {
    method: "POST",
    headers: {
      accept: "text/event-stream",
      authorization: "Bearer private-user-token",
      "content-type": "application/json",
      "x-agentweave-request-id": "request_000000000001",
    },
    body: JSON.stringify({
      model: "model-small",
      input: [{ role: "user", content: "VERY_PRIVATE_PROMPT" }],
      max_output_tokens: 50,
      tools: [],
      stream: true,
      ...body,
    }),
  });
}

function dependencies(fetchImpl, logs = [], gatewayOptions = {}, fixtureOptions = {}) {
  const settlements = [];
  const quotaCalls = [];
  const entitlements = {
    async assertDeploymentEnabled() {},
    async reserve(receivedIdentity, request) {
      assert.deepEqual(receivedIdentity, identity);
      return Object.freeze({
        reservationId: "reservation-1",
        identity: Object.freeze({
          providerId: identity.providerId,
          issuer: identity.issuer,
          tenant: identity.tenant,
          subject: identity.subject,
          device: identity.device,
          deviceVerified: identity.deviceVerified,
        }),
        model: request.model,
        reservedUnits: request.units,
        maxConcurrency: 2,
        expiresAt: fixtureOptions.reservationExpiresAt ?? 1_800_000_120,
        dispatched: false,
      });
    },
    async markDispatched(reservation) {
      return Object.freeze({ ...reservation, dispatched: true });
    },
    async settle(reservation, settlement) {
      settlements.push({ reservation, settlement });
      return fixtureOptions.settlementResult ?? { applied: true };
    },
  };
  const quota = {
    async checkIdentityRate(receivedIdentity) {
      quotaCalls.push({ type: "rate", identity: receivedIdentity });
    },
    async acquireConcurrency(receivedIdentity, limit) {
      quotaCalls.push({ type: "acquire", identity: receivedIdentity, limit });
      return {
        key: "hashed-key",
        leaseId: "lease-1",
        expiresAt: fixtureOptions.leaseExpiresAt ?? 1_800_000_120_000,
      };
    },
    async releaseConcurrency(lease) {
      quotaCalls.push({ type: "release", lease });
      return true;
    },
  };
  return {
    gateway: createGateway({
      fetchImpl,
      cryptoImpl: fakeCrypto(),
      nowMilliseconds: () => 1_800_000_000_000,
      logger: {
        info(event) { logs.push(event); },
        error(event) { logs.push(event); },
      },
      authenticatorFactory: () => ({ async authenticate() { return identity; } }),
      entitlementStoreFactory: () => entitlements,
      quotaCoordinatorFactory: () => quota,
      ...gatewayOptions,
    }),
    quotaCalls,
    settlements,
  };
}

test("Worker streams SSE without buffering and holds quota until the stream ends", async () => {
  let upstreamController;
  const upstreamCalls = [];
  const logs = [];
  const fetchImpl = async (url, init) => {
    upstreamCalls.push({ url, init });
    return new Response(new ReadableStream({
      start(controller) {
        upstreamController = controller;
        controller.enqueue(new TextEncoder().encode("data: first\n\n"));
      },
    }), {
      headers: { "content-type": "text/event-stream", "set-cookie": "never-forward=this" },
    });
  };
  const { gateway, quotaCalls, settlements } = dependencies(fetchImpl, logs);
  const execution = context();
  const config = gatewayConfig();
  const response = await gateway.fetch(modelRequest(), runtimeEnv(config), execution);

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("content-type"), "text/event-stream");
  assert.equal(response.headers.get("set-cookie"), null);
  assert.equal(settlements[0].settlement.outcome, "completed");
  assert.ok(settlements[0].settlement.actualUnits > 50);
  assert.equal(quotaCalls.filter((call) => call.type === "release").length, 0);

  const upstream = upstreamCalls[0];
  assert.equal(upstream.url, "https://models.example.test/v1/responses");
  assert.equal(upstream.init.redirect, "manual");
  assert.equal(upstream.init.headers.get("authorization"), "Bearer server-side-secret");
  assert.notEqual(upstream.init.headers.get("authorization"), "Bearer private-user-token");
  assert.equal(upstream.init.headers.get("x-agentweave-request-id"), null);
  const forwarded = JSON.parse(new TextDecoder().decode(upstream.init.body));
  assert.deepEqual(forwarded.input, [{ role: "user", content: "VERY_PRIVATE_PROMPT" }]);
  assert.equal(forwarded.max_output_tokens, 50);

  const reader = response.body.getReader();
  const first = await reader.read();
  assert.equal(new TextDecoder().decode(first.value), "data: first\n\n");
  assert.equal(settlements.length, 1, "D1 is committed once before SSE is exposed");
  upstreamController.enqueue(new TextEncoder().encode("data: [DONE]\n\n"));
  upstreamController.close();
  const second = await reader.read();
  assert.equal(new TextDecoder().decode(second.value), "data: [DONE]\n\n");
  assert.equal((await reader.read()).done, true);
  await execution.drain();

  assert.equal(settlements.length, 1);
  assert.equal(quotaCalls.at(-1).type, "release");
  const logWire = JSON.stringify(logs);
  assert.doesNotMatch(logWire, /VERY_PRIVATE_PROMPT|private-user-token|server-side-secret|user-123/);
  assert.match(logWire, /gateway.request_completed/);
});

test("upstream errors are redacted, release reservations, and never log bodies", async () => {
  const logs = [];
  const fetchImpl = async () => new Response(JSON.stringify({
    internal_error: "UPSTREAM_PRIVATE_DIAGNOSTIC",
  }), {
    status: 401,
    headers: { "content-type": "application/json" },
  });
  const { gateway, quotaCalls, settlements } = dependencies(fetchImpl, logs);
  const response = await gateway.fetch(modelRequest(), runtimeEnv(gatewayConfig()), context());
  assert.equal(response.status, 502);
  const body = await response.text();
  assert.match(body, /upstream_rejected/);
  assert.doesNotMatch(body, /UPSTREAM_PRIVATE_DIAGNOSTIC|VERY_PRIVATE_PROMPT|server-side-secret/);
  assert.deepEqual(settlements[0].settlement, { outcome: "rejected", actualUnits: 0 });
  assert.equal(quotaCalls.at(-1).type, "release");
  assert.doesNotMatch(
    JSON.stringify(logs),
    /UPSTREAM_PRIVATE_DIAGNOSTIC|VERY_PRIVATE_PROMPT|private-user-token|server-side-secret|user-123/,
  );
});

test("an unknown upstream transport result is conservatively charged as uncertain", async () => {
  const { gateway, settlements, quotaCalls } = dependencies(async () => {
    throw new Error("network result unknown");
  });
  const response = await gateway.fetch(
    modelRequest(),
    runtimeEnv(gatewayConfig()),
    context(),
  );
  assert.equal(response.status, 502);
  assert.match(await response.text(), /upstream_unavailable/);
  assert.equal(settlements.length, 1);
  assert.equal(settlements[0].settlement.outcome, "uncertain");
  assert.equal(settlements[0].settlement.actualUnits, settlements[0].reservation.reservedUnits);
  assert.equal(quotaCalls.at(-1).type, "release");
});

test("upstream 5xx and timeout responses are uncertain, not zero-cost rejections", async () => {
  for (const status of [408, 500, 503]) {
    const { gateway, settlements } = dependencies(async () => new Response("private failure", { status }));
    const response = await gateway.fetch(
      modelRequest(),
      runtimeEnv(gatewayConfig()),
      context(),
    );
    assert.equal(response.status, 502);
    assert.match(await response.text(), /upstream_unavailable/);
    assert.equal(settlements.length, 1);
    assert.equal(settlements[0].settlement.outcome, "uncertain");
    assert.equal(settlements[0].settlement.actualUnits, settlements[0].reservation.reservedUnits);
  }
});

test("edge admission runs before configuration parsing and public deep health", async () => {
  let deepHealthCalls = 0;
  const env = {
    GATEWAY_CONFIG_JSON: "{invalid-json",
    GATEWAY_EDGE_RATE_LIMITER: { async limit() { return { success: false }; } },
    ENTITLEMENTS: {
      prepare() {
        deepHealthCalls += 1;
        throw new Error("must not run");
      },
    },
  };
  const gateway = createGateway({ cryptoImpl: fakeCrypto() });
  const response = await gateway.fetch(new Request("https://gateway.test/version"), env, context());
  assert.equal(response.status, 429);
  assert.match(await response.text(), /edge_rate_limit_exceeded/);
  assert.equal(deepHealthCalls, 0);
  const health = await gateway.fetch(new Request("https://gateway.test/healthz"), env, context());
  assert.equal(health.status, 429);
  assert.equal(deepHealthCalls, 0);
});

test("the deployment kill switch rejects before identity, entitlement, body, or upstream work", async () => {
  let upstreamCalls = 0;
  const { gateway, quotaCalls, settlements } = dependencies(async () => {
    upstreamCalls += 1;
    return new Response("never");
  });
  const response = await gateway.fetch(
    modelRequest(),
    runtimeEnv(gatewayConfig({ controls: { modelRequestsEnabled: false } })),
    context(),
  );
  assert.equal(response.status, 503);
  assert.match(await response.text(), /gateway_disabled/);
  assert.equal(upstreamCalls, 0);
  assert.deepEqual(quotaCalls, []);
  assert.deepEqual(settlements, []);
});

test("a remotely deployed development label cannot disable identity rate limiting", async () => {
  let upstreamCalls = 0;
  const { gateway, quotaCalls, settlements } = dependencies(async () => {
    upstreamCalls += 1;
    return new Response("never");
  });
  const config = gatewayConfig({
    environment: "development",
    rateLimit: { required: false },
  });
  const remote = modelRequest();
  Object.defineProperty(remote, "cf", { value: { colo: "SFO" } });
  const response = await gateway.fetch(remote, runtimeEnv(config), context());
  assert.equal(response.status, 503);
  assert.match(await response.text(), /gateway_misconfigured/);
  assert.equal(upstreamCalls, 0);
  assert.deepEqual(quotaCalls, []);
  assert.deepEqual(settlements, []);
});

test("an overlong stream is aborted before its strict concurrency lease expires", async () => {
  let deadlineCallback;
  let cleared = false;
  const fetchImpl = async (_url, init) => new Response(new ReadableStream({
    start(controller) {
      init.signal.addEventListener("abort", () => controller.error(new Error("aborted")));
      controller.enqueue(new TextEncoder().encode("data: open\n\n"));
    },
  }), { headers: { "content-type": "text/event-stream" } });
  const { gateway, quotaCalls, settlements } = dependencies(fetchImpl, [], {
    setTimeoutImpl(callback, milliseconds) {
      assert.equal(milliseconds, 115_000);
      deadlineCallback = callback;
      return { unref() {} };
    },
    clearTimeoutImpl() {
      cleared = true;
    },
  });
  const execution = context();
  const response = await gateway.fetch(modelRequest(), runtimeEnv(gatewayConfig()), execution);
  const reader = response.body.getReader();
  assert.equal(new TextDecoder().decode((await reader.read()).value), "data: open\n\n");
  deadlineCallback();
  await assert.rejects(reader.read(), /aborted/);
  await execution.drain();
  assert.equal(cleared, true);
  assert.equal(settlements[0].settlement.outcome, "completed");
  assert.ok(settlements[0].settlement.actualUnits > 50);
  assert.equal(settlements.length, 1, "stream cancellation cannot roll back committed usage");
  assert.equal(quotaCalls.at(-1).type, "release");
});

test("D1 settlement failure cancels the upstream body before exposing it", async () => {
  let cancelled = false;
  const fetchImpl = async () => new Response(new ReadableStream({
    start(controller) {
      controller.enqueue(new TextEncoder().encode("PRIVATE_MODEL_OUTPUT"));
    },
    cancel() {
      cancelled = true;
    },
  }), { headers: { "content-type": "text/event-stream" } });
  const { gateway, quotaCalls, settlements } = dependencies(
    fetchImpl,
    [],
    {},
    { settlementResult: { applied: false } },
  );
  const response = await gateway.fetch(modelRequest(), runtimeEnv(gatewayConfig()), context());
  assert.equal(response.status, 503);
  const body = await response.text();
  assert.match(body, /entitlement_settlement_failed/);
  assert.doesNotMatch(body, /PRIVATE_MODEL_OUTPUT/);
  assert.equal(cancelled, true);
  assert.deepEqual(settlements.map((item) => item.settlement.outcome), ["completed", "uncertain"]);
  assert.equal(quotaCalls.at(-1).type, "release");
});

test("response deadline is derived from the absolute D1 reservation expiry", async () => {
  let upstreamCalls = 0;
  const { gateway, quotaCalls } = dependencies(
    async () => {
      upstreamCalls += 1;
      return new Response("never");
    },
    [],
    {},
    { reservationExpiresAt: 1_800_000_004 },
  );
  const response = await gateway.fetch(modelRequest(), runtimeEnv(gatewayConfig()), context());
  assert.equal(response.status, 503);
  assert.match(await response.text(), /entitlement_reservation_expired/);
  assert.equal(upstreamCalls, 0);
  assert.equal(quotaCalls.at(-1).type, "release");
});

test("health, version, and deployment facts expose stable non-secret metadata", async () => {
  const { gateway } = dependencies(async () => { throw new Error("not called"); });
  const config = gatewayConfig();
  const env = runtimeEnv(config, {
    CF_VERSION_METADATA: { id: "version-123", tag: "release" },
  });
  const health = await gateway.fetch(new Request("https://gateway.test/healthz"), env, context());
  assert.equal(health.status, 200);
  assert.deepEqual(await health.json(), {
    status: "ready",
    contract_version: 1,
    worker_version: "0.3.0",
    deployment_id: "deployment-test",
    configuration_id: "configuration-test",
    environment: "production",
    region: null,
    version_id: "version-123",
    maintenance_last_run: null,
  });

  const version = await gateway.fetch(new Request("https://gateway.test/version"), env, context());
  assert.deepEqual(await version.json(), { contract_version: 1, worker_version: "0.3.0" });

  const facts = await gateway.fetch(
    new Request("https://gateway.test/.well-known/agentweave-gateway"),
    env,
    context(),
  );
  const factsBody = await facts.json();
  assert.equal(factsBody.kind, "agentweave.model-gateway");
  assert.equal(factsBody.deployment.version_id, "version-123");
  assert.equal(factsBody.policy.entitlements, "d1-authoritative");
  assert.equal(factsBody.policy.request_body_logging, false);
  assert.doesNotMatch(JSON.stringify(factsBody), /server-side-secret|UPSTREAM_API_KEY/);
});

test("authenticated gateway health verifies identity without reserving or invoking a model", async () => {
  let upstreamCalls = 0;
  const { gateway, quotaCalls, settlements } = dependencies(async () => {
    upstreamCalls += 1;
    return new Response("never");
  });
  const request = new Request(
    "https://gateway.test/.well-known/agentweave/gateway-health",
    { headers: { authorization: "Bearer one-time-user-assertion" } },
  );
  const response = await gateway.fetch(
    request,
    runtimeEnv(gatewayConfig(), { CF_VERSION_METADATA: { id: "version-current" } }),
    context(),
  );
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    status: "ready",
    protocol_version: "1",
    deployment_id: "deployment-test",
    remote_version: "version-current",
  });
  assert.equal(upstreamCalls, 0);
  assert.deepEqual(settlements, []);
  assert.equal(quotaCalls.filter((call) => call.type === "rate").length, 1);
  assert.equal(quotaCalls.filter((call) => call.type === "acquire").length, 0);
});

test("health and production requests fail closed when configuration or bindings are unsafe", async () => {
  const logs = [];
  const { gateway } = dependencies(async () => { throw new Error("not called"); }, logs);
  const missingSecret = runtimeEnv(gatewayConfig());
  delete missingSecret.UPSTREAM_API_KEY;
  const unhealthy = await gateway.fetch(new Request("https://gateway.test/healthz"), missingSecret, context());
  assert.equal(unhealthy.status, 503);
  assert.deepEqual(await unhealthy.json(), {
    status: "misconfigured",
    contract_version: 1,
    worker_version: "0.3.0",
  });

  const missingSchema = runtimeEnv(gatewayConfig(), {
    ENTITLEMENTS: {
      prepare() {
        return {
          bind() { return this; },
          async first() { return { schema_version: null, last_cleanup_at: null }; },
        };
      },
    },
  });
  const schemaUnhealthy = await gateway.fetch(
    new Request("https://gateway.test/healthz"),
    missingSchema,
    context(),
  );
  assert.equal(schemaUnhealthy.status, 503);

  const anonymousProduction = runtimeEnv(gatewayConfig({
    auth: { mode: "anonymous", providers: [] },
  }));
  const denied = await gateway.fetch(modelRequest(), anonymousProduction, context());
  assert.equal(denied.status, 503);
  assert.match(await denied.text(), /gateway_misconfigured/);
  assert.doesNotMatch(JSON.stringify(logs), /anonymous requires|UPSTREAM_API_KEY|server-side-secret/);
});

test("anonymous identity is restricted to an explicit local development runtime", async () => {
  const { gateway } = dependencies(async () => { throw new Error("not called"); });
  const config = gatewayConfig({
    environment: "development",
    auth: { mode: "anonymous", providers: [] },
  });
  const noOptIn = await gateway.fetch(
    new Request("https://gateway.test/healthz"),
    runtimeEnv(config),
    context(),
  );
  assert.equal(noOptIn.status, 503);

  const localEnv = runtimeEnv(config, { LOCAL_DEV_ANONYMOUS: "true" });
  const local = await gateway.fetch(new Request("https://gateway.test/healthz"), localEnv, context());
  assert.equal(local.status, 200);

  const remoteRequest = new Request("https://gateway.test/healthz");
  Object.defineProperty(remoteRequest, "cf", { value: { colo: "SFO" } });
  const remote = await gateway.fetch(remoteRequest, localEnv, context());
  assert.equal(remote.status, 503);
});

test("scheduled maintenance uses configured bounded retention without logging identity data", async () => {
  const calls = [];
  const logs = [];
  const gateway = createGateway({
    fetchImpl: async () => { throw new Error("not called"); },
    cryptoImpl: fakeCrypto(),
    nowMilliseconds: () => 1_800_000_000_000,
    logger: {
      info(event) { logs.push(event); },
      error(event) { logs.push(event); },
    },
    entitlementStoreFactory: () => ({
      async cleanup(policy) {
        calls.push(policy);
        return { reservationsExpired: 2, reservationsDeleted: 3 };
      },
    }),
  });
  await gateway.scheduled({}, runtimeEnv(gatewayConfig()));
  assert.deepEqual(calls, [{ retentionSeconds: 2_592_000, batchSize: 100 }]);
  assert.match(JSON.stringify(logs), /gateway.maintenance_completed/);
  assert.doesNotMatch(JSON.stringify(logs), /user-123|VERY_PRIVATE_PROMPT|server-side-secret/);
});
