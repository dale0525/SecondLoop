use super::*;
use agent_runtime::{
    credential::{CredentialScope, InMemorySecretStore, SecretId, SecretMaterial, SecretStore},
    storage::Storage,
};
use std::{
    collections::VecDeque,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    time::Duration,
};
use tokio::sync::Mutex;

struct FakeFirebaseHttp {
    responses: Mutex<VecDeque<FirebaseControlResponse>>,
    requests: Mutex<Vec<String>>,
}

struct DeleteFailingSecretStore {
    inner: InMemorySecretStore,
    fail_delete: AtomicBool,
}

#[async_trait]
impl SecretStore for DeleteFailingSecretStore {
    async fn save(
        &self,
        scope: &CredentialScope,
        secret_id: &SecretId,
        value: SecretMaterial,
    ) -> anyhow::Result<()> {
        self.inner.save(scope, secret_id, value).await
    }

    async fn load(
        &self,
        scope: &CredentialScope,
        secret_id: &SecretId,
    ) -> anyhow::Result<Option<SecretMaterial>> {
        self.inner.load(scope, secret_id).await
    }

    async fn delete(&self, scope: &CredentialScope, secret_id: &SecretId) -> anyhow::Result<bool> {
        if self.fail_delete.load(Ordering::SeqCst) {
            anyhow::bail!("injected secret deletion failure");
        }
        self.inner.delete(scope, secret_id).await
    }

    async fn rotate(
        &self,
        scope: &CredentialScope,
        secret_id: &SecretId,
        value: SecretMaterial,
    ) -> anyhow::Result<()> {
        self.inner.rotate(scope, secret_id, value).await
    }
}

#[async_trait]
impl FirebaseControlHttp for FakeFirebaseHttp {
    async fn send(&self, request: FirebaseControlRequest) -> DevkitResult<FirebaseControlResponse> {
        self.requests
            .lock()
            .await
            .push(format!("{} {}", request.method, request.url));
        self.responses.lock().await.pop_front().ok_or_else(internal)
    }
}

fn response(status: u16, body: Value) -> FirebaseControlResponse {
    FirebaseControlResponse {
        status,
        body: serde_json::to_vec(&body).unwrap(),
    }
}

#[tokio::test]
async fn one_click_configuration_binds_project_and_returns_public_web_config() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let mut control = DeveloperControlPlane::cloudflare(
        storage.sqlite_pool(),
        Arc::new(InMemorySecretStore::default()),
        "firebase-test-project",
        "com.example.agent",
        crate::developer_control_plane::CloudflareOAuthDefaults::default(),
    )
    .await
    .unwrap();
    let fake = Arc::new(FakeFirebaseHttp {
        responses: Mutex::new(VecDeque::from([
            response(
                200,
                json!({
                    "access_token": "google-access-token",
                    "refresh_token": "google-refresh-token",
                    "expires_in": 3600,
                    "scope": format!("{GOOGLE_SCOPE_CLOUD} {GOOGLE_SCOPE_FIREBASE}"),
                    "token_type": "Bearer"
                }),
            ),
            response(
                200,
                json!({
                    "projects": [{
                        "projectId": "another-project-456",
                        "projectNumber": "987654321",
                        "name": "Another Project",
                        "lifecycleState": "ACTIVE"
                    }],
                    "nextPageToken": "projects-next/with+reserved"
                }),
            ),
            response(
                200,
                json!({
                    "projects": [{
                        "projectId": "sample-project-123",
                        "projectNumber": "123456789",
                        "name": "Sample Project",
                        "lifecycleState": "ACTIVE"
                    }]
                }),
            ),
            response(200, json!({"projectId": "sample-project-123"})),
            response(200, json!({"name": "operations/enable-auth", "done": true})),
            response(200, json!({"signIn": {"email": {"enabled": true}}})),
            response(
                200,
                json!({
                    "apps": [{
                        "name": "projects/sample-project-123/webApps/1:123:web:other",
                        "displayName": "Another App"
                    }],
                    "nextPageToken": "apps-next/with+reserved"
                }),
            ),
            response(
                200,
                json!({
                    "apps": [{
                        "name": "projects/sample-project-123/webApps/1:123:web:abc",
                        "displayName": "AgentWeave · com.example.agent"
                    }]
                }),
            ),
            response(
                200,
                json!({
                    "projectId": "sample-project-123",
                    "appId": "1:123:web:abc",
                    "apiKey": "public-firebase-web-key",
                    "authDomain": "sample-project-123.firebaseapp.com"
                }),
            ),
        ])),
        requests: Mutex::new(Vec::new()),
    });
    control.firebase_http = fake.clone();

    let start = control
        .start_firebase_authorization(
            FirebaseOAuthClientSelection::Custom {
                client_id: "desktop-client.apps.googleusercontent.com".into(),
                client_secret: None,
            },
            Url::parse("http://127.0.0.1:43892/firebase/callback").unwrap(),
        )
        .await
        .unwrap();
    let state = Url::parse(&start.authorization_url)
        .unwrap()
        .query_pairs()
        .find(|(name, _)| name == "state")
        .unwrap()
        .1
        .into_owned();
    let status = control
        .complete_firebase_authorization(&format!(
            "http://127.0.0.1:43892/firebase/callback?code=one-time-code&state={state}"
        ))
        .await
        .unwrap();
    assert_eq!(status.phase, FirebaseAuthorizationPhase::SelectProject);

    let receipt = control
        .configure_firebase_project("sample-project-123")
        .await
        .unwrap();
    assert_eq!(receipt.project_id, "sample-project-123");
    assert_eq!(
        receipt.public_config.firebase_web_key,
        "public-firebase-web-key"
    );
    let status = control.firebase_authorization_status().await.unwrap();
    assert_eq!(status.phase, FirebaseAuthorizationPhase::Ready);
    assert_eq!(status.project_id.as_deref(), Some("sample-project-123"));
    let requests = fake.requests.lock().await;
    assert!(
        requests
            .iter()
            .any(|request| request.contains("identitytoolkit.googleapis.com/v2"))
    );
    assert!(requests.iter().any(|request| {
        request.contains("cloudresourcemanager.googleapis.com/v1/projects")
            && request.contains("pageToken=projects-next%2Fwith%2Breserved")
    }));
    assert!(requests.iter().any(|request| {
        request.contains("firebase.googleapis.com/v1beta1/projects/sample-project-123/webApps")
            && request.contains("pageToken=apps-next%2Fwith%2Breserved")
    }));
    assert!(!serde_json::to_string(&status).unwrap().contains("token"));
}

