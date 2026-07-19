import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import test from "node:test";

import { parseGatewayConfig } from "../src/config.js";
import {
  checkEdgeAdmission,
  ConcurrencyLeaseCore,
  ConcurrencyLimiter,
  deviceQuotaKey,
  edgeQuotaKey,
  QuotaCoordinator,
  identityQuotaKey,
} from "../src/quota.js";
import { gatewayConfig } from "./fixtures.js";

class MemoryStorage {
  constructor() {
    this.values = new Map();
    this.lock = Promise.resolve();
    this.alarm = null;
  }

  transaction(operation) {
    const run = this.lock.then(() => operation({
      list: async ({ prefix, limit }) => new Map(
        [...this.values]
          .filter(([key]) => key.startsWith(prefix))
          .sort(([left], [right]) => left.localeCompare(right))
          .slice(0, limit),
      ),
      get: async (key) => this.values.get(key),
      put: async (key, value) => { this.values.set(key, structuredClone(value)); },
      delete: async (keys) => {
        const batch = Array.isArray(keys) ? keys : [keys];
        if (batch.length > 128) throw new Error("Durable Object delete accepts at most 128 keys");
        for (const key of batch) this.values.delete(key);
      },
    }));
    this.lock = run.catch(() => undefined);
    return run;
  }

  async getAlarm() {
    return this.alarm;
  }

  async setAlarm(value) {
    this.alarm = value;
  }
}

test("Durable Object lease core serializes strict concurrent acquisition", async () => {
  let now = 1_000;
  const storage = new MemoryStorage();
  const core = new ConcurrencyLeaseCore(storage, { nowMilliseconds: () => now });
  const attempts = await Promise.all([
    core.acquire({ leaseId: "lease_one", limit: 2, expiresAt: 2_000 }),
    core.acquire({ leaseId: "lease_two", limit: 2, expiresAt: 2_000 }),
    core.acquire({ leaseId: "lease_three", limit: 2, expiresAt: 2_000 }),
  ]);
  assert.deepEqual(attempts.map((attempt) => attempt.acquired), [true, true, false]);
  assert.equal([...storage.values.keys()].filter((key) => key.startsWith("lease:")).length, 2);

  assert.equal(await core.release("lease_one"), true);
  assert.equal((await core.acquire({ leaseId: "lease_three", limit: 2, expiresAt: 2_000 })).acquired, true);
  assert.equal(await core.release("missing"), false);

  now = 2_001;
  await core.purgeExpired();
  assert.equal([...storage.values.keys()].filter((key) => key.startsWith("lease:")).length, 0);
});

test("Durable Object fetch projection exposes only bounded acquire and release operations", async () => {
  const storage = new MemoryStorage();
  const object = new ConcurrencyLimiter({ storage });
  const health = await object.fetch(new Request("https://quota.internal/health"));
  assert.deepEqual(await health.json(), { status: "ready", contract_version: 1 });
  const acquire = (leaseId) => object.fetch(new Request("https://quota.internal/acquire", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ leaseId, limit: 1, expiresAt: Date.now() + 10_000 }),
  }));
  assert.equal((await acquire("lease_first")).status, 201);
  assert.equal((await acquire("lease_second")).status, 429);
  const released = await object.fetch(new Request("https://quota.internal/release", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ leaseId: "lease_first" }),
  }));
  assert.equal(released.status, 200);
  assert.deepEqual(await released.json(), { released: true });
});

test("Durable Object expiration cleanup respects the 128-key batch deletion limit", async () => {
  const storage = new MemoryStorage();
  storage.values.set("metadata", { active: 300 });
  for (let index = 0; index < 300; index += 1) {
    storage.values.set(`lease:expired_${String(index).padStart(4, "0")}`, { expiresAt: 999 });
  }
  const core = new ConcurrencyLeaseCore(storage, { nowMilliseconds: () => 1_000 });
  await core.purgeExpired();
  assert.equal([...storage.values.keys()].filter((key) => key.startsWith("lease:")).length, 0);
  assert.deepEqual(storage.values.get("metadata"), { active: 0 });
});

