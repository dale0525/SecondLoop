use agent_devkit::{
    DevkitError, DevkitErrorCode, DevkitResult, ProviderDescriptor,
    cloudflare::cloudflare_gateway_provider_descriptor,
};
use agent_runtime::app_manifest::{
    AgentAppModelAccess, AgentAppModelAuthentication, AgentAppModelConfigurationPolicy,
    AgentAppProviderBinding,
};
use identity_oidc::{
    OidcHttpClient, OidcPluginPublicConfig, discover_gateway_verifier,
    oidc_identity_provider_descriptor,
};
use model_gateway::provider::EndpointType;
use serde::Deserialize;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use url::Url;

use crate::developer_control_plane_deployment::DeploymentReferenceInput;

const HTTP_ENTITLEMENT_ID: &str = entitlement_providers::HTTP_ENTITLEMENT_PROVIDER_ID;
const PROJECTION_SECRET_BINDING: &str = "ENTITLEMENT_PROJECTION_SECRET";
const UPSTREAM_SECRET_BINDING: &str = "UPSTREAM_API_KEY";
const BUDGET_PERIOD_END: i64 = 4_102_444_800;

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct GatewayProjectPlanInput {
    pub project_revision: String,
    pub app_id: String,
    pub providers: GatewayProjectProviders,
    pub model_access: AgentAppModelAccess,
    pub deployment: GatewayProjectDeployment,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct GatewayProjectProviders {
    pub identity: AgentAppProviderBinding,
    pub entitlement: AgentAppProviderBinding,
    pub gateway: AgentAppProviderBinding,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct GatewayProjectDeployment {
    pub provider: String,
    pub cloudflare: GatewayCloudflareTarget,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct GatewayCloudflareTarget {
    pub account_id: String,
    pub worker_name: String,
    #[serde(default)]
    pub environment: Option<String>,
}

#[derive(Clone, Debug, PartialEq)]
pub(crate) struct GatewayProjectProjection {
    pub target: DeploymentReferenceInput,
    pub gateway_config: Value,
    pub entitlement_bootstrap: Value,
    pub secret_bindings: BTreeMap<String, String>,
}

#[derive(Clone, Copy, Debug, Default, Deserialize)]
#[serde(rename_all = "snake_case")]
enum UpstreamAuthentication {
    #[default]
    Bearer,
    XApiKey,
    ApiKey,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct CloudflareGatewayPublicConfig {
    upstream_base_url: String,
    #[serde(default)]
    upstream_authentication: UpstreamAuthentication,
    #[serde(default = "default_max_body_bytes")]
    max_body_bytes: u64,
    #[serde(default = "default_max_output_tokens")]
    max_output_tokens: u64,
    #[serde(default = "default_max_tools")]
    max_tools: u64,
    #[serde(default = "default_request_base_units")]
    request_base_units: u64,
    #[serde(default = "default_deployment_max_requests")]
    deployment_max_requests: i64,
    #[serde(default = "default_deployment_max_units")]
    deployment_max_units: i64,
    #[serde(default = "default_deployment_concurrency")]
    deployment_concurrency: u64,
    #[serde(default = "default_tenant_concurrency")]
    tenant_concurrency: u64,
    #[serde(default = "default_device_concurrency")]
    device_concurrency: u64,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct HttpEntitlementGatewayConfig {
    base_url: String,
    #[serde(default = "default_entitlement_timeout")]
    timeout_milliseconds: u64,
    #[serde(default = "default_entitlement_response_bytes")]
    max_response_bytes: u64,
}

pub(crate) async fn project_gateway_plan(
    input: GatewayProjectPlanInput,
    http: &dyn OidcHttpClient,
) -> DevkitResult<GatewayProjectProjection> {
    validate_project_identity(&input)?;
    ensure_provider(
        &input.providers.gateway,
        &cloudflare_gateway_provider_descriptor()?,
    )?;
    ensure_provider(
        &input.providers.identity,
        &oidc_identity_provider_descriptor(),
    )?;
    let entitlement_descriptor = entitlement_providers::entitlement_provider_descriptors()
        .into_iter()
        .find(|descriptor| descriptor.provider_id == HTTP_ENTITLEMENT_ID)
        .ok_or_else(|| DevkitError::new(DevkitErrorCode::Internal, "provider is unavailable"))?;
    ensure_provider(&input.providers.entitlement, &entitlement_descriptor)?;

    let gateway: CloudflareGatewayPublicConfig =
        serde_json::from_value(input.providers.gateway.public_config.clone()).map_err(|_| {
            DevkitError::invalid_configuration("Cloudflare gateway configuration is invalid")
        })?;
    validate_gateway_config(&gateway)?;
    let identity: OidcPluginPublicConfig =
        serde_json::from_value(input.providers.identity.public_config.clone()).map_err(|_| {
            DevkitError::invalid_configuration("OIDC public configuration is invalid")
        })?;
    let verifier = discover_gateway_verifier(&identity, http)
        .await
        .map_err(|_| {
            DevkitError::new(
                DevkitErrorCode::VerificationFailed,
                "OIDC gateway verifier discovery failed",
            )
        })?;
    let entitlement: HttpEntitlementGatewayConfig = serde_json::from_value(
        input.providers.entitlement.public_config.clone(),
    )
    .map_err(|_| {
        DevkitError::invalid_configuration("entitlement projection configuration is invalid")
    })?;
    let projection_url = entitlement_projection_url(&entitlement)?;
    let profile = input.model_access.profile.as_ref().ok_or_else(|| {
        DevkitError::invalid_configuration("app-managed model profile is missing")
    })?;
    let environment = input
        .deployment
        .cloudflare
        .environment
        .clone()
        .unwrap_or_else(|| "production".into());
    if !matches!(
        environment.as_str(),
        "development" | "staging" | "production"
    ) {
        return Err(DevkitError::invalid_configuration(
            "gateway environment is unsupported",
        ));
    }
    let deployment_id = deployment_id(
        &input.app_id,
        &input.deployment.cloudflare.account_id,
        &input.deployment.cloudflare.worker_name,
        &environment,
    );
    let target = DeploymentReferenceInput {
        account_id: input.deployment.cloudflare.account_id,
        deployment_id: deployment_id.clone(),
        worker_name: input.deployment.cloudflare.worker_name,
        environment: Some(environment.clone()),
    };
    let (route_path, upstream_path, token_field, wire_protocol, allowed_tools) =
        route_projection(profile.endpoint_type);
    let (secret_header, secret_prefix) =
        upstream_secret_projection(gateway.upstream_authentication);
    let gateway_config = json!({
        "schemaVersion": 1,
        "environment": environment,
        "deploymentId": deployment_id,
        "configurationId": input.project_revision,
        "auth": { "mode": "required", "providers": [verifier] },
        "entitlements": {
            "mode": "signed_http",
            "projection": {
                "sourceId": HTTP_ENTITLEMENT_ID,
                "url": projection_url,
                "secretBinding": PROJECTION_SECRET_BINDING,
                "timeoutMilliseconds": entitlement.timeout_milliseconds,
                "maxResponseBytes": entitlement.max_response_bytes,
                "refreshBeforeSeconds": 30,
                "maxClockSkewSeconds": 300
            }
        },
        "upstream": {
            "baseUrl": normalized_https_url(&gateway.upstream_base_url, "upstream model URL")?,
            "allowedBaseUrls": [normalized_https_url(&gateway.upstream_base_url, "upstream model URL")?],
            "secretBinding": UPSTREAM_SECRET_BINDING,
            "secretHeader": secret_header,
            "secretPrefix": secret_prefix,
            "requestHeaders": [],
            "staticHeaders": profile.headers,
            "responseHeaders": ["content-type", "retry-after"]
        },
        "routes": [{
            "id": "primary-model",
            "path": route_path,
            "upstreamPath": upstream_path,
            "methods": ["POST"],
            "models": [profile.model_name],
            "tokenField": token_field,
            "allowedToolTypes": allowed_tools,
            "wireProtocol": wire_protocol,
            "modelUnitWeights": { profile.model_name.clone(): 1 }
        }],
        "limits": {
            "maxBodyBytes": gateway.max_body_bytes,
            "maxOutputTokens": gateway.max_output_tokens,
            "maxTools": gateway.max_tools,
            "reservationTtlSeconds": 120,
            "requestBaseUnits": gateway.request_base_units,
            "reservationRetentionSeconds": 2_592_000,
            "idempotencyRetentionSeconds": 31_536_000,
            "maintenanceBatchSize": 100
        },
        "bindings": { "entitlements": "ENTITLEMENTS", "concurrency": "CONCURRENCY" },
        "rateLimit": {
            "required": true,
            "deploymentBinding": "GATEWAY_DEPLOYMENT_RATE_LIMITER",
            "tenantBinding": "GATEWAY_TENANT_RATE_LIMITER",
            "subjectBinding": "GATEWAY_RATE_LIMITER",
            "deviceBinding": "GATEWAY_DEVICE_RATE_LIMITER"
        },
        "concurrency": {
            "deploymentLimit": gateway.deployment_concurrency,
            "tenantLimit": gateway.tenant_concurrency,
            "deviceLimit": gateway.device_concurrency
        },
        "controls": { "modelRequestsEnabled": true }
    });
    let entitlement_bootstrap = json!({
        "schemaVersion": 1,
        "periodStart": 0,
        "periodEnd": BUDGET_PERIOD_END,
        "replaceSubjects": false,
        "deployment": {
            "status": "active",
            "maxRequests": gateway.deployment_max_requests,
            "maxUnits": gateway.deployment_max_units
        },
        "tenants": [],
        "subjects": []
    });
    Ok(GatewayProjectProjection {
        target,
        gateway_config,
        entitlement_bootstrap,
        secret_bindings: BTreeMap::from([
            (
                "entitlement.serviceCredential".into(),
                PROJECTION_SECRET_BINDING.into(),
            ),
            (
                "gateway.upstreamApiKey".into(),
                UPSTREAM_SECRET_BINDING.into(),
            ),
        ]),
    })
}

fn validate_project_identity(input: &GatewayProjectPlanInput) -> DevkitResult<()> {
    let revision_ok = input.project_revision.len() == 64
        && input
            .project_revision
            .bytes()
            .all(|byte| byte.is_ascii_hexdigit());
    let app_ok = !input.app_id.is_empty()
        && input.app_id.len() <= 255
        && !input.app_id.chars().any(char::is_control);
    if !revision_ok || !app_ok || input.deployment.provider != "cloudflare" {
        return Err(DevkitError::invalid_configuration(
            "developer project gateway projection is invalid",
        ));
    }
    if input.model_access.configuration_policy != AgentAppModelConfigurationPolicy::AppManaged
        || input.model_access.profile.as_ref().is_none_or(|profile| {
            profile.authentication != AgentAppModelAuthentication::UserIdentity
        })
    {
        return Err(DevkitError::invalid_configuration(
            "gateway deployment requires app-managed user-identity model access",
        ));
    }
    Ok(())
}

fn ensure_provider(
    selection: &AgentAppProviderBinding,
    descriptor: &ProviderDescriptor,
) -> DevkitResult<()> {
    if selection.id.as_str() != descriptor.provider_id
        || !selection.version.matches(&descriptor.provider_version)
        || !selection.public_config.is_object()
    {
        return Err(DevkitError::new(
            DevkitErrorCode::Unsupported,
            "selected provider is unavailable or incompatible",
        ));
    }
    Ok(())
}

fn validate_gateway_config(config: &CloudflareGatewayPublicConfig) -> DevkitResult<()> {
    normalized_https_url(&config.upstream_base_url, "upstream model URL")?;
    let bounded = (1..=10 * 1024 * 1024).contains(&config.max_body_bytes)
        && (1..=1_000_000).contains(&config.max_output_tokens)
        && config.max_tools <= 1024
        && config.request_base_units <= 1_000_000_000
        && config.deployment_max_requests > 0
        && config.deployment_max_units > 0
        && (1..=1000).contains(&config.deployment_concurrency)
        && (1..=1000).contains(&config.tenant_concurrency)
        && (1..=1000).contains(&config.device_concurrency);
    if bounded {
        Ok(())
    } else {
        Err(DevkitError::invalid_configuration(
            "gateway limits are invalid",
        ))
    }
}

fn entitlement_projection_url(config: &HttpEntitlementGatewayConfig) -> DevkitResult<String> {
    if !(100..=30_000).contains(&config.timeout_milliseconds)
        || !(1024..=1_048_576).contains(&config.max_response_bytes)
    {
        return Err(DevkitError::invalid_configuration(
            "entitlement projection limits are invalid",
        ));
    }
    let mut url = Url::parse(&config.base_url)
        .map_err(|_| DevkitError::invalid_configuration("entitlement service URL is invalid"))?;
    if url.scheme() != "https"
        || url.host().is_none()
        || !url.username().is_empty()
        || url.password().is_some()
        || url.query().is_some()
        || url.fragment().is_some()
        || url.path() != "/"
    {
        return Err(DevkitError::invalid_configuration(
            "entitlement service must be an HTTPS origin",
        ));
    }
    url.set_path(entitlement_providers::GATEWAY_PROJECTION_PATH);
    Ok(url.to_string())
}

fn normalized_https_url(value: &str, label: &str) -> DevkitResult<String> {
    let mut url = Url::parse(value)
        .map_err(|_| DevkitError::invalid_configuration(format!("{label} is invalid")))?;
    if url.scheme() != "https"
        || url.host().is_none()
        || !url.username().is_empty()
        || url.password().is_some()
        || url.query().is_some()
        || url.fragment().is_some()
    {
        return Err(DevkitError::invalid_configuration(format!(
            "{label} must use a credential-free HTTPS URL"
        )));
    }
    let path = url.path().trim_end_matches('/').to_owned();
    url.set_path(if path.is_empty() { "/" } else { &path });
    Ok(url.to_string().trim_end_matches('/').to_owned())
}

fn deployment_id(app_id: &str, account_id: &str, worker_name: &str, environment: &str) -> String {
    let mut digest = Sha256::new();
    digest.update(b"agentweave.gateway.deployment.v1\0");
    for value in [app_id, account_id, worker_name, environment] {
        digest.update((value.len() as u64).to_be_bytes());
        digest.update(value.as_bytes());
    }
    format!("aw-{}", &hex::encode(digest.finalize())[..32])
}

fn route_projection(
    endpoint: EndpointType,
) -> (
    &'static str,
    &'static str,
    &'static str,
    &'static str,
    Value,
) {
    match endpoint {
        EndpointType::Responses => (
            "/v1/responses",
            "/responses",
            "max_output_tokens",
            "agentweave_responses_v1",
            json!(["function"]),
        ),
        EndpointType::ChatCompletions => (
            "/v1/chat/completions",
            "/chat/completions",
            "max_completion_tokens",
            "agentweave_chat_completions_v1",
            json!(["function"]),
        ),
        EndpointType::Completion => (
            "/v1/completions",
            "/completions",
            "max_tokens",
            "agentweave_completion_v1",
            json!([]),
        ),
    }
}

fn upstream_secret_projection(
    authentication: UpstreamAuthentication,
) -> (&'static str, &'static str) {
    match authentication {
        UpstreamAuthentication::Bearer => ("authorization", "Bearer "),
        UpstreamAuthentication::XApiKey => ("x-api-key", ""),
        UpstreamAuthentication::ApiKey => ("api-key", ""),
    }
}

const fn default_max_body_bytes() -> u64 {
    4_194_304
}
const fn default_max_output_tokens() -> u64 {
    16_384
}
const fn default_max_tools() -> u64 {
    128
}
const fn default_request_base_units() -> u64 {
    1
}
const fn default_deployment_max_requests() -> i64 {
    10_000_000
}
const fn default_deployment_max_units() -> i64 {
    1_000_000_000_000
}
const fn default_deployment_concurrency() -> u64 {
    100
}
const fn default_tenant_concurrency() -> u64 {
    20
}
const fn default_device_concurrency() -> u64 {
    1
}
const fn default_entitlement_timeout() -> u64 {
    5_000
}
const fn default_entitlement_response_bytes() -> u64 {
    65_536
}

#[cfg(test)]
mod tests {
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
}
