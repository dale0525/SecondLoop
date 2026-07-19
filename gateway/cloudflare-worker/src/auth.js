import { GatewayError, fail } from "./errors.js";

const MAX_JWT_BYTES = 32 * 1024;
const MAX_JWKS_BYTES = 128 * 1024;

function unauthorized() {
  fail(401, "authentication_failed", "A valid user identity is required.", {
    headers: { "www-authenticate": "Bearer" },
  });
}

function decodeBase64Url(value) {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]+$/.test(value)) unauthorized();
  const normalized = value.replaceAll("-", "+").replaceAll("_", "/");
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
  try {
    if (typeof Buffer !== "undefined") return new Uint8Array(Buffer.from(padded, "base64"));
    const binary = atob(padded);
    return Uint8Array.from(binary, (character) => character.charCodeAt(0));
  } catch {
    unauthorized();
  }
}

function decodeJsonSegment(value) {
  let decoded;
  try {
    decoded = new TextDecoder("utf-8", { fatal: true }).decode(decodeBase64Url(value));
    const parsed = JSON.parse(decoded);
    if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) unauthorized();
    return parsed;
  } catch (error) {
    if (error instanceof GatewayError) throw error;
    unauthorized();
  }
}

function parseJwt(token) {
  if (typeof token !== "string" || token.length === 0 || token.length > MAX_JWT_BYTES) unauthorized();
  const segments = token.split(".");
  if (segments.length !== 3 || segments.some((segment) => segment.length === 0)) unauthorized();
  return {
    header: decodeJsonSegment(segments[0]),
    claims: decodeJsonSegment(segments[1]),
    signature: decodeBase64Url(segments[2]),
    signingInput: new TextEncoder().encode(`${segments[0]}.${segments[1]}`),
  };
}

function audienceMatches(claim, expected) {
  if (typeof claim === "string") return claim === expected;
  return Array.isArray(claim) && claim.length > 0
    && claim.every((entry) => typeof entry === "string")
    && claim.includes(expected);
}

function assertFixedClaims(parsed, provider, nowSeconds) {
  const { header, claims } = parsed;
  if (header.alg !== provider.algorithm || typeof header.kid !== "string" || header.kid === "") unauthorized();
  if (header.typ !== undefined && header.typ !== "JWT" && header.typ !== "at+jwt") unauthorized();
  if (header.crit !== undefined || header.b64 !== undefined) unauthorized();
  if (claims.iss !== provider.issuer || !audienceMatches(claims.aud, provider.audience)) unauthorized();
  if (!Number.isInteger(claims.exp) || nowSeconds - provider.clockSkewSeconds >= claims.exp) unauthorized();
  if (provider.requireNbf && !Number.isInteger(claims.nbf)) unauthorized();
  if (claims.nbf !== undefined
    && (!Number.isInteger(claims.nbf) || nowSeconds + provider.clockSkewSeconds < claims.nbf)) unauthorized();
  if (claims.iat !== undefined
    && (!Number.isInteger(claims.iat) || nowSeconds + provider.clockSkewSeconds < claims.iat)) unauthorized();
}

