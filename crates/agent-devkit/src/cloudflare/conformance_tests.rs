use super::*;
use crate::{
    ApplyOutcome, CompleteProviderAuthorizationRequest, DeploymentArtifact, DeploymentTarget,
    DesiredDeploymentState, DeveloperAuthorization, DevkitErrorCode, GatewayDeploymentProvider,
    MutationControl, OperationLease, ProviderConfiguration, ReconcileDirective, RollbackRequest,
    RollbackResourceScope, SensitiveInputHandle, SensitiveInputResolver, SensitiveInputStore,
    SensitiveValue, reconcile_directive,
};
use async_trait::async_trait;
use serde_json::{Value, json};
use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::sync::{Arc, Mutex};
use url::Url;
use uuid::Uuid;

enum FakeAction {
    Response(CloudflareTransportResponse),
    Failure(CloudflareTransportFailure),
}

#[derive(Clone, Debug)]
struct RecordedRequest {
    method: CloudflareHttpMethod,
    url: String,
    safe_debug: String,
    redirect_policy: RedirectPolicy,
}

#[derive(Default)]
struct FakeTransport {
    actions: Mutex<VecDeque<FakeAction>>,
    requests: Mutex<Vec<RecordedRequest>>,
}

impl FakeTransport {
    fn with_actions(actions: impl IntoIterator<Item = FakeAction>) -> Self {
        Self {
            actions: Mutex::new(actions.into_iter().collect()),
            requests: Mutex::new(Vec::new()),
        }
    }

    fn requests(&self) -> Vec<RecordedRequest> {
        self.requests.lock().unwrap().clone()
    }

    fn remaining_actions(&self) -> usize {
        self.actions.lock().unwrap().len()
    }
}

#[async_trait]
impl CloudflareTransport for FakeTransport {
    async fn send(
        &self,
        request: CloudflareTransportRequest,
    ) -> Result<CloudflareTransportResponse, CloudflareTransportFailure> {
        self.requests.lock().unwrap().push(RecordedRequest {
            method: request.method(),
            url: request.url().to_string(),
            safe_debug: format!("{request:?}"),
            redirect_policy: request.redirect_policy(),
        });
        match self.actions.lock().unwrap().pop_front() {
            Some(FakeAction::Response(response)) => Ok(response),
            Some(FakeAction::Failure(error)) => Err(error),
            None => Err(CloudflareTransportFailure::protocol(
                "fake transport received an unexpected request",
            )),
        }
    }
}

#[derive(Default)]
struct FakeSecretStore {
    values: Mutex<BTreeMap<String, Vec<u8>>>,
    next_id: Mutex<u64>,
}

impl FakeSecretStore {
    fn insert(&self, name: &str, value: &str) -> SensitiveInputHandle {
        let reference = format!("fake-secret:{name}");
        self.values
            .lock()
            .unwrap()
            .insert(reference.clone(), value.as_bytes().to_vec());
        SensitiveInputHandle::from_opaque_reference(reference).unwrap()
    }
}

#[async_trait]
impl SensitiveInputResolver for FakeSecretStore {
    async fn resolve(&self, handle: &SensitiveInputHandle) -> crate::DevkitResult<SensitiveValue> {
        let value = self
            .values
            .lock()
            .unwrap()
            .get(handle.opaque_reference())
            .cloned()
            .ok_or_else(|| {
                crate::DevkitError::new(
                    DevkitErrorCode::SensitiveInputUnavailable,
                    "fake sensitive input is unavailable",
                )
            })?;
        SensitiveValue::new(value)
    }
}

#[async_trait]
impl SensitiveInputStore for FakeSecretStore {
    async fn store(
        &self,
        namespace: &str,
        value: SensitiveValue,
    ) -> crate::DevkitResult<SensitiveInputHandle> {
        let mut next_id = self.next_id.lock().unwrap();
        *next_id += 1;
        let reference = format!("fake-secret:{namespace}:{}", *next_id);
        let bytes = value.expose(|bytes| Ok(bytes.to_vec()))?;
        self.values.lock().unwrap().insert(reference.clone(), bytes);
        SensitiveInputHandle::from_opaque_reference(reference)
    }
}

