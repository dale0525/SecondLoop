use super::commerce_d1::COMMERCE_D1_BINDING_NAME;
use super::d1::D1_BINDING_NAME;
use super::managed_worker::{ManagedWorkerRole, PreparedWorkerResources};
use super::provider::{
    CAPABILITY_D1_READ, CAPABILITY_D1_WRITE, CAPABILITY_WORKERS_SCRIPTS_READ,
    CAPABILITY_WORKERS_SCRIPTS_WRITE,
};
use super::{
    CLOUDFLARE_PROVIDER_ID, CloudflareHttpMethod, CloudflareRestClient, CloudflareTransport,
};
use crate::{
    DeploymentPlan, DeploymentTarget, DestroyPlan, DeveloperAuthorization, DevkitError,
    DevkitErrorCode, DevkitResult, MutationControl, ObservationReachability,
    ObservedDeploymentState, ObservedSecretBinding, RemoteMutationRisk, SensitiveInputResolver,
};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};

pub(super) fn validate_cloudflare_segment(label: &str, value: &str) -> DevkitResult<()> {
    if value.is_empty()
        || value.len() > 128
        || !value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.'))
    {
        return Err(DevkitError::invalid_configuration(format!(
            "Cloudflare {label} is invalid"
        )));
    }
    Ok(())
}

pub(super) fn validate_deployment_target(target: &DeploymentTarget) -> DevkitResult<()> {
    target.validate()?;
    if target.provider_id != CLOUDFLARE_PROVIDER_ID {
        return Err(DevkitError::invalid_configuration(
            "deployment target belongs to another provider",
        ));
    }
    validate_cloudflare_segment("account id", &target.account_id)?;
    validate_cloudflare_segment("Worker script name", &target.resource_name)?;
    Ok(())
}

pub(super) fn ensure_provider_authorization(
    authorization: &DeveloperAuthorization,
    target: &DeploymentTarget,
    write: bool,
    now_unix_ms: u64,
) -> DevkitResult<()> {
    validate_deployment_target(target)?;
    let mut capabilities = BTreeSet::from([
        CAPABILITY_D1_READ.into(),
        CAPABILITY_WORKERS_SCRIPTS_READ.into(),
    ]);
    capabilities.insert(CAPABILITY_D1_WRITE.into());
    if write {
        capabilities.insert(CAPABILITY_WORKERS_SCRIPTS_WRITE.into());
    }
    authorization.ensure_usable(
        CLOUDFLARE_PROVIDER_ID,
        &target.account_id,
        &capabilities,
        now_unix_ms,
    )
}

pub(super) fn worker_script_path(target: &DeploymentTarget, suffix: &str) -> String {
    let base = format!(
        "accounts/{}/workers/scripts/{}",
        target.account_id, target.resource_name
    );
    if suffix.is_empty() {
        base
    } else {
        format!("{base}/{suffix}")
    }
}

pub(super) fn empty_observation(
    target: &DeploymentTarget,
    reachability: ObservationReachability,
    now_unix_ms: u64,
) -> ObservedDeploymentState {
    ObservedDeploymentState {
        target: target.clone(),
        reachability,
        remote_version: None,
        remote_etag: None,
        observed_desired_hash: None,
        active_artifact_hash: None,
        secret_bindings: BTreeMap::new(),
        managed_routes: BTreeSet::new(),
        resource_facts: BTreeMap::new(),
        observed_at_unix_ms: now_unix_ms,
    }
}

#[derive(Default)]
pub(super) struct ParsedDeploymentFacts {
    pub active_version: Option<String>,
    pub etag: Option<String>,
    pub desired_hash: Option<String>,
    pub artifact_hash: Option<String>,
    pub secret_revisions: BTreeMap<String, String>,
    pub routes: BTreeSet<String>,
    pub public_facts: BTreeMap<String, Value>,
}

