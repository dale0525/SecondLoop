CREATE TABLE commerce_schema_metadata (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

INSERT INTO commerce_schema_metadata (key, value, updated_at)
VALUES ('schema_version', '1', unixepoch());

CREATE TABLE commerce_events (
  event_id TEXT PRIMARY KEY,
  environment TEXT NOT NULL CHECK (environment IN ('test', 'production')),
  event_type TEXT NOT NULL,
  body_hash TEXT NOT NULL CHECK (length(body_hash) = 64),
  provider_created_at INTEGER NOT NULL,
  processed_at INTEGER NOT NULL,
  outcome TEXT NOT NULL CHECK (outcome IN ('applied', 'ignored_old', 'replayed', 'conflict')),
  projection_revision TEXT
);

CREATE TABLE commerce_subjects (
  app_id TEXT NOT NULL,
  environment TEXT NOT NULL CHECK (environment IN ('test', 'production')),
  subject_ref TEXT NOT NULL,
  customer_id TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('active', 'conflict', 'revoked')),
  first_seen INTEGER NOT NULL,
  last_seen INTEGER NOT NULL,
  PRIMARY KEY (app_id, environment, subject_ref),
  UNIQUE (app_id, environment, subject_ref, customer_id),
  UNIQUE (app_id, environment, customer_id)
);

CREATE TABLE commerce_subscriptions (
  subscription_id TEXT PRIMARY KEY,
  app_id TEXT NOT NULL,
  environment TEXT NOT NULL CHECK (environment IN ('test', 'production')),
  subject_ref TEXT NOT NULL,
  customer_id TEXT NOT NULL,
  product_id TEXT NOT NULL,
  plan_id TEXT NOT NULL,
  normalized_status TEXT NOT NULL CHECK (normalized_status IN (
    'trialing', 'active', 'scheduled_cancel', 'past_due', 'paused', 'canceled',
    'expired', 'unpaid', 'refunded', 'disputed'
  )),
  current_period_start INTEGER,
  current_period_end INTEGER,
  paid_through INTEGER,
  provider_updated_at INTEGER NOT NULL,
  last_paid_transaction_id TEXT,
  revoked_at INTEGER,
  projection_revision TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (app_id, environment, subject_ref, customer_id)
    REFERENCES commerce_subjects (app_id, environment, subject_ref, customer_id)
    ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE TABLE commerce_revocations (
  event_id TEXT PRIMARY KEY,
  subscription_id TEXT NOT NULL,
  subject_ref TEXT NOT NULL,
  reason TEXT NOT NULL CHECK (reason IN ('expired', 'unpaid', 'refund', 'dispute', 'manual')),
  effective_at INTEGER NOT NULL,
  FOREIGN KEY (event_id) REFERENCES commerce_events (event_id) ON DELETE RESTRICT,
  FOREIGN KEY (subscription_id) REFERENCES commerce_subscriptions (subscription_id) ON DELETE RESTRICT
);

CREATE TABLE commerce_request_nonces (
  app_id TEXT NOT NULL,
  environment TEXT NOT NULL CHECK (environment IN ('test', 'production')),
  subject_ref TEXT NOT NULL,
  operation TEXT NOT NULL CHECK (operation IN ('checkout', 'customer_portal')),
  nonce_hash TEXT NOT NULL CHECK (length(nonce_hash) = 64),
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  PRIMARY KEY (app_id, environment, subject_ref, operation, nonce_hash)
);

CREATE TABLE commerce_checkout_requests (
  request_id TEXT PRIMARY KEY,
  app_id TEXT NOT NULL,
  environment TEXT NOT NULL CHECK (environment IN ('test', 'production')),
  subject_ref TEXT NOT NULL,
  product_id TEXT NOT NULL,
  plan_id TEXT NOT NULL,
  request_hash TEXT NOT NULL CHECK (length(request_hash) = 64),
  created_at INTEGER NOT NULL,
  last_attempt_at INTEGER NOT NULL
);

CREATE TABLE commerce_verifications (
  app_id TEXT NOT NULL,
  environment TEXT NOT NULL CHECK (environment IN ('test', 'production')),
  capability TEXT NOT NULL CHECK (capability IN ('signed_webhook_v1', 'customer_portal_v1')),
  verified_at INTEGER NOT NULL,
  PRIMARY KEY (app_id, environment, capability)
);

CREATE INDEX commerce_subject_subscriptions
  ON commerce_subscriptions (app_id, environment, subject_ref, provider_updated_at DESC);
CREATE INDEX commerce_reconciliation_candidates
  ON commerce_subscriptions (environment, normalized_status, provider_updated_at);
CREATE INDEX commerce_nonce_expiry
  ON commerce_request_nonces (expires_at);
