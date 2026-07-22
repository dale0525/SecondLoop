use crate::developer_firebase::{
    CAPABILITY_AUTH, CAPABILITY_PROJECTS, FirebaseProjectSummary, GOOGLE_SCOPE_CLOUD,
    GOOGLE_SCOPE_FIREBASE,
};
use agent_devkit::{
    DevkitError, DevkitErrorCode, DevkitResult, SensitiveInputHandle, SensitiveInputResolver,
};
use identity_firebase::FirebaseSecret;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};
use url::Url;
use uuid::Uuid;

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct GoogleTokenResponse {
    pub(crate) access_token: FirebaseSecret,
    #[serde(default)]
    pub(crate) refresh_token: Option<FirebaseSecret>,
    pub(crate) expires_in: u64,
    pub(crate) scope: String,
    token_type: String,
}

impl GoogleTokenResponse {
    pub(crate) fn validate(&self) -> DevkitResult<()> {
        let scopes = self.scope.split_whitespace().collect::<BTreeSet<_>>();
        if self.access_token.is_empty()
            || !(60..=86_400).contains(&self.expires_in)
            || self.token_type != "Bearer"
            || !scopes.contains(GOOGLE_SCOPE_CLOUD)
            || !scopes.contains(GOOGLE_SCOPE_FIREBASE)
        {
            return Err(invalid_authorization());
        }
        Ok(())
    }
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct GoogleRefreshTokenResponse {
    pub(crate) access_token: FirebaseSecret,
    pub(crate) expires_in: u64,
    #[serde(default)]
    pub(crate) refresh_token: Option<FirebaseSecret>,
    #[serde(default)]
    pub(crate) scope: Option<String>,
    token_type: String,
}

impl GoogleRefreshTokenResponse {
    pub(crate) fn validate(&self) -> DevkitResult<()> {
        let scopes_valid = self.scope.as_deref().is_none_or(|scope| {
            let scopes = scope.split_whitespace().collect::<BTreeSet<_>>();
            scopes.contains(GOOGLE_SCOPE_CLOUD) && scopes.contains(GOOGLE_SCOPE_FIREBASE)
        });
        if self.access_token.is_empty()
            || !(60..=86_400).contains(&self.expires_in)
            || self.token_type != "Bearer"
            || !scopes_valid
            || self
                .refresh_token
                .as_ref()
                .is_some_and(FirebaseSecret::is_empty)
        {
            return Err(invalid_authorization());
        }
        Ok(())
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct GoogleRefreshCredential {
    pub(crate) client_id: String,
    #[serde(default)]
    pub(crate) client_secret: Option<FirebaseSecret>,
    pub(crate) refresh_token: FirebaseSecret,
}

impl GoogleRefreshCredential {
    pub(crate) fn validate(&self) -> DevkitResult<()> {
        validate_oauth_value(&self.client_id)?;
        if let Some(secret) = &self.client_secret {
            validate_oauth_value(secret.expose_secret())?;
        }
        if self.refresh_token.is_empty() {
            return Err(invalid_authorization());
        }
        Ok(())
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct GoogleRefreshCredentialDocument<'a> {
    client_id: &'a str,
    client_secret: Option<&'a str>,
    refresh_token: &'a str,
}

pub(crate) fn google_refresh_credential_document(
    refresh_token: &FirebaseSecret,
    client_id: &str,
    client_secret: Option<&FirebaseSecret>,
) -> DevkitResult<Vec<u8>> {
    validate_oauth_value(client_id)?;
    if refresh_token.is_empty() {
        return Err(invalid_authorization());
    }
    if let Some(secret) = client_secret {
        validate_oauth_value(secret.expose_secret())?;
    }
    serde_json::to_vec(&GoogleRefreshCredentialDocument {
        client_id,
        client_secret: client_secret.map(FirebaseSecret::expose_secret),
        refresh_token: refresh_token.expose_secret(),
    })
    .map_err(|_| internal())
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct CloudProjectList {
    #[serde(default)]
    pub(crate) projects: Vec<CloudProject>,
    #[serde(default)]
    pub(crate) next_page_token: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct CloudProject {
    project_id: String,
    project_number: String,
    #[serde(default)]
    name: Option<String>,
    lifecycle_state: String,
    #[serde(default)]
    create_time: Option<String>,
    #[serde(default)]
    labels: Option<Value>,
    #[serde(default)]
    parent: Option<Value>,
}

impl CloudProject {
    pub(crate) fn summary(self) -> DevkitResult<FirebaseProjectSummary> {
        let _ = (self.create_time, self.labels, self.parent);
        validate_project_id(&self.project_id)?;
        let display_name = match self.name {
            Some(name) if name.trim().is_empty() => self.project_id.clone(),
            Some(name) if name.len() <= 512 => name,
            Some(_) => return Err(remote_protocol()),
            None => self.project_id.clone(),
        };
        if self.project_number.is_empty()
            || !self
                .project_number
                .bytes()
                .all(|byte| byte.is_ascii_digit())
            || self.lifecycle_state != "ACTIVE"
        {
            return Err(remote_protocol());
        }
        Ok(FirebaseProjectSummary {
            project_id: self.project_id,
            project_number: self.project_number,
            display_name,
        })
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct WebAppList {
    #[serde(default)]
    pub(crate) apps: Vec<WebApp>,
    #[serde(default)]
    pub(crate) next_page_token: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[allow(dead_code)]
pub(crate) struct WebApp {
    pub(crate) name: String,
    #[serde(default)]
    pub(crate) display_name: Option<String>,
    #[serde(default)]
    app_id: Option<String>,
    #[serde(default)]
    project_id: Option<String>,
    #[serde(default)]
    web_id: Option<String>,
    #[serde(default)]
    state: Option<String>,
    #[serde(default)]
    etag: Option<String>,
    #[serde(default)]
    api_key_id: Option<String>,
    #[serde(default)]
    app_urls: Option<Vec<String>>,
    #[serde(default)]
    expire_time: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[allow(dead_code)]
pub(crate) struct WebAppConfig {
    pub(crate) project_id: String,
    pub(crate) app_id: String,
    pub(crate) api_key: String,
    #[serde(default)]
    pub(crate) auth_domain: Option<String>,
    #[serde(default)]
    storage_bucket: Option<String>,
    #[serde(default)]
    messaging_sender_id: Option<String>,
    #[serde(default)]
    measurement_id: Option<String>,
    #[serde(default, rename = "databaseURL")]
    database_url: Option<String>,
    #[serde(default)]
    location_id: Option<String>,
    #[serde(default)]
    project_number: Option<String>,
    #[serde(default)]
    realtime_database_url: Option<String>,
    #[serde(default)]
    recaptcha_site_key: Option<String>,
    #[serde(default)]
    version: Option<String>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
#[allow(dead_code)]
pub(crate) struct GoogleOperation {
    pub(crate) name: String,
    #[serde(default)]
    pub(crate) done: Option<bool>,
    #[serde(default)]
    pub(crate) response: Option<Value>,
    #[serde(default)]
    pub(crate) error: Option<Value>,
    #[serde(default)]
    metadata: Option<Value>,
}

pub(crate) async fn sensitive_text(
    store: &dyn SensitiveInputResolver,
    handle: &SensitiveInputHandle,
) -> DevkitResult<FirebaseSecret> {
    let value = store.resolve(handle).await?;
    value.expose(|bytes| {
        String::from_utf8(bytes.to_vec())
            .map(FirebaseSecret::new)
            .map_err(|_| remote_protocol())
    })
}

pub(crate) fn required_capabilities() -> BTreeSet<String> {
    BTreeSet::from([CAPABILITY_PROJECTS.into(), CAPABILITY_AUTH.into()])
}

pub(crate) fn validate_loopback_callback(url: &Url) -> DevkitResult<()> {
    if url.scheme() != "http"
        || url.host_str() != Some("127.0.0.1")
        || url.port().is_none()
        || url.query().is_some()
        || url.fragment().is_some()
    {
        return Err(DevkitError::new(
            DevkitErrorCode::RedirectRejected,
            "Firebase OAuth callback must use an exact IPv4 loopback URL",
        ));
    }
    Ok(())
}

pub(crate) fn validate_callback(callback: &Url, expected: &Url) -> DevkitResult<()> {
    if callback.scheme() != expected.scheme()
        || callback.host_str() != expected.host_str()
        || callback.port() != expected.port()
        || callback.path() != expected.path()
        || callback.fragment().is_some()
    {
        return Err(invalid_authorization());
    }
    Ok(())
}

pub(crate) fn unique_query(url: &Url) -> DevkitResult<BTreeMap<String, String>> {
    let mut values = BTreeMap::new();
    for (name, value) in url.query_pairs() {
        if !matches!(
            name.as_ref(),
            "code" | "state" | "scope" | "iss" | "error" | "error_description"
        ) || values
            .insert(name.into_owned(), value.into_owned())
            .is_some()
        {
            return Err(invalid_authorization());
        }
    }
    Ok(values)
}

pub(crate) fn validate_project_id(value: &str) -> DevkitResult<()> {
    let valid = (6..=30).contains(&value.len())
        && value
            .bytes()
            .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-')
        && value.as_bytes().first().is_some_and(u8::is_ascii_lowercase)
        && value
            .as_bytes()
            .last()
            .is_some_and(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit());
    if valid {
        Ok(())
    } else {
        Err(DevkitError::invalid_configuration(
            "Firebase project ID is invalid",
        ))
    }
}

pub(crate) fn validate_resource_name(value: &str, separator: &str) -> DevkitResult<String> {
    if value.starts_with("projects/")
        && value.contains(separator)
        && value.len() <= 1024
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || "/:_-".contains(byte as char))
    {
        Ok(value.into())
    } else {
        Err(remote_protocol())
    }
}

pub(crate) fn validate_operation_name(value: &str) -> DevkitResult<&str> {
    if !value.is_empty()
        && value.len() <= 1024
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || "/_:-".contains(byte as char))
    {
        Ok(value)
    } else {
        Err(remote_protocol())
    }
}

pub(crate) fn validate_oauth_value(value: &str) -> DevkitResult<()> {
    if value.is_empty() || value.len() > 4096 || value.chars().any(char::is_control) {
        Err(DevkitError::invalid_configuration(
            "Firebase OAuth client configuration is invalid",
        ))
    } else {
        Ok(())
    }
}

pub(crate) fn random_value() -> String {
    format!("{}{}", Uuid::new_v4().simple(), Uuid::new_v4().simple())
}

pub(crate) fn invalid_authorization() -> DevkitError {
    DevkitError::new(
        DevkitErrorCode::InvalidAuthorization,
        "Firebase developer authorization is invalid or expired",
    )
}

pub(crate) fn permission() -> DevkitError {
    DevkitError::new(
        DevkitErrorCode::PermissionInsufficient,
        "The Google account cannot configure the selected Firebase project",
    )
}

pub(crate) fn unavailable() -> DevkitError {
    DevkitError::new(
        DevkitErrorCode::Unavailable,
        "Firebase developer services are unavailable",
    )
}

pub(crate) fn remote_protocol() -> DevkitError {
    DevkitError::new(
        DevkitErrorCode::RemoteProtocol,
        "Firebase returned an invalid response",
    )
}

pub(crate) fn internal() -> DevkitError {
    DevkitError::new(
        DevkitErrorCode::Internal,
        "Firebase developer configuration failed",
    )
}
