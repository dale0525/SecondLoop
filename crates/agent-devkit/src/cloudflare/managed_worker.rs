use super::commerce_d1;
use super::d1::{self, D1Database, D1MigrationStatus, PreparedD1Resources};
use super::provider_support::{inspect_reconciliation_schedule, inspect_workers_dev};
use super::{CloudflareRestClient, CloudflareTransport};
use crate::{
    DeploymentTarget, DesiredDeploymentState, DeveloperAuthorization, DevkitError, DevkitResult,
    GatewayTestReceipt, ObservationReachability, ObservedDeploymentState, RollbackBoundary,
    RollbackResourceScope, SensitiveInputHandle, SensitiveInputResolver,
};
use serde_json::{Value, json};
use std::collections::BTreeSet;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum ManagedWorkerRole {
    Gateway,
    EntitlementPolicy,
}

impl ManagedWorkerRole {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Gateway => "model_gateway",
            Self::EntitlementPolicy => "entitlement_policy",
        }
    }
}

#[derive(Clone, Debug)]
pub(super) struct PreparedWorkerResources {
    pub role: ManagedWorkerRole,
    pub database: Option<D1Database>,
    pub migration_hash: Option<String>,
    pub commerce_enabled: bool,
}

pub(super) fn role_from_desired(
    desired: &DesiredDeploymentState,
) -> DevkitResult<ManagedWorkerRole> {
    match desired
        .public_configuration()
        .get("worker_role")
        .and_then(Value::as_str)
    {
        None | Some("model_gateway") => Ok(ManagedWorkerRole::Gateway),
        Some("entitlement_policy") => Ok(ManagedWorkerRole::EntitlementPolicy),
        Some(_) => Err(DevkitError::invalid_configuration(
            "Cloudflare managed Worker role is unsupported",
        )),
    }
}

pub(super) fn role_from_observation(observed: &ObservedDeploymentState) -> ManagedWorkerRole {
    match observed
        .resource_facts
        .get("worker_role")
        .and_then(Value::as_str)
    {
        Some("entitlement_policy") => ManagedWorkerRole::EntitlementPolicy,
        _ => ManagedWorkerRole::Gateway,
    }
}

pub(super) fn commerce_enabled_from_observation(observed: &ObservedDeploymentState) -> bool {
    observed
        .resource_facts
        .get("commerce_enabled")
        .and_then(Value::as_bool)
        == Some(true)
}

pub(super) fn validate_desired(desired: &DesiredDeploymentState) -> DevkitResult<bool> {
    match role_from_desired(desired)? {
        ManagedWorkerRole::Gateway => {
            d1::validate_gateway_public_configuration(desired)?;
            Ok(true)
        }
        ManagedWorkerRole::EntitlementPolicy => {
            commerce_d1::validate_entitlement_public_configuration(desired)
        }
    }
}

pub(super) fn database_name(
    role: ManagedWorkerRole,
    commerce_enabled: bool,
    target: &DeploymentTarget,
) -> Option<String> {
    match role {
        ManagedWorkerRole::Gateway => Some(d1::database_name(target)),
        ManagedWorkerRole::EntitlementPolicy if commerce_enabled => {
            Some(commerce_d1::database_name(target))
        }
        ManagedWorkerRole::EntitlementPolicy => None,
    }
}

pub(super) async fn ensure_resources<T, R>(
    rest: &CloudflareRestClient<T, R>,
    authorization: &DeveloperAuthorization,
    desired: &DesiredDeploymentState,
) -> DevkitResult<PreparedWorkerResources>
where
    T: CloudflareTransport,
    R: SensitiveInputResolver,
{
    let role = role_from_desired(desired)?;
    match role {
        ManagedWorkerRole::Gateway => {
            let resources = d1::ensure_resources(rest, authorization, desired).await?;
            Ok(from_database(role, resources, false))
        }
        ManagedWorkerRole::EntitlementPolicy => {
            let commerce_enabled = commerce_d1::validate_entitlement_public_configuration(desired)?;
            if commerce_enabled {
                let resources = commerce_d1::ensure_resources(rest, authorization, desired).await?;
                Ok(from_database(role, resources, true))
            } else {
                Ok(PreparedWorkerResources {
                    role,
                    database: None,
                    migration_hash: None,
                    commerce_enabled: false,
                })
            }
        }
    }
}

