use crate::{
    ApplyOutcome, ApplyReceipt, DeploymentPlan, DeploymentTarget, DesiredDeploymentState,
    DeveloperAuthorization, DevkitError, DevkitErrorCode, DevkitResult, GatewayDeploymentProvider,
    MutationControl, PlanHash, RemoteMutationRisk,
};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};
use uuid::Uuid;

pub const DEPLOYMENT_BUNDLE_SCHEMA_VERSION: u32 = 1;

#[derive(Clone, Copy, Debug, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum DeploymentResourceKind {
    Worker,
    D1Database,
    DurableObjectNamespace,
    RateLimiter,
    SecretBinding,
    ScheduledTrigger,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum DeploymentResourcePurpose {
    EntitlementPolicy,
    ModelGateway,
    GatewayLedger,
    CommerceProjection,
    Secret,
    ConcurrencyControl,
    EdgeRateLimit,
    Reconciliation,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum DeploymentResourceOwnership {
    Exclusive,
    Shared,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DeploymentResourceSpec {
    pub resource_id: String,
    pub kind: DeploymentResourceKind,
    pub purpose: DeploymentResourcePurpose,
    pub target: DeploymentTarget,
    pub dependencies: BTreeSet<String>,
    pub ownership: DeploymentResourceOwnership,
    pub controller_resource_id: Option<String>,
    pub independently_rollbackable: bool,
    pub delete_requires_confirmation: bool,
    pub desired: Option<DesiredDeploymentState>,
}

impl DeploymentResourceSpec {
    fn validate_shallow(&self) -> DevkitResult<()> {
        validate_resource_id(&self.resource_id)?;
        self.target.validate()?;
        if self.dependencies.contains(&self.resource_id)
            || self.controller_resource_id.as_deref() == Some(self.resource_id.as_str())
        {
            return Err(DevkitError::invalid_configuration(
                "deployment resource cannot depend on or be controlled by itself",
            ));
        }
        match (self.kind, self.desired.as_ref()) {
            (DeploymentResourceKind::Worker, Some(desired)) => {
                desired.verify_integrity()?;
                if desired.target() != &self.target {
                    return Err(DevkitError::invalid_configuration(
                        "deployment Worker resource target does not match desired state",
                    ));
                }
                if self.controller_resource_id.is_some() {
                    return Err(DevkitError::invalid_configuration(
                        "deployment Worker resource cannot have a controller",
                    ));
                }
            }
            (DeploymentResourceKind::Worker, None) => {
                return Err(DevkitError::invalid_configuration(
                    "deployment Worker resource requires desired state",
                ));
            }
            (_, Some(_)) => {
                return Err(DevkitError::invalid_configuration(
                    "only Worker resources can carry desired deployment state",
                ));
            }
            (_, None) => {}
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DesiredDeploymentBundle {
    schema_version: u32,
    bundle_id: String,
    resources: BTreeMap<String, DeploymentResourceSpec>,
    desired_hash: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct BundleHashInput<'a> {
    schema_version: u32,
    bundle_id: &'a str,
    resources: BTreeMap<&'a str, BundleResourceHashInput<'a>>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct BundleResourceHashInput<'a> {
    kind: DeploymentResourceKind,
    purpose: DeploymentResourcePurpose,
    target: &'a DeploymentTarget,
    dependencies: &'a BTreeSet<String>,
    ownership: DeploymentResourceOwnership,
    controller_resource_id: Option<&'a str>,
    independently_rollbackable: bool,
    delete_requires_confirmation: bool,
    desired_state_hash: Option<&'a str>,
    secret_revisions: BTreeMap<&'a str, &'a str>,
}

impl DesiredDeploymentBundle {
    pub fn new(
        bundle_id: impl Into<String>,
        resources: Vec<DeploymentResourceSpec>,
    ) -> DevkitResult<Self> {
        let bundle_id = bundle_id.into();
        validate_resource_id(&bundle_id)?;
        if resources.is_empty() || resources.len() > 128 {
            return Err(DevkitError::invalid_configuration(
                "deployment bundle resource count is invalid",
            ));
        }
        let mut indexed = BTreeMap::new();
        for resource in resources {
            resource.validate_shallow()?;
            let resource_id = resource.resource_id.clone();
            if indexed.insert(resource_id, resource).is_some() {
                return Err(DevkitError::invalid_configuration(
                    "deployment bundle resource identifiers must be unique",
                ));
            }
        }
        validate_graph(&indexed)?;
        let desired_hash = hash_bundle_input(&bundle_id, &indexed)?;
        Ok(Self {
            schema_version: DEPLOYMENT_BUNDLE_SCHEMA_VERSION,
            bundle_id,
            resources: indexed,
            desired_hash,
        })
    }

    pub fn verify_integrity(&self) -> DevkitResult<()> {
        if self.schema_version != DEPLOYMENT_BUNDLE_SCHEMA_VERSION {
            return Err(DevkitError::new(
                DevkitErrorCode::PlanIntegrityFailed,
                "deployment bundle schema version is unsupported",
            ));
        }
        validate_resource_id(&self.bundle_id)?;
        for resource in self.resources.values() {
            resource.validate_shallow()?;
        }
        validate_graph(&self.resources)?;
        if hash_bundle_input(&self.bundle_id, &self.resources)? != self.desired_hash {
            return Err(DevkitError::new(
                DevkitErrorCode::PlanIntegrityFailed,
                "deployment bundle content does not match its immutable hash",
            ));
        }
        Ok(())
    }

    pub fn bundle_id(&self) -> &str {
        &self.bundle_id
    }

    pub fn resources(&self) -> &BTreeMap<String, DeploymentResourceSpec> {
        &self.resources
    }

    pub fn desired_hash(&self) -> &str {
        &self.desired_hash
    }

    pub fn topological_order(&self) -> DevkitResult<Vec<String>> {
        topological_order(&self.resources)
    }
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DeploymentBundlePlan {
    desired: DesiredDeploymentBundle,
    worker_plans: BTreeMap<String, DeploymentPlan>,
    control: MutationControl,
    created_at_unix_ms: u64,
    hash: PlanHash,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct BundlePlanHashInput<'a> {
    desired_hash: &'a str,
    worker_plan_hashes: BTreeMap<&'a str, &'a str>,
    control: &'a MutationControl,
    created_at_unix_ms: u64,
}

impl DeploymentBundlePlan {
    pub fn build(
        desired: DesiredDeploymentBundle,
        worker_plans: BTreeMap<String, DeploymentPlan>,
        control: MutationControl,
        created_at_unix_ms: u64,
    ) -> DevkitResult<Self> {
        desired.verify_integrity()?;
        control.validate(created_at_unix_ms)?;
        validate_worker_plans(&desired, &worker_plans)?;
        let hash = PlanHash::from_sha256(hash_serializable(&bundle_plan_hash_input(
            &desired,
            &worker_plans,
            &control,
            created_at_unix_ms,
        ))?);
        Ok(Self {
            desired,
            worker_plans,
            control,
            created_at_unix_ms,
            hash,
        })
    }

    pub fn verify_integrity(&self) -> DevkitResult<()> {
        self.desired.verify_integrity()?;
        self.control.validate(self.created_at_unix_ms)?;
        validate_worker_plans(&self.desired, &self.worker_plans)?;
        let expected = hash_serializable(&bundle_plan_hash_input(
            &self.desired,
            &self.worker_plans,
            &self.control,
            self.created_at_unix_ms,
        ))?;
        if expected != self.hash.as_str() {
            return Err(DevkitError::new(
                DevkitErrorCode::PlanIntegrityFailed,
                "deployment bundle plan content does not match its immutable hash",
            ));
        }
        Ok(())
    }

    pub fn desired(&self) -> &DesiredDeploymentBundle {
        &self.desired
    }

    pub fn worker_plans(&self) -> &BTreeMap<String, DeploymentPlan> {
        &self.worker_plans
    }

    pub fn control(&self) -> &MutationControl {
        &self.control
    }

    pub fn hash(&self) -> &PlanHash {
        &self.hash
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum DeploymentBundleResourceStatus {
    Applied,
    AlreadyConverged,
    Failed,
    Uncertain,
    Blocked,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DeploymentBundleResourceReceipt {
    pub resource_id: String,
    pub status: DeploymentBundleResourceStatus,
    pub apply_receipt: Option<ApplyReceipt>,
    pub error_code: Option<DevkitErrorCode>,
    pub safe_message: Option<String>,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum DeploymentBundleOutcome {
    Succeeded,
    FailedBeforeActivation,
    EntitlementReadyGatewayFailed,
    GatewayActiveVerificationFailed,
    UncertainRemoteState,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DeploymentBundleReceipt {
    pub schema_version: u32,
    pub bundle_id: String,
    pub plan_hash: PlanHash,
    pub operation_id: Uuid,
    pub outcome: DeploymentBundleOutcome,
    pub resources: BTreeMap<String, DeploymentBundleResourceReceipt>,
    pub completed_at_unix_ms: u64,
}

pub async fn apply_deployment_bundle<P: GatewayDeploymentProvider + ?Sized>(
    provider: &P,
    authorization: &DeveloperAuthorization,
    plan: &DeploymentBundlePlan,
    now_unix_ms: u64,
) -> DevkitResult<DeploymentBundleReceipt> {
    plan.verify_integrity()?;
    plan.control().validate(now_unix_ms)?;
    let order = plan.desired().topological_order()?;
    let mut receipts = BTreeMap::new();
    let mut failure: Option<(String, DevkitError)> = None;
    let mut entitlement_ready = false;
    for resource_id in order {
        let resource = &plan.desired().resources()[&resource_id];
        if resource.kind != DeploymentResourceKind::Worker {
            continue;
        }
        if failure.is_some()
            || resource.dependencies.iter().any(|dependency| {
                receipts
                    .get(dependency)
                    .is_some_and(|receipt: &DeploymentBundleResourceReceipt| {
                        !matches!(
                            receipt.status,
                            DeploymentBundleResourceStatus::Applied
                                | DeploymentBundleResourceStatus::AlreadyConverged
                        )
                    })
            })
        {
            receipts.insert(resource_id.clone(), blocked_receipt(&resource_id));
            mark_controlled_resources(plan.desired(), &resource_id, &mut receipts, None);
            continue;
        }
        let worker_plan = &plan.worker_plans()[&resource_id];
        match provider
            .apply(authorization, worker_plan, now_unix_ms)
            .await
        {
            Ok(receipt) => {
                let status = if receipt.outcome == ApplyOutcome::AlreadyConverged {
                    DeploymentBundleResourceStatus::AlreadyConverged
                } else {
                    DeploymentBundleResourceStatus::Applied
                };
                if resource.purpose == DeploymentResourcePurpose::EntitlementPolicy {
                    entitlement_ready = true;
                }
                receipts.insert(
                    resource_id.clone(),
                    DeploymentBundleResourceReceipt {
                        resource_id: resource_id.clone(),
                        status,
                        apply_receipt: Some(receipt),
                        error_code: None,
                        safe_message: None,
                    },
                );
                mark_controlled_resources(
                    plan.desired(),
                    &resource_id,
                    &mut receipts,
                    Some(status),
                );
            }
            Err(error) => {
                let status = if error.remote_mutation_risk == RemoteMutationRisk::Possible
                    || error.code == DevkitErrorCode::Timeout
                {
                    DeploymentBundleResourceStatus::Uncertain
                } else {
                    DeploymentBundleResourceStatus::Failed
                };
                receipts.insert(
                    resource_id.clone(),
                    DeploymentBundleResourceReceipt {
                        resource_id: resource_id.clone(),
                        status,
                        apply_receipt: None,
                        error_code: Some(error.code),
                        safe_message: Some(error.safe_message.clone()),
                    },
                );
                mark_controlled_resources(
                    plan.desired(),
                    &resource_id,
                    &mut receipts,
                    Some(status),
                );
                failure = Some((resource_id, error));
            }
        }
    }
    for resource_id in plan.desired().resources().keys() {
        receipts
            .entry(resource_id.clone())
            .or_insert_with(|| blocked_receipt(resource_id));
    }
    let outcome = match failure.as_ref() {
        None => DeploymentBundleOutcome::Succeeded,
        Some((_, error))
            if error.remote_mutation_risk == RemoteMutationRisk::Possible
                || error.code == DevkitErrorCode::Timeout =>
        {
            DeploymentBundleOutcome::UncertainRemoteState
        }
        Some((resource_id, _))
            if entitlement_ready
                && plan.desired().resources()[resource_id].purpose
                    == DeploymentResourcePurpose::ModelGateway =>
        {
            DeploymentBundleOutcome::EntitlementReadyGatewayFailed
        }
        Some(_) => DeploymentBundleOutcome::FailedBeforeActivation,
    };
    Ok(DeploymentBundleReceipt {
        schema_version: DEPLOYMENT_BUNDLE_SCHEMA_VERSION,
        bundle_id: plan.desired().bundle_id().into(),
        plan_hash: plan.hash().clone(),
        operation_id: plan.control().operation_id,
        outcome,
        resources: receipts,
        completed_at_unix_ms: now_unix_ms,
    })
}

fn mark_controlled_resources(
    desired: &DesiredDeploymentBundle,
    controller_id: &str,
    receipts: &mut BTreeMap<String, DeploymentBundleResourceReceipt>,
    status: Option<DeploymentBundleResourceStatus>,
) {
    for resource in desired
        .resources()
        .values()
        .filter(|candidate| candidate.controller_resource_id.as_deref() == Some(controller_id))
    {
        receipts.insert(
            resource.resource_id.clone(),
            DeploymentBundleResourceReceipt {
                resource_id: resource.resource_id.clone(),
                status: status.unwrap_or(DeploymentBundleResourceStatus::Blocked),
                apply_receipt: None,
                error_code: None,
                safe_message: None,
            },
        );
    }
}

fn blocked_receipt(resource_id: &str) -> DeploymentBundleResourceReceipt {
    DeploymentBundleResourceReceipt {
        resource_id: resource_id.into(),
        status: DeploymentBundleResourceStatus::Blocked,
        apply_receipt: None,
        error_code: None,
        safe_message: None,
    }
}

fn validate_worker_plans(
    desired: &DesiredDeploymentBundle,
    worker_plans: &BTreeMap<String, DeploymentPlan>,
) -> DevkitResult<()> {
    let worker_ids = desired
        .resources()
        .values()
        .filter(|resource| resource.kind == DeploymentResourceKind::Worker)
        .map(|resource| resource.resource_id.as_str())
        .collect::<BTreeSet<_>>();
    if worker_ids.len() != worker_plans.len()
        || worker_plans
            .keys()
            .any(|id| !worker_ids.contains(id.as_str()))
    {
        return Err(DevkitError::invalid_plan(
            "deployment bundle Worker plans do not match the resource graph",
        ));
    }
    for (resource_id, plan) in worker_plans {
        plan.verify_integrity()?;
        let resource = &desired.resources()[resource_id];
        if resource.desired.as_ref() != Some(plan.desired()) {
            return Err(DevkitError::invalid_plan(
                "deployment bundle Worker plan differs from desired state",
            ));
        }
    }
    Ok(())
}

fn validate_graph(resources: &BTreeMap<String, DeploymentResourceSpec>) -> DevkitResult<()> {
    let first = resources.values().next().ok_or_else(|| {
        DevkitError::invalid_configuration("deployment bundle requires resources")
    })?;
    for resource in resources.values() {
        if resource.target.provider_id != first.target.provider_id
            || resource.target.account_id != first.target.account_id
            || resource.target.app_id != first.target.app_id
        {
            return Err(DevkitError::invalid_configuration(
                "deployment bundle resources must share provider, account, and App boundaries",
            ));
        }
        for dependency in &resource.dependencies {
            if !resources.contains_key(dependency) {
                return Err(DevkitError::invalid_configuration(
                    "deployment resource dependency is missing",
                ));
            }
        }
        if let Some(controller) = &resource.controller_resource_id {
            let Some(controller) = resources.get(controller) else {
                return Err(DevkitError::invalid_configuration(
                    "deployment resource controller is missing",
                ));
            };
            if controller.kind != DeploymentResourceKind::Worker {
                return Err(DevkitError::invalid_configuration(
                    "deployment resource controller must be a Worker",
                ));
            }
        }
    }
    topological_order(resources).map(|_| ())
}

fn topological_order(
    resources: &BTreeMap<String, DeploymentResourceSpec>,
) -> DevkitResult<Vec<String>> {
    let mut remaining = resources
        .iter()
        .map(|(id, resource)| (id.clone(), resource.dependencies.clone()))
        .collect::<BTreeMap<_, _>>();
    let mut order = Vec::with_capacity(resources.len());
    while !remaining.is_empty() {
        let ready = remaining
            .iter()
            .filter(|(_, dependencies)| dependencies.is_empty())
            .map(|(id, _)| id.clone())
            .collect::<Vec<_>>();
        if ready.is_empty() {
            return Err(DevkitError::invalid_configuration(
                "deployment resource graph contains a dependency cycle",
            ));
        }
        for id in ready {
            remaining.remove(&id);
            for dependencies in remaining.values_mut() {
                dependencies.remove(&id);
            }
            order.push(id);
        }
    }
    Ok(order)
}

fn bundle_plan_hash_input<'a>(
    desired: &'a DesiredDeploymentBundle,
    worker_plans: &'a BTreeMap<String, DeploymentPlan>,
    control: &'a MutationControl,
    created_at_unix_ms: u64,
) -> BundlePlanHashInput<'a> {
    BundlePlanHashInput {
        desired_hash: desired.desired_hash(),
        worker_plan_hashes: worker_plans
            .iter()
            .map(|(id, plan)| (id.as_str(), plan.hash().as_str()))
            .collect(),
        control,
        created_at_unix_ms,
    }
}

fn hash_bundle_input(
    bundle_id: &str,
    resources: &BTreeMap<String, DeploymentResourceSpec>,
) -> DevkitResult<String> {
    let resources = resources
        .iter()
        .map(|(id, resource)| {
            let secret_revisions = resource
                .desired
                .as_ref()
                .map(|desired| {
                    desired
                        .secret_bindings()
                        .iter()
                        .map(|(name, binding)| (name.as_str(), binding.revision.as_str()))
                        .collect()
                })
                .unwrap_or_default();
            (
                id.as_str(),
                BundleResourceHashInput {
                    kind: resource.kind,
                    purpose: resource.purpose,
                    target: &resource.target,
                    dependencies: &resource.dependencies,
                    ownership: resource.ownership,
                    controller_resource_id: resource.controller_resource_id.as_deref(),
                    independently_rollbackable: resource.independently_rollbackable,
                    delete_requires_confirmation: resource.delete_requires_confirmation,
                    desired_state_hash: resource.desired.as_ref().map(|value| value.state_hash()),
                    secret_revisions,
                },
            )
        })
        .collect();
    hash_serializable(&BundleHashInput {
        schema_version: DEPLOYMENT_BUNDLE_SCHEMA_VERSION,
        bundle_id,
        resources,
    })
}

fn validate_resource_id(value: &str) -> DevkitResult<()> {
    if value.is_empty()
        || value.len() > 128
        || !value.bytes().all(|byte| {
            byte.is_ascii_lowercase()
                || byte.is_ascii_digit()
                || matches!(byte, b'-' | b'_' | b'.' | b':')
        })
    {
        return Err(DevkitError::invalid_configuration(
            "deployment resource identifier is invalid",
        ));
    }
    Ok(())
}

fn hash_serializable(value: &impl Serialize) -> DevkitResult<String> {
    let bytes = serde_json::to_vec(value).map_err(|_| {
        DevkitError::new(
            DevkitErrorCode::Internal,
            "deployment bundle could not be hashed",
        )
    })?;
    Ok(hex::encode(Sha256::digest(bytes)))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{DeploymentArtifact, DesiredSecretBinding, OperationLease, SensitiveInputHandle};
    use serde_json::json;

    fn target(name: &str) -> DeploymentTarget {
        DeploymentTarget {
            provider_id: "cloudflare-workers".into(),
            account_id: "account-1".into(),
            app_id: "com.example.agent".into(),
            deployment_id: "production".into(),
            resource_name: name.into(),
        }
    }

    fn desired(name: &str, revision: &str) -> DesiredDeploymentState {
        DesiredDeploymentState::new(
            target(name),
            "1.0.0",
            DeploymentArtifact::new(
                "application/javascript+module",
                b"export default {}".to_vec(),
            )
            .unwrap(),
            BTreeMap::from([("worker_role".into(), json!(name))]),
            BTreeMap::from([(
                "SHARED_SECRET".into(),
                DesiredSecretBinding {
                    value_handle: SensitiveInputHandle::from_opaque_reference(format!(
                        "vault:{name}"
                    ))
                    .unwrap(),
                    revision: revision.into(),
                },
            )]),
            BTreeSet::new(),
        )
        .unwrap()
    }

    fn worker_with_revision(
        id: &str,
        name: &str,
        dependencies: BTreeSet<String>,
        revision: &str,
    ) -> DeploymentResourceSpec {
        let desired = desired(name, revision);
        DeploymentResourceSpec {
            resource_id: id.into(),
            kind: DeploymentResourceKind::Worker,
            purpose: if id == "entitlement-policy" {
                DeploymentResourcePurpose::EntitlementPolicy
            } else {
                DeploymentResourcePurpose::ModelGateway
            },
            target: desired.target().clone(),
            dependencies,
            ownership: DeploymentResourceOwnership::Exclusive,
            controller_resource_id: None,
            independently_rollbackable: true,
            delete_requires_confirmation: false,
            desired: Some(desired),
        }
    }

    fn worker(id: &str, name: &str, dependencies: BTreeSet<String>) -> DeploymentResourceSpec {
        worker_with_revision(id, name, dependencies, "revision-1")
    }

    #[test]
    fn graph_orders_entitlement_before_gateway_and_rejects_cycles() {
        let entitlement = worker("entitlement-policy", "app-entitlements", BTreeSet::new());
        let gateway = worker(
            "model-gateway",
            "app-gateway",
            BTreeSet::from(["entitlement-policy".into()]),
        );
        let bundle = DesiredDeploymentBundle::new(
            "access-production",
            vec![gateway.clone(), entitlement.clone()],
        )
        .unwrap();
        let order = bundle.topological_order().unwrap();
        assert!(
            order.iter().position(|id| id == "entitlement-policy")
                < order.iter().position(|id| id == "model-gateway")
        );

        let mut left = entitlement;
        left.dependencies.insert("model-gateway".into());
        assert!(DesiredDeploymentBundle::new("access-production", vec![left, gateway]).is_err());
    }

    #[test]
    fn desired_hash_includes_secret_revision_without_serializing_secret_value() {
        let first = DesiredDeploymentBundle::new(
            "access-production",
            vec![worker(
                "entitlement-policy",
                "app-entitlements",
                BTreeSet::new(),
            )],
        )
        .unwrap();
        let changed = worker_with_revision(
            "entitlement-policy",
            "app-entitlements",
            BTreeSet::new(),
            "revision-2",
        );
        let second = DesiredDeploymentBundle::new("access-production", vec![changed]).unwrap();
        assert_ne!(first.desired_hash(), second.desired_hash());
        assert!(
            !serde_json::to_string(&first.desired_hash())
                .unwrap()
                .contains("vault:")
        );
    }

    #[test]
    fn controlled_resources_must_point_to_a_worker() {
        let worker = worker("model-gateway", "app-gateway", BTreeSet::new());
        let database = DeploymentResourceSpec {
            resource_id: "gateway-ledger".into(),
            kind: DeploymentResourceKind::D1Database,
            purpose: DeploymentResourcePurpose::GatewayLedger,
            target: target("app-gateway"),
            dependencies: BTreeSet::new(),
            ownership: DeploymentResourceOwnership::Exclusive,
            controller_resource_id: Some("missing".into()),
            independently_rollbackable: false,
            delete_requires_confirmation: true,
            desired: None,
        };
        assert!(DesiredDeploymentBundle::new("access-production", vec![worker, database]).is_err());
    }

    #[test]
    fn bundle_control_shape_remains_usable() {
        let control = MutationControl {
            operation_id: Uuid::new_v4(),
            idempotency_key: "bundle-idempotency-key".into(),
            expected_remote_version: None,
            expected_remote_etag: None,
            lease: OperationLease {
                owner_id: "test".into(),
                lease_version: 1,
                expires_at_unix_ms: 2_000,
            },
        };
        control.validate(1_000).unwrap();
    }
}
