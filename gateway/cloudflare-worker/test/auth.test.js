import assert from "node:assert/strict";
import test from "node:test";

import { Authenticator, JwksResolver, JwtVerifier } from "../src/auth.js";
import { parseGatewayConfig } from "../src/config.js";
import { GatewayError } from "../src/errors.js";
import {
  NOW_SECONDS,
  fakeCrypto,
  gatewayConfig,
  jwksResponse,
  jwt,
} from "./fixtures.js";

function verifier({ signatureValid = true, keys, fetchCalls = [] } = {}) {
  const cryptoImpl = fakeCrypto({ signatureValid });
  const resolver = new JwksResolver({
    fetchImpl: async (url, options) => {
      fetchCalls.push({ url, options });
      return jwksResponse(keys);
    },
    nowMilliseconds: () => NOW_SECONDS * 1000,
  });
  return {
    cryptoImpl,
    verifier: new JwtVerifier({
      cryptoImpl,
      jwksResolver: resolver,
      nowSeconds: () => NOW_SECONDS,
    }),
  };
}

test("generic OIDC verifies fixed JOSE and claims before projecting bounded identity", async () => {
  const config = parseGatewayConfig(gatewayConfig());
  const fetchCalls = [];
  const { cryptoImpl, verifier: jwtVerifier } = verifier({ fetchCalls });
  const authenticator = new Authenticator(config, jwtVerifier);
  const token = jwt();

  const identity = await authenticator.authenticate(new Request("https://gateway.test/v1/responses", {
    headers: { authorization: `Bearer ${token}` },
  }));
  assert.deepEqual(identity, {
    providerId: "oidc-test",
    kind: "oidc",
    issuer: "https://identity.example.test/",
    subject: "user-123",
    tenant: "tenant-7",
    device: "device-9",
    deviceVerified: true,
    roles: ["member"],
  });
  assert.equal(fetchCalls.length, 1);
  assert.equal(fetchCalls[0].url, "https://identity.example.test/.well-known/jwks.json");
  assert.equal(fetchCalls[0].options.redirect, "manual");
  assert.equal(cryptoImpl.calls.imported[0][2].name, "RSASSA-PKCS1-v1_5");
  assert.equal(cryptoImpl.calls.verified.length, 1);

  await authenticator.authenticate(new Request("https://gateway.test/v1/responses", {
    headers: { authorization: `Bearer ${token}` },
  }));
  assert.equal(fetchCalls.length, 1, "JWKS is cached within its bounded max-age");
});

test("concurrent JWT verification coalesces the initial JWKS fetch", async () => {
  const config = parseGatewayConfig(gatewayConfig());
  let fetchCount = 0;
  let releaseFetch;
  const resolver = new JwksResolver({
    fetchImpl: async () => {
      fetchCount += 1;
      await new Promise((resolve) => { releaseFetch = resolve; });
      return jwksResponse();
    },
    nowMilliseconds: () => NOW_SECONDS * 1000,
  });
  const jwtVerifier = new JwtVerifier({
    cryptoImpl: fakeCrypto(),
    jwksResolver: resolver,
    nowSeconds: () => NOW_SECONDS,
  });
  const authenticator = new Authenticator(config, jwtVerifier);
  const authenticate = () => authenticator.authenticate(new Request("https://gateway.test", {
    headers: { authorization: `Bearer ${jwt()}` },
  }));
  const requests = [authenticate(), authenticate()];
  await new Promise((resolve) => setTimeout(resolve, 0));
  assert.equal(fetchCount, 1);
  releaseFetch();
  await Promise.all(requests);
});

test("JWKS fetch and body processing have a hard deadline", async () => {
  let deadlineCallback;
  let cleared = false;
  const resolver = new JwksResolver({
    fetchImpl: async (_url, init) => new Promise((_resolve, reject) => {
      init.signal.addEventListener("abort", () => reject(new Error("aborted")));
    }),
    nowMilliseconds: () => NOW_SECONDS * 1000,
    setTimeoutImpl(callback, milliseconds) {
      assert.equal(milliseconds, 5_000);
      deadlineCallback = callback;
      return { unref() {} };
    },
    clearTimeoutImpl() {
      cleared = true;
    },
  });
  const config = parseGatewayConfig(gatewayConfig());
  const operation = resolver.resolve(config.auth.providers[0], "key-1");
  await new Promise((resolve) => setTimeout(resolve, 0));
  deadlineCallback();
  await assert.rejects(
    operation,
    (error) => error.code === "identity_provider_unavailable" && error.status === 503,
  );
  assert.equal(cleared, true);
});

test("Cloudflare Access assertion uses its dedicated header and identity projection", async () => {
  const raw = gatewayConfig({
    auth: {
      providers: [{
        id: "access-test",
        kind: "cloudflare_access",
        issuer: "https://team.cloudflareaccess.com",
        audience: "access-audience",
        jwksUrl: "https://team.cloudflareaccess.com/cdn-cgi/access/certs",
        algorithm: "RS256",
        clockSkewSeconds: 0,
        projection: {
          subjectClaim: "sub",
          tenantClaim: "org_id",
          deviceClaim: "device_id",
        },
      }],
    },
  });
  const config = parseGatewayConfig(raw);
  const { verifier: jwtVerifier } = verifier();
  const token = jwt({
    claims: {
      iss: "https://team.cloudflareaccess.com",
      aud: ["access-audience"],
      sub: "access-user",
      org_id: "access-tenant",
      device_id: "access-device",
    },
  });
  const identity = await new Authenticator(config, jwtVerifier).authenticate(new Request("https://gateway.test", {
    headers: { "cf-access-jwt-assertion": token },
  }));
  assert.equal(identity.kind, "cloudflare_access");
  assert.equal(identity.subject, "access-user");
  assert.equal(identity.deviceVerified, true);
});

