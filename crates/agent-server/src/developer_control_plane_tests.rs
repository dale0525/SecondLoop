use crate::developer_control_plane::{
    CloudflareOAuthDefaults, DeveloperControlPlane, GatewayTemplateArtifact,
};
use crate::developer_control_plane_deployment::{DeploymentPlanInput, DeploymentSecretInput};
use crate::developer_control_plane_oauth::{
    CloudflareOAuthClientSelection, DeveloperAuthorizationPhase,
};
use crate::developer_sensitive_store::DeveloperSensitiveStore;
use agent_devkit::cloudflare::{CLOUDFLARE_PROVIDER_ID, cloudflare_gateway_provider_descriptor};
use agent_devkit::{
    ApplyOutcome, ApplyReceipt, AuthorizationRequirements, BeginProviderAuthorizationRequest,
    CompleteProviderAuthorizationRequest, DeploymentPlan, DeploymentTarget, DestroyPlan,
    DestroyReceipt, DeveloperAccount, DeveloperAuthorization, DevkitResult,
    GatewayDeploymentProvider, GatewayTestReceipt, MutationControl, ObservationReachability,
    ObservedDeploymentState, PlanOperation, PlanOperationKind, ProviderAuthorizationPlan,
    ProviderConfiguration, ProviderDescriptor, RollbackBoundary, RollbackReceipt, RollbackRequest,
    RollbackResourceScope, SecretRotationReceipt, SecretRotationRequest, SensitiveInputResolver,
    SensitiveInputStore, SensitiveValue,
};
use agent_runtime::credential::InMemorySecretStore;
use agent_runtime::storage::Storage;
use async_trait::async_trait;
use serde_json::json;
use std::collections::{BTreeMap, BTreeSet};
use std::sync::Arc;
use url::Url;

const ACCOUNT_ID: &str = "0123456789abcdef0123456789abcdef";

struct FakeGatewayProvider {
    descriptor: ProviderDescriptor,
    secrets: Arc<DeveloperSensitiveStore>,
}

impl FakeGatewayProvider {
    fn new(secrets: Arc<DeveloperSensitiveStore>) -> Self {
        Self {
            descriptor: cloudflare_gateway_provider_descriptor().unwrap(),
            secrets,
        }
    }
}

#[async_trait]
impl GatewayDeploymentProvider for FakeGatewayProvider {
    fn describe(&self) -> &ProviderDescriptor {
        &self.descriptor
    }

    async fn authorization_requirements(
        &self,
        _configuration: &ProviderConfiguration,
        requested_capabilities: &BTreeSet<String>,
    ) -> DevkitResult<AuthorizationRequirements> {
        Ok(AuthorizationRequirements {
            provider_id: CLOUDFLARE_PROVIDER_ID.into(),
            catalog_revision: "catalog-v1".into(),
            scope_ids_by_capability: requested_capabilities
                .iter()
                .map(|capability| (capability.clone(), BTreeSet::from([capability.clone()])))
                .collect(),
            reasons_by_capability: requested_capabilities
                .iter()
                .map(|capability| (capability.clone(), "test".into()))
                .collect(),
        })
    }

    async fn begin_provider_authorization(
        &self,
        request: BeginProviderAuthorizationRequest,
    ) -> DevkitResult<ProviderAuthorizationPlan> {
        let state = self.secrets.resolve(&request.state_handle).await?;
        let state = state.expose(|bytes| {
            std::str::from_utf8(bytes)
                .map(str::to_owned)
                .map_err(|_| agent_devkit::DevkitError::invalid_configuration("invalid state"))
        })?;
        let mut url = Url::parse("https://auth.example.test/authorize").unwrap();
        url.query_pairs_mut().append_pair("state", &state);
        Ok(ProviderAuthorizationPlan {
            provider_id: CLOUDFLARE_PROVIDER_ID.into(),
            authorization_url: url,
            requested_scope_ids: request.requested_capabilities.clone(),
            catalog_revision: "catalog-v1".into(),
            expires_at_unix_ms: request.expires_at_unix_ms,
        })
    }

