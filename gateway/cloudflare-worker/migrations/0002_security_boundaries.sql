ALTER TABLE gateway_entitlements RENAME TO gateway_entitlements_v1;
ALTER TABLE gateway_reservations RENAME TO gateway_reservations_v1;

DROP INDEX IF EXISTS gateway_reservations_expiry;
DROP INDEX IF EXISTS gateway_reservations_period;
DROP INDEX IF EXISTS gateway_reservations_retention;

CREATE TABLE gateway_deployment_budgets (
  deployment_id TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('active', 'suspended', 'disabled')),
  period_start INTEGER NOT NULL,
  period_end INTEGER NOT NULL CHECK (period_end > period_start),
  max_requests INTEGER NOT NULL CHECK (max_requests >= 0),
  max_units INTEGER NOT NULL CHECK (max_units >= 0),
  used_requests INTEGER NOT NULL DEFAULT 0 CHECK (used_requests >= 0),
  used_units INTEGER NOT NULL DEFAULT 0 CHECK (used_units >= 0),
  reserved_requests INTEGER NOT NULL DEFAULT 0 CHECK (reserved_requests >= 0),
  reserved_units INTEGER NOT NULL DEFAULT 0 CHECK (reserved_units >= 0),
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (deployment_id, period_start)
);

CREATE TABLE gateway_tenant_budgets (
  deployment_id TEXT NOT NULL,
  provider_id TEXT NOT NULL,
  issuer TEXT NOT NULL,
  tenant TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('active', 'suspended', 'disabled')),
  period_start INTEGER NOT NULL,
  period_end INTEGER NOT NULL CHECK (period_end > period_start),
  max_requests INTEGER NOT NULL CHECK (max_requests >= 0),
  max_units INTEGER NOT NULL CHECK (max_units >= 0),
  used_requests INTEGER NOT NULL DEFAULT 0 CHECK (used_requests >= 0),
  used_units INTEGER NOT NULL DEFAULT 0 CHECK (used_units >= 0),
  reserved_requests INTEGER NOT NULL DEFAULT 0 CHECK (reserved_requests >= 0),
  reserved_units INTEGER NOT NULL DEFAULT 0 CHECK (reserved_units >= 0),
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (deployment_id, provider_id, issuer, tenant, period_start)
);

CREATE TABLE gateway_entitlements (
  deployment_id TEXT NOT NULL,
  provider_id TEXT NOT NULL,
  issuer TEXT NOT NULL,
  tenant TEXT NOT NULL,
  subject TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('active', 'suspended', 'revoked')),
  period_start INTEGER NOT NULL,
  period_end INTEGER NOT NULL CHECK (period_end > period_start),
  max_requests INTEGER NOT NULL CHECK (max_requests >= 0),
  max_units INTEGER NOT NULL CHECK (max_units >= 0),
  max_concurrency INTEGER NOT NULL CHECK (max_concurrency > 0 AND max_concurrency <= 1000),
  used_requests INTEGER NOT NULL DEFAULT 0 CHECK (used_requests >= 0),
  used_units INTEGER NOT NULL DEFAULT 0 CHECK (used_units >= 0),
  reserved_requests INTEGER NOT NULL DEFAULT 0 CHECK (reserved_requests >= 0),
  reserved_units INTEGER NOT NULL DEFAULT 0 CHECK (reserved_units >= 0),
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (deployment_id, provider_id, issuer, tenant, subject, period_start)
);

