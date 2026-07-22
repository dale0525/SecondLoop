import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import { readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import test from "node:test";

import { D1EntitlementStore } from "../src/entitlements.js";
import { GatewayError } from "../src/errors.js";

const schema = readFileSync(new URL("../schema.sql", import.meta.url), "utf8");
const migrationV1 = readFileSync(new URL("../migrations/0001_initial.sql", import.meta.url), "utf8");
const migrationV2 = readFileSync(new URL("../migrations/0002_security_boundaries.sql", import.meta.url), "utf8");
const migrationV3 = readFileSync(
  new URL("../migrations/0003_signed_entitlement_projections.sql", import.meta.url),
  "utf8",
);
const migrationV4 = readFileSync(
  new URL("../migrations/0004_unlimited_policy_limits.sql", import.meta.url),
  "utf8",
);
const deploymentId = "deployment-test";
const identity = Object.freeze({
  providerId: "oidc-test",
  issuer: "https://identity.example.test/",
  tenant: "tenant-7",
  subject: "user-123",
  device: "device-9",
  deviceVerified: true,
});

function reservationInput(index, units, ttlSeconds = 30) {
  return {
    model: "model-small",
    units,
    ttlSeconds,
    idempotencyKey: `request_${String(index).padStart(16, "0")}`,
    requestHash: index.toString(16).padStart(64, "0"),
    idempotencyRetentionSeconds: 3600,
    cleanupBatchSize: 10,
  };
}

class LocalD1Statement {
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
    return this.owner.database.prepare(this.sql).get(...this.values);
  }

  async run() {
    const result = this.owner.database.prepare(this.sql).run(...this.values);
    return { results: [], meta: { changes: Number(result.changes) } };
  }
}

class LocalD1 {
  constructor(source = schema) {
    if (source && typeof source.prepare === "function" && typeof source.exec === "function") {
      this.database = source;
    } else {
      this.database = new DatabaseSync(":memory:");
      this.database.exec(source);
    }
  }

  prepare(sql) {
    return new LocalD1Statement(this, sql);
  }

  async batch(statements) {
    this.database.exec("BEGIN IMMEDIATE");
    try {
      const results = statements.map((item) => {
        const statement = this.database.prepare(item.sql);
        if (/\bRETURNING\b/i.test(item.sql)) {
          const returned = statement.all(...item.values);
          return { results: returned, meta: { changes: returned.length } };
        }
        const result = statement.run(...item.values);
        return { results: [], meta: { changes: Number(result.changes) } };
      });
      this.database.exec("COMMIT");
      return results;
    } catch (error) {
      this.database.exec("ROLLBACK");
      throw error;
    }
  }

  seed({
    principal = identity,
    now,
    periodStart = now - 60,
    periodEnd = now + 3600,
    deploymentMaxRequests = 100,
    deploymentMaxUnits = 100_000,
    tenantMaxRequests = 100,
    tenantMaxUnits = 100_000,
    maxRequests = 1,
    maxUnits = 1000,
    maxConcurrency = 2,
  }) {
    this.database.prepare(`
      INSERT OR IGNORE INTO gateway_deployment_budgets (
        deployment_id, status, period_start, period_end, max_requests,
        max_units, updated_at
      ) VALUES (?, 'active', ?, ?, ?, ?, ?)
    `).run(
      deploymentId,
      periodStart,
      periodEnd,
      deploymentMaxRequests,
      deploymentMaxUnits,
      now,
    );
    this.database.prepare(`
      INSERT OR IGNORE INTO gateway_tenant_budgets (
        deployment_id, provider_id, issuer, tenant, status, period_start,
        period_end, max_requests, max_units, updated_at
      ) VALUES (?, ?, ?, ?, 'active', ?, ?, ?, ?, ?)
    `).run(
      deploymentId,
      principal.providerId,
      principal.issuer,
      principal.tenant,
      periodStart,
      periodEnd,
      tenantMaxRequests,
      tenantMaxUnits,
      now,
    );
    this.database.prepare(`
      INSERT INTO gateway_entitlements (
        deployment_id, provider_id, issuer, tenant, subject, status,
        period_start, period_end, max_requests, max_units, max_concurrency,
        updated_at
      ) VALUES (?, ?, ?, ?, ?, 'active', ?, ?, ?, ?, ?, ?)
    `).run(
      deploymentId,
      principal.providerId,
      principal.issuer,
      principal.tenant,
      principal.subject,
      periodStart,
      periodEnd,
      maxRequests,
      maxUnits,
      maxConcurrency,
      now,
    );
  }

