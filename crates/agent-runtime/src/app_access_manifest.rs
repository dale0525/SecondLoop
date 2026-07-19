use crate::app_manifest::{AgentAppIdentifier, AgentAppManifest};
use anyhow::Context;
use model_gateway::provider::EndpointType;
use semver::VersionReq;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use url::{Host, Url};

const MAX_PROVIDER_CONFIG_BYTES: usize = 64 * 1024;
const MAX_PROVIDER_CONFIG_DEPTH: usize = 16;
const MAX_MODEL_HEADERS: usize = 32;
const MAX_MODEL_VALUE_LENGTH: usize = 4096;

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum AgentAppIdentityMode {
    LocalSingleUser,
    Required,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum AgentAppEntitlementMode {
    Disabled,
    Required,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentAppProviderBinding {
    pub id: AgentAppIdentifier,
    pub version: VersionReq,
    pub public_config: serde_json::Value,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentAppIdentityConfiguration {
    pub mode: AgentAppIdentityMode,
    pub provider: Option<AgentAppProviderBinding>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentAppEntitlementConfiguration {
    pub mode: AgentAppEntitlementMode,
    pub provider: Option<AgentAppProviderBinding>,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum AgentAppModelConfigurationPolicy {
    UserConfigurable,
    AppManaged,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum AgentAppModelAuthentication {
    None,
    UserIdentity,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentAppModelProfile {
    pub provider_id: AgentAppIdentifier,
    pub endpoint_type: EndpointType,
    pub base_url: String,
    pub model_name: String,
    pub authentication: AgentAppModelAuthentication,
    #[serde(default)]
    pub headers: BTreeMap<String, String>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentAppModelAccess {
    pub configuration_policy: AgentAppModelConfigurationPolicy,
    pub profile: Option<AgentAppModelProfile>,
}

impl AgentAppManifest {
    pub fn effective_model_access(&self) -> AgentAppModelAccess {
        self.model_access.clone().unwrap_or(AgentAppModelAccess {
            configuration_policy: AgentAppModelConfigurationPolicy::UserConfigurable,
            profile: None,
        })
    }

    pub fn effective_identity(&self) -> AgentAppIdentityConfiguration {
        self.identity
            .clone()
            .unwrap_or(AgentAppIdentityConfiguration {
                mode: AgentAppIdentityMode::LocalSingleUser,
                provider: None,
            })
    }

    pub fn effective_entitlements(&self) -> AgentAppEntitlementConfiguration {
        self.entitlements
            .clone()
            .unwrap_or(AgentAppEntitlementConfiguration {
                mode: AgentAppEntitlementMode::Disabled,
                provider: None,
            })
    }

    pub(crate) fn validate_access_configuration(&self) -> anyhow::Result<()> {
        if self.schema_version == 1 {
            anyhow::ensure!(
                self.model_access.is_none()
                    && self.identity.is_none()
                    && self.entitlements.is_none(),
                "agent app manifest schema version 1 cannot declare modelAccess, identity, or entitlements"
            );
            return Ok(());
        }

        let model_access = self.model_access.as_ref().ok_or_else(|| {
            anyhow::anyhow!("agent app manifest schema version 2 requires modelAccess")
        })?;
        let identity = self.identity.as_ref().ok_or_else(|| {
            anyhow::anyhow!("agent app manifest schema version 2 requires identity")
        })?;
        let entitlements = self.entitlements.as_ref().ok_or_else(|| {
            anyhow::anyhow!("agent app manifest schema version 2 requires entitlements")
        })?;

        validate_provider_mode(
            "identity",
            identity.mode == AgentAppIdentityMode::Required,
            identity.provider.as_ref(),
        )?;
        validate_provider_mode(
            "entitlements",
            entitlements.mode == AgentAppEntitlementMode::Required,
            entitlements.provider.as_ref(),
        )?;

        if let Some(profile) = &model_access.profile {
            validate_model_profile(profile)?;
            if profile.authentication == AgentAppModelAuthentication::UserIdentity {
                anyhow::ensure!(
                    identity.mode == AgentAppIdentityMode::Required,
                    "modelAccess user_identity authentication requires identity.mode=required"
                );
            }
        }

        if model_access.configuration_policy == AgentAppModelConfigurationPolicy::AppManaged {
            let profile = model_access.profile.as_ref().ok_or_else(|| {
                anyhow::anyhow!("app-managed model access requires a model profile")
            })?;
            if !model_profile_is_loopback(profile)? {
                anyhow::ensure!(
                    profile.authentication == AgentAppModelAuthentication::UserIdentity,
                    "non-loopback app-managed model access requires user_identity authentication"
                );
                anyhow::ensure!(
                    entitlements.mode == AgentAppEntitlementMode::Required,
                    "non-loopback app-managed model access requires entitlements.mode=required"
                );
            }
        }
        Ok(())
    }
}

fn validate_provider_mode(
    label: &str,
    required: bool,
    provider: Option<&AgentAppProviderBinding>,
) -> anyhow::Result<()> {
    match (required, provider) {
        (true, None) => anyhow::bail!("{label}.mode=required requires a provider"),
        (false, Some(_)) => {
            anyhow::bail!("{label} provider is forbidden when the mode is disabled or local")
        }
        (_, Some(binding)) => validate_provider_binding(label, binding),
        (_, None) => Ok(()),
    }
}

fn validate_provider_binding(label: &str, binding: &AgentAppProviderBinding) -> anyhow::Result<()> {
    anyhow::ensure!(
        binding.public_config.is_object(),
        "{label}.provider.publicConfig must be an object"
    );
    let encoded = serde_json::to_vec(&binding.public_config)
        .with_context(|| format!("failed to encode {label} provider public config"))?;
    anyhow::ensure!(
        encoded.len() <= MAX_PROVIDER_CONFIG_BYTES,
        "{label}.provider.publicConfig exceeds {MAX_PROVIDER_CONFIG_BYTES} bytes"
    );
    validate_json_depth(&binding.public_config, 0, label)
}

fn validate_json_depth(value: &serde_json::Value, depth: usize, label: &str) -> anyhow::Result<()> {
    anyhow::ensure!(
        depth <= MAX_PROVIDER_CONFIG_DEPTH,
        "{label}.provider.publicConfig exceeds the maximum nesting depth"
    );
    match value {
        serde_json::Value::Array(items) => {
            for item in items {
                validate_json_depth(item, depth + 1, label)?;
            }
        }
        serde_json::Value::Object(fields) => {
            for item in fields.values() {
                validate_json_depth(item, depth + 1, label)?;
            }
        }
        _ => {}
    }
    Ok(())
}

fn validate_model_profile(profile: &AgentAppModelProfile) -> anyhow::Result<()> {
    validate_text(
        &profile.model_name,
        "modelAccess.profile.modelName",
        MAX_MODEL_VALUE_LENGTH,
        true,
    )?;
    let url = Url::parse(&profile.base_url)
        .context("modelAccess.profile.baseUrl must be an absolute URL")?;
    anyhow::ensure!(
        matches!(url.scheme(), "http" | "https"),
        "modelAccess.profile.baseUrl must use HTTP or HTTPS"
    );
    anyhow::ensure!(
        url.username().is_empty() && url.password().is_none(),
        "modelAccess.profile.baseUrl must not contain user information"
    );
    anyhow::ensure!(
        url.query().is_none() && url.fragment().is_none(),
        "modelAccess.profile.baseUrl must not contain a query or fragment"
    );
    let is_loopback = url.host().is_some_and(host_is_loopback);
    anyhow::ensure!(
        url.scheme() == "https" || is_loopback,
        "non-loopback modelAccess.profile.baseUrl must use HTTPS"
    );
    anyhow::ensure!(
        profile.headers.len() <= MAX_MODEL_HEADERS,
        "modelAccess.profile.headers must contain at most {MAX_MODEL_HEADERS} entries"
    );
    for (name, value) in &profile.headers {
        validate_text(name, "modelAccess profile header name", 256, true)?;
        validate_text(
            value,
            "modelAccess profile header value",
            MAX_MODEL_VALUE_LENGTH,
            false,
        )?;
        anyhow::ensure!(
            !is_sensitive_header_name(name),
            "modelAccess.profile.headers must not contain sensitive header {name}"
        );
    }
    Ok(())
}

fn model_profile_is_loopback(profile: &AgentAppModelProfile) -> anyhow::Result<bool> {
    let url = Url::parse(&profile.base_url)
        .context("modelAccess.profile.baseUrl must be an absolute URL")?;
    Ok(url.host().is_some_and(host_is_loopback))
}

fn host_is_loopback(host: Host<&str>) -> bool {
    match host {
        Host::Domain(domain) => domain.eq_ignore_ascii_case("localhost"),
        Host::Ipv4(address) => address.is_loopback(),
        Host::Ipv6(address) => address.is_loopback(),
    }
}

fn is_sensitive_header_name(name: &str) -> bool {
    let normalized = name
        .chars()
        .filter(|character| character.is_ascii_alphanumeric())
        .flat_map(char::to_lowercase)
        .collect::<String>();
    normalized == "authorization"
        || normalized == "proxyauthorization"
        || normalized.contains("apikey")
        || normalized.contains("token")
        || normalized.contains("secret")
        || normalized.contains("credential")
}

fn validate_text(value: &str, label: &str, maximum: usize, required: bool) -> anyhow::Result<()> {
    anyhow::ensure!(
        value == value.trim(),
        "{label} must not have surrounding whitespace"
    );
    if required {
        anyhow::ensure!(!value.is_empty(), "{label} cannot be empty");
    }
    anyhow::ensure!(
        value.chars().count() <= maximum,
        "{label} exceeds {maximum} characters"
    );
    anyhow::ensure!(
        !value.chars().any(char::is_control),
        "{label} cannot contain control characters"
    );
    Ok(())
}

pub(crate) fn reject_secret_like_fields(
    value: &serde_json::Value,
    location: &str,
) -> anyhow::Result<()> {
    match value {
        serde_json::Value::Object(object) => {
            for (key, child) in object {
                anyhow::ensure!(
                    !is_secret_like_field_name(key),
                    "agent app manifest must not contain credential field {location}.{key}"
                );
                reject_secret_like_fields(child, &format!("{location}.{key}"))?;
            }
        }
        serde_json::Value::Array(items) => {
            for (index, child) in items.iter().enumerate() {
                reject_secret_like_fields(child, &format!("{location}[{index}]"))?;
            }
        }
        _ => {}
    }
    Ok(())
}

fn is_secret_like_field_name(name: &str) -> bool {
    let normalized = name
        .chars()
        .filter(|character| character.is_ascii_alphanumeric())
        .flat_map(char::to_lowercase)
        .collect::<String>();
    normalized.contains("password")
        || normalized.contains("secret")
        || normalized.contains("oauth")
        || normalized.contains("token")
        || normalized.contains("credential")
        || matches!(
            normalized.as_str(),
            "apikey" | "accesskey" | "privatekey" | "clientkey"
        )
}