test("lease metadata reconstruction fails closed across a truncated storage scan", async () => {
  const storage = new MemoryStorage();
  for (let index = 0; index < 1_000; index += 1) {
    storage.values.set(`lease:expired_${String(index).padStart(4, "0")}`, { expiresAt: 999 });
  }
  storage.values.set("lease:zzzz_active", { expiresAt: 2_000 });
  const core = new ConcurrencyLeaseCore(storage, { nowMilliseconds: () => 1_000 });

  assert.deepEqual(
    await core.acquire({ leaseId: "lease_new", limit: 1_000, expiresAt: 2_000 }),
    { acquired: false, active: 1_000 },
  );
  assert.deepEqual(storage.values.get("metadata"), { active: 1_000 });

  storage.values.set("lease:release_target", { expiresAt: 2_000 });
  storage.values.set("metadata", { active: -1 });
  assert.equal(await core.release("release_target"), true);
  assert.deepEqual(storage.values.get("metadata"), { active: 1_000 });

  await core.purgeExpired();
  assert.deepEqual(storage.values.get("metadata"), { active: 1_000 });
  assert.equal(storage.alarm, 1_001);
  await core.purgeExpired();
  assert.deepEqual(storage.values.get("metadata"), { active: 1 });
});

test("a committed lease remains releasable when alarm scheduling fails", async () => {
  const storage = new MemoryStorage();
  storage.setAlarm = async () => { throw new Error("alarm unavailable"); };
  const core = new ConcurrencyLeaseCore(storage, { nowMilliseconds: () => 1_000 });

  assert.deepEqual(
    await core.acquire({ leaseId: "lease_alarm", limit: 1, expiresAt: 2_000 }),
    { acquired: true, active: 1 },
  );
  assert.equal(await core.release("lease_alarm"), true);
  assert.deepEqual(storage.values.get("metadata"), { active: 0 });
});

test("quota identity keys are stable hashes and do not expose provider subjects", async () => {
  const identity = {
    providerId: "oidc",
    issuer: "https://issuer.test/",
    tenant: "tenant-7",
    subject: "private-user-id",
    device: "device-9",
    deviceVerified: true,
  };
  const first = await identityQuotaKey(identity, webcrypto);
  const second = await identityQuotaKey(identity, webcrypto);
  const different = await identityQuotaKey({ ...identity, subject: "other-user" }, webcrypto);
  const otherDevice = await identityQuotaKey({ ...identity, device: "device-10" }, webcrypto);
  const device = await deviceQuotaKey(identity, webcrypto);
  const changedDevice = await deviceQuotaKey({ ...identity, device: "device-10" }, webcrypto);
  const otherDeployment = await identityQuotaKey(identity, webcrypto, "other-deployment");
  assert.equal(first, second);
  assert.equal(first, otherDevice, "subject ceilings cannot be multiplied by changing devices");
  assert.notEqual(first, different);
  assert.notEqual(device, changedDevice);
  assert.equal(device, await deviceQuotaKey({ ...identity, subject: "other-user" }, webcrypto));
  assert.notEqual(first, otherDeployment);
  assert.match(first, /^[a-f0-9]{64}$/);
  assert.doesNotMatch(first, /private-user-id/);
});

