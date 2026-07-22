use super::*;
use identity_oidc::{OidcHttpError, OidcHttpRequest, OidcHttpResponse};

struct FakeDiscovery;

#[async_trait::async_trait]
impl OidcHttpClient for FakeDiscovery {
    async fn send(&self, request: OidcHttpRequest) -> Result<OidcHttpResponse, OidcHttpError> {
        let final_url = request.url().clone();
        Ok(OidcHttpResponse::new(
            200,
            final_url,
            serde_json::to_vec(&json!({
                "issuer": "https://identity.example.test/",
                "authorization_endpoint": "https://identity.example.test/authorize",
                "token_endpoint": "https://identity.example.test/token",
                "jwks_uri": "https://identity.example.test/jwks.json",
                "code_challenge_methods_supported": ["S256"],
                "id_token_signing_alg_values_supported": ["RS256"]
            }))
            .unwrap(),
        ))
    }
}

#[test]
fn deployment_identity_is_stable_and_delimiter_safe() {
    let first = deployment_id("com.example.app", "account", "worker", "production");
    let second = deployment_id("com.example.app", "account", "worker", "production");
    assert_eq!(first, second);
    assert!(first.starts_with("aw-"));
    assert_eq!(first.len(), 35);
}

#[test]
fn entitlement_projection_requires_an_https_origin() {
    let invalid = HttpEntitlementGatewayConfig {
        base_url: "https://example.test/path".into(),
        timeout_milliseconds: 5_000,
        max_response_bytes: 65_536,
    };
    assert!(entitlement_projection_url(&invalid).is_err());
}

#[test]
fn commerce_webhook_bootstrap_requires_cloudflare_and_creem_only() {
    let input = commerce_bootstrap_input("cloudflare-workers");
    let projected = project_commerce_webhook_bootstrap(&input).unwrap();
    assert_eq!(projected.target.worker_name, "example-entitlements");
    assert_eq!(
        projected.entitlement_config["setup"]["mode"],
        "commerce_webhook"
    );
    assert_eq!(projected.entitlement_config["setup"]["environment"], "test");

    let mut without_creem = input.clone();
    without_creem.providers.commerce = None;
    assert!(project_commerce_webhook_bootstrap(&without_creem).is_err());
    let without_cloudflare = commerce_bootstrap_input("other-gateway");
    assert!(project_commerce_webhook_bootstrap(&without_cloudflare).is_err());
}

#[tokio::test]
async fn firebase_identity_uses_the_pinned_secure_token_verifier() {
    let binding: AgentAppProviderBinding = serde_json::from_value(json!({
        "id": "agentweave.identity.firebase",
        "version": "0.1.0",
        "publicConfig": {
            "projectId": "sample-project-123",
            "firebaseWebKey": "public-web-key",
            "webApplicationId": "1:123:web:abc",
            "authDomain": "sample-project-123.firebaseapp.com"
        }
    }))
    .unwrap();

    let verifier = project_identity_verifier(&binding, &FakeDiscovery)
        .await
        .unwrap();

    assert_eq!(verifier["kind"], "oidc");
    assert_eq!(
        verifier["issuer"],
        "https://securetoken.google.com/sample-project-123"
    );
    assert_eq!(verifier["audience"], "sample-project-123");
    assert_eq!(verifier["projection"]["subjectClaim"], "sub");
}

#[tokio::test]
async fn selected_plugins_are_projected_into_a_gateway_plan() {
    let input: GatewayProjectPlanInput = serde_json::from_value(json!({
        "projectRevision": "a".repeat(64),
        "appId": "com.example.agent",
        "providers": {
            "identity": {
                "id": "agentweave.identity.oidc",
                "version": "0.1.0",
                "publicConfig": {
                    "preset": "auth0",
                    "issuer": "https://identity.example.test/",
                    "clientId": "native-client",
                    "audience": "https://gateway.example.test",
                    "scopes": ["openid", "profile", "offline_access"],
                    "redirectUri": "com.example.agent:/oauth/callback",
                    "gatewayAlgorithm": "RS256",
                    "gatewayTenantClaim": "organization.id"
                }
            },
            "entitlement": {
                "id": "agentweave.entitlements.http",
                "version": "0.1.0",
                "publicConfig": {
                    "baseUrl": "https://entitlements.example.test/",
                    "timeoutMilliseconds": 5000,
                    "maxResponseBytes": 65536
                }
            },
            "gateway": {
                "id": "cloudflare-workers",
                "version": "0.1.0",
                "publicConfig": {
                    "upstreamBaseUrl": "https://api.openai.com/v1",
                    "upstreamAuthentication": "bearer"
                }
            }
        },
        "modelAccess": {
            "configurationPolicy": "app_managed",
            "profile": {
                "providerId": "cloudflare-gateway",
                "endpointType": "responses",
                "baseUrl": "https://gateway.invalid/v1",
                "modelName": "approved-model",
                "authentication": "user_identity",
                "headers": {}
            }
        },
        "deployment": {
            "provider": "cloudflare",
            "cloudflare": {
                "accountId": "0123456789abcdef0123456789abcdef",
                "workerName": "example-agent-gateway",
                "environment": "production"
            }
        }
    }))
    .unwrap();

    let projected = project_gateway_plan(input, &FakeDiscovery).await.unwrap();
    assert_eq!(
        projected.gateway_config["auth"]["providers"][0]["jwksUrl"],
        "https://identity.example.test/jwks.json"
    );
    assert_eq!(
        projected.gateway_config["entitlements"]["mode"],
        "signed_http"
    );
    assert_eq!(
        projected.gateway_config["routes"][0]["path"],
        "/v1/responses"
    );
    assert_eq!(
        projected.secret_bindings["gateway.upstreamApiKey"],
        UPSTREAM_SECRET_BINDING
    );
    assert!(projected.target.deployment_id.starts_with("aw-"));
    assert_eq!(projected.entitlement_bootstrap["subjects"], json!([]));
}

fn commerce_bootstrap_input(gateway_provider_id: &str) -> GatewayProjectPlanInput {
    serde_json::from_value(json!({
        "projectRevision": "a".repeat(64),
        "appId": "com.example.agent",
        "providers": {
            "identity": {
                "id": "agentweave.identity.firebase",
                "version": "0.1.0",
                "publicConfig": {}
            },
            "entitlement": {
                "id": "agentweave.entitlements.cloudflare_policy",
                "version": "0.1.0",
                "publicConfig": {}
            },
            "commerce": {
                "id": "agentweave.commerce.creem",
                "version": "0.1.0",
                "publicConfig": {"environment": "test"}
            },
            "gateway": {
                "id": gateway_provider_id,
                "version": "0.1.0",
                "publicConfig": {}
            }
        },
        "modelAccess": {"configurationPolicy": "user_configurable"},
        "deployment": {
            "provider": "cloudflare",
            "cloudflare": {
                "accountId": "0123456789abcdef0123456789abcdef",
                "gatewayWorkerName": "example-gateway",
                "environment": "production",
                "entitlement": {
                    "mode": "managed_worker",
                    "workerName": "example-entitlements",
                    "policy": {
                        "sourceMode": "commerce_provider",
                        "tenantLimits": {"maxRequests": 0, "maxUnits": 0},
                        "productPlans": []
                    }
                }
            }
        }
    }))
    .unwrap()
}