#[tokio::test]
async fn expired_google_access_token_refreshes_without_reauthorizing() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let mut control = DeveloperControlPlane::cloudflare(
        storage.sqlite_pool(),
        Arc::new(InMemorySecretStore::default()),
        "firebase-refresh-test-project",
        "com.example.agent",
        crate::developer_control_plane::CloudflareOAuthDefaults::default(),
    )
    .await
    .unwrap();
    let fake = Arc::new(FakeFirebaseHttp {
        responses: Mutex::new(VecDeque::from([
            response(
                200,
                json!({
                    "access_token": "initial-google-access-token",
                    "refresh_token": "persistent-google-refresh-token",
                    "expires_in": 3600,
                    "scope": format!("{GOOGLE_SCOPE_CLOUD} {GOOGLE_SCOPE_FIREBASE}"),
                    "token_type": "Bearer"
                }),
            ),
            response(
                200,
                json!({
                    "access_token": "refreshed-google-access-token",
                    "expires_in": 3600,
                    "scope": format!("{GOOGLE_SCOPE_CLOUD} {GOOGLE_SCOPE_FIREBASE}"),
                    "token_type": "Bearer"
                }),
            ),
            response(
                200,
                json!({
                    "projects": [{
                        "projectId": "sample-project-123",
                        "projectNumber": "123456789",
                        "name": "Sample Project",
                        "lifecycleState": "ACTIVE"
                    }]
                }),
            ),
        ])),
        requests: Mutex::new(Vec::new()),
    });
    control.firebase_http = fake.clone();

    let start = control
        .start_firebase_authorization(
            FirebaseOAuthClientSelection::Custom {
                client_id: "desktop-client.apps.googleusercontent.com".into(),
                client_secret: Some("desktop-client-secret".into()),
            },
            Url::parse("http://127.0.0.1:43893/firebase/callback").unwrap(),
        )
        .await
        .unwrap();
    let state = Url::parse(&start.authorization_url)
        .unwrap()
        .query_pairs()
        .find(|(name, _)| name == "state")
        .unwrap()
        .1
        .into_owned();
    control
        .complete_firebase_authorization(&format!(
            "http://127.0.0.1:43893/firebase/callback?code=one-time-code&state={state}"
        ))
        .await
        .unwrap();
    let forced_expiry = now_unix_ms().saturating_add(1);
    sqlx::query("UPDATE developer_provider_authorizations SET authorization_json = json_set(authorization_json, '$.expires_at_unix_ms', ?1) WHERE project_key = ?2 AND provider_id = ?3")
        .bind(forced_expiry as i64)
        .bind(&control.project_key)
        .bind(FIREBASE_DEVELOPER_PROVIDER_ID)
        .execute(&control.pool)
        .await
        .unwrap();

    let projects = control.list_firebase_projects().await.unwrap();

    assert_eq!(projects[0].project_id, "sample-project-123");
    let refreshed = control
        .load_firebase_authorization()
        .await
        .unwrap()
        .unwrap();
    assert!(refreshed.expires_at_unix_ms().unwrap() > forced_expiry);
    assert!(refreshed.refresh_token_handle().is_some());
    let requests = fake.requests.lock().await;
    assert_eq!(
        requests
            .iter()
            .filter(|request| request.contains("oauth2.googleapis.com/token"))
            .count(),
        2
    );
}