pub(super) fn parse_deployment_facts(value: &Value) -> ParsedDeploymentFacts {
    let current = value
        .get("deployments")
        .and_then(Value::as_array)
        .and_then(|items| items.first())
        .unwrap_or(value);
    let mut annotations = current
        .get("annotations")
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default();
    if let Some(version_annotations) = current
        .get("versions")
        .and_then(Value::as_array)
        .and_then(|versions| versions.first())
        .and_then(|version| version.get("annotations"))
        .and_then(Value::as_object)
    {
        for (key, value) in version_annotations {
            annotations
                .entry(key.clone())
                .or_insert_with(|| value.clone());
        }
    }
    let active_version = find_string(current, &["active_version", "version_id"]).or_else(|| {
        current
            .get("versions")
            .and_then(Value::as_array)
            .and_then(|versions| versions.first())
            .and_then(|version| find_string(version, &["version_id", "id"]))
    });
    let desired_hash = annotations
        .get("agentweave_desired_hash")
        .and_then(Value::as_str)
        .map(str::to_owned);
    let artifact_hash = annotations
        .get("agentweave_artifact_hash")
        .and_then(Value::as_str)
        .map(str::to_owned);
    let secret_revisions = annotations
        .get("agentweave_secret_revisions")
        .and_then(Value::as_object)
        .map(|values| {
            values
                .iter()
                .filter_map(|(name, revision)| {
                    revision
                        .as_str()
                        .map(|revision| (name.clone(), revision.into()))
                })
                .collect()
        })
        .unwrap_or_default();
    let routes = current
        .get("routes")
        .and_then(Value::as_array)
        .map(|routes| {
            routes
                .iter()
                .filter_map(Value::as_str)
                .map(str::to_owned)
                .collect()
        })
        .unwrap_or_default();
    let mut public_facts = BTreeMap::new();
    for key in [
        "gateway_url",
        "gateway_health_url",
        "gateway_protocol_version",
        "deployment_id",
        "d1_database_id",
        "d1_database_name",
        "d1_migration_hash",
        "worker_role",
        "worker_url",
        "entitlement_url",
        "entitlement_health_url",
        "commerce_webhook_url",
        "commerce_enabled",
        "reconciliation_schedule",
    ] {
        if let Some(value) = annotations.get(key) {
            public_facts.insert(key.into(), value.clone());
        }
    }
    ParsedDeploymentFacts {
        active_version,
        etag: find_string(current, &["etag"]),
        desired_hash,
        artifact_hash,
        secret_revisions,
        routes,
        public_facts,
    }
}

pub(super) fn parse_secret_bindings(
    value: &Value,
    _revisions: &BTreeMap<String, String>,
) -> BTreeMap<String, ObservedSecretBinding> {
    value
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|secret| secret.get("name").and_then(Value::as_str))
        .map(|name| {
            (
                name.into(),
                ObservedSecretBinding {
                    configured: true,
                    // Cloudflare exposes binding names, never secret values or trustworthy
                    // value revisions. The Host deployment lock remains authoritative here.
                    observed_revision: None,
                },
            )
        })
        .collect()
}

pub(super) fn find_string(value: &Value, keys: &[&str]) -> Option<String> {
    keys.iter()
        .find_map(|key| value.get(*key).and_then(Value::as_str).map(str::to_owned))
}

pub(super) fn check_plan_concurrency(
    plan: &DeploymentPlan,
    observed: &ObservedDeploymentState,
) -> DevkitResult<()> {
    let control = plan.control();
    if control
        .expected_remote_version
        .as_deref()
        .is_some_and(|version| observed.remote_version.as_deref() != Some(version))
        || control
            .expected_remote_etag
            .as_deref()
            .is_some_and(|etag| observed.remote_etag.as_deref() != Some(etag))
    {
        return Err(DevkitError::new(
            DevkitErrorCode::ConcurrentModification,
            "Cloudflare deployment changed after the plan was created",
        ));
    }
    if observed.remote_version != plan.observed_before().remote_version
        || observed.remote_etag != plan.observed_before().remote_etag
    {
        return Err(DevkitError::new(
            DevkitErrorCode::ConcurrentModification,
            "Cloudflare deployment no longer matches the plan observation",
        ));
    }
    Ok(())
}

pub(super) async fn workers_dev_gateway_url<T, R>(
    rest: &CloudflareRestClient<T, R>,
    authorization: &DeveloperAuthorization,
    target: &DeploymentTarget,
) -> DevkitResult<String>
where
    T: CloudflareTransport,
    R: SensitiveInputResolver,
{
    let result = rest
        .get_json(
            Some(authorization),
            &format!("accounts/{}/workers/subdomain", target.account_id),
        )
        .await?;
    let subdomain = result
        .value
        .get("subdomain")
        .and_then(Value::as_str)
        .ok_or_else(|| {
            DevkitError::new(
                DevkitErrorCode::RemoteProtocol,
                "Cloudflare account omitted its workers.dev subdomain",
            )
        })?;
    validate_cloudflare_segment("workers.dev subdomain", subdomain)?;
    Ok(format!(
        "https://{}.{}.workers.dev",
        target.resource_name, subdomain
    ))
}

