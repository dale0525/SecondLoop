import { fail } from "./errors.js";

const LEASE_PREFIX = "lease:";
const META_KEY = "metadata";
const MAX_CONCURRENCY = 1_000;
const MAX_LEASE_MILLISECONDS = 3_600_000;

function leaseKey(leaseId) {
  return `${LEASE_PREFIX}${leaseId}`;
}

async function deleteInChunks(transaction, keys) {
  for (let offset = 0; offset < keys.length; offset += 128) {
    await transaction.delete(keys.slice(offset, offset + 128));
  }
}

function assertLeaseInput(leaseId, limit, expiresAt) {
  if (typeof leaseId !== "string" || !/^[A-Za-z0-9_-]{8,128}$/.test(leaseId)
    || !Number.isInteger(limit) || limit < 1 || limit > MAX_CONCURRENCY
    || !Number.isInteger(expiresAt) || expiresAt < 1) {
    throw new TypeError("invalid concurrency lease");
  }
}

function validActiveCount(value) {
  return Number.isInteger(value) && value >= 0 && value <= MAX_CONCURRENCY;
}

async function rebuildActiveCount(transaction, now) {
  const leases = await transaction.list({ prefix: LEASE_PREFIX, limit: MAX_CONCURRENCY + 1 });
  if (leases.size > MAX_CONCURRENCY) return MAX_CONCURRENCY;
  return [...leases.values()].filter((value) => value?.expiresAt > now).length;
}

export class ConcurrencyLeaseCore {
  constructor(storage, { nowMilliseconds = () => Date.now() } = {}) {
    this.storage = storage;
    this.nowMilliseconds = nowMilliseconds;
  }

  async acquire({ leaseId, limit, expiresAt }) {
    assertLeaseInput(leaseId, limit, expiresAt);
    const now = this.nowMilliseconds();
    if (expiresAt <= now || expiresAt > now + MAX_LEASE_MILLISECONDS) {
      throw new TypeError("invalid concurrency lease expiry");
    }
    const result = await this.storage.transaction(async (transaction) => {
      const key = leaseKey(leaseId);
      const existing = await transaction.get(key);
      const metadata = await transaction.get(META_KEY);
      const hasMetadata = validActiveCount(metadata?.active);
      let active = hasMetadata ? metadata.active : null;
      if (active === null) {
        active = await rebuildActiveCount(transaction, now);
      }
      if (existing?.expiresAt > now) {
        await transaction.put(leaseKey(leaseId), { expiresAt });
        await transaction.put(META_KEY, { active });
        return { acquired: true, active };
      }
      if (existing !== undefined) {
        await transaction.delete(key);
        if (hasMetadata) active = Math.max(0, active - 1);
      }
      if (active >= limit) {
        if (!hasMetadata) await transaction.put(META_KEY, { active });
        return { acquired: false, active };
      }
      await transaction.put(key, { expiresAt });
      await transaction.put(META_KEY, { active: active + 1 });
      return { acquired: true, active: active + 1 };
    });
    if (result.acquired) {
      try {
        await this.#schedule(expiresAt);
      } catch {
        // The committed lease must be returned so its caller can release it.
      }
    }
    return result;
  }

  async release(leaseId) {
    if (typeof leaseId !== "string" || leaseId === "") return false;
    const key = leaseKey(leaseId);
    const now = this.nowMilliseconds();
    return this.storage.transaction(async (transaction) => {
      const existing = await transaction.get(key);
      if (existing === undefined) return false;
      await transaction.delete(key);
      const metadata = await transaction.get(META_KEY);
      if (validActiveCount(metadata?.active)) {
        await transaction.put(META_KEY, { active: Math.max(0, metadata.active - 1) });
      } else {
        const active = await rebuildActiveCount(transaction, now);
        await transaction.put(META_KEY, { active });
      }
      return true;
    });
  }

  async purgeExpired() {
    const now = this.nowMilliseconds();
    const result = await this.storage.transaction(async (transaction) => {
      const leases = await transaction.list({ prefix: LEASE_PREFIX, limit: MAX_CONCURRENCY + 1 });
      const expired = [];
      let earliest = null;
      for (const [key, value] of leases) {
        if (!value || !Number.isInteger(value.expiresAt) || value.expiresAt <= now) expired.push(key);
        else earliest = earliest === null ? value.expiresAt : Math.min(earliest, value.expiresAt);
      }
      if (expired.length > 0) await deleteInChunks(transaction, expired);
      const truncated = leases.size > MAX_CONCURRENCY;
      const active = truncated ? MAX_CONCURRENCY : leases.size - expired.length;
      await transaction.put(META_KEY, { active });
      return truncated && expired.length > 0 ? now + 1 : earliest;
    });
    if (result !== null && typeof this.storage.setAlarm === "function") {
      await this.storage.setAlarm(result);
    }
  }

