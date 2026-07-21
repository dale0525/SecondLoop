use crate::{FirebaseError, Result};
use serde::{Deserialize, Serialize};
use url::Url;

const MAX_PUBLIC_VALUE_BYTES: usize = 2048;

/// Public Firebase web configuration stored in an Agent App provider binding.
///
/// `firebase_web_key` is the Firebase-generated browser API identifier. It is
/// not an authorization secret; Firebase ID tokens authorize user operations.
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct FirebasePublicConfig {
    pub project_id: String,
    pub firebase_web_key: String,
    pub web_application_id: String,
    #[serde(default)]
    pub auth_domain: Option<String>,
}

impl FirebasePublicConfig {
    pub fn validate(&self) -> Result<()> {
        if !valid_project_id(&self.project_id)
            || !valid_public_value(&self.firebase_web_key)
            || !valid_public_value(&self.web_application_id)
            || self
                .auth_domain
                .as_deref()
                .is_some_and(|value| !valid_auth_domain(value))
        {
            return Err(FirebaseError::InvalidConfiguration);
        }
        Ok(())
    }

    pub fn issuer(&self) -> String {
        format!("https://securetoken.google.com/{}", self.project_id)
    }

    pub fn audience(&self) -> &str {
        &self.project_id
    }

    pub fn jwks_url() -> &'static str {
        "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com"
    }

    pub fn sign_in_url(&self) -> Result<Url> {
        endpoint_with_key(
            "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword",
            &self.firebase_web_key,
        )
    }

    pub fn refresh_url(&self) -> Result<Url> {
        endpoint_with_key(
            "https://securetoken.googleapis.com/v1/token",
            &self.firebase_web_key,
        )
    }
}

fn endpoint_with_key(base: &str, key: &str) -> Result<Url> {
    let mut url = Url::parse(base).map_err(|_| FirebaseError::InvalidConfiguration)?;
    url.query_pairs_mut().append_pair("key", key);
    Ok(url)
}

fn valid_project_id(value: &str) -> bool {
    (6..=30).contains(&value.len())
        && value.starts_with(|character: char| character.is_ascii_lowercase())
        && value.ends_with(|character: char| {
            character.is_ascii_lowercase() || character.is_ascii_digit()
        })
        && value
            .bytes()
            .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-')
}

fn valid_public_value(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= MAX_PUBLIC_VALUE_BYTES
        && value == value.trim()
        && !value.chars().any(char::is_control)
}

fn valid_auth_domain(value: &str) -> bool {
    valid_public_value(value)
        && !value.contains(['/', ':', '@'])
        && value.split('.').all(|label| {
            !label.is_empty()
                && label.len() <= 63
                && !label.starts_with('-')
                && !label.ends_with('-')
                && label
                    .bytes()
                    .all(|byte| byte.is_ascii_alphanumeric() || byte == b'-')
        })
}