test("identity providers can use a trusted configured tenant and disable device isolation", async () => {
  const provider = {
    ...gatewayConfig().auth.providers[0],
    projection: {
      subjectClaim: "sub",
      rolesClaim: "roles",
      deviceMode: "disabled",
    },
  };
  const config = parseGatewayConfig(gatewayConfig({ auth: { providers: [provider] } }));
  const identity = await new Authenticator(config, verifier().verifier).authenticate(new Request(
    "https://gateway.test",
    {
      headers: {
        authorization: `Bearer ${jwt({ claims: { org: undefined, device: undefined } })}`,
      },
    },
  ));
  assert.equal(identity.tenant, "provider:oidc-test");
  assert.equal(identity.device, null);
  assert.equal(identity.deviceVerified, false);
});

test("optional verified device mode accepts an assertion without the configured claim", async () => {
  const provider = {
    ...gatewayConfig().auth.providers[0],
    projection: {
      subjectClaim: "sub",
      tenantClaim: "org.id",
      deviceClaim: "device.id",
      deviceMode: "optional_verified",
    },
  };
  const config = parseGatewayConfig(gatewayConfig({ auth: { providers: [provider] } }));
  const identity = await new Authenticator(config, verifier().verifier).authenticate(new Request(
    "https://gateway.test",
    {
      headers: { authorization: `Bearer ${jwt({ claims: { device: undefined } })}` },
    },
  ));
  assert.equal(identity.tenant, "tenant-7");
  assert.equal(identity.device, null);
  assert.equal(identity.deviceVerified, false);
});

const invalidCases = [
  ["algorithm", { header: { alg: "none" } }],
  ["issuer", { claims: { iss: "https://attacker.invalid/" } }],
  ["audience", { claims: { aud: "some-other-app" } }],
  ["expiration", { claims: { exp: NOW_SECONDS } }],
  ["not-before", { claims: { nbf: NOW_SECONDS + 1 } }],
  ["kid", { header: { kid: "unknown-key" } }],
];

for (const [name, tokenOverrides] of invalidCases) {
  test(`JWT rejects mismatched ${name}`, async () => {
    const config = parseGatewayConfig(gatewayConfig());
    const fetchCalls = [];
    const { verifier: jwtVerifier } = verifier({ fetchCalls });
    const request = new Request("https://gateway.test", {
      headers: { authorization: `Bearer ${jwt(tokenOverrides)}` },
    });
    await assert.rejects(
      new Authenticator(config, jwtVerifier).authenticate(request),
      (error) => error instanceof GatewayError && error.status === 401 && error.code === "authentication_failed",
    );
    if (name === "kid") {
      await assert.rejects(
        new Authenticator(config, jwtVerifier).authenticate(new Request("https://gateway.test", {
          headers: { authorization: `Bearer ${jwt(tokenOverrides)}` },
        })),
        (error) => error.code === "authentication_failed",
      );
      assert.equal(fetchCalls.length, 1, "unknown kids cannot force unbounded JWKS refreshes");
    }
  });
}

test("JWT rejects invalid signatures and ambiguous credential headers", async () => {
  const config = parseGatewayConfig(gatewayConfig({
    auth: {
      providers: [
        gatewayConfig().auth.providers[0],
        {
          id: "access-test",
          kind: "cloudflare_access",
          issuer: "https://team.cloudflareaccess.com",
          audience: "access-audience",
          jwksUrl: "https://team.cloudflareaccess.com/cdn-cgi/access/certs",
          algorithm: "RS256",
          projection: {
            tenantClaim: "org_id",
            deviceClaim: "device_id",
          },
        },
      ],
    },
  }));
  const badVerifier = verifier({ signatureValid: false }).verifier;
  await assert.rejects(
    new Authenticator(config, badVerifier).authenticate(new Request("https://gateway.test", {
      headers: { authorization: `Bearer ${jwt()}` },
    })),
    (error) => error.code === "authentication_failed",
  );

  await assert.rejects(
    new Authenticator(config, verifier().verifier).authenticate(new Request("https://gateway.test", {
      headers: {
        authorization: `Bearer ${jwt()}`,
        "cf-access-jwt-assertion": jwt({
          claims: {
            iss: "https://team.cloudflareaccess.com",
            aud: "access-audience",
            org_id: "access-tenant",
            device_id: "access-device",
          },
        }),
      },
    })),
    (error) => error.code === "authentication_failed",
  );
});

test("production anonymous mode is rejected during configuration", () => {
  assert.throws(
    () => parseGatewayConfig(gatewayConfig({ auth: { mode: "anonymous", providers: [] } })),
    (error) => error instanceof GatewayError
      && error.status === 503
      && error.code === "gateway_misconfigured"
      && !error.publicMessage.includes("anonymous"),
  );
  assert.throws(
    () => parseGatewayConfig(gatewayConfig({
      environment: "staging",
      auth: { mode: "anonymous", providers: [] },
    })),
    (error) => error.code === "gateway_misconfigured",
  );
});