  async #schedule(timestamp) {
    if (typeof this.storage.setAlarm !== "function") return;
    const current = typeof this.storage.getAlarm === "function" ? await this.storage.getAlarm() : null;
    if (current === null || current > timestamp) await this.storage.setAlarm(timestamp);
  }
}

async function internalJson(request) {
  const declared = Number(request.headers.get("content-length") ?? 0);
  if (declared > 4096) throw new TypeError("internal request too large");
  const text = await request.text();
  if (new TextEncoder().encode(text).byteLength > 4096) throw new TypeError("internal request too large");
  const value = JSON.parse(text);
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new TypeError("invalid internal request");
  return value;
}

export class ConcurrencyLimiter {
  constructor(state) {
    this.core = new ConcurrencyLeaseCore(state.storage);
  }

  async fetch(request) {
    try {
      const url = new URL(request.url);
      if (request.method === "GET" && url.pathname === "/health") {
        return Response.json({ status: "ready", contract_version: 1 });
      }
      if (request.method !== "POST") return new Response(null, { status: 405, headers: { allow: "GET, POST" } });
      const body = await internalJson(request);
      if (url.pathname === "/acquire") {
        const result = await this.core.acquire(body);
        return Response.json(result, { status: result.acquired ? 201 : 429 });
      }
      if (url.pathname === "/release") {
        const released = await this.core.release(body.leaseId);
        return Response.json({ released });
      }
      return new Response(null, { status: 404 });
    } catch {
      return Response.json({ error: "invalid_quota_request" }, { status: 400 });
    }
  }

  async alarm() {
    await this.core.purgeExpired();
  }
}

function toHex(bytes) {
  return [...new Uint8Array(bytes)].map((value) => value.toString(16).padStart(2, "0")).join("");
}

async function quotaKey(deploymentId, identity, scope, cryptoImpl) {
  const dimensions = [scope, deploymentId];
  if (scope !== "deployment") {
    dimensions.push(identity.providerId, identity.issuer, identity.tenant);
  }
  if (scope === "subject") dimensions.push(identity.subject);
  if (scope === "device") dimensions.push(identity.device);
  const wire = dimensions.join("\0");
  const digest = await cryptoImpl.subtle.digest("SHA-256", new TextEncoder().encode(wire));
  return toHex(digest);
}

export async function identityQuotaKey(
  identity,
  cryptoImpl = globalThis.crypto,
  deploymentId = "unscoped-test-deployment",
) {
  return quotaKey(deploymentId, identity, "subject", cryptoImpl);
}

export async function deviceQuotaKey(
  identity,
  cryptoImpl = globalThis.crypto,
  deploymentId = "unscoped-test-deployment",
) {
  return quotaKey(deploymentId, identity, "device", cryptoImpl);
}

export async function tenantQuotaKey(
  identity,
  cryptoImpl = globalThis.crypto,
  deploymentId = "unscoped-test-deployment",
) {
  return quotaKey(deploymentId, identity, "tenant", cryptoImpl);
}

export async function deploymentQuotaKey(
  cryptoImpl = globalThis.crypto,
  deploymentId = "unscoped-test-deployment",
) {
  return quotaKey(deploymentId, {}, "deployment", cryptoImpl);
}

export async function edgeQuotaKey(request, cryptoImpl = globalThis.crypto) {
  const address = request.headers.get("cf-connecting-ip")
    ?? (request.cf === undefined ? "local-development" : "remote-address-unavailable");
  const digest = await cryptoImpl.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(`edge\0${address}`),
  );
  return toHex(digest);
}

export async function checkEdgeAdmission(request, env, cryptoImpl = globalThis.crypto) {
  const limiter = env?.GATEWAY_EDGE_RATE_LIMITER;
  if (!limiter) {
    if (request.cf !== undefined) {
      fail(503, "quota_service_unavailable", "Usage controls are temporarily unavailable.");
    }
    return;
  }
  let result;
  try {
    result = await limiter.limit({ key: await edgeQuotaKey(request, cryptoImpl) });
  } catch {
    fail(503, "quota_service_unavailable", "Usage controls are temporarily unavailable.");
  }
  if (!result?.success) {
    fail(429, "edge_rate_limit_exceeded", "The request rate limit has been reached.", {
      headers: { "retry-after": "60" },
    });
  }
}

