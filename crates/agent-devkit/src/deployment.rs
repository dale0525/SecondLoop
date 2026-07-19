use crate::{
    AuthorizationRequirements, BeginProviderAuthorizationRequest,
    CompleteProviderAuthorizationRequest, DeveloperAccount, DeveloperAuthorization, DevkitError,
    DevkitErrorCode, DevkitResult, ProviderAuthorizationPlan, ProviderConfiguration,
    ProviderDescriptor, RemoteMutationRisk, SensitiveInputHandle,
};
use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};
use std::fmt;
use uuid::Uuid;

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct DeploymentTarget {
    pub provider_id: String,
    pub account_id: String,
    pub app_id: String,
    pub deployment_id: String,
    pub resource_name: String,
}

impl DeploymentTarget {
    pub fn validate(&self) -> DevkitResult<()> {
        for (label, value, maximum) in [
            ("provider id", self.provider_id.as_str(), 128),
            ("account id", self.account_id.as_str(), 256),
            ("app id", self.app_id.as_str(), 128),
            ("deployment id", self.deployment_id.as_str(), 128),
            ("resource name", self.resource_name.as_str(), 128),
        ] {
            if value.is_empty() || value.len() > maximum || value.chars().any(char::is_control) {
                return Err(DevkitError::invalid_configuration(format!(
                    "deployment target {label} is invalid"
                )));
            }
        }
        Ok(())
    }
}

#[derive(Clone, Deserialize, Eq, PartialEq, Serialize)]
pub struct DeploymentArtifact {
    media_type: String,
    bytes: Vec<u8>,
    sha256: String,
}

impl DeploymentArtifact {
    pub fn new(media_type: impl Into<String>, bytes: Vec<u8>) -> DevkitResult<Self> {
        let media_type = media_type.into();
        if media_type.is_empty() || media_type.len() > 128 || bytes.is_empty() {
            return Err(DevkitError::invalid_configuration(
                "deployment artifact is invalid",
            ));
        }
        if bytes.len() > 16 * 1024 * 1024 {
            return Err(DevkitError::invalid_configuration(
                "deployment artifact exceeds the size limit",
            ));
        }
        let sha256 = hex::encode(Sha256::digest(&bytes));
        Ok(Self {
            media_type,
            bytes,
            sha256,
        })
    }

    pub fn media_type(&self) -> &str {
        &self.media_type
    }

    pub fn bytes(&self) -> &[u8] {
        &self.bytes
    }

    pub fn sha256(&self) -> &str {
        &self.sha256
    }

    pub fn verify_integrity(&self) -> DevkitResult<()> {
        if self.media_type.is_empty()
            || self.media_type.len() > 128
            || self.bytes.is_empty()
            || self.bytes.len() > 16 * 1024 * 1024
            || hex::encode(Sha256::digest(&self.bytes)) != self.sha256
        {
            return Err(DevkitError::new(
                DevkitErrorCode::PlanIntegrityFailed,
                "deployment artifact content does not match its immutable hash",
            ));
        }
        Ok(())
    }
}

impl fmt::Debug for DeploymentArtifact {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("DeploymentArtifact")
            .field("media_type", &self.media_type)
            .field("byte_length", &self.bytes.len())
            .field("sha256", &self.sha256)
            .finish()
    }
}

#[derive(Clone, Deserialize, Eq, PartialEq, Serialize)]
pub struct DesiredSecretBinding {
    pub value_handle: SensitiveInputHandle,
    /// Host-lock revision used for explicit rotation receipts. Providers that cannot read remote
    /// secret values must not claim this revision was observed from the cloud control plane.
    pub revision: String,
}

impl fmt::Debug for DesiredSecretBinding {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("DesiredSecretBinding")
            .field("value_handle", &"[REDACTED]")
            .field("revision", &self.revision)
            .finish()
    }
}

#[derive(Clone, Deserialize, PartialEq, Serialize)]
pub struct DesiredDeploymentState {
    target: DeploymentTarget,
    template_version: String,
    artifact: DeploymentArtifact,
    public_configuration: BTreeMap<String, Value>,
    secret_bindings: BTreeMap<String, DesiredSecretBinding>,
    managed_routes: BTreeSet<String>,
    state_hash: String,
}

#[derive(Serialize)]
struct DesiredDeploymentHashInput<'a> {
    target: &'a DeploymentTarget,
    template_version: &'a str,
    artifact_sha256: &'a str,
    public_configuration: &'a BTreeMap<String, Value>,
    secret_binding_names: BTreeSet<&'a str>,
    managed_routes: &'a BTreeSet<String>,
}