fn api_success(result: Value) -> FakeAction {
    FakeAction::Response(CloudflareTransportResponse::json(
        200,
        json!({"success": true, "result": result}),
    ))
}

fn not_found() -> FakeAction {
    FakeAction::Response(CloudflareTransportResponse::json(
        404,
        json!({"success": false}),
    ))
}

fn deployment(desired_hash: &str, version: &str) -> FakeAction {
    let artifact_hash = DeploymentArtifact::new(
        "application/javascript+module",
        b"export default {};".to_vec(),
    )
    .unwrap()
    .sha256()
    .to_owned();
    api_success(json!({
        "deployments": [{
            "id": "deployment-1",
            "versions": [{"version_id": version, "percentage": 100}],
            "etag": format!("etag-{version}"),
            "annotations": {
                "agentweave_desired_hash": desired_hash,
                "agentweave_artifact_hash": artifact_hash,
                "gateway_protocol_version": "1",
                "gateway_url": "https://example-gateway.example-subdomain.workers.dev",
                "gateway_health_url":
                    "https://gateway.example.test/.well-known/agentweave/gateway-health",
                "d1_database_id": "d1-database-1",
                "d1_database_name": "example-gateway-entitlements",
                "d1_migration_hash": super::d1::migration_hash(),
            }
        }]
    }))
}

fn target() -> DeploymentTarget {
    DeploymentTarget {
        provider_id: CLOUDFLARE_PROVIDER_ID.into(),
        account_id: "account-123".into(),
        app_id: "example-app".into(),
        deployment_id: "deployment-1".into(),
        resource_name: "example-gateway".into(),
    }
}

fn control(expected_version: Option<&str>) -> MutationControl {
    MutationControl {
        operation_id: Uuid::new_v4(),
        idempotency_key: format!("deploy-idempotency-{}", Uuid::new_v4()),
        expected_remote_version: expected_version.map(str::to_owned),
        expected_remote_etag: None,
        lease: OperationLease {
            owner_id: "host-process-1".into(),
            lease_version: 1,
            expires_at_unix_ms: 60_000,
        },
    }
}

fn desired() -> DesiredDeploymentState {
    DesiredDeploymentState::new(
        target(),
        "gateway-template-v1",
        DeploymentArtifact::new(
            "application/javascript+module",
            b"export default {};".to_vec(),
        )
        .unwrap(),
        BTreeMap::from([
            (
                "gateway_config".into(),
                json!({
                    "schemaVersion": 1,
                    "deploymentId": "deployment-1",
                    "auth": {"mode": "required"}
                }),
            ),
            (
                "entitlement_bootstrap".into(),
                json!({
                    "schemaVersion": 1,
                    "periodStart": 1,
                    "periodEnd": 4102444800_i64,
                    "replaceSubjects": false,
                    "deployment": {
                        "status": "active",
                        "maxRequests": 100000,
                        "maxUnits": 100000000
                    },
                    "tenants": [],
                    "subjects": []
                }),
            ),
        ]),
        BTreeMap::new(),
        BTreeSet::new(),
    )
    .unwrap()
}

fn d1_database() -> FakeAction {
    api_success(json!([{
        "uuid": "d1-database-1",
        "name": "example-gateway-entitlements"
    }]))
}

fn d1_missing() -> FakeAction {
    api_success(json!([]))
}

fn d1_created() -> FakeAction {
    api_success(json!({
        "uuid": "d1-database-1",
        "name": "example-gateway-entitlements"
    }))
}

fn d1_query_success() -> FakeAction {
    api_success(json!([{"results": [], "success": true}]))
}

fn d1_migration_table() -> FakeAction {
    api_success(json!([{
        "results": [{"name": "agentweave_gateway_migrations"}],
        "success": true
    }]))
}

