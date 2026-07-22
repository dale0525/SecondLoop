use super::accounts::parse_cloudflare_accounts;
use super::configuration::parse_cloudflare_configuration;
use super::managed_worker::{self, ManagedWorkerRole, PreparedWorkerResources};
use super::provider_support::{
    check_plan_concurrency, delete_worker_script, destroy_d1_database_id, empty_observation,
    enable_workers_dev, ensure_control_matches, ensure_provider_authorization,
    ensure_reconciliation_schedule, find_string, parse_deployment_facts, parse_secret_bindings,
    validate_cloudflare_segment, worker_multipart, worker_script_path, workers_dev_gateway_url,
};
use super::schema::{cloudflare_capability_requirements, cloudflare_gateway_provider_descriptor};
use super::{
    CLOUDFLARE_PROVIDER_ID, CloudflareAuthorizationUrlInput, CloudflareHttpMethod,
    CloudflareOAuthClient, CloudflareRestClient, CloudflareTokenExchangeInput, CloudflareTransport,
    RequestBodySensitivity,
};
use crate::{
    ApplyOutcome, ApplyReceipt, AuthorizationCapabilityRequirement, AuthorizationRequirements,
    BeginProviderAuthorizationRequest, CompleteProviderAuthorizationRequest, DeploymentPlan,
    DeploymentTarget, DesiredDeploymentState, DestroyPlan, DestroyReceipt, DeveloperAccount,
    DeveloperAuthorization, DevkitError, DevkitErrorCode, DevkitResult, DriftStatus,
    GatewayDeploymentProvider, GatewayTestReceipt, MutationControl, ObservationReachability,
    ObservedDeploymentState, PlanOperation, PlanOperationKind, ProviderAuthorizationPlan,
    ProviderConfiguration, ProviderDescriptor, RollbackReceipt, RollbackRequest,
    SecretRotationReceipt, SecretRotationRequest, SensitiveInputHandle, SensitiveInputStore,
};
use async_trait::async_trait;
use serde_json::{Value, json};
use std::collections::{BTreeMap, BTreeSet};
use std::sync::Arc;

pub const CAPABILITY_WORKERS_SCRIPTS_READ: &str = "workers-scripts-read";
pub const CAPABILITY_WORKERS_SCRIPTS_WRITE: &str = "workers-scripts-write";
pub const CAPABILITY_ACCOUNT_SETTINGS_READ: &str = "account-settings-read";
pub const CAPABILITY_USER_DETAILS_READ: &str = "user-details-read";
pub const CAPABILITY_D1_READ: &str = "d1-read";
pub const CAPABILITY_D1_WRITE: &str = "d1-write";

pub struct CloudflareGatewayProvider<T, S> {
    descriptor: ProviderDescriptor,
    rest: CloudflareRestClient<T, S>,
    oauth: CloudflareOAuthClient<T, S>,
    capability_requirements: Vec<AuthorizationCapabilityRequirement>,
}

