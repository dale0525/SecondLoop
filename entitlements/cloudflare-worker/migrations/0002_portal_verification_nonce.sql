CREATE TABLE commerce_request_nonces_next (
  app_id TEXT NOT NULL,
  environment TEXT NOT NULL CHECK (environment IN ('test', 'production')),
  subject_ref TEXT NOT NULL,
  operation TEXT NOT NULL CHECK (
    operation IN ('checkout', 'customer_portal', 'customer_portal_verified')
  ),
  nonce_hash TEXT NOT NULL CHECK (length(nonce_hash) = 64),
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  PRIMARY KEY (app_id, environment, subject_ref, operation, nonce_hash)
);

INSERT INTO commerce_request_nonces_next (
  app_id, environment, subject_ref, operation, nonce_hash, created_at, expires_at
)
SELECT app_id, environment, subject_ref, operation, nonce_hash, created_at, expires_at
FROM commerce_request_nonces;

DROP TABLE commerce_request_nonces;
ALTER TABLE commerce_request_nonces_next RENAME TO commerce_request_nonces;
CREATE INDEX commerce_nonce_expiry ON commerce_request_nonces (expires_at);
