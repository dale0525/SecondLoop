# AgentWeave Cloudflare model gateway

This directory is a deployable Cloudflare Worker template for an app-managed model connection. It keeps the upstream provider credential in a Worker secret and accepts model requests only after identity, entitlement, rate, concurrency, route, model, header, body, token, and tool checks succeed.

The template is provider-neutral at its identity boundary. A developer tool can fill the same configuration from a generic OIDC plugin or from Cloudflare Access without changing the Worker implementation.

## Runtime bindings

| Binding | Cloudflare resource | Required behavior |
| --- | --- | --- |
| `GATEWAY_CONFIG_JSON` | Plain Worker variable | Valid schema-versioned non-secret deployment configuration. |
| `UPSTREAM_API_KEY` | Worker secret | Upstream credential. The binding name is selected by `upstream.secretBinding`. |
| `ENTITLEMENTS` | D1 database | Authoritative deployment, tenant, and subject budgets, reservations, dispatch state, tombstones, and settlements. |
| `ENTITLEMENT_PROJECTION_SECRET` | Worker secret | Required only for `signed_http`; HMAC-signs resolver requests and verifies resolver responses. |
| `CONCURRENCY` | Durable Object namespace | Strict deployment, tenant, subject, and optional verified-device active-request leases. |
| `GATEWAY_EDGE_RATE_LIMITER` | Workers Rate Limiting binding | Static pre-configuration edge/IP admission, including public routes. Required remotely. |
| `GATEWAY_DEPLOYMENT_RATE_LIMITER` | Workers Rate Limiting binding | Deployment-wide request-rate admission. Required remotely. |
| `GATEWAY_TENANT_RATE_LIMITER` | Workers Rate Limiting binding | Tenant-wide request-rate admission. Required remotely. |
| `GATEWAY_RATE_LIMITER` | Workers Rate Limiting binding | Subject-wide request-rate admission. Required remotely. |
| `GATEWAY_DEVICE_RATE_LIMITER` | Workers Rate Limiting binding | Optional verified-device request-rate admission, with its own stricter binding limit. Required when any provider enables verified devices. |
| `CF_VERSION_METADATA` | Workers version metadata | Optional version ID and tag in deployment facts. |

The model provider key must never be placed in `GATEWAY_CONFIG_JSON`, `.dev.vars`, an app manifest, or a packaged desktop application. Store it with `wrangler secret put UPSTREAM_API_KEY` or the equivalent Cloudflare API operation.

## Deployment contract

1. Create a D1 database and replace the placeholder `database_id` in `wrangler.toml`.
2. Run `wrangler d1 migrations apply <database-name> --remote`. The versioned files in `migrations/` are the only authoritative path for both empty databases and upgrades. `schema.sql` is a v3 snapshot used by local SQLite tests; do not execute it as a deployment step and then run migrations.
3. Replace all example identity, deployment, audience, model, and Rate Limiting namespace values.
4. Set the upstream credential as a Worker secret.
5. For `static` entitlements, create one current `gateway_deployment_budgets` row for the deployment, one current `gateway_tenant_budgets` row per tenant, and one current `gateway_entitlements` row per subject. For `signed_http`, seed only the deployment budget and configure the HMAC secret; the resolver atomically refreshes versioned tenant, subject, and per-model policy rows in D1. Exactly one row on every active axis must cover the request time.
6. Deploy the Worker and verify `/healthz` and `/.well-known/agentweave-gateway`.

A migrated v1 database is intentionally isolated under `legacy-unbound`. Old reservations and their idempotency hashes remain as long-lived tombstones, but they cannot authorize a v3 request. Because v1 did not record the upstream dispatch boundary, every unfinished v1 reservation is conservatively migrated as `dispatched`; maintenance charges its maximum if it expires. The deployment provider must still quiesce traffic before migration and explicitly reconcile current deployment, tenant, and subject rows before marking the gateway ready.

The checked-in `wrangler.toml` is intentionally a template. An AgentWeave deployment provider should render its values from the developer's plugin choices rather than editing the Worker source.

## Security behavior

