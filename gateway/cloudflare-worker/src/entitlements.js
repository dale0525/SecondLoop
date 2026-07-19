import { fail } from "./errors.js";

const LEGACY_DEPLOYMENT = "legacy-unbound";

const SCOPED_CANDIDATES = `
WITH candidates AS (
  SELECT reservation_id
  FROM gateway_reservations
  WHERE deployment_id = ?1 AND provider_id = ?2 AND issuer = ?3
    AND tenant = ?4 AND subject = ?5
    AND state IN ('reserved', 'dispatched') AND finalized = 0 AND expires_at <= ?6
  ORDER BY expires_at, reservation_id
  LIMIT ?7
)`;

const GLOBAL_CANDIDATES = `
WITH candidates AS (
  SELECT reservation_id
  FROM gateway_reservations
  WHERE state IN ('reserved', 'dispatched') AND finalized = 0 AND expires_at <= ?1
  ORDER BY expires_at, reservation_id
  LIMIT ?2
)`;

const TARGET_CANDIDATE = `
WITH candidates AS (
  SELECT reservation_id
  FROM gateway_reservations
  WHERE reservation_id = ?1 AND deployment_id = ?2 AND provider_id = ?3
    AND issuer = ?4 AND tenant = ?5 AND subject = ?6
    AND state IN ('reserved', 'dispatched') AND finalized = 0 AND expires_at <= ?7
)`;

function reconcileEntitlements(candidateSql, nowPlaceholder) {
  return `${candidateSql}
UPDATE gateway_entitlements
SET reserved_requests = MAX(0, reserved_requests - (
      SELECT COUNT(*) FROM gateway_reservations AS reservation
      WHERE reservation.reservation_id IN (SELECT reservation_id FROM candidates)
        AND reservation.deployment_id = gateway_entitlements.deployment_id
        AND reservation.provider_id = gateway_entitlements.provider_id
        AND reservation.issuer = gateway_entitlements.issuer
        AND reservation.tenant = gateway_entitlements.tenant
        AND reservation.subject = gateway_entitlements.subject
        AND reservation.entitlement_period_start = gateway_entitlements.period_start
    )),
    reserved_units = MAX(0, reserved_units - COALESCE((
      SELECT SUM(reservation.reserved_units) FROM gateway_reservations AS reservation
      WHERE reservation.reservation_id IN (SELECT reservation_id FROM candidates)
        AND reservation.deployment_id = gateway_entitlements.deployment_id
        AND reservation.provider_id = gateway_entitlements.provider_id
        AND reservation.issuer = gateway_entitlements.issuer
        AND reservation.tenant = gateway_entitlements.tenant
        AND reservation.subject = gateway_entitlements.subject
        AND reservation.entitlement_period_start = gateway_entitlements.period_start
    ), 0)),
    used_requests = used_requests + (
      SELECT COUNT(*) FROM gateway_reservations AS reservation
      WHERE reservation.reservation_id IN (SELECT reservation_id FROM candidates)
        AND reservation.deployment_id = gateway_entitlements.deployment_id
        AND reservation.provider_id = gateway_entitlements.provider_id
        AND reservation.issuer = gateway_entitlements.issuer
        AND reservation.tenant = gateway_entitlements.tenant
        AND reservation.subject = gateway_entitlements.subject
        AND reservation.entitlement_period_start = gateway_entitlements.period_start
        AND reservation.state = 'dispatched'
    ),
    used_units = used_units + COALESCE((
      SELECT SUM(reservation.reserved_units) FROM gateway_reservations AS reservation
      WHERE reservation.reservation_id IN (SELECT reservation_id FROM candidates)
        AND reservation.deployment_id = gateway_entitlements.deployment_id
        AND reservation.provider_id = gateway_entitlements.provider_id
        AND reservation.issuer = gateway_entitlements.issuer
        AND reservation.tenant = gateway_entitlements.tenant
        AND reservation.subject = gateway_entitlements.subject
        AND reservation.entitlement_period_start = gateway_entitlements.period_start
        AND reservation.state = 'dispatched'
    ), 0),
    updated_at = ${nowPlaceholder}
WHERE EXISTS (
  SELECT 1 FROM gateway_reservations AS reservation
  WHERE reservation.reservation_id IN (SELECT reservation_id FROM candidates)
    AND reservation.deployment_id = gateway_entitlements.deployment_id
    AND reservation.provider_id = gateway_entitlements.provider_id
    AND reservation.issuer = gateway_entitlements.issuer
    AND reservation.tenant = gateway_entitlements.tenant
    AND reservation.subject = gateway_entitlements.subject
    AND reservation.entitlement_period_start = gateway_entitlements.period_start
)`;
}