function algorithmParameters(algorithm) {
  if (algorithm === "RS256") {
    return {
      expectedKty: "RSA",
      import: { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      verify: { name: "RSASSA-PKCS1-v1_5" },
    };
  }
  if (algorithm === "ES256") {
    return {
      expectedKty: "EC",
      import: { name: "ECDSA", namedCurve: "P-256" },
      verify: { name: "ECDSA", hash: "SHA-256" },
    };
  }
  unauthorized();
}

function cacheSeconds(headers) {
  const cacheControl = headers?.get?.("cache-control") ?? "";
  const match = /(?:^|,)\s*max-age=(\d+)/i.exec(cacheControl);
  return Math.min(3600, Math.max(30, match ? Number(match[1]) : 300));
}

async function readBoundedText(response, maximum) {
  if (!response.body) return "";
  const reader = response.body.getReader();
  const chunks = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > maximum) {
        await reader.cancel("JWKS size limit exceeded");
        throw new Error("JWKS size limit exceeded");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
}

export class JwksResolver {
  constructor({
    fetchImpl = globalThis.fetch,
    nowMilliseconds = () => Date.now(),
    timeoutMilliseconds = 5_000,
    setTimeoutImpl = globalThis.setTimeout,
    clearTimeoutImpl = globalThis.clearTimeout,
  } = {}) {
    this.fetchImpl = (...args) => fetchImpl(...args);
    this.nowMilliseconds = nowMilliseconds;
    this.timeoutMilliseconds = timeoutMilliseconds;
    this.setTimeoutImpl = (...args) => setTimeoutImpl(...args);
    this.clearTimeoutImpl = (...args) => clearTimeoutImpl(...args);
    this.cache = new Map();
    this.inflight = new Map();
  }

  async resolve(provider, kid) {
    const now = this.nowMilliseconds();
    let entry = this.cache.get(provider.jwksUrl);
    if (!entry || entry.expiresAt <= now) entry = await this.#refresh(provider.jwksUrl, now);
    let keys = entry.keys.filter((key) => key.kid === kid);
    if (keys.length === 0 && entry.nextUnknownKidRefreshAt <= now) {
      entry = await this.#refresh(provider.jwksUrl, now);
      keys = entry.keys.filter((key) => key.kid === kid);
    }
    if (keys.length !== 1) unauthorized();
    const key = keys[0];
    if (key.alg !== undefined && key.alg !== provider.algorithm) unauthorized();
    if (key.use !== undefined && key.use !== "sig") unauthorized();
    if (key.key_ops !== undefined && (!Array.isArray(key.key_ops) || !key.key_ops.includes("verify"))) unauthorized();
    return key;
  }

  async #refresh(url, now) {
    const existing = this.inflight.get(url);
    if (existing) return existing;
    const operation = this.#fetchAndCache(url, now);
    this.inflight.set(url, operation);
    try {
      return await operation;
    } finally {
      if (this.inflight.get(url) === operation) this.inflight.delete(url);
    }
  }

  async #fetchAndCache(url, now) {
    const controller = new AbortController();
    const deadline = this.setTimeoutImpl(
      () => controller.abort("JWKS deadline exceeded"),
      this.timeoutMilliseconds,
    );
    deadline?.unref?.();
    let response;
    let text;
    let document;
    try {
      response = await this.fetchImpl(url, {
        headers: { accept: "application/json" },
        redirect: "manual",
        signal: controller.signal,
      });
      if (!response?.ok) throw new Error("JWKS response failed");
      text = await readBoundedText(response, MAX_JWKS_BYTES);
      document = JSON.parse(text);
    } catch {
      fail(503, "identity_provider_unavailable", "The identity provider is temporarily unavailable.");
    } finally {
      this.clearTimeoutImpl(deadline);
    }
    if (!document || !Array.isArray(document.keys) || document.keys.length > 128) {
      fail(503, "identity_provider_unavailable", "The identity provider is temporarily unavailable.");
    }
    const entry = {
      keys: document.keys.filter((key) => key && typeof key === "object"),
      expiresAt: now + cacheSeconds(response.headers) * 1000,
      nextUnknownKidRefreshAt: now + 30_000,
    };
    this.cache.set(url, entry);
    return entry;
  }
}

export class JwtVerifier {
  constructor({
    cryptoImpl = globalThis.crypto,
    jwksResolver = new JwksResolver(),
    nowSeconds = () => Math.floor(Date.now() / 1000),
  } = {}) {
    this.cryptoImpl = cryptoImpl;
    this.jwksResolver = jwksResolver;
    this.nowSeconds = nowSeconds;
  }

  peek(token) {
    const parsed = parseJwt(token);
    return { issuer: parsed.claims.iss, audience: parsed.claims.aud };
  }