pub(super) async fn enable_workers_dev<T, R>(
    rest: &CloudflareRestClient<T, R>,
    authorization: &DeveloperAuthorization,
    target: &DeploymentTarget,
) -> DevkitResult<()>
where
    T: CloudflareTransport,
    R: SensitiveInputResolver,
{
    match rest
        .execute_json(
            Some(authorization),
            CloudflareHttpMethod::Post,
            &worker_script_path(target, "subdomain"),
            Some(&json!({"enabled": true, "previews_enabled": false})),
        )
        .await
    {
        Ok(_) => {}
        Err(error) if error.remote_mutation_risk == RemoteMutationRisk::Possible => {
            if inspect_workers_dev(rest, authorization, target).await? {
                return Ok(());
            }
            return Err(error);
        }
        Err(error) => return Err(error),
    }
    if inspect_workers_dev(rest, authorization, target).await? {
        Ok(())
    } else {
        Err(DevkitError::new(
            DevkitErrorCode::VerificationFailed,
            "Cloudflare Worker is not enabled on its production workers.dev subdomain",
        ))
    }
}

pub(super) async fn inspect_workers_dev<T, R>(
    rest: &CloudflareRestClient<T, R>,
    authorization: &DeveloperAuthorization,
    target: &DeploymentTarget,
) -> DevkitResult<bool>
where
    T: CloudflareTransport,
    R: SensitiveInputResolver,
{
    let value = rest
        .get_json(
            Some(authorization),
            &worker_script_path(target, "subdomain"),
        )
        .await?
        .value;
    let enabled = value.get("enabled").and_then(Value::as_bool);
    let previews_enabled = value.get("previews_enabled").and_then(Value::as_bool);
    match (enabled, previews_enabled) {
        (Some(enabled), Some(previews_enabled)) => Ok(enabled && !previews_enabled),
        _ => Err(DevkitError::new(
            DevkitErrorCode::RemoteProtocol,
            "Cloudflare Worker subdomain state is invalid",
        )),
    }
}

pub(super) async fn ensure_reconciliation_schedule<T, R>(
    rest: &CloudflareRestClient<T, R>,
    authorization: &DeveloperAuthorization,
    target: &DeploymentTarget,
) -> DevkitResult<()>
where
    T: CloudflareTransport,
    R: SensitiveInputResolver,
{
    if inspect_reconciliation_schedule(rest, authorization, target).await? {
        return Ok(());
    }
    rest.execute_json(
        Some(authorization),
        CloudflareHttpMethod::Post,
        &worker_script_path(target, "schedules"),
        Some(&json!({"cron": "0 */6 * * *"})),
    )
    .await?;
    if inspect_reconciliation_schedule(rest, authorization, target).await? {
        Ok(())
    } else {
        Err(DevkitError::new(
            DevkitErrorCode::VerificationFailed,
            "Cloudflare reconciliation schedule did not converge",
        ))
    }
}

pub(super) async fn inspect_reconciliation_schedule<T, R>(
    rest: &CloudflareRestClient<T, R>,
    authorization: &DeveloperAuthorization,
    target: &DeploymentTarget,
) -> DevkitResult<bool>
where
    T: CloudflareTransport,
    R: SensitiveInputResolver,
{
    let value = rest
        .get_json(
            Some(authorization),
            &worker_script_path(target, "schedules"),
        )
        .await?
        .value;
    let schedules = value.as_array().ok_or_else(|| {
        DevkitError::new(
            DevkitErrorCode::RemoteProtocol,
            "Cloudflare Worker schedules have an invalid shape",
        )
    })?;
    Ok(schedules
        .iter()
        .any(|schedule| schedule.get("cron").and_then(Value::as_str) == Some("0 */6 * * *")))
}

pub(super) fn destroy_d1_database_id(plan: &DestroyPlan) -> DevkitResult<Option<&str>> {
    let ids = plan
        .resources()
        .iter()
        .filter_map(|resource| resource.strip_prefix("d1-database:"))
        .collect::<Vec<_>>();
    match ids.as_slice() {
        [] => Ok(None),
        [id] => {
            validate_cloudflare_segment("D1 database id", id)?;
            Ok(Some(id))
        }
        _ => Err(DevkitError::new(
            DevkitErrorCode::PlanIntegrityFailed,
            "destroy plan contains multiple managed D1 databases",
        )),
    }
}