fn d1_migration_ledger() -> FakeAction {
    let rows = super::d1::expected_migration_hashes()
        .into_iter()
        .map(|(name, sha256)| json!({"name": name, "sha256": sha256}))
        .collect::<Vec<_>>();
    api_success(json!([{"results": rows, "success": true}]))
}

fn workers_dev_subdomain() -> FakeAction {
    api_success(json!({"subdomain": "example-subdomain"}))
}

fn worker_subdomain_enabled() -> FakeAction {
    api_success(json!({"enabled": true, "previews_enabled": false}))
}

fn authorization(store: &FakeSecretStore) -> DeveloperAuthorization {
    DeveloperAuthorization::new(
        CLOUDFLARE_PROVIDER_ID,
        "developer-1",
        "account-123",
        store.insert("cloudflare-access", "top-secret-cloudflare-token"),
        None,
        BTreeSet::from([
            "scope-d1-dynamic".into(),
            "scope-read-dynamic".into(),
            "scope-write-dynamic".into(),
        ]),
        BTreeSet::from([
            CAPABILITY_D1_WRITE.into(),
            CAPABILITY_WORKERS_SCRIPTS_READ.into(),
            CAPABILITY_WORKERS_SCRIPTS_WRITE.into(),
        ]),
        "catalog-revision",
        1,
        None,
    )
    .unwrap()
}

fn unbound_authorization(store: &FakeSecretStore) -> DeveloperAuthorization {
    DeveloperAuthorization::new_unbound(
        CLOUDFLARE_PROVIDER_ID,
        "developer-1",
        store.insert("cloudflare-access-unbound", "top-secret-cloudflare-token"),
        None,
        BTreeSet::from([
            "scope-d1-dynamic".into(),
            "scope-read-dynamic".into(),
            "scope-write-dynamic".into(),
        ]),
        BTreeSet::from([
            CAPABILITY_D1_WRITE.into(),
            CAPABILITY_WORKERS_SCRIPTS_READ.into(),
            CAPABILITY_WORKERS_SCRIPTS_WRITE.into(),
        ]),
        "catalog-revision",
        1,
        None,
    )
    .unwrap()
}

fn configuration() -> ProviderConfiguration {
    ProviderConfiguration {
        schema_version: 1,
        public: BTreeMap::from([
            ("account-id".into(), json!("account-123")),
            ("client-id".into(), json!("oauth-client-123")),
            (
                "callback-uri".into(),
                json!("https://callback.example.test/cloudflare"),
            ),
            (
                "scope-catalog".into(),
                json!({
                    "Workers Scripts Read": "scope-read-dynamic",
                    "Workers Scripts Write": "scope-write-dynamic",
                    "D1 Write": "scope-d1-dynamic"
                }),
            ),
        ]),
        sensitive: BTreeMap::new(),
    }
}

fn provider(
    actions: impl IntoIterator<Item = FakeAction>,
) -> (
    Arc<FakeTransport>,
    Arc<FakeSecretStore>,
    CloudflareGatewayProvider<FakeTransport, FakeSecretStore>,
) {
    let transport = Arc::new(FakeTransport::with_actions(actions));
    let store = Arc::new(FakeSecretStore::default());
    let provider = CloudflareGatewayProvider::with_endpoints(
        "https://api.example.test/client/v4/",
        "https://auth.example.test/oauth2/auth",
        "https://auth.example.test/oauth2/token",
        Arc::clone(&transport),
        Arc::clone(&store),
    )
    .unwrap();
    (transport, store, provider)
}

#[tokio::test]
async fn https_and_origin_pinning_are_enforced_before_transport() {
    let transport = Arc::new(FakeTransport::default());
    let store = Arc::new(FakeSecretStore::default());
    let insecure = CloudflareRestClient::with_api_base(
        "http://api.example.test/client/v4/",
        Arc::clone(&transport),
        Arc::clone(&store),
    );
    let error = match insecure {
        Ok(_) => panic!("insecure Cloudflare API origin must be rejected"),
        Err(error) => error,
    };
    assert_eq!(error.code, DevkitErrorCode::OriginRejected);

    let client = CloudflareRestClient::with_api_base(
        "https://api.example.test/client/v4/",
        Arc::clone(&transport),
        store,
    )
    .unwrap();
    for escaped in [
        "https://evil.example.test/client/v4/accounts",
        "../accounts",
        "/accounts",
        "accounts?id=https://evil.example.test",
    ] {
        let error = client.get_json(None, escaped).await.unwrap_err();
        assert_eq!(error.code, DevkitErrorCode::OriginRejected);
    }
    assert!(transport.requests().is_empty());
}

