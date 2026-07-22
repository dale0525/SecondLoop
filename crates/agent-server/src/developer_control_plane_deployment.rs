use crate::developer_control_plane::{
    CachedDeploymentPlan, CachedDestroyPlan, CachedPlan, DeveloperControlPlane, now_unix_ms,
};
use agent_devkit::cloudflare::CLOUDFLARE_PROVIDER_ID;
use agent_devkit::{
    ApplyOutcome, DeploymentArtifact, DeploymentTarget, DesiredDeploymentState,
    DesiredSecretBinding, DevkitError, DevkitErrorCode, DevkitResult, DriftReport,
    GatewayTestReceipt, ObservationReachability, ObservedDeploymentState, PlanOperation,
    RollbackBoundary, RollbackRequest, SecretRotationRequest, SensitiveInputStore, SensitiveValue,
    assess_drift,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};
use uuid::Uuid;

#[derive(Debug)]
pub struct DeploymentPlanInput {
    pub account_id: String,
    pub deployment_id: String,
    pub worker_name: String,
    pub environment: Option<String>,
    pub gateway_config: Value,
    pub entitlement_bootstrap: Value,
    pub secrets: BTreeMap<String, DeploymentSecretInput>,
    pub idempotency_key: Option<String>,
    pub expected_remote_version: Option<String>,
    pub expected_remote_etag: Option<String>,
}

pub struct DeploymentSecretInput {
    pub revision: String,
    pub value: Option<Vec<u8>>,
}