#[tokio::test]
async fn transient_token_exchange_failure_preserves_the_pending_authorization() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let mut control = DeveloperControlPlane::cloudflare(
        storage.sqlite_pool(),
        Arc::new(InMemorySecretStore::default()),
        "firebase-retry-test-project",
        "com.example.agent",
        crate::developer_control_plane::CloudflareOAuthDefaults::default(),
    )
    .await
    .unwrap();
    let fake = Arc::new(FakeFirebaseHttp {
        responses: Mutex::new(VecDeque::from([
            response(503, json!({})),
            response(
                200,
                json!({
                    "access_token": "google-access-token",
                    "refresh_token": "google-refresh-token",
                    "expires_in": 3600,
                    "scope": format!("{GOOGLE_SCOPE_CLOUD} {GOOGLE_SCOPE_FIREBASE}"),
                    "token_type": "Bearer"
                }),
            ),
        ])),
        requests: Mutex::new(Vec::new()),
    });
    control.firebase_http = fake.clone();
    let start = control
        .start_firebase_authorization(
            FirebaseOAuthClientSelection::Custom {
                client_id: "desktop-client.apps.googleusercontent.com".into(),
                client_secret: None,
            },
            Url::parse("http://127.0.0.1:43894/firebase/callback").unwrap(),
        )
        .await
        .unwrap();
    let state = Url::parse(&start.authorization_url)
        .unwrap()
        .query_pairs()
        .find(|(name, _)| name == "state")
        .unwrap()
        .1
        .into_owned();
    let callback =
        format!("http://127.0.0.1:43894/firebase/callback?code=one-time-code&state={state}");

    assert_eq!(
        control
            .complete_firebase_authorization(&callback)
            .await
            .unwrap_err()
            .code,
        DevkitErrorCode::Unavailable
    );
    assert_eq!(
        control.firebase_authorization_status().await.unwrap().phase,
        FirebaseAuthorizationPhase::AwaitingCallback
    );
    assert_eq!(
        control
            .complete_firebase_authorization(&callback)
            .await
            .unwrap()
            .phase,
        FirebaseAuthorizationPhase::SelectProject
    );
    assert_eq!(fake.requests.lock().await.len(), 2);
}

#[tokio::test]
async fn invalid_token_exchange_consumes_the_pending_authorization() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let mut control = DeveloperControlPlane::cloudflare(
        storage.sqlite_pool(),
        Arc::new(InMemorySecretStore::default()),
        "firebase-invalid-code-test-project",
        "com.example.agent",
        crate::developer_control_plane::CloudflareOAuthDefaults::default(),
    )
    .await
    .unwrap();
    let fake = Arc::new(FakeFirebaseHttp {
        responses: Mutex::new(VecDeque::from([response(400, json!({}))])),
        requests: Mutex::new(Vec::new()),
    });
    control.firebase_http = fake.clone();
    let start = control
        .start_firebase_authorization(
            FirebaseOAuthClientSelection::Custom {
                client_id: "desktop-client.apps.googleusercontent.com".into(),
                client_secret: None,
            },
            Url::parse("http://127.0.0.1:43895/firebase/callback").unwrap(),
        )
        .await
        .unwrap();
    let state = Url::parse(&start.authorization_url)
        .unwrap()
        .query_pairs()
        .find(|(name, _)| name == "state")
        .unwrap()
        .1
        .into_owned();
    let callback =
        format!("http://127.0.0.1:43895/firebase/callback?code=invalid-code&state={state}");

    assert_eq!(
        control
            .complete_firebase_authorization(&callback)
            .await
            .unwrap_err()
            .code,
        DevkitErrorCode::InvalidAuthorization
    );
    assert_eq!(
        control
            .complete_firebase_authorization(&callback)
            .await
            .unwrap_err()
            .code,
        DevkitErrorCode::InvalidAuthorization
    );
    assert_eq!(fake.requests.lock().await.len(), 1);
}

