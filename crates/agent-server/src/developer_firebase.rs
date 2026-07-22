use crate::developer_control_plane::{DeveloperControlPlane, now_unix_ms};
use crate::developer_firebase_models::*;
pub(crate) use crate::developer_firebase_oauth::FirebaseOAuthDefaults;
use crate::developer_firebase_pagination::{checked_next_page_token, paginated_url};
use agent_devkit::{
    DeveloperAuthorization, DevkitError, DevkitErrorCode, DevkitResult, SensitiveInputHandle,
    SensitiveInputResolver, SensitiveInputStore, SensitiveValue,
};
use async_trait::async_trait;
use base64::{Engine as _, engine::general_purpose::URL_SAFE_NO_PAD};
use identity_firebase::{FirebasePublicConfig, FirebaseSecret};
use reqwest::Method;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use sqlx::Row;
use std::collections::BTreeSet;
use std::time::Duration;
use url::Url;
use uuid::Uuid;

pub(crate) const FIREBASE_DEVELOPER_PROVIDER_ID: &str = "google.firebase";
const AUTHORIZATION_LIFETIME_MS: u64 = 10 * 60 * 1_000;
const GOOGLE_OAUTH_ISSUER: &str = "https://accounts.google.com";
pub(crate) const GOOGLE_SCOPE_CLOUD: &str = "https://www.googleapis.com/auth/cloud-platform";
pub(crate) const GOOGLE_SCOPE_FIREBASE: &str = "https://www.googleapis.com/auth/firebase";
pub(crate) const CAPABILITY_PROJECTS: &str = "firebase.projects.manage";
pub(crate) const CAPABILITY_AUTH: &str = "firebase.authentication.configure";
const MAX_RESPONSE_BYTES: usize = 1024 * 1024;
const MAX_LIST_PAGES: usize = 1_000;

fn firebase_configuration_error(status: u16) -> DevkitError {
    match status {
        404 => DevkitError::new(
            DevkitErrorCode::NotFound,
            "The selected Firebase project was not found",
        ),
        429 => DevkitError::new(
            DevkitErrorCode::RateLimited,
            "Firebase developer services are rate limited",
        )
        .retry_after(1_000),
        500..=599 => unavailable(),
        _ => permission(),
    }
}

