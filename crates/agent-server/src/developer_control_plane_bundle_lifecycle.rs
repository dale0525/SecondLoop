use crate::developer_control_plane::{DeveloperControlPlane, now_unix_ms};
use crate::developer_control_plane_bundle::{AccessBundleTestReceipt, ExpectedResourceVersion};
use crate::developer_control_plane_deployment::{
    DeploymentObservation, DeploymentReferenceInput, ensure_account, observation_from_provider,
    validate_environment,
};
use agent_devkit::{
    DeploymentBundleResourceStatus, DevkitError, DevkitErrorCode, DevkitResult, MutationControl,
    ObservationReachability, RemoteMutationRisk, RollbackBoundary, RollbackRequest,
    SecretRotationRequest,
};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use uuid::Uuid;
use zeroize::Zeroize;

const ENTITLEMENT_POLICY_RESOURCE_ID: &str = "entitlement-policy";
const MODEL_GATEWAY_RESOURCE_ID: &str = "model-gateway";
const PROJECTION_SECRET: &str = "ENTITLEMENT_PROJECTION_SECRET";
const PROJECTION_SECRET_NEXT: &str = "ENTITLEMENT_PROJECTION_SECRET_NEXT";

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AccessBundleLifecycleTargets {
    pub gateway: DeploymentReferenceInput,
    pub entitlement_policy: DeploymentReferenceInput,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum AccessBundleInspectOutcome {
    Ready,
    Partial,
    Unavailable,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AccessBundleResourceObservation {
    pub resource_id: String,
    pub observation: Option<DeploymentObservation>,
    pub error_code: Option<DevkitErrorCode>,
    pub safe_message: Option<String>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AccessBundleInspectReceipt {
    pub schema_version: u32,
    pub bundle_id: String,
    pub outcome: AccessBundleInspectOutcome,
    pub resources: BTreeMap<String, AccessBundleResourceObservation>,
    pub inspected_at_unix_ms: u64,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AccessBundleMutationInput {
    pub targets: AccessBundleLifecycleTargets,
    #[serde(default)]
    pub idempotency_key: Option<String>,
    #[serde(default)]
    pub expected_resources: BTreeMap<String, ExpectedResourceVersion>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum AccessBundleMutationOutcome {
    Succeeded,
    FailedBeforeActivation,
    EntitlementReadyGatewayFailed,
    VerificationFailed,
    Partial,
    UncertainRemoteState,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AccessBundleLifecycleResourceReceipt {
    pub resource_id: String,
    pub target: DeploymentReferenceInput,
    pub status: DeploymentBundleResourceStatus,
    pub version_id: Option<String>,
    pub previous_version_id: Option<String>,
    pub configured_revision: Option<String>,
    pub rollback_boundary: Option<RollbackBoundary>,
    pub error_code: Option<DevkitErrorCode>,
    pub safe_message: Option<String>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AccessBundleRotationReceipt {
    pub schema_version: u32,
    pub operation_id: Uuid,
    pub outcome: AccessBundleMutationOutcome,
    pub configured_revision: String,
    pub resources: BTreeMap<String, AccessBundleLifecycleResourceReceipt>,
    pub verification: Option<AccessBundleTestReceipt>,
    pub completed_at_unix_ms: u64,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AccessBundleRollbackInput {
    pub targets: AccessBundleLifecycleTargets,
    pub restore_gateway_version: String,
    pub restore_entitlement_version: String,
    #[serde(default)]
    pub idempotency_key: Option<String>,
    #[serde(default)]
    pub expected_resources: BTreeMap<String, ExpectedResourceVersion>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AccessBundleRollbackReceipt {
    pub schema_version: u32,
    pub operation_id: Uuid,
    pub outcome: AccessBundleMutationOutcome,
    pub resources: BTreeMap<String, AccessBundleLifecycleResourceReceipt>,
    pub verification: Option<AccessBundleTestReceipt>,
    pub completed_at_unix_ms: u64,
}

impl DeveloperControlPlane {
    pub async fn inspect_access_bundle(
        &self,
        targets: AccessBundleLifecycleTargets,
    ) -> DevkitResult<AccessBundleInspectReceipt> {
        validate_targets(&targets)?;
        let authorization = self.require_authorization(true).await?;
        ensure_account(&authorization, &targets.gateway.account_id)?;
        let gateway_target = target(self, &targets.gateway)?;
        let entitlement_target = target(self, &targets.entitlement_policy)?;
        let now = now_unix_ms();
        let mut resources = BTreeMap::new();
        for (resource_id, reference, deployment_target) in [
            (
                MODEL_GATEWAY_RESOURCE_ID,
                targets.gateway.clone(),
                gateway_target,
            ),
            (
                ENTITLEMENT_POLICY_RESOURCE_ID,
                targets.entitlement_policy.clone(),
                entitlement_target,
            ),
        ] {
            let observation = self
                .provider
                .inspect(&authorization, &deployment_target, now)
                .await;
            resources.insert(
                resource_id.into(),
                match observation {
                    Ok(observed) => AccessBundleResourceObservation {
                        resource_id: resource_id.into(),
                        observation: Some(observation_from_provider(observed, reference)),
                        error_code: None,
                        safe_message: None,
                    },
                    Err(error) => AccessBundleResourceObservation {
                        resource_id: resource_id.into(),
                        observation: None,
                        error_code: Some(error.code),
                        safe_message: Some(error.safe_message),
                    },
                },
            );
        }
        let reachable = resources
            .values()
            .filter(|resource| {
                resource
                    .observation
                    .as_ref()
                    .is_some_and(|value| value.reachability == ObservationReachability::Reachable)
            })
            .count();
        let outcome = if reachable == resources.len() {
            AccessBundleInspectOutcome::Ready
        } else if reachable == 0
            && resources
                .values()
                .all(|resource| resource.observation.is_none())
        {
            AccessBundleInspectOutcome::Unavailable
        } else {
            AccessBundleInspectOutcome::Partial
        };
        Ok(AccessBundleInspectReceipt {
            schema_version: 1,
            bundle_id: lifecycle_bundle_id(&targets),
            outcome,
            resources,
            inspected_at_unix_ms: now,
        })
    }

    pub async fn rotate_access_bundle_projection_secret(
        &self,
        input: AccessBundleMutationInput,
        identity_header: &str,
        identity_token: Vec<u8>,
    ) -> DevkitResult<AccessBundleRotationReceipt> {
        let _mutation = self.mutation.lock().await;
        validate_targets(&input.targets)?;
        let authorization = self.require_authorization(true).await?;
        ensure_account(&authorization, &input.targets.gateway.account_id)?;
        let gateway_target = target(self, &input.targets.gateway)?;
        let entitlement_target = target(self, &input.targets.entitlement_policy)?;
        let control = self
            .acquire_lease(
                input
                    .idempotency_key
                    .unwrap_or_else(lifecycle_idempotency_key),
                None,
                None,
            )
            .await?;
        let revision = format!("auto-{}", Uuid::new_v4());
        let mut secret = random_secret_bytes();
        let next = self
            .resolve_sensitive_binding(PROJECTION_SECRET_NEXT, &revision, Some(secret.clone()))
            .await?;
        let mut resources = BTreeMap::new();
        let next_result = self
            .provider
            .rotate_secret(
                &authorization,
                SecretRotationRequest {
                    target: entitlement_target.clone(),
                    binding_name: PROJECTION_SECRET_NEXT.into(),
                    new_value_handle: next.handle.clone(),
                    new_revision: revision.clone(),
                    control: child_control(
                        &control,
                        "entitlement-next",
                        input.expected_resources.get(ENTITLEMENT_POLICY_RESOURCE_ID),
                    ),
                },
                now_unix_ms(),
            )
            .await;
        if let Err(error) = next_result {
            resources.insert(
                ENTITLEMENT_POLICY_RESOURCE_ID.into(),
                error_resource(
                    ENTITLEMENT_POLICY_RESOURCE_ID,
                    input.targets.entitlement_policy,
                    &error,
                ),
            );
            resources.insert(
                MODEL_GATEWAY_RESOURCE_ID.into(),
                blocked_resource(MODEL_GATEWAY_RESOURCE_ID, input.targets.gateway),
            );
            secret.zeroize();
            let _ = self.release_lease(&control.lease).await;
            return Ok(rotation_receipt(
                control.operation_id,
                mutation_failure_outcome(&error, false),
                revision,
                resources,
                None,
            ));
        }
        let gateway_result = self
            .provider
            .rotate_secret(
                &authorization,
                SecretRotationRequest {
                    target: gateway_target,
                    binding_name: PROJECTION_SECRET.into(),
                    new_value_handle: next.handle.clone(),
                    new_revision: revision.clone(),
                    control: child_control(
                        &control,
                        "gateway-current",
                        input.expected_resources.get(MODEL_GATEWAY_RESOURCE_ID),
                    ),
                },
                now_unix_ms(),
            )
            .await;
        if let Err(error) = gateway_result {
            resources.insert(
                ENTITLEMENT_POLICY_RESOURCE_ID.into(),
                applied_binding_resource(
                    ENTITLEMENT_POLICY_RESOURCE_ID,
                    input.targets.entitlement_policy,
                    &revision,
                ),
            );
            resources.insert(
                MODEL_GATEWAY_RESOURCE_ID.into(),
                error_resource(MODEL_GATEWAY_RESOURCE_ID, input.targets.gateway, &error),
            );
            secret.zeroize();
            let _ = self.release_lease(&control.lease).await;
            return Ok(rotation_receipt(
                control.operation_id,
                mutation_failure_outcome(&error, true),
                revision,
                resources,
                None,
            ));
        }
        let verification = self
            .test_access_bundle(
                crate::developer_control_plane_bundle::AccessBundleTestInput {
                    gateway: input.targets.gateway.clone(),
                    entitlement_policy: input.targets.entitlement_policy.clone(),
                },
                identity_header,
                identity_token,
            )
            .await;
        if let Err(error) = verification {
            resources.insert(
                ENTITLEMENT_POLICY_RESOURCE_ID.into(),
                applied_binding_resource(
                    ENTITLEMENT_POLICY_RESOURCE_ID,
                    input.targets.entitlement_policy,
                    &revision,
                ),
            );
            resources.insert(
                MODEL_GATEWAY_RESOURCE_ID.into(),
                error_resource(MODEL_GATEWAY_RESOURCE_ID, input.targets.gateway, &error),
            );
            secret.zeroize();
            let _ = self.release_lease(&control.lease).await;
            return Ok(rotation_receipt(
                control.operation_id,
                AccessBundleMutationOutcome::VerificationFailed,
                revision,
                resources,
                None,
            ));
        }
        let current_result = self
            .provider
            .rotate_secret(
                &authorization,
                SecretRotationRequest {
                    target: entitlement_target,
                    binding_name: PROJECTION_SECRET.into(),
                    new_value_handle: next.handle,
                    new_revision: revision.clone(),
                    control: child_control(
                        &control,
                        "entitlement-current",
                        input.expected_resources.get(ENTITLEMENT_POLICY_RESOURCE_ID),
                    ),
                },
                now_unix_ms(),
            )
            .await;
        if let Err(error) = current_result {
            resources.insert(
                ENTITLEMENT_POLICY_RESOURCE_ID.into(),
                error_resource(
                    ENTITLEMENT_POLICY_RESOURCE_ID,
                    input.targets.entitlement_policy,
                    &error,
                ),
            );
            resources.insert(
                MODEL_GATEWAY_RESOURCE_ID.into(),
                applied_binding_resource(
                    MODEL_GATEWAY_RESOURCE_ID,
                    input.targets.gateway,
                    &revision,
                ),
            );
            secret.zeroize();
            let _ = self.release_lease(&control.lease).await;
            return Ok(rotation_receipt(
                control.operation_id,
                mutation_failure_outcome(&error, true),
                revision,
                resources,
                None,
            ));
        }
        self.resolve_sensitive_binding(PROJECTION_SECRET, &revision, Some(secret.clone()))
            .await?;
        secret.zeroize();
        let mut verification = verification.ok();
        if let Some(test) = verification.as_mut() {
            test.projection_secret_revision = revision.clone();
        }
        resources.insert(
            ENTITLEMENT_POLICY_RESOURCE_ID.into(),
            applied_binding_resource(
                ENTITLEMENT_POLICY_RESOURCE_ID,
                input.targets.entitlement_policy,
                &revision,
            ),
        );
        resources.insert(
            MODEL_GATEWAY_RESOURCE_ID.into(),
            applied_binding_resource(MODEL_GATEWAY_RESOURCE_ID, input.targets.gateway, &revision),
        );
        self.release_lease(&control.lease).await?;
        Ok(rotation_receipt(
            control.operation_id,
            AccessBundleMutationOutcome::Succeeded,
            revision,
            resources,
            verification,
        ))
    }

    pub async fn rollback_access_bundle(
        &self,
        input: AccessBundleRollbackInput,
        identity_header: &str,
        identity_token: Vec<u8>,
    ) -> DevkitResult<AccessBundleRollbackReceipt> {
        let _mutation = self.mutation.lock().await;
        validate_targets(&input.targets)?;
        validate_remote_version(&input.restore_gateway_version)?;
        validate_remote_version(&input.restore_entitlement_version)?;
        let authorization = self.require_authorization(true).await?;
        ensure_account(&authorization, &input.targets.gateway.account_id)?;
        let gateway_target = target(self, &input.targets.gateway)?;
        let entitlement_target = target(self, &input.targets.entitlement_policy)?;
        let control = self
            .acquire_lease(
                input
                    .idempotency_key
                    .unwrap_or_else(lifecycle_idempotency_key),
                None,
                None,
            )
            .await?;
        let mut resources = BTreeMap::new();
        let entitlement = self
            .provider
            .rollback(
                &authorization,
                RollbackRequest {
                    target: entitlement_target,
                    restore_remote_version: input.restore_entitlement_version,
                    control: child_control(
                        &control,
                        "rollback-entitlement",
                        input.expected_resources.get(ENTITLEMENT_POLICY_RESOURCE_ID),
                    ),
                },
                now_unix_ms(),
            )
            .await;
        let entitlement = match entitlement {
            Ok(receipt) => receipt,
            Err(error) => {
                resources.insert(
                    ENTITLEMENT_POLICY_RESOURCE_ID.into(),
                    error_resource(
                        ENTITLEMENT_POLICY_RESOURCE_ID,
                        input.targets.entitlement_policy,
                        &error,
                    ),
                );
                resources.insert(
                    MODEL_GATEWAY_RESOURCE_ID.into(),
                    blocked_resource(MODEL_GATEWAY_RESOURCE_ID, input.targets.gateway),
                );
                let _ = self.release_lease(&control.lease).await;
                return Ok(rollback_receipt(
                    control.operation_id,
                    mutation_failure_outcome(&error, false),
                    resources,
                    None,
                ));
            }
        };
        resources.insert(
            ENTITLEMENT_POLICY_RESOURCE_ID.into(),
            rollback_resource(
                ENTITLEMENT_POLICY_RESOURCE_ID,
                input.targets.entitlement_policy.clone(),
                &entitlement,
            ),
        );
        let gateway = self
            .provider
            .rollback(
                &authorization,
                RollbackRequest {
                    target: gateway_target,
                    restore_remote_version: input.restore_gateway_version,
                    control: child_control(
                        &control,
                        "rollback-gateway",
                        input.expected_resources.get(MODEL_GATEWAY_RESOURCE_ID),
                    ),
                },
                now_unix_ms(),
            )
            .await;
        let gateway = match gateway {
            Ok(receipt) => receipt,
            Err(error) => {
                resources.insert(
                    MODEL_GATEWAY_RESOURCE_ID.into(),
                    error_resource(MODEL_GATEWAY_RESOURCE_ID, input.targets.gateway, &error),
                );
                let _ = self.release_lease(&control.lease).await;
                return Ok(rollback_receipt(
                    control.operation_id,
                    mutation_failure_outcome(&error, true),
                    resources,
                    None,
                ));
            }
        };
        resources.insert(
            MODEL_GATEWAY_RESOURCE_ID.into(),
            rollback_resource(
                MODEL_GATEWAY_RESOURCE_ID,
                input.targets.gateway.clone(),
                &gateway,
            ),
        );
        let verification = self
            .test_access_bundle(
                crate::developer_control_plane_bundle::AccessBundleTestInput {
                    gateway: input.targets.gateway,
                    entitlement_policy: input.targets.entitlement_policy,
                },
                identity_header,
                identity_token,
            )
            .await;
        let outcome = if verification.is_ok() {
            AccessBundleMutationOutcome::Succeeded
        } else {
            AccessBundleMutationOutcome::VerificationFailed
        };
        self.release_lease(&control.lease).await?;
        Ok(rollback_receipt(
            control.operation_id,
            outcome,
            resources,
            verification.ok(),
        ))
    }
}

pub(super) fn validate_targets(targets: &AccessBundleLifecycleTargets) -> DevkitResult<()> {
    validate_environment(targets.gateway.environment.as_deref())?;
    validate_environment(targets.entitlement_policy.environment.as_deref())?;
    if targets.gateway.account_id != targets.entitlement_policy.account_id
        || targets.gateway.deployment_id != targets.entitlement_policy.deployment_id
        || targets.gateway.environment != targets.entitlement_policy.environment
        || targets.gateway.worker_name == targets.entitlement_policy.worker_name
    {
        return Err(DevkitError::invalid_configuration(
            "access bundle targets do not form one deployment",
        ));
    }
    Ok(())
}

pub(super) fn target(
    control: &DeveloperControlPlane,
    reference: &DeploymentReferenceInput,
) -> DevkitResult<agent_devkit::DeploymentTarget> {
    control.target(
        reference.account_id.clone(),
        reference.deployment_id.clone(),
        reference.worker_name.clone(),
    )
}

fn validate_remote_version(value: &str) -> DevkitResult<()> {
    if value.is_empty() || value.len() > 256 || value.chars().any(char::is_control) {
        return Err(DevkitError::invalid_configuration(
            "access rollback version is invalid",
        ));
    }
    Ok(())
}

pub(super) fn child_control(
    parent: &MutationControl,
    operation: &str,
    expected: Option<&ExpectedResourceVersion>,
) -> MutationControl {
    MutationControl {
        operation_id: Uuid::new_v4(),
        idempotency_key: format!("{}:{operation}", parent.idempotency_key),
        expected_remote_version: expected.and_then(|value| value.remote_version.clone()),
        expected_remote_etag: expected.and_then(|value| value.remote_etag.clone()),
        lease: parent.lease.clone(),
    }
}

fn random_secret_bytes() -> Vec<u8> {
    let mut bytes = Vec::with_capacity(32);
    bytes.extend_from_slice(Uuid::new_v4().as_bytes());
    bytes.extend_from_slice(Uuid::new_v4().as_bytes());
    bytes
}

pub(super) fn lifecycle_idempotency_key() -> String {
    format!("agentweave-access-lifecycle-{}", Uuid::new_v4())
}

pub(super) fn lifecycle_bundle_id(targets: &AccessBundleLifecycleTargets) -> String {
    format!(
        "access-{}-{}",
        targets.gateway.deployment_id,
        targets
            .gateway
            .environment
            .as_deref()
            .unwrap_or("production")
    )
    .to_ascii_lowercase()
    .replace(
        |character: char| !character.is_ascii_alphanumeric() && character != '-',
        "-",
    )
}

pub(super) fn mutation_failure_outcome(
    error: &DevkitError,
    entitlement_ready: bool,
) -> AccessBundleMutationOutcome {
    if error.remote_mutation_risk == RemoteMutationRisk::Possible
        || error.code == DevkitErrorCode::Timeout
    {
        AccessBundleMutationOutcome::UncertainRemoteState
    } else if entitlement_ready {
        AccessBundleMutationOutcome::EntitlementReadyGatewayFailed
    } else {
        AccessBundleMutationOutcome::FailedBeforeActivation
    }
}

pub(super) fn error_resource(
    resource_id: &str,
    target: DeploymentReferenceInput,
    error: &DevkitError,
) -> AccessBundleLifecycleResourceReceipt {
    AccessBundleLifecycleResourceReceipt {
        resource_id: resource_id.into(),
        target,
        status: if error.remote_mutation_risk == RemoteMutationRisk::Possible
            || error.code == DevkitErrorCode::Timeout
        {
            DeploymentBundleResourceStatus::Uncertain
        } else {
            DeploymentBundleResourceStatus::Failed
        },
        version_id: None,
        previous_version_id: None,
        configured_revision: None,
        rollback_boundary: None,
        error_code: Some(error.code),
        safe_message: Some(error.safe_message.clone()),
    }
}

pub(super) fn blocked_resource(
    resource_id: &str,
    target: DeploymentReferenceInput,
) -> AccessBundleLifecycleResourceReceipt {
    AccessBundleLifecycleResourceReceipt {
        resource_id: resource_id.into(),
        target,
        status: DeploymentBundleResourceStatus::Blocked,
        version_id: None,
        previous_version_id: None,
        configured_revision: None,
        rollback_boundary: None,
        error_code: None,
        safe_message: None,
    }
}

fn applied_binding_resource(
    resource_id: &str,
    target: DeploymentReferenceInput,
    revision: &str,
) -> AccessBundleLifecycleResourceReceipt {
    AccessBundleLifecycleResourceReceipt {
        resource_id: resource_id.into(),
        target,
        status: DeploymentBundleResourceStatus::Applied,
        version_id: None,
        previous_version_id: None,
        configured_revision: Some(revision.into()),
        rollback_boundary: None,
        error_code: None,
        safe_message: None,
    }
}

fn rollback_resource(
    resource_id: &str,
    target: DeploymentReferenceInput,
    receipt: &agent_devkit::RollbackReceipt,
) -> AccessBundleLifecycleResourceReceipt {
    AccessBundleLifecycleResourceReceipt {
        resource_id: resource_id.into(),
        target,
        status: DeploymentBundleResourceStatus::Applied,
        version_id: Some(receipt.active_remote_version.clone()),
        previous_version_id: Some(receipt.previous_remote_version.clone()),
        configured_revision: None,
        rollback_boundary: Some(receipt.boundary.clone()),
        error_code: None,
        safe_message: None,
    }
}

pub(super) fn deleted_resource(
    resource_id: &str,
    target: DeploymentReferenceInput,
) -> AccessBundleLifecycleResourceReceipt {
    AccessBundleLifecycleResourceReceipt {
        resource_id: resource_id.into(),
        target,
        status: DeploymentBundleResourceStatus::Applied,
        version_id: None,
        previous_version_id: None,
        configured_revision: None,
        rollback_boundary: None,
        error_code: None,
        safe_message: None,
    }
}

fn rotation_receipt(
    operation_id: Uuid,
    outcome: AccessBundleMutationOutcome,
    configured_revision: String,
    resources: BTreeMap<String, AccessBundleLifecycleResourceReceipt>,
    verification: Option<AccessBundleTestReceipt>,
) -> AccessBundleRotationReceipt {
    AccessBundleRotationReceipt {
        schema_version: 1,
        operation_id,
        outcome,
        configured_revision,
        resources,
        verification,
        completed_at_unix_ms: now_unix_ms(),
    }
}

fn rollback_receipt(
    operation_id: Uuid,
    outcome: AccessBundleMutationOutcome,
    resources: BTreeMap<String, AccessBundleLifecycleResourceReceipt>,
    verification: Option<AccessBundleTestReceipt>,
) -> AccessBundleRollbackReceipt {
    AccessBundleRollbackReceipt {
        schema_version: 1,
        operation_id,
        outcome,
        resources,
        verification,
        completed_at_unix_ms: now_unix_ms(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generated_projection_rotation_secret_has_32_bytes() {
        assert_eq!(random_secret_bytes().len(), 32);
        assert_ne!(random_secret_bytes(), random_secret_bytes());
    }

    #[test]
    fn lifecycle_targets_must_form_one_bundle() {
        let targets = AccessBundleLifecycleTargets {
            gateway: DeploymentReferenceInput {
                account_id: "a".repeat(32),
                deployment_id: "production".into(),
                worker_name: "app-gateway".into(),
                environment: Some("production".into()),
            },
            entitlement_policy: DeploymentReferenceInput {
                account_id: "a".repeat(32),
                deployment_id: "production".into(),
                worker_name: "app-entitlements".into(),
                environment: Some("production".into()),
            },
        };
        assert!(validate_targets(&targets).is_ok());
        let mut invalid = targets;
        invalid.entitlement_policy.worker_name = invalid.gateway.worker_name.clone();
        assert!(validate_targets(&invalid).is_err());
    }
}
