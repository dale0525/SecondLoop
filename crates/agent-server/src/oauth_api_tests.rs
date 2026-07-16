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
    structured_content::{
        StructuredActionBindingRequest, StructuredActionConstraints, StructuredActionIntent,
        StructuredContentAudience,
    },
    structured_content_store::PublishStructuredContentRequest,
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
    api::router(oauth_state().await)
}

async fn oauth_state() -> Arc<AppState> {
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
            app_id: "dev.agentweave.default".to_string(),
            tenant_id: "local".to_string(),
            user_id: "local-user".to_string(),
        },
        "http://127.0.0.1:49152/oauth/callback",
        vault,
        vec![Arc::new(FakeProvider)],
    )
    .await
    .unwrap();
    Arc::new(AppState::new(storage).with_oauth_broker(broker))
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

#[tokio::test]
async fn callback_publishes_the_next_structured_content_revision_without_secrets() {
    let state = oauth_state().await;
    let session = state
        .storage()
        .create_scoped_session(state.conversation_scope(), "OAuth card")
        .await
        .unwrap();
    let now = Utc::now();
    let published = state
        .structured_content()
        .publish(
            &session.id,
            Some("turn-oauth"),
            oauth_card_request(now, "oauth-card", "oauth-card-1"),
            now,
        )
        .await
        .unwrap();
    let binding_id = &published.bindings[0].binding_id;
    let app = api::router(state.clone());
    let accepted = app
        .clone()
        .oneshot(json_request(
            "POST",
            &format!(
                "/sessions/{}/structured-actions/{binding_id}/accept",
                session.id
            ),
            json!({"input":{}}),
        ))
        .await
        .unwrap();
    assert_eq!(accepted.status(), StatusCode::OK);
    let accepted = read_json(accepted).await;
    let authorization_id = accepted["hostDirective"]["authorization_id"]
        .as_str()
        .unwrap();
    let authorization_url = accepted["hostDirective"]["url"].as_str().unwrap();
    let oauth_state = Url::parse(authorization_url)
        .unwrap()
        .query_pairs()
        .find_map(|(key, value)| (key == "state").then(|| value.into_owned()))
        .unwrap();
    let before_callback = state
        .storage()
        .list_conversation_events(state.conversation_scope(), &session.id)
        .await
        .unwrap();
    let callback_cursor = before_callback.last().unwrap().event_index;

    let callback = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!(
                    "/oauth/callback?state={oauth_state}&code=provider-code"
                ))
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
    for secret in [&oauth_state, "provider-code", "access-token"] {
        assert!(!callback_body.contains(secret));
    }

    let events = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!(
                    "/sessions/{}/events?after={callback_cursor}&limit=100&waitMs=0",
                    session.id
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(events.status(), StatusCode::OK);
    let events = read_json(events).await;
    assert_eq!(events["events"].as_array().unwrap().len(), 1);
    assert_eq!(events["events"][0]["payload"]["content"]["revision"], 3);
    assert_eq!(
        events["events"][0]["payload"]["content"]["payload"]["status"]["label"],
        "Completed"
    );
    assert_eq!(
        events["events"][0]["payload"]["content"]["payload"]["fields"][1]["label"],
        "Capabilities"
    );
    let serialized = events.to_string();
    for secret in [
        &oauth_state,
        "provider-code",
        "access-token",
        "refresh-token",
        "credentialId",
    ] {
        assert!(!serialized.contains(secret));
    }

    let status = app
        .oneshot(
            Request::builder()
                .uri(format!("/host/oauth/authorizations/{authorization_id}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(read_json(status).await["status"], "completed");
}

#[tokio::test]
async fn host_cancellation_advances_the_structured_card_after_browser_open_failure() {
    let state = oauth_state().await;
    let session = state
        .storage()
        .create_scoped_session(state.conversation_scope(), "OAuth cancellation")
        .await
        .unwrap();
    let now = Utc::now();
    let published = state
        .structured_content()
        .publish(
            &session.id,
            None,
            oauth_card_request(now, "cancel-card", "cancel-card-1"),
            now,
        )
        .await
        .unwrap();
    let app = api::router(state.clone());
    let accepted = read_json(
        app.clone()
            .oneshot(json_request(
                "POST",
                &format!(
                    "/sessions/{}/structured-actions/{}/accept",
                    session.id, published.bindings[0].binding_id
                ),
                json!({"input":{}}),
            ))
            .await
            .unwrap(),
    )
    .await;
    let authorization_id = accepted["hostDirective"]["authorization_id"]
        .as_str()
        .unwrap();

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
    let content = state
        .structured_content()
        .get(&session.id, "cancel-card")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(content.revision, 3);
    assert_eq!(content.payload["status"]["label"], "Cancelled");
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

fn oauth_card_request(
    now: chrono::DateTime<Utc>,
    content_id: &str,
    idempotency_key: &str,
) -> PublishStructuredContentRequest {
    PublishStructuredContentRequest {
        content_id: Some(content_id.into()),
        expected_revision: None,
        mime_type: "application/vnd.agentweave.card+json".into(),
        schema_version: "1".into(),
        payload: json!({
            "title":"Connect calendar",
            "status":{"label":"Authorization required","tone":"info"},
            "actions":[{"id":"authorize","label":"Continue","style":"primary"}]
        }),
        fallback_text: "Connect calendar".into(),
        audience: StructuredContentAudience::User,
        bindings: vec![StructuredActionBindingRequest {
            action_id: "authorize".into(),
            intent: StructuredActionIntent::OauthStart,
            idempotency_key: idempotency_key.into(),
            expires_at: now + ChronoDuration::minutes(10),
            parameters: json!({
                "providerId":"workspace",
                "connectorIds":["calendar"],
                "requestedCapabilities":["read"]
            }),
            input_schema: json!({
                "type":"object",
                "properties":{},
                "required":[],
                "additionalProperties":false
            }),
            constraints: StructuredActionConstraints {
                provider_ids: vec!["workspace".into()],
                connector_ids: vec!["calendar".into()],
                capabilities: vec!["read".into()],
            },
        }],
    }
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
