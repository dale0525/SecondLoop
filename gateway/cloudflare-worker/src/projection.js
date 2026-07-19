import { fail } from "./errors.js";

const REQUEST_DOMAIN = "agentweave-entitlement-projection-request-v1";
const RESPONSE_DOMAIN = "agentweave-entitlement-projection-response-v1";
const SIGNATURE_HEADER = "x-agentweave-entitlement-signature";

const POLICY_STATE = `
SELECT
  (SELECT COUNT(*) FROM gateway_tenant_budgets
    WHERE deployment_id = ?1 AND provider_id = ?2 AND issuer = ?3 AND tenant = ?4
      AND period_start <= ?7 AND period_end > ?7 AND policy_source = ?9
      AND policy_expires_at > ?8) AS tenant_rows,
  (SELECT COUNT(*) FROM gateway_tenant_budgets
    WHERE deployment_id = ?1 AND provider_id = ?2 AND issuer = ?3 AND tenant = ?4
      AND period_start <= ?7 AND period_end > ?7 AND policy_source = ?9
      AND policy_expires_at > ?8 AND status = 'active') AS tenant_active,
  (SELECT COUNT(*) FROM gateway_entitlements
    WHERE deployment_id = ?1 AND provider_id = ?2 AND issuer = ?3 AND tenant = ?4
      AND subject = ?5 AND period_start <= ?7 AND period_end > ?7
      AND policy_source = ?9 AND policy_expires_at > ?8) AS subject_rows,
  (SELECT COUNT(*) FROM gateway_entitlements
    WHERE deployment_id = ?1 AND provider_id = ?2 AND issuer = ?3 AND tenant = ?4
      AND subject = ?5 AND period_start <= ?7 AND period_end > ?7
      AND policy_source = ?9 AND policy_expires_at > ?8 AND status = 'active') AS subject_active,
  (SELECT COUNT(*) FROM gateway_entitlement_models
    WHERE deployment_id = ?1 AND provider_id = ?2 AND issuer = ?3 AND tenant = ?4
      AND subject = ?5 AND model = ?6 AND period_start <= ?7 AND period_end > ?7
      AND policy_source = ?9 AND policy_expires_at > ?8) AS model_rows,
  (SELECT COUNT(*) FROM gateway_entitlement_models
    WHERE deployment_id = ?1 AND provider_id = ?2 AND issuer = ?3 AND tenant = ?4
      AND subject = ?5 AND model = ?6 AND period_start <= ?7 AND period_end > ?7
      AND policy_source = ?9 AND policy_expires_at > ?8 AND status = 'active') AS model_active`;

const REVOKE_OLD_TENANT = `
UPDATE gateway_tenant_budgets
SET status = 'suspended', policy_expires_at = MIN(policy_expires_at, ?7), updated_at = ?7
WHERE deployment_id = ?1 AND provider_id = ?2 AND issuer = ?3 AND tenant = ?4
  AND policy_source = ?5 AND period_start <> ?6 AND period_end > ?7
  AND policy_issued_at <= ?8`;

const REVOKE_OLD_SUBJECT = `
UPDATE gateway_entitlements
SET status = 'suspended', policy_expires_at = MIN(policy_expires_at, ?8), updated_at = ?8
WHERE deployment_id = ?1 AND provider_id = ?2 AND issuer = ?3 AND tenant = ?4
  AND subject = ?5 AND policy_source = ?6 AND period_start <> ?7 AND period_end > ?8
  AND policy_issued_at <= ?9`;

const REVOKE_OLD_MODELS = `
UPDATE gateway_entitlement_models
SET status = 'denied', policy_expires_at = MIN(policy_expires_at, ?8), updated_at = ?8
WHERE deployment_id = ?1 AND provider_id = ?2 AND issuer = ?3 AND tenant = ?4
  AND subject = ?5 AND policy_source = ?6 AND period_start <> ?7 AND period_end > ?8
  AND policy_issued_at <= ?9`;

