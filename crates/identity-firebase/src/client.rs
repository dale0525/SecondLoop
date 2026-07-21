use crate::{
    FIREBASE_IDENTITY_PROVIDER_ID, FirebaseError, FirebasePublicConfig, FirebaseSecret,
    FirebaseSession, FirebaseSessionStore, Result,
};
use agent_runtime::identity::{
    IdentityProvider, IdentityProviderError, PrincipalIdentity, SECURITY_CONTEXT_SCHEMA_VERSION,
    SecurityContext, SecurityContextRequest,
};
use async_trait::async_trait;
use chrono::{DateTime, Duration, Utc};
use reqwest::header::CONTENT_TYPE;
use serde::{Deserialize, Serialize};
use std::{collections::BTreeSet, sync::Arc, time::Duration as StdDuration};
use tokio::sync::Mutex;
use url::Url;

const MAX_RESPONSE_BYTES: usize = 256 * 1024;
const REFRESH_BEFORE_SECONDS: i64 = 60;

#[derive(Clone, Debug)]
pub struct FirebaseHttpResponse {
    pub status: u16,
    pub body: Vec<u8>,
}

#[async_trait]
pub trait FirebaseHttpClient: Send + Sync {
    async fn post_json(&self, url: Url, body: Vec<u8>) -> Result<FirebaseHttpResponse>;
    async fn post_form(
        &self,
        url: Url,
        form: Vec<(String, FirebaseSecret)>,
    ) -> Result<FirebaseHttpResponse>;
}

#[derive(Clone)]
pub struct ReqwestFirebaseHttpClient {
    client: reqwest::Client,
}

impl ReqwestFirebaseHttpClient {
    pub fn new() -> Result<Self> {
        let client = reqwest::Client::builder()
            .timeout(StdDuration::from_secs(30))
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .map_err(|_| FirebaseError::Unavailable)?;
        Ok(Self { client })
    }
}

#[async_trait]
impl FirebaseHttpClient for ReqwestFirebaseHttpClient {
    async fn post_json(&self, url: Url, body: Vec<u8>) -> Result<FirebaseHttpResponse> {
        let response = self
            .client
            .post(url)
            .header(CONTENT_TYPE, "application/json")
            .body(body)
            .send()
            .await
            .map_err(|_| FirebaseError::Unavailable)?;
        bounded_response(response).await
    }

    async fn post_form(
        &self,
        url: Url,
        form: Vec<(String, FirebaseSecret)>,
    ) -> Result<FirebaseHttpResponse> {
        let exposed = form
            .iter()
            .map(|(name, value)| (name.as_str(), value.expose_secret()))
            .collect::<Vec<_>>();
        let response = self
            .client
            .post(url)
            .form(&exposed)
            .send()
            .await
            .map_err(|_| FirebaseError::Unavailable)?;
        bounded_response(response).await
    }
}

async fn bounded_response(response: reqwest::Response) -> Result<FirebaseHttpResponse> {
    if response
        .content_length()
        .is_some_and(|length| length > MAX_RESPONSE_BYTES as u64)
    {
        return Err(FirebaseError::InvalidResponse);
    }
    let status = response.status().as_u16();
    let body = response
        .bytes()
        .await
        .map_err(|_| FirebaseError::Unavailable)?;
    if body.len() > MAX_RESPONSE_BYTES {
        return Err(FirebaseError::InvalidResponse);
    }
    Ok(FirebaseHttpResponse {
        status,
        body: body.to_vec(),
    })
}

pub struct FirebaseIdentityProvider {
    config: FirebasePublicConfig,
    store: Arc<dyn FirebaseSessionStore>,
    http: Arc<dyn FirebaseHttpClient>,
    session_gate: Mutex<()>,
}

impl FirebaseIdentityProvider {
    pub fn new(
        config: FirebasePublicConfig,
        store: Arc<dyn FirebaseSessionStore>,
        http: Arc<dyn FirebaseHttpClient>,
    ) -> Result<Self> {
        config.validate()?;
        Ok(Self {
            config,
            store,
            http,
            session_gate: Mutex::new(()),
        })
    }

    pub async fn sign_in_with_password(
        &self,
        request: &SecurityContextRequest,
        email: FirebaseSecret,
        password: FirebaseSecret,
    ) -> Result<SecurityContext> {
        validate_request(&self.config, request)?;
        validate_credential(email.expose_secret(), 320)?;
        validate_credential(password.expose_secret(), 4096)?;
        let _guard = self.session_gate.lock().await;
        let body = serde_json::to_vec(&PasswordRequest {
            email: email.expose_secret(),
            password: password.expose_secret(),
            return_secure_token: true,
        })
        .map_err(|_| FirebaseError::InvalidRequest)?;
        let response = self
            .http
            .post_json(self.config.sign_in_url()?, body)
            .await?;
        if response.status == 400 || response.status == 401 {
            return Err(FirebaseError::AccessDenied);
        }
        if response.status != 200 {
            return Err(FirebaseError::Unavailable);
        }
        let token: PasswordTokenResponse =
            serde_json::from_slice(&response.body).map_err(|_| FirebaseError::InvalidResponse)?;
        let session = token.into_session(Utc::now())?;
        let context = self.context(request, &session)?;
        self.store.save_session(session).await?;
        Ok(context)
    }

    pub async fn gateway_assertion(
        &self,
        request: &SecurityContextRequest,
    ) -> Result<FirebaseSecret> {
        Ok(self.validated_session(request).await?.id_token)
    }

    pub async fn sign_out(&self) -> Result<()> {
        let _guard = self.session_gate.lock().await;
        self.store.delete_session().await
    }

    async fn security_context_inner(
        &self,
        request: &SecurityContextRequest,
    ) -> Result<SecurityContext> {
        let session = self.validated_session(request).await?;
        self.context(request, &session)
    }