    async fn complete_provider_authorization(
        &self,
        request: CompleteProviderAuthorizationRequest,
    ) -> DevkitResult<DeveloperAuthorization> {
        self.secrets.resolve(&request.code_handle).await?;
        self.secrets.resolve(&request.pkce_verifier_handle).await?;
        let token = self
            .secrets
            .store(
                "fake/access-token",
                SensitiveValue::new(b"cloudflare-token-secret".to_vec())?,
            )
            .await?;
        let logical_capabilities = request.expected_scope_ids.clone();
        DeveloperAuthorization::new_unbound(
            CLOUDFLARE_PROVIDER_ID,
            request.actor_id,
            token,
            None,
            request.expected_scope_ids,
            logical_capabilities,
            request.expected_catalog_revision,
            request.now_unix_ms,
            None,
        )
    }

    async fn list_authorization_accounts(
        &self,
        _authorization: &DeveloperAuthorization,
        _now_unix_ms: u64,
    ) -> DevkitResult<Vec<DeveloperAccount>> {
        Ok(vec![DeveloperAccount {
            provider_id: CLOUDFLARE_PROVIDER_ID.into(),
            account_id: ACCOUNT_ID.into(),
            display_name: Some("Example account".into()),
        }])
    }

    async fn bind_authorization_account(
        &self,
        authorization: &DeveloperAuthorization,
        account_id: &str,
        _now_unix_ms: u64,
    ) -> DevkitResult<DeveloperAuthorization> {
        if account_id != ACCOUNT_ID {
            return Err(agent_devkit::DevkitError::new(
                agent_devkit::DevkitErrorCode::InvalidAuthorization,
                "unknown account",
            ));
        }
        authorization.bind_account(account_id)
    }

    async fn plan(
        &self,
        _authorization: &DeveloperAuthorization,
        desired: agent_devkit::DesiredDeploymentState,
        control: MutationControl,
        now_unix_ms: u64,
    ) -> DevkitResult<DeploymentPlan> {
        let observed = ObservedDeploymentState {
            target: desired.target().clone(),
            reachability: ObservationReachability::Missing,
            remote_version: None,
            remote_etag: None,
            observed_desired_hash: None,
            active_artifact_hash: None,
            secret_bindings: BTreeMap::new(),
            managed_routes: BTreeSet::new(),
            resource_facts: BTreeMap::new(),
            observed_at_unix_ms: now_unix_ms,
        };
        DeploymentPlan::build(
            desired,
            observed,
            vec![PlanOperation {
                kind: PlanOperationKind::CreateScript,
                resource: "example-gateway".into(),
                destructive: false,
            }],
            control,
            now_unix_ms,
        )
    }

    async fn apply(
        &self,
        _authorization: &DeveloperAuthorization,
        plan: &DeploymentPlan,
        now_unix_ms: u64,
    ) -> DevkitResult<ApplyReceipt> {
        Ok(ApplyReceipt {
            target: plan.desired().target().clone(),
            plan_hash: plan.hash().clone(),
            operation_id: plan.control().operation_id,
            idempotency_key: plan.control().idempotency_key.clone(),
            outcome: ApplyOutcome::Applied,
            previous_remote_version: None,
            active_remote_version: "version-1".into(),
            remote_etag: Some("etag-1".into()),
            completed_at_unix_ms: now_unix_ms,
        })
    }

    async fn inspect(
        &self,
        _authorization: &DeveloperAuthorization,
        target: &DeploymentTarget,
        now_unix_ms: u64,
    ) -> DevkitResult<ObservedDeploymentState> {
        Ok(ObservedDeploymentState {
            target: target.clone(),
            reachability: ObservationReachability::Reachable,
            remote_version: Some("version-1".into()),
            remote_etag: Some("etag-1".into()),
            observed_desired_hash: Some("desired".into()),
            active_artifact_hash: Some("artifact".into()),
            secret_bindings: BTreeMap::new(),
            managed_routes: BTreeSet::new(),
            resource_facts: BTreeMap::from([
                (
                    "gateway_url".into(),
                    json!("https://example-gateway.workers.dev"),
                ),
                ("gateway_protocol_version".into(), json!("1")),
            ]),
            observed_at_unix_ms: now_unix_ms,
        })
    }

