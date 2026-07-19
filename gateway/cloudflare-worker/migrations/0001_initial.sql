CREATE TABLE gateway_schema_metadata (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

INSERT INTO gateway_schema_metadata (key, value, updated_at)
VALUES ('schema_version', '1', unixepoch());

INSERT INTO gateway_schema_metadata (key, value, updated_at)
VALUES ('last_cleanup_at', '0', unixepoch());

CREATE TABLE gateway_entitlements (
  provider_id TEXT NOT NULL,
  issuer TEXT NOT NULL,
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
  reservation_fence TEXT,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (provider_id, issuer, subject, period_start)
);

CREATE TABLE gateway_reservations (
  reservation_id TEXT PRIMARY KEY,
  provider_id TEXT NOT NULL,
  issuer TEXT NOT NULL,
  subject TEXT NOT NULL,
  period_start INTEGER NOT NULL,
  model TEXT NOT NULL,
  reserved_units INTEGER NOT NULL CHECK (reserved_units > 0),
  state TEXT NOT NULL CHECK (state IN ('reserved', 'settled', 'released', 'expired')),
  outcome TEXT CHECK (outcome IS NULL OR outcome IN ('completed', 'failed', 'cancelled', 'expired')),
  actual_units INTEGER NOT NULL DEFAULT 0 CHECK (actual_units >= 0),
  finalized INTEGER NOT NULL DEFAULT 0 CHECK (finalized IN (0, 1)),
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  settled_at INTEGER,
  idempotency_key_hash TEXT NOT NULL CHECK (length(idempotency_key_hash) = 64),
  request_hash TEXT NOT NULL CHECK (length(request_hash) = 64),
  FOREIGN KEY (provider_id, issuer, subject, period_start)
    REFERENCES gateway_entitlements (provider_id, issuer, subject, period_start)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  UNIQUE (provider_id, issuer, subject, idempotency_key_hash)
);

CREATE INDEX gateway_reservations_expiry
  ON gateway_reservations (provider_id, issuer, subject, state, finalized, expires_at);

CREATE INDEX gateway_reservations_period
  ON gateway_reservations (provider_id, issuer, subject, period_start, created_at);

CREATE INDEX gateway_reservations_retention
  ON gateway_reservations (finalized, settled_at, reservation_id);