pub(super) async fn delete_worker_script<T, R>(
    rest: &CloudflareRestClient<T, R>,
    authorization: &DeveloperAuthorization,
    target: &DeploymentTarget,
) -> DevkitResult<()>
where
    T: CloudflareTransport,
    R: SensitiveInputResolver,
{
    match rest
        .execute_json(
            Some(authorization),
            CloudflareHttpMethod::Delete,
            &worker_script_path(target, ""),
            None,
        )
        .await
    {
        Ok(_) => {}
        Err(error) if error.code == DevkitErrorCode::NotFound => return Ok(()),
        Err(error) if error.remote_mutation_risk == RemoteMutationRisk::Possible => {
            return match rest
                .get_json(
                    Some(authorization),
                    &worker_script_path(target, "deployments"),
                )
                .await
            {
                Err(observation) if observation.code == DevkitErrorCode::NotFound => Ok(()),
                Ok(_) => Err(error),
                Err(observation) => Err(observation),
            };
        }
        Err(error) => return Err(error),
    }
    match rest
        .get_json(
            Some(authorization),
            &worker_script_path(target, "deployments"),
        )
        .await
    {
        Err(error) if error.code == DevkitErrorCode::NotFound => Ok(()),
        Ok(_) => Err(DevkitError::new(
            DevkitErrorCode::VerificationFailed,
            "Cloudflare Worker still exists after deletion",
        )),
        Err(error) => Err(error),
    }
}

