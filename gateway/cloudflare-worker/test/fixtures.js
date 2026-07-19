import { webcrypto } from "node:crypto";

export const NOW_SECONDS = 1_800_000_000;

export function gatewayConfig(overrides = {}) {
  const value = {
    schemaVersion: 1,
    environment: "production",
    deploymentId: "deployment-test",
    configurationId: "configuration-test",
    auth: {
      mode: "required",
      providers: [{
        id: "oidc-test",
        kind: "oidc",
        issuer: "https://identity.example.test/",
        audience: "agentweave-test",
        jwksUrl: "https://identity.example.test/.well-known/jwks.json",
        algorithm: "RS256",
        clockSkewSeconds: 0,
        projection: {
          tenantClaim: "org.id",
          deviceClaim: "device.id",
          rolesClaim: "roles",
        },
      }],
    },
    entitlements: {
      mode: "static",
    },
    upstream: {
      baseUrl: "https://models.example.test",
      allowedBaseUrls: ["https://models.example.test"],
      secretBinding: "UPSTREAM_API_KEY",
      secretHeader: "authorization",
      secretPrefix: "Bearer ",
      requestHeaders: ["accept"],
      staticHeaders: { "openai-beta": "responses=v1" },
      responseHeaders: ["content-type", "retry-after"],
    },
    routes: [{
      id: "responses",
      path: "/v1/responses",
      upstreamPath: "/v1/responses",
      methods: ["POST"],
      models: ["model-small", "model-large"],
      tokenField: "max_output_tokens",
      allowedToolTypes: ["function"],
      wireProtocol: "agentweave_responses_v1",
      modelUnitWeights: { "model-small": 1, "model-large": 4 },
    }],
    limits: {
      maxBodyBytes: 4096,
      maxOutputTokens: 1024,
      maxTools: 4,
      reservationTtlSeconds: 120,
      requestBaseUnits: 10,
      reservationRetentionSeconds: 2592000,
      idempotencyRetentionSeconds: 31536000,
      maintenanceBatchSize: 100,
    },
    bindings: {
      entitlements: "ENTITLEMENTS",
      concurrency: "CONCURRENCY",
    },
    rateLimit: {
      required: true,
      deploymentBinding: "GATEWAY_DEPLOYMENT_RATE_LIMITER",
      tenantBinding: "GATEWAY_TENANT_RATE_LIMITER",
      subjectBinding: "GATEWAY_RATE_LIMITER",
      deviceBinding: "GATEWAY_DEVICE_RATE_LIMITER",
    },
    concurrency: {
      deploymentLimit: 100,
      tenantLimit: 20,
      deviceLimit: 1,
    },
    controls: {
      modelRequestsEnabled: true,
    },
  };
  return merge(value, overrides);
}

function merge(base, overrides) {
  if (!overrides || typeof overrides !== "object" || Array.isArray(overrides)) return overrides;
  const result = structuredClone(base);
  for (const [key, value] of Object.entries(overrides)) {
    if (value && typeof value === "object" && !Array.isArray(value)
      && result[key] && typeof result[key] === "object" && !Array.isArray(result[key])) {
      result[key] = merge(result[key], value);
    } else {
      result[key] = structuredClone(value);
    }
  }
  return result;
}

function base64Url(value) {
  const bytes = typeof value === "string" ? Buffer.from(value) : Buffer.from(JSON.stringify(value));
  return bytes.toString("base64url");
}

export function jwt({ header = {}, claims = {} } = {}) {
  return [
    base64Url({ alg: "RS256", kid: "key-1", typ: "JWT", ...header }),
    base64Url({
      iss: "https://identity.example.test/",
      aud: "agentweave-test",
      sub: "user-123",
      exp: NOW_SECONDS + 300,
      nbf: NOW_SECONDS - 10,
      org: { id: "tenant-7" },
      device: { id: "device-9" },
      roles: ["member"],
      ...claims,
    }),
    base64Url("test-signature"),
  ].join(".");
}

export function fakeCrypto({ signatureValid = true } = {}) {
  const calls = { imported: [], verified: [] };
  return {
    calls,
    randomUUID: () => "00000000-0000-4000-8000-000000000001",
    subtle: {
      digest: (...args) => webcrypto.subtle.digest(...args),
      async importKey(...args) {
        calls.imported.push(args);
        return { fake: true };
      },
      async verify(...args) {
        calls.verified.push(args);
        return signatureValid;
      },
    },
  };
}

export function jwksResponse(keys = [{
  kty: "RSA",
  kid: "key-1",
  alg: "RS256",
  use: "sig",
  key_ops: ["verify"],
  n: "test-modulus",
  e: "AQAB",
}]) {
  return Response.json({ keys }, {
    headers: { "cache-control": "public, max-age=600" },
  });
}

export function runtimeEnv(config, overrides = {}) {
  return {
    GATEWAY_CONFIG_JSON: JSON.stringify(config),
    UPSTREAM_API_KEY: "server-side-secret",
    ENTITLEMENTS: {
      prepare() {
        return {
          bind() { return this; },
          async first() {
            return {
              schema_version: "3",
              last_cleanup_at: "0",
              deployment_budget_rows: 1,
            };
          },
        };
      },
    },
    CONCURRENCY: {
      idFromName(name) { return name; },
      get() {
        return {
          async fetch() {
            return Response.json({ status: "ready", contract_version: 1 });
          },
        };
      },
    },
    GATEWAY_DEPLOYMENT_RATE_LIMITER: {
      async limit() { return { success: true }; },
    },
    GATEWAY_TENANT_RATE_LIMITER: {
      async limit() { return { success: true }; },
    },
    GATEWAY_RATE_LIMITER: {
      async limit() { return { success: true }; },
    },
    GATEWAY_DEVICE_RATE_LIMITER: {
      async limit() { return { success: true }; },
    },
    GATEWAY_EDGE_RATE_LIMITER: {
      async limit() { return { success: true }; },
    },
    ...overrides,
  };
}