function reconcileDeploymentBudgets(candidateSql, nowPlaceholder) {
  return `${candidateSql}
UPDATE gateway_deployment_budgets
SET reserved_requests = MAX(0, reserved_requests - (
      SELECT COUNT(*) FROM gateway_reservations AS reservation
      WHERE reservation.reservation_id IN (SELECT reservation_id FROM candidates)
        AND reservation.deployment_id = gateway_deployment_budgets.deployment_id
        AND reservation.deployment_period_start = gateway_deployment_budgets.period_start
    )),
    reserved_units = MAX(0, reserved_units - COALESCE((
      SELECT SUM(reservation.reserved_units) FROM gateway_reservations AS reservation
      WHERE reservation.reservation_id IN (SELECT reservation_id FROM candidates)
        AND reservation.deployment_id = gateway_deployment_budgets.deployment_id
        AND reservation.deployment_period_start = gateway_deployment_budgets.period_start
    ), 0)),
    used_requests = used_requests + (
      SELECT COUNT(*) FROM gateway_reservations AS reservation
      WHERE reservation.reservation_id IN (SELECT reservation_id FROM candidates)
        AND reservation.deployment_id = gateway_deployment_budgets.deployment_id
        AND reservation.deployment_period_start = gateway_deployment_budgets.period_start
        AND reservation.state = 'dispatched'
    ),
    used_units = used_units + COALESCE((
      SELECT SUM(reservation.reserved_units) FROM gateway_reservations AS reservation
      WHERE reservation.reservation_id IN (SELECT reservation_id FROM candidates)
        AND reservation.deployment_id = gateway_deployment_budgets.deployment_id
        AND reservation.deployment_period_start = gateway_deployment_budgets.period_start
        AND reservation.state = 'dispatched'
    ), 0),
    updated_at = ${nowPlaceholder}
WHERE EXISTS (
  SELECT 1 FROM gateway_reservations AS reservation
  WHERE reservation.reservation_id IN (SELECT reservation_id FROM candidates)
    AND reservation.deployment_id = gateway_deployment_budgets.deployment_id
    AND reservation.deployment_period_start = gateway_deployment_budgets.period_start
)`;
}

function reconcileTenantBudgets(candidateSql, nowPlaceholder) {
  return `${candidateSql}
UPDATE gateway_tenant_budgets
SET reserved_requests = MAX(0, reserved_requests - (
      SELECT COUNT(*) FROM gateway_reservations AS reservation
      WHERE reservation.reservation_id IN (SELECT reservation_id FROM candidates)
        AND reservation.deployment_id = gateway_tenant_budgets.deployment_id
        AND reservation.provider_id = gateway_tenant_budgets.provider_id
        AND reservation.issuer = gateway_tenant_budgets.issuer
        AND reservation.tenant = gateway_tenant_budgets.tenant
        AND reservation.tenant_period_start = gateway_tenant_budgets.period_start
    )),
    reserved_units = MAX(0, reserved_units - COALESCE((
      SELECT SUM(reservation.reserved_units) FROM gateway_reservations AS reservation
      WHERE reservation.reservation_id IN (SELECT reservation_id FROM candidates)
        AND reservation.deployment_id = gateway_tenant_budgets.deployment_id
        AND reservation.provider_id = gateway_tenant_budgets.provider_id
        AND reservation.issuer = gateway_tenant_budgets.issuer
        AND reservation.tenant = gateway_tenant_budgets.tenant
        AND reservation.tenant_period_start = gateway_tenant_budgets.period_start
    ), 0)),
    used_requests = used_requests + (
      SELECT COUNT(*) FROM gateway_reservations AS reservation
      WHERE reservation.reservation_id IN (SELECT reservation_id FROM candidates)
        AND reservation.deployment_id = gateway_tenant_budgets.deployment_id
        AND reservation.provider_id = gateway_tenant_budgets.provider_id
        AND reservation.issuer = gateway_tenant_budgets.issuer
        AND reservation.tenant = gateway_tenant_budgets.tenant
        AND reservation.tenant_period_start = gateway_tenant_budgets.period_start
        AND reservation.state = 'dispatched'
    ),
    used_units = used_units + COALESCE((
      SELECT SUM(reservation.reserved_units) FROM gateway_reservations AS reservation
      WHERE reservation.reservation_id IN (SELECT reservation_id FROM candidates)
        AND reservation.deployment_id = gateway_tenant_budgets.deployment_id
        AND reservation.provider_id = gateway_tenant_budgets.provider_id
        AND reservation.issuer = gateway_tenant_budgets.issuer
        AND reservation.tenant = gateway_tenant_budgets.tenant
        AND reservation.tenant_period_start = gateway_tenant_budgets.period_start
        AND reservation.state = 'dispatched'
    ), 0),
    updated_at = ${nowPlaceholder}
WHERE EXISTS (
  SELECT 1 FROM gateway_reservations AS reservation
  WHERE reservation.reservation_id IN (SELECT reservation_id FROM candidates)
    AND reservation.deployment_id = gateway_tenant_budgets.deployment_id
    AND reservation.provider_id = gateway_tenant_budgets.provider_id
    AND reservation.issuer = gateway_tenant_budgets.issuer
    AND reservation.tenant = gateway_tenant_budgets.tenant
    AND reservation.tenant_period_start = gateway_tenant_budgets.period_start
)`;
}

function markReconciled(candidateSql, now) {
  return `${candidateSql}
UPDATE gateway_reservations
SET state = CASE state WHEN 'dispatched' THEN 'uncertain' ELSE 'expired' END,
    outcome = CASE state WHEN 'dispatched' THEN 'uncertain' ELSE 'expired' END,
    actual_units = CASE state WHEN 'dispatched' THEN reserved_units ELSE 0 END,
    finalized = 1,
    settled_at = ${now}
WHERE reservation_id IN (SELECT reservation_id FROM candidates)
RETURNING state`;
}

const RECONCILE_TARGET_ENTITLEMENT = reconcileEntitlements(TARGET_CANDIDATE, "?7");
const RECONCILE_TARGET_DEPLOYMENT = reconcileDeploymentBudgets(TARGET_CANDIDATE, "?7");
const RECONCILE_TARGET_TENANT = reconcileTenantBudgets(TARGET_CANDIDATE, "?7");
const MARK_TARGET_RECONCILED = markReconciled(TARGET_CANDIDATE, "?7");
const RECONCILE_SCOPED_ENTITLEMENTS = reconcileEntitlements(SCOPED_CANDIDATES, "?6");
const RECONCILE_SCOPED_DEPLOYMENT = reconcileDeploymentBudgets(SCOPED_CANDIDATES, "?6");
const RECONCILE_SCOPED_TENANTS = reconcileTenantBudgets(SCOPED_CANDIDATES, "?6");
const MARK_SCOPED_RECONCILED = markReconciled(SCOPED_CANDIDATES, "?6");
const RECONCILE_GLOBAL_ENTITLEMENTS = reconcileEntitlements(GLOBAL_CANDIDATES, "?1");
const RECONCILE_GLOBAL_DEPLOYMENT = reconcileDeploymentBudgets(GLOBAL_CANDIDATES, "?1");
const RECONCILE_GLOBAL_TENANTS = reconcileTenantBudgets(GLOBAL_CANDIDATES, "?1");
const MARK_GLOBAL_RECONCILED = markReconciled(GLOBAL_CANDIDATES, "?1");