#[tokio::test]
async fn redirects_are_observed_once_and_rejected() {
    let response = CloudflareTransportResponse::new(
        302,
        BTreeMap::from([("location".into(), "https://evil.example.test/steal".into())]),
        Vec::new(),
    );
    let (transport, store, _) = provider([FakeAction::Response(response)]);
    let client = CloudflareRestClient::with_api_base(
        "https://api.example.test/client/v4/",
        Arc::clone(&transport),
        store,
    )
    .unwrap();
    let error = client.get_json(None, "accounts").await.unwrap_err();
    assert_eq!(error.code, DevkitErrorCode::RedirectRejected);
    let requests = transport.requests();
    assert_eq!(requests.len(), 1);
    assert_eq!(requests[0].redirect_policy, RedirectPolicy::Reject);
    assert_eq!(
        requests[0].url,
        "https://api.example.test/client/v4/accounts"
    );
}

#[tokio::test]
async fn oauth_capabilities_map_to_authoritative_dynamic_scope_ids() {
    let (transport, store, provider) = provider([api_success(json!([
        {"id": "scope-read-dynamic", "name": "Workers Scripts Read"},
        {"id": "scope-write-dynamic", "name": "Workers Scripts Write"},
        {"id": "scope-unrelated", "name": "Account Analytics Read"}
    ]))]);
    let requirements = provider
        .authorization_requirements(
            &configuration(),
            &BTreeSet::from([
                CAPABILITY_WORKERS_SCRIPTS_READ.into(),
                CAPABILITY_WORKERS_SCRIPTS_WRITE.into(),
            ]),
        )
        .await
        .unwrap();
    assert_eq!(
        requirements.scope_ids_by_capability[CAPABILITY_WORKERS_SCRIPTS_READ],
        BTreeSet::from(["scope-read-dynamic".into()])
    );
    assert_eq!(
        requirements.scope_ids_by_capability[CAPABILITY_WORKERS_SCRIPTS_WRITE],
        BTreeSet::from(["scope-write-dynamic".into()])
    );
    assert!(
        !requirements
            .all_scope_ids()
            .contains("workers.scripts.write")
    );
    let rest = CloudflareRestClient::with_api_base(
        "https://api.example.test/client/v4/",
        Arc::clone(&transport),
        Arc::clone(&store),
    )
    .unwrap();
    let oauth = CloudflareOAuthClient::with_endpoints(
        rest,
        "https://auth.example.test/oauth2/auth",
        "https://auth.example.test/oauth2/token",
        Arc::clone(&transport),
        Arc::clone(&store),
    )
    .unwrap();
    let live_catalog = oauth.scope_catalog(&authorization(&store)).await.unwrap();
    assert!(
        live_catalog
            .scopes
            .iter()
            .any(|scope| scope.id == "scope-write-dynamic")
    );
    assert_eq!(
        transport.requests()[0].url,
        "https://api.example.test/client/v4/oauth/scopes"
    );
    assert_eq!(transport.remaining_actions(), 0);
}