  counters(table, principal = identity) {
    const predicates = table === "gateway_deployment_budgets"
      ? ["deployment_id = ?"]
      : table === "gateway_tenant_budgets"
        ? ["deployment_id = ?", "provider_id = ?", "issuer = ?", "tenant = ?"]
        : [
          "deployment_id = ?",
          "provider_id = ?",
          "issuer = ?",
          "tenant = ?",
          "subject = ?",
        ];
    const values = [deploymentId];
    if (table !== "gateway_deployment_budgets") {
      values.push(principal.providerId, principal.issuer, principal.tenant);
    }
    if (table === "gateway_entitlements") values.push(principal.subject);
    return { ...this.database.prepare(`
      SELECT used_requests, used_units, reserved_requests, reserved_units
      FROM ${table}
      WHERE ${predicates.join(" AND ")}
      ORDER BY period_start DESC
      LIMIT 1
    `).get(...values) };
  }

  allAxisCounters(principal = identity) {
    return {
      deployment: this.counters("gateway_deployment_budgets", principal),
      tenant: this.counters("gateway_tenant_budgets", principal),
      subject: this.counters("gateway_entitlements", principal),
    };
  }

  count(table) {
    return Number(this.database.prepare(`SELECT COUNT(*) AS count FROM ${table}`).get().count);
  }

  metadata(key) {
    return this.database.prepare("SELECT value FROM gateway_schema_metadata WHERE key = ?").get(key)?.value;
  }
}

function entitlementStore(database, now) {
  let fence = 0;
  return new D1EntitlementStore(database, {
    deploymentId,
    nowSeconds: () => now.value,
    randomUUID: () => `reservation-fence-${++fence}`,
    cryptoImpl: webcrypto,
  });
}

const emptyCounters = Object.freeze({
  used_requests: 0,
  used_units: 0,
  reserved_requests: 0,
  reserved_units: 0,
});