const INSERT_RESERVATION = `
INSERT INTO gateway_reservations (
  reservation_id, deployment_id, provider_id, issuer, tenant, subject, device_id,
  entitlement_period_start, deployment_period_start, tenant_period_start,
  model, reserved_units, max_concurrency, state, outcome, actual_units, finalized,
  created_at, expires_at, dispatched_at, settled_at, idempotency_key_hash,
  request_hash, reservation_fence, idempotency_expires_at
)
SELECT
  ?1, ?2, ?3, ?4, ?5, ?6, ?7,
  entitlement.period_start, deployment.period_start, tenant_budget.period_start,
  ?8, ?9, entitlement.max_concurrency, 'reserved', NULL, 0, 0,
  ?10, ?11, NULL, NULL, ?12, ?13, ?14, ?15
FROM gateway_entitlements AS entitlement
JOIN gateway_deployment_budgets AS deployment
  ON deployment.deployment_id = ?2
JOIN gateway_tenant_budgets AS tenant_budget
  ON tenant_budget.deployment_id = ?2
 AND tenant_budget.provider_id = ?3 AND tenant_budget.issuer = ?4
 AND tenant_budget.tenant = ?5
WHERE entitlement.deployment_id = ?2
  AND entitlement.provider_id = ?3 AND entitlement.issuer = ?4
  AND entitlement.tenant = ?5 AND entitlement.subject = ?6
  AND entitlement.status = 'active'
  AND entitlement.period_start <= ?10 AND entitlement.period_end > ?10
  AND entitlement.policy_source = ?17 AND entitlement.policy_expires_at > ?10
  AND deployment.status = 'active'
  AND deployment.period_start <= ?10 AND deployment.period_end > ?10
  AND tenant_budget.status = 'active'
  AND tenant_budget.period_start <= ?10 AND tenant_budget.period_end > ?10
  AND tenant_budget.policy_source = ?17 AND tenant_budget.policy_expires_at > ?10
  AND 1 = (
    SELECT COUNT(*) FROM gateway_entitlements AS candidate
    WHERE candidate.deployment_id = ?2 AND candidate.provider_id = ?3
      AND candidate.issuer = ?4 AND candidate.tenant = ?5 AND candidate.subject = ?6
      AND candidate.status = 'active'
      AND candidate.period_start <= ?10 AND candidate.period_end > ?10
      AND candidate.policy_source = ?17 AND candidate.policy_expires_at > ?10
  )
  AND 1 = (
    SELECT COUNT(*) FROM gateway_deployment_budgets AS candidate
    WHERE candidate.deployment_id = ?2 AND candidate.status = 'active'
      AND candidate.period_start <= ?10 AND candidate.period_end > ?10
  )
  AND 1 = (
    SELECT COUNT(*) FROM gateway_tenant_budgets AS candidate
    WHERE candidate.deployment_id = ?2 AND candidate.provider_id = ?3
      AND candidate.issuer = ?4 AND candidate.tenant = ?5 AND candidate.status = 'active'
      AND candidate.period_start <= ?10 AND candidate.period_end > ?10
      AND candidate.policy_source = ?17 AND candidate.policy_expires_at > ?10
  )
  AND (?17 = 'static' OR 1 = (
    SELECT COUNT(*) FROM gateway_entitlement_models AS model_policy
    WHERE model_policy.deployment_id = ?2 AND model_policy.provider_id = ?3
      AND model_policy.issuer = ?4 AND model_policy.tenant = ?5
      AND model_policy.subject = ?6 AND model_policy.model = ?8
      AND model_policy.status = 'active' AND model_policy.policy_source = ?17
      AND model_policy.period_start <= ?10 AND model_policy.period_end > ?10
      AND model_policy.policy_expires_at > ?10
  ))
  AND entitlement.used_requests + entitlement.reserved_requests + 1 <= entitlement.max_requests
  AND entitlement.used_units + entitlement.reserved_units + ?9 <= entitlement.max_units
  AND deployment.used_requests + deployment.reserved_requests + 1 <= deployment.max_requests
  AND deployment.used_units + deployment.reserved_units + ?9 <= deployment.max_units
  AND tenant_budget.used_requests + tenant_budget.reserved_requests + 1 <= tenant_budget.max_requests
  AND tenant_budget.used_units + tenant_budget.reserved_units + ?9 <= tenant_budget.max_units
  AND NOT EXISTS (
    SELECT 1 FROM gateway_idempotency_tombstones AS tombstone
    WHERE tombstone.provider_id = ?3 AND tombstone.issuer = ?4
      AND tombstone.subject = ?6 AND tombstone.retain_until > ?10
      AND ((tombstone.deployment_id = ?2 AND tombstone.tenant = ?5
          AND tombstone.idempotency_key_hash = ?12)
        OR (tombstone.deployment_id = '${LEGACY_DEPLOYMENT}'
          AND tombstone.idempotency_key_hash = ?16))
  )
RETURNING entitlement_period_start, deployment_period_start, tenant_period_start,
  max_concurrency`;