#[tokio::test]
async fn cancel_is_idempotent_when_pending_secret_cleanup_fails() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let secrets = Arc::new(DeleteFailingSecretStore {
        inner: InMemorySecretStore::default(),
        fail_delete: AtomicBool::new(false),
    });
    let control = DeveloperControlPlane::cloudflare(
        storage.sqlite_pool(),
        secrets.clone(),
        "firebase-cancel-test-project",
        "com.example.agent",
        crate::developer_control_plane::CloudflareOAuthDefaults::default(),
    )
    .await
    .unwrap();
    control
        .start_firebase_authorization(
            FirebaseOAuthClientSelection::Custom {
                client_id: "desktop-client.apps.googleusercontent.com".into(),
                client_secret: None,
            },
            Url::parse("http://127.0.0.1:43896/firebase/callback").unwrap(),
        )
        .await
        .unwrap();
    secrets.fail_delete.store(true, Ordering::SeqCst);

    assert_eq!(
        control.cancel_firebase_authorization().await.unwrap().phase,
        FirebaseAuthorizationPhase::Disconnected
    );
    assert_eq!(
        control.cancel_firebase_authorization().await.unwrap().phase,
        FirebaseAuthorizationPhase::Disconnected
    );
}

#[tokio::test]
async fn cancel_does_not_self_deadlock_when_existing_authorization_needs_refresh() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let mut control = DeveloperControlPlane::cloudflare(
        storage.sqlite_pool(),
        Arc::new(InMemorySecretStore::default()),
        "firebase-cancel-refresh-test-project",
        "com.example.agent",
        crate::developer_control_plane::CloudflareOAuthDefaults::default(),
    )
    .await
    .unwrap();
    let fake = Arc::new(FakeFirebaseHttp {
        responses: Mutex::new(VecDeque::from([
            response(
                200,
                json!({
                    "access_token": "initial-google-access-token",
                    "refresh_token": "persistent-google-refresh-token",
                    "expires_in": 3600,
                    "scope": format!("{GOOGLE_SCOPE_CLOUD} {GOOGLE_SCOPE_FIREBASE}"),
                    "token_type": "Bearer"
                }),
            ),
            response(
                200,
                json!({
                    "access_token": "refreshed-google-access-token",
                    "expires_in": 3600,
                    "scope": format!("{GOOGLE_SCOPE_CLOUD} {GOOGLE_SCOPE_FIREBASE}"),
                    "token_type": "Bearer"
                }),
            ),
        ])),
        requests: Mutex::new(Vec::new()),
    });
    control.firebase_http = fake;
    let start = control
        .start_firebase_authorization(
            FirebaseOAuthClientSelection::Custom {
                client_id: "desktop-client.apps.googleusercontent.com".into(),
                client_secret: None,
            },
            Url::parse("http://127.0.0.1:43897/firebase/callback").unwrap(),
        )
        .await
        .unwrap();
    let state = Url::parse(&start.authorization_url)
        .unwrap()
        .query_pairs()
        .find(|(name, _)| name == "state")
        .unwrap()
        .1
        .into_owned();
    control
        .complete_firebase_authorization(&format!(
            "http://127.0.0.1:43897/firebase/callback?code=one-time-code&state={state}"
        ))
        .await
        .unwrap();
    sqlx::query("UPDATE developer_provider_authorizations SET authorization_json = json_set(authorization_json, '$.expires_at_unix_ms', ?1) WHERE project_key = ?2 AND provider_id = ?3")
        .bind(now_unix_ms().saturating_add(1) as i64)
        .bind(&control.project_key)
        .bind(FIREBASE_DEVELOPER_PROVIDER_ID)
        .execute(&control.pool)
        .await
        .unwrap();

    let status = tokio::time::timeout(
        Duration::from_secs(1),
        control.cancel_firebase_authorization(),
    )
    .await
    .expect("cancel must not self-deadlock")
    .unwrap();

    assert_eq!(status.phase, FirebaseAuthorizationPhase::SelectProject);
}

#[test]
fn operation_names_reject_parent_path_segments() {
    assert_eq!(
        validate_operation_name("operations/../../admin")
            .unwrap_err()
            .code,
        DevkitErrorCode::RemoteProtocol
    );
}