#[derive(Clone, Debug, Deserialize)]
#[serde(
    tag = "mode",
    rename_all = "snake_case",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub(crate) enum FirebaseOAuthClientSelection {
    AgentWeavePublic,
    Custom {
        client_id: String,
        #[serde(default)]
        client_secret: Option<String>,
    },
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum FirebaseAuthorizationPhase {
    Disconnected,
    AwaitingCallback,
    SelectProject,
    Ready,
    Expired,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct FirebaseAuthorizationStatus {
    provider_id: String,
    phase: FirebaseAuthorizationPhase,
    project_id: Option<String>,
    expires_at_unix_ms: Option<u64>,
    public_oauth_client_available: bool,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct FirebaseAuthorizationStart {
    authorization_url: String,
    expires_at_unix_ms: u64,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct FirebaseProjectSummary {
    pub(crate) project_id: String,
    pub(crate) project_number: String,
    pub(crate) display_name: String,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct FirebaseConfigurationReceipt {
    project_id: String,
    display_name: String,
    public_config: FirebasePublicConfig,
}

pub(super) struct PendingFirebaseAuthorization {
    redirect_uri: Url,
    client_id: String,
    client_secret_handle: Option<SensitiveInputHandle>,
    state_handle: SensitiveInputHandle,
    verifier_handle: SensitiveInputHandle,
    expires_at_unix_ms: u64,
}

struct FirebaseAuthorizationCompletionError {
    error: DevkitError,
    retain_pending: bool,
}

impl From<DevkitError> for FirebaseAuthorizationCompletionError {
    fn from(error: DevkitError) -> Self {
        Self {
            error,
            retain_pending: false,
        }
    }
}

impl FirebaseAuthorizationCompletionError {
    fn retryable(error: DevkitError) -> Self {
        Self {
            error,
            retain_pending: true,
        }
    }
}

pub(crate) struct FirebaseControlRequest {
    pub(crate) method: Method,
    pub(crate) url: Url,
    pub(crate) bearer: Option<FirebaseSecret>,
    pub(crate) body: FirebaseControlBody,
}

pub(crate) enum FirebaseControlBody {
    Empty,
    Form(Vec<(String, FirebaseSecret)>),
    Json(Value),
}

pub(crate) struct FirebaseControlResponse {
    pub(crate) status: u16,
    pub(crate) body: Vec<u8>,
}

#[async_trait]
pub(crate) trait FirebaseControlHttp: Send + Sync {
    async fn send(&self, request: FirebaseControlRequest) -> DevkitResult<FirebaseControlResponse>;
}

pub(crate) struct ReqwestFirebaseControlHttp {
    client: reqwest::Client,
}

impl ReqwestFirebaseControlHttp {
    pub(crate) fn new() -> anyhow::Result<Self> {
        Ok(Self {
            client: reqwest::Client::builder()
                .timeout(Duration::from_secs(30))
                .redirect(reqwest::redirect::Policy::none())
                .build()?,
        })
    }
}

#[async_trait]
impl FirebaseControlHttp for ReqwestFirebaseControlHttp {
    async fn send(&self, request: FirebaseControlRequest) -> DevkitResult<FirebaseControlResponse> {
        let mut builder = self.client.request(request.method, request.url);
        if let Some(token) = request.bearer.as_ref() {
            builder = builder.bearer_auth(token.expose_secret());
        }
        builder = match &request.body {
            FirebaseControlBody::Empty => builder,
            FirebaseControlBody::Json(value) => builder.json(value),
            FirebaseControlBody::Form(values) => builder.form(
                &values
                    .iter()
                    .map(|(name, value)| (name.as_str(), value.expose_secret()))
                    .collect::<Vec<_>>(),
            ),
        };
        let response = builder.send().await.map_err(|_| unavailable())?;
        if response
            .content_length()
            .is_some_and(|length| length > MAX_RESPONSE_BYTES as u64)
        {
            return Err(remote_protocol());
        }
        let status = response.status().as_u16();
        let body = response.bytes().await.map_err(|_| unavailable())?;
        if body.len() > MAX_RESPONSE_BYTES {
            return Err(remote_protocol());
        }
        Ok(FirebaseControlResponse {
            status,
            body: body.to_vec(),
        })
    }
}

impl DeveloperControlPlane {
    pub(crate) async fn firebase_authorization_status(
        &self,
    ) -> DevkitResult<FirebaseAuthorizationStatus> {
        let authorization = match self.load_firebase_authorization().await? {
            Some(value) => Some(self.refresh_firebase_authorization_if_needed(value).await?),
            None => None,
        };
        let now = now_unix_ms();
        let pending = self.pending_firebase_authorization.lock().await;
        let phase = match authorization.as_ref() {
            Some(value)
                if value
                    .expires_at_unix_ms()
                    .is_some_and(|expiry| expiry <= now) =>
            {
                FirebaseAuthorizationPhase::Expired
            }
            Some(value) if value.account_id().is_some() => FirebaseAuthorizationPhase::Ready,
            Some(_) => FirebaseAuthorizationPhase::SelectProject,
            None if pending
                .as_ref()
                .is_some_and(|transaction| transaction.expires_at_unix_ms > now) =>
            {
                FirebaseAuthorizationPhase::AwaitingCallback
            }
            None => FirebaseAuthorizationPhase::Disconnected,
        };
        Ok(FirebaseAuthorizationStatus {
            provider_id: FIREBASE_DEVELOPER_PROVIDER_ID.into(),
            phase,
            project_id: authorization
                .as_ref()
                .and_then(DeveloperAuthorization::account_id)
                .map(str::to_owned),
            expires_at_unix_ms: authorization
                .as_ref()
                .and_then(DeveloperAuthorization::expires_at_unix_ms),
            public_oauth_client_available: self.firebase_oauth_defaults.public_client_available(),
        })
    }

    pub(crate) async fn start_firebase_authorization(
        &self,
        selection: FirebaseOAuthClientSelection,
        redirect_uri: Url,
    ) -> DevkitResult<FirebaseAuthorizationStart> {
        let _mutation = self.mutation.lock().await;
        let _refresh = self.firebase_refresh.lock().await;
        self.clear_pending_firebase_authorization().await?;
        if let Some(previous) = self.load_firebase_authorization().await? {
            self.delete_firebase_authorization().await?;
            let mut handles = vec![previous.token_handle().clone()];
            handles.extend(previous.refresh_token_handle().cloned());
            let _ = self.sensitive.delete_handles(handles).await;
        }
        validate_loopback_callback(&redirect_uri)?;
        let (client_id, client_secret) = self.firebase_oauth_client(selection)?;
        let state = random_value();
        let verifier = random_value();
        let challenge = URL_SAFE_NO_PAD.encode(Sha256::digest(verifier.as_bytes()));
        let state_handle = self
            .sensitive
            .store(
                "firebase/oauth/state",
                SensitiveValue::new(state.as_bytes().to_vec())?,
            )
            .await?;
        let verifier_handle = match self
            .sensitive
            .store(
                "firebase/oauth/pkce-verifier",
                SensitiveValue::new(verifier.into_bytes())?,
            )
            .await
        {
            Ok(handle) => handle,
            Err(error) => {
                let _ = self.sensitive.delete_handle(&state_handle).await;
                return Err(error);
            }
        };
        let client_secret_handle = match client_secret {
            Some(value) => match self
                .sensitive
                .store(
                    "firebase/oauth/client-secret",
                    SensitiveValue::new(value.into_bytes())?,
                )
                .await
            {
                Ok(handle) => Some(handle),
                Err(error) => {
                    let _ = self
                        .sensitive
                        .delete_handles([state_handle, verifier_handle])
                        .await;
                    return Err(error);
                }
            },
            None => None,
        };
        let expires_at_unix_ms = now_unix_ms().saturating_add(AUTHORIZATION_LIFETIME_MS);
        let mut authorization_url =
            Url::parse("https://accounts.google.com/o/oauth2/v2/auth").map_err(|_| internal())?;
        authorization_url
            .query_pairs_mut()
            .append_pair("client_id", &client_id)
            .append_pair("redirect_uri", redirect_uri.as_str())
            .append_pair("response_type", "code")
            .append_pair(
                "scope",
                &format!("{GOOGLE_SCOPE_CLOUD} {GOOGLE_SCOPE_FIREBASE}"),
            )
            .append_pair("access_type", "offline")
            .append_pair("prompt", "consent")
            .append_pair("code_challenge", &challenge)
            .append_pair("code_challenge_method", "S256")
            .append_pair("state", &state);
        *self.pending_firebase_authorization.lock().await = Some(PendingFirebaseAuthorization {
            redirect_uri,
            client_id,
            client_secret_handle,
            state_handle,
            verifier_handle,
            expires_at_unix_ms,
        });
        Ok(FirebaseAuthorizationStart {
            authorization_url: authorization_url.into(),
            expires_at_unix_ms,
        })
    }

    pub(crate) async fn complete_firebase_authorization(
        &self,
        callback_url: &str,
    ) -> DevkitResult<FirebaseAuthorizationStatus> {
        let _mutation = self.mutation.lock().await;
        let pending = self
            .pending_firebase_authorization
            .lock()
            .await
            .take()
            .ok_or_else(invalid_authorization)?;
        let result = self
            .complete_firebase_authorization_inner(callback_url, &pending)
            .await;
        match result {
            Ok(status) => {
                self.delete_pending_firebase_authorization_handles(pending)
                    .await;
                Ok(status)
            }
            Err(failure) if failure.retain_pending => {
                *self.pending_firebase_authorization.lock().await = Some(pending);
                Err(failure.error)
            }
            Err(failure) => {
                self.delete_pending_firebase_authorization_handles(pending)
                    .await;
                Err(failure.error)
            }
        }
    }

    async fn complete_firebase_authorization_inner(
        &self,
        callback_url: &str,
        pending: &PendingFirebaseAuthorization,
    ) -> Result<FirebaseAuthorizationStatus, FirebaseAuthorizationCompletionError> {
        if pending.expires_at_unix_ms <= now_unix_ms() {
            return Err(invalid_authorization().into());
        }
        let callback = Url::parse(callback_url).map_err(|_| invalid_authorization())?;
        validate_callback(&callback, &pending.redirect_uri)?;
        let query = unique_query(&callback)?;
        let state = query.get("state").ok_or_else(invalid_authorization)?;
        if query
            .get("iss")
            .is_some_and(|issuer| issuer != GOOGLE_OAUTH_ISSUER)
        {
            return Err(invalid_authorization().into());
        }
        let expected = self.sensitive.resolve(&pending.state_handle).await?;
        let state_matches = expected.expose(|bytes| {
            Ok(Sha256::digest(bytes).as_slice() == Sha256::digest(state.as_bytes()).as_slice())
        })?;
        if !state_matches || query.contains_key("error") {
            return Err(invalid_authorization().into());
        }
        let code = query.get("code").ok_or_else(invalid_authorization)?;
        let verifier = sensitive_text(&*self.sensitive, &pending.verifier_handle).await?;
        let mut form = vec![
            ("client_id".into(), FirebaseSecret::new(&pending.client_id)),
            ("code".into(), FirebaseSecret::new(code)),
            ("code_verifier".into(), verifier),
            (
                "grant_type".into(),
                FirebaseSecret::new("authorization_code"),
            ),
            (
                "redirect_uri".into(),
                FirebaseSecret::new(pending.redirect_uri.as_str()),
            ),
        ];
        let client_secret = match &pending.client_secret_handle {
            Some(handle) => Some(sensitive_text(&*self.sensitive, handle).await?),
            None => None,
        };
        if let Some(secret) = &client_secret {
            form.push(("client_secret".into(), secret.clone()));
        }
        let token_url =
            Url::parse("https://oauth2.googleapis.com/token").map_err(|_| internal())?;
        let response = self
            .firebase_http
            .send(FirebaseControlRequest {
                method: Method::POST,
                url: token_url,
                bearer: None,
                body: FirebaseControlBody::Form(form),
            })
            .await
            .map_err(|error| {
                if matches!(
                    error.code,
                    DevkitErrorCode::RateLimited
                        | DevkitErrorCode::Timeout
                        | DevkitErrorCode::Unavailable
                ) {
                    FirebaseAuthorizationCompletionError::retryable(error)
                } else {
                    error.into()
                }
            })?;
        if response.status == 429 || (500..=599).contains(&response.status) {
            return Err(FirebaseAuthorizationCompletionError::retryable(
                unavailable(),
            ));
        }
        if response.status != 200 {
            return Err(invalid_authorization().into());
        }
        let token: GoogleTokenResponse =
            serde_json::from_slice(&response.body).map_err(|_| remote_protocol())?;
        token.validate()?;
        let token_handle = self
            .sensitive
            .store(
                "firebase/oauth/access-token",
                SensitiveValue::new(token.access_token.expose_secret().as_bytes().to_vec())?,
            )
            .await?;
        let refresh_handle = match token.refresh_token.as_ref() {
            Some(value) => match self
                .sensitive
                .store(
                    "firebase/oauth/refresh-credential",
                    SensitiveValue::new(google_refresh_credential_document(
                        value,
                        &pending.client_id,
                        client_secret.as_ref(),
                    )?)?,
                )
                .await
            {
                Ok(handle) => Some(handle),
                Err(error) => {
                    let _ = self.sensitive.delete_handle(&token_handle).await;
                    return Err(error.into());
                }
            },
            None => None,
        };
        let now = now_unix_ms();
        let authorization = DeveloperAuthorization::new_unbound(
            FIREBASE_DEVELOPER_PROVIDER_ID,
            "local-developer-host",
            token_handle,
            refresh_handle,
            token.scope.split_whitespace().map(str::to_owned).collect(),
            required_capabilities(),
            format!("google-oauth-{}", Uuid::new_v4()),
            now,
            Some(now.saturating_add(token.expires_in.saturating_mul(1000))),
        )?;
        if let Err(error) = self.save_firebase_authorization(&authorization).await {
            let mut handles = vec![authorization.token_handle().clone()];
            handles.extend(authorization.refresh_token_handle().cloned());
            let _ = self.sensitive.delete_handles(handles).await;
            return Err(error.into());
        }
        self.firebase_authorization_status()
            .await
            .map_err(Into::into)
    }

    pub(crate) async fn list_firebase_projects(&self) -> DevkitResult<Vec<FirebaseProjectSummary>> {
        let authorization = self.require_firebase_authorization().await?;
        let mut projects = Vec::new();
        let mut page_token = None;
        let mut seen_page_tokens = BTreeSet::new();
        for _ in 0..MAX_LIST_PAGES {
            let url = paginated_url(
                "https://cloudresourcemanager.googleapis.com/v1/projects",
                &[("pageSize", "100"), ("filter", "lifecycleState:ACTIVE")],
                page_token.as_deref(),
            )?;
            let response = self
                .firebase_request(
                    &authorization,
                    Method::GET,
                    &url,
                    FirebaseControlBody::Empty,
                )
                .await?;
            if response.status != 200 {
                return Err(permission());
            }
            let list: CloudProjectList =
                serde_json::from_slice(&response.body).map_err(|_| remote_protocol())?;
            projects.extend(
                list.projects
                    .into_iter()
                    .map(CloudProject::summary)
                    .collect::<DevkitResult<Vec<_>>>()?,
            );
            page_token = checked_next_page_token(list.next_page_token, &mut seen_page_tokens)?;
            if page_token.is_none() {
                break;
            }
        }
        if page_token.is_some() {
            return Err(remote_protocol());
        }
        projects.sort_by(|left, right| {
            left.display_name
                .cmp(&right.display_name)
                .then_with(|| left.project_id.cmp(&right.project_id))
        });
        Ok(projects)
    }

    pub(crate) async fn configure_firebase_project(
        &self,
        project_id: &str,
    ) -> DevkitResult<FirebaseConfigurationReceipt> {
        validate_project_id(project_id)?;
        let projects = self.list_firebase_projects().await?;
        let project = projects
            .into_iter()
            .find(|project| project.project_id == project_id)
            .ok_or_else(permission)?;
        let authorization = self.require_firebase_authorization().await?;
        self.ensure_firebase_project(&authorization, &project)
            .await?;
        self.enable_identity_toolkit(&authorization, &project)
            .await?;
        self.enable_email_password(&authorization, &project).await?;
        let app_name = self.ensure_web_app(&authorization, &project).await?;
        let config = self.web_app_config(&authorization, &app_name).await?;
        config.validate().map_err(|_| remote_protocol())?;
        let bound = authorization.bind_account(project.project_id.clone())?;
        self.save_firebase_authorization(&bound).await?;
        Ok(FirebaseConfigurationReceipt {
            project_id: project.project_id,
            display_name: project.display_name,
            public_config: config,
        })
    }

    pub(crate) async fn cancel_firebase_authorization(
        &self,
    ) -> DevkitResult<FirebaseAuthorizationStatus> {
        let _mutation = self.mutation.lock().await;
        self.clear_pending_firebase_authorization().await?;
        self.firebase_authorization_status().await
    }

    pub(crate) async fn disconnect_firebase_authorization(
        &self,
    ) -> DevkitResult<FirebaseAuthorizationStatus> {
        let _mutation = self.mutation.lock().await;
        self.clear_pending_firebase_authorization().await?;
        if let Some(authorization) = self.load_firebase_authorization().await? {
            self.delete_firebase_authorization().await?;
            let mut handles = vec![authorization.token_handle().clone()];
            handles.extend(authorization.refresh_token_handle().cloned());
            let _ = self.sensitive.delete_handles(handles).await;
        }
        self.firebase_authorization_status().await
    }

    async fn ensure_firebase_project(
        &self,
        authorization: &DeveloperAuthorization,
        project: &FirebaseProjectSummary,
    ) -> DevkitResult<()> {
        let get = self
            .firebase_request(
                authorization,
                Method::GET,
                &format!(
                    "https://firebase.googleapis.com/v1beta1/projects/{}",
                    project.project_id
                ),
                FirebaseControlBody::Empty,
            )
            .await?;
        if get.status == 200 {
            return Ok(());
        }
        if get.status != 404 {
            return Err(permission());
        }
        let add = self
            .firebase_request(
                authorization,
                Method::POST,
                &format!(
                    "https://firebase.googleapis.com/v1beta1/projects/{}:addFirebase",
                    project.project_id
                ),
                FirebaseControlBody::Json(json!({})),
            )
            .await?;
        self.require_operation_success(
            authorization,
            add,
            "https://firebase.googleapis.com/v1beta1/",
        )
        .await
    }

    async fn enable_identity_toolkit(
        &self,
        authorization: &DeveloperAuthorization,
        project: &FirebaseProjectSummary,
    ) -> DevkitResult<()> {
        let response = self
            .firebase_request(
                authorization,
                Method::POST,
                &format!("https://serviceusage.googleapis.com/v1/projects/{}/services/identitytoolkit.googleapis.com:enable", project.project_number),
                FirebaseControlBody::Json(json!({})),
            )
            .await?;
        self.require_operation_success(
            authorization,
            response,
            "https://serviceusage.googleapis.com/v1/",
        )
        .await
    }

    async fn enable_email_password(
        &self,
        authorization: &DeveloperAuthorization,
        project: &FirebaseProjectSummary,
    ) -> DevkitResult<()> {
        let update_url = format!(
            "https://identitytoolkit.googleapis.com/admin/v2/projects/{}/config?updateMask=signIn.email",
            project.project_id
        );
        let config = json!({
            "signIn": { "email": { "enabled": true, "passwordRequired": true } }
        });
        let mut response = self
            .firebase_request(
                authorization,
                Method::PATCH,
                &update_url,
                FirebaseControlBody::Json(config.clone()),
            )
            .await?;
        if response.status == 404 {
            let initialized = self
                .firebase_request(
                    authorization,
                    Method::POST,
                    &format!(
                        "https://identitytoolkit.googleapis.com/v2/projects/{}/identityPlatform:initializeAuth",
                        project.project_id
                    ),
                    FirebaseControlBody::Json(json!({})),
                )
                .await?;
            if initialized.status != 200 {
                return Err(firebase_configuration_error(initialized.status));
            }
            response = self
                .firebase_request(
                    authorization,
                    Method::PATCH,
                    &update_url,
                    FirebaseControlBody::Json(config),
                )
                .await?;
        }
        if response.status == 200 {
            Ok(())
        } else {
            Err(firebase_configuration_error(response.status))
        }
    }

    async fn ensure_web_app(
        &self,
        authorization: &DeveloperAuthorization,
        project: &FirebaseProjectSummary,
    ) -> DevkitResult<String> {
        let base_url = format!(
            "https://firebase.googleapis.com/v1beta1/projects/{}/webApps",
            project.project_id
        );
        let mut all_apps = Vec::new();
        let mut page_token = None;
        let mut seen_page_tokens = BTreeSet::new();
        for _ in 0..MAX_LIST_PAGES {
            let url = paginated_url(&base_url, &[("pageSize", "100")], page_token.as_deref())?;
            let response = self
                .firebase_request(authorization, Method::GET, &url, FirebaseControlBody::Empty)
                .await?;
            if response.status != 200 {
                return Err(permission());
            }
            let apps: WebAppList =
                serde_json::from_slice(&response.body).map_err(|_| remote_protocol())?;
            all_apps.extend(apps.apps);
            page_token = checked_next_page_token(apps.next_page_token, &mut seen_page_tokens)?;
            if page_token.is_none() {
                break;
            }
        }
        if page_token.is_some() {
            return Err(remote_protocol());
        }
        let display_name = format!("AgentWeave · {}", self.app_id);
        if let Some(app) = all_apps
            .into_iter()
            .find(|app| app.display_name.as_deref() == Some(display_name.as_str()))
        {
            return validate_resource_name(&app.name, "/webApps/");
        }
        let create = self
            .firebase_request(
                authorization,
                Method::POST,
                &format!(
                    "https://firebase.googleapis.com/v1beta1/projects/{}/webApps",
                    project.project_id
                ),
                FirebaseControlBody::Json(json!({ "displayName": display_name })),
            )
            .await?;
        let operation = self
            .wait_operation(
                authorization,
                create,
                "https://firebase.googleapis.com/v1beta1/",
            )
            .await?;
        let app: WebApp = serde_json::from_value(operation.response.ok_or_else(remote_protocol)?)
            .map_err(|_| remote_protocol())?;
        validate_resource_name(&app.name, "/webApps/")
    }

    async fn web_app_config(
        &self,
        authorization: &DeveloperAuthorization,
        app_name: &str,
    ) -> DevkitResult<FirebasePublicConfig> {
        let response = self
            .firebase_request(
                authorization,
                Method::GET,
                &format!("https://firebase.googleapis.com/v1beta1/{app_name}/config"),
                FirebaseControlBody::Empty,
            )
            .await?;
        if response.status != 200 {
            return Err(permission());
        }
        let config: WebAppConfig =
            serde_json::from_slice(&response.body).map_err(|_| remote_protocol())?;
        Ok(FirebasePublicConfig {
            project_id: config.project_id,
            firebase_web_key: config.api_key,
            web_application_id: config.app_id,
            auth_domain: config.auth_domain,
        })
    }

    async fn require_operation_success(
        &self,
        authorization: &DeveloperAuthorization,
        response: FirebaseControlResponse,
        operation_base: &str,
    ) -> DevkitResult<()> {
        self.wait_operation(authorization, response, operation_base)
            .await
            .map(|_| ())
    }

    async fn wait_operation(
        &self,
        authorization: &DeveloperAuthorization,
        response: FirebaseControlResponse,
        operation_base: &str,
    ) -> DevkitResult<GoogleOperation> {
        if response.status != 200 {
            return Err(permission());
        }
        let mut operation: GoogleOperation =
            serde_json::from_slice(&response.body).map_err(|_| remote_protocol())?;
        for _ in 0..60 {
            if operation.done.unwrap_or(false) {
                return if operation.error.is_none() {
                    Ok(operation)
                } else {
                    Err(permission())
                };
            }
            tokio::time::sleep(Duration::from_millis(500)).await;
            let name = validate_operation_name(&operation.name)?;
            let polled = self
                .firebase_request(
                    authorization,
                    Method::GET,
                    &format!("{operation_base}{name}"),
                    FirebaseControlBody::Empty,
                )
                .await?;
            if polled.status != 200 {
                return Err(unavailable());
            }
            operation = serde_json::from_slice(&polled.body).map_err(|_| remote_protocol())?;
        }
        Err(DevkitError::new(
            DevkitErrorCode::Timeout,
            "Firebase configuration did not finish before the timeout",
        ))
    }

    async fn firebase_request(
        &self,
        authorization: &DeveloperAuthorization,
        method: Method,
        url: &str,
        body: FirebaseControlBody,
    ) -> DevkitResult<FirebaseControlResponse> {
        authorization.ensure_provider_usable(
            FIREBASE_DEVELOPER_PROVIDER_ID,
            &required_capabilities(),
            now_unix_ms(),
        )?;
        let token = sensitive_text(&*self.sensitive, authorization.token_handle()).await?;
        self.firebase_http
            .send(FirebaseControlRequest {
                method,
                url: Url::parse(url).map_err(|_| internal())?,
                bearer: Some(token),
                body,
            })
            .await
    }

    pub(crate) async fn load_firebase_authorization(
        &self,
    ) -> DevkitResult<Option<DeveloperAuthorization>> {
        let row = sqlx::query("SELECT authorization_json FROM developer_provider_authorizations WHERE project_key = ?1 AND provider_id = ?2")
            .bind(&self.project_key)
            .bind(FIREBASE_DEVELOPER_PROVIDER_ID)
            .fetch_optional(&self.pool)
            .await
            .map_err(|_| internal())?;
        row.map(|row| {
            serde_json::from_str(row.get::<&str, _>("authorization_json")).map_err(|_| internal())
        })
        .transpose()
    }

    pub(crate) async fn save_firebase_authorization(
        &self,
        authorization: &DeveloperAuthorization,
    ) -> DevkitResult<()> {
        if authorization.provider_id() != FIREBASE_DEVELOPER_PROVIDER_ID {
            return Err(invalid_authorization());
        }
        let document = serde_json::to_string(authorization).map_err(|_| internal())?;
        sqlx::query("INSERT INTO developer_provider_authorizations (project_key, provider_id, authorization_json, updated_at_unix_ms) VALUES (?1, ?2, ?3, ?4) ON CONFLICT (project_key, provider_id) DO UPDATE SET authorization_json = excluded.authorization_json, updated_at_unix_ms = excluded.updated_at_unix_ms")
            .bind(&self.project_key)
            .bind(FIREBASE_DEVELOPER_PROVIDER_ID)
            .bind(document)
            .bind(now_unix_ms() as i64)
            .execute(&self.pool)
            .await
            .map_err(|_| internal())?;
        Ok(())
    }

    pub(crate) async fn delete_firebase_authorization(&self) -> DevkitResult<()> {
        sqlx::query("DELETE FROM developer_provider_authorizations WHERE project_key = ?1 AND provider_id = ?2")
            .bind(&self.project_key)
            .bind(FIREBASE_DEVELOPER_PROVIDER_ID)
            .execute(&self.pool)
            .await
            .map_err(|_| internal())?;
        Ok(())
    }

    async fn clear_pending_firebase_authorization(&self) -> DevkitResult<()> {
        if let Some(pending) = self.pending_firebase_authorization.lock().await.take() {
            self.delete_pending_firebase_authorization_handles(pending)
                .await;
        }
        Ok(())
    }

    async fn delete_pending_firebase_authorization_handles(
        &self,
        pending: PendingFirebaseAuthorization,
    ) {
        let mut handles = vec![pending.state_handle, pending.verifier_handle];
        handles.extend(pending.client_secret_handle);
        let _ = self.sensitive.delete_handles(handles).await;
    }

    fn firebase_oauth_client(
        &self,
        selection: FirebaseOAuthClientSelection,
    ) -> DevkitResult<(String, Option<String>)> {
        let values = match selection {
            FirebaseOAuthClientSelection::AgentWeavePublic => (
                self.firebase_oauth_defaults
                    .client_id
                    .clone()
                    .ok_or_else(unavailable)?,
                self.firebase_oauth_defaults.client_secret.clone(),
            ),
            FirebaseOAuthClientSelection::Custom {
                client_id,
                client_secret,
            } => (client_id, client_secret),
        };
        validate_oauth_value(&values.0)?;
        if let Some(secret) = &values.1 {
            validate_oauth_value(secret)?;
        }
        Ok(values)
    }
}

#[cfg(test)]
#[path = "developer_firebase_tests.rs"]
mod tests;