const APPLY_ENTITLEMENT_RESERVATION = `
UPDATE gateway_entitlements
SET reserved_requests = reserved_requests + 1,
    reserved_units = reserved_units + ?7,
    updated_at = ?8
WHERE deployment_id = ?1 AND provider_id = ?2 AND issuer = ?3
  AND tenant = ?4 AND subject = ?5
  AND period_start = (
    SELECT entitlement_period_start FROM gateway_reservations
    WHERE reservation_id = ?6 AND reservation_fence = ?9 AND state = 'reserved'
  )`;

const APPLY_DEPLOYMENT_RESERVATION = `
UPDATE gateway_deployment_budgets
SET reserved_requests = reserved_requests + 1,
    reserved_units = reserved_units + ?3,
    updated_at = ?4
WHERE deployment_id = ?1
  AND period_start = (
    SELECT deployment_period_start FROM gateway_reservations
    WHERE reservation_id = ?2 AND reservation_fence = ?5 AND state = 'reserved'
  )`;

const APPLY_TENANT_RESERVATION = `
UPDATE gateway_tenant_budgets
SET reserved_requests = reserved_requests + 1,
    reserved_units = reserved_units + ?6,
    updated_at = ?7
WHERE deployment_id = ?1 AND provider_id = ?2 AND issuer = ?3 AND tenant = ?4
  AND period_start = (
    SELECT tenant_period_start FROM gateway_reservations
    WHERE reservation_id = ?5 AND reservation_fence = ?8 AND state = 'reserved'
  )`;

const INSERT_TOMBSTONE = `
INSERT INTO gateway_idempotency_tombstones (
  deployment_id, provider_id, issuer, tenant, subject, idempotency_key_hash,
  request_hash, reservation_id, created_at, retain_until
)
SELECT deployment_id, provider_id, issuer, tenant, subject, idempotency_key_hash,
  request_hash, reservation_id, created_at, idempotency_expires_at
FROM gateway_reservations
WHERE reservation_id = ?1 AND reservation_fence = ?2
ON CONFLICT (deployment_id, provider_id, issuer, tenant, subject, idempotency_key_hash)
DO UPDATE SET
  request_hash = excluded.request_hash,
  reservation_id = excluded.reservation_id,
  created_at = excluded.created_at,
  retain_until = excluded.retain_until
WHERE gateway_idempotency_tombstones.retain_until <= excluded.created_at`;

const DELETE_EXPIRED_IDEMPOTENCY_DETAIL = `
DELETE FROM gateway_reservations
WHERE reservation_id = ?1 AND deployment_id = ?2 AND provider_id = ?3
  AND issuer = ?4 AND tenant = ?5 AND subject = ?6
  AND finalized = 1 AND idempotency_expires_at <= ?7`;

const FIND_TOMBSTONE = `
SELECT request_hash, reservation_id
FROM gateway_idempotency_tombstones
WHERE provider_id = ?1 AND issuer = ?2 AND subject = ?3
  AND retain_until > ?5
  AND ((deployment_id = ?6 AND tenant = ?7 AND idempotency_key_hash = ?4)
    OR (deployment_id = '${LEGACY_DEPLOYMENT}' AND idempotency_key_hash = ?8))
ORDER BY CASE WHEN deployment_id = ?6 THEN 0 ELSE 1 END
LIMIT 1`;

const FIND_RESERVATION = `
SELECT state, outcome, actual_units, reserved_units, finalized, request_hash,
  dispatched_at
FROM gateway_reservations
WHERE reservation_id = ?1 AND deployment_id = ?2 AND provider_id = ?3
  AND issuer = ?4 AND tenant = ?5 AND subject = ?6`;

const ADMISSION_DIAGNOSTIC = `
SELECT
  (SELECT COUNT(*) FROM gateway_deployment_budgets
    WHERE deployment_id = ?1 AND period_start <= ?7 AND period_end > ?7) AS deployment_rows,
  (SELECT COUNT(*) FROM gateway_deployment_budgets
    WHERE deployment_id = ?1 AND status = 'active'
      AND period_start <= ?7 AND period_end > ?7
      AND used_requests + reserved_requests + 1 <= max_requests
      AND used_units + reserved_units + ?8 <= max_units) AS deployment_available,
  (SELECT COUNT(*) FROM gateway_tenant_budgets
    WHERE deployment_id = ?1 AND provider_id = ?2 AND issuer = ?3 AND tenant = ?4
      AND period_start <= ?7 AND period_end > ?7
      AND policy_source = ?10 AND policy_expires_at > ?7) AS tenant_rows,
  (SELECT COUNT(*) FROM gateway_tenant_budgets
    WHERE deployment_id = ?1 AND provider_id = ?2 AND issuer = ?3 AND tenant = ?4
      AND status = 'active' AND period_start <= ?7 AND period_end > ?7
      AND policy_source = ?10 AND policy_expires_at > ?7
      AND used_requests + reserved_requests + 1 <= max_requests
      AND used_units + reserved_units + ?8 <= max_units) AS tenant_available,
  (SELECT COUNT(*) FROM gateway_entitlements
    WHERE deployment_id = ?1 AND provider_id = ?2 AND issuer = ?3
      AND tenant = ?4 AND subject = ?5
      AND period_start <= ?7 AND period_end > ?7
      AND policy_source = ?10 AND policy_expires_at > ?7) AS entitlement_rows,
  (SELECT COUNT(*) FROM gateway_entitlements
    WHERE deployment_id = ?1 AND provider_id = ?2 AND issuer = ?3
      AND tenant = ?4 AND subject = ?5 AND status = 'active'
      AND period_start <= ?7 AND period_end > ?7
      AND policy_source = ?10 AND policy_expires_at > ?7
      AND used_requests + reserved_requests + 1 <= max_requests
      AND used_units + reserved_units + ?8 <= max_units) AS entitlement_available,
  CASE WHEN ?10 = 'static' THEN 1 ELSE (
    SELECT COUNT(*) FROM gateway_entitlement_models
    WHERE deployment_id = ?1 AND provider_id = ?2 AND issuer = ?3
      AND tenant = ?4 AND subject = ?5 AND model = ?9 AND status = 'active'
      AND period_start <= ?7 AND period_end > ?7
      AND policy_source = ?10 AND policy_expires_at > ?7
  ) END AS model_available`;