impl<T, S> CloudflareGatewayProvider<T, S>
where
    T: CloudflareTransport,
    S: SensitiveInputStore,
{
    pub fn new(transport: Arc<T>, store: Arc<S>) -> DevkitResult<Self> {
        let rest = CloudflareRestClient::new(Arc::clone(&transport), Arc::clone(&store))?;
        let oauth = CloudflareOAuthClient::new(rest.clone(), transport, store)?;
        Self::from_clients(rest, oauth)
    }

    pub fn with_endpoints(
        api_base: &str,
        authorization_endpoint: &str,
        token_endpoint: &str,
        transport: Arc<T>,
        store: Arc<S>,
    ) -> DevkitResult<Self> {
        let rest = CloudflareRestClient::with_api_base(
            api_base,
            Arc::clone(&transport),
            Arc::clone(&store),
        )?;
        let oauth = CloudflareOAuthClient::with_endpoints(
            rest.clone(),
            authorization_endpoint,
            token_endpoint,
            transport,
            store,
        )?;
        Self::from_clients(rest, oauth)
    }

    fn from_clients(
        rest: CloudflareRestClient<T, S>,
        oauth: CloudflareOAuthClient<T, S>,
    ) -> DevkitResult<Self> {
        let descriptor = cloudflare_gateway_provider_descriptor()?;
        descriptor.validate()?;
        Ok(Self {
            descriptor,
            rest,
            oauth,
            capability_requirements: cloudflare_capability_requirements(),
        })
    }

    fn requirements_for(
        &self,
        catalog: &super::CloudflareOAuthScopeCatalog,
        capabilities: &BTreeSet<String>,
    ) -> DevkitResult<AuthorizationRequirements> {
        catalog.resolve(
            CLOUDFLARE_PROVIDER_ID,
            &self.capability_requirements,
            capabilities,
        )
    }

    async fn inspect_inner(
        &self,
        authorization: &DeveloperAuthorization,
        target: &DeploymentTarget,
        now_unix_ms: u64,
    ) -> DevkitResult<ObservedDeploymentState> {
        let deployment = match self
            .rest
            .get_json(
                Some(authorization),
                &worker_script_path(target, "deployments"),
            )
            .await
        {
            Ok(result) => result,
            Err(error) if error.code == DevkitErrorCode::NotFound => {
                return Ok(empty_observation(
                    target,
                    ObservationReachability::Missing,
                    now_unix_ms,
                ));
            }
            Err(error) if error.code == DevkitErrorCode::PermissionInsufficient => {
                return Ok(empty_observation(
                    target,
                    ObservationReachability::Unauthorized,
                    now_unix_ms,
                ));
            }
            Err(error)
                if matches!(
                    error.code,
                    DevkitErrorCode::Unavailable | DevkitErrorCode::Timeout
                ) =>
            {
                return Ok(empty_observation(
                    target,
                    ObservationReachability::Unreachable,
                    now_unix_ms,
                ));
            }
            Err(error) => return Err(error),
        };
        let facts = parse_deployment_facts(&deployment.value);
        let secrets = match self
            .rest
            .get_json(Some(authorization), &worker_script_path(target, "secrets"))
            .await
        {
            Ok(result) => parse_secret_bindings(&result.value, &facts.secret_revisions),
            Err(error) if error.code == DevkitErrorCode::NotFound => BTreeMap::new(),
            Err(error) => return Err(error),
        };
        Ok(ObservedDeploymentState {
            target: target.clone(),
            reachability: ObservationReachability::Reachable,
            remote_version: facts.active_version,
            remote_etag: deployment.etag.or(facts.etag),
            observed_desired_hash: facts.desired_hash,
            active_artifact_hash: facts.artifact_hash,
            secret_bindings: secrets,
            managed_routes: facts.routes,
            resource_facts: facts.public_facts,
            observed_at_unix_ms: now_unix_ms,
        })
    }

    async fn upload_version(
        &self,
        authorization: &DeveloperAuthorization,
        plan: &DeploymentPlan,
        resources: &PreparedWorkerResources,
        worker_url: &str,
        create: bool,
    ) -> DevkitResult<Option<String>> {
        let (body, boundary) = worker_multipart(plan, resources, worker_url, create)?;
        let path = if create {
            worker_script_path(plan.desired().target(), "")
        } else {
            worker_script_path(plan.desired().target(), "versions")
        };
        let result = self
            .rest
            .execute_bytes(
                Some(authorization),
                if create {
                    CloudflareHttpMethod::Put
                } else {
                    CloudflareHttpMethod::Post
                },
                &path,
                body,
                RequestBodySensitivity::Public,
                Some(&format!("multipart/form-data; boundary={boundary}")),
            )
            .await?;
        let version = find_string(&result.value, &["id", "version_id"]);
        if !create && version.is_none() {
            return Err(DevkitError::new(
                DevkitErrorCode::RemoteProtocol,
                "Cloudflare version upload response omitted the Worker version id",
            ));
        }
        Ok(version)
    }

    async fn configure_planned_secrets(
        &self,
        authorization: &DeveloperAuthorization,
        plan: &DeploymentPlan,
    ) -> DevkitResult<()> {
        for operation in plan
            .operations()
            .iter()
            .filter(|operation| operation.kind == PlanOperationKind::ConfigureSecret)
        {
            let secret = plan
                .desired()
                .secret_bindings()
                .get(&operation.resource)
                .ok_or_else(|| {
                    DevkitError::new(
                        DevkitErrorCode::PlanIntegrityFailed,
                        "deployment plan references an unknown secret binding",
                    )
                })?;
            self.rest
                .put_secret(
                    authorization,
                    &worker_script_path(plan.desired().target(), "secrets"),
                    &operation.resource,
                    &secret.value_handle,
                )
                .await?;
        }
        Ok(())
    }

    async fn activate_version(
        &self,
        authorization: &DeveloperAuthorization,
        target: &DeploymentTarget,
        remote_version: &str,
        desired_hash: &str,
        operation_id: &str,
    ) -> DevkitResult<()> {
        self.rest
            .execute_json(
                Some(authorization),
                CloudflareHttpMethod::Post,
                &worker_script_path(target, "deployments"),
                Some(&json!({
                    "strategy": "percentage",
                    "versions": [{"version_id": remote_version, "percentage": 100}],
                    "annotations": {
                        "agentweave_desired_hash": desired_hash,
                        "agentweave_operation_id": operation_id,
                    }
                })),
            )
            .await?;
        Ok(())
    }

    async fn recovered_receipt(
        &self,
        authorization: &DeveloperAuthorization,
        plan: &DeploymentPlan,
        previous_remote_version: Option<String>,
        now_unix_ms: u64,
    ) -> DevkitResult<Option<ApplyReceipt>> {
        let role = managed_worker::role_from_desired(plan.desired())?;
        let commerce_enabled = managed_worker::validate_desired(plan.desired())?;
        let observed = self
            .inspect_full_expected(
                authorization,
                plan.desired().target(),
                now_unix_ms,
                Some((role, commerce_enabled)),
            )
            .await?;
        if crate::assess_drift(plan.desired(), &observed).status == DriftStatus::InSync
            && managed_worker::resources_in_sync(&observed, role, commerce_enabled)
        {
            return Ok(Some(ApplyReceipt {
                target: plan.desired().target().clone(),
                plan_hash: plan.hash().clone(),
                operation_id: plan.control().operation_id,
                idempotency_key: plan.control().idempotency_key.clone(),
                outcome: ApplyOutcome::RecoveredAfterUncertainWrite,
                previous_remote_version,
                active_remote_version: observed.remote_version.ok_or_else(|| {
                    DevkitError::new(
                        DevkitErrorCode::VerificationFailed,
                        "recovered Cloudflare deployment omitted its active version",
                    )
                })?,
                remote_etag: observed.remote_etag,
                completed_at_unix_ms: now_unix_ms,
            }));
        }
        Ok(None)
    }

    async fn inspect_full(
        &self,
        authorization: &DeveloperAuthorization,
        target: &DeploymentTarget,
        now_unix_ms: u64,
    ) -> DevkitResult<ObservedDeploymentState> {
        self.inspect_full_expected(authorization, target, now_unix_ms, None)
            .await
    }

    async fn inspect_full_expected(
        &self,
        authorization: &DeveloperAuthorization,
        target: &DeploymentTarget,
        now_unix_ms: u64,
        expected: Option<(ManagedWorkerRole, bool)>,
    ) -> DevkitResult<ObservedDeploymentState> {
        let mut observed = self
            .inspect_inner(authorization, target, now_unix_ms)
            .await?;
        if matches!(
            observed.reachability,
            ObservationReachability::Unauthorized | ObservationReachability::Unreachable
        ) {
            return Ok(observed);
        }
        managed_worker::enrich_observation(
            &self.rest,
            authorization,
            target,
            &mut observed,
            expected,
        )
        .await?;
        Ok(observed)
    }
}