#[tokio::test]
async fn oauth_exchange_revalidates_the_scope_catalog_with_the_new_grant() {
    let token_response = FakeAction::Response(CloudflareTransportResponse::json(
        200,
        json!({
            "access_token": "new-cloudflare-access-token",
            "refresh_token": "new-cloudflare-refresh-token",
            "token_type": "bearer",
            "expires_in": 3600,
            "scope": "scope-read-dynamic scope-write-dynamic"
        }),
    ));
    let live_catalog = api_success(json!([
        {"id": "scope-read-dynamic", "name": "Workers Scripts Read"},
        {"id": "scope-write-dynamic", "name": "Workers Scripts Write"}
    ]));
    let (transport, store, provider) = provider([token_response, live_catalog]);
    let requirements = provider
        .authorization_requirements(
            &configuration(),
            &BTreeSet::from([
                CAPABILITY_WORKERS_SCRIPTS_READ.into(),
                CAPABILITY_WORKERS_SCRIPTS_WRITE.into(),
            ]),
        )
        .await
        .unwrap();
    let authorization = provider
        .complete_provider_authorization(CompleteProviderAuthorizationRequest {
            configuration: configuration(),
            redirect_uri: Url::parse("https://callback.example.test/cloudflare").unwrap(),
            code_handle: store.insert("oauth-code", "one-time-oauth-code"),
            pkce_verifier_handle: store.insert("pkce-verifier", &"v".repeat(64)),
            expected_catalog_revision: requirements.catalog_revision.clone(),
            expected_scope_ids: requirements.all_scope_ids(),
            actor_id: "developer-1".into(),
            now_unix_ms: 100,
        })
        .await
        .unwrap();
    assert_eq!(authorization.account_id(), None);
    assert!(authorization.refresh_token_handle().is_some());
    assert!(
        authorization
            .logical_capabilities()
            .contains(CAPABILITY_WORKERS_SCRIPTS_WRITE)
    );
    let requests = transport.requests();
    assert_eq!(requests.len(), 2);
    assert_eq!(requests[0].url, "https://auth.example.test/oauth2/token");
    assert_eq!(
        requests[1].url,
        "https://api.example.test/client/v4/oauth/scopes"
    );
    let debug = requests
        .iter()
        .map(|request| request.safe_debug.as_str())
        .collect::<Vec<_>>()
        .join(" ");
    assert!(!debug.contains("one-time-oauth-code"));
    assert!(!debug.contains("new-cloudflare-access-token"));
}

#[tokio::test]
async fn oauth_account_selection_is_listed_and_revalidated_after_authorization() {
    let accounts = || {
        api_success(json!([
            {"id": "account-b", "name": "Beta"},
            {"id": "account-a", "name": "Alpha"}
        ]))
    };
    let (transport, store, provider) = provider([accounts(), accounts()]);
    let authorization = unbound_authorization(&store);

    let listed = provider
        .list_authorization_accounts(&authorization, 100)
        .await
        .unwrap();
    assert_eq!(
        listed
            .iter()
            .map(|account| account.account_id.as_str())
            .collect::<Vec<_>>(),
        vec!["account-a", "account-b"]
    );
    let bound = provider
        .bind_authorization_account(&authorization, "account-b", 100)
        .await
        .unwrap();
    assert_eq!(bound.account_id(), Some("account-b"));
    assert_eq!(authorization.account_id(), None);
    assert_eq!(transport.requests().len(), 2);
    assert!(
        transport
            .requests()
            .iter()
            .all(|request| request.url.ends_with("/client/v4/accounts"))
    );
}

#[tokio::test]
async fn fixed_loopback_callback_is_supported_without_accepting_ambiguous_http_urls() {
    let (_transport, _store, provider) = provider([]);
    let requested = BTreeSet::from([CAPABILITY_WORKERS_SCRIPTS_READ.into()]);
    let mut loopback = configuration();
    loopback.public.remove("account-id");
    loopback.public.insert(
        "callback-uri".into(),
        json!("http://127.0.0.1:43122/cloudflare/callback"),
    );
    provider
        .authorization_requirements(&loopback, &requested)
        .await
        .unwrap();

    for invalid in [
        "http://127.0.0.1/cloudflare/callback",
        "http://localhost:43122/cloudflare/callback",
        "http://192.0.2.1:43122/cloudflare/callback",
        "http://127.0.0.1:43122/",
        "http://127.0.0.1:43122/cloudflare/callback?code=unsafe",
    ] {
        let mut configuration = loopback.clone();
        configuration
            .public
            .insert("callback-uri".into(), json!(invalid));
        assert!(
            provider
                .authorization_requirements(&configuration, &requested)
                .await
                .is_err(),
            "expected {invalid} to be rejected"
        );
    }
}