export class QuotaCoordinator {
  constructor(config, env, {
    cryptoImpl = globalThis.crypto,
    randomUUID = () => globalThis.crypto.randomUUID(),
    nowMilliseconds = () => Date.now(),
  } = {}) {
    this.config = config;
    this.cryptoImpl = cryptoImpl;
    this.randomUUID = randomUUID;
    this.nowMilliseconds = nowMilliseconds;
    this.namespace = env[config.bindings.concurrency];
    this.rateLimiters = Object.fromEntries(Object.entries(config.rateLimit.bindings)
      .map(([axis, binding]) => [axis, env[binding]]));
  }

  async checkIdentityRate(identity) {
    const axes = await this.#quotaAxes(identity, null);
    for (const axis of axes) {
      const limiter = this.rateLimiters[axis.scope];
      if (!limiter) {
        if (this.config.rateLimit.required) {
          fail(503, "quota_service_unavailable", "Usage controls are temporarily unavailable.");
        }
        continue;
      }
      let result;
      try {
        result = await limiter.limit({ key: axis.key });
      } catch {
        fail(503, "quota_service_unavailable", "Usage controls are temporarily unavailable.");
      }
      if (!result?.success) {
        fail(429, "rate_limit_exceeded", "The request rate limit has been reached.", {
          headers: { "retry-after": "60" },
        });
      }
    }
  }

  async checkRate(identity) {
    return this.checkIdentityRate(identity);
  }

  async acquireConcurrency(identity, limit, ttlSeconds) {
    if (!this.namespace) fail(503, "quota_service_unavailable", "Usage controls are temporarily unavailable.");
    const expiresAt = this.nowMilliseconds() + ttlSeconds * 1000;
    const axes = await this.#quotaAxes(identity, limit);
    const leases = [];
    try {
      for (const axis of axes) {
        leases.push(await this.#acquireAxis(axis, axis.limit, expiresAt));
      }
    } catch (error) {
      await this.releaseConcurrency({ leases });
      throw error;
    }
    return Object.freeze({ leases: Object.freeze(leases), expiresAt });
  }

  async releaseConcurrency(lease) {
    if (!lease || !this.namespace || !Array.isArray(lease.leases)) return false;
    const results = await Promise.all(lease.leases.map(async (axis) => {
      try {
        const id = this.namespace.idFromName(`v2:${axis.scope}:${axis.key}`);
        const response = await this.namespace.get(id).fetch("https://quota.internal/release", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ leaseId: axis.leaseId }),
        });
        return response.ok;
      } catch {
        return false;
      }
    }));
    return results.length > 0 && results.every(Boolean);
  }

  async #acquireAxis(axis, limit, expiresAt) {
    const leaseId = this.randomUUID().replaceAll("-", "_");
    let response;
    try {
      const id = this.namespace.idFromName(`v2:${axis.scope}:${axis.key}`);
      response = await this.namespace.get(id).fetch("https://quota.internal/acquire", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ leaseId, limit, expiresAt }),
      });
    } catch {
      fail(503, "quota_service_unavailable", "Usage controls are temporarily unavailable.");
    }
    if (response.status === 429) {
      fail(429, "concurrency_limit_exceeded", "This account has too many active model requests.", {
        headers: { "retry-after": "1" },
      });
    }
    if (response.status !== 201) fail(503, "quota_service_unavailable", "Usage controls are temporarily unavailable.");
    return Object.freeze({ ...axis, leaseId });
  }

  async #quotaAxes(identity, subjectLimit) {
    const deploymentId = this.config.deploymentId;
    const axes = await Promise.all([
      deploymentQuotaKey(this.cryptoImpl, deploymentId)
        .then((key) => ({
          scope: "deployment",
          key,
          limit: this.config.concurrency.deploymentLimit,
        })),
      tenantQuotaKey(identity, this.cryptoImpl, deploymentId)
        .then((key) => ({
          scope: "tenant",
          key,
          limit: this.config.concurrency.tenantLimit,
        })),
      identityQuotaKey(identity, this.cryptoImpl, deploymentId)
        .then((key) => ({ scope: "subject", key, limit: subjectLimit })),
    ]);
    if (identity.deviceVerified && typeof identity.device === "string") {
      axes.push(await deviceQuotaKey(identity, this.cryptoImpl, deploymentId)
        .then((key) => ({
          scope: "device",
          key,
          limit: this.config.concurrency.deviceLimit,
        })));
    }
    return axes;
  }
}
