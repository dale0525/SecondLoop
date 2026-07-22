ALTER TABLE gateway_deployment_budgets
  ADD COLUMN max_requests_unlimited INTEGER NOT NULL DEFAULT 0
  CHECK (max_requests_unlimited IN (0, 1));
ALTER TABLE gateway_deployment_budgets
  ADD COLUMN max_units_unlimited INTEGER NOT NULL DEFAULT 0
  CHECK (max_units_unlimited IN (0, 1));

ALTER TABLE gateway_tenant_budgets
  ADD COLUMN max_requests_unlimited INTEGER NOT NULL DEFAULT 0
  CHECK (max_requests_unlimited IN (0, 1));
ALTER TABLE gateway_tenant_budgets
  ADD COLUMN max_units_unlimited INTEGER NOT NULL DEFAULT 0
  CHECK (max_units_unlimited IN (0, 1));

ALTER TABLE gateway_entitlements
  ADD COLUMN max_requests_unlimited INTEGER NOT NULL DEFAULT 0
  CHECK (max_requests_unlimited IN (0, 1));
ALTER TABLE gateway_entitlements
  ADD COLUMN max_units_unlimited INTEGER NOT NULL DEFAULT 0
  CHECK (max_units_unlimited IN (0, 1));
ALTER TABLE gateway_entitlements
  ADD COLUMN max_concurrency_unlimited INTEGER NOT NULL DEFAULT 0
  CHECK (max_concurrency_unlimited IN (0, 1));

UPDATE gateway_schema_metadata
SET value = '4', updated_at = unixepoch()
WHERE key = 'schema_version' AND value = '3';