#[async_trait]
impl<T, S> GatewayDeploymentProvider for CloudflareGatewayProvider<T, S>
where
    T: CloudflareTransport,
    S: SensitiveInputStore,
{
    fn describe(&self) -> &ProviderDescriptor {
        &self.descriptor
    }

    async fn authorization_requirements(
        &self,
        configuration: &ProviderConfiguration,
        requested_capabilities: &BTreeSet<String>,
    ) -> DevkitResult<AuthorizationRequirements> {
        let configuration = parse_cloudflare_configuration(&self.descriptor, configuration)?;
        self.requirements_for(&configuration.scope_catalog, requested_capabilities)
    }

    async fn begin_provider_authorization(
        &self,
        request: BeginProviderAuthorizationRequest,
    ) -> DevkitResult<ProviderAuthorizationPlan> {
        let configuration =
            parse_cloudflare_configuration(&self.descriptor, &request.configuration)?;
        if request.redirect_uri != configuration.oauth_redirect_uri {
            return Err(DevkitError::invalid_configuration(
                "OAuth request redirect URI differs from the configured callback",
            ));
        }
        let requirements = self.requirements_for(
            &configuration.scope_catalog,
            &request.requested_capabilities,
        )?;
        let requested_scope_ids = requirements.all_scope_ids();
        let authorization_url = self
            .oauth
            .authorization_url(CloudflareAuthorizationUrlInput {
                client_id: &configuration.oauth_client_id,
                redirect_uri: &request.redirect_uri,
                pkce_s256_challenge: &request.pkce_s256_challenge,
                state_handle: &request.state_handle,
                scope_ids: &requested_scope_ids,
            })
            .await?;
        Ok(ProviderAuthorizationPlan {
            provider_id: CLOUDFLARE_PROVIDER_ID.into(),
            authorization_url,
            requested_scope_ids,
            catalog_revision: configuration.scope_catalog.revision,
            expires_at_unix_ms: request.expires_at_unix_ms,
        })
    }

    async fn complete_provider_authorization(
        &self,
        request: CompleteProviderAuthorizationRequest,
    ) -> DevkitResult<DeveloperAuthorization> {
        let configuration =
            parse_cloudflare_configuration(&self.descriptor, &request.configuration)?;
        if request.redirect_uri != configuration.oauth_redirect_uri {
            return Err(DevkitError::invalid_configuration(
                "OAuth callback differs from the configured callback",
            ));
        }
        if configuration.scope_catalog.revision != request.expected_catalog_revision {
            return Err(DevkitError::new(
                DevkitErrorCode::ConcurrentModification,
                "Cloudflare OAuth scope catalog changed during authorization",
            ));
        }
        let logical_capabilities = self
            .capability_requirements
            .iter()
            .filter_map(|requirement| {
                let requested = BTreeSet::from([requirement.capability.clone()]);
                self.requirements_for(&configuration.scope_catalog, &requested)
                    .ok()
                    .filter(|resolved| {
                        resolved
                            .all_scope_ids()
                            .is_subset(&request.expected_scope_ids)
                    })
                    .map(|_| requirement.capability.clone())
            })
            .collect::<BTreeSet<_>>();
        let grant = self
            .oauth
            .exchange_code(CloudflareTokenExchangeInput {
                client_id: &configuration.oauth_client_id,
                redirect_uri: &request.redirect_uri,
                code_handle: &request.code_handle,
                pkce_verifier_handle: &request.pkce_verifier_handle,
                expected_scope_ids: &request.expected_scope_ids,
                now_unix_ms: request.now_unix_ms,
            })
            .await?;
        let authorization = DeveloperAuthorization::new_unbound(
            CLOUDFLARE_PROVIDER_ID,
            request.actor_id,
            grant.access_token_handle.clone(),
            grant.refresh_token_handle.clone(),
            grant.granted_scope_ids.clone(),
            logical_capabilities.clone(),
            &configuration.scope_catalog.revision,
            request.now_unix_ms,
            grant.expires_at_unix_ms,
        )?;
        let live_catalog = self.oauth.scope_catalog(&authorization).await?;
        let live_requirements = self.requirements_for(&live_catalog, &logical_capabilities)?;
        if live_requirements.all_scope_ids() != request.expected_scope_ids {
            return Err(DevkitError::new(
                DevkitErrorCode::ConcurrentModification,
                "Cloudflare OAuth scope IDs changed after authorization",
            ));
        }
        DeveloperAuthorization::new_unbound(
            CLOUDFLARE_PROVIDER_ID,
            authorization.actor_id(),
            grant.access_token_handle,
            grant.refresh_token_handle,
            grant.granted_scope_ids,
            logical_capabilities,
            live_catalog.revision,
            request.now_unix_ms,
            grant.expires_at_unix_ms,
        )
    }

    async fn list_authorization_accounts(
        &self,
        authorization: &DeveloperAuthorization,
        now_unix_ms: u64,
    ) -> DevkitResult<Vec<DeveloperAccount>> {
        authorization.ensure_provider_usable(
            CLOUDFLARE_PROVIDER_ID,
            &BTreeSet::from([CAPABILITY_ACCOUNT_SETTINGS_READ.into()]),
            now_unix_ms,
        )?;
        let result = self.rest.get_json(Some(authorization), "accounts").await?;
        parse_cloudflare_accounts(&result.value)
    }

    async fn bind_authorization_account(
        &self,
        authorization: &DeveloperAuthorization,
        account_id: &str,
        now_unix_ms: u64,
    ) -> DevkitResult<DeveloperAuthorization> {
        validate_cloudflare_segment("account id", account_id)?;
        let accounts = self
            .list_authorization_accounts(authorization, now_unix_ms)
            .await?;
        if !accounts
            .iter()
            .any(|account| account.account_id == account_id)
        {
            return Err(DevkitError::new(
                DevkitErrorCode::InvalidAuthorization,
                "selected Cloudflare account is not visible to this authorization",
            ));
        }
        authorization.bind_account(account_id)
    }

    async fn plan(
        &self,
        authorization: &DeveloperAuthorization,
        desired: DesiredDeploymentState,
        control: MutationControl,
        now_unix_ms: u64,
    ) -> DevkitResult<DeploymentPlan> {
        ensure_provider_authorization(authorization, desired.target(), false, now_unix_ms)?;
        control.validate(now_unix_ms)?;
        let role = managed_worker::role_from_desired(&desired)?;
        let commerce_enabled = managed_worker::validate_desired(&desired)?;
        if !desired.managed_routes().is_empty() {
            return Err(DevkitError::new(
                DevkitErrorCode::Unsupported,
                "Cloudflare route management requires an explicit zone-scoped extension",
            ));
        }
        let observed = self
            .inspect_full_expected(
                authorization,
                desired.target(),
                now_unix_ms,
                Some((role, commerce_enabled)),
            )
            .await?;
        if observed.reachability == ObservationReachability::Unauthorized {
            return Err(DevkitError::new(
                DevkitErrorCode::PermissionInsufficient,
                "Cloudflare deployment cannot be inspected with the current authorization",
            ));
        }
        if observed.reachability == ObservationReachability::Unreachable {
            return Err(DevkitError::new(
                DevkitErrorCode::Unavailable,
                "Cloudflare deployment cannot be inspected before planning",
            ));
        }
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
                "Cloudflare deployment does not match the requested concurrency guard",
            ));
        }
        let drift = crate::assess_drift(&desired, &observed);
        let resources_in_sync =
            managed_worker::resources_in_sync(&observed, role, commerce_enabled);
        let database_name = managed_worker::database_name(role, commerce_enabled, desired.target());
        let mut operations = Vec::new();
        if database_name.is_some()
            && observed
                .resource_facts
                .get("observed_d1_missing")
                .and_then(Value::as_bool)
                == Some(true)
        {
            operations.push(PlanOperation {
                kind: PlanOperationKind::CreateDatabase,
                resource: database_name.clone().expect("checked database name"),
                destructive: false,
            });
        }
        if !resources_in_sync {
            if let Some(database_name) = database_name {
                operations.push(PlanOperation {
                    kind: PlanOperationKind::ApplyDatabaseMigration,
                    resource: database_name,
                    destructive: false,
                });
            }
            if role == ManagedWorkerRole::Gateway {
                operations.push(PlanOperation {
                    kind: PlanOperationKind::SeedEntitlements,
                    resource: desired.target().deployment_id.clone(),
                    destructive: false,
                });
            }
            operations.push(PlanOperation {
                kind: PlanOperationKind::ConfigureBindings,
                resource: desired.target().resource_name.clone(),
                destructive: false,
            });
            if role == ManagedWorkerRole::EntitlementPolicy && commerce_enabled {
                operations.push(PlanOperation {
                    kind: PlanOperationKind::ConfigureScheduledTrigger,
                    resource: "commerce-reconciliation".into(),
                    destructive: false,
                });
            }
        }
        match drift.status {
            DriftStatus::InSync => {}
            DriftStatus::Missing => operations.push(PlanOperation {
                kind: PlanOperationKind::CreateScript,
                resource: desired.target().resource_name.clone(),
                destructive: false,
            }),
            DriftStatus::Drifted => {}
            DriftStatus::Unauthorized | DriftStatus::Unreachable => {
                return Err(DevkitError::new(
                    DevkitErrorCode::Unavailable,
                    "Cloudflare deployment cannot be safely planned",
                ));
            }
        }
        if drift.status != DriftStatus::InSync || !resources_in_sync {
            operations.extend(
                desired
                    .secret_bindings()
                    .keys()
                    .filter(|name| {
                        !observed
                            .secret_bindings
                            .get(*name)
                            .is_some_and(|binding| binding.configured)
                    })
                    .map(|name| PlanOperation {
                        kind: PlanOperationKind::ConfigureSecret,
                        resource: name.clone(),
                        destructive: false,
                    }),
            );
            if drift.status == DriftStatus::Drifted
                || (drift.status == DriftStatus::InSync && !resources_in_sync)
            {
                operations.push(PlanOperation {
                    kind: PlanOperationKind::UploadVersion,
                    resource: desired.target().resource_name.clone(),
                    destructive: false,
                });
                operations.push(PlanOperation {
                    kind: PlanOperationKind::ActivateVersion,
                    resource: desired.target().resource_name.clone(),
                    destructive: false,
                });
            }
            operations.push(PlanOperation {
                kind: PlanOperationKind::EnablePublicEndpoint,
                resource: desired.target().resource_name.clone(),
                destructive: false,
            });
            operations.push(PlanOperation {
                kind: PlanOperationKind::Verify,
                resource: desired.target().resource_name.clone(),
                destructive: false,
            });
        }
        DeploymentPlan::build(desired, observed, operations, control, now_unix_ms)
    }

    async fn apply(
        &self,
        authorization: &DeveloperAuthorization,
        plan: &DeploymentPlan,
        now_unix_ms: u64,
    ) -> DevkitResult<ApplyReceipt> {
        plan.verify_integrity()?;
        plan.control().validate(now_unix_ms)?;
        ensure_provider_authorization(authorization, plan.desired().target(), true, now_unix_ms)?;
        let role = managed_worker::role_from_desired(plan.desired())?;
        let commerce_enabled = managed_worker::validate_desired(plan.desired())?;
        let before = self
            .inspect_full_expected(
                authorization,
                plan.desired().target(),
                now_unix_ms,
                Some((role, commerce_enabled)),
            )
            .await?;
        if crate::assess_drift(plan.desired(), &before).status == DriftStatus::InSync
            && managed_worker::resources_in_sync(&before, role, commerce_enabled)
        {
            return Ok(ApplyReceipt {
                target: plan.desired().target().clone(),
                plan_hash: plan.hash().clone(),
                operation_id: plan.control().operation_id,
                idempotency_key: plan.control().idempotency_key.clone(),
                outcome: ApplyOutcome::AlreadyConverged,
                previous_remote_version: before.remote_version.clone(),
                active_remote_version: before.remote_version.ok_or_else(|| {
                    DevkitError::new(
                        DevkitErrorCode::VerificationFailed,
                        "converged Cloudflare deployment omitted its active version",
                    )
                })?,
                remote_etag: before.remote_etag,
                completed_at_unix_ms: now_unix_ms,
            });
        }
        check_plan_concurrency(plan, &before)?;
        let previous_remote_version = before.remote_version.clone();
        let create = before.reachability == ObservationReachability::Missing;
        let resources =
            managed_worker::ensure_resources(&self.rest, authorization, plan.desired()).await?;
        let worker_url =
            workers_dev_gateway_url(&self.rest, authorization, plan.desired().target()).await?;
        if !create {
            self.configure_planned_secrets(authorization, plan).await?;
        }
        let uploaded_version = match self
            .upload_version(authorization, plan, &resources, &worker_url, create)
            .await
        {
            Ok(version) => version,
            Err(error) if error.remote_mutation_risk == crate::RemoteMutationRisk::Possible => {
                if let Some(receipt) = self
                    .recovered_receipt(
                        authorization,
                        plan,
                        previous_remote_version.clone(),
                        now_unix_ms,
                    )
                    .await?
                {
                    return Ok(receipt);
                }
                return Err(error);
            }
            Err(error) => return Err(error),
        };
        if create {
            self.configure_planned_secrets(authorization, plan).await?;
        }
        if !create {
            let remote_version = uploaded_version.as_deref().ok_or_else(|| {
                DevkitError::new(
                    DevkitErrorCode::RemoteProtocol,
                    "Cloudflare version upload omitted the Worker version id",
                )
            })?;
            self.activate_version(
                authorization,
                plan.desired().target(),
                remote_version,
                plan.desired().state_hash(),
                &plan.control().operation_id.to_string(),
            )
            .await?;
        }
        enable_workers_dev(&self.rest, authorization, plan.desired().target()).await?;
        if role == ManagedWorkerRole::EntitlementPolicy && commerce_enabled {
            ensure_reconciliation_schedule(&self.rest, authorization, plan.desired().target())
                .await?;
        }
        let after = self
            .inspect_full_expected(
                authorization,
                plan.desired().target(),
                now_unix_ms,
                Some((role, commerce_enabled)),
            )
            .await?;
        if crate::assess_drift(plan.desired(), &after).status != DriftStatus::InSync
            || !managed_worker::resources_in_sync(&after, role, commerce_enabled)
        {
            return Err(DevkitError::new(
                DevkitErrorCode::VerificationFailed,
                "Cloudflare deployment did not converge to the planned state",
            ));
        }
        Ok(ApplyReceipt {
            target: plan.desired().target().clone(),
            plan_hash: plan.hash().clone(),
            operation_id: plan.control().operation_id,
            idempotency_key: plan.control().idempotency_key.clone(),
            outcome: ApplyOutcome::Applied,
            previous_remote_version,
            active_remote_version: after.remote_version.or(uploaded_version).ok_or_else(|| {
                DevkitError::new(
                    DevkitErrorCode::VerificationFailed,
                    "Cloudflare deployment omitted its active Worker version",
                )
            })?,
            remote_etag: after.remote_etag,
            completed_at_unix_ms: now_unix_ms,
        })
    }

    async fn inspect(
        &self,
        authorization: &DeveloperAuthorization,
        target: &DeploymentTarget,
        now_unix_ms: u64,
    ) -> DevkitResult<ObservedDeploymentState> {
        ensure_provider_authorization(authorization, target, false, now_unix_ms)?;
        self.inspect_full(authorization, target, now_unix_ms).await
    }

    async fn resolve_public_endpoint(
        &self,
        authorization: &DeveloperAuthorization,
        target: &DeploymentTarget,
        now_unix_ms: u64,
    ) -> DevkitResult<String> {
        ensure_provider_authorization(authorization, target, false, now_unix_ms)?;
        workers_dev_gateway_url(&self.rest, authorization, target).await
    }

    async fn test(
        &self,
        authorization: &DeveloperAuthorization,
        target: &DeploymentTarget,
        one_time_identity: &SensitiveInputHandle,
        now_unix_ms: u64,
    ) -> DevkitResult<GatewayTestReceipt> {
        let observed = self.inspect(authorization, target, now_unix_ms).await?;
        managed_worker::test_managed_worker(
            &self.rest,
            &observed,
            target,
            one_time_identity,
            now_unix_ms,
        )
        .await
    }

    async fn rotate_secret(
        &self,
        authorization: &DeveloperAuthorization,
        request: SecretRotationRequest,
        now_unix_ms: u64,
    ) -> DevkitResult<SecretRotationReceipt> {
        request.control.validate(now_unix_ms)?;
        ensure_provider_authorization(authorization, &request.target, true, now_unix_ms)?;
        let observed = self
            .inspect_inner(authorization, &request.target, now_unix_ms)
            .await?;
        ensure_control_matches(&request.control, &observed)?;
        self.rest
            .put_secret(
                authorization,
                &worker_script_path(&request.target, "secrets"),
                &request.binding_name,
                &request.new_value_handle,
            )
            .await?;
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
        authorization: &DeveloperAuthorization,
        request: RollbackRequest,
        now_unix_ms: u64,
    ) -> DevkitResult<RollbackReceipt> {
        request.control.validate(now_unix_ms)?;
        ensure_provider_authorization(authorization, &request.target, true, now_unix_ms)?;
        validate_cloudflare_segment("Worker version id", &request.restore_remote_version)?;
        let before = self
            .inspect_inner(authorization, &request.target, now_unix_ms)
            .await?;
        ensure_control_matches(&request.control, &before)?;
        let previous = before.remote_version.ok_or_else(|| {
            DevkitError::new(
                DevkitErrorCode::NotFound,
                "Cloudflare Worker has no active version to roll back",
            )
        })?;
        self.activate_version(
            authorization,
            &request.target,
            &request.restore_remote_version,
            &format!("rollback:{}", request.restore_remote_version),
            &request.control.operation_id.to_string(),
        )
        .await?;
        let boundary = managed_worker::worker_code_rollback_boundary();
        Ok(RollbackReceipt {
            target: request.target,
            operation_id: request.control.operation_id,
            previous_remote_version: previous,
            active_remote_version: request.restore_remote_version,
            boundary,
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
        ensure_provider_authorization(authorization, target, false, now_unix_ms)?;
        let observed = self
            .inspect_full(authorization, target, now_unix_ms)
            .await?;
        let mut resources = BTreeSet::from([format!("worker-script:{}", target.resource_name)]);
        resources.extend(
            observed
                .secret_bindings
                .keys()
                .map(|name| format!("secret:{name}")),
        );
        if let Some(database_id) = observed
            .resource_facts
            .get("observed_d1_database_id")
            .and_then(Value::as_str)
        {
            resources.insert(format!("d1-database:{database_id}"));
        }
        if observed
            .resource_facts
            .get("observed_reconciliation_schedule_in_sync")
            .and_then(Value::as_bool)
            == Some(true)
        {
            resources.insert("scheduled-trigger:commerce-reconciliation".into());
        }
        DestroyPlan::build(target.clone(), observed, resources, control, now_unix_ms)
    }

    async fn destroy(
        &self,
        authorization: &DeveloperAuthorization,
        plan: &DestroyPlan,
        now_unix_ms: u64,
    ) -> DevkitResult<DestroyReceipt> {
        plan.verify_integrity()?;
        plan.control().validate(now_unix_ms)?;
        ensure_provider_authorization(authorization, plan.target(), true, now_unix_ms)?;
        let observed = self
            .inspect_full(authorization, plan.target(), now_unix_ms)
            .await?;
        if observed.remote_version.is_some()
            && (observed.remote_version != plan.observed_before().remote_version
                || observed.remote_etag != plan.observed_before().remote_etag)
        {
            return Err(DevkitError::new(
                DevkitErrorCode::ConcurrentModification,
                "Cloudflare Worker changed after the destroy plan was created",
            ));
        }
        let planned_database_id = destroy_d1_database_id(plan)?;
        let role = managed_worker::role_from_observation(&observed);
        let observed_database_id = observed
            .resource_facts
            .get("observed_d1_database_id")
            .and_then(Value::as_str);
        if planned_database_id.is_none() && observed_database_id.is_some() {
            return Err(DevkitError::new(
                DevkitErrorCode::ConcurrentModification,
                "a managed Cloudflare D1 database appeared after the destroy plan was created",
            ));
        }
        delete_worker_script(&self.rest, authorization, plan.target()).await?;
        if let Some(database_id) = planned_database_id {
            managed_worker::delete_database(
                &self.rest,
                authorization,
                plan.target(),
                role,
                database_id,
            )
            .await?;
        }
        Ok(DestroyReceipt {
            target: plan.target().clone(),
            plan_hash: plan.hash().clone(),
            operation_id: plan.control().operation_id,
            deleted_resources: plan.resources().clone(),
            completed_at_unix_ms: now_unix_ms,
        })
    }
}