const UPSERT_TENANT = `
INSERT INTO gateway_tenant_budgets (
  deployment_id, provider_id, issuer, tenant, status, period_start, period_end,
  max_requests, max_units, used_requests, used_units, reserved_requests,
  reserved_units, policy_source, policy_revision, policy_projection_id,
  policy_issued_at, policy_expires_at, updated_at
) VALUES (?1, ?2, ?3, ?4, 'active', ?5, ?6, ?7, ?8, 0, 0, 0, 0,
  ?9, ?10, ?11, ?12, ?13, ?14)
ON CONFLICT (deployment_id, provider_id, issuer, tenant, period_start) DO UPDATE SET
  status = excluded.status,
  period_end = excluded.period_end,
  max_requests = excluded.max_requests,
  max_units = excluded.max_units,
  policy_source = excluded.policy_source,
  policy_revision = excluded.policy_revision,
  policy_projection_id = excluded.policy_projection_id,
  policy_issued_at = excluded.policy_issued_at,
  policy_expires_at = excluded.policy_expires_at,
  updated_at = excluded.updated_at
WHERE gateway_tenant_budgets.policy_source <> excluded.policy_source
   OR excluded.policy_issued_at > gateway_tenant_budgets.policy_issued_at
   OR (excluded.policy_issued_at = gateway_tenant_budgets.policy_issued_at
       AND excluded.policy_revision = gateway_tenant_budgets.policy_revision)`;

const UPSERT_SUBJECT = `
INSERT INTO gateway_entitlements (
  deployment_id, provider_id, issuer, tenant, subject, status, period_start,
  period_end, max_requests, max_units, max_concurrency, used_requests, used_units,
  reserved_requests, reserved_units, policy_source, policy_revision,
  policy_projection_id, policy_issued_at, policy_expires_at, updated_at
) VALUES (?1, ?2, ?3, ?4, ?5, 'active', ?6, ?7, ?8, ?9, ?10, 0, 0, 0, 0,
  ?11, ?12, ?13, ?14, ?15, ?16)
ON CONFLICT (deployment_id, provider_id, issuer, tenant, subject, period_start) DO UPDATE SET
  status = excluded.status,
  period_end = excluded.period_end,
  max_requests = excluded.max_requests,
  max_units = excluded.max_units,
  max_concurrency = excluded.max_concurrency,
  policy_source = excluded.policy_source,
  policy_revision = excluded.policy_revision,
  policy_projection_id = excluded.policy_projection_id,
  policy_issued_at = excluded.policy_issued_at,
  policy_expires_at = excluded.policy_expires_at,
  updated_at = excluded.updated_at
WHERE gateway_entitlements.policy_source <> excluded.policy_source
   OR excluded.policy_issued_at > gateway_entitlements.policy_issued_at
   OR (excluded.policy_issued_at = gateway_entitlements.policy_issued_at
       AND excluded.policy_revision = gateway_entitlements.policy_revision)`;

const UPSERT_MODEL = `
INSERT INTO gateway_entitlement_models (
  deployment_id, provider_id, issuer, tenant, subject, period_start, model,
  period_end, status, reason_code, policy_source, policy_revision,
  policy_projection_id, policy_issued_at, policy_expires_at, updated_at
) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16)
ON CONFLICT (deployment_id, provider_id, issuer, tenant, subject, period_start, model)
DO UPDATE SET
  period_end = excluded.period_end,
  status = excluded.status,
  reason_code = excluded.reason_code,
  policy_source = excluded.policy_source,
  policy_revision = excluded.policy_revision,
  policy_projection_id = excluded.policy_projection_id,
  policy_issued_at = excluded.policy_issued_at,
  policy_expires_at = excluded.policy_expires_at,
  updated_at = excluded.updated_at
WHERE gateway_entitlement_models.policy_source <> excluded.policy_source
   OR excluded.policy_issued_at > gateway_entitlement_models.policy_issued_at
   OR (excluded.policy_issued_at = gateway_entitlement_models.policy_issued_at
       AND excluded.policy_revision = gateway_entitlement_models.policy_revision)`;

function unavailable() {
  fail(503, "entitlement_projection_unavailable", "Usage authorization is temporarily unavailable.");
}

function text(value, label, maximum = 2048) {
  if (typeof value !== "string" || value === "" || value.length > maximum || /[\x00-\x1f\x7f]/.test(value)) {
    throw new TypeError(`${label} is invalid`);
  }
  return value;
}

