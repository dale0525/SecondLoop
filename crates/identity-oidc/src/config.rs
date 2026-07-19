use crate::error::{OidcError, Result};
use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;
use url::{Host, Url};

const MAX_PUBLIC_VALUE_BYTES: usize = 2048;
const MAX_SCOPES: usize = 64;

/// The complete public configuration accepted from an Agent App manifest.
/// Client secrets and bearer credentials have no representation here.
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct OidcPublicConfig {
    pub issuer: Url,
    pub client_id: String,
    pub audience: String,
    pub scopes: BTreeSet<String>,
    pub redirect_uri: Url,
}

impl OidcPublicConfig {
    pub fn validate(&self) -> Result<()> {
        validate_network_url(&self.issuer)?;
        if self.issuer.query().is_some() || self.issuer.fragment().is_some() {
            return Err(OidcError::InvalidConfiguration);
        }
        validate_public_value(&self.client_id)?;
        validate_public_value(&self.audience)?;
        validate_redirect_uri(&self.redirect_uri)?;
        if self.scopes.is_empty()
            || self.scopes.len() > MAX_SCOPES
            || !self.scopes.contains("openid")
            || self.scopes.iter().any(|scope| {
                validate_public_value(scope).is_err()
                    || scope.chars().any(char::is_whitespace)
                    || scope.contains(['&', '='])
            })
        {
            return Err(OidcError::InvalidConfiguration);
        }
        Ok(())
    }

    pub(crate) fn validate_for_preset(&self, preset: &OidcPreset) -> Result<()> {
        self.validate()?;
        if preset.resource_parameter == ResourceParameter::Rfc8707AuthorizationAndToken {
            let resource =
                Url::parse(&self.audience).map_err(|_| OidcError::InvalidConfiguration)?;
            if resource.fragment().is_some()
                || !resource.username().is_empty()
                || resource.password().is_some()
                || (resource.cannot_be_a_base() && resource.scheme() != "urn")
            {
                return Err(OidcError::InvalidConfiguration);
            }
        }
        Ok(())
    }

    pub fn discovery_url(&self) -> Result<Url> {
        let mut url = self.issuer.clone();
        let issuer_path = url.path().trim_end_matches('/');
        url.set_path(&format!("{issuer_path}/.well-known/openid-configuration"));
        url.set_query(None);
        url.set_fragment(None);
        validate_same_origin(&self.issuer, &url)?;
        Ok(url)
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum OidcPresetId {
    Generic,
    Auth0,
    Clerk,
    Supabase,
    CloudflareAccess,
}

/// Complete non-secret configuration stored in an Agent App provider binding.
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct OidcPluginPublicConfig {
    pub preset: OidcPresetId,
    pub issuer: Url,
    pub client_id: String,
    pub audience: String,
    pub scopes: BTreeSet<String>,
    pub redirect_uri: Url,
    #[serde(default)]
    pub gateway_algorithm: GatewaySigningAlgorithm,
    #[serde(default)]
    pub gateway_audience: Option<String>,
    #[serde(default)]
    pub gateway_tenant_claim: Option<String>,
    #[serde(default)]
    pub gateway_device_claim: Option<String>,
    #[serde(default)]
    pub gateway_device_mode: GatewayDeviceMode,
    #[serde(default)]
    pub gateway_roles_claim: Option<String>,
    #[serde(default)]
    pub gateway_require_nbf: bool,
}

impl OidcPluginPublicConfig {
    pub fn connection(&self) -> OidcPublicConfig {
        OidcPublicConfig {
            issuer: self.issuer.clone(),
            client_id: self.client_id.clone(),
            audience: self.audience.clone(),
            scopes: self.scopes.clone(),
            redirect_uri: self.redirect_uri.clone(),
        }
    }

    pub fn validate(&self) -> Result<()> {
        let preset = oidc_preset(self.preset);
        self.connection().validate_for_preset(preset)?;
        let algorithm = self.gateway_algorithm.as_str();
        if !preset.allowed_id_token_algorithms.contains(&algorithm) {
            return Err(OidcError::InvalidConfiguration);
        }
        if let Some(audience) = &self.gateway_audience {
            validate_public_value(audience)?;
        }
        for claim in [
            self.gateway_tenant_claim.as_deref(),
            self.gateway_device_claim.as_deref(),
            self.gateway_roles_claim.as_deref(),
        ]
        .into_iter()
        .flatten()
        {
            validate_claim_path(claim)?;
        }
        if (self.gateway_device_mode == GatewayDeviceMode::Disabled)
            != self.gateway_device_claim.is_none()
        {
            return Err(OidcError::InvalidConfiguration);
        }
        Ok(())
    }
}

#[derive(Clone, Copy, Debug, Default, Deserialize, Serialize, PartialEq, Eq)]
pub enum GatewaySigningAlgorithm {
    #[serde(rename = "RS256")]
    #[default]
    Rs256,
    #[serde(rename = "ES256")]
    Es256,
}

impl GatewaySigningAlgorithm {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Rs256 => "RS256",
            Self::Es256 => "ES256",
        }
    }
}