    async fn test(
        &self,
        _authorization: &DeveloperAuthorization,
        target: &DeploymentTarget,
        one_time_identity: &agent_devkit::SensitiveInputHandle,
        now_unix_ms: u64,
    ) -> DevkitResult<GatewayTestReceipt> {
        self.secrets.resolve(one_time_identity).await?;
        Ok(GatewayTestReceipt {
            target: target.clone(),
            protocol_version: "1".into(),
            remote_version: "version-1".into(),
            tested_at_unix_ms: now_unix_ms,
        })
    }

    async fn rotate_secret(
        &self,
        _authorization: &DeveloperAuthorization,
        request: SecretRotationRequest,
        now_unix_ms: u64,
    ) -> DevkitResult<SecretRotationReceipt> {
        self.secrets.resolve(&request.new_value_handle).await?;
        Ok(SecretRotationReceipt {
            target: request.target,
            operation_id: request.control.operation_id,
            binding_name: request.binding_name,
            configured_revision: request.new_revision,
            completed_at_unix_ms: now_unix_ms,
        })
    }

    async fn rollback(
        &self,
        _authorization: &DeveloperAuthorization,
        request: RollbackRequest,
        now_unix_ms: u64,
    ) -> DevkitResult<RollbackReceipt> {
        Ok(RollbackReceipt {
            target: request.target,
            operation_id: request.control.operation_id,
            previous_remote_version: "version-1".into(),
            active_remote_version: request.restore_remote_version,
            boundary: RollbackBoundary {
                restored: BTreeSet::from([RollbackResourceScope::WorkerCode]),
                not_restored: BTreeSet::from([RollbackResourceScope::SecretBindings]),
                manual_repair_required: true,
            },
            completed_at_unix_ms: now_unix_ms,
        })
    }

    async fn destroy_plan(
        &self,
        authorization: &DeveloperAuthorization,
        target: &DeploymentTarget,
        control: MutationControl,
        now_unix_ms: u64,
    ) -> DevkitResult<DestroyPlan> {
        DestroyPlan::build(
            target.clone(),
            self.inspect(authorization, target, now_unix_ms).await?,
            BTreeSet::from([format!("worker-script:{}", target.resource_name)]),
            control,
            now_unix_ms,
        )
    }

    async fn destroy(
        &self,
        _authorization: &DeveloperAuthorization,
        plan: &DestroyPlan,
        now_unix_ms: u64,
    ) -> DevkitResult<DestroyReceipt> {
        Ok(DestroyReceipt {
            target: plan.target().clone(),
            plan_hash: plan.hash().clone(),
            operation_id: plan.control().operation_id,
            deleted_resources: plan.resources().clone(),
            completed_at_unix_ms: now_unix_ms,
        })
    }
}