const DEPLOYMENT_ADMISSION = `
SELECT
  COUNT(*) AS row_count,
  SUM(CASE WHEN status = 'active' THEN 1 ELSE 0 END) AS active_count,
  SUM(CASE WHEN status = 'active'
    AND used_requests + reserved_requests < max_requests
    AND used_units + reserved_units < max_units THEN 1 ELSE 0 END) AS available_count
FROM gateway_deployment_budgets
WHERE deployment_id = ?1 AND period_start <= ?2 AND period_end > ?2`;

const MARK_DISPATCHED = `
UPDATE gateway_reservations
SET state = 'dispatched', dispatched_at = ?7
WHERE reservation_id = ?1 AND deployment_id = ?2 AND provider_id = ?3
  AND issuer = ?4 AND tenant = ?5 AND subject = ?6
  AND state = 'reserved' AND finalized = 0`;

function applySettlement(table, periodColumn, identityPredicate) {
  return `
UPDATE ${table}
SET reserved_requests = MAX(0, reserved_requests - 1),
    reserved_units = MAX(0, reserved_units - (
      SELECT reserved_units FROM gateway_reservations WHERE reservation_id = ?1
    )),
    used_requests = used_requests + ?8,
    used_units = used_units + MIN(MAX(0, ?9), (
      SELECT reserved_units FROM gateway_reservations WHERE reservation_id = ?1
    )),
    updated_at = ?10
WHERE ${identityPredicate}
  AND period_start = (
    SELECT ${periodColumn} FROM gateway_reservations WHERE reservation_id = ?1
  )
  AND EXISTS (
    SELECT 1 FROM gateway_reservations
    WHERE reservation_id = ?1 AND deployment_id = ?2 AND provider_id = ?3
      AND issuer = ?4 AND tenant = ?5 AND subject = ?6
      AND state = ?7 AND finalized = 0
  )`;
}

const APPLY_ENTITLEMENT_SETTLEMENT = applySettlement(
  "gateway_entitlements",
  "entitlement_period_start",
  "deployment_id = ?2 AND provider_id = ?3 AND issuer = ?4 AND tenant = ?5 AND subject = ?6",
);
const APPLY_DEPLOYMENT_SETTLEMENT = applySettlement(
  "gateway_deployment_budgets",
  "deployment_period_start",
  "deployment_id = ?2",
);
const APPLY_TENANT_SETTLEMENT = applySettlement(
  "gateway_tenant_budgets",
  "tenant_period_start",
  "deployment_id = ?2 AND provider_id = ?3 AND issuer = ?4 AND tenant = ?5",
);

const FINALIZE_RESERVATION = `
UPDATE gateway_reservations
SET state = ?11, outcome = ?12,
    actual_units = MIN(MAX(0, ?9), reserved_units),
    finalized = 1, settled_at = ?10
WHERE reservation_id = ?1 AND deployment_id = ?2 AND provider_id = ?3
  AND issuer = ?4 AND tenant = ?5 AND subject = ?6
  AND state = ?7 AND finalized = 0`;

const DELETE_RETAINED_RESERVATIONS = `
DELETE FROM gateway_reservations
WHERE reservation_id IN (
  SELECT reservation_id FROM gateway_reservations
  WHERE finalized = 1 AND settled_at IS NOT NULL AND settled_at <= ?1
  ORDER BY settled_at, reservation_id
  LIMIT ?2
)`;

const DELETE_EXPIRED_TOMBSTONES = `
DELETE FROM gateway_idempotency_tombstones
WHERE rowid IN (
  SELECT rowid FROM gateway_idempotency_tombstones
  WHERE retain_until <= ?1
  ORDER BY retain_until, reservation_id
  LIMIT ?2
)`;

const RECORD_CLEANUP = `
INSERT INTO gateway_schema_metadata (key, value, updated_at)
VALUES ('last_cleanup_at', CAST(?1 AS TEXT), ?1)
ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`;

function changes(result) {
  return Number(result?.meta?.changes ?? result?.meta?.rows_written ?? 0);
}

function rows(result) {
  return Array.isArray(result?.results) ? result.results : [];
}

function assertIdentity(identity) {
  for (const field of ["providerId", "issuer", "tenant", "subject"]) {
    if (typeof identity?.[field] !== "string" || identity[field] === "" || identity[field].length > 2048) {
      fail(401, "authentication_failed", "A valid user identity is required.");
    }
  }
  if (identity?.device !== null
    && (typeof identity?.device !== "string" || identity.device === "" || identity.device.length > 2048)) {
    fail(401, "authentication_failed", "A valid user identity is required.");
  }
  if (typeof identity?.deviceVerified !== "boolean"
    || identity.deviceVerified !== (identity.device !== null)) {
    fail(401, "authentication_failed", "A valid user identity is required.");
  }
}

function databaseUnavailable() {
  fail(503, "entitlement_service_unavailable", "Usage authorization is temporarily unavailable.");
}