    async fn validated_session(&self, request: &SecurityContextRequest) -> Result<FirebaseSession> {
        validate_request(&self.config, request)?;
        let _guard = self.session_gate.lock().await;
        let mut session = self
            .store
            .load_session()
            .await?
            .ok_or(FirebaseError::AuthenticationRequired)?;
        if session.expires_at <= Utc::now() + Duration::seconds(REFRESH_BEFORE_SECONDS) {
            session = self.refresh(session).await?;
            self.store.save_session(session.clone()).await?;
        }
        self.context(request, &session)?;
        Ok(session)
    }

    async fn refresh(&self, previous: FirebaseSession) -> Result<FirebaseSession> {
        let response = self
            .http
            .post_form(
                self.config.refresh_url()?,
                vec![
                    ("grant_type".into(), FirebaseSecret::new("refresh_token")),
                    ("refresh_token".into(), previous.refresh_token.clone()),
                ],
            )
            .await?;
        if response.status == 400 || response.status == 401 {
            self.store.delete_session().await?;
            return Err(FirebaseError::AuthenticationRequired);
        }
        if response.status != 200 {
            return Err(FirebaseError::Unavailable);
        }
        let token: RefreshTokenResponse =
            serde_json::from_slice(&response.body).map_err(|_| FirebaseError::InvalidResponse)?;
        token.into_session(previous.authenticated_at, &self.config.project_id)
    }

    fn context(
        &self,
        request: &SecurityContextRequest,
        session: &FirebaseSession,
    ) -> Result<SecurityContext> {
        let context = SecurityContext {
            schema_version: SECURITY_CONTEXT_SCHEMA_VERSION,
            provider_id: FIREBASE_IDENTITY_PROVIDER_ID.into(),
            app_id: request.app_id.clone(),
            tenant_id: request.tenant_id.clone(),
            audience: request.audience.clone(),
            principal: PrincipalIdentity {
                issuer: self.config.issuer(),
                subject: session.subject.clone(),
            },
            granted_scopes: BTreeSet::new(),
            authenticated_at: session.authenticated_at,
            expires_at: session.expires_at,
        };
        context
            .validate_for(FIREBASE_IDENTITY_PROVIDER_ID, request, Utc::now())
            .map_err(|_| FirebaseError::InvalidResponse)?;
        Ok(context)
    }
}

#[async_trait]
impl IdentityProvider for FirebaseIdentityProvider {
    fn provider_id(&self) -> &str {
        FIREBASE_IDENTITY_PROVIDER_ID
    }

    async fn security_context(
        &self,
        request: &SecurityContextRequest,
    ) -> std::result::Result<SecurityContext, IdentityProviderError> {
        self.security_context_inner(request)
            .await
            .map_err(Into::into)
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct PasswordRequest<'a> {
    email: &'a str,
    password: &'a str,
    return_secure_token: bool,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct PasswordTokenResponse {
    #[serde(default)]
    kind: Option<String>,
    local_id: String,
    id_token: FirebaseSecret,
    refresh_token: FirebaseSecret,
    expires_in: String,
    #[serde(default)]
    email: Option<String>,
    #[serde(default)]
    display_name: Option<String>,
    #[serde(default)]
    registered: Option<bool>,
}

impl PasswordTokenResponse {
    fn into_session(self, authenticated_at: DateTime<Utc>) -> Result<FirebaseSession> {
        let _ = (self.kind, self.email, self.display_name, self.registered);
        session(
            self.local_id,
            self.id_token,
            self.refresh_token,
            authenticated_at,
            &self.expires_in,
        )
    }
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct RefreshTokenResponse {
    user_id: String,
    id_token: FirebaseSecret,
    refresh_token: FirebaseSecret,
    expires_in: String,
    project_id: String,
    token_type: String,
}

impl RefreshTokenResponse {
    fn into_session(
        self,
        authenticated_at: DateTime<Utc>,
        expected_project_id: &str,
    ) -> Result<FirebaseSession> {
        if self.project_id != expected_project_id || self.token_type != "Bearer" {
            return Err(FirebaseError::InvalidResponse);
        }
        session(
            self.user_id,
            self.id_token,
            self.refresh_token,
            authenticated_at,
            &self.expires_in,
        )
    }
}

fn session(
    subject: String,
    id_token: FirebaseSecret,
    refresh_token: FirebaseSecret,
    authenticated_at: DateTime<Utc>,
    expires_in: &str,
) -> Result<FirebaseSession> {
    let seconds = expires_in
        .parse::<i64>()
        .ok()
        .filter(|value| (60..=86_400).contains(value))
        .ok_or(FirebaseError::InvalidResponse)?;
    if subject.is_empty()
        || subject.len() > 2048
        || subject.chars().any(char::is_control)
        || id_token.is_empty()
        || refresh_token.is_empty()
    {
        return Err(FirebaseError::InvalidResponse);
    }
    Ok(FirebaseSession {
        subject,
        id_token,
        refresh_token,
        authenticated_at,
        expires_at: Utc::now() + Duration::seconds(seconds),
    })
}

fn validate_request(config: &FirebasePublicConfig, request: &SecurityContextRequest) -> Result<()> {
    config.validate()?;
    request
        .validate()
        .map_err(|_| FirebaseError::InvalidRequest)?;
    if request.audience != config.audience() || !request.required_scopes.is_empty() {
        return Err(FirebaseError::InvalidRequest);
    }
    Ok(())
}

fn validate_credential(value: &str, maximum: usize) -> Result<()> {
    if value.is_empty() || value.len() > maximum || value.chars().any(char::is_control) {
        return Err(FirebaseError::InvalidRequest);
    }
    Ok(())
}