#[tokio::test]
async fn planning_performs_reads_only_and_produces_an_integrity_hash() {
    let (transport, store, provider) = provider([not_found(), d1_missing()]);
    let plan = provider
        .plan(&authorization(&store), desired(), control(None), 100)
        .await
        .unwrap();
    plan.verify_integrity().unwrap();
    assert_eq!(plan.hash().as_str().len(), 64);
    assert!(
        plan.operations()
            .iter()
            .any(|operation| operation.kind == crate::PlanOperationKind::CreateScript)
    );
    let requests = transport.requests();
    assert_eq!(requests.len(), 2);
    assert!(
        requests
            .iter()
            .all(|request| request.method == CloudflareHttpMethod::Get)
    );

    let mut tampered = serde_json::to_value(&plan).unwrap();
    tampered["document"]["desired"]["template_version"] = json!("tampered-template");
    let tampered: crate::DeploymentPlan = serde_json::from_value(tampered).unwrap();
    assert_eq!(
        tampered.verify_integrity().unwrap_err().code,
        DevkitErrorCode::PlanIntegrityFailed
    );
    assert!(serde_json::from_str::<SensitiveInputHandle>("\"\"").is_err());

    let resources = super::d1::PreparedD1Resources {
        database: super::d1::D1Database {
            id: "d1-database-1".into(),
            name: "example-gateway-entitlements".into(),
        },
        migration_hash: super::d1::migration_hash(),
    };
    let (multipart, _) = super::provider_support::worker_multipart(
        &plan,
        &resources,
        "https://example-gateway.example-subdomain.workers.dev",
        true,
    )
    .unwrap();
    let multipart = String::from_utf8(multipart).unwrap();
    assert!(multipart.contains("\"database_id\":\"d1-database-1\""));
    assert!(!multipart.contains("\"type\":\"d1\",\"name\":\"ENTITLEMENTS\",\"id\""));
}

#[tokio::test]
async fn timed_out_write_is_inspected_and_never_blindly_retried() {
    let desired = desired();
    let desired_hash = desired.state_hash().to_owned();
    let (transport, store, provider) = provider([
        not_found(),
        d1_missing(),
        not_found(),
        d1_missing(),
        d1_missing(),
        d1_created(),
        d1_query_success(),
        d1_query_success(),
        d1_query_success(),
        d1_query_success(),
        d1_query_success(),
        d1_query_success(),
        workers_dev_subdomain(),
        FakeAction::Failure(CloudflareTransportFailure::timeout()),
        deployment(&desired_hash, "version-recovered"),
        api_success(json!([])),
        d1_database(),
        d1_migration_table(),
        d1_migration_ledger(),
        worker_subdomain_enabled(),
    ]);
    let authorization = authorization(&store);
    let plan = provider
        .plan(&authorization, desired, control(None), 100)
        .await
        .unwrap();
    let receipt = provider.apply(&authorization, &plan, 200).await.unwrap();
    assert_eq!(receipt.outcome, ApplyOutcome::RecoveredAfterUncertainWrite);
    assert_eq!(receipt.active_remote_version, "version-recovered");
    let requests = transport.requests();
    let worker_uploads = requests
        .iter()
        .filter(|request| {
            request.method == CloudflareHttpMethod::Put
                && request.url.ends_with("/workers/scripts/example-gateway")
        })
        .count();
    assert_eq!(worker_uploads, 1);
    assert_eq!(transport.remaining_actions(), 0);
}