function hex(bytes) {
  return [...new Uint8Array(bytes)].map((value) => value.toString(16).padStart(2, "0")).join("");
}

async function reservationIdFor(deploymentId, identity, idempotencyKey, cryptoImpl) {
  const input = [
    deploymentId,
    identity.providerId,
    identity.issuer,
    identity.tenant,
    identity.subject,
    idempotencyKey,
  ].join("\0");
  const digest = await cryptoImpl.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return `reservation_${hex(digest)}`;
}

async function legacyIdempotencyHashFor(identity, idempotencyKey, cryptoImpl) {
  const input = [identity.providerId, identity.issuer, identity.subject, idempotencyKey].join("\0");
  const digest = await cryptoImpl.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return hex(digest);
}

function scopedStatements(database, identity, now, batchSize) {
  const bind = (sql) => database.prepare(sql).bind(
    identity.deploymentId,
    identity.providerId,
    identity.issuer,
    identity.tenant,
    identity.subject,
    now,
    batchSize,
  );
  return [
    bind(RECONCILE_SCOPED_ENTITLEMENTS),
    bind(RECONCILE_SCOPED_DEPLOYMENT),
    bind(RECONCILE_SCOPED_TENANTS),
    bind(MARK_SCOPED_RECONCILED),
  ];
}

function targetStatements(database, identity, reservationId, now) {
  const bind = (sql) => database.prepare(sql).bind(
    reservationId,
    identity.deploymentId,
    identity.providerId,
    identity.issuer,
    identity.tenant,
    identity.subject,
    now,
  );
  return [
    bind(RECONCILE_TARGET_ENTITLEMENT),
    bind(RECONCILE_TARGET_DEPLOYMENT),
    bind(RECONCILE_TARGET_TENANT),
    bind(MARK_TARGET_RECONCILED),
  ];
}

export class D1EntitlementStore {
  constructor(database, {
    deploymentId,
    policySource = "static",
    randomUUID = () => globalThis.crypto.randomUUID(),
    nowSeconds = () => Math.floor(Date.now() / 1000),
    cryptoImpl = globalThis.crypto,
  } = {}) {
    this.database = database;
    this.deploymentId = deploymentId;
    if (typeof policySource !== "string" || policySource === "" || policySource.length > 128
      || /[\x00-\x1f\x7f]/.test(policySource)) {
      throw new TypeError("invalid entitlement policy source");
    }
    this.policySource = policySource;
    this.randomUUID = randomUUID;
    this.nowSeconds = nowSeconds;
    this.cryptoImpl = cryptoImpl;
  }

  async assertDeploymentEnabled() {
    if (typeof this.deploymentId !== "string" || this.deploymentId === "") databaseUnavailable();
    let result;
    try {
      result = await this.database.prepare(DEPLOYMENT_ADMISSION)
        .bind(this.deploymentId, this.nowSeconds())
        .first();
    } catch {
      databaseUnavailable();
    }
    if (Number(result?.row_count) !== 1 || Number(result?.active_count) !== 1) {
      fail(503, "gateway_disabled", "Model requests are temporarily disabled.");
    }
    if (Number(result?.available_count) !== 1) {
      fail(429, "global_budget_exhausted", "The application model budget has been reached.", {
        headers: { "retry-after": "60" },
      });
    }
  }

