use crate::developer_control_plane::{
    CachedBundlePlan, CachedPlan, DeveloperControlPlane, now_unix_ms,
};
use crate::developer_control_plane_deployment::{
    DeploymentReferenceInput, DeploymentSecretInput, ensure_account, public_fact_string,
    reference_from_target, validate_environment, validate_gateway_configuration,
};
use agent_devkit::{
    DeploymentArtifact, DeploymentBundleOutcome, DeploymentBundlePlan,
    DeploymentBundleResourceReceipt, DeploymentBundleResourceStatus, DeploymentResourceKind,
    DeploymentResourceOwnership, DeploymentResourcePurpose, DeploymentResourceSpec,
    DesiredDeploymentBundle, DesiredDeploymentState, DesiredSecretBinding, DevkitError,
    DevkitErrorCode, DevkitResult, DriftReport, GatewayTestReceipt, MutationControl,
    ObservedDeploymentState, PlanOperation, SensitiveInputStore, apply_deployment_bundle,
    assess_drift,
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::collections::{BTreeMap, BTreeSet};
use uuid::Uuid;

const ENTITLEMENT_POLICY_RESOURCE_ID: &str = "entitlement-policy";
const MODEL_GATEWAY_RESOURCE_ID: &str = "model-gateway";
const ENTITLEMENT_PROJECTION_SECRET: &str = "ENTITLEMENT_PROJECTION_SECRET";
const COMMERCE_SUBJECT_BINDING_SECRET: &str = "COMMERCE_SUBJECT_BINDING_SECRET";

#[derive(Debug)]
pub struct AccessBundlePlanInput {
    pub account_id: String,
    pub deployment_id: String,
    pub environment: Option<String>,
    pub gateway_worker_name: String,
    pub entitlement_worker_name: String,
    pub gateway_config: Value,
    pub entitlement_bootstrap: Value,
    pub entitlement_config: Value,
    pub secrets: BTreeMap<String, DeploymentSecretInput>,
    pub idempotency_key: Option<String>,
    pub expected_resources: BTreeMap<String, ExpectedResourceVersion>,
}

#[derive(Clone, Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ExpectedResourceVersion {
    pub remote_version: Option<String>,
    pub remote_etag: Option<String>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AccessBundleResourcePlanSummary {
    pub resource_id: String,
    pub kind: DeploymentResourceKind,
    pub purpose: DeploymentResourcePurpose,
    pub dependencies: BTreeSet<String>,
    pub ownership: DeploymentResourceOwnership,
    pub target: DeploymentReferenceInput,
    pub operations: Vec<PlanOperation>,
    pub drift: Option<DriftReport>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AccessBundlePlanSummary {
    pub schema_version: u32,
    pub bundle_id: String,
    pub desired_hash: String,
    pub plan_hash: String,
    pub resources: Vec<AccessBundleResourcePlanSummary>,
    pub expires_at_unix_ms: u64,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AccessBundleResourceApplyReceipt {
    pub resource_id: String,
    pub status: DeploymentBundleResourceStatus,
    pub target: DeploymentReferenceInput,
    pub version_id: Option<String>,
    pub previous_version_id: Option<String>,
    pub endpoint: Option<String>,
    pub error_code: Option<DevkitErrorCode>,
    pub safe_message: Option<String>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AccessBundleApplyReceipt {
    pub schema_version: u32,
    pub provider_id: String,
    pub provider_version: String,
    pub bundle_id: String,
    pub plan_hash: String,
    pub operation_id: Uuid,
    pub outcome: DeploymentBundleOutcome,
    pub resources: BTreeMap<String, AccessBundleResourceApplyReceipt>,
    pub completed_at_unix_ms: u64,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AccessBundleTestInput {
    pub gateway: DeploymentReferenceInput,
    pub entitlement_policy: DeploymentReferenceInput,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AccessBundleCommerceVerification {
    pub database_id: String,
    pub migration_hash: String,
    pub capabilities: BTreeSet<String>,
    pub webhook_verified_at_unix_ms: Option<u64>,
    pub portal_verified_at_unix_ms: Option<u64>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AccessBundleTestReceipt {
    pub gateway: crate::developer_control_plane_deployment::DeploymentTestReceipt,
    pub entitlement_policy: crate::developer_control_plane_deployment::DeploymentTestReceipt,
    pub commerce: Option<AccessBundleCommerceVerification>,
    pub projection_secret_revision: String,
    pub tested_at_unix_ms: u64,
}

impl DeveloperControlPlane {
    pub async fn plan_access_bundle(
        &self,
        mut input: AccessBundlePlanInput,
    ) -> DevkitResult<AccessBundlePlanSummary> {
        let _mutation = self.mutation.lock().await;
        let authorization = self.require_authorization(true).await?;
        ensure_account(&authorization, &input.account_id)?;
        validate_environment(input.environment.as_deref())?;
        if input.gateway_worker_name == input.entitlement_worker_name {
            return Err(DevkitError::invalid_configuration(
                "gateway and entitlement Worker names must differ",
            ));
        }
        let gateway_target = self.target(
            input.account_id.clone(),
            input.deployment_id.clone(),
            input.gateway_worker_name.clone(),
        )?;
        let entitlement_target = self.target(
            input.account_id.clone(),
            input.deployment_id.clone(),
            input.entitlement_worker_name.clone(),
        )?;
        let entitlement_requirements = validate_entitlement_configuration(
            &input.entitlement_config,
            &self.app_id,
            &entitlement_target,
            input.environment.as_deref(),
        )?;
        let entitlement_endpoint = self
            .provider
            .resolve_public_endpoint(&authorization, &entitlement_target, now_unix_ms())
            .await?;
        set_gateway_entitlement_endpoint(&mut input.gateway_config, &entitlement_endpoint)?;
        let gateway_requirements = validate_gateway_configuration(
            &input.gateway_config,
            &gateway_target,
            input.environment.as_deref(),
        )?;
        let required_bindings = gateway_requirements
            .union(&entitlement_requirements.required_bindings)
            .cloned()
            .collect::<BTreeSet<_>>();
        let stored = self
            .resolve_bundle_secrets(
                &required_bindings,
                &entitlement_requirements.auto_bindings,
                input.secrets,
            )
            .await?;
        let gateway_secret_bindings = select_secret_bindings(&stored, &gateway_requirements)?;
        let entitlement_secret_bindings =
            select_secret_bindings(&stored, &entitlement_requirements.required_bindings)?;
        let gateway_template = self.gateway_template().ok_or_else(|| {
            DevkitError::new(
                DevkitErrorCode::Unavailable,
                "trusted Cloudflare gateway template is unavailable",
            )
        })?;
        let entitlement_template = self.entitlement_template().ok_or_else(|| {
            DevkitError::new(
                DevkitErrorCode::Unavailable,
                "trusted Cloudflare entitlement template is unavailable",
            )
        })?;
        let gateway_desired = DesiredDeploymentState::new(
            gateway_target.clone(),
            gateway_template.version(),
            DeploymentArtifact::new(
                "application/javascript+module",
                gateway_template.bytes().to_vec(),
            )?,
            BTreeMap::from([
                ("worker_role".into(), json!("model_gateway")),
                ("gateway_config".into(), input.gateway_config),
                ("entitlement_bootstrap".into(), input.entitlement_bootstrap),
            ]),
            gateway_secret_bindings,
            BTreeSet::new(),
        )?;
        let entitlement_desired = DesiredDeploymentState::new(
            entitlement_target.clone(),
            entitlement_template.version(),
            DeploymentArtifact::new(
                "application/javascript+module",
                entitlement_template.bytes().to_vec(),
            )?,
            BTreeMap::from([
                ("worker_role".into(), json!("entitlement_policy")),
                ("entitlement_config".into(), input.entitlement_config),
            ]),
            entitlement_secret_bindings,
            BTreeSet::new(),
        )?;
        let bundle_id = bundle_id(&input.deployment_id, input.environment.as_deref());
        let desired_bundle = DesiredDeploymentBundle::new(
            bundle_id,
            access_resource_graph(
                &gateway_desired,
                &entitlement_desired,
                &gateway_requirements,
                &entitlement_requirements,
            ),
        )?;
        let bundle_control = self
            .acquire_lease(
                input.idempotency_key.unwrap_or_else(bundle_idempotency_key),
                None,
                None,
            )
            .await?;
        let entitlement_plan = self
            .provider
            .plan(
                &authorization,
                entitlement_desired,
                child_control(
                    &bundle_control,
                    ENTITLEMENT_POLICY_RESOURCE_ID,
                    input.expected_resources.get(ENTITLEMENT_POLICY_RESOURCE_ID),
                ),
                now_unix_ms(),
            )
            .await;
        let entitlement_plan = match entitlement_plan {
            Ok(plan) => plan,
            Err(error) => {
                let _ = self.release_lease(&bundle_control.lease).await;
                return Err(error);
            }
        };
        let gateway_plan = self
            .provider
            .plan(
                &authorization,
                gateway_desired,
                child_control(
                    &bundle_control,
                    MODEL_GATEWAY_RESOURCE_ID,
                    input.expected_resources.get(MODEL_GATEWAY_RESOURCE_ID),
                ),
                now_unix_ms(),
            )
            .await;
        let gateway_plan = match gateway_plan {
            Ok(plan) => plan,
            Err(error) => {
                let _ = self.release_lease(&bundle_control.lease).await;
                return Err(error);
            }
        };
        let plans = BTreeMap::from([
            (ENTITLEMENT_POLICY_RESOURCE_ID.into(), entitlement_plan),
            (MODEL_GATEWAY_RESOURCE_ID.into(), gateway_plan),
        ]);
        let plan = DeploymentBundlePlan::build(
            desired_bundle,
            plans,
            bundle_control.clone(),
            now_unix_ms(),
        )?;
        let expires_at_unix_ms = Self::plan_expiry().min(bundle_control.lease.expires_at_unix_ms);
        let summary = bundle_plan_summary(&plan, input.environment.clone(), expires_at_unix_ms);
        self.cache_plan(
            summary.plan_hash.clone(),
            CachedPlan::Bundle(Box::new(CachedBundlePlan {
                plan,
                environment: input.environment,
                expires_at_unix_ms,
            })),
        )
        .await;
        Ok(summary)
    }

    pub async fn apply_access_bundle(
        &self,
        plan_hash: &str,
    ) -> DevkitResult<AccessBundleApplyReceipt> {
        let _mutation = self.mutation.lock().await;
        let cached = self.bundle_plan(plan_hash).await?;
        let authorization = self.require_authorization(true).await?;
        let first = cached
            .plan
            .desired()
            .resources()
            .values()
            .next()
            .ok_or_else(|| DevkitError::new(DevkitErrorCode::InvalidPlan, "bundle is empty"))?;
        ensure_account(&authorization, &first.target.account_id)?;
        let receipt = apply_deployment_bundle(
            self.provider.as_ref(),
            &authorization,
            &cached.plan,
            now_unix_ms(),
        )
        .await?;
        let mut resources = BTreeMap::new();
        for (resource_id, resource_receipt) in &receipt.resources {
            let spec = &cached.plan.desired().resources()[resource_id];
            let endpoint = if spec.kind == DeploymentResourceKind::Worker
                && matches!(
                    resource_receipt.status,
                    DeploymentBundleResourceStatus::Applied
                        | DeploymentBundleResourceStatus::AlreadyConverged
                ) {
                let observed = self
                    .provider
                    .inspect(&authorization, &spec.target, now_unix_ms())
                    .await?;
                match spec.purpose {
                    DeploymentResourcePurpose::ModelGateway => {
                        public_fact_string(&observed, "gateway_url")
                    }
                    DeploymentResourcePurpose::EntitlementPolicy => {
                        public_fact_string(&observed, "entitlement_url")
                    }
                    _ => None,
                }
            } else {
                None
            };
            resources.insert(
                resource_id.clone(),
                public_resource_receipt(
                    resource_receipt,
                    &spec.target,
                    cached.environment.clone(),
                    endpoint,
                ),
            );
        }
        if receipt.outcome == DeploymentBundleOutcome::Succeeded {
            self.cached_plans.lock().await.remove(plan_hash);
            self.release_lease(&cached.plan.control().lease).await?;
        }
        Ok(AccessBundleApplyReceipt {
            schema_version: receipt.schema_version,
            provider_id: self.provider.describe().provider_id.clone(),
            provider_version: self.provider.describe().provider_version.to_string(),
            bundle_id: receipt.bundle_id,
            plan_hash: receipt.plan_hash.as_str().into(),
            operation_id: receipt.operation_id,
            outcome: receipt.outcome,
            resources,
            completed_at_unix_ms: receipt.completed_at_unix_ms,
        })
    }

    pub async fn test_access_bundle(
        &self,
        input: AccessBundleTestInput,
        identity_header: &str,
        identity_token: Vec<u8>,
    ) -> DevkitResult<AccessBundleTestReceipt> {
        if !matches!(identity_header, "authorization" | "cf-access-jwt-assertion") {
            return Err(DevkitError::invalid_configuration(
                "access bundle test identity header is unsupported",
            ));
        }
        if input.gateway.account_id != input.entitlement_policy.account_id
            || input.gateway.deployment_id != input.entitlement_policy.deployment_id
            || input.gateway.environment != input.entitlement_policy.environment
            || input.gateway.worker_name == input.entitlement_policy.worker_name
        {
            return Err(DevkitError::invalid_configuration(
                "access bundle test targets do not form one deployment",
            ));
        }
        let authorization = self.require_authorization(true).await?;
        ensure_account(&authorization, &input.gateway.account_id)?;
        let gateway_target = self.target(
            input.gateway.account_id.clone(),
            input.gateway.deployment_id.clone(),
            input.gateway.worker_name.clone(),
        )?;
        let entitlement_target = self.target(
            input.entitlement_policy.account_id.clone(),
            input.entitlement_policy.deployment_id.clone(),
            input.entitlement_policy.worker_name.clone(),
        )?;
        let document = serde_json::to_vec(&json!({
            "schemaVersion": 1,
            "header": identity_header,
            "token": std::str::from_utf8(&identity_token).map_err(|_| {
                DevkitError::invalid_configuration("access bundle test identity is invalid")
            })?,
        }))
        .map_err(|_| {
            DevkitError::invalid_configuration("access bundle test identity is invalid")
        })?;
        let handle = self
            .sensitive
            .store(
                "cloudflare/access-bundle/one-time-identity",
                agent_devkit::SensitiveValue::new(document)?,
            )
            .await?;
        let now = now_unix_ms();
        let entitlement_test = self
            .provider
            .test(&authorization, &entitlement_target, &handle, now)
            .await;
        let gateway_test = match entitlement_test {
            Ok(entitlement_test) => {
                let gateway_test = self
                    .provider
                    .test(&authorization, &gateway_target, &handle, now)
                    .await;
                (entitlement_test, gateway_test)
            }
            Err(error) => {
                let _ = self.sensitive.delete_handle(&handle).await;
                return Err(error);
            }
        };
        let _ = self.sensitive.delete_handle(&handle).await;
        let (entitlement_test, gateway_test) = (gateway_test.0, gateway_test.1?);
        let observed = self
            .provider
            .inspect(&authorization, &entitlement_target, now_unix_ms())
            .await?;
        let commerce = observed
            .resource_facts
            .get("commerce_enabled")
            .and_then(Value::as_bool)
            .filter(|enabled| *enabled)
            .map(|_| commerce_verification(&observed))
            .transpose()?;
        let projection_secret_revision = self
            .sensitive_binding_revisions()
            .await?
            .remove(ENTITLEMENT_PROJECTION_SECRET)
            .ok_or_else(|| {
                DevkitError::new(
                    DevkitErrorCode::SensitiveInputUnavailable,
                    "entitlement projection secret revision is unavailable",
                )
            })?;
        Ok(AccessBundleTestReceipt {
            gateway: test_receipt(gateway_test, input.gateway),
            entitlement_policy: test_receipt(entitlement_test, input.entitlement_policy),
            commerce,
            projection_secret_revision,
            tested_at_unix_ms: now,
        })
    }

    async fn resolve_bundle_secrets(
        &self,
        required: &BTreeSet<String>,
        automatic: &BTreeSet<String>,
        mut supplied: BTreeMap<String, DeploymentSecretInput>,
    ) -> DevkitResult<BTreeMap<String, DesiredSecretBinding>> {
        if supplied.keys().any(|name| !required.contains(name)) {
            return Err(DevkitError::invalid_configuration(
                "access bundle contains an unknown secret input",
            ));
        }
        let revisions = self.sensitive_binding_revisions().await?;
        let mut result = BTreeMap::new();
        for name in required {
            let provided = supplied.remove(name);
            let stored = if automatic.contains(name) {
                match provided {
                    Some(secret) if secret.value.is_some() => {
                        return Err(DevkitError::invalid_configuration(
                            "automatically generated access secrets cannot be supplied by the Renderer",
                        ));
                    }
                    Some(secret) => {
                        self.resolve_sensitive_binding(name, &secret.revision, None)
                            .await?
                    }
                    None if revisions.contains_key(name) => {
                        self.resolve_sensitive_binding(name, &revisions[name], None)
                            .await?
                    }
                    None => {
                        let revision = format!("auto-{}", Uuid::new_v4());
                        self.resolve_sensitive_binding(name, &revision, Some(random_secret_bytes()))
                            .await?
                    }
                }
            } else {
                let secret = provided.ok_or_else(|| {
                    DevkitError::new(
                        DevkitErrorCode::SensitiveInputUnavailable,
                        format!("sensitive binding requires a value or stored revision: {name}"),
                    )
                })?;
                self.resolve_sensitive_binding(name, &secret.revision, secret.value)
                    .await?
            };
            result.insert(
                name.clone(),
                DesiredSecretBinding {
                    value_handle: stored.handle,
                    revision: stored.revision,
                },
            );
        }
        Ok(result)
    }

    async fn bundle_plan(&self, hash: &str) -> DevkitResult<CachedBundlePlan> {
        let plan = self.cached_plans.lock().await.get(hash).cloned();
        match plan {
            Some(CachedPlan::Bundle(plan)) if plan.expires_at_unix_ms > now_unix_ms() => {
                plan.plan.verify_integrity()?;
                Ok(*plan)
            }
            Some(_) => Err(DevkitError::new(
                DevkitErrorCode::InvalidPlan,
                "access bundle plan is expired or has the wrong operation type",
            )),
            None => Err(DevkitError::new(
                DevkitErrorCode::NotFound,
                "access bundle plan is unavailable; create a new plan",
            )),
        }
    }
}

#[derive(Debug)]
struct EntitlementRequirements {
    required_bindings: BTreeSet<String>,
    auto_bindings: BTreeSet<String>,
    commerce_enabled: bool,
}

fn validate_entitlement_configuration(
    configuration: &Value,
    app_id: &str,
    target: &agent_devkit::DeploymentTarget,
    environment: Option<&str>,
) -> DevkitResult<EntitlementRequirements> {
    let root = configuration.as_object().ok_or_else(|| {
        DevkitError::invalid_configuration("entitlement configuration must be an object")
    })?;
    if root.get("schemaVersion").and_then(Value::as_u64) != Some(1)
        || root.get("appId").and_then(Value::as_str) != Some(app_id)
        || root.get("deploymentId").and_then(Value::as_str) != Some(target.deployment_id.as_str())
        || root.get("environment").and_then(Value::as_str)
            != Some(environment.unwrap_or("production"))
    {
        return Err(DevkitError::invalid_configuration(
            "entitlement configuration does not match the access deployment",
        ));
    }
    let policy = root
        .get("policy")
        .and_then(Value::as_object)
        .ok_or_else(|| DevkitError::invalid_configuration("entitlement policy is missing"))?;
    let source_mode = policy
        .get("sourceMode")
        .and_then(Value::as_str)
        .ok_or_else(|| {
            DevkitError::invalid_configuration("entitlement policy source is missing")
        })?;
    let mut required_bindings = BTreeSet::from([ENTITLEMENT_PROJECTION_SECRET.into()]);
    let mut auto_bindings = required_bindings.clone();
    match source_mode {
        "uniform_bounded" => Ok(EntitlementRequirements {
            required_bindings,
            auto_bindings,
            commerce_enabled: false,
        }),
        "commerce_provider" => {
            if root
                .get("commerce")
                .and_then(Value::as_object)
                .and_then(|commerce| commerce.get("providerId"))
                .and_then(Value::as_str)
                != Some(commerce_creem::CREEM_PROVIDER_ID)
            {
                return Err(DevkitError::invalid_configuration(
                    "managed Commerce provider is invalid",
                ));
            }
            for name in [
                "CREEM_API_KEY",
                "CREEM_WEBHOOK_SECRET",
                COMMERCE_SUBJECT_BINDING_SECRET,
            ] {
                required_bindings.insert(name.into());
            }
            auto_bindings.insert(COMMERCE_SUBJECT_BINDING_SECRET.into());
            Ok(EntitlementRequirements {
                required_bindings,
                auto_bindings,
                commerce_enabled: true,
            })
        }
        _ => Err(DevkitError::invalid_configuration(
            "entitlement policy source is unsupported",
        )),
    }
}

fn set_gateway_entitlement_endpoint(configuration: &mut Value, endpoint: &str) -> DevkitResult<()> {
    let projection = configuration
        .as_object_mut()
        .and_then(|root| root.get_mut("entitlements"))
        .and_then(Value::as_object_mut)
        .and_then(|entitlements| entitlements.get_mut("projection"))
        .and_then(Value::as_object_mut)
        .ok_or_else(|| {
            DevkitError::invalid_configuration("gateway signed entitlement projection is missing")
        })?;
    let mut url = url::Url::parse(endpoint)
        .map_err(|_| DevkitError::invalid_configuration("entitlement endpoint is invalid"))?;
    if url.scheme() != "https" || url.username() != "" || url.password().is_some() {
        return Err(DevkitError::invalid_configuration(
            "entitlement endpoint must be credential-free HTTPS",
        ));
    }
    url.set_path(entitlement_providers::GATEWAY_PROJECTION_PATH);
    url.set_query(None);
    url.set_fragment(None);
    projection.insert("schemaVersion".into(), json!(2));
    projection.insert(
        "sourceId".into(),
        json!(entitlement_providers::CLOUDFLARE_POLICY_ENTITLEMENT_PROVIDER_ID),
    );
    projection.insert("url".into(), json!(url.as_str()));
    Ok(())
}

fn select_secret_bindings(
    stored: &BTreeMap<String, DesiredSecretBinding>,
    names: &BTreeSet<String>,
) -> DevkitResult<BTreeMap<String, DesiredSecretBinding>> {
    names
        .iter()
        .map(|name| {
            stored
                .get(name)
                .cloned()
                .map(|binding| (name.clone(), binding))
                .ok_or_else(|| {
                    DevkitError::new(DevkitErrorCode::Internal, "secret map is incomplete")
                })
        })
        .collect()
}

fn commerce_verification(
    observed: &ObservedDeploymentState,
) -> DevkitResult<AccessBundleCommerceVerification> {
    let database_id = public_fact_string(observed, "observed_d1_database_id").ok_or_else(|| {
        DevkitError::new(
            DevkitErrorCode::DriftDetected,
            "Commerce projection database is unavailable",
        )
    })?;
    let migration_hash = public_fact_string(observed, "d1_migration_hash").ok_or_else(|| {
        DevkitError::new(
            DevkitErrorCode::DriftDetected,
            "Commerce projection migration metadata is unavailable",
        )
    })?;
    if observed
        .resource_facts
        .get("observed_d1_migration_status")
        .and_then(Value::as_str)
        != Some("in_sync")
    {
        return Err(DevkitError::new(
            DevkitErrorCode::DriftDetected,
            "Commerce projection database migrations are not in sync",
        ));
    }
    Ok(AccessBundleCommerceVerification {
        database_id,
        migration_hash,
        capabilities: commerce_runtime::REQUIRED_SUBSCRIPTION_CAPABILITIES
            .into_iter()
            .map(str::to_owned)
            .collect(),
        webhook_verified_at_unix_ms: verification_timestamp(
            observed,
            "commerce_webhook_verified_at",
        )?,
        portal_verified_at_unix_ms: verification_timestamp(
            observed,
            "commerce_portal_verified_at",
        )?,
    })
}

fn verification_timestamp(
    observed: &ObservedDeploymentState,
    key: &str,
) -> DevkitResult<Option<u64>> {
    match observed.resource_facts.get(key) {
        None | Some(Value::Null) => Ok(None),
        Some(value) => value.as_u64().map(Some).ok_or_else(|| {
            DevkitError::new(
                DevkitErrorCode::RemoteProtocol,
                "Commerce verification timestamp is invalid",
            )
        }),
    }
}

fn test_receipt(
    receipt: GatewayTestReceipt,
    reference: DeploymentReferenceInput,
) -> crate::developer_control_plane_deployment::DeploymentTestReceipt {
    crate::developer_control_plane_deployment::DeploymentTestReceipt {
        target: reference,
        protocol_version: receipt.protocol_version,
        remote_version: receipt.remote_version,
        tested_at_unix_ms: receipt.tested_at_unix_ms,
    }
}

fn access_resource_graph(
    gateway: &DesiredDeploymentState,
    entitlement: &DesiredDeploymentState,
    gateway_secrets: &BTreeSet<String>,
    entitlement_requirements: &EntitlementRequirements,
) -> Vec<DeploymentResourceSpec> {
    let gateway_target = gateway.target().clone();
    let entitlement_target = entitlement.target().clone();
    let mut resources = vec![
        worker_resource(
            ENTITLEMENT_POLICY_RESOURCE_ID,
            DeploymentResourcePurpose::EntitlementPolicy,
            entitlement.clone(),
            BTreeSet::new(),
        ),
        worker_resource(
            MODEL_GATEWAY_RESOURCE_ID,
            DeploymentResourcePurpose::ModelGateway,
            gateway.clone(),
            BTreeSet::from([ENTITLEMENT_POLICY_RESOURCE_ID.into()]),
        ),
        controlled_resource(
            "gateway-ledger",
            DeploymentResourceKind::D1Database,
            DeploymentResourcePurpose::GatewayLedger,
            gateway_target.clone(),
            MODEL_GATEWAY_RESOURCE_ID,
            true,
        ),
        controlled_resource(
            "gateway-concurrency",
            DeploymentResourceKind::DurableObjectNamespace,
            DeploymentResourcePurpose::ConcurrencyControl,
            gateway_target.clone(),
            MODEL_GATEWAY_RESOURCE_ID,
            false,
        ),
        controlled_resource(
            "gateway-rate-limits",
            DeploymentResourceKind::RateLimiter,
            DeploymentResourcePurpose::EdgeRateLimit,
            gateway_target.clone(),
            MODEL_GATEWAY_RESOURCE_ID,
            false,
        ),
    ];
    if entitlement_requirements.commerce_enabled {
        resources.extend([
            controlled_resource(
                "commerce-projection",
                DeploymentResourceKind::D1Database,
                DeploymentResourcePurpose::CommerceProjection,
                entitlement_target.clone(),
                ENTITLEMENT_POLICY_RESOURCE_ID,
                true,
            ),
            controlled_resource(
                "commerce-reconciliation",
                DeploymentResourceKind::ScheduledTrigger,
                DeploymentResourcePurpose::Reconciliation,
                entitlement_target.clone(),
                ENTITLEMENT_POLICY_RESOURCE_ID,
                false,
            ),
        ]);
    }
    for (controller, target, names) in [
        (MODEL_GATEWAY_RESOURCE_ID, gateway_target, gateway_secrets),
        (
            ENTITLEMENT_POLICY_RESOURCE_ID,
            entitlement_target,
            &entitlement_requirements.required_bindings,
        ),
    ] {
        for name in names {
            resources.push(controlled_resource(
                &format!("secret:{controller}:{}", name.to_ascii_lowercase()),
                DeploymentResourceKind::SecretBinding,
                DeploymentResourcePurpose::Secret,
                target.clone(),
                controller,
                false,
            ));
        }
    }
    resources
}

fn worker_resource(
    id: &str,
    purpose: DeploymentResourcePurpose,
    desired: DesiredDeploymentState,
    dependencies: BTreeSet<String>,
) -> DeploymentResourceSpec {
    DeploymentResourceSpec {
        resource_id: id.into(),
        kind: DeploymentResourceKind::Worker,
        purpose,
        target: desired.target().clone(),
        dependencies,
        ownership: DeploymentResourceOwnership::Exclusive,
        controller_resource_id: None,
        independently_rollbackable: true,
        delete_requires_confirmation: false,
        desired: Some(desired),
    }
}

fn controlled_resource(
    id: &str,
    kind: DeploymentResourceKind,
    purpose: DeploymentResourcePurpose,
    target: agent_devkit::DeploymentTarget,
    controller: &str,
    delete_requires_confirmation: bool,
) -> DeploymentResourceSpec {
    DeploymentResourceSpec {
        resource_id: id.into(),
        kind,
        purpose,
        target,
        dependencies: BTreeSet::new(),
        ownership: DeploymentResourceOwnership::Exclusive,
        controller_resource_id: Some(controller.into()),
        independently_rollbackable: false,
        delete_requires_confirmation,
        desired: None,
    }
}

fn child_control(
    parent: &MutationControl,
    resource_id: &str,
    expected: Option<&ExpectedResourceVersion>,
) -> MutationControl {
    MutationControl {
        operation_id: Uuid::new_v4(),
        idempotency_key: format!("{}:{resource_id}", parent.idempotency_key),
        expected_remote_version: expected.and_then(|value| value.remote_version.clone()),
        expected_remote_etag: expected.and_then(|value| value.remote_etag.clone()),
        lease: parent.lease.clone(),
    }
}

fn bundle_plan_summary(
    plan: &DeploymentBundlePlan,
    environment: Option<String>,
    expires_at_unix_ms: u64,
) -> AccessBundlePlanSummary {
    let resources = plan
        .desired()
        .resources()
        .values()
        .map(|resource| {
            let worker_plan = plan.worker_plans().get(&resource.resource_id);
            AccessBundleResourcePlanSummary {
                resource_id: resource.resource_id.clone(),
                kind: resource.kind,
                purpose: resource.purpose,
                dependencies: resource.dependencies.clone(),
                ownership: resource.ownership,
                target: reference_from_target(&resource.target, environment.clone()),
                operations: worker_plan
                    .map(|value| value.operations().to_vec())
                    .unwrap_or_default(),
                drift: worker_plan
                    .map(|value| assess_drift(value.desired(), value.observed_before())),
            }
        })
        .collect();
    AccessBundlePlanSummary {
        schema_version: agent_devkit::DEPLOYMENT_BUNDLE_SCHEMA_VERSION,
        bundle_id: plan.desired().bundle_id().into(),
        desired_hash: plan.desired().desired_hash().into(),
        plan_hash: plan.hash().as_str().into(),
        resources,
        expires_at_unix_ms,
    }
}

fn public_resource_receipt(
    receipt: &DeploymentBundleResourceReceipt,
    target: &agent_devkit::DeploymentTarget,
    environment: Option<String>,
    endpoint: Option<String>,
) -> AccessBundleResourceApplyReceipt {
    AccessBundleResourceApplyReceipt {
        resource_id: receipt.resource_id.clone(),
        status: receipt.status,
        target: reference_from_target(target, environment),
        version_id: receipt
            .apply_receipt
            .as_ref()
            .map(|value| value.active_remote_version.clone()),
        previous_version_id: receipt
            .apply_receipt
            .as_ref()
            .and_then(|value| value.previous_remote_version.clone()),
        endpoint,
        error_code: receipt.error_code,
        safe_message: receipt.safe_message.clone(),
    }
}

fn bundle_id(deployment_id: &str, environment: Option<&str>) -> String {
    format!(
        "access-{deployment_id}-{}",
        environment.unwrap_or("production")
    )
    .to_ascii_lowercase()
    .replace(
        |character: char| !character.is_ascii_alphanumeric() && character != '-',
        "-",
    )
}

fn bundle_idempotency_key() -> String {
    format!("agentweave-access-bundle-{}", Uuid::new_v4())
}

fn random_secret_bytes() -> Vec<u8> {
    let mut bytes = Vec::with_capacity(32);
    bytes.extend_from_slice(Uuid::new_v4().as_bytes());
    bytes.extend_from_slice(Uuid::new_v4().as_bytes());
    bytes
}

#[cfg(test)]
#[path = "developer_control_plane_bundle_tests.rs"]
mod tests;
