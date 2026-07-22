use crate::developer_control_plane::{
    CachedAccessBundleDestroyPlan, CachedPlan, DeveloperControlPlane, now_unix_ms,
};
use crate::developer_control_plane_bundle::ExpectedResourceVersion;
use crate::developer_control_plane_bundle_lifecycle::{
    AccessBundleLifecycleResourceReceipt, AccessBundleLifecycleTargets,
    AccessBundleMutationOutcome, blocked_resource, child_control, deleted_resource, error_resource,
    lifecycle_bundle_id, lifecycle_idempotency_key, mutation_failure_outcome, target,
    validate_targets,
};
use crate::developer_control_plane_deployment::{
    DeploymentReferenceInput, ensure_account, reference_from_target,
};
use agent_devkit::{DestroyPlan, DevkitError, DevkitErrorCode, DevkitResult};
use serde::{Deserialize, Serialize};
use serde_json::json;
use sha2::{Digest, Sha256};
use sqlx::Row;
use std::collections::{BTreeMap, BTreeSet};
use uuid::Uuid;

const ENTITLEMENT_POLICY_RESOURCE_ID: &str = "entitlement-policy";
const MODEL_GATEWAY_RESOURCE_ID: &str = "model-gateway";

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AccessBundleDestroyPlanInput {
    pub targets: AccessBundleLifecycleTargets,
    #[serde(default)]
    pub idempotency_key: Option<String>,
    #[serde(default)]
    pub expected_resources: BTreeMap<String, ExpectedResourceVersion>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AccessBundleDestroyPlanSummary {
    pub schema_version: u32,
    pub plan_hash: String,
    pub bundle_id: String,
    pub resources: Vec<AccessBundleDestroyResourceSummary>,
    pub commerce_data_loss_requires_confirmation: bool,
    pub expires_at_unix_ms: u64,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AccessBundleDestroyResourceSummary {
    pub resource_id: String,
    pub target: DeploymentReferenceInput,
    pub resources: BTreeSet<String>,
    pub ownership: &'static str,
    pub delete_requires_confirmation: bool,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AccessBundleDestroyReceipt {
    pub schema_version: u32,
    pub plan_hash: String,
    pub operation_id: Uuid,
    pub outcome: AccessBundleMutationOutcome,
    pub resources: BTreeMap<String, AccessBundleLifecycleResourceReceipt>,
    pub completed_at_unix_ms: u64,
}

impl DeveloperControlPlane {
    pub async fn plan_destroy_access_bundle(
        &self,
        input: AccessBundleDestroyPlanInput,
    ) -> DevkitResult<AccessBundleDestroyPlanSummary> {
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
        let gateway = self
            .provider
            .destroy_plan(
                &authorization,
                &gateway_target,
                child_control(
                    &control,
                    "destroy-gateway",
                    input.expected_resources.get(MODEL_GATEWAY_RESOURCE_ID),
                ),
                now_unix_ms(),
            )
            .await;
        let gateway = match gateway {
            Ok(plan) => plan,
            Err(error) => {
                let _ = self.release_lease(&control.lease).await;
                return Err(error);
            }
        };
        let entitlement = self
            .provider
            .destroy_plan(
                &authorization,
                &entitlement_target,
                child_control(
                    &control,
                    "destroy-entitlement",
                    input.expected_resources.get(ENTITLEMENT_POLICY_RESOURCE_ID),
                ),
                now_unix_ms(),
            )
            .await;
        let entitlement = match entitlement {
            Ok(plan) => plan,
            Err(error) => {
                let _ = self.release_lease(&control.lease).await;
                return Err(error);
            }
        };
        let commerce_confirmation = entitlement
            .resources()
            .iter()
            .any(|resource| resource.starts_with("d1-database:"));
        let plan_hash = destroy_bundle_hash(&gateway, &entitlement, commerce_confirmation)?;
        let expires_at_unix_ms = Self::plan_expiry().min(control.lease.expires_at_unix_ms);
        let resources = vec![
            destroy_summary(
                MODEL_GATEWAY_RESOURCE_ID,
                input.targets.gateway.clone(),
                &gateway,
                false,
            ),
            destroy_summary(
                ENTITLEMENT_POLICY_RESOURCE_ID,
                input.targets.entitlement_policy.clone(),
                &entitlement,
                commerce_confirmation,
            ),
        ];
        let summary = AccessBundleDestroyPlanSummary {
            schema_version: 1,
            plan_hash: plan_hash.clone(),
            bundle_id: lifecycle_bundle_id(&input.targets),
            resources,
            commerce_data_loss_requires_confirmation: commerce_confirmation,
            expires_at_unix_ms,
        };
        self.cache_plan(
            plan_hash,
            CachedPlan::AccessBundleDestroy(Box::new(CachedAccessBundleDestroyPlan {
                gateway,
                entitlement,
                commerce_confirmation,
                parent_control: control,
                expires_at_unix_ms,
            })),
        )
        .await;
        Ok(summary)
    }

    pub async fn apply_destroy_access_bundle(
        &self,
        plan_hash: &str,
        confirm_commerce_projection_rebuild: bool,
    ) -> DevkitResult<AccessBundleDestroyReceipt> {
        let _mutation = self.mutation.lock().await;
        let cached = self.access_bundle_destroy_plan(plan_hash).await?;
        if cached.commerce_confirmation && !confirm_commerce_projection_rebuild {
            return Err(DevkitError::invalid_configuration(
                "Commerce projection rebuild confirmation is required",
            ));
        }
        let authorization = self.require_authorization(true).await?;
        ensure_account(&authorization, &cached.gateway.target().account_id)?;
        let operation_id = cached.parent_control.operation_id;
        let mut resources = BTreeMap::new();
        let gateway = self
            .provider
            .destroy(&authorization, &cached.gateway, now_unix_ms())
            .await;
        if let Err(error) = gateway {
            resources.insert(
                MODEL_GATEWAY_RESOURCE_ID.into(),
                error_resource(
                    MODEL_GATEWAY_RESOURCE_ID,
                    reference_from_target(cached.gateway.target(), None),
                    &error,
                ),
            );
            resources.insert(
                ENTITLEMENT_POLICY_RESOURCE_ID.into(),
                blocked_resource(
                    ENTITLEMENT_POLICY_RESOURCE_ID,
                    reference_from_target(cached.entitlement.target(), None),
                ),
            );
            self.cached_plans.lock().await.remove(plan_hash);
            let _ = self.release_lease(&cached.parent_control.lease).await;
            return Ok(destroy_receipt(
                plan_hash,
                operation_id,
                mutation_failure_outcome(&error, false),
                resources,
            ));
        }
        resources.insert(
            MODEL_GATEWAY_RESOURCE_ID.into(),
            deleted_resource(
                MODEL_GATEWAY_RESOURCE_ID,
                reference_from_target(cached.gateway.target(), None),
            ),
        );
        let entitlement = self
            .provider
            .destroy(&authorization, &cached.entitlement, now_unix_ms())
            .await;
        if let Err(error) = entitlement {
            resources.insert(
                ENTITLEMENT_POLICY_RESOURCE_ID.into(),
                error_resource(
                    ENTITLEMENT_POLICY_RESOURCE_ID,
                    reference_from_target(cached.entitlement.target(), None),
                    &error,
                ),
            );
            self.cached_plans.lock().await.remove(plan_hash);
            let _ = self.release_lease(&cached.parent_control.lease).await;
            return Ok(destroy_receipt(
                plan_hash,
                operation_id,
                mutation_failure_outcome(&error, true),
                resources,
            ));
        }
        resources.insert(
            ENTITLEMENT_POLICY_RESOURCE_ID.into(),
            deleted_resource(
                ENTITLEMENT_POLICY_RESOURCE_ID,
                reference_from_target(cached.entitlement.target(), None),
            ),
        );
        self.delete_access_bundle_sensitive_bindings().await?;
        self.cached_plans.lock().await.remove(plan_hash);
        self.release_lease(&cached.parent_control.lease).await?;
        Ok(destroy_receipt(
            plan_hash,
            operation_id,
            AccessBundleMutationOutcome::Succeeded,
            resources,
        ))
    }

    async fn access_bundle_destroy_plan(
        &self,
        hash: &str,
    ) -> DevkitResult<CachedAccessBundleDestroyPlan> {
        match self.cached_plans.lock().await.get(hash).cloned() {
            Some(CachedPlan::AccessBundleDestroy(plan))
                if plan.expires_at_unix_ms > now_unix_ms() =>
            {
                plan.gateway.verify_integrity()?;
                plan.entitlement.verify_integrity()?;
                if destroy_bundle_hash(
                    &plan.gateway,
                    &plan.entitlement,
                    plan.commerce_confirmation,
                )? != hash
                {
                    return Err(DevkitError::new(
                        DevkitErrorCode::PlanIntegrityFailed,
                        "access destroy plan content does not match its immutable hash",
                    ));
                }
                Ok(*plan)
            }
            Some(_) => Err(DevkitError::new(
                DevkitErrorCode::InvalidPlan,
                "access destroy plan is expired or has the wrong operation type",
            )),
            None => Err(DevkitError::new(
                DevkitErrorCode::NotFound,
                "access destroy plan is unavailable; create a new plan",
            )),
        }
    }

    async fn delete_access_bundle_sensitive_bindings(&self) -> DevkitResult<()> {
        let rows =
            sqlx::query("SELECT handle FROM developer_sensitive_bindings WHERE project_key = ?1")
                .bind(&self.project_key)
                .fetch_all(&self.pool)
                .await
                .map_err(|_| crate::developer_control_plane::internal_state_error())?;
        sqlx::query("DELETE FROM developer_sensitive_bindings WHERE project_key = ?1")
            .bind(&self.project_key)
            .execute(&self.pool)
            .await
            .map_err(|_| crate::developer_control_plane::internal_state_error())?;
        for row in rows {
            if let Ok(handle) = agent_devkit::SensitiveInputHandle::from_opaque_reference(
                row.get::<String, _>("handle"),
            ) {
                let _ = self.sensitive.delete_handle(&handle).await;
            }
        }
        Ok(())
    }
}

fn destroy_receipt(
    plan_hash: &str,
    operation_id: Uuid,
    outcome: AccessBundleMutationOutcome,
    resources: BTreeMap<String, AccessBundleLifecycleResourceReceipt>,
) -> AccessBundleDestroyReceipt {
    AccessBundleDestroyReceipt {
        schema_version: 1,
        plan_hash: plan_hash.into(),
        operation_id,
        outcome,
        resources,
        completed_at_unix_ms: now_unix_ms(),
    }
}

fn destroy_summary(
    resource_id: &str,
    target: DeploymentReferenceInput,
    plan: &DestroyPlan,
    delete_requires_confirmation: bool,
) -> AccessBundleDestroyResourceSummary {
    AccessBundleDestroyResourceSummary {
        resource_id: resource_id.into(),
        target,
        resources: plan.resources().clone(),
        ownership: "exclusive",
        delete_requires_confirmation,
    }
}

fn destroy_bundle_hash(
    gateway: &DestroyPlan,
    entitlement: &DestroyPlan,
    commerce_confirmation: bool,
) -> DevkitResult<String> {
    let bytes = serde_json::to_vec(&json!({
        "schemaVersion": 1,
        "gatewayPlanHash": gateway.hash().as_str(),
        "entitlementPlanHash": entitlement.hash().as_str(),
        "commerceConfirmation": commerce_confirmation,
    }))
    .map_err(|_| {
        DevkitError::new(
            DevkitErrorCode::Internal,
            "access destroy plan could not be hashed",
        )
    })?;
    Ok(hex::encode(Sha256::digest(bytes)))
}