function integer(value, label, minimum, maximum) {
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) {
    throw new TypeError(`${label} is invalid`);
  }
  return value;
}

function onlyKeys(value, allowed, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new TypeError(`${label} is invalid`);
  }
  for (const key of Object.keys(value)) {
    if (!allowed.includes(key)) throw new TypeError(`${label} contains an unknown field`);
  }
  return value;
}

function budget(value, label, subject = false) {
  onlyKeys(value, ["periodStart", "periodEnd", "maxRequests", "maxUnits", "maxConcurrency"], label);
  const result = {
    periodStart: integer(value.periodStart, `${label}.periodStart`, 0, Number.MAX_SAFE_INTEGER),
    periodEnd: integer(value.periodEnd, `${label}.periodEnd`, 1, Number.MAX_SAFE_INTEGER),
    maxRequests: integer(value.maxRequests, `${label}.maxRequests`, 0, Number.MAX_SAFE_INTEGER),
    maxUnits: integer(value.maxUnits, `${label}.maxUnits`, 0, Number.MAX_SAFE_INTEGER),
  };
  if (result.periodEnd <= result.periodStart) throw new TypeError(`${label} window is invalid`);
  if (subject) {
    result.maxConcurrency = integer(value.maxConcurrency, `${label}.maxConcurrency`, 1, 1000);
  } else if (value.maxConcurrency !== undefined) {
    throw new TypeError(`${label}.maxConcurrency is not allowed`);
  }
  return Object.freeze(result);
}

function concat(...values) {
  const size = values.reduce((total, value) => total + value.byteLength, 0);
  const result = new Uint8Array(size);
  let offset = 0;
  for (const value of values) {
    result.set(value, offset);
    offset += value.byteLength;
  }
  return result;
}

function canonical(domain, fields, body) {
  const prefix = new TextEncoder().encode(`${domain}\n${fields.join("\n")}\n`);
  return concat(prefix, body);
}

function base64Url(bytes) {
  let binary = "";
  for (const value of new Uint8Array(bytes)) binary += String.fromCharCode(value);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

function decodeBase64Url(value) {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]{43}$/.test(value)) {
    throw new TypeError("signature is invalid");
  }
  const normalized = value.replaceAll("-", "+").replaceAll("_", "/") + "=".repeat((4 - value.length % 4) % 4);
  const decoded = atob(normalized);
  return Uint8Array.from(decoded, (character) => character.charCodeAt(0));
}

async function boundedBody(response, maximum) {
  const declared = Number(response.headers.get("content-length"));
  if (Number.isFinite(declared) && declared > maximum) throw new TypeError("response is too large");
  if (!response.body) return new Uint8Array();
  const reader = response.body.getReader();
  const chunks = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > maximum) throw new TypeError("response is too large");
      chunks.push(value);
    }
  } catch (error) {
    await reader.cancel().catch(() => {});
    throw error;
  }
  return concat(...chunks);
}