- Anonymous mode is accepted only when configuration says `development`, the non-production runtime explicitly binds `LOCAL_DEV_ANONYMOUS=true`, and the incoming request has no Cloudflare `request.cf` metadata. A remotely deployed Worker therefore rejects anonymous traffic even if its JSON is mislabeled. Staging and production require identity. Invalid configuration and missing security bindings fail closed.
- JWT verification pins one configured algorithm, issuer, audience, JWKS URL, and `kid`; it enforces `exp`, enforces `nbf` when present, and can require `nbf` per provider. A provider may project tenant from a signed claim; otherwise the gateway derives a stable single-tenant boundary from the trusted provider configuration. Device policy is explicit: `required_verified`, `optional_verified`, or `disabled`. Only a configured signed assertion claim can create a device boundary; an ordinary request header is never trusted. This keeps Generic OIDC and native Cloudflare Access usable with device controls disabled while allowing a compatible identity plugin to opt into stricter device isolation.
- OIDC bearer tokens and Cloudflare Access assertions use separate fixed headers. Supplying both is rejected.
- A request cannot choose its upstream base URL. The configured base URL must be present in `allowedBaseUrls`, and each method/path/model mapping is exact.
- Every route selects a versioned AgentWeave wire protocol. Unknown top-level or nested fields fail closed, so clients cannot reference account-global upstream Responses, conversations, prompts, files, vector stores, audio, or other server resources through the developer's shared provider credential.
- End-user authorization, cookies, forwarding headers, Cloudflare headers, and every supported upstream secret-header name never reach the model provider. Only explicitly allowed safe headers are copied; developer-fixed non-secret headers are separate and immutable to clients; then the upstream secret header is set by the Worker.
- The Worker reads request bodies through a byte ceiling, accepts JSON objects only, injects or validates the route-specific output-token ceiling, forces one generation, and bounds both `tools` and legacy `functions` arrays.
- Gateway contract v1 permits only ordinary client-executed `function` tools. Paid server-side tools such as web search, MCP, file search, code interpreter, computer use, and image generation fail closed until a future metering contract represents their cost.
- D1 reserves conservative cost units before an upstream call: `requestBaseUnits + modelUnitWeight × (canonical request bytes + maximum output tokens)`. The same transaction verifies deployment-wide, tenant-wide, and subject-wide period budgets before incrementing all three reserved counters. `controls.modelRequestsEnabled=false` is a static deployment kill switch; setting the current deployment budget status to `disabled` or `suspended` is the authoritative D1 kill switch.
- The optional signed HTTP entitlement resolver never deducts usage itself. On a missing or expiring policy row, the Worker sends a nonce-bound HMAC-SHA256 request to one exact HTTPS URL, verifies the bounded response before parsing it, and atomically projects tenant, subject, and per-model policy windows into D1. Timeouts, redirects, signature failures, stale revisions, ambiguous rows, or invalid projections fail closed. D1 remains the only reservation and settlement ledger, so Host and Worker cannot double-charge the same call.
- A reservation is synchronously marked `dispatched` before the upstream fetch. A known HTTP rejection releases all three reserved counters without charging usage. A transport failure, abort, or crash after dispatch is `uncertain` and conservatively charges the enforced maximum. A 2xx response is synchronously committed before any response body is exposed to the client.
- Every model call requires an opaque unique `X-AgentWeave-Request-Id`. D1 stores only its deployment/tenant/subject-bound hash with the canonical request hash, so a timeout retry cannot invoke or charge the upstream twice; reuse for different input is a conflict. Detailed reservations have a shorter retention window, while lightweight tombstones retain the request hash for the longer configured retry horizon. Response bodies are not retained for replay.
- Durable Objects acquire deployment, tenant, and subject leases with independent configured ceilings. When the provider supplies a verified device claim, a fourth device lease uses its own lower ceiling and a key that cannot be multiplied by switching subjects. All acquired leases remain until the upstream response stream closes or is cancelled; partial acquisition is compensated before returning an error. The four Rate Limiting bindings enforce the same independent axes before body parsing.
- A scheduled maintenance handler reconciles only a bounded candidate page per run. Expired pre-dispatch reservations are refunded; expired dispatched reservations become `uncertain` and charge the maximum. Finalized detail rows and expired tombstones are deleted in separate bounded batches.
- Upstream error bodies, tokens, request headers, prompts, and model response bodies are never written by application logging. Public errors contain a stable code and a random request ID only.

## Public facts

- `GET /healthz` verifies D1 schema v3, a current deployment budget row, and a no-side-effect Durable Object health method before reporting readiness. The deep result is cached briefly after the static edge limiter admits the request. It reports contract/deployment versions and the last cleanup time without making a paid upstream request.
- `GET /version` reports the Worker and gateway-contract versions.
- `GET /.well-known/agentweave-gateway` reports non-secret deployment, auth-provider kinds, route/model policy, limit ceilings, and enforcement modes.
- `GET /.well-known/agentweave/gateway-health` validates one configured final-user assertion, applies identity rate limiting, verifies D1/DO readiness, and returns the active Worker version without reserving quota or calling the model provider.

All other paths pass through authentication and the complete authorization pipeline.

## Local verification

From this directory, using the repository's pixi-managed Node runtime:

```sh
pixi run node --check src/*.js
pixi run node --test test/*.test.js
```

The tests use fake JWKS and cryptography projections, a local in-memory SQLite adapter for the D1 transaction contract, fake Rate Limiting and Durable Object bindings, and in-memory streaming responses. They do not use real network endpoints or credentials.