#[tokio::test]
async fn rate_limit_returns_bounded_retry_contract_without_mutation_retry() {
    let response = CloudflareTransportResponse::new(
        429,
        BTreeMap::from([("retry-after".into(), "7".into())]),
        b"upstream details are intentionally ignored".to_vec(),
    );
    let (transport, store, _) = provider([FakeAction::Response(response)]);
    let client = CloudflareRestClient::with_api_base(
        "https://api.example.test/client/v4/",
        Arc::clone(&transport),
        Arc::clone(&store),
    )
    .unwrap();
    let error = client
        .execute_json(
            Some(&authorization(&store)),
            CloudflareHttpMethod::Post,
            "accounts/account-123/workers/scripts/example-gateway/deployments",
            Some(&json!({"version": "v1"})),
        )
        .await
        .unwrap_err();
    assert_eq!(error.code, DevkitErrorCode::RateLimited);
    assert_eq!(error.retry_after_ms, Some(7_000));
    assert_eq!(
        reconcile_directive(&error),
        ReconcileDirective::WaitThenInspect {
            retry_after_ms: 7_000
        }
    );
    assert_eq!(transport.requests().len(), 1);
}

#[tokio::test]
async fn authorization_and_secret_values_are_redacted_from_debug_and_errors() {
    let secret_in_upstream_error = "model-secret-value";
    let response = CloudflareTransportResponse::json(
        400,
        json!({
            "success": false,
            "errors": [{"message": secret_in_upstream_error}]
        }),
    );
    let (transport, store, _) = provider([
        FakeAction::Response(response),
        FakeAction::Failure(CloudflareTransportFailure::protocol(
            secret_in_upstream_error,
        )),
    ]);
    let client = CloudflareRestClient::with_api_base(
        "https://api.example.test/client/v4/",
        Arc::clone(&transport),
        Arc::clone(&store),
    )
    .unwrap();
    let authorization = authorization(&store);
    let model_secret = store.insert("model-api-key", secret_in_upstream_error);
    let error = client
        .put_secret(
            &authorization,
            "accounts/account-123/workers/scripts/example-gateway/secrets",
            "UPSTREAM_API_KEY",
            &model_secret,
        )
        .await
        .unwrap_err();
    let transport_error = client
        .get_json(None, "accounts/account-123")
        .await
        .unwrap_err();
    let error_text = format!("{error:?} {error} {transport_error:?} {transport_error}");
    let request_text = &transport.requests()[0].safe_debug;
    for secret in [secret_in_upstream_error, "top-secret-cloudflare-token"] {
        assert!(!error_text.contains(secret));
        assert!(!request_text.contains(secret));
    }
    assert!(request_text.contains("[REDACTED]"));
}

#[tokio::test]
async fn gateway_test_uses_a_one_time_identity_on_a_pinned_health_endpoint() {
    let health = FakeAction::Response(CloudflareTransportResponse::json(
        200,
        json!({
            "protocol_version": "1",
            "deployment_id": "deployment-1",
            "remote_version": "version-current"
        }),
    ));
    let (transport, store, provider) = provider([
        deployment("desired-hash", "version-current"),
        api_success(json!([])),
        d1_database(),
        d1_query_success(),
        worker_subdomain_enabled(),
        health,
    ]);
    let identity = store.insert(
        "one-time-identity",
        r#"{"schemaVersion":1,"header":"cf-access-jwt-assertion","token":"single-use-end-user-token"}"#,
    );
    let receipt = provider
        .test(&authorization(&store), &target(), &identity, 100)
        .await
        .unwrap();
    assert_eq!(receipt.protocol_version, "1");
    assert_eq!(receipt.remote_version, "version-current");
    let requests = transport.requests();
    let health_request = requests.last().unwrap();
    assert_eq!(
        health_request.url,
        "https://gateway.example.test/.well-known/agentweave/gateway-health"
    );
    assert_eq!(health_request.redirect_policy, RedirectPolicy::Reject);
    assert!(
        health_request
            .safe_debug
            .contains("cf-access-jwt-assertion")
    );
    assert!(health_request.safe_debug.contains("[REDACTED]"));
    assert!(
        !health_request
            .safe_debug
            .contains("single-use-end-user-token")
    );
}