  async reserve(identity, {
    model,
    units,
    ttlSeconds,
    idempotencyKey,
    requestHash,
    idempotencyRetentionSeconds,
    cleanupBatchSize,
  }) {
    assertIdentity(identity);
    if (typeof model !== "string" || model === "" || !Number.isInteger(units) || units < 1
      || !Number.isInteger(ttlSeconds) || ttlSeconds < 1
      || !Number.isInteger(idempotencyRetentionSeconds) || idempotencyRetentionSeconds < ttlSeconds
      || !Number.isInteger(cleanupBatchSize) || cleanupBatchSize < 1 || cleanupBatchSize > 1000) {
      throw new TypeError("invalid entitlement reservation");
    }
    if (typeof idempotencyKey !== "string" || !/^[A-Za-z0-9_-]{16,128}$/.test(idempotencyKey)
      || typeof requestHash !== "string" || !/^[a-f0-9]{64}$/.test(requestHash)) {
      throw new TypeError("invalid entitlement idempotency input");
    }
    const boundedIdentity = { ...identity, deploymentId: this.deploymentId };
    const reservationId = await reservationIdFor(
      this.deploymentId,
      boundedIdentity,
      idempotencyKey,
      this.cryptoImpl,
    );
    const legacyIdempotencyHash = await legacyIdempotencyHashFor(
      boundedIdentity,
      idempotencyKey,
      this.cryptoImpl,
    );
    const reservationFence = this.randomUUID();
    const now = this.nowSeconds();
    const expiresAt = now + ttlSeconds;
    const idempotencyExpiresAt = now + idempotencyRetentionSeconds;
    let results;
    try {
      results = await this.database.batch([
        ...targetStatements(this.database, boundedIdentity, reservationId, now),
        ...scopedStatements(this.database, boundedIdentity, now, cleanupBatchSize),
        this.database.prepare(DELETE_EXPIRED_IDEMPOTENCY_DETAIL).bind(
          reservationId,
          this.deploymentId,
          identity.providerId,
          identity.issuer,
          identity.tenant,
          identity.subject,
          now,
        ),
        this.database.prepare(INSERT_RESERVATION).bind(
          reservationId,
          this.deploymentId,
          identity.providerId,
          identity.issuer,
          identity.tenant,
          identity.subject,
          identity.device ?? "device-disabled",
          model,
          units,
          now,
          expiresAt,
          reservationId.slice("reservation_".length),
          requestHash,
          reservationFence,
          idempotencyExpiresAt,
          legacyIdempotencyHash,
          this.policySource,
        ),
        this.database.prepare(APPLY_ENTITLEMENT_RESERVATION).bind(
          this.deploymentId,
          identity.providerId,
          identity.issuer,
          identity.tenant,
          identity.subject,
          reservationId,
          units,
          now,
          reservationFence,
        ),
        this.database.prepare(APPLY_DEPLOYMENT_RESERVATION).bind(
          this.deploymentId,
          reservationId,
          units,
          now,
          reservationFence,
        ),
        this.database.prepare(APPLY_TENANT_RESERVATION).bind(
          this.deploymentId,
          identity.providerId,
          identity.issuer,
          identity.tenant,
          reservationId,
          units,
          now,
          reservationFence,
        ),
        this.database.prepare(INSERT_TOMBSTONE).bind(reservationId, reservationFence),
      ]);
    } catch {
      databaseUnavailable();
    }
    const inserted = rows(results?.[9])[0];
    if (!inserted) {
      const tombstone = await this.#findTombstone(
        identity,
        reservationId,
        legacyIdempotencyHash,
        now,
      );
      if (tombstone) {
        if (tombstone.request_hash !== requestHash) {
          fail(409, "idempotency_conflict", "This request ID was already used for different model input.");
        }
        fail(409, "duplicate_request", "This model request was already accepted and will not be repeated.");
      }
      await this.#denyFromDiagnostic(identity, now, units, model);
    }
    if ([10, 11, 12, 13].some((index) => changes(results?.[index]) !== 1)) databaseUnavailable();
    const maxConcurrency = Number(inserted.max_concurrency);
    if (!Number.isInteger(maxConcurrency) || maxConcurrency < 1 || maxConcurrency > 1000) databaseUnavailable();
    return Object.freeze({
      reservationId,
      identity: Object.freeze({
        providerId: identity.providerId,
        issuer: identity.issuer,
        tenant: identity.tenant,
        subject: identity.subject,
        device: identity.device,
        deviceVerified: identity.deviceVerified,
      }),
      model,
      reservedUnits: units,
      maxConcurrency,
      entitlementPeriodStart: Number(inserted.entitlement_period_start),
      deploymentPeriodStart: Number(inserted.deployment_period_start),
      tenantPeriodStart: Number(inserted.tenant_period_start),
      expiresAt,
      dispatched: false,
    });
  }

  async markDispatched(reservation) {
    this.#assertReservation(reservation);
    const identity = reservation.identity;
    const now = this.nowSeconds();
    let result;
    try {
      result = await this.database.prepare(MARK_DISPATCHED).bind(
        reservation.reservationId,
        this.deploymentId,
        identity.providerId,
        identity.issuer,
        identity.tenant,
        identity.subject,
        now,
      ).run();
    } catch {
      databaseUnavailable();
    }
    if (changes(result) === 1) return Object.freeze({ ...reservation, dispatched: true });
    const existing = await this.#findReservation(reservation);
    if (existing?.state === "dispatched" && existing.finalized === 0) {
      return Object.freeze({ ...reservation, dispatched: true });
    }
    fail(503, "entitlement_dispatch_conflict", "Usage authorization could not be dispatched.");
  }

  async settle(reservation, { outcome, actualUnits }) {
    this.#assertReservation(reservation);
    if (!["completed", "failed", "cancelled", "uncertain", "rejected"].includes(outcome)
      || !Number.isInteger(actualUnits) || actualUnits < 0) {
      throw new TypeError("invalid entitlement settlement");
    }
    const dispatchedOutcome = outcome === "completed" || outcome === "uncertain" || outcome === "rejected";
    const expectedState = dispatchedOutcome ? "dispatched" : "reserved";
    const chargedRequest = outcome === "completed" || outcome === "uncertain" ? 1 : 0;
    const chargedUnits = outcome === "uncertain" ? reservation.reservedUnits : actualUnits;
    const state = outcome === "completed" ? "settled"
      : outcome === "uncertain" ? "uncertain" : "released";
    const identity = reservation.identity;
    const now = this.nowSeconds();
    const settlementValues = [
      reservation.reservationId,
      this.deploymentId,
      identity.providerId,
      identity.issuer,
      identity.tenant,
      identity.subject,
      expectedState,
      chargedRequest,
      chargedUnits,
      now,
    ];
    const finalizeValues = [...settlementValues, state, outcome];
    let results;
    try {
      results = await this.database.batch([
        this.database.prepare(APPLY_ENTITLEMENT_SETTLEMENT).bind(...settlementValues),
        this.database.prepare(APPLY_DEPLOYMENT_SETTLEMENT).bind(...settlementValues),
        this.database.prepare(APPLY_TENANT_SETTLEMENT).bind(...settlementValues),
        this.database.prepare(FINALIZE_RESERVATION).bind(...finalizeValues),
      ]);
    } catch {
      databaseUnavailable();
    }
    const applied = results?.every((result) => changes(result) === 1);
    if (applied) return Object.freeze({ applied: true, alreadyApplied: false });
    const existing = await this.#findReservation(reservation);
    const expectedUnits = Math.min(chargedUnits, reservation.reservedUnits);
    if (existing?.finalized === 1 && existing.outcome === outcome
      && Number(existing.actual_units) === expectedUnits) {
      return Object.freeze({ applied: false, alreadyApplied: true });
    }
    fail(503, "entitlement_settlement_conflict", "Usage authorization could not be committed.");
  }

  async cleanup({ retentionSeconds, batchSize }) {
    if (!Number.isInteger(retentionSeconds) || retentionSeconds < 0
      || !Number.isInteger(batchSize) || batchSize < 1 || batchSize > 1000) {
      throw new TypeError("invalid entitlement cleanup policy");
    }
    const now = this.nowSeconds();
    const cutoff = now - retentionSeconds;
    let results;
    try {
      results = await this.database.batch([
        this.database.prepare(RECONCILE_GLOBAL_ENTITLEMENTS).bind(now, batchSize),
        this.database.prepare(RECONCILE_GLOBAL_DEPLOYMENT).bind(now, batchSize),
        this.database.prepare(RECONCILE_GLOBAL_TENANTS).bind(now, batchSize),
        this.database.prepare(MARK_GLOBAL_RECONCILED).bind(now, batchSize),
        this.database.prepare(DELETE_RETAINED_RESERVATIONS).bind(cutoff, batchSize),
        this.database.prepare(DELETE_EXPIRED_TOMBSTONES).bind(now, batchSize),
        this.database.prepare(RECORD_CLEANUP).bind(now),
      ]);
    } catch {
      databaseUnavailable();
    }
    const finalized = rows(results?.[3]);
    return Object.freeze({
      entitlementRowsReconciled: changes(results?.[0]),
      deploymentRowsReconciled: changes(results?.[1]),
      tenantRowsReconciled: changes(results?.[2]),
      reservationsExpired: finalized.filter((row) => row.state === "expired").length,
      reservationsUncertain: finalized.filter((row) => row.state === "uncertain").length,
      reservationsDeleted: changes(results?.[4]),
      tombstonesDeleted: changes(results?.[5]),
      ranAt: now,
    });
  }

  #assertReservation(reservation) {
    if (!reservation || typeof reservation.reservationId !== "string" || !reservation.identity
      || reservation.identity.tenant === undefined || reservation.identity.device === undefined
      || !Number.isInteger(reservation.reservedUnits) || reservation.reservedUnits < 1) {
      throw new TypeError("invalid entitlement settlement");
    }
  }

  async #findTombstone(identity, reservationId, legacyIdempotencyHash, now) {
    try {
      return await this.database.prepare(FIND_TOMBSTONE).bind(
        identity.providerId,
        identity.issuer,
        identity.subject,
        reservationId.slice("reservation_".length),
        now,
        this.deploymentId,
        identity.tenant,
        legacyIdempotencyHash,
      ).first();
    } catch {
      databaseUnavailable();
    }
  }

  async #findReservation(reservation) {
    const identity = reservation.identity;
    try {
      return await this.database.prepare(FIND_RESERVATION).bind(
        reservation.reservationId,
        this.deploymentId,
        identity.providerId,
        identity.issuer,
        identity.tenant,
        identity.subject,
      ).first();
    } catch {
      databaseUnavailable();
    }
  }

  async #denyFromDiagnostic(identity, now, units, model) {
    let diagnostic;
    try {
      diagnostic = await this.database.prepare(ADMISSION_DIAGNOSTIC).bind(
        this.deploymentId,
        identity.providerId,
        identity.issuer,
        identity.tenant,
        identity.subject,
        identity.device,
        now,
        units,
        model,
        this.policySource,
      ).first();
    } catch {
      databaseUnavailable();
    }
    if (Number(diagnostic?.deployment_rows) !== 1) databaseUnavailable();
    if (Number(diagnostic.deployment_available) !== 1) {
      fail(429, "global_budget_exhausted", "The application model budget has been reached.", {
        headers: { "retry-after": "60" },
      });
    }
    if (Number(diagnostic.tenant_rows) !== 1 || Number(diagnostic.tenant_available) !== 1) {
      fail(403, "tenant_budget_denied", "This tenant has no available model usage entitlement.");
    }
    if (Number(diagnostic.entitlement_rows) !== 1 || Number(diagnostic.entitlement_available) !== 1) {
      fail(403, "entitlement_denied", "This account has no available model usage entitlement.");
    }
    if (Number(diagnostic.model_available) !== 1) {
      fail(403, "entitlement_denied", "This account cannot use the requested model.");
    }
    databaseUnavailable();
  }
}