pub(super) async fn inspect_database<T, R>(
    rest: &CloudflareRestClient<T, R>,
    authorization: &DeveloperAuthorization,
    target: &DeploymentTarget,
    role: ManagedWorkerRole,
    commerce_enabled: bool,
) -> DevkitResult<Option<(D1Database, D1MigrationStatus, String)>>
where
    T: CloudflareTransport,
    R: SensitiveInputResolver,
{
    match role {
        ManagedWorkerRole::Gateway => match d1::inspect_database(rest, authorization, target)
            .await?
        {
            Some(database) => {
                let status = d1::inspect_migrations(rest, authorization, target, &database).await?;
                Ok(Some((database, status, d1::migration_hash())))
            }
            None => Ok(None),
        },
        ManagedWorkerRole::EntitlementPolicy if commerce_enabled => {
            match commerce_d1::inspect_database(rest, authorization, target).await? {
                Some(database) => {
                    let status =
                        commerce_d1::inspect_migrations(rest, authorization, target, &database)
                            .await?;
                    Ok(Some((database, status, commerce_d1::migration_hash())))
                }
                None => Ok(None),
            }
        }
        ManagedWorkerRole::EntitlementPolicy => Ok(None),
    }
}

pub(super) async fn delete_database<T, R>(
    rest: &CloudflareRestClient<T, R>,
    authorization: &DeveloperAuthorization,
    target: &DeploymentTarget,
    role: ManagedWorkerRole,
    expected_database_id: &str,
) -> DevkitResult<()>
where
    T: CloudflareTransport,
    R: SensitiveInputResolver,
{
    match role {
        ManagedWorkerRole::Gateway => {
            d1::delete_database(rest, authorization, target, expected_database_id).await
        }
        ManagedWorkerRole::EntitlementPolicy => {
            commerce_d1::delete_database(rest, authorization, target, expected_database_id).await
        }
    }
}

pub(super) fn resources_in_sync(
    observed: &ObservedDeploymentState,
    role: ManagedWorkerRole,
    commerce_enabled: bool,
) -> bool {
    let workers_dev_ready = observed
        .resource_facts
        .get("observed_workers_dev_in_sync")
        .and_then(Value::as_bool)
        == Some(true);
    if !workers_dev_ready {
        return false;
    }
    if role == ManagedWorkerRole::EntitlementPolicy
        && commerce_enabled
        && observed
            .resource_facts
            .get("observed_reconciliation_schedule_in_sync")
            .and_then(Value::as_bool)
            != Some(true)
    {
        return false;
    }
    if role == ManagedWorkerRole::EntitlementPolicy && !commerce_enabled {
        return observed.resource_facts.get("d1_database_id").is_none();
    }
    let expected_hash = match role {
        ManagedWorkerRole::Gateway => d1::migration_hash(),
        ManagedWorkerRole::EntitlementPolicy => commerce_d1::migration_hash(),
    };
    let annotated_id = observed
        .resource_facts
        .get("d1_database_id")
        .and_then(Value::as_str);
    let actual_id = observed
        .resource_facts
        .get("observed_d1_database_id")
        .and_then(Value::as_str);
    let annotated_hash = observed
        .resource_facts
        .get("d1_migration_hash")
        .and_then(Value::as_str);
    annotated_id.is_some()
        && annotated_id == actual_id
        && annotated_hash == Some(expected_hash.as_str())
        && observed
            .resource_facts
            .get("observed_d1_migration_status")
            .and_then(Value::as_str)
            == Some("in_sync")
}

pub(super) fn worker_code_rollback_boundary() -> RollbackBoundary {
    RollbackBoundary {
        restored: BTreeSet::from([RollbackResourceScope::WorkerCode]),
        not_restored: BTreeSet::from([
            RollbackResourceScope::SecretBindings,
            RollbackResourceScope::Routes,
            RollbackResourceScope::KvData,
            RollbackResourceScope::D1Data,
            RollbackResourceScope::DurableObjects,
        ]),
        manual_repair_required: true,
    }
}