pub(super) fn worker_multipart(
    plan: &DeploymentPlan,
    resources: &PreparedWorkerResources,
    worker_url: &str,
    create: bool,
) -> DevkitResult<(Vec<u8>, String)> {
    let boundary = format!("agentweave-{}", plan.control().operation_id.simple());
    let idempotency_key_hash =
        hex::encode(Sha256::digest(plan.control().idempotency_key.as_bytes()));
    let secret_revisions = plan
        .desired()
        .secret_bindings()
        .iter()
        .map(|(name, secret)| (name.clone(), Value::String(secret.revision.clone())))
        .collect::<serde_json::Map<_, _>>();
    let (main_module, configuration_binding, configuration_key) = match resources.role {
        ManagedWorkerRole::Gateway => ("gateway.mjs", "GATEWAY_CONFIG_JSON", "gateway_config"),
        ManagedWorkerRole::EntitlementPolicy => (
            "entitlement.mjs",
            "ENTITLEMENT_CONFIG_JSON",
            "entitlement_config",
        ),
    };
    let configuration = plan
        .desired()
        .public_configuration()
        .get(configuration_key)
        .ok_or_else(|| DevkitError::invalid_configuration("Worker configuration is missing"))?;
    let configuration = serde_json::to_string(configuration).map_err(|_| {
        DevkitError::invalid_configuration("Worker configuration could not be encoded")
    })?;
    let mut bindings = vec![
        json!({"type": "plain_text", "name": configuration_binding, "text": configuration}),
        json!({"type": "version_metadata", "name": "CF_VERSION_METADATA"}),
    ];
    if let Some(database) = &resources.database {
        bindings.push(json!({
            "type": "d1",
            "name": match resources.role {
                ManagedWorkerRole::Gateway => D1_BINDING_NAME,
                ManagedWorkerRole::EntitlementPolicy => COMMERCE_D1_BINDING_NAME,
            },
            "database_id": database.id,
        }));
    }
    if resources.role == ManagedWorkerRole::Gateway {
        let rate_limits = rate_limit_bindings(&plan.desired().target().deployment_id);
        bindings.extend([
            json!({"type": "durable_object_namespace", "name": "CONCURRENCY", "class_name": "ConcurrencyLimiter"}),
            json!({"type": "ratelimit", "name": "GATEWAY_EDGE_RATE_LIMITER", "namespace_id": rate_limits[0], "simple": {"limit": 120, "period": 60}}),
            json!({"type": "ratelimit", "name": "GATEWAY_DEPLOYMENT_RATE_LIMITER", "namespace_id": rate_limits[1], "simple": {"limit": 1000, "period": 60}}),
            json!({"type": "ratelimit", "name": "GATEWAY_TENANT_RATE_LIMITER", "namespace_id": rate_limits[2], "simple": {"limit": 300, "period": 60}}),
            json!({"type": "ratelimit", "name": "GATEWAY_RATE_LIMITER", "namespace_id": rate_limits[3], "simple": {"limit": 60, "period": 60}}),
            json!({"type": "ratelimit", "name": "GATEWAY_DEVICE_RATE_LIMITER", "namespace_id": rate_limits[4], "simple": {"limit": 30, "period": 60}}),
        ]);
    }
    let mut annotations = json!({
        "agentweave_desired_hash": plan.desired().state_hash(),
        "agentweave_artifact_hash": plan.desired().artifact().sha256(),
        "agentweave_template_version": plan.desired().template_version(),
        "agentweave_operation_id": plan.control().operation_id.to_string(),
        "agentweave_idempotency_key_hash": idempotency_key_hash,
        "agentweave_secret_revisions": secret_revisions,
        "worker_role": resources.role.as_str(),
        "worker_url": worker_url,
        "deployment_id": plan.desired().target().deployment_id.clone(),
        "commerce_enabled": resources.commerce_enabled,
    });
    if let (Some(database), Some(migration_hash)) = (&resources.database, &resources.migration_hash)
    {
        annotations["d1_database_id"] = json!(database.id);
        annotations["d1_database_name"] = json!(database.name);
        annotations["d1_migration_hash"] = json!(migration_hash);
    }
    match resources.role {
        ManagedWorkerRole::Gateway => {
            annotations["gateway_url"] = json!(worker_url);
            annotations["gateway_health_url"] = json!(format!(
                "{worker_url}/.well-known/agentweave/gateway-health"
            ));
            annotations["gateway_protocol_version"] = json!("2");
        }
        ManagedWorkerRole::EntitlementPolicy => {
            annotations["entitlement_url"] = json!(worker_url);
            annotations["entitlement_health_url"] = json!(format!("{worker_url}/healthz"));
            annotations["commerce_webhook_url"] = json!(format!(
                "{worker_url}/agentweave/commerce/v1/webhooks/creem"
            ));
            if resources.commerce_enabled {
                annotations["reconciliation_schedule"] = json!("0 */6 * * *");
            }
        }
    }
    let mut metadata = json!({
        "main_module": main_module,
        "keep_bindings": ["secret_text"],
        "bindings": bindings,
        "annotations": annotations,
    });
    if create && resources.role == ManagedWorkerRole::Gateway {
        metadata["migrations"] = json!({
            "new_tag": "v1",
            "new_sqlite_classes": ["ConcurrencyLimiter"]
        });
    }
    let metadata = serde_json::to_vec(&metadata).map_err(|_| {
        DevkitError::new(
            DevkitErrorCode::Internal,
            "Cloudflare Worker metadata could not be encoded",
        )
    })?;
    let mut body = Vec::new();
    body.extend_from_slice(format!("--{boundary}\r\n").as_bytes());
    body.extend_from_slice(b"Content-Disposition: form-data; name=\"metadata\"\r\n");
    body.extend_from_slice(b"Content-Type: application/json\r\n\r\n");
    body.extend_from_slice(&metadata);
    body.extend_from_slice(format!("\r\n--{boundary}\r\n").as_bytes());
    body.extend_from_slice(
        format!(
            "Content-Disposition: form-data; name=\"{main_module}\"; filename=\"{main_module}\"\r\n"
        )
        .as_bytes(),
    );
    body.extend_from_slice(
        format!(
            "Content-Type: {}\r\n\r\n",
            plan.desired().artifact().media_type()
        )
        .as_bytes(),
    );
    body.extend_from_slice(plan.desired().artifact().bytes());
    body.extend_from_slice(format!("\r\n--{boundary}--\r\n").as_bytes());
    Ok((body, boundary))
}

fn rate_limit_bindings(deployment_id: &str) -> [String; 5] {
    std::array::from_fn(|index| {
        let mut digest = Sha256::new();
        digest.update(b"agentweave.cloudflare.ratelimit.v1\0");
        digest.update(deployment_id.as_bytes());
        digest.update([index as u8]);
        let bytes = digest.finalize();
        let mut value = u32::from_be_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]);
        if value == 0 {
            value = (index as u32) + 1;
        }
        value.to_string()
    })
}

pub(super) fn ensure_control_matches(
    control: &MutationControl,
    observed: &ObservedDeploymentState,
) -> DevkitResult<()> {
    if control
        .expected_remote_version
        .as_deref()
        .is_some_and(|version| observed.remote_version.as_deref() != Some(version))
        || control
            .expected_remote_etag
            .as_deref()
            .is_some_and(|etag| observed.remote_etag.as_deref() != Some(etag))
    {
        return Err(DevkitError::new(
            DevkitErrorCode::ConcurrentModification,
            "Cloudflare deployment does not match the operation concurrency guard",
        ));
    }
    Ok(())
}
