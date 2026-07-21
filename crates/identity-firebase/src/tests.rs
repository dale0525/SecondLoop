use super::*;
use agent_runtime::identity::{IdentityProvider, SecurityContextRequest};
use async_trait::async_trait;
use chrono::{Duration, Utc};
use std::{
    collections::BTreeSet,
    sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    },
};
use tokio::sync::Mutex;
use url::Url;

#[derive(Default)]
struct MemoryStore(Mutex<Option<FirebaseSession>>);

struct LoadCountingStore {
    session: Mutex<Option<FirebaseSession>>,
    loads: AtomicUsize,
}

#[async_trait]
impl FirebaseSessionStore for MemoryStore {
    async fn load_session(&self) -> Result<Option<FirebaseSession>> {
        Ok(self.0.lock().await.clone())
    }

    async fn save_session(&self, session: FirebaseSession) -> Result<()> {
        *self.0.lock().await = Some(session);
        Ok(())
    }

    async fn delete_session(&self) -> Result<()> {
        *self.0.lock().await = None;
        Ok(())
    }
}

#[async_trait]
impl FirebaseSessionStore for LoadCountingStore {
    async fn load_session(&self) -> Result<Option<FirebaseSession>> {
        self.loads.fetch_add(1, Ordering::SeqCst);
        Ok(self.session.lock().await.clone())
    }

    async fn save_session(&self, session: FirebaseSession) -> Result<()> {
        *self.session.lock().await = Some(session);
        Ok(())
    }

    async fn delete_session(&self) -> Result<()> {
        *self.session.lock().await = None;
        Ok(())
    }
}

struct FakeHttp(Mutex<Vec<FirebaseHttpResponse>>);

#[async_trait]
impl FirebaseHttpClient for FakeHttp {
    async fn post_json(&self, url: Url, body: Vec<u8>) -> Result<FirebaseHttpResponse> {
        assert_eq!(url.host_str(), Some("identitytoolkit.googleapis.com"));
        let request: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(request["email"], "person@example.test");
        assert_eq!(request["password"], "password-sentinel");
        self.next().await
    }

    async fn post_form(
        &self,
        url: Url,
        form: Vec<(String, FirebaseSecret)>,
    ) -> Result<FirebaseHttpResponse> {
        assert_eq!(url.host_str(), Some("securetoken.googleapis.com"));
        assert_eq!(form[0].1.expose_secret(), "refresh_token");
        self.next().await
    }
}

impl FakeHttp {
    async fn next(&self) -> Result<FirebaseHttpResponse> {
        Ok(self.0.lock().await.remove(0))
    }
}

fn config() -> FirebasePublicConfig {
    FirebasePublicConfig {
        project_id: "sample-project-123".into(),
        firebase_web_key: "public-web-identifier".into(),
        web_application_id: "1:123:web:abc".into(),
        auth_domain: Some("sample-project-123.firebaseapp.com".into()),
    }
}

fn request() -> SecurityContextRequest {
    SecurityContextRequest {
        app_id: "com.example.app".into(),
        tenant_id: "local".into(),
        audience: "sample-project-123".into(),
        required_scopes: BTreeSet::new(),
    }
}

#[test]
fn descriptor_exposes_only_public_firebase_configuration() {
    let descriptor = firebase_identity_provider_descriptor();
    descriptor.validate().unwrap();
    assert_eq!(descriptor.provider_id, FIREBASE_IDENTITY_PROVIDER_ID);
    assert!(descriptor.configuration_schema.sensitive_fields.is_empty());
    assert_eq!(
        config().issuer(),
        "https://securetoken.google.com/sample-project-123"
    );
}