  async verify(token, provider) {
    const parsed = parseJwt(token);
    assertFixedClaims(parsed, provider, this.nowSeconds());
    const parameters = algorithmParameters(provider.algorithm);
    const jwk = await this.jwksResolver.resolve(provider, parsed.header.kid);
    if (jwk.kty !== parameters.expectedKty) unauthorized();
    let key;
    let valid;
    try {
      key = await this.cryptoImpl.subtle.importKey("jwk", jwk, parameters.import, false, ["verify"]);
      valid = await this.cryptoImpl.subtle.verify(
        parameters.verify,
        key,
        parsed.signature,
        parsed.signingInput,
      );
    } catch {
      unauthorized();
    }
    if (!valid) unauthorized();
    return projectIdentity(parsed.claims, provider);
  }
}

function claimAt(claims, name) {
  if (!name.includes(".")) return claims[name];
  return name.split(".").reduce((value, part) => value && typeof value === "object" ? value[part] : undefined, claims);
}

function projectIdentity(claims, provider) {
  const subject = claimAt(claims, provider.projection.subjectClaim);
  if (typeof subject !== "string" || subject === "" || subject.length > 512) unauthorized();
  const tenantValue = provider.projection.tenantClaim
    ? claimAt(claims, provider.projection.tenantClaim)
    : `provider:${provider.id}`;
  if (typeof tenantValue !== "string" || tenantValue === "" || tenantValue.length > 512) unauthorized();
  let deviceValue = null;
  if (provider.projection.deviceMode !== "disabled") {
    const projected = claimAt(claims, provider.projection.deviceClaim);
    if (projected !== null && projected !== undefined
      && (typeof projected !== "string" || projected === "" || projected.length > 512)) unauthorized();
    if (provider.projection.deviceMode === "required_verified"
      && (typeof projected !== "string" || projected === "")) unauthorized();
    deviceValue = typeof projected === "string" && projected !== "" ? projected : null;
  }
  const rolesValue = provider.projection.rolesClaim ? claimAt(claims, provider.projection.rolesClaim) : [];
  if (rolesValue !== undefined && (!Array.isArray(rolesValue) || rolesValue.length > 256
    || rolesValue.some((role) => typeof role !== "string" || role.length > 256))) {
    unauthorized();
  }
  return Object.freeze({
    providerId: provider.id,
    kind: provider.kind,
    issuer: provider.issuer,
    subject,
    tenant: tenantValue,
    device: deviceValue,
    deviceVerified: deviceValue !== null,
    roles: Object.freeze([...(rolesValue ?? [])]),
  });
}

function credentialFrom(request, provider) {
  const value = request.headers.get(provider.header);
  if (!value) return null;
  if (provider.kind === "oidc") {
    const match = /^Bearer ([A-Za-z0-9._-]+)$/.exec(value);
    if (!match) unauthorized();
    return match[1];
  }
  if (/[\s,]/.test(value)) unauthorized();
  return value;
}

export class Authenticator {
  constructor(config, verifier = new JwtVerifier()) {
    this.config = config;
    this.verifier = verifier;
  }

  async authenticate(request) {
    const presented = new Map();
    for (const provider of this.config.auth.providers) {
      const token = credentialFrom(request, provider);
      if (token) presented.set(provider.header, token);
    }
    if (presented.size === 0) {
      if (this.config.auth.mode === "anonymous" && this.config.environment === "development") {
        return Object.freeze({
          providerId: "development-anonymous",
          kind: "anonymous",
          issuer: "urn:agentweave:development",
          subject: "anonymous",
          tenant: "development",
          device: null,
          deviceVerified: false,
          roles: Object.freeze([]),
        });
      }
      unauthorized();
    }
    if (presented.size !== 1) unauthorized();
    const [[header, token]] = presented;
    const candidates = this.config.auth.providers.filter((provider) => provider.header === header);
    const peeked = this.verifier.peek(token);
    const matching = candidates.filter((provider) => provider.issuer === peeked.issuer
      && audienceMatches(peeked.audience, provider.audience));
    if (matching.length !== 1) unauthorized();
    return this.verifier.verify(token, matching[0]);
  }
}

export const authInternals = Object.freeze({ audienceMatches, parseJwt });
