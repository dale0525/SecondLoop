use super::*;
use crate::api;
use agent_runtime::{
    credential::{CredentialScope, CredentialVault, InMemorySecretStore, SecretMaterial},
    credential_sqlite::SqliteCredentialMetadataStore,
    oauth::{
        OAuthAuthorizationPlan, OAuthAuthorizationUrlRequest, OAuthCodeExchangeRequest,
        OAuthProvider, OAuthProviderError, OAuthProviderErrorCode, OAuthRefreshRequest,
        OAuthTokenGrant,
    },
    storage::Storage,
};
use async_trait::async_trait;
use axum::{body::Body, http::Request};
use chrono::Duration as ChronoDuration;
use serde_json::{Value, json};
use std::collections::{BTreeMap, BTreeSet};
use tower::ServiceExt;
use url::Url;

struct FakeProvider;

#[async_trait]
impl OAuthProvider for FakeProvider {
    fn provider_id(&self) -> &str {
        "workspace"
    }

    fn authorization_origin(&self) -> &str {
        "https://accounts.example.test"
    }

    fn authorization_plan(
        &self,
        connector_ids: &BTreeSet<String>,
        capabilities: &BTreeSet<String>,
    ) -> Result<OAuthAuthorizationPlan, OAuthProviderError> {
        if connector_ids != &BTreeSet::from(["calendar".to_string()])
            || capabilities != &BTreeSet::from(["read".to_string()])
        {
            return Err(OAuthProviderError::new(
                OAuthProviderErrorCode::InvalidRequest,
            ));
        }
        Ok(OAuthAuthorizationPlan {
            requested_scopes: BTreeSet::from(["calendar.read".to_string()]),
            connector_scopes: BTreeMap::from([(
                "calendar".to_string(),
                BTreeSet::from(["calendar.read".to_string()]),
            )]),
        })
    }

    fn authorization_url(
        &self,
        _request: OAuthAuthorizationUrlRequest,
    ) -> Result<String, OAuthProviderError> {
        Ok("https://accounts.example.test/authorize?client_id=test".into())
    }

    async fn exchange_code(
        &self,
        request: OAuthCodeExchangeRequest,
    ) -> Result<OAuthTokenGrant, OAuthProviderError> {
        if request.code.expose() != "provider-code" {
            return Err(OAuthProviderError::new(
                OAuthProviderErrorCode::ExchangeFailed,
            ));
        }
        Ok(OAuthTokenGrant {
            provider_subject: "user@example.test".to_string(),
            access_token: SecretMaterial::new("access-token")
                .map_err(|_| OAuthProviderError::new(OAuthProviderErrorCode::ExchangeFailed))?,
            refresh_token: None,
            granted_scopes: BTreeSet::from(["calendar.read".to_string()]),
            expires_at: Some(Utc::now() + ChronoDuration::hours(1)),
        })
    }

    async fn refresh_token(
        &self,
        _request: OAuthRefreshRequest,
    ) -> Result<OAuthTokenGrant, OAuthProviderError> {
        Err(OAuthProviderError::new(
            OAuthProviderErrorCode::RefreshFailed,
        ))
    }
}

async fn oauth_app() -> axum::Router {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let metadata = SqliteCredentialMetadataStore::from_storage(&storage)
        .await
        .unwrap();
    let vault = Arc::new(CredentialVault::new_persistent(
        Arc::new(InMemorySecretStore::default()),
        metadata,
    ));
    let broker = agent_runtime::oauth::OAuthBroker::new(
        &storage,
        CredentialScope {
            app_id: "com.example.oauth-api".to_string(),
            tenant_id: "local".to_string(),
            user_id: "user".to_string(),
        },
        "http://127.0.0.1:49152/oauth/callback",
        vault,
        vec![Arc::new(FakeProvider)],
    )
    .await
    .unwrap();
    api::router(Arc::new(AppState::new(storage).with_oauth_broker(broker)))
}

