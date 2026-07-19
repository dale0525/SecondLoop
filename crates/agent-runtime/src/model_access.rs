use crate::entitlement::EntitlementMode;
use crate::identity::IdentityMode;
use model_gateway::provider::EndpointType;
use serde::{Deserialize, Deserializer, Serialize, Serializer, de, ser};
use std::collections::BTreeMap;
use std::fmt;
use thiserror::Error;
use url::{Host, Url};

const MAX_IDENTIFIER_BYTES: usize = 255;
const MAX_MODEL_VALUE_BYTES: usize = 4096;
const MAX_HEADERS: usize = 32;

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ModelConfigurationPolicy {
    UserConfigurable,
    AppManaged,
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ModelAuthentication {
    None,
    UserIdentity,
}

/// Public model routing metadata. Secret values and credential references are
/// intentionally absent; a trusted host transport supplies authentication.
#[derive(Clone, PartialEq, Eq)]
pub struct ModelAccessProfile {
    pub provider_id: String,
    pub endpoint_type: EndpointType,
    pub base_url: String,
    pub model_name: String,
    pub authentication: ModelAuthentication,
    pub headers: BTreeMap<String, String>,
}

impl fmt::Debug for ModelAccessProfile {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("ModelAccessProfile")
            .field("provider_id", &self.provider_id)
            .field("endpoint_type", &self.endpoint_type)
            .field("base_url", &self.base_url)
            .field("model_name", &self.model_name)
            .field("authentication", &self.authentication)
            .field("header_names", &self.headers.keys().collect::<Vec<_>>())
            .finish()
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct ModelAccessProfileWire {
    provider_id: String,
    endpoint_type: EndpointType,
    base_url: String,
    model_name: String,
    authentication: ModelAuthentication,
    #[serde(default)]
    headers: BTreeMap<String, String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ModelAccessProfileRef<'a> {
    provider_id: &'a str,
    endpoint_type: EndpointType,
    base_url: &'a str,
    model_name: &'a str,
    authentication: ModelAuthentication,
    headers: &'a BTreeMap<String, String>,
}

impl Serialize for ModelAccessProfile {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        self.validate().map_err(ser::Error::custom)?;
        ModelAccessProfileRef {
            provider_id: &self.provider_id,
            endpoint_type: self.endpoint_type,
            base_url: &self.base_url,
            model_name: &self.model_name,
            authentication: self.authentication,
            headers: &self.headers,
        }
        .serialize(serializer)
    }
}

impl<'de> Deserialize<'de> for ModelAccessProfile {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let wire = ModelAccessProfileWire::deserialize(deserializer)?;
        let profile = Self {
            provider_id: wire.provider_id,
            endpoint_type: wire.endpoint_type,
            base_url: wire.base_url,
            model_name: wire.model_name,
            authentication: wire.authentication,
            headers: wire.headers,
        };
        profile.validate().map_err(de::Error::custom)?;
        Ok(profile)
    }
}

impl ModelAccessProfile {
    pub fn validate(&self) -> Result<(), ModelAccessError> {
        validate_identifier(&self.provider_id, "provider_id")?;
        validate_text(&self.base_url, "base_url", MAX_MODEL_VALUE_BYTES, true)?;
        validate_text(&self.model_name, "model_name", MAX_MODEL_VALUE_BYTES, true)?;
        let url =
            Url::parse(&self.base_url).map_err(|_| ModelAccessError::InvalidField("base_url"))?;
        if !matches!(url.scheme(), "http" | "https")
            || url.host().is_none()
            || !url.username().is_empty()
            || url.password().is_some()
            || url.query().is_some()
            || url.fragment().is_some()
        {
            return Err(ModelAccessError::InvalidField("base_url"));
        }
        if url.scheme() != "https" && !url.host().is_some_and(host_is_loopback) {
            return Err(ModelAccessError::InsecureRemoteEndpoint);
        }
        if self.headers.len() > MAX_HEADERS {
            return Err(ModelAccessError::TooManyHeaders);
        }
        for (name, value) in &self.headers {
            validate_header_name(name)?;
            validate_text(value, "header value", MAX_MODEL_VALUE_BYTES, false)?;
            if is_sensitive_header_name(name) {
                return Err(ModelAccessError::SensitiveHeader(name.clone()));
            }
        }
        Ok(())
    }

