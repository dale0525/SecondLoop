PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS gateway_schema_metadata (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

INSERT INTO gateway_schema_metadata (key, value, updated_at)
VALUES ('schema_version', '4', unixepoch())
ON CONFLICT(key) DO NOTHING;

INSERT INTO gateway_schema_metadata (key, value, updated_at)
VALUES ('last_cleanup_at', '0', unixepoch())
ON CONFLICT(key) DO NOTHING;

CREATE TABLE IF NOT EXISTS gateway_deployment_budgets (
  deployment_id TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('active', 'suspended', 'disabled')),
  period_start INTEGER NOT NULL,
  period_end INTEGER NOT NULL CHECK (period_end > period_start),
  max_requests INTEGER NOT NULL CHECK (max_requests >= 0),
  max_units INTEGER NOT NULL CHECK (max_units >= 0),
  max_requests_unlimited INTEGER NOT NULL DEFAULT 0 CHECK (max_requests_unlimited IN (0, 1)),
  max_units_unlimited INTEGER NOT NULL DEFAULT 0 CHECK (max_units_unlimited IN (0, 1)),
  used_requests INTEGER NOT NULL DEFAULT 0 CHECK (used_requests >= 0),
  used_units INTEGER NOT NULL DEFAULT 0 CHECK (used_units >= 0),
  reserved_requests INTEGER NOT NULL DEFAULT 0 CHECK (reserved_requests >= 0),
  reserved_units INTEGER NOT NULL DEFAULT 0 CHECK (reserved_units >= 0),
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (deployment_id, period_start)
);

CREATE TABLE IF NOT EXISTS gateway_tenant_budgets (
  deployment_id TEXT NOT NULL,
  provider_id TEXT NOT NULL,
  issuer TEXT NOT NULL,
  tenant TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('active', 'suspended', 'disabled')),
  period_start INTEGER NOT NULL,
  period_end INTEGER NOT NULL CHECK (period_end > period_start),
  max_requests INTEGER NOT NULL CHECK (max_requests >= 0),
  max_units INTEGER NOT NULL CHECK (max_units >= 0),
  max_requests_unlimited INTEGER NOT NULL DEFAULT 0 CHECK (max_requests_unlimited IN (0, 1)),
  max_units_unlimited INTEGER NOT NULL DEFAULT 0 CHECK (max_units_unlimited IN (0, 1)),
  used_requests INTEGER NOT NULL DEFAULT 0 CHECK (used_requests >= 0),
  used_units INTEGER NOT NULL DEFAULT 0 CHECK (used_units >= 0),
  reserved_requests INTEGER NOT NULL DEFAULT 0 CHECK (reserved_requests >= 0),
  reserved_units INTEGER NOT NULL DEFAULT 0 CHECK (reserved_units >= 0),
  policy_source TEXT NOT NULL DEFAULT 'static',
  policy_revision TEXT NOT NULL DEFAULT 'static-v1',
  policy_projection_id TEXT NOT NULL DEFAULT 'static-bootstrap',
  policy_issued_at INTEGER NOT NULL DEFAULT 0,
  policy_expires_at INTEGER NOT NULL DEFAULT 4102444800,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (deployment_id, provider_id, issuer, tenant, period_start)
);

CREATE TABLE IF NOT EXISTS gateway_entitlements (
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
  max_requests_unlimited INTEGER NOT NULL DEFAULT 0 CHECK (max_requests_unlimited IN (0, 1)),
  max_units_unlimited INTEGER NOT NULL DEFAULT 0 CHECK (max_units_unlimited IN (0, 1)),
  max_concurrency_unlimited INTEGER NOT NULL DEFAULT 0 CHECK (max_concurrency_unlimited IN (0, 1)),
  used_requests INTEGER NOT NULL DEFAULT 0 CHECK (used_requests >= 0),
  used_units INTEGER NOT NULL DEFAULT 0 CHECK (used_units >= 0),
  reserved_requests INTEGER NOT NULL DEFAULT 0 CHECK (reserved_requests >= 0),
  reserved_units INTEGER NOT NULL DEFAULT 0 CHECK (reserved_units >= 0),
  policy_source TEXT NOT NULL DEFAULT 'static',
  policy_revision TEXT NOT NULL DEFAULT 'static-v1',
  policy_projection_id TEXT NOT NULL DEFAULT 'static-bootstrap',
  policy_issued_at INTEGER NOT NULL DEFAULT 0,
  policy_expires_at INTEGER NOT NULL DEFAULT 4102444800,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (deployment_id, provider_id, issuer, tenant, subject, period_start)
);

CREATE TABLE IF NOT EXISTS gateway_entitlement_models (
  deployment_id TEXT NOT NULL,
  provider_id TEXT NOT NULL,
  issuer TEXT NOT NULL,
  tenant TEXT NOT NULL,
  subject TEXT NOT NULL,
  period_start INTEGER NOT NULL,
  model TEXT NOT NULL,
  period_end INTEGER NOT NULL CHECK (period_end > period_start),
  status TEXT NOT NULL CHECK (status IN ('active', 'denied')),
  reason_code TEXT,
  policy_source TEXT NOT NULL,
  policy_revision TEXT NOT NULL,
  policy_projection_id TEXT NOT NULL,
  policy_issued_at INTEGER NOT NULL,
  policy_expires_at INTEGER NOT NULL CHECK (policy_expires_at > policy_issued_at),
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (
    deployment_id, provider_id, issuer, tenant, subject, period_start, model
  ),
  FOREIGN KEY (deployment_id, provider_id, issuer, tenant, subject, period_start)
    REFERENCES gateway_entitlements (
      deployment_id, provider_id, issuer, tenant, subject, period_start
    ) ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS gateway_reservations (
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

CREATE TABLE IF NOT EXISTS gateway_idempotency_tombstones (
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

CREATE INDEX IF NOT EXISTS gateway_deployment_budgets_active
  ON gateway_deployment_budgets (deployment_id, status, period_start, period_end);

CREATE INDEX IF NOT EXISTS gateway_tenant_budgets_active
  ON gateway_tenant_budgets (
    deployment_id, provider_id, issuer, tenant, status, period_start, period_end
  );

CREATE INDEX IF NOT EXISTS gateway_entitlements_active
  ON gateway_entitlements (
    deployment_id, provider_id, issuer, tenant, subject, status, period_start, period_end
  );

CREATE INDEX IF NOT EXISTS gateway_entitlement_models_active
  ON gateway_entitlement_models (
    deployment_id, provider_id, issuer, tenant, subject, model, status,
    period_start, period_end, policy_expires_at
  );

CREATE INDEX IF NOT EXISTS gateway_reservations_expiry
  ON gateway_reservations (state, finalized, expires_at, reservation_id);

CREATE INDEX IF NOT EXISTS gateway_reservations_identity
  ON gateway_reservations (
    deployment_id, provider_id, issuer, tenant, subject, state, finalized, expires_at
  );

CREATE INDEX IF NOT EXISTS gateway_reservations_retention
  ON gateway_reservations (finalized, settled_at, reservation_id);

CREATE INDEX IF NOT EXISTS gateway_idempotency_retention
  ON gateway_idempotency_tombstones (retain_until, reservation_id);
