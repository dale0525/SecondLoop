ALTER TABLE gateway_tenant_budgets
  ADD COLUMN policy_source TEXT NOT NULL DEFAULT 'static';
ALTER TABLE gateway_tenant_budgets
  ADD COLUMN policy_revision TEXT NOT NULL DEFAULT 'static-v1';
ALTER TABLE gateway_tenant_budgets
  ADD COLUMN policy_projection_id TEXT NOT NULL DEFAULT 'static-bootstrap';
ALTER TABLE gateway_tenant_budgets
  ADD COLUMN policy_issued_at INTEGER NOT NULL DEFAULT 0;
ALTER TABLE gateway_tenant_budgets
  ADD COLUMN policy_expires_at INTEGER NOT NULL DEFAULT 4102444800;

ALTER TABLE gateway_entitlements
  ADD COLUMN policy_source TEXT NOT NULL DEFAULT 'static';
ALTER TABLE gateway_entitlements
  ADD COLUMN policy_revision TEXT NOT NULL DEFAULT 'static-v1';
ALTER TABLE gateway_entitlements
  ADD COLUMN policy_projection_id TEXT NOT NULL DEFAULT 'static-bootstrap';
ALTER TABLE gateway_entitlements
  ADD COLUMN policy_issued_at INTEGER NOT NULL DEFAULT 0;
ALTER TABLE gateway_entitlements
  ADD COLUMN policy_expires_at INTEGER NOT NULL DEFAULT 4102444800;

CREATE TABLE gateway_entitlement_models (
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

CREATE INDEX gateway_entitlement_models_active
  ON gateway_entitlement_models (
    deployment_id, provider_id, issuer, tenant, subject, model, status,
    period_start, period_end, policy_expires_at
  );

UPDATE gateway_schema_metadata
SET value = '3', updated_at = unixepoch()
WHERE key = 'schema_version' AND value = '2';