#[tokio::test]
async fn password_login_keeps_credentials_in_the_session_store() {
    let store = Arc::new(MemoryStore::default());
    let http = Arc::new(FakeHttp(Mutex::new(vec![FirebaseHttpResponse {
        status: 200,
        body: serde_json::to_vec(&serde_json::json!({
            "localId": "firebase-subject",
            "email": "person@example.test",
            "displayName": "",
            "idToken": "id-token-sentinel",
            "registered": true,
            "refreshToken": "refresh-token-sentinel",
            "expiresIn": "3600"
        }))
        .unwrap(),
    }])));
    let provider = FirebaseIdentityProvider::new(config(), store.clone(), http).unwrap();
    let context = provider
        .sign_in_with_password(
            &request(),
            FirebaseSecret::new("person@example.test"),
            FirebaseSecret::new("password-sentinel"),
        )
        .await
        .unwrap();

    assert_eq!(context.principal.subject, "firebase-subject");
    assert_eq!(context.audience, "sample-project-123");
    let stored = store.load_session().await.unwrap().unwrap();
    assert_eq!(stored.id_token.expose_secret(), "id-token-sentinel");
    assert!(!format!("{stored:?}").contains("id-token-sentinel"));
}

#[tokio::test]
async fn expired_session_refreshes_before_returning_a_context() {
    let store = Arc::new(MemoryStore(Mutex::new(Some(FirebaseSession {
        subject: "firebase-subject".into(),
        id_token: FirebaseSecret::new("old-token"),
        refresh_token: FirebaseSecret::new("old-refresh"),
        authenticated_at: Utc::now() - Duration::hours(1),
        expires_at: Utc::now() - Duration::seconds(1),
    }))));
    let http = Arc::new(FakeHttp(Mutex::new(vec![FirebaseHttpResponse {
        status: 200,
        body: serde_json::to_vec(&serde_json::json!({
            "expires_in": "3600",
            "token_type": "Bearer",
            "refresh_token": "new-refresh",
            "id_token": "new-id-token",
            "user_id": "firebase-subject",
            "project_id": "sample-project-123"
        }))
        .unwrap(),
    }])));
    let provider = FirebaseIdentityProvider::new(config(), store.clone(), http).unwrap();

    let context = provider.security_context(&request()).await.unwrap();
    assert_eq!(context.principal.subject, "firebase-subject");
    assert_eq!(
        store
            .load_session()
            .await
            .unwrap()
            .unwrap()
            .id_token
            .expose_secret(),
        "new-id-token"
    );
}

#[tokio::test]
async fn refresh_rejects_a_token_from_a_different_firebase_project() {
    let store = Arc::new(MemoryStore(Mutex::new(Some(FirebaseSession {
        subject: "firebase-subject".into(),
        id_token: FirebaseSecret::new("old-token"),
        refresh_token: FirebaseSecret::new("old-refresh"),
        authenticated_at: Utc::now() - Duration::hours(1),
        expires_at: Utc::now() - Duration::seconds(1),
    }))));
    let http = Arc::new(FakeHttp(Mutex::new(vec![FirebaseHttpResponse {
        status: 200,
        body: serde_json::to_vec(&serde_json::json!({
            "expires_in": "3600",
            "token_type": "Bearer",
            "refresh_token": "foreign-refresh",
            "id_token": "foreign-id-token",
            "user_id": "firebase-subject",
            "project_id": "foreign-project-456"
        }))
        .unwrap(),
    }])));
    let provider = FirebaseIdentityProvider::new(config(), store, http).unwrap();

    assert_eq!(
        provider
            .security_context(&request())
            .await
            .unwrap_err()
            .code,
        agent_runtime::identity::IdentityProviderErrorCode::InvalidResponse
    );
}

#[tokio::test]
async fn gateway_assertion_uses_the_session_validated_under_one_gate() {
    let store = Arc::new(LoadCountingStore {
        session: Mutex::new(Some(FirebaseSession {
            subject: "firebase-subject".into(),
            id_token: FirebaseSecret::new("id-token-sentinel"),
            refresh_token: FirebaseSecret::new("refresh-token-sentinel"),
            authenticated_at: Utc::now() - Duration::minutes(1),
            expires_at: Utc::now() + Duration::hours(1),
        })),
        loads: AtomicUsize::new(0),
    });
    let provider = FirebaseIdentityProvider::new(
        config(),
        store.clone(),
        Arc::new(FakeHttp(Mutex::new(Vec::new()))),
    )
    .unwrap();

    let assertion = provider.gateway_assertion(&request()).await.unwrap();

    assert_eq!(assertion.expose_secret(), "id-token-sentinel");
    assert_eq!(store.loads.load(Ordering::SeqCst), 1);
}