export const entitlementSql = Object.freeze({
  ADMISSION_DIAGNOSTIC,
  APPLY_DEPLOYMENT_RESERVATION,
  APPLY_DEPLOYMENT_SETTLEMENT,
  APPLY_ENTITLEMENT_RESERVATION,
  APPLY_ENTITLEMENT_SETTLEMENT,
  APPLY_TENANT_RESERVATION,
  APPLY_TENANT_SETTLEMENT,
  DELETE_EXPIRED_TOMBSTONES,
  DELETE_EXPIRED_IDEMPOTENCY_DETAIL,
  DELETE_RETAINED_RESERVATIONS,
  DEPLOYMENT_ADMISSION,
  FINALIZE_RESERVATION,
  FIND_RESERVATION,
  FIND_TOMBSTONE,
  INSERT_RESERVATION,
  INSERT_TOMBSTONE,
  MARK_DISPATCHED,
  MARK_GLOBAL_RECONCILED,
  MARK_SCOPED_RECONCILED,
  MARK_TARGET_RECONCILED,
  RECONCILE_GLOBAL_DEPLOYMENT,
  RECONCILE_GLOBAL_ENTITLEMENTS,
  RECONCILE_GLOBAL_TENANTS,
  RECONCILE_SCOPED_DEPLOYMENT,
  RECONCILE_SCOPED_ENTITLEMENTS,
  RECONCILE_SCOPED_TENANTS,
  RECONCILE_TARGET_DEPLOYMENT,
  RECONCILE_TARGET_ENTITLEMENT,
  RECONCILE_TARGET_TENANT,
  RECORD_CLEANUP,
});