#[tokio::test]
async fn rollback_receipt_names_non_versioned_resource_boundaries() {
    let (transport, store, provider) = provider([
        deployment("old-desired-hash", "version-current"),
        api_success(json!([{"name": "UPSTREAM_API_KEY"}])),
        api_success(json!({"id": "deployment-rollback"})),
    ]);
    let request = RollbackRequest {
        target: target(),
        restore_remote_version: "version-previous".into(),
        control: control(Some("version-current")),
    };
    let receipt = provider
        .rollback(&authorization(&store), request, 100)
        .await
        .unwrap();
    assert_eq!(
        receipt.boundary.restored,
        BTreeSet::from([RollbackResourceScope::WorkerCode])
    );
    assert!(
        receipt
            .boundary
            .not_restored
            .contains(&RollbackResourceScope::SecretBindings)
    );
    assert!(
        receipt
            .boundary
            .not_restored
            .contains(&RollbackResourceScope::Routes)
    );
    assert!(
        receipt
            .boundary
            .not_restored
            .contains(&RollbackResourceScope::D1Data)
    );
    assert!(receipt.boundary.manual_repair_required);
    assert_eq!(
        transport
            .requests()
            .iter()
            .filter(|request| request.method.is_mutating())
            .count(),
        1
    );
}

#[tokio::test]
async fn destroy_plan_deletes_and_verifies_the_worker_and_bound_d1_database() {
    let planned = || deployment("old-desired-hash", "version-current");
    let no_secrets = || api_success(json!([]));
    let (transport, store, provider) = provider([
        planned(),
        no_secrets(),
        d1_database(),
        d1_query_success(),
        worker_subdomain_enabled(),
        planned(),
        no_secrets(),
        d1_database(),
        d1_query_success(),
        worker_subdomain_enabled(),
        api_success(Value::Null),
        not_found(),
        d1_database(),
        api_success(Value::Null),
        d1_missing(),
    ]);
    let authorization = authorization(&store);
    let plan = provider
        .destroy_plan(
            &authorization,
            &target(),
            control(Some("version-current")),
            100,
        )
        .await
        .unwrap();
    assert!(plan.resources().contains("worker-script:example-gateway"));
    assert!(plan.resources().contains("d1-database:d1-database-1"));

    let receipt = provider.destroy(&authorization, &plan, 200).await.unwrap();
    assert_eq!(receipt.deleted_resources, plan.resources().clone());
    let requests = transport.requests();
    let delete_urls = requests
        .iter()
        .filter(|request| request.method == CloudflareHttpMethod::Delete)
        .map(|request| request.url.as_str())
        .collect::<Vec<_>>();
    assert_eq!(delete_urls.len(), 2);
    assert!(
        delete_urls
            .iter()
            .any(|url| url.ends_with("/workers/scripts/example-gateway"))
    );
    assert!(
        delete_urls
            .iter()
            .any(|url| url.ends_with("/d1/database/d1-database-1"))
    );
    assert_eq!(transport.remaining_actions(), 0);
}

#[tokio::test]
async fn destroy_resumes_after_worker_removal_and_recovers_a_timed_out_d1_delete() {
    let (transport, store, provider) = provider([
        deployment("old-desired-hash", "version-current"),
        api_success(json!([])),
        d1_database(),
        d1_query_success(),
        worker_subdomain_enabled(),
        not_found(),
        d1_database(),
        d1_query_success(),
        not_found(),
        d1_database(),
        FakeAction::Failure(CloudflareTransportFailure::timeout()),
        d1_missing(),
    ]);
    let authorization = authorization(&store);
    let plan = provider
        .destroy_plan(
            &authorization,
            &target(),
            control(Some("version-current")),
            100,
        )
        .await
        .unwrap();
    let receipt = provider.destroy(&authorization, &plan, 200).await.unwrap();
    assert!(
        receipt
            .deleted_resources
            .contains("d1-database:d1-database-1")
    );
    assert_eq!(
        transport
            .requests()
            .iter()
            .filter(|request| {
                request.method == CloudflareHttpMethod::Delete
                    && request.url.ends_with("/d1/database/d1-database-1")
            })
            .count(),
        1
    );
    assert_eq!(transport.remaining_actions(), 0);
}