impl std::fmt::Debug for DeploymentSecretInput {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("DeploymentSecretInput")
            .field("revision", &self.revision)
            .field("value", &self.value.as_ref().map(|_| "[REDACTED]"))
            .finish()
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DeploymentReferenceInput {
    pub account_id: String,
    pub deployment_id: String,
    pub worker_name: String,
    pub environment: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DeploymentPlanSummary {
    pub plan_hash: String,
    pub target: DeploymentReferenceInput,
    pub operations: Vec<PlanOperation>,
    pub drift: DriftReport,
    pub expires_at_unix_ms: u64,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DeploymentApplyReceipt {
    pub provider_id: String,
    pub provider_version: String,
    pub target: DeploymentReferenceInput,
    pub outcome: ApplyOutcome,
    pub previous_version_id: Option<String>,
    pub version_id: String,
    pub endpoint: String,
    pub operation_id: Uuid,
    pub completed_at_unix_ms: u64,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DeploymentObservation {
    pub target: DeploymentReferenceInput,
    pub reachability: ObservationReachability,
    pub remote_version: Option<String>,
    pub remote_etag: Option<String>,
    pub observed_desired_hash: Option<String>,
    pub active_artifact_hash: Option<String>,
    pub endpoint: Option<String>,
    pub gateway_protocol_version: Option<String>,
    pub d1_migration_status: Option<String>,
    pub workers_dev_ready: Option<bool>,
    pub observed_at_unix_ms: u64,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DeploymentTestReceipt {
    pub target: DeploymentReferenceInput,
    pub protocol_version: String,
    pub remote_version: String,
    pub tested_at_unix_ms: u64,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SecretRotationPublicReceipt {
    pub target: DeploymentReferenceInput,
    pub binding_name: String,
    pub configured_revision: String,
    pub operation_id: Uuid,
    pub completed_at_unix_ms: u64,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RollbackPublicReceipt {
    pub target: DeploymentReferenceInput,
    pub previous_version_id: String,
    pub version_id: String,
    pub operation_id: Uuid,
    pub boundary: RollbackBoundary,
    pub completed_at_unix_ms: u64,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DestroyPlanSummary {
    pub plan_hash: String,
    pub target: DeploymentReferenceInput,
    pub resources: BTreeSet<String>,
    pub expires_at_unix_ms: u64,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DestroyPublicReceipt {
    pub plan_hash: String,
    pub target: DeploymentReferenceInput,
    pub deleted_resources: BTreeSet<String>,
    pub operation_id: Uuid,
    pub completed_at_unix_ms: u64,
}

impl DeveloperControlPlane {
    pub async fn plan_deployment(
        &self,
        input: DeploymentPlanInput,
    ) -> DevkitResult<DeploymentPlanSummary> {
        let _mutation = self.mutation.lock().await;
        let authorization = self.require_authorization(true).await?;
        ensure_account(&authorization, &input.account_id)?;
        validate_environment(input.environment.as_deref())?;
        let target = self.target(input.account_id, input.deployment_id, input.worker_name)?;
        let required_bindings = validate_gateway_configuration(
            &input.gateway_config,
            &target,
            input.environment.as_deref(),
        )?;
        if input.secrets.keys().cloned().collect::<BTreeSet<_>>() != required_bindings {
            return Err(DevkitError::invalid_configuration(
                "deployment secret inputs do not match the gateway configuration",
            ));
        }
        let mut secret_bindings = BTreeMap::new();
        for (binding_name, secret) in input.secrets {
            let stored = self
                .resolve_sensitive_binding(&binding_name, &secret.revision, secret.value)
                .await?;
            secret_bindings.insert(
                binding_name,
                DesiredSecretBinding {
                    value_handle: stored.handle,
                    revision: stored.revision,
                },
            );
        }
        let template = self.gateway_template().ok_or_else(|| {
            DevkitError::new(
                DevkitErrorCode::Unavailable,
                "trusted Cloudflare gateway template is unavailable",
            )
        })?;
        let desired = DesiredDeploymentState::new(
            target.clone(),
            template.version(),
            DeploymentArtifact::new("application/javascript+module", template.bytes().to_vec())?,
            BTreeMap::from([
                ("gateway_config".into(), input.gateway_config),
                ("entitlement_bootstrap".into(), input.entitlement_bootstrap),
            ]),
            secret_bindings,
            BTreeSet::new(),
        )?;
        let control = self
            .acquire_lease(
                input
                    .idempotency_key
                    .unwrap_or_else(deployment_idempotency_key),
                input.expected_remote_version,
                input.expected_remote_etag,
            )
            .await?;
        let plan = match self
            .provider
            .plan(&authorization, desired, control.clone(), now_unix_ms())
            .await
        {
            Ok(plan) => plan,
            Err(error) => {
                let _ = self.release_lease(&control.lease).await;
                return Err(error);
            }
        };
        let expires_at_unix_ms = Self::plan_expiry().min(control.lease.expires_at_unix_ms);
        let summary = DeploymentPlanSummary {
            plan_hash: plan.hash().as_str().into(),
            target: reference_from_target(&target, input.environment.clone()),
            operations: plan.operations().to_vec(),
            drift: assess_drift(plan.desired(), plan.observed_before()),
            expires_at_unix_ms,
        };
        self.cache_plan(
            summary.plan_hash.clone(),
            CachedPlan::Deployment(Box::new(CachedDeploymentPlan {
                plan,
                environment: input.environment,
                expires_at_unix_ms,
            })),
        )
        .await;
        Ok(summary)
    }

    pub async fn apply_deployment(&self, plan_hash: &str) -> DevkitResult<DeploymentApplyReceipt> {
        let _mutation = self.mutation.lock().await;
        let cached = self.deployment_plan(plan_hash).await?;
        let authorization = self.require_authorization(true).await?;
        ensure_account(&authorization, &cached.plan.desired().target().account_id)?;
        let receipt = self
            .provider
            .apply(&authorization, &cached.plan, now_unix_ms())
            .await?;
        let observed = self
            .provider
            .inspect(&authorization, &receipt.target, now_unix_ms())
            .await?;
        let endpoint = public_fact_string(&observed, "gateway_url").ok_or_else(|| {
            DevkitError::new(
                DevkitErrorCode::VerificationFailed,
                "deployed gateway did not publish its endpoint",
            )
        })?;
        self.cached_plans.lock().await.remove(plan_hash);
        self.release_lease(&cached.plan.control().lease).await?;
        Ok(DeploymentApplyReceipt {
            provider_id: self.provider.describe().provider_id.clone(),
            provider_version: self.provider.describe().provider_version.to_string(),
            target: reference_from_target(&receipt.target, cached.environment),
            outcome: receipt.outcome,
            previous_version_id: receipt.previous_remote_version,
            version_id: receipt.active_remote_version,
            endpoint,
            operation_id: receipt.operation_id,
            completed_at_unix_ms: receipt.completed_at_unix_ms,
        })
    }

    pub async fn inspect_deployment(
        &self,
        reference: DeploymentReferenceInput,
    ) -> DevkitResult<DeploymentObservation> {
        let authorization = self.require_authorization(true).await?;
        validate_environment(reference.environment.as_deref())?;
        ensure_account(&authorization, &reference.account_id)?;
        let target = self.target(
            reference.account_id.clone(),
            reference.deployment_id.clone(),
            reference.worker_name.clone(),
        )?;
        let observed = self
            .provider
            .inspect(&authorization, &target, now_unix_ms())
            .await?;
        Ok(observation_from_provider(observed, reference))
    }

    pub async fn test_deployment(
        &self,
        reference: DeploymentReferenceInput,
        identity_header: &str,
        identity_token: Vec<u8>,
    ) -> DevkitResult<DeploymentTestReceipt> {
        if !matches!(identity_header, "authorization" | "cf-access-jwt-assertion") {
            return Err(DevkitError::invalid_configuration(
                "gateway test identity header is unsupported",
            ));
        }
        let authorization = self.require_authorization(true).await?;
        validate_environment(reference.environment.as_deref())?;
        ensure_account(&authorization, &reference.account_id)?;
        let target = self.target(
            reference.account_id.clone(),
            reference.deployment_id.clone(),
            reference.worker_name.clone(),
        )?;
        let document = serde_json::to_vec(&serde_json::json!({
            "schemaVersion": 1,
            "header": identity_header,
            "token": std::str::from_utf8(&identity_token).map_err(|_| {
                DevkitError::invalid_configuration("gateway test identity is invalid")
            })?,
        }))
        .map_err(|_| DevkitError::invalid_configuration("gateway test identity is invalid"))?;
        let handle = self
            .sensitive
            .store(
                "cloudflare/gateway/one-time-identity",
                SensitiveValue::new(document)?,
            )
            .await?;
        let tested = self
            .provider
            .test(&authorization, &target, &handle, now_unix_ms())
            .await;
        let _ = self.sensitive.delete_handle(&handle).await;
        tested.map(|receipt| test_receipt(receipt, reference))
    }

    #[allow(clippy::too_many_arguments)]
    pub async fn rotate_deployment_secret(
        &self,
        reference: DeploymentReferenceInput,
        binding_name: String,
        revision: String,
        value: Vec<u8>,
        idempotency_key: Option<String>,
        expected_remote_version: Option<String>,
        expected_remote_etag: Option<String>,
    ) -> DevkitResult<SecretRotationPublicReceipt> {
        let _mutation = self.mutation.lock().await;
        let authorization = self.require_authorization(true).await?;
        validate_environment(reference.environment.as_deref())?;
        ensure_account(&authorization, &reference.account_id)?;
        let stored = self
            .resolve_sensitive_binding(&binding_name, &revision, Some(value))
            .await?;
        let target = self.target(
            reference.account_id.clone(),
            reference.deployment_id.clone(),
            reference.worker_name.clone(),
        )?;
        let control = self
            .acquire_lease(
                idempotency_key.unwrap_or_else(deployment_idempotency_key),
                expected_remote_version,
                expected_remote_etag,
            )
            .await?;
        let result = self
            .provider
            .rotate_secret(
                &authorization,
                SecretRotationRequest {
                    target,
                    binding_name,
                    new_value_handle: stored.handle,
                    new_revision: revision,
                    control: control.clone(),
                },
                now_unix_ms(),
            )
            .await;
        if result.is_ok() {
            self.release_lease(&control.lease).await?;
        }
        result.map(|receipt| SecretRotationPublicReceipt {
            target: reference,
            binding_name: receipt.binding_name,
            configured_revision: receipt.configured_revision,
            operation_id: receipt.operation_id,
            completed_at_unix_ms: receipt.completed_at_unix_ms,
        })
    }

    #[allow(clippy::too_many_arguments)]
    pub async fn rollback_deployment(
        &self,
        reference: DeploymentReferenceInput,
        restore_version: String,
        idempotency_key: Option<String>,
        expected_remote_version: Option<String>,
        expected_remote_etag: Option<String>,
    ) -> DevkitResult<RollbackPublicReceipt> {
        let _mutation = self.mutation.lock().await;
        let authorization = self.require_authorization(true).await?;
        validate_environment(reference.environment.as_deref())?;
        ensure_account(&authorization, &reference.account_id)?;
        let target = self.target(
            reference.account_id.clone(),
            reference.deployment_id.clone(),
            reference.worker_name.clone(),
        )?;
        let control = self
            .acquire_lease(
                idempotency_key.unwrap_or_else(deployment_idempotency_key),
                expected_remote_version,
                expected_remote_etag,
            )
            .await?;
        let result = self
            .provider
            .rollback(
                &authorization,
                RollbackRequest {
                    target,
                    restore_remote_version: restore_version,
                    control: control.clone(),
                },
                now_unix_ms(),
            )
            .await;
        if result.is_ok() {
            self.release_lease(&control.lease).await?;
        }
        result.map(|receipt| RollbackPublicReceipt {
            target: reference,
            previous_version_id: receipt.previous_remote_version,
            version_id: receipt.active_remote_version,
            operation_id: receipt.operation_id,
            boundary: receipt.boundary,
            completed_at_unix_ms: receipt.completed_at_unix_ms,
        })
    }

    pub async fn plan_destroy(
        &self,
        reference: DeploymentReferenceInput,
        idempotency_key: Option<String>,
        expected_remote_version: Option<String>,
        expected_remote_etag: Option<String>,
    ) -> DevkitResult<DestroyPlanSummary> {
        let _mutation = self.mutation.lock().await;
        let authorization = self.require_authorization(true).await?;
        validate_environment(reference.environment.as_deref())?;
        ensure_account(&authorization, &reference.account_id)?;
        let target = self.target(
            reference.account_id.clone(),
            reference.deployment_id.clone(),
            reference.worker_name.clone(),
        )?;
        let control = self
            .acquire_lease(
                idempotency_key.unwrap_or_else(deployment_idempotency_key),
                expected_remote_version,
                expected_remote_etag,
            )
            .await?;
        let plan = match self
            .provider
            .destroy_plan(&authorization, &target, control.clone(), now_unix_ms())
            .await
        {
            Ok(plan) => plan,
            Err(error) => {
                let _ = self.release_lease(&control.lease).await;
                return Err(error);
            }
        };
        let expires_at_unix_ms = Self::plan_expiry().min(control.lease.expires_at_unix_ms);
        let summary = DestroyPlanSummary {
            plan_hash: plan.hash().as_str().into(),
            target: reference,
            resources: plan.resources().clone(),
            expires_at_unix_ms,
        };
        self.cache_plan(
            summary.plan_hash.clone(),
            CachedPlan::Destroy(Box::new(CachedDestroyPlan {
                plan,
                expires_at_unix_ms,
            })),
        )
        .await;
        Ok(summary)
    }

    pub async fn apply_destroy(&self, plan_hash: &str) -> DevkitResult<DestroyPublicReceipt> {
        let _mutation = self.mutation.lock().await;
        let cached = self.destroy_plan(plan_hash).await?;
        let authorization = self.require_authorization(true).await?;
        ensure_account(&authorization, &cached.plan.target().account_id)?;
        let receipt = self
            .provider
            .destroy(&authorization, &cached.plan, now_unix_ms())
            .await?;
        self.cached_plans.lock().await.remove(plan_hash);
        self.release_lease(&cached.plan.control().lease).await?;
        Ok(DestroyPublicReceipt {
            plan_hash: receipt.plan_hash.as_str().into(),
            target: reference_from_target(&receipt.target, None),
            deleted_resources: receipt.deleted_resources,
            operation_id: receipt.operation_id,
            completed_at_unix_ms: receipt.completed_at_unix_ms,
        })
    }

    pub(super) fn target(
        &self,
        account_id: String,
        deployment_id: String,
        worker_name: String,
    ) -> DevkitResult<DeploymentTarget> {
        if account_id.len() != 32
            || !account_id.bytes().all(|byte| byte.is_ascii_hexdigit())
            || deployment_id.is_empty()
            || deployment_id.len() > 128
            || !deployment_id
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'_' | b'-'))
            || worker_name.is_empty()
            || worker_name.len() > 63
            || worker_name.starts_with('-')
            || worker_name.ends_with('-')
            || !worker_name
                .bytes()
                .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-')
        {
            return Err(DevkitError::invalid_configuration(
                "Cloudflare deployment target is invalid",
            ));
        }
        let target = DeploymentTarget {
            provider_id: CLOUDFLARE_PROVIDER_ID.into(),
            account_id,
            app_id: self.app_id.clone(),
            deployment_id,
            resource_name: worker_name,
        };
        target.validate()?;
        Ok(target)
    }

    async fn deployment_plan(&self, hash: &str) -> DevkitResult<CachedDeploymentPlan> {
        let plan = self.cached_plans.lock().await.get(hash).cloned();
        match plan {
            Some(CachedPlan::Deployment(plan)) if plan.expires_at_unix_ms > now_unix_ms() => {
                plan.plan.verify_integrity()?;
                Ok(*plan)
            }
            Some(_) => Err(DevkitError::new(
                DevkitErrorCode::InvalidPlan,
                "deployment plan is expired or has the wrong operation type",
            )),
            None => Err(DevkitError::new(
                DevkitErrorCode::NotFound,
                "deployment plan is unavailable; create a new plan",
            )),
        }
    }

    async fn destroy_plan(&self, hash: &str) -> DevkitResult<CachedDestroyPlan> {
        let plan = self.cached_plans.lock().await.get(hash).cloned();
        match plan {
            Some(CachedPlan::Destroy(plan)) if plan.expires_at_unix_ms > now_unix_ms() => {
                plan.plan.verify_integrity()?;
                Ok(*plan)
            }
            Some(_) => Err(DevkitError::new(
                DevkitErrorCode::InvalidPlan,
                "destroy plan is expired or has the wrong operation type",
            )),
            None => Err(DevkitError::new(
                DevkitErrorCode::NotFound,
                "destroy plan is unavailable; create a new plan",
            )),
        }
    }
}

pub(super) fn ensure_account(
    authorization: &agent_devkit::DeveloperAuthorization,
    account_id: &str,
) -> DevkitResult<()> {
    if authorization.account_id() != Some(account_id) {
        return Err(DevkitError::new(
            DevkitErrorCode::InvalidAuthorization,
            "deployment target differs from the selected Cloudflare account",
        ));
    }
    Ok(())
}

pub(super) fn reference_from_target(
    target: &DeploymentTarget,
    environment: Option<String>,
) -> DeploymentReferenceInput {
    DeploymentReferenceInput {
        account_id: target.account_id.clone(),
        deployment_id: target.deployment_id.clone(),
        worker_name: target.resource_name.clone(),
        environment,
    }
}

pub(super) fn observation_from_provider(
    observed: ObservedDeploymentState,
    reference: DeploymentReferenceInput,
) -> DeploymentObservation {
    let endpoint = public_fact_string(&observed, "gateway_url");
    let gateway_protocol_version = public_fact_string(&observed, "gateway_protocol_version");
    let d1_migration_status = public_fact_string(&observed, "observed_d1_migration_status");
    let workers_dev_ready = observed
        .resource_facts
        .get("observed_workers_dev_in_sync")
        .and_then(Value::as_bool);
    DeploymentObservation {
        target: reference,
        reachability: observed.reachability,
        remote_version: observed.remote_version,
        remote_etag: observed.remote_etag,
        observed_desired_hash: observed.observed_desired_hash,
        active_artifact_hash: observed.active_artifact_hash,
        endpoint,
        gateway_protocol_version,
        d1_migration_status,
        workers_dev_ready,
        observed_at_unix_ms: observed.observed_at_unix_ms,
    }
}

pub(super) fn public_fact_string(observed: &ObservedDeploymentState, key: &str) -> Option<String> {
    observed
        .resource_facts
        .get(key)
        .and_then(Value::as_str)
        .filter(|value| value.len() <= 8 * 1024 && !value.chars().any(char::is_control))
        .map(str::to_owned)
}

fn test_receipt(
    receipt: GatewayTestReceipt,
    reference: DeploymentReferenceInput,
) -> DeploymentTestReceipt {
    DeploymentTestReceipt {
        target: reference,
        protocol_version: receipt.protocol_version,
        remote_version: receipt.remote_version,
        tested_at_unix_ms: receipt.tested_at_unix_ms,
    }
}

fn deployment_idempotency_key() -> String {
    format!("agentweave-deployment-{}", Uuid::new_v4())
}

pub(super) fn validate_environment(environment: Option<&str>) -> DevkitResult<()> {
    if environment.is_some_and(|value| {
        value.is_empty()
            || value.len() > 32
            || value.starts_with('-')
            || value.ends_with('-')
            || !value
                .bytes()
                .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-')
    }) {
        return Err(DevkitError::invalid_configuration(
            "Cloudflare deployment environment is invalid",
        ));
    }
    Ok(())
}

pub(super) fn validate_gateway_configuration(
    configuration: &Value,
    target: &DeploymentTarget,
    environment: Option<&str>,
) -> DevkitResult<BTreeSet<String>> {
    let root = configuration.as_object().ok_or_else(|| {
        DevkitError::invalid_configuration("gateway configuration must be an object")
    })?;
    if root.get("schemaVersion").and_then(Value::as_u64) != Some(1)
        || root.get("deploymentId").and_then(Value::as_str) != Some(target.deployment_id.as_str())
        || root.get("environment").and_then(Value::as_str)
            != Some(environment.unwrap_or("production"))
    {
        return Err(DevkitError::invalid_configuration(
            "gateway configuration does not match the deployment target",
        ));
    }
    let upstream_secret = root
        .get("upstream")
        .and_then(Value::as_object)
        .and_then(|upstream| upstream.get("secretBinding"))
        .and_then(Value::as_str)
        .ok_or_else(|| {
            DevkitError::invalid_configuration("gateway upstream secret binding is missing")
        })?;
    let mut required = BTreeSet::from([upstream_secret.to_owned()]);
    let entitlements = root
        .get("entitlements")
        .and_then(Value::as_object)
        .ok_or_else(|| {
            DevkitError::invalid_configuration("gateway entitlement configuration is missing")
        })?;
    match entitlements.get("mode").and_then(Value::as_str) {
        Some("static") => {}
        Some("signed_http") => {
            let binding = entitlements
                .get("projection")
                .and_then(Value::as_object)
                .and_then(|projection| projection.get("secretBinding"))
                .and_then(Value::as_str)
                .unwrap_or("ENTITLEMENT_PROJECTION_SECRET");
            required.insert(binding.to_owned());
        }
        _ => {
            return Err(DevkitError::invalid_configuration(
                "gateway entitlement mode is invalid",
            ));
        }
    }
    for binding in &required {
        if binding.is_empty()
            || binding.len() > 64
            || !binding
                .bytes()
                .all(|byte| byte.is_ascii_uppercase() || byte.is_ascii_digit() || byte == b'_')
        {
            return Err(DevkitError::invalid_configuration(
                "gateway secret binding is invalid",
            ));
        }
    }
    Ok(required)
}