function validateProjection(value, expected, config, now) {
  onlyKeys(value, [
    "schemaVersion",
    "sourceId",
    "projectionId",
    "revision",
    "nonce",
    "deploymentId",
    "providerId",
    "issuer",
    "tenant",
    "subject",
    "model",
    "issuedAt",
    "expiresAt",
    "decision",
    "reasonCode",
    "tenantBudget",
    "subjectBudget",
  ], "projection");
  const tenantBudget = budget(value.tenantBudget, "projection.tenantBudget");
  const subjectBudget = budget(value.subjectBudget, "projection.subjectBudget", true);
  const issuedAt = integer(value.issuedAt, "projection.issuedAt", 0, Number.MAX_SAFE_INTEGER);
  const expiresAt = integer(value.expiresAt, "projection.expiresAt", 1, Number.MAX_SAFE_INTEGER);
  const decision = text(value.decision, "projection.decision", 16);
  if (!['allow', 'deny'].includes(decision)) throw new TypeError("projection.decision is invalid");
  const reasonCode = value.reasonCode === null ? null : text(value.reasonCode, "projection.reasonCode", 128);
  const exact = value.schemaVersion === 1
    && value.sourceId === config.sourceId
    && value.nonce === expected.nonce
    && value.deploymentId === expected.deploymentId
    && value.providerId === expected.providerId
    && value.issuer === expected.issuer
    && value.tenant === expected.tenant
    && value.subject === expected.subject
    && value.model === expected.model;
  const timing = issuedAt >= now - config.maxClockSkewSeconds
    && issuedAt <= now + config.maxClockSkewSeconds
    && expiresAt > issuedAt
    && expiresAt > now + config.refreshBeforeSeconds
    && expiresAt <= tenantBudget.periodEnd
    && expiresAt <= subjectBudget.periodEnd
    && tenantBudget.periodStart <= now && tenantBudget.periodEnd > now
    && subjectBudget.periodStart <= now && subjectBudget.periodEnd > now;
  const decisionShape = decision === "allow" ? reasonCode === null : reasonCode !== null;
  if (!exact || !timing || !decisionShape) throw new TypeError("projection binding is invalid");
  return Object.freeze({
    projectionId: text(value.projectionId, "projection.projectionId", 256),
    revision: text(value.revision, "projection.revision", 256),
    issuedAt,
    expiresAt,
    decision,
    reasonCode,
    tenantBudget,
    subjectBudget,
  });
}

export class EntitlementProjectionResolver {
  constructor(config, env, {
    fetchImpl = globalThis.fetch,
    cryptoImpl = globalThis.crypto,
    nowMilliseconds = () => Date.now(),
    setTimeoutImpl = globalThis.setTimeout,
    clearTimeoutImpl = globalThis.clearTimeout,
  } = {}) {
    this.config = config;
    this.database = env?.[config.bindings.entitlements];
    this.fetchImpl = fetchImpl;
    this.cryptoImpl = cryptoImpl;
    this.nowMilliseconds = nowMilliseconds;
    this.setTimeoutImpl = setTimeoutImpl;
    this.clearTimeoutImpl = clearTimeoutImpl;
    this.projection = config.entitlements.projection;
    this.secret = this.projection ? env?.[this.projection.secretBinding] : null;
  }

  async ensure(identity, { model }) {
    if (!this.projection) return;
    const now = Math.floor(this.nowMilliseconds() / 1000);
    const refreshAfter = now + this.projection.refreshBeforeSeconds;
    const state = await this.#policyState(identity, model, now, refreshAfter);
    if (this.#fresh(state)) return this.#enforce(state);
    const projection = await this.#fetchProjection(identity, model, now);
    await this.#applyProjection(identity, model, projection, now);
    const applied = await this.#policyState(identity, model, now, refreshAfter);
    if (!this.#fresh(applied)) unavailable();
    return this.#enforce(applied);
  }

  async #policyState(identity, model, now, refreshAfter) {
    try {
      return await this.database.prepare(POLICY_STATE).bind(
        this.config.deploymentId,
        identity.providerId,
        identity.issuer,
        identity.tenant,
        identity.subject,
        model,
        now,
        refreshAfter,
        this.projection.sourceId,
      ).first();
    } catch {
      unavailable();
    }
  }

  #fresh(state) {
    return Number(state?.tenant_rows) === 1
      && Number(state?.subject_rows) === 1
      && Number(state?.model_rows) === 1;
  }