    pub fn is_loopback(&self) -> Result<bool, ModelAccessError> {
        self.validate()?;
        let url =
            Url::parse(&self.base_url).map_err(|_| ModelAccessError::InvalidField("base_url"))?;
        Ok(url.host().is_some_and(host_is_loopback))
    }
}

/// Runtime policy compiled from the App manifest and selected plugins.
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ModelAccessPolicy {
    pub configuration_policy: ModelConfigurationPolicy,
    pub profile: Option<ModelAccessProfile>,
    pub identity_mode: IdentityMode,
    pub entitlement_mode: EntitlementMode,
}

impl ModelAccessPolicy {
    pub fn validate(&self) -> Result<(), ModelAccessError> {
        if let Some(profile) = &self.profile {
            profile.validate()?;
            if profile.authentication == ModelAuthentication::UserIdentity
                && self.identity_mode != IdentityMode::Required
            {
                return Err(ModelAccessError::UserIdentityRequiresIdentityProvider);
            }
        }

        if self.configuration_policy == ModelConfigurationPolicy::AppManaged {
            let profile = self
                .profile
                .as_ref()
                .ok_or(ModelAccessError::ManagedProfileRequired)?;
            if !profile.is_loopback()? {
                if profile.authentication != ModelAuthentication::UserIdentity {
                    return Err(ModelAccessError::RemoteManagedProfileRequiresUserIdentity);
                }
                if self.entitlement_mode != EntitlementMode::Required {
                    return Err(ModelAccessError::RemoteManagedProfileRequiresEntitlements);
                }
            }
        }
        Ok(())
    }