#[tokio::test]
async fn protected_api_starts_polls_and_cancels_without_exposing_secrets() {
    let app = oauth_app().await;
    let start = app
        .clone()
        .oneshot(json_request(
            "POST",
            "/host/oauth/authorizations",
            json!({
                "providerId": "workspace",
                "connectorIds": ["calendar"],
                "requestedCapabilities": ["read"]
            }),
        ))
        .await
        .unwrap();
    assert_eq!(start.status(), StatusCode::OK);
    assert_eq!(start.headers()[header::CACHE_CONTROL], "no-store");
    assert_eq!(start.headers()[header::PRAGMA], "no-cache");
    let start = read_json(start).await;
    let authorization_id = start["authorizationId"].as_str().unwrap();
    assert_eq!(
        start["authorizationOrigin"],
        "https://accounts.example.test"
    );
    assert_eq!(start["status"], "pending");
    assert!(start.get("credentialId").is_none());
    assert!(start.get("state").is_none());
    assert!(start.get("code").is_none());
    assert!(start.get("verifier").is_none());
    assert!(start.get("token").is_none());

    let pending = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("/host/oauth/authorizations/{authorization_id}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(pending.status(), StatusCode::OK);
    assert_eq!(pending.headers()[header::CACHE_CONTROL], "no-store");
    let pending = read_json(pending).await;
    assert_eq!(pending["status"], "pending");
    assert!(pending.get("authorizationUrl").is_none());

    let cancelled = app
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!("/host/oauth/authorizations/{authorization_id}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(cancelled.status(), StatusCode::OK);
    assert_eq!(cancelled.headers()[header::CACHE_CONTROL], "no-store");
    assert_eq!(read_json(cancelled).await["status"], "cancelled");
}

#[tokio::test]
async fn callback_consumes_state_once_and_returns_only_static_pages() {
    let app = oauth_app().await;
    let start = app
        .clone()
        .oneshot(json_request(
            "POST",
            "/host/oauth/authorizations",
            json!({
                "providerId": "workspace",
                "connectorIds": ["calendar"],
                "requestedCapabilities": ["read"]
            }),
        ))
        .await
        .unwrap();
    let start = read_json(start).await;
    let authorization_id = start["authorizationId"].as_str().unwrap().to_string();
    let state = Url::parse(start["authorizationUrl"].as_str().unwrap())
        .unwrap()
        .query_pairs()
        .find_map(|(key, value)| (key == "state").then(|| value.into_owned()))
        .unwrap();
    let callback_uri = format!("/oauth/callback?state={state}&error=access_denied");
    let callback = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(&callback_uri)
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(callback.status(), StatusCode::OK);
    assert_eq!(
        callback.headers()[header::CONTENT_SECURITY_POLICY],
        "default-src 'none'"
    );
    let callback_body = String::from_utf8(
        axum::body::to_bytes(callback.into_body(), 16 * 1024)
            .await
            .unwrap()
            .to_vec(),
    )
    .unwrap();
    assert!(callback_body.contains("Authorization not completed"));
    assert!(!callback_body.contains(&state));
    assert!(!callback_body.contains("access_denied"));

    let replay = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(&callback_uri)
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(replay.status(), StatusCode::BAD_REQUEST);

    let status = app
        .oneshot(
            Request::builder()
                .uri(format!("/host/oauth/authorizations/{authorization_id}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let status = read_json(status).await;
    assert_eq!(status["status"], "denied");
    assert_eq!(status["errorCode"], "access_denied");
}

#[tokio::test]
async fn callback_completes_with_code_and_ignores_provider_parameters() {
    let app = oauth_app().await;
    let start = app
        .clone()
        .oneshot(json_request(
            "POST",
            "/host/oauth/authorizations",
            json!({
                "providerId": "workspace",
                "connectorIds": ["calendar"],
                "requestedCapabilities": ["read"]
            }),
        ))
        .await
        .unwrap();
    let start = read_json(start).await;
    let authorization_id = start["authorizationId"].as_str().unwrap().to_string();
    let state = Url::parse(start["authorizationUrl"].as_str().unwrap())
        .unwrap()
        .query_pairs()
        .find_map(|(key, value)| (key == "state").then(|| value.into_owned()))
        .unwrap();
    let provider_detail = "private-provider-detail";
    let callback_uri = format!(
        "/oauth/callback?state={state}&code=provider-code&scope=calendar.read&provider_detail={provider_detail}"
    );
    let callback = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(&callback_uri)
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(callback.status(), StatusCode::OK);
    let callback_body = String::from_utf8(
        axum::body::to_bytes(callback.into_body(), 16 * 1024)
            .await
            .unwrap()
            .to_vec(),
    )
    .unwrap();
    assert!(callback_body.contains("Authorization complete"));
    for secret in [&state, "provider-code", provider_detail] {
        assert!(!callback_body.contains(secret));
    }

    let completed = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("/host/oauth/authorizations/{authorization_id}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let completed = read_json(completed).await;
    assert_eq!(completed["status"], "completed");
    assert_eq!(completed["bindings"].as_array().unwrap().len(), 1);
    let serialized = completed.to_string();
    for secret in ["provider-code", "access-token", "credentialId", "verifier"] {
        assert!(!serialized.contains(secret));
    }

    let replay = app
        .oneshot(
            Request::builder()
                .uri(&callback_uri)
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(replay.status(), StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn callback_rejects_an_unissued_high_entropy_state_without_echoing_it() {
    let app = oauth_app().await;
    let state = "a".repeat(64);
    let response = app
        .oneshot(
            Request::builder()
                .uri(format!(
                    "/oauth/callback?state={state}&code=private-provider-code"
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    let body = String::from_utf8(
        axum::body::to_bytes(response.into_body(), 16 * 1024)
            .await
            .unwrap()
            .to_vec(),
    )
    .unwrap();
    assert!(body.contains("Authorization not completed"));
    assert!(!body.contains(&state));
    assert!(!body.contains("private-provider-code"));
}

#[test]
fn callback_query_rejects_low_entropy_duplicates_and_malformed_escapes() {
    for query in [
        None,
        Some("state=short&code=code"),
        Some(
            "state=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa&state=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb&code=code",
        ),
        Some("state=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa&code=%GG"),
    ] {
        assert!(matches!(
            parse_callback_query(query),
            Err(CallbackQueryError::Invalid)
        ));
    }

    let oversized = format!(
        "state={}&code={}",
        "a".repeat(64),
        "x".repeat(MAX_CALLBACK_QUERY_BYTES)
    );
    assert!(matches!(
        parse_callback_query(Some(&oversized)),
        Err(CallbackQueryError::TooLarge)
    ));
}

fn json_request(method: &str, uri: &str, value: Value) -> Request<Body> {
    Request::builder()
        .method(method)
        .uri(uri)
        .header(header::CONTENT_TYPE, "application/json")
        .body(Body::from(serde_json::to_vec(&value).unwrap()))
        .unwrap()
}

async fn read_json(response: Response) -> Value {
    serde_json::from_slice(
        &axum::body::to_bytes(response.into_body(), 1024 * 1024)
            .await
            .unwrap(),
    )
    .unwrap()
}