async function sha256Hex(value) {
  const digest = await webcrypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

test("D1 reserves all deployment, tenant, and subject axes atomically", async () => {
  const now = { value: 10_000 };
  const database = new LocalD1();
  database.seed({ now: now.value, maxRequests: 1, maxUnits: 1000, maxConcurrency: 3 });
  const store = entitlementStore(database, now);
  await store.assertDeploymentEnabled();

  const results = await Promise.allSettled([
    store.reserve(identity, reservationInput(1, 600)),
    store.reserve(identity, reservationInput(2, 600)),
  ]);
  assert.equal(results.filter((result) => result.status === "fulfilled").length, 1);
  assert.equal(results.find((result) => result.status === "rejected").reason.code, "entitlement_denied");
  assert.deepEqual(database.allAxisCounters(), {
    deployment: { ...emptyCounters, reserved_requests: 1, reserved_units: 600 },
    tenant: { ...emptyCounters, reserved_requests: 1, reserved_units: 600 },
    subject: { ...emptyCounters, reserved_requests: 1, reserved_units: 600 },
  });

  const reservation = results.find((result) => result.status === "fulfilled").value;
  assert.equal(reservation.maxConcurrency, 3);
  assert.deepEqual(reservation.identity, identity);
  const dispatched = await store.markDispatched(reservation);
  await store.settle(dispatched, { outcome: "completed", actualUnits: 200 });
  assert.deepEqual(database.allAxisCounters(), {
    deployment: { ...emptyCounters, used_requests: 1, used_units: 200 },
    tenant: { ...emptyCounters, used_requests: 1, used_units: 200 },
    subject: { ...emptyCounters, used_requests: 1, used_units: 200 },
  });
});

test("two subjects cannot race through the final global budget slot", async () => {
  const now = { value: 20_000 };
  const database = new LocalD1();
  const second = { ...identity, subject: "user-456", device: "device-10" };
  database.seed({
    now: now.value,
    principal: identity,
    deploymentMaxRequests: 1,
    deploymentMaxUnits: 1000,
    maxRequests: 2,
    maxUnits: 2000,
  });
  database.seed({
    now: now.value,
    principal: second,
    deploymentMaxRequests: 1,
    deploymentMaxUnits: 1000,
    maxRequests: 2,
    maxUnits: 2000,
  });
  const store = entitlementStore(database, now);
  const results = await Promise.allSettled([
    store.reserve(identity, reservationInput(3, 600)),
    store.reserve(second, reservationInput(4, 600)),
  ]);
  assert.equal(results.filter((result) => result.status === "fulfilled").length, 1);
  assert.equal(results.find((result) => result.status === "rejected").reason.code, "global_budget_exhausted");
  assert.deepEqual(database.counters("gateway_deployment_budgets"), {
    ...emptyCounters,
    reserved_requests: 1,
    reserved_units: 600,
  });
  assert.equal(database.count("gateway_reservations"), 1);
  assert.equal(database.count("gateway_idempotency_tombstones"), 1);
});

test("explicit unlimited flags bypass only plan budgets and retain the system concurrency ceiling", async () => {
  const now = { value: 15_000 };
  const database = new LocalD1();
  database.seed({ now: now.value, maxRequests: 1, maxUnits: 1, maxConcurrency: 1 });
  for (const table of ["gateway_deployment_budgets", "gateway_tenant_budgets"]) {
    database.database.exec(`
      UPDATE ${table}
      SET max_requests = 0, max_units = 0,
          max_requests_unlimited = 1, max_units_unlimited = 1
    `);
  }
  database.database.exec(`
    UPDATE gateway_entitlements
    SET max_requests = 0, max_units = 0, max_concurrency = 1,
        max_requests_unlimited = 1, max_units_unlimited = 1,
        max_concurrency_unlimited = 1
  `);
  const store = entitlementStore(database, now);
  const reservation = await store.reserve(identity, reservationInput(80, 50_000));
  assert.equal(reservation.maxConcurrency, 1000);
  const dispatched = await store.markDispatched(reservation);
  await store.settle(dispatched, { outcome: "completed", actualUnits: 40_000 });
  const second = await store.reserve(identity, reservationInput(81, 50_000));
  assert.equal(second.maxConcurrency, 1000);
});

test("tenant rejection cannot leave partial global or subject counters", async () => {
  const now = { value: 25_000 };
  const database = new LocalD1();
  database.seed({ now: now.value, tenantMaxRequests: 0, tenantMaxUnits: 0 });
  const store = entitlementStore(database, now);
  await assert.rejects(
    store.reserve(identity, reservationInput(5, 100)),
    (error) => error.code === "tenant_budget_denied",
  );
  assert.deepEqual(database.allAxisCounters(), {
    deployment: emptyCounters,
    tenant: emptyCounters,
    subject: emptyCounters,
  });
  assert.equal(database.count("gateway_reservations"), 0);
  assert.equal(database.count("gateway_idempotency_tombstones"), 0);
});

test("known upstream rejection releases dispatched reservation while uncertainty charges maximum", async () => {
  const now = { value: 30_000 };
  const database = new LocalD1();
  database.seed({ now: now.value, maxRequests: 3, maxUnits: 3000 });
  const store = entitlementStore(database, now);

  const rejected = await store.markDispatched(
    await store.reserve(identity, reservationInput(6, 700)),
  );
  await store.settle(rejected, { outcome: "rejected", actualUnits: 0 });
  assert.deepEqual(database.allAxisCounters(), {
    deployment: emptyCounters,
    tenant: emptyCounters,
    subject: emptyCounters,
  });

  const uncertain = await store.markDispatched(
    await store.reserve(identity, reservationInput(7, 800)),
  );
  await store.settle(uncertain, { outcome: "uncertain", actualUnits: 0 });
  assert.deepEqual(database.allAxisCounters(), {
    deployment: { ...emptyCounters, used_requests: 1, used_units: 800 },
    tenant: { ...emptyCounters, used_requests: 1, used_units: 800 },
    subject: { ...emptyCounters, used_requests: 1, used_units: 800 },
  });
  assert.equal(database.count("gateway_idempotency_tombstones"), 2);
});

test("idempotency tombstone outlives the detailed reservation retention window", async () => {
  const now = { value: 40_000 };
  const database = new LocalD1();
  database.seed({
    now: now.value,
    periodEnd: now.value + 20_000,
    maxRequests: 2,
    maxUnits: 2000,
  });
  const store = entitlementStore(database, now);
  const input = reservationInput(8, 500);
  const reservation = await store.reserve(identity, input);
  await store.settle(reservation, { outcome: "failed", actualUnits: 0 });

  now.value += 3601;
  await store.cleanup({ retentionSeconds: 3600, batchSize: 10 });
  assert.equal(database.count("gateway_reservations"), 0);
  assert.equal(database.count("gateway_idempotency_tombstones"), 0, "configured tombstone has also expired");

  const longInput = { ...reservationInput(9, 500), idempotencyRetentionSeconds: 7200 };
  const retained = await store.reserve(identity, longInput);
  await store.settle(retained, { outcome: "failed", actualUnits: 0 });
  now.value += 3601;
  await store.cleanup({ retentionSeconds: 3600, batchSize: 10 });
  assert.equal(database.count("gateway_reservations"), 0);
  assert.equal(database.count("gateway_idempotency_tombstones"), 1);
  await assert.rejects(
    store.reserve(identity, longInput),
    (error) => error.code === "duplicate_request" && error.status === 409,
  );
  await assert.rejects(
    store.reserve(identity, { ...longInput, requestHash: "f".repeat(64) }),
    (error) => error.code === "idempotency_conflict" && error.status === 409,
  );
});

test("an expired tombstone can be safely reused without waiting for cron cleanup", async () => {
  const now = { value: 47_500 };
  const database = new LocalD1();
  database.seed({
    now: now.value,
    periodEnd: now.value + 20_000,
    maxRequests: 2,
    maxUnits: 2000,
  });
  const store = entitlementStore(database, now);
  const input = reservationInput(90, 500);
  const first = await store.reserve(identity, input);
  await store.settle(first, { outcome: "failed", actualUnits: 0 });
  assert.equal(database.count("gateway_reservations"), 1);
  assert.equal(database.count("gateway_idempotency_tombstones"), 1);

  now.value += 3601;
  const reused = await store.reserve(identity, { ...input, requestHash: "e".repeat(64) });
  assert.equal(reused.reservationId, first.reservationId);
  assert.equal(database.count("gateway_reservations"), 1);
  assert.equal(database.count("gateway_idempotency_tombstones"), 1);
  assert.deepEqual(database.counters("gateway_entitlements"), {
    ...emptyCounters,
    reserved_requests: 1,
    reserved_units: 500,
  });
});

test("targeted reconciliation prevents pagination from deadlocking request ID reuse", async () => {
  const now = { value: 48_000 };
  const database = new LocalD1();
  database.seed({
    now: now.value,
    periodEnd: now.value + 20_000,
    maxRequests: 3,
    maxUnits: 3000,
  });
  const store = entitlementStore(database, now);
  await store.reserve(identity, reservationInput(91, 300));
  now.value += 1;
  const targetInput = { ...reservationInput(92, 400), cleanupBatchSize: 1 };
  const target = await store.reserve(identity, targetInput);

  now.value += 3601;
  const reused = await store.reserve(identity, {
    ...targetInput,
    requestHash: "d".repeat(64),
  });
  assert.equal(reused.reservationId, target.reservationId);
  assert.deepEqual(database.allAxisCounters(), {
    deployment: { ...emptyCounters, reserved_requests: 1, reserved_units: 400 },
    tenant: { ...emptyCounters, reserved_requests: 1, reserved_units: 400 },
    subject: { ...emptyCounters, reserved_requests: 1, reserved_units: 400 },
  });
  assert.equal(database.count("gateway_reservations"), 2);
  assert.equal(Number(database.database.prepare(`
    SELECT COUNT(*) AS count FROM gateway_reservations
    WHERE state = 'expired' AND finalized = 1
  `).get().count), 1);
});

test("bounded cleanup refunds reserved calls and conservatively charges dispatched calls", async () => {
  const now = { value: 50_000 };
  const database = new LocalD1();
  database.seed({ now: now.value, maxRequests: 4, maxUnits: 4000 });
  const store = entitlementStore(database, now);
  await store.reserve(identity, reservationInput(10, 300));
  await store.markDispatched(await store.reserve(identity, reservationInput(11, 400)));
  now.value += 31;

  const first = await store.cleanup({ retentionSeconds: 3600, batchSize: 1 });
  const second = await store.cleanup({ retentionSeconds: 3600, batchSize: 1 });
  assert.equal(first.reservationsExpired + second.reservationsExpired, 1);
  assert.equal(first.reservationsUncertain + second.reservationsUncertain, 1);
  assert.deepEqual(database.allAxisCounters(), {
    deployment: { ...emptyCounters, used_requests: 1, used_units: 400 },
    tenant: { ...emptyCounters, used_requests: 1, used_units: 400 },
    subject: { ...emptyCounters, used_requests: 1, used_units: 400 },
  });
  assert.equal(Number(database.metadata("last_cleanup_at")), now.value);
});

function foreignKeys(database, table) {
  return database.prepare(`PRAGMA foreign_key_list(${table})`).all()
    .map((row) => ({
      table: row.table,
      from: row.from,
      to: row.to,
      on_update: row.on_update,
      on_delete: row.on_delete,
      seq: Number(row.seq),
    }))
    .sort((left, right) => JSON.stringify(left).localeCompare(JSON.stringify(right)));
}

test("authoritative migrations produce the same v4 foreign-key contract as the snapshot", () => {
  const fresh = new DatabaseSync(":memory:");
  fresh.exec(schema);
  const migrated = new DatabaseSync(":memory:");
  migrated.exec(migrationV1);
  migrated.exec(migrationV2);
  migrated.exec(migrationV3);
  migrated.exec(migrationV4);
  assert.equal(migrated.prepare(`
    SELECT value FROM gateway_schema_metadata WHERE key = 'schema_version'
  `).get().value, "4");
  for (const table of [
    "gateway_tenant_budgets",
    "gateway_entitlements",
    "gateway_entitlement_models",
    "gateway_reservations",
  ]) {
    assert.deepEqual(foreignKeys(migrated, table), foreignKeys(fresh, table));
  }

  migrated.exec("PRAGMA foreign_keys = ON");
  assert.throws(() => migrated.prepare(`
    INSERT INTO gateway_reservations (
      reservation_id, deployment_id, provider_id, issuer, tenant, subject,
      device_id, entitlement_period_start, deployment_period_start,
      tenant_period_start, model, reserved_units, max_concurrency, state,
      actual_units, finalized, created_at, expires_at, idempotency_key_hash,
      request_hash, reservation_fence, idempotency_expires_at
    ) VALUES (
      'orphan', 'wrong-deployment', 'provider', 'issuer', 'tenant', 'subject',
      'device', 1, 1, 1, 'model', 1, 1, 'reserved', 0, 0, 1, 2,
      ?, ?, 'fence', 3
    )
  `).run("a".repeat(64), "b".repeat(64)), /FOREIGN KEY/);
});

test("v1 migration preserves reservations as isolated legacy tombstones", () => {
  const database = new DatabaseSync(":memory:");
  database.exec(migrationV1);
  database.prepare(`
    INSERT INTO gateway_entitlements (
      provider_id, issuer, subject, status, period_start, period_end,
      max_requests, max_units, max_concurrency, updated_at
    ) VALUES (?, ?, ?, 'active', 1, 100, 10, 1000, 2, 1)
  `).run(identity.providerId, identity.issuer, identity.subject);
  database.prepare(`
    INSERT INTO gateway_reservations (
      reservation_id, provider_id, issuer, subject, period_start, model,
      reserved_units, state, actual_units, finalized, created_at, expires_at,
      idempotency_key_hash, request_hash
    ) VALUES ('legacy-reservation', ?, ?, ?, 1, 'model-small', 100,
      'reserved', 0, 0, 2, 90, ?, ?)
  `).run(identity.providerId, identity.issuer, identity.subject, "a".repeat(64), "b".repeat(64));
  database.exec(migrationV2);
  database.exec(migrationV3);
  database.exec(migrationV4);

  const migrated = database.prepare(`
    SELECT deployment_id, tenant, device_id, state, dispatched_at
    FROM gateway_reservations WHERE reservation_id = 'legacy-reservation'
  `).get();
  assert.deepEqual({ ...migrated }, {
    deployment_id: "legacy-unbound",
    tenant: "legacy-unbound",
    device_id: "legacy-unbound",
    state: "dispatched",
    dispatched_at: 2,
  });
  assert.equal(Number(database.prepare(`
    SELECT COUNT(*) AS count FROM gateway_idempotency_tombstones
    WHERE reservation_id = 'legacy-reservation' AND deployment_id = 'legacy-unbound'
  `).get().count), 1);
});

test("a migrated v1 idempotency hash blocks the same raw request ID in v4", async () => {
  const current = Math.floor(Date.now() / 1000);
  const rawInput = reservationInput(93, 100);
  const legacyHash = await sha256Hex([
    identity.providerId,
    identity.issuer,
    identity.subject,
    rawInput.idempotencyKey,
  ].join("\0"));
  const database = new DatabaseSync(":memory:");
  database.exec(migrationV1);
  database.prepare(`
    INSERT INTO gateway_entitlements (
      provider_id, issuer, subject, status, period_start, period_end,
      max_requests, max_units, max_concurrency, reserved_requests,
      reserved_units, updated_at
    ) VALUES (?, ?, ?, 'active', ?, ?, 10, 1000, 2, 1, 100, ?)
  `).run(identity.providerId, identity.issuer, identity.subject, current - 60, current + 3600, current);
  database.prepare(`
    INSERT INTO gateway_reservations (
      reservation_id, provider_id, issuer, subject, period_start, model,
      reserved_units, state, actual_units, finalized, created_at, expires_at,
      idempotency_key_hash, request_hash
    ) VALUES (?, ?, ?, ?, ?, 'model-small', 100, 'reserved', 0, 0, ?, ?, ?, ?)
  `).run(
    `reservation_${legacyHash}`,
    identity.providerId,
    identity.issuer,
    identity.subject,
    current - 60,
    current,
    current + 30,
    legacyHash,
    rawInput.requestHash,
  );
  database.exec(migrationV2);
  database.exec(migrationV3);
  database.exec(migrationV4);

  const wrapped = new LocalD1(database);
  wrapped.seed({
    now: current,
    periodEnd: current + 3600,
    maxRequests: 2,
    maxUnits: 2000,
  });
  const store = entitlementStore(wrapped, { value: current });
  await assert.rejects(
    store.reserve(identity, rawInput),
    (error) => error.code === "duplicate_request",
  );
  await assert.rejects(
    store.reserve(identity, { ...rawInput, requestHash: "f".repeat(64) }),
    (error) => error.code === "idempotency_conflict",
  );
  assert.deepEqual(wrapped.allAxisCounters(), {
    deployment: emptyCounters,
    tenant: emptyCounters,
    subject: emptyCounters,
  });
  assert.equal(Number(database.prepare(`
    SELECT COUNT(*) AS count FROM gateway_reservations
    WHERE deployment_id = ?
  `).get(deploymentId).count), 0);
});

test("D1 errors fail closed without exposing database details", async () => {
  const store = new D1EntitlementStore({
    prepare() {
      return { bind() { return this; } };
    },
    async batch() {
      throw new Error("secret table name and SQL details");
    },
  }, {
    deploymentId,
    randomUUID: () => "reservation-error",
    nowSeconds: () => 1,
    cryptoImpl: webcrypto,
  });
  await assert.rejects(
    store.reserve(identity, reservationInput(12, 1)),
    (error) => error instanceof GatewayError
      && error.code === "entitlement_service_unavailable"
      && !error.publicMessage.includes("table")
      && !error.publicMessage.includes("SQL"),
  );
});