impl DesiredDeploymentState {
    pub fn new(
        target: DeploymentTarget,
        template_version: impl Into<String>,
        artifact: DeploymentArtifact,
        public_configuration: BTreeMap<String, Value>,
        secret_bindings: BTreeMap<String, DesiredSecretBinding>,
        managed_routes: BTreeSet<String>,
    ) -> DevkitResult<Self> {
        target.validate()?;
        let template_version = template_version.into();
        if template_version.is_empty() || template_version.len() > 128 {
            return Err(DevkitError::invalid_configuration(
                "gateway template version is invalid",
            ));
        }
        validate_secret_bindings(&secret_bindings)?;
        let state_hash = hash_serializable(&DesiredDeploymentHashInput {
            target: &target,
            template_version: &template_version,
            artifact_sha256: artifact.sha256(),
            public_configuration: &public_configuration,
            secret_binding_names: secret_bindings.keys().map(String::as_str).collect(),
            managed_routes: &managed_routes,
        })?;
        Ok(Self {
            target,
            template_version,
            artifact,
            public_configuration,
            secret_bindings,
            managed_routes,
            state_hash,
        })
    }

    pub fn target(&self) -> &DeploymentTarget {
        &self.target
    }

    pub fn template_version(&self) -> &str {
        &self.template_version
    }

    pub fn artifact(&self) -> &DeploymentArtifact {
        &self.artifact
    }

    pub fn public_configuration(&self) -> &BTreeMap<String, Value> {
        &self.public_configuration
    }

    pub fn secret_bindings(&self) -> &BTreeMap<String, DesiredSecretBinding> {
        &self.secret_bindings
    }

    pub fn managed_routes(&self) -> &BTreeSet<String> {
        &self.managed_routes
    }

    pub fn state_hash(&self) -> &str {
        &self.state_hash
    }

    pub fn verify_integrity(&self) -> DevkitResult<()> {
        self.target.validate()?;
        self.artifact.verify_integrity()?;
        validate_secret_bindings(&self.secret_bindings)?;
        if self.template_version.is_empty() || self.template_version.len() > 128 {
            return Err(DevkitError::new(
                DevkitErrorCode::PlanIntegrityFailed,
                "gateway template version is invalid",
            ));
        }
        let computed = hash_serializable(&DesiredDeploymentHashInput {
            target: &self.target,
            template_version: &self.template_version,
            artifact_sha256: self.artifact.sha256(),
            public_configuration: &self.public_configuration,
            secret_binding_names: self.secret_bindings.keys().map(String::as_str).collect(),
            managed_routes: &self.managed_routes,
        })?;
        if computed != self.state_hash {
            return Err(DevkitError::new(
                DevkitErrorCode::PlanIntegrityFailed,
                "desired deployment state does not match its immutable hash",
            ));
        }
        Ok(())
    }
}