#[derive(Clone, Copy, Debug, Default, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum GatewayDeviceMode {
    RequiredVerified,
    OptionalVerified,
    #[default]
    Disabled,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ResourceParameter {
    None,
    AuthorizationAudience,
    Rfc8707AuthorizationAndToken,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AccessTokenRepresentation {
    Unspecified,
    Opaque,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct EdgeAssertionBoundary {
    pub header_name: &'static str,
    pub is_access_token: bool,
    pub verified_by_gateway_edge: bool,
}

/// Data-only behavior selected by a developer. Cloudflare deployment OAuth is
/// intentionally absent: `CloudflareAccess` describes end-user Managed OAuth.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct OidcPreset {
    pub id: OidcPresetId,
    pub resource_parameter: ResourceParameter,
    pub access_token_representation: AccessTokenRepresentation,
    pub edge_assertion: Option<EdgeAssertionBoundary>,
    pub allowed_id_token_algorithms: &'static [&'static str],
}

const RSA_ONLY: &[&str] = &["RS256"];
const RSA_OR_P256: &[&str] = &["RS256", "ES256"];

pub const OIDC_PRESETS: &[OidcPreset] = &[
    OidcPreset {
        id: OidcPresetId::Generic,
        resource_parameter: ResourceParameter::Rfc8707AuthorizationAndToken,
        access_token_representation: AccessTokenRepresentation::Unspecified,
        edge_assertion: None,
        allowed_id_token_algorithms: RSA_OR_P256,
    },
    OidcPreset {
        id: OidcPresetId::Auth0,
        resource_parameter: ResourceParameter::AuthorizationAudience,
        access_token_representation: AccessTokenRepresentation::Unspecified,
        edge_assertion: None,
        allowed_id_token_algorithms: RSA_ONLY,
    },
    OidcPreset {
        id: OidcPresetId::Clerk,
        resource_parameter: ResourceParameter::Rfc8707AuthorizationAndToken,
        access_token_representation: AccessTokenRepresentation::Opaque,
        edge_assertion: None,
        allowed_id_token_algorithms: RSA_ONLY,
    },
    OidcPreset {
        id: OidcPresetId::Supabase,
        resource_parameter: ResourceParameter::None,
        access_token_representation: AccessTokenRepresentation::Opaque,
        edge_assertion: None,
        allowed_id_token_algorithms: RSA_OR_P256,
    },
    OidcPreset {
        id: OidcPresetId::CloudflareAccess,
        resource_parameter: ResourceParameter::Rfc8707AuthorizationAndToken,
        access_token_representation: AccessTokenRepresentation::Opaque,
        edge_assertion: Some(EdgeAssertionBoundary {
            header_name: "Cf-Access-Jwt-Assertion",
            is_access_token: false,
            verified_by_gateway_edge: true,
        }),
        allowed_id_token_algorithms: RSA_ONLY,
    },
];

pub fn oidc_preset(id: OidcPresetId) -> &'static OidcPreset {
    OIDC_PRESETS
        .iter()
        .find(|preset| preset.id == id)
        .expect("all public preset identifiers have static data")
}

#[derive(Clone, Debug, Deserialize)]
pub(crate) struct DiscoveryDocument {
    pub issuer: Url,
    pub authorization_endpoint: Url,
    pub token_endpoint: Url,
    pub jwks_uri: Url,
    #[serde(default)]
    pub revocation_endpoint: Option<Url>,
    #[serde(default)]
    pub end_session_endpoint: Option<Url>,
    #[serde(default)]
    pub code_challenge_methods_supported: Vec<String>,
    #[serde(default)]
    pub id_token_signing_alg_values_supported: Vec<String>,
}

