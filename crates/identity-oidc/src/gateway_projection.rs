use crate::{
    DiscoveryDocument, GatewayDeviceMode, OIDC_IDENTITY_PROVIDER_ID, OidcError, OidcHttpClient,
    OidcHttpRequest, OidcPluginPublicConfig, OidcPresetId, Result, oidc_preset,
    provider::send_pinned,
};
use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum GatewayIdentityKind {
    Oidc,
    CloudflareAccess,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct GatewayClaimProjection {
    pub subject_claim: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tenant_claim: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub device_claim: Option<String>,
    pub device_mode: GatewayDeviceMode,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub roles_claim: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct GatewayVerifierProjection {
    pub id: String,
    pub kind: GatewayIdentityKind,
    pub issuer: String,
    pub audience: String,
    pub jwks_url: String,
    pub algorithm: String,
    pub header: String,
    pub require_nbf: bool,
    pub clock_skew_seconds: u32,
    pub projection: GatewayClaimProjection,
}

pub async fn discover_gateway_verifier(
    config: &OidcPluginPublicConfig,
    http: &dyn OidcHttpClient,
) -> Result<GatewayVerifierProjection> {
    config.validate()?;
    let connection = config.connection();
    let preset = oidc_preset(config.preset);
    let discovery_url = connection.discovery_url()?;
    let response = send_pinned(http, OidcHttpRequest::get(discovery_url)).await?;
    if response.status() != 200 {
        return Err(OidcError::Unavailable);
    }
    let discovery: DiscoveryDocument =
        serde_json::from_slice(response.body()).map_err(|_| OidcError::InvalidProviderResponse)?;
    discovery.validate(&connection, preset)?;
    let algorithm = config.gateway_algorithm.as_str();
    if !discovery
        .id_token_signing_alg_values_supported
        .iter()
        .any(|advertised| advertised == algorithm)
        || discovery.issuer.scheme() != "https"
        || discovery.jwks_uri.scheme() != "https"
    {
        return Err(OidcError::InvalidProviderResponse);
    }
    let cloudflare_access = config.preset == OidcPresetId::CloudflareAccess;
    Ok(GatewayVerifierProjection {
        id: OIDC_IDENTITY_PROVIDER_ID.into(),
        kind: if cloudflare_access {
            GatewayIdentityKind::CloudflareAccess
        } else {
            GatewayIdentityKind::Oidc
        },
        issuer: discovery.issuer.to_string(),
        audience: config
            .gateway_audience
            .clone()
            .unwrap_or_else(|| config.audience.clone()),
        jwks_url: discovery.jwks_uri.to_string(),
        algorithm: algorithm.into(),
        header: if cloudflare_access {
            "cf-access-jwt-assertion".into()
        } else {
            "authorization".into()
        },
        require_nbf: config.gateway_require_nbf,
        clock_skew_seconds: 60,
        projection: GatewayClaimProjection {
            subject_claim: "sub".into(),
            tenant_claim: config.gateway_tenant_claim.clone(),
            device_claim: config.gateway_device_claim.clone(),
            device_mode: config.gateway_device_mode,
            roles_claim: config.gateway_roles_claim.clone(),
        },
    })
}