#[tokio::test]
async fn oauth_account_binding_and_deployment_are_host_scoped_and_public_only() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let secret_store = Arc::new(InMemorySecretStore::default());
    let sensitive = Arc::new(DeveloperSensitiveStore::new(secret_store, &"c".repeat(64)).unwrap());
    let provider = Arc::new(FakeGatewayProvider::new(sensitive.clone()));
    let control = DeveloperControlPlane::new(
        storage.sqlite_pool(),
        sensitive,
        provider,
        "c".repeat(64),
        "com.example.agent".into(),
        CloudflareOAuthDefaults::default(),
        Some(GatewayTemplateArtifact::new("0.3.0".into(), b"export default {};".to_vec()).unwrap()),
    )
    .await
    .unwrap();
    let start = control
        .start_authorization(
            CloudflareOAuthClientSelection::Custom {
                client_id: "client-id".into(),
                scope_catalog: BTreeMap::from([
                    ("Workers Scripts Read".into(), "scope-read".into()),
                    ("Workers Scripts Write".into(), "scope-write".into()),
                    ("D1 Write".into(), "scope-d1".into()),
                ]),
            },
            Url::parse("http://127.0.0.1:43891/cloudflare/callback").unwrap(),
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
    let callback = control
        .complete_authorization_callback(&format!(
            "http://127.0.0.1:43891/cloudflare/callback?code=one-time-code&state={state}"
        ))
        .await
        .unwrap();
    assert_eq!(
        callback.status.phase,
        DeveloperAuthorizationPhase::SelectAccount
    );
    let ready = control
        .select_authorization_account(ACCOUNT_ID)
        .await
        .unwrap();
    assert_eq!(ready.phase, DeveloperAuthorizationPhase::Ready);
    let public = serde_json::to_string(&ready).unwrap();
    assert!(!public.contains("token"));
    assert!(!public.contains("awdev"));

    let plan = control
        .plan_deployment(DeploymentPlanInput {
            account_id: ACCOUNT_ID.into(),
            deployment_id: "deployment-1".into(),
            worker_name: "example-gateway".into(),
            environment: None,
            gateway_config: json!({
                "schemaVersion": 1,
                "environment": "production",
                "deploymentId": "deployment-1",
                "upstream": {"secretBinding": "UPSTREAM_API_KEY"},
                "entitlements": {"mode": "static"}
            }),
            entitlement_bootstrap: json!({"schemaVersion": 1}),
            secrets: BTreeMap::from([(
                "UPSTREAM_API_KEY".into(),
                DeploymentSecretInput {
                    revision: "model-key-v1".into(),
                    value: Some(b"upstream-model-secret".to_vec()),
                },
            )]),
            idempotency_key: None,
            expected_remote_version: None,
            expected_remote_etag: None,
        })
        .await
        .unwrap();
    assert_eq!(plan.operations[0].kind, PlanOperationKind::CreateScript);
    let applied = control.apply_deployment(&plan.plan_hash).await.unwrap();
    assert_eq!(applied.version_id, "version-1");
    assert_eq!(applied.endpoint, "https://example-gateway.workers.dev");
    let serialized = serde_json::to_string(&applied).unwrap();
    assert!(!serialized.contains("upstream-model-secret"));
    assert!(!serialized.contains("cloudflare-token-secret"));

    let reused = control
        .plan_deployment(DeploymentPlanInput {
            account_id: ACCOUNT_ID.into(),
            deployment_id: "deployment-1".into(),
            worker_name: "example-gateway".into(),
            environment: None,
            gateway_config: json!({
                "schemaVersion": 1,
                "environment": "production",
                "deploymentId": "deployment-1",
                "upstream": {"secretBinding": "UPSTREAM_API_KEY"},
                "entitlements": {"mode": "static"}
            }),
            entitlement_bootstrap: json!({"schemaVersion": 1}),
            secrets: BTreeMap::from([(
                "UPSTREAM_API_KEY".into(),
                DeploymentSecretInput {
                    revision: "model-key-v1".into(),
                    value: None,
                },
            )]),
            idempotency_key: None,
            expected_remote_version: None,
            expected_remote_etag: None,
        })
        .await;
    assert!(
        reused.is_ok(),
        "stored secret should be reusable without Renderer access"
    );
}

#[tokio::test]
async fn oauth_state_is_one_time_even_when_the_callback_is_rejected() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let sensitive = Arc::new(
        DeveloperSensitiveStore::new(Arc::new(InMemorySecretStore::default()), &"d".repeat(64))
            .unwrap(),
    );
    let control = DeveloperControlPlane::new(
        storage.sqlite_pool(),
        sensitive.clone(),
        Arc::new(FakeGatewayProvider::new(sensitive)),
        "d".repeat(64),
        "com.example.agent".into(),
        CloudflareOAuthDefaults::default(),
        None,
    )
    .await
    .unwrap();
    control
        .start_authorization(
            CloudflareOAuthClientSelection::Custom {
                client_id: "client-id".into(),
                scope_catalog: BTreeMap::from([("scope".into(), "scope".into())]),
            },
            Url::parse("http://127.0.0.1:43892/cloudflare/callback").unwrap(),
        )
        .await
        .unwrap();

    assert!(
        control
            .complete_authorization_callback(
                "http://127.0.0.1:43892/cloudflare/callback?code=code&state=wrong-state"
            )
            .await
            .is_err()
    );
    assert!(
        control
            .complete_authorization_callback(
                "http://127.0.0.1:43892/cloudflare/callback?code=code&state=wrong-state"
            )
            .await
            .is_err(),
        "a rejected callback must still consume the pending transaction"
    );
}