impl DiscoveryDocument {
    pub fn validate(&self, config: &OidcPublicConfig, preset: &OidcPreset) -> Result<()> {
        if canonical_issuer(&self.issuer)? != canonical_issuer(&config.issuer)?
            || !self
                .code_challenge_methods_supported
                .iter()
                .any(|method| method == "S256")
            || !preset.allowed_id_token_algorithms.iter().any(|allowed| {
                self.id_token_signing_alg_values_supported
                    .iter()
                    .any(|advertised| advertised == allowed)
            })
        {
            return Err(OidcError::InvalidProviderResponse);
        }
        for endpoint in [
            Some(&self.authorization_endpoint),
            Some(&self.token_endpoint),
            Some(&self.jwks_uri),
            self.revocation_endpoint.as_ref(),
            self.end_session_endpoint.as_ref(),
        ]
        .into_iter()
        .flatten()
        {
            validate_network_url(endpoint).map_err(|_| OidcError::InvalidProviderResponse)?;
            validate_same_origin(&config.issuer, endpoint)
                .map_err(|_| OidcError::InvalidProviderResponse)?;
            if endpoint.fragment().is_some() || endpoint.query().is_some() {
                return Err(OidcError::InvalidProviderResponse);
            }
        }
        Ok(())
    }
}

pub(crate) fn validate_same_origin(expected: &Url, actual: &Url) -> Result<()> {
    if expected.scheme() == actual.scheme()
        && expected.host_str().map(str::to_ascii_lowercase)
            == actual.host_str().map(str::to_ascii_lowercase)
        && expected.port_or_known_default() == actual.port_or_known_default()
    {
        Ok(())
    } else {
        Err(OidcError::InvalidConfiguration)
    }
}

fn validate_network_url(url: &Url) -> Result<()> {
    if !url.username().is_empty() || url.password().is_some() || url.host().is_none() {
        return Err(OidcError::InvalidConfiguration);
    }
    let accepted = url.scheme() == "https"
        || (url.scheme() == "http" && url.host().is_some_and(host_is_loopback));
    if accepted {
        Ok(())
    } else {
        Err(OidcError::InvalidConfiguration)
    }
}

fn validate_redirect_uri(url: &Url) -> Result<()> {
    if url.fragment().is_some() || url.query().is_some() || !url.username().is_empty() {
        return Err(OidcError::InvalidConfiguration);
    }
    if url.scheme() == "https" && url.host().is_some() {
        return Ok(());
    }
    if url.scheme() == "http" && url.host().is_some_and(host_is_loopback) {
        return Ok(());
    }
    let private_scheme = url.scheme().contains('.')
        && url
            .scheme()
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'+' | b'-' | b'.'));
    if private_scheme && url.host().is_none() {
        Ok(())
    } else {
        Err(OidcError::InvalidConfiguration)
    }
}

fn canonical_issuer(url: &Url) -> Result<String> {
    validate_network_url(url)?;
    let mut value = url.clone();
    value.set_fragment(None);
    value.set_query(None);
    if value.path() != "/" {
        let path = value.path().trim_end_matches('/').to_owned();
        value.set_path(&path);
    }
    Ok(value.to_string())
}

fn validate_public_value(value: &str) -> Result<()> {
    if value.is_empty()
        || value.len() > MAX_PUBLIC_VALUE_BYTES
        || value != value.trim()
        || value.chars().any(char::is_control)
    {
        Err(OidcError::InvalidConfiguration)
    } else {
        Ok(())
    }
}

fn validate_claim_path(value: &str) -> Result<()> {
    validate_public_value(value)?;
    if value.len() > 256
        || value.split('.').any(|part| {
            part.is_empty()
                || !part
                    .bytes()
                    .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'-'))
        })
    {
        Err(OidcError::InvalidConfiguration)
    } else {
        Ok(())
    }
}

fn host_is_loopback(host: Host<&str>) -> bool {
    match host {
        Host::Domain(domain) => domain.eq_ignore_ascii_case("localhost"),
        Host::Ipv4(address) => address.is_loopback(),
        Host::Ipv6(address) => address.is_loopback(),
    }
}