    /// Selects an effective profile while enforcing the packaged override
    /// policy. A user profile can never request host identity injection.
    pub fn resolve(
        &self,
        user_profile: Option<&ModelAccessProfile>,
    ) -> Result<ResolvedModelAccess, ModelAccessError> {
        self.validate()?;
        match self.configuration_policy {
            ModelConfigurationPolicy::AppManaged => {
                if user_profile.is_some() {
                    return Err(ModelAccessError::UserOverrideForbidden);
                }
                Ok(ResolvedModelAccess {
                    profile: self
                        .profile
                        .clone()
                        .ok_or(ModelAccessError::ManagedProfileRequired)?,
                    source: ModelProfileSource::App,
                    identity_mode: self.identity_mode,
                    entitlement_mode: self.entitlement_mode,
                })
            }
            ModelConfigurationPolicy::UserConfigurable => {
                let (profile, source) = match user_profile {
                    Some(profile) => (profile, ModelProfileSource::User),
                    None => (
                        self.profile
                            .as_ref()
                            .ok_or(ModelAccessError::EffectiveProfileRequired)?,
                        ModelProfileSource::App,
                    ),
                };
                profile.validate()?;
                if source == ModelProfileSource::User
                    && profile.authentication == ModelAuthentication::UserIdentity
                {
                    return Err(ModelAccessError::UserProfileCannotUseAppIdentity);
                }
                Ok(ResolvedModelAccess {
                    profile: profile.clone(),
                    source,
                    identity_mode: self.identity_mode,
                    entitlement_mode: self.entitlement_mode,
                })
            }
        }
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ModelProfileSource {
    App,
    User,
}

/// The resolved result remains public metadata; model credentials are supplied
/// out of band by the trusted host selected for this profile.
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ResolvedModelAccess {
    pub profile: ModelAccessProfile,
    pub source: ModelProfileSource,
    pub identity_mode: IdentityMode,
    pub entitlement_mode: EntitlementMode,
}

#[derive(Clone, Debug, Error, PartialEq, Eq)]
pub enum ModelAccessError {
    #[error("invalid model access field: {0}")]
    InvalidField(&'static str),
    #[error("non-loopback model endpoint must use HTTPS")]
    InsecureRemoteEndpoint,
    #[error("model profile contains too many public headers")]
    TooManyHeaders,
    #[error("model profile header must not carry secrets: {0}")]
    SensitiveHeader(String),
    #[error("app-managed model access requires a profile")]
    ManagedProfileRequired,
    #[error("user-identity model authentication requires an identity provider")]
    UserIdentityRequiresIdentityProvider,
    #[error("remote app-managed model access requires user identity authentication")]
    RemoteManagedProfileRequiresUserIdentity,
    #[error("remote app-managed model access requires entitlements")]
    RemoteManagedProfileRequiresEntitlements,
    #[error("app-managed model access forbids user profile overrides")]
    UserOverrideForbidden,
    #[error("model access has no effective profile")]
    EffectiveProfileRequired,
    #[error("a user-supplied profile cannot request App identity injection")]
    UserProfileCannotUseAppIdentity,
}

fn validate_identifier(value: &str, field: &'static str) -> Result<(), ModelAccessError> {
    let valid = !value.is_empty()
        && value.len() <= MAX_IDENTIFIER_BYTES
        && value == value.trim()
        && value.split('.').all(|segment| {
            !segment.is_empty()
                && segment.len() <= 63
                && segment
                    .bytes()
                    .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_'))
        });
    if valid {
        Ok(())
    } else {
        Err(ModelAccessError::InvalidField(field))
    }
}

fn validate_text(
    value: &str,
    field: &'static str,
    maximum_bytes: usize,
    required: bool,
) -> Result<(), ModelAccessError> {
    let valid = (!required || !value.is_empty())
        && value.len() <= maximum_bytes
        && value == value.trim()
        && !value.chars().any(char::is_control);
    if valid {
        Ok(())
    } else {
        Err(ModelAccessError::InvalidField(field))
    }
}

fn validate_header_name(name: &str) -> Result<(), ModelAccessError> {
    let valid = !name.is_empty()
        && name.len() <= 256
        && name.bytes().all(|byte| {
            byte.is_ascii_alphanumeric()
                || matches!(
                    byte,
                    b'!' | b'#'
                        | b'$'
                        | b'%'
                        | b'&'
                        | b'\''
                        | b'*'
                        | b'+'
                        | b'-'
                        | b'.'
                        | b'^'
                        | b'_'
                        | b'`'
                        | b'|'
                        | b'~'
                )
        });
    if valid {
        Ok(())
    } else {
        Err(ModelAccessError::InvalidField("header name"))
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

fn host_is_loopback(host: Host<&str>) -> bool {
    match host {
        Host::Domain(domain) => domain.eq_ignore_ascii_case("localhost"),
        Host::Ipv4(address) => address.is_loopback(),
        Host::Ipv6(address) => address.is_loopback(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn remote_profile(authentication: ModelAuthentication) -> ModelAccessProfile {
        ModelAccessProfile {
            provider_id: "com.example.gateway".into(),
            endpoint_type: EndpointType::Responses,
            base_url: "https://gateway.example.com/v1".into(),
            model_name: "gpt-test".into(),
            authentication,
            headers: BTreeMap::from([("X-Client-Version".into(), "desktop-1".into())]),
        }
    }

    fn managed_remote_policy() -> ModelAccessPolicy {
        ModelAccessPolicy {
            configuration_policy: ModelConfigurationPolicy::AppManaged,
            profile: Some(remote_profile(ModelAuthentication::UserIdentity)),
            identity_mode: IdentityMode::Required,
            entitlement_mode: EntitlementMode::Required,
        }
    }

    #[test]
    fn remote_app_managed_profile_requires_identity_and_entitlements() {
        assert!(managed_remote_policy().validate().is_ok());

        let mut no_identity = managed_remote_policy();
        no_identity.profile.as_mut().unwrap().authentication = ModelAuthentication::None;
        assert_eq!(
            no_identity.validate().unwrap_err(),
            ModelAccessError::RemoteManagedProfileRequiresUserIdentity
        );

        let mut no_entitlements = managed_remote_policy();
        no_entitlements.entitlement_mode = EntitlementMode::Disabled;
        assert_eq!(
            no_entitlements.validate().unwrap_err(),
            ModelAccessError::RemoteManagedProfileRequiresEntitlements
        );
    }

    #[test]
    fn loopback_app_managed_profile_can_be_unauthenticated() {
        let policy = ModelAccessPolicy {
            configuration_policy: ModelConfigurationPolicy::AppManaged,
            profile: Some(ModelAccessProfile {
                provider_id: "local".into(),
                endpoint_type: EndpointType::ChatCompletions,
                base_url: "http://127.0.0.1:11434/v1".into(),
                model_name: "qwen".into(),
                authentication: ModelAuthentication::None,
                headers: BTreeMap::new(),
            }),
            identity_mode: IdentityMode::LocalSingleUser,
            entitlement_mode: EntitlementMode::Disabled,
        };

        assert!(policy.validate().is_ok());
        assert_eq!(
            policy.resolve(None).unwrap().source,
            ModelProfileSource::App
        );
    }

    #[test]
    fn app_managed_policy_rejects_every_user_override() {
        let policy = managed_remote_policy();
        let user = ModelAccessProfile {
            authentication: ModelAuthentication::None,
            ..remote_profile(ModelAuthentication::None)
        };

        assert_eq!(
            policy.resolve(Some(&user)).unwrap_err(),
            ModelAccessError::UserOverrideForbidden
        );
    }

    #[test]
    fn user_configurable_policy_prefers_safe_user_profile_then_app_default() {
        let default = remote_profile(ModelAuthentication::UserIdentity);
        let policy = ModelAccessPolicy {
            configuration_policy: ModelConfigurationPolicy::UserConfigurable,
            profile: Some(default.clone()),
            identity_mode: IdentityMode::Required,
            entitlement_mode: EntitlementMode::Disabled,
        };
        let user = ModelAccessProfile {
            provider_id: "local".into(),
            endpoint_type: EndpointType::ChatCompletions,
            base_url: "http://localhost:11434/v1".into(),
            model_name: "local-model".into(),
            authentication: ModelAuthentication::None,
            headers: BTreeMap::new(),
        };

        let selected_user = policy.resolve(Some(&user)).unwrap();
        assert_eq!(selected_user.source, ModelProfileSource::User);
        assert_eq!(selected_user.profile, user);

        let selected_default = policy.resolve(None).unwrap();
        assert_eq!(selected_default.source, ModelProfileSource::App);
        assert_eq!(selected_default.profile, default);
    }

    #[test]
    fn user_profile_cannot_redirect_app_identity() {
        let policy = ModelAccessPolicy {
            configuration_policy: ModelConfigurationPolicy::UserConfigurable,
            profile: None,
            identity_mode: IdentityMode::Required,
            entitlement_mode: EntitlementMode::Disabled,
        };
        let malicious = remote_profile(ModelAuthentication::UserIdentity);

        assert_eq!(
            policy.resolve(Some(&malicious)).unwrap_err(),
            ModelAccessError::UserProfileCannotUseAppIdentity
        );
    }

    #[test]
    fn profile_rejects_cleartext_remote_urls_and_url_credentials() {
        let mut cleartext = remote_profile(ModelAuthentication::None);
        cleartext.base_url = "http://gateway.example.com/v1".into();
        assert_eq!(
            cleartext.validate().unwrap_err(),
            ModelAccessError::InsecureRemoteEndpoint
        );

        let mut credential = remote_profile(ModelAuthentication::None);
        credential.base_url = "https://user:password@gateway.example.com/v1".into();
        assert_eq!(
            credential.validate().unwrap_err(),
            ModelAccessError::InvalidField("base_url")
        );

        let mut query = remote_profile(ModelAuthentication::None);
        query.base_url = "https://gateway.example.com/v1?api_key=secret".into();
        assert_eq!(
            query.validate().unwrap_err(),
            ModelAccessError::InvalidField("base_url")
        );
    }

    #[test]
    fn profile_rejects_sensitive_headers() {
        for header in [
            "Authorization",
            "Proxy-Authorization",
            "X-API-Key",
            "X-Access-Token",
            "X-Client-Secret",
            "X-Credential",
        ] {
            let mut profile = remote_profile(ModelAuthentication::None);
            profile.headers = BTreeMap::from([(header.into(), "secret-sentinel".into())]);
            assert_eq!(
                profile.validate().unwrap_err(),
                ModelAccessError::SensitiveHeader(header.into())
            );
            assert!(serde_json::to_value(&profile).is_err());
            assert!(!format!("{profile:?}").contains("secret-sentinel"));
        }
    }

    #[test]
    fn serialized_profile_cannot_add_secret_fields() {
        let encoded =
            serde_json::to_value(remote_profile(ModelAuthentication::UserIdentity)).unwrap();
        let object = encoded.as_object().unwrap();
        for forbidden in ["apiKey", "accessToken", "secretId", "credential"] {
            assert!(!object.contains_key(forbidden));
        }

        let mut with_secret = encoded;
        with_secret["apiKey"] = serde_json::json!("secret-sentinel");
        assert!(serde_json::from_value::<ModelAccessProfile>(with_secret).is_err());
    }
}