pub(super) async fn enrich_observation<T, R>(
    rest: &CloudflareRestClient<T, R>,
    authorization: &DeveloperAuthorization,
    target: &DeploymentTarget,
    observed: &mut ObservedDeploymentState,
    expected: Option<(ManagedWorkerRole, bool)>,
) -> DevkitResult<()>
where
    T: CloudflareTransport,
    R: SensitiveInputResolver,
{
    let (role, commerce_enabled) = expected.unwrap_or_else(|| {
        (
            role_from_observation(observed),
            commerce_enabled_from_observation(observed),
        )
    });
    if let Some((database, migration_status, _)) =
        inspect_database(rest, authorization, target, role, commerce_enabled).await?
    {
        if role == ManagedWorkerRole::EntitlementPolicy && commerce_enabled {
            let verifications =
                commerce_d1::inspect_verifications(rest, authorization, target, &database).await?;
            observed.resource_facts.insert(
                "commerce_webhook_verified_at".into(),
                json!(verifications.get("signed_webhook_v1").copied()),
            );
            observed.resource_facts.insert(
                "commerce_portal_verified_at".into(),
                json!(verifications.get("customer_portal_v1").copied()),
            );
        }
        observed
            .resource_facts
            .insert("observed_d1_database_id".into(), json!(database.id));
        observed
            .resource_facts
            .insert("observed_d1_database_name".into(), json!(database.name));
        observed.resource_facts.insert(
            "observed_d1_migration_status".into(),
            json!(match migration_status {
                D1MigrationStatus::Missing => "missing",
                D1MigrationStatus::InSync => "in_sync",
                D1MigrationStatus::Drifted => "drifted",
            }),
        );
    } else if role == ManagedWorkerRole::Gateway || commerce_enabled {
        observed
            .resource_facts
            .insert("observed_d1_missing".into(), json!(true));
    }
    if observed.reachability == ObservationReachability::Reachable {
        observed.resource_facts.insert(
            "observed_workers_dev_in_sync".into(),
            json!(inspect_workers_dev(rest, authorization, target).await?),
        );
        if role == ManagedWorkerRole::EntitlementPolicy && commerce_enabled {
            observed.resource_facts.insert(
                "observed_reconciliation_schedule_in_sync".into(),
                json!(inspect_reconciliation_schedule(rest, authorization, target).await?),
            );
        }
    }
    Ok(())
}

pub(super) async fn test_managed_worker<T, R>(
    rest: &CloudflareRestClient<T, R>,
    observed: &ObservedDeploymentState,
    target: &DeploymentTarget,
    one_time_identity: &SensitiveInputHandle,
    now_unix_ms: u64,
) -> DevkitResult<GatewayTestReceipt>
where
    T: CloudflareTransport,
    R: SensitiveInputResolver,
{
    let role = role_from_observation(observed);
    let health = match role {
        ManagedWorkerRole::Gateway => {
            let url = observed
                .resource_facts
                .get("gateway_health_url")
                .and_then(Value::as_str)
                .ok_or_else(|| {
                    DevkitError::new(
                        crate::DevkitErrorCode::VerificationFailed,
                        "Cloudflare Worker did not publish a verified gateway health URL",
                    )
                })?;
            rest.test_gateway_health(url, one_time_identity).await?
        }
        ManagedWorkerRole::EntitlementPolicy => {
            let url = observed
                .resource_facts
                .get("entitlement_health_url")
                .and_then(Value::as_str)
                .ok_or_else(|| {
                    DevkitError::new(
                        crate::DevkitErrorCode::VerificationFailed,
                        "Cloudflare Worker did not publish a verified entitlement health URL",
                    )
                })?;
            rest.test_entitlement_health(url).await?
        }
    };
    let protocol_version = health
        .get("protocol_version")
        .and_then(Value::as_str)
        .ok_or_else(|| {
            DevkitError::new(
                crate::DevkitErrorCode::RemoteProtocol,
                "Worker health response omitted its protocol version",
            )
        })?;
    if health.get("deployment_id").and_then(Value::as_str) != Some(target.deployment_id.as_str()) {
        return Err(DevkitError::new(
            crate::DevkitErrorCode::VerificationFailed,
            "Worker health response belongs to a different deployment",
        ));
    }
    let remote_version = health
        .get("remote_version")
        .and_then(Value::as_str)
        .ok_or_else(|| {
            DevkitError::new(
                crate::DevkitErrorCode::RemoteProtocol,
                "Worker health response omitted its remote version",
            )
        })?;
    if observed.remote_version.as_deref() != Some(remote_version) {
        return Err(DevkitError::new(
            crate::DevkitErrorCode::DriftDetected,
            "Worker health version differs from the Cloudflare deployment",
        ));
    }
    Ok(GatewayTestReceipt {
        target: target.clone(),
        protocol_version: protocol_version.into(),
        remote_version: remote_version.into(),
        tested_at_unix_ms: now_unix_ms,
    })
}

fn from_database(
    role: ManagedWorkerRole,
    resources: PreparedD1Resources,
    commerce_enabled: bool,
) -> PreparedWorkerResources {
    PreparedWorkerResources {
        role,
        database: Some(resources.database),
        migration_hash: Some(resources.migration_hash),
        commerce_enabled,
    }
}