test("Rate Limit and Durable Object bindings fail closed and use hashed keys", async () => {
  const config = parseGatewayConfig(gatewayConfig());
  const calls = [];
  const namespace = {
    idFromName(name) {
      calls.push({ type: "id", name });
      return name;
    },
    get() {
      return {
        async fetch(url, init) {
          calls.push({ type: "fetch", url, body: JSON.parse(init.body) });
          return Response.json({ acquired: true }, { status: 201 });
        },
      };
    },
  };
  const identity = {
    providerId: "oidc",
    issuer: "https://issuer.test/",
    tenant: "tenant-7",
    subject: "private-user-id",
    device: "device-9",
    deviceVerified: true,
  };
  const rateCalls = [];
  const limiter = (axis, result = { success: true }) => ({
    async limit(input) {
      rateCalls.push({ axis, input });
      if (result instanceof Error) throw result;
      return result;
    },
  });
  const coordinator = new QuotaCoordinator(config, {
    CONCURRENCY: namespace,
    GATEWAY_DEPLOYMENT_RATE_LIMITER: limiter("deployment"),
    GATEWAY_TENANT_RATE_LIMITER: limiter("tenant"),
    GATEWAY_RATE_LIMITER: limiter("subject"),
    GATEWAY_DEVICE_RATE_LIMITER: limiter("device"),
  }, {
    cryptoImpl: webcrypto,
    randomUUID: () => "00000000-0000-4000-8000-000000000001",
    nowMilliseconds: () => 1_000,
  });
  await coordinator.checkIdentityRate(identity);
  assert.deepEqual(rateCalls.map((call) => call.axis), ["deployment", "tenant", "subject", "device"]);
  const lease = await coordinator.acquireConcurrency(identity, 2, 30);
  assert.equal(calls.filter((call) => call.type === "id").length, 4);
  assert.ok(calls.filter((call) => call.type === "id").some((call) => call.name.startsWith("v2:deployment:")));
  assert.ok(calls.filter((call) => call.type === "id").some((call) => call.name.startsWith("v2:tenant:")));
  assert.ok(calls.filter((call) => call.type === "id").some((call) => call.name.startsWith("v2:subject:")));
  assert.ok(calls.filter((call) => call.type === "id").some((call) => call.name.startsWith("v2:device:")));
  assert.doesNotMatch(calls.find((call) => call.type === "id").name, /private-user-id|tenant-7|device-9/);
  assert.deepEqual(
    calls.filter((call) => call.type === "fetch" && call.url.endsWith("/acquire"))
      .map((call) => call.body.limit),
    [100, 20, 2, 1],
  );
  assert.equal(await coordinator.releaseConcurrency(lease), true);
  assert.equal(calls.filter((call) => call.type === "fetch" && call.url.endsWith("/release")).length, 4);

  const denied = new QuotaCoordinator(config, {
    CONCURRENCY: namespace,
    GATEWAY_DEPLOYMENT_RATE_LIMITER: limiter("deployment-denied-path"),
    GATEWAY_TENANT_RATE_LIMITER: limiter("tenant-denied-path"),
    GATEWAY_RATE_LIMITER: limiter("subject-denied", { success: false }),
    GATEWAY_DEVICE_RATE_LIMITER: limiter("device-denied-path"),
  }, { cryptoImpl: webcrypto });
  await assert.rejects(
    denied.checkRate(identity),
    (error) => error.code === "rate_limit_exceeded" && error.status === 429,
  );

  const unavailable = new QuotaCoordinator(config, {
    CONCURRENCY: namespace,
    GATEWAY_DEPLOYMENT_RATE_LIMITER: limiter("deployment-unavailable-path"),
    GATEWAY_TENANT_RATE_LIMITER: limiter("tenant-unavailable", new Error("binding unavailable")),
    GATEWAY_RATE_LIMITER: limiter("subject-unavailable-path"),
    GATEWAY_DEVICE_RATE_LIMITER: limiter("device-unavailable-path"),
  }, { cryptoImpl: webcrypto });
  await assert.rejects(
    unavailable.checkRate(identity),
    (error) => error.code === "quota_service_unavailable" && error.status === 503,
  );
});

test("edge admission uses a static pre-configuration binding and conservative remote key", async () => {
  const calls = [];
  const env = {
    GATEWAY_EDGE_RATE_LIMITER: {
      async limit(input) {
        calls.push(input);
        return { success: true };
      },
    },
  };
  const remote = new Request("https://gateway.test/healthz");
  Object.defineProperty(remote, "cf", { value: { colo: "SFO", clientTcpRtt: 42 } });
  await checkEdgeAdmission(remote, env, webcrypto);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].key, await edgeQuotaKey(remote, webcrypto));
  assert.doesNotMatch(calls[0].key, /42|SFO/);

  await assert.rejects(
    checkEdgeAdmission(remote, {}, webcrypto),
    (error) => error.code === "quota_service_unavailable",
  );
  await assert.rejects(
    checkEdgeAdmission(remote, {
      GATEWAY_EDGE_RATE_LIMITER: { async limit() { return { success: false }; } },
    }, webcrypto),
    (error) => error.code === "edge_rate_limit_exceeded" && error.status === 429,
  );
});