CREATE TABLE gateway_reservations (
  reservation_id TEXT PRIMARY KEY,
  deployment_id TEXT NOT NULL,
  provider_id TEXT NOT NULL,
  issuer TEXT NOT NULL,
  tenant TEXT NOT NULL,
  subject TEXT NOT NULL,
  device_id TEXT NOT NULL,
  entitlement_period_start INTEGER NOT NULL,
  deployment_period_start INTEGER NOT NULL,
  tenant_period_start INTEGER NOT NULL,
  model TEXT NOT NULL,
  reserved_units INTEGER NOT NULL CHECK (reserved_units > 0),
  max_concurrency INTEGER NOT NULL CHECK (max_concurrency > 0 AND max_concurrency <= 1000),
  state TEXT NOT NULL CHECK (state IN ('reserved', 'dispatched', 'settled', 'released', 'expired', 'uncertain')),
  outcome TEXT CHECK (outcome IS NULL OR outcome IN ('completed', 'failed', 'cancelled', 'expired', 'uncertain', 'rejected')),
  actual_units INTEGER NOT NULL DEFAULT 0 CHECK (actual_units >= 0),
  finalized INTEGER NOT NULL DEFAULT 0 CHECK (finalized IN (0, 1)),
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  dispatched_at INTEGER,
  settled_at INTEGER,
  idempotency_key_hash TEXT NOT NULL CHECK (length(idempotency_key_hash) = 64),
  request_hash TEXT NOT NULL CHECK (length(request_hash) = 64),
  reservation_fence TEXT NOT NULL,
  idempotency_expires_at INTEGER NOT NULL,
  FOREIGN KEY (deployment_id, provider_id, issuer, tenant, subject, entitlement_period_start)
    REFERENCES gateway_entitlements (
      deployment_id, provider_id, issuer, tenant, subject, period_start
    ) ON UPDATE CASCADE ON DELETE RESTRICT,
  FOREIGN KEY (deployment_id, deployment_period_start)
    REFERENCES gateway_deployment_budgets (deployment_id, period_start)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  FOREIGN KEY (deployment_id, provider_id, issuer, tenant, tenant_period_start)
    REFERENCES gateway_tenant_budgets (deployment_id, provider_id, issuer, tenant, period_start)
    ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE TABLE gateway_idempotency_tombstones (
  deployment_id TEXT NOT NULL,
  provider_id TEXT NOT NULL,
  issuer TEXT NOT NULL,
  tenant TEXT NOT NULL,
  subject TEXT NOT NULL,
  idempotency_key_hash TEXT NOT NULL CHECK (length(idempotency_key_hash) = 64),
  request_hash TEXT NOT NULL CHECK (length(request_hash) = 64),
  reservation_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  retain_until INTEGER NOT NULL,
  PRIMARY KEY (
    deployment_id, provider_id, issuer, tenant, subject, idempotency_key_hash
  )
);

INSERT INTO gateway_deployment_budgets (
  deployment_id, status, period_start, period_end, max_requests, max_units,
  used_requests, used_units, reserved_requests, reserved_units, updated_at
)
SELECT
  'legacy-unbound', 'disabled', period_start, MAX(period_end),
  SUM(max_requests), SUM(max_units), SUM(used_requests), SUM(used_units),
  SUM(reserved_requests), SUM(reserved_units), MAX(updated_at)
FROM gateway_entitlements_v1
GROUP BY period_start;

INSERT INTO gateway_tenant_budgets (
  deployment_id, provider_id, issuer, tenant, status, period_start, period_end,
  max_requests, max_units, used_requests, used_units, reserved_requests,
  reserved_units, updated_at
)
SELECT
  'legacy-unbound', provider_id, issuer, 'legacy-unbound', 'disabled',
  period_start, MAX(period_end), SUM(max_requests), SUM(max_units),
  SUM(used_requests), SUM(used_units), SUM(reserved_requests),
  SUM(reserved_units), MAX(updated_at)
FROM gateway_entitlements_v1
GROUP BY provider_id, issuer, period_start;

INSERT INTO gateway_entitlements (
  deployment_id, provider_id, issuer, tenant, subject, status, period_start,
  period_end, max_requests, max_units, max_concurrency, used_requests,
  used_units, reserved_requests, reserved_units, updated_at
)
SELECT
  'legacy-unbound', provider_id, issuer, 'legacy-unbound', subject, status,
  period_start, period_end, max_requests, max_units, max_concurrency,
  used_requests, used_units, reserved_requests, reserved_units, updated_at
FROM gateway_entitlements_v1;

INSERT INTO gateway_reservations (
  reservation_id, deployment_id, provider_id, issuer, tenant, subject,
  device_id, entitlement_period_start, deployment_period_start,
  tenant_period_start, model, reserved_units, max_concurrency, state, outcome,
  actual_units, finalized, created_at, expires_at, dispatched_at, settled_at,
  idempotency_key_hash, request_hash, reservation_fence,
  idempotency_expires_at
)
SELECT
  reservation.reservation_id, 'legacy-unbound', reservation.provider_id,
  reservation.issuer, 'legacy-unbound', reservation.subject, 'legacy-unbound',
  reservation.period_start, reservation.period_start, reservation.period_start,
  reservation.model, reservation.reserved_units, entitlement.max_concurrency,
  CASE reservation.state WHEN 'reserved' THEN 'dispatched' ELSE reservation.state END,
  reservation.outcome, reservation.actual_units,
  reservation.finalized, reservation.created_at, reservation.expires_at,
  CASE reservation.state WHEN 'reserved' THEN reservation.created_at ELSE NULL END,
  reservation.settled_at, reservation.idempotency_key_hash,
  reservation.request_hash, 'legacy-migration', unixepoch() + 31536000
FROM gateway_reservations_v1 AS reservation
JOIN gateway_entitlements_v1 AS entitlement
  ON entitlement.provider_id = reservation.provider_id
 AND entitlement.issuer = reservation.issuer
 AND entitlement.subject = reservation.subject
 AND entitlement.period_start = reservation.period_start;

INSERT INTO gateway_idempotency_tombstones (
  deployment_id, provider_id, issuer, tenant, subject, idempotency_key_hash,
  request_hash, reservation_id, created_at, retain_until
)
SELECT
  'legacy-unbound', provider_id, issuer, 'legacy-unbound', subject,
  idempotency_key_hash, request_hash, reservation_id, created_at,
  unixepoch() + 31536000
FROM gateway_reservations_v1;

DROP TABLE gateway_reservations_v1;
DROP TABLE gateway_entitlements_v1;

CREATE INDEX gateway_deployment_budgets_active
  ON gateway_deployment_budgets (deployment_id, status, period_start, period_end);
CREATE INDEX gateway_tenant_budgets_active
  ON gateway_tenant_budgets (
    deployment_id, provider_id, issuer, tenant, status, period_start, period_end
  );
CREATE INDEX gateway_entitlements_active
  ON gateway_entitlements (
    deployment_id, provider_id, issuer, tenant, subject, status, period_start, period_end
  );
CREATE INDEX gateway_reservations_expiry
  ON gateway_reservations (state, finalized, expires_at, reservation_id);
CREATE INDEX gateway_reservations_identity
  ON gateway_reservations (
    deployment_id, provider_id, issuer, tenant, subject, state, finalized, expires_at
  );
CREATE INDEX gateway_reservations_retention
  ON gateway_reservations (finalized, settled_at, reservation_id);
CREATE INDEX gateway_idempotency_retention
  ON gateway_idempotency_tombstones (retain_until, reservation_id);

UPDATE gateway_schema_metadata
SET value = '2', updated_at = unixepoch()
WHERE key = 'schema_version' AND value = '1';