impl fmt::Debug for DesiredDeploymentState {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("DesiredDeploymentState")
            .field("target", &self.target)
            .field("template_version", &self.template_version)
            .field("artifact", &self.artifact)
            .field("public_configuration", &self.public_configuration)
            .field(
                "secret_bindings",
                &self.secret_bindings.keys().collect::<Vec<_>>(),
            )
            .field("managed_routes", &self.managed_routes)
            .field("state_hash", &self.state_hash)
            .finish()
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ObservationReachability {
    Reachable,
    Missing,
    Unauthorized,
    Unreachable,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct ObservedSecretBinding {
    pub configured: bool,
    pub observed_revision: Option<String>,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
pub struct ObservedDeploymentState {
    pub target: DeploymentTarget,
    pub reachability: ObservationReachability,
    pub remote_version: Option<String>,
    pub remote_etag: Option<String>,
    pub observed_desired_hash: Option<String>,
    pub active_artifact_hash: Option<String>,
    pub secret_bindings: BTreeMap<String, ObservedSecretBinding>,
    pub managed_routes: BTreeSet<String>,
    pub resource_facts: BTreeMap<String, Value>,
    pub observed_at_unix_ms: u64,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum DriftStatus {
    InSync,
    Drifted,
    Missing,
    Unauthorized,
    Unreachable,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct DriftDifference {
    pub resource: String,
    pub reason_code: String,
    pub expected: Option<String>,
    pub actual: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct DriftReport {
    pub status: DriftStatus,
    pub differences: Vec<DriftDifference>,
}

pub fn assess_drift(
    desired: &DesiredDeploymentState,
    observed: &ObservedDeploymentState,
) -> DriftReport {
    let terminal = match observed.reachability {
        ObservationReachability::Missing => Some(DriftStatus::Missing),
        ObservationReachability::Unauthorized => Some(DriftStatus::Unauthorized),
        ObservationReachability::Unreachable => Some(DriftStatus::Unreachable),
        ObservationReachability::Reachable => None,
    };
    if let Some(status) = terminal {
        return DriftReport {
            status,
            differences: Vec::new(),
        };
    }
    let mut differences = Vec::new();
    if observed.target != *desired.target() {
        differences.push(DriftDifference {
            resource: "deployment".into(),
            reason_code: "target_mismatch".into(),
            expected: Some(desired.target().deployment_id.clone()),
            actual: Some(observed.target.deployment_id.clone()),
        });
    }
    if observed.remote_version.is_none() {
        differences.push(DriftDifference {
            resource: "deployment".into(),
            reason_code: "active_version_missing".into(),
            expected: Some("active".into()),
            actual: None,
        });
    }
    if observed.observed_desired_hash.as_deref() != Some(desired.state_hash()) {
        differences.push(DriftDifference {
            resource: "deployment".into(),
            reason_code: "desired_state_hash_mismatch".into(),
            expected: Some(desired.state_hash().into()),
            actual: observed.observed_desired_hash.clone(),
        });
    }
    if observed.active_artifact_hash.as_deref() != Some(desired.artifact().sha256()) {
        differences.push(DriftDifference {
            resource: "worker_code".into(),
            reason_code: "artifact_hash_mismatch".into(),
            expected: Some(desired.artifact().sha256().into()),
            actual: observed.active_artifact_hash.clone(),
        });
    }
    for (name, expected) in desired.secret_bindings() {
        match observed.secret_bindings.get(name) {
            Some(actual) if actual.configured => {
                if actual
                    .observed_revision
                    .as_deref()
                    .is_some_and(|revision| revision != expected.revision)
                {
                    differences.push(DriftDifference {
                        resource: format!("secret:{name}"),
                        reason_code: "secret_revision_mismatch".into(),
                        expected: Some(expected.revision.clone()),
                        actual: actual.observed_revision.clone(),
                    });
                }
            }
            _ => differences.push(DriftDifference {
                resource: format!("secret:{name}"),
                reason_code: "secret_missing".into(),
                expected: Some("configured".into()),
                actual: Some("missing".into()),
            }),
        }
    }
    if observed.managed_routes != *desired.managed_routes() {
        differences.push(DriftDifference {
            resource: "routes".into(),
            reason_code: "route_set_mismatch".into(),
            expected: Some(desired.managed_routes().len().to_string()),
            actual: Some(observed.managed_routes.len().to_string()),
        });
    }
    DriftReport {
        status: if differences.is_empty() {
            DriftStatus::InSync
        } else {
            DriftStatus::Drifted
        },
        differences,
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct OperationLease {
    pub owner_id: String,
    pub lease_version: u64,
    pub expires_at_unix_ms: u64,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct MutationControl {
    pub operation_id: Uuid,
    pub idempotency_key: String,
    pub expected_remote_version: Option<String>,
    pub expected_remote_etag: Option<String>,
    pub lease: OperationLease,
}

impl MutationControl {
    pub fn validate(&self, now_unix_ms: u64) -> DevkitResult<()> {
        if self.idempotency_key.len() < 16
            || self.idempotency_key.len() > 256
            || self.idempotency_key.chars().any(char::is_control)
        {
            return Err(DevkitError::invalid_plan(
                "deployment idempotency key is invalid",
            ));
        }
        if self.lease.owner_id.is_empty()
            || self.lease.owner_id.len() > 256
            || self.lease.expires_at_unix_ms <= now_unix_ms
        {
            return Err(DevkitError::invalid_plan(
                "deployment operation lease is invalid or expired",
            ));
        }
        Ok(())
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum PlanOperationKind {
    CreateDatabase,
    ApplyDatabaseMigration,
    SeedEntitlements,
    CreateScript,
    UploadVersion,
    ConfigureBindings,
    ConfigureSecret,
    ConfigureRoute,
    EnablePublicEndpoint,
    ActivateVersion,
    Verify,
    DeleteResource,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct PlanOperation {
    pub kind: PlanOperationKind,
    pub resource: String,
    pub destructive: bool,
}

#[derive(Clone, Deserialize, Eq, Hash, PartialEq, Serialize)]
#[serde(transparent)]
pub struct PlanHash(String);

impl PlanHash {
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Debug for PlanHash {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.0)
    }
}

impl fmt::Display for PlanHash {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.0)
    }
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
struct DeploymentPlanDocument {
    desired: DesiredDeploymentState,
    observed_before: ObservedDeploymentState,
    operations: Vec<PlanOperation>,
    control: MutationControl,
    created_at_unix_ms: u64,
}

/// Immutable deployment preview. The hash covers desired state, prior observation and guards.
#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
pub struct DeploymentPlan {
    document: DeploymentPlanDocument,
    hash: PlanHash,
}

impl DeploymentPlan {
    pub fn build(
        desired: DesiredDeploymentState,
        observed_before: ObservedDeploymentState,
        operations: Vec<PlanOperation>,
        control: MutationControl,
        created_at_unix_ms: u64,
    ) -> DevkitResult<Self> {
        desired.verify_integrity()?;
        control.validate(created_at_unix_ms)?;
        if desired.target() != &observed_before.target {
            return Err(DevkitError::invalid_plan(
                "deployment plan target does not match its observation",
            ));
        }
        let document = DeploymentPlanDocument {
            desired,
            observed_before,
            operations,
            control,
            created_at_unix_ms,
        };
        let hash = PlanHash(hash_serializable(&document)?);
        Ok(Self { document, hash })
    }

    pub fn verify_integrity(&self) -> DevkitResult<()> {
        self.document.desired.verify_integrity()?;
        if hash_serializable(&self.document)? != self.hash.0 {
            return Err(DevkitError::new(
                DevkitErrorCode::PlanIntegrityFailed,
                "deployment plan content does not match its immutable hash",
            ));
        }
        Ok(())
    }

    pub fn hash(&self) -> &PlanHash {
        &self.hash
    }

    pub fn desired(&self) -> &DesiredDeploymentState {
        &self.document.desired
    }

    pub fn observed_before(&self) -> &ObservedDeploymentState {
        &self.document.observed_before
    }

    pub fn operations(&self) -> &[PlanOperation] {
        &self.document.operations
    }

    pub fn control(&self) -> &MutationControl {
        &self.document.control
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ReconcileStatus {
    Queued,
    Applying,
    AwaitingObservation,
    Verifying,
    Succeeded,
    Failed,
    Uncertain,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct ReconcileState {
    pub operation_id: Uuid,
    pub idempotency_key: String,
    pub plan_hash: PlanHash,
    pub status: ReconcileStatus,
    pub attempt: u32,
    pub checkpoint: Option<String>,
    pub updated_at_unix_ms: u64,
}

impl ReconcileState {
    pub fn transition(
        mut self,
        next: ReconcileStatus,
        checkpoint: Option<String>,
        now_unix_ms: u64,
    ) -> DevkitResult<Self> {
        let allowed = matches!(
            (self.status, next),
            (ReconcileStatus::Queued, ReconcileStatus::Applying)
                | (
                    ReconcileStatus::Applying,
                    ReconcileStatus::AwaitingObservation
                )
                | (ReconcileStatus::Applying, ReconcileStatus::Verifying)
                | (ReconcileStatus::Applying, ReconcileStatus::Failed)
                | (ReconcileStatus::Applying, ReconcileStatus::Uncertain)
                | (
                    ReconcileStatus::AwaitingObservation,
                    ReconcileStatus::Verifying
                )
                | (
                    ReconcileStatus::AwaitingObservation,
                    ReconcileStatus::Applying
                )
                | (
                    ReconcileStatus::AwaitingObservation,
                    ReconcileStatus::Failed
                )
                | (
                    ReconcileStatus::AwaitingObservation,
                    ReconcileStatus::Uncertain
                )
                | (ReconcileStatus::Verifying, ReconcileStatus::Succeeded)
                | (ReconcileStatus::Verifying, ReconcileStatus::Failed)
                | (ReconcileStatus::Verifying, ReconcileStatus::Uncertain)
                | (
                    ReconcileStatus::Uncertain,
                    ReconcileStatus::AwaitingObservation
                )
        );
        if !allowed {
            return Err(DevkitError::new(
                DevkitErrorCode::ConcurrentModification,
                "invalid deployment reconciliation state transition",
            ));
        }
        if next == ReconcileStatus::Applying {
            self.attempt = self.attempt.saturating_add(1);
        }
        self.status = next;
        self.checkpoint = checkpoint;
        self.updated_at_unix_ms = now_unix_ms;
        Ok(self)
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(tag = "action", rename_all = "snake_case")]
pub enum ReconcileDirective {
    InspectBeforeRetry,
    WaitThenInspect { retry_after_ms: u64 },
    SafeToRetry,
    DoNotRetry,
}

pub fn reconcile_directive(error: &DevkitError) -> ReconcileDirective {
    if error.code == DevkitErrorCode::RateLimited {
        return ReconcileDirective::WaitThenInspect {
            retry_after_ms: error.retry_after_ms.unwrap_or(1_000),
        };
    }
    if error.remote_mutation_risk == RemoteMutationRisk::Possible
        || error.code == DevkitErrorCode::Timeout
    {
        return ReconcileDirective::InspectBeforeRetry;
    }
    match error.code {
        DevkitErrorCode::Unavailable => ReconcileDirective::SafeToRetry,
        _ => ReconcileDirective::DoNotRetry,
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ApplyOutcome {
    Applied,
    AlreadyConverged,
    RecoveredAfterUncertainWrite,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct ApplyReceipt {
    pub target: DeploymentTarget,
    pub plan_hash: PlanHash,
    pub operation_id: Uuid,
    pub idempotency_key: String,
    pub outcome: ApplyOutcome,
    pub previous_remote_version: Option<String>,
    pub active_remote_version: String,
    pub remote_etag: Option<String>,
    pub completed_at_unix_ms: u64,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum RollbackResourceScope {
    WorkerCode,
    SecretBindings,
    Routes,
    KvData,
    D1Data,
    DurableObjects,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct RollbackBoundary {
    pub restored: BTreeSet<RollbackResourceScope>,
    pub not_restored: BTreeSet<RollbackResourceScope>,
    pub manual_repair_required: bool,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct RollbackRequest {
    pub target: DeploymentTarget,
    pub restore_remote_version: String,
    pub control: MutationControl,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct RollbackReceipt {
    pub target: DeploymentTarget,
    pub operation_id: Uuid,
    pub previous_remote_version: String,
    pub active_remote_version: String,
    pub boundary: RollbackBoundary,
    pub completed_at_unix_ms: u64,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct SecretRotationRequest {
    pub target: DeploymentTarget,
    pub binding_name: String,
    pub new_value_handle: SensitiveInputHandle,
    pub new_revision: String,
    pub control: MutationControl,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct SecretRotationReceipt {
    pub target: DeploymentTarget,
    pub operation_id: Uuid,
    pub binding_name: String,
    pub configured_revision: String,
    pub completed_at_unix_ms: u64,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct GatewayTestReceipt {
    pub target: DeploymentTarget,
    pub protocol_version: String,
    pub remote_version: String,
    pub tested_at_unix_ms: u64,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
struct DestroyPlanDocument {
    target: DeploymentTarget,
    observed_before: ObservedDeploymentState,
    resources: BTreeSet<String>,
    control: MutationControl,
    created_at_unix_ms: u64,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
pub struct DestroyPlan {
    document: DestroyPlanDocument,
    hash: PlanHash,
}

impl DestroyPlan {
    pub fn build(
        target: DeploymentTarget,
        observed_before: ObservedDeploymentState,
        resources: BTreeSet<String>,
        control: MutationControl,
        created_at_unix_ms: u64,
    ) -> DevkitResult<Self> {
        control.validate(created_at_unix_ms)?;
        if target != observed_before.target || resources.is_empty() {
            return Err(DevkitError::invalid_plan(
                "destroy plan target or resource scope is invalid",
            ));
        }
        let document = DestroyPlanDocument {
            target,
            observed_before,
            resources,
            control,
            created_at_unix_ms,
        };
        let hash = PlanHash(hash_serializable(&document)?);
        Ok(Self { document, hash })
    }

    pub fn verify_integrity(&self) -> DevkitResult<()> {
        if hash_serializable(&self.document)? != self.hash.0 {
            return Err(DevkitError::new(
                DevkitErrorCode::PlanIntegrityFailed,
                "destroy plan content does not match its immutable hash",
            ));
        }
        Ok(())
    }

    pub fn target(&self) -> &DeploymentTarget {
        &self.document.target
    }

    pub fn observed_before(&self) -> &ObservedDeploymentState {
        &self.document.observed_before
    }

    pub fn resources(&self) -> &BTreeSet<String> {
        &self.document.resources
    }

    pub fn control(&self) -> &MutationControl {
        &self.document.control
    }

    pub fn hash(&self) -> &PlanHash {
        &self.hash
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct DestroyReceipt {
    pub target: DeploymentTarget,
    pub plan_hash: PlanHash,
    pub operation_id: Uuid,
    pub deleted_resources: BTreeSet<String>,
    pub completed_at_unix_ms: u64,
}

#[async_trait]
pub trait GatewayDeploymentProvider: Send + Sync {
    fn describe(&self) -> &ProviderDescriptor;

    async fn authorization_requirements(
        &self,
        configuration: &ProviderConfiguration,
        requested_capabilities: &BTreeSet<String>,
    ) -> DevkitResult<AuthorizationRequirements>;

    async fn begin_provider_authorization(
        &self,
        request: BeginProviderAuthorizationRequest,
    ) -> DevkitResult<ProviderAuthorizationPlan>;

    async fn complete_provider_authorization(
        &self,
        request: CompleteProviderAuthorizationRequest,
    ) -> DevkitResult<DeveloperAuthorization>;

    /// Lists accounts visible to a provider grant before the grant is bound to one target.
    async fn list_authorization_accounts(
        &self,
        authorization: &DeveloperAuthorization,
        now_unix_ms: u64,
    ) -> DevkitResult<Vec<DeveloperAccount>>;

    /// Revalidates the selected account against the provider before returning an account-bound
    /// authorization. Implementations must not trust a Renderer-supplied account identifier.
    async fn bind_authorization_account(
        &self,
        authorization: &DeveloperAuthorization,
        account_id: &str,
        now_unix_ms: u64,
    ) -> DevkitResult<DeveloperAuthorization>;

    /// Must be read-only: implementations may inspect but must not create or update resources.
    async fn plan(
        &self,
        authorization: &DeveloperAuthorization,
        desired: DesiredDeploymentState,
        control: MutationControl,
        now_unix_ms: u64,
    ) -> DevkitResult<DeploymentPlan>;

    async fn apply(
        &self,
        authorization: &DeveloperAuthorization,
        plan: &DeploymentPlan,
        now_unix_ms: u64,
    ) -> DevkitResult<ApplyReceipt>;

    async fn inspect(
        &self,
        authorization: &DeveloperAuthorization,
        target: &DeploymentTarget,
        now_unix_ms: u64,
    ) -> DevkitResult<ObservedDeploymentState>;

    async fn test(
        &self,
        authorization: &DeveloperAuthorization,
        target: &DeploymentTarget,
        one_time_identity: &SensitiveInputHandle,
        now_unix_ms: u64,
    ) -> DevkitResult<GatewayTestReceipt>;

    async fn rotate_secret(
        &self,
        authorization: &DeveloperAuthorization,
        request: SecretRotationRequest,
        now_unix_ms: u64,
    ) -> DevkitResult<SecretRotationReceipt>;

    async fn rollback(
        &self,
        authorization: &DeveloperAuthorization,
        request: RollbackRequest,
        now_unix_ms: u64,
    ) -> DevkitResult<RollbackReceipt>;

    /// Must be read-only and bind the observed target/version into the returned plan hash.
    async fn destroy_plan(
        &self,
        authorization: &DeveloperAuthorization,
        target: &DeploymentTarget,
        control: MutationControl,
        now_unix_ms: u64,
    ) -> DevkitResult<DestroyPlan>;

    async fn destroy(
        &self,
        authorization: &DeveloperAuthorization,
        plan: &DestroyPlan,
        now_unix_ms: u64,
    ) -> DevkitResult<DestroyReceipt>;
}

fn hash_serializable(value: &impl Serialize) -> DevkitResult<String> {
    let canonical = serde_json::to_vec(value).map_err(|_| {
        DevkitError::new(
            DevkitErrorCode::Internal,
            "deployment state could not be hashed",
        )
    })?;
    Ok(hex::encode(Sha256::digest(canonical)))
}

fn validate_secret_bindings(
    secret_bindings: &BTreeMap<String, DesiredSecretBinding>,
) -> DevkitResult<()> {
    for (binding, secret) in secret_bindings {
        if binding.is_empty()
            || binding.len() > 128
            || !binding
                .bytes()
                .all(|byte| byte.is_ascii_uppercase() || byte.is_ascii_digit() || byte == b'_')
            || secret.revision.is_empty()
            || secret.revision.len() > 256
        {
            return Err(DevkitError::invalid_configuration(
                "desired secret binding or revision is invalid",
            ));
        }
    }
    Ok(())
}