  #enforce(state) {
    if (Number(state?.tenant_active) !== 1 || Number(state?.subject_active) !== 1
      || Number(state?.model_active) !== 1) {
      fail(403, "entitlement_denied", "This account cannot use the requested model.");
    }
  }

  async #fetchProjection(identity, model, now) {
    const nonce = this.cryptoImpl.randomUUID();
    const request = {
      schemaVersion: 1,
      sourceId: this.projection.sourceId,
      nonce,
      deploymentId: this.config.deploymentId,
      providerId: identity.providerId,
      issuer: identity.issuer,
      tenant: identity.tenant,
      subject: identity.subject,
      model,
      requestedAt: now,
    };
    const body = new TextEncoder().encode(JSON.stringify(request));
    let key;
    let signature;
    try {
      key = await this.cryptoImpl.subtle.importKey(
        "raw",
        new TextEncoder().encode(this.secret),
        { name: "HMAC", hash: "SHA-256" },
        false,
        ["sign", "verify"],
      );
      signature = await this.cryptoImpl.subtle.sign(
        "HMAC",
        key,
        canonical(REQUEST_DOMAIN, [String(now), nonce], body),
      );
    } catch {
      unavailable();
    }
    const abort = new AbortController();
    const timeout = this.setTimeoutImpl(
      () => abort.abort("entitlement projection timeout"),
      this.projection.timeoutMilliseconds,
    );
    timeout?.unref?.();
    let response;
    let responseBody;
    try {
      response = await this.fetchImpl(this.projection.url, {
        method: "POST",
        redirect: "error",
        signal: abort.signal,
        headers: {
          "content-type": "application/json",
          "x-agentweave-entitlement-version": "1",
          "x-agentweave-entitlement-timestamp": String(now),
          "x-agentweave-entitlement-nonce": nonce,
          [SIGNATURE_HEADER]: `v1=${base64Url(signature)}`,
        },
        body,
      });
      if (response.status !== 200 || response.redirected
        || (response.url && response.url !== this.projection.url)
        || !/^application\/json(?:;|$)/i.test(response.headers.get("content-type") ?? "")) {
        throw new TypeError("projection response metadata is invalid");
      }
      responseBody = await boundedBody(response, this.projection.maxResponseBytes);
      const signed = response.headers.get(SIGNATURE_HEADER);
      if (!signed?.startsWith("v1=")) throw new TypeError("projection signature is missing");
      const valid = await this.cryptoImpl.subtle.verify(
        "HMAC",
        key,
        decodeBase64Url(signed.slice(3)),
        canonical(RESPONSE_DOMAIN, [nonce], responseBody),
      );
      if (!valid) throw new TypeError("projection signature is invalid");
      const decoded = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(responseBody));
      return validateProjection(decoded, request, this.projection, now);
    } catch {
      unavailable();
    } finally {
      this.clearTimeoutImpl(timeout);
    }
  }

  async #applyProjection(identity, model, projection, now) {
    const common = [
      this.config.deploymentId,
      identity.providerId,
      identity.issuer,
      identity.tenant,
    ];
    const source = this.projection.sourceId;
    const tenant = projection.tenantBudget;
    const subject = projection.subjectBudget;
    try {
      await this.database.batch([
        this.database.prepare(REVOKE_OLD_TENANT).bind(
          ...common,
          source,
          tenant.periodStart,
          now,
          projection.issuedAt,
        ),
        this.database.prepare(REVOKE_OLD_SUBJECT).bind(
          ...common,
          identity.subject,
          source,
          subject.periodStart,
          now,
          projection.issuedAt,
        ),
        this.database.prepare(REVOKE_OLD_MODELS).bind(
          ...common,
          identity.subject,
          source,
          subject.periodStart,
          now,
          projection.issuedAt,
        ),
        this.database.prepare(UPSERT_TENANT).bind(
          ...common,
          tenant.periodStart,
          tenant.periodEnd,
          tenant.maxRequests,
          tenant.maxUnits,
          source,
          projection.revision,
          projection.projectionId,
          projection.issuedAt,
          projection.expiresAt,
          now,
        ),
        this.database.prepare(UPSERT_SUBJECT).bind(
          ...common,
          identity.subject,
          subject.periodStart,
          subject.periodEnd,
          subject.maxRequests,
          subject.maxUnits,
          subject.maxConcurrency,
          source,
          projection.revision,
          projection.projectionId,
          projection.issuedAt,
          projection.expiresAt,
          now,
        ),
        this.database.prepare(UPSERT_MODEL).bind(
          ...common,
          identity.subject,
          subject.periodStart,
          model,
          subject.periodEnd,
          projection.decision === "allow" ? "active" : "denied",
          projection.reasonCode,
          source,
          projection.revision,
          projection.projectionId,
          projection.issuedAt,
          projection.expiresAt,
          now,
        ),
      ]);
    } catch {
      unavailable();
    }
  }
}

export const projectionInternals = Object.freeze({
  POLICY_STATE,
  REQUEST_DOMAIN,
  RESPONSE_DOMAIN,
  SIGNATURE_HEADER,
});
