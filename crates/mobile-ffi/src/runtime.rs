use crate::runtime_inventory::{
    layer_name, managed_inventory_revision, managed_revision_ids, mobile_layer_status,
    mobile_layered_skill, resolution_status_name,
};
use crate::types::{
    MobileDiagnostics, MobileInitConfig, MobileMessageDto, MobileModelConfigDto, MobileSessionDto,
    MobileSkillDto, MobileTurnDto,
};
use agent_runtime::app_definition::ResolvedAgentApp;
use agent_runtime::app_manifest::{AppNetworkPolicy, ExternalSideEffectPolicy};
use agent_runtime::automation::{
    DeclarativeScheduledRunExecutor, NotificationDeliveryOutcome, NotificationRecord,
    NotificationStore, SchedulerRunner,
};
use agent_runtime::connector::ConnectorRuntime;
use agent_runtime::connector_ledger::SqliteConnectorActionLedger;
use agent_runtime::connector_tools::{ConnectorToolRuntime, EphemeralConnectorContextProvider};
use agent_runtime::credential::{CredentialScope, CredentialVault, InMemorySecretStore};
use agent_runtime::foundation_actions::MailActionService;
use agent_runtime::mail::{MailAccount, MailAddress};
use agent_runtime::mail_connector_transport::MailConnectorTransport;
use agent_runtime::mail_fake::FakeMailConnector;
use agent_runtime::memory::{MemoryProvider, MemoryScope};
use agent_runtime::memory_tools::MemoryToolRuntime;
use agent_runtime::mobile_host::{HttpMobileRuntimeHost, MobileRuntimeInit, SecretResolver};
use agent_runtime::model_config::StoredModelConfig;
use agent_runtime::platform::{CapabilitySet, PlatformId};
use agent_runtime::prompt_composer::AppPromptConfig;
use agent_runtime::scheduler::{ScheduledJob, ScheduledJobRequest, SchedulerStore};
use agent_runtime::session::ConversationScope;
use agent_runtime::skill_bundle::BundleSkillSource;
use agent_runtime::skill_management::{
    CreateSkillDraftRequest, DraftFileUpdate, OwnerSkillManagementService, SkillActionFacts,
    SkillDraftSummary, SkillDraftValidation, SkillPackageStatus, SkillRollbackOutcome,
};
use agent_runtime::skill_manager::{SkillManager, SkillManagerConfig};
use agent_runtime::skill_package::SkillPackageId;
use agent_runtime::skill_policy::{
    ActorContext, SkillManagementMode, SkillManagementPolicy, SkillOperation,
};
use agent_runtime::skill_recovery::RecoveryStatus;
use agent_runtime::skill_source::{
    DirectorySkillSource, ManagedSkillSource, SkillLayer, SkillSource,
};
use agent_runtime::skill_state::{SkillApprovalRecord, SkillSnapshotStatus, SkillStateStore};
use agent_runtime::skill_store::{SkillRevisionStore, SkillStorePaths};
use agent_runtime::storage::Storage;
use agent_runtime::tools::RuntimeConfig;
use anyhow::{Context, Result};
use chrono::{Duration as ChronoDuration, Utc};
use model_gateway::provider::EndpointType;
use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::Duration;
use tokio::runtime::Runtime;
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

#[path = "runtime_support.rs"]
mod support;
use support::*;

#[path = "runtime_policy.rs"]
mod runtime_policy;

pub struct MobileRuntime {
    tokio: Runtime,
    storage: Storage,
    init: MobileRuntimeInit,
    skill_manager: SkillManager,
    skill_management: OwnerSkillManagementService,
    skill_state: SkillStateStore,
    skill_policy: SkillManagementPolicy,
    actor_context: ActorContext,
    runtime_config: RuntimeConfig,
    database_ready: bool,
    skills_ready: bool,
    reload_status: MonotonicReloadStatus,
    model_configured: AtomicBool,
    cancellation: CancellationToken,
    app_prompt: AppPromptConfig,
    conversation_scope: ConversationScope,
    memory_tools: Option<MemoryToolRuntime>,
    connector_tools: Option<ConnectorToolRuntime>,
    mail_actions: Option<MailActionService>,
    scheduler: SchedulerStore,
    notifications: NotificationStore,
}

impl MobileRuntime {
    pub fn initialize(mut config: MobileInitConfig) -> Result<Self> {
        let storage_protection_key =
            decode_storage_protection_key(config.storage_protection_key_hex.take())?;
        let tokio = Runtime::new()?;
        let platform = parse_platform(&config.platform)?;
        let capabilities = CapabilitySet::from_names(config.capabilities.clone());
        let app_data_dir = prepare_private_root(&config.app_data_dir)?;
        let cache_dir = prepare_private_root(&config.cache_dir)?;
        let allowed_roots = [app_data_dir.clone(), cache_dir.clone()];
        let app_package_path = config
            .app_package_dir
            .as_deref()
            .map(|path| {
                resolve_private_path(path, &app_data_dir, &allowed_roots, "App package directory")
            })
            .transpose()?;
        let builtin_skills_path = resolve_private_path(
            &config.builtin_skills_dir,
            &app_data_dir,
            &allowed_roots,
            "built-in skills directory",
        )?;
        let managed_skills_path = resolve_private_path(
            &config.managed_skills_dir,
            &app_data_dir,
            &allowed_roots,
            "managed skills directory",
        )?;
        let staging_skills_path = resolve_private_path(
            &config.staging_skills_dir,
            &cache_dir,
            &allowed_roots,
            "staging skills directory",
        )?;
        let quarantine_skills_path = resolve_private_path(
            &config.quarantine_skills_dir,
            &app_data_dir,
            &allowed_roots,
            "quarantine skills directory",
        )?;
        ensure_distinct_roots(&[
            &builtin_skills_path,
            &managed_skills_path,
            &staging_skills_path,
            &quarantine_skills_path,
        ])?;
        let database_path = resolve_private_path(
            &config.database_path,
            &app_data_dir,
            &allowed_roots,
            "database path",
        )?;
        ensure_database_outside_skill_roots(
            &database_path,
            &[
                &builtin_skills_path,
                &managed_skills_path,
                &staging_skills_path,
                &quarantine_skills_path,
            ],
        )?;
        let storage = open_mobile_storage(&tokio, &database_path, storage_protection_key)?;
        let init = MobileRuntimeInit {
            platform,
            capabilities,
        };
        let state = SkillStateStore::new(storage.clone());
        let store_paths = tokio.block_on(SkillStorePaths::prepare(&app_data_dir, &cache_dir))?;
        ensure_configured_store_root(
            &managed_skills_path,
            &store_paths.managed,
            "managed skills directory",
        )?;
        ensure_configured_store_root(
            &staging_skills_path,
            &store_paths.staging,
            "staging skills directory",
        )?;
        ensure_configured_store_root(
            &quarantine_skills_path,
            &store_paths.quarantine,
            "quarantine skills directory",
        )?;
        let prepared_builtin = builtin_skills_path.canonicalize()?;
        ensure_distinct_roots(&[
            &prepared_builtin,
            &store_paths.managed,
            &store_paths.staging,
            &store_paths.quarantine,
        ])?;
        let revisions = SkillRevisionStore::new(store_paths, state.clone());
        let builtin = tokio.block_on(BundleSkillSource::open(&builtin_skills_path))?;
        let managed = ManagedSkillSource::from_store(revisions.clone());
        let mut sources: Vec<Arc<dyn SkillSource>> = vec![Arc::new(builtin)];
        if let Some(app_package_path) = &app_package_path {
            let packages = app_package_path.join("packages");
            if packages.is_dir() {
                sources.push(Arc::new(DirectorySkillSource::new(
                    SkillLayer::Session,
                    packages,
                )));
            }
        }
        sources.push(Arc::new(managed));
        let skill_manager =
            tokio.block_on(SkillManager::new_deferred_managed(SkillManagerConfig {
                sources,
                platform: init.platform,
                capabilities: init.capabilities.clone(),
                protected_packages: config
                    .skill_policy
                    .protected_packages
                    .iter()
                    .cloned()
                    .collect(),
                allowed_overrides: config
                    .skill_policy
                    .allowed_overrides
                    .iter()
                    .cloned()
                    .collect(),
                runtime_version: env!("CARGO_PKG_VERSION").parse()?,
            }))?;
        let skill_management = OwnerSkillManagementService::new(
            skill_manager.clone(),
            revisions,
            state.clone(),
            config.skill_policy.clone(),
        );
        let recovery = tokio
            .block_on(skill_manager.startup_reconcile())
            .context("managed skill startup reconciliation failed")?;
        let model_configured = tokio.block_on(storage.load_model_config())?.is_some();
        let mut excluded_roots = vec![
            prepared_builtin,
            managed_skills_path,
            staging_skills_path,
            quarantine_skills_path,
            database_path,
        ];
        if let Some(path) = &app_package_path {
            excluded_roots.push(path.clone());
        }
        let runtime_config = RuntimeConfig::workspace_write(&app_data_dir, &app_data_dir)
            .excluding_workspace_roots(excluded_roots);
        let (app_prompt, runtime_config) = if let Some(path) = app_package_path {
            let inventory =
                crate::mobile_app::runtime_inventory(&skill_manager, &init, &runtime_config)?;
            let resolved = tokio.block_on(ResolvedAgentApp::load(&path, &inventory, 64 * 1024))?;
            let runtime_config =
                runtime_config.with_agent_app_policy(resolved.runtime_policy().clone());
            (resolved.prompt, runtime_config)
        } else {
            (AppPromptConfig::default(), runtime_config)
        };
        let conversation_scope = ConversationScope::local(&app_prompt.identity.app_id);
        let memory_tools = tokio.block_on(resolve_mobile_memory(&storage, &app_prompt))?;
        let connector_foundation =
            tokio.block_on(resolve_mobile_mail(&storage, &app_prompt, &runtime_config))?;
        let connector_tools = connector_foundation
            .as_ref()
            .map(|foundation| foundation.0.clone());
        let mail_actions = connector_foundation.as_ref().and_then(|foundation| {
            runtime_config
                .agent_app_policy
                .as_ref()
                .is_none_or(|policy| {
                    policy.external_side_effects() != ExternalSideEffectPolicy::Deny
                })
                .then(|| foundation.1.clone())
        });
        let scheduler = tokio.block_on(SchedulerStore::from_storage(&storage))?;
        let notifications = tokio.block_on(NotificationStore::from_storage(&storage))?;
        Ok(Self {
            tokio,
            storage,
            init,
            skill_manager,
            skill_management,
            skill_state: state,
            skill_policy: config.skill_policy.clone(),
            actor_context: config.actor_context.clone(),
            runtime_config,
            database_ready: true,
            skills_ready: true,
            reload_status: MonotonicReloadStatus::new(
                recovery.generation,
                recovery_status_name(recovery.status),
            ),
            model_configured: AtomicBool::new(model_configured),
            cancellation: CancellationToken::new(),
            app_prompt,
            conversation_scope,
            memory_tools,
            connector_tools,
            mail_actions,
            scheduler,
            notifications,
        })
    }

    pub fn create_scheduled_job(&self, request: ScheduledJobRequest) -> Result<ScheduledJob> {
        self.ensure_background_execution_allowed()?;
        self.tokio
            .block_on(self.scheduler.create_job(request, Utc::now()))
    }

    pub fn run_scheduler_tick(&self, limit: usize) -> Result<usize> {
        self.ensure_background_execution_allowed()?;
        let runner = SchedulerRunner::new(
            self.scheduler.clone(),
            self.notifications.clone(),
            DeclarativeScheduledRunExecutor,
            format!("android:{}", std::process::id()),
            ChronoDuration::seconds(60),
        )?;
        self.tokio.block_on(runner.tick(Utc::now(), limit))
    }

    pub fn claim_notifications(
        &self,
        worker: &str,
        limit: usize,
    ) -> Result<Vec<NotificationRecord>> {
        self.ensure_background_execution_allowed()?;
        self.tokio.block_on(self.notifications.claim_due(
            worker,
            Utc::now(),
            ChronoDuration::seconds(60),
            limit,
        ))
    }

    pub fn finish_notification(
        &self,
        notification_id: &str,
        worker: &str,
        outcome: NotificationDeliveryOutcome,
    ) -> Result<bool> {
        self.ensure_background_execution_allowed()?;
        self.tokio.block_on(
            self.notifications
                .finish(notification_id, worker, outcome, Utc::now()),
        )
    }

    pub fn diagnostics(&self) -> Result<MobileDiagnostics> {
        let snapshot = self.skill_manager.current_snapshot();
        let quarantined_count = self
            .tokio
            .block_on(self.skill_state.count_quarantined_revisions())?;
        Ok(MobileDiagnostics {
            app_id: self.app_prompt.identity.app_id.clone(),
            app_version: self.app_prompt.identity.version.clone(),
            app_display_name: self.app_prompt.identity.display_name.clone(),
            platform: platform_name(self.init.platform).to_string(),
            capabilities: self.init.capabilities.names().to_vec(),
            database_ready: self.database_ready,
            storage_protection_state: self.storage.protection_status().state().as_str().into(),
            skills_ready: self.skills_ready,
            model_configured: self.model_configured.load(Ordering::Acquire),
            skill_management_mode: management_mode_name(self.skill_policy.mode).into(),
            active_snapshot_generation: snapshot.generation(),
            quarantined_count,
            last_reload_status: self.reload_status.snapshot(),
        })
    }

    pub fn list_skills(&self) -> Result<Vec<MobileSkillDto>> {
        if self.skill_policy.can_inspect(&self.actor_context) {
            let layered = self.tokio.block_on(
                self.skill_management
                    .list_layered_skills(&self.actor_context),
            )?;
            return layered.into_iter().map(mobile_layered_skill).collect();
        }
        let snapshot = self.skill_manager.current_snapshot();
        let snapshot_record = self
            .tokio
            .block_on(self.skill_state.get_snapshot(snapshot.generation()))?
            .with_context(|| {
                format!(
                    "active skill snapshot state is missing for generation {}",
                    snapshot.generation()
                )
            })?;
        anyhow::ensure!(
            snapshot_record.status == SkillSnapshotStatus::Active,
            "skill snapshot generation {} is not active",
            snapshot.generation()
        );
        let active_revisions = managed_revision_ids(&snapshot_record.members_json)?;
        let mut managed_revisions = BTreeMap::new();
        for row in self
            .tokio
            .block_on(self.skill_state.list_managed_installations_with_revisions())?
        {
            let installation = row.installation;
            match (
                installation.active_revision_id,
                row.active_version,
                row.active_content_hash,
            ) {
                (Some(revision_id), Some(version), Some(content_hash)) => {
                    managed_revisions.insert(
                        installation.package_id,
                        (revision_id, version, content_hash),
                    );
                }
                (None, None, None) => {}
                _ => anyhow::bail!(
                    "managed installation revision state is inconsistent for {}",
                    installation.package_id.as_str()
                ),
            }
        }
        let mut builtin_ids = BTreeSet::new();
        let mut managed_ids = BTreeSet::new();
        for resolved in snapshot.inactive().iter().chain(snapshot.packages()) {
            match resolved.package.layer {
                SkillLayer::Builtin => {
                    builtin_ids.insert(resolved.package.descriptor.id.clone());
                }
                SkillLayer::Managed => {
                    managed_ids.insert(resolved.package.descriptor.id.clone());
                }
                SkillLayer::Session => {}
            }
        }
        let mut inventory = BTreeMap::new();
        for resolved in snapshot.inactive() {
            let descriptor = &resolved.package.descriptor;
            let source_layer = layer_name(resolved.package.layer);
            let status = resolution_status_name(resolved.status);
            let active_revision_id =
                managed_inventory_revision(resolved, false, &active_revisions, &managed_revisions)?;
            let dto = MobileSkillDto {
                package_id: descriptor.id.as_str().to_string(),
                display_name: descriptor.display_name.clone(),
                version: descriptor.version.to_string(),
                source_layer: source_layer.into(),
                status: status.into(),
                available: false,
                reason: resolved.reason.clone(),
                active_revision_id: active_revision_id.clone(),
                manageable: self.skill_manageable(resolved),
                built_in_collision: builtin_ids.contains(&descriptor.id)
                    && managed_ids.contains(&descriptor.id),
                effective: None,
                managed: (resolved.package.layer == SkillLayer::Managed).then(|| {
                    mobile_layer_status(
                        resolved,
                        false,
                        active_revision_id.clone(),
                        self.skill_manageable(resolved),
                    )
                }),
                actions: SkillActionFacts::default(),
            };
            let key = descriptor.id.as_str().to_string();
            if dto.source_layer == "managed"
                || inventory
                    .get(&key)
                    .is_none_or(|existing: &MobileSkillDto| existing.source_layer != "managed")
            {
                inventory.insert(key, dto);
            }
        }
        for resolved in snapshot.packages() {
            let descriptor = &resolved.package.descriptor;
            let active_revision_id =
                managed_inventory_revision(resolved, true, &active_revisions, &managed_revisions)?;
            let key = descriptor.id.as_str().to_string();
            let previous_managed = inventory.get(&key).and_then(|item| item.managed.clone());
            let manageable = self.skill_manageable(resolved);
            let effective =
                mobile_layer_status(resolved, true, active_revision_id.clone(), manageable);
            inventory.insert(
                key,
                MobileSkillDto {
                    package_id: descriptor.id.as_str().to_string(),
                    display_name: descriptor.display_name.clone(),
                    version: descriptor.version.to_string(),
                    source_layer: layer_name(resolved.package.layer).into(),
                    status: resolution_status_name(resolved.status).into(),
                    available: true,
                    reason: resolved.reason.clone(),
                    active_revision_id,
                    manageable,
                    built_in_collision: builtin_ids.contains(&descriptor.id)
                        && managed_ids.contains(&descriptor.id),
                    effective: Some(effective.clone()),
                    managed: if resolved.package.layer == SkillLayer::Managed {
                        Some(effective)
                    } else {
                        previous_managed
                    },
                    actions: SkillActionFacts::default(),
                },
            );
        }
        Ok(inventory.into_values().collect())
    }

    fn skill_manageable(
        &self,
        resolved: &agent_runtime::skill_resolver::ResolvedSkillPackage,
    ) -> bool {
        let descriptor = &resolved.package.descriptor;
        match resolved.package.layer {
            SkillLayer::Builtin => self
                .skill_policy
                .can_override(&self.actor_context, &descriptor.id),
            SkillLayer::Managed => [
                SkillOperation::Disable,
                SkillOperation::DeleteManaged,
                SkillOperation::Rollback,
            ]
            .into_iter()
            .any(|operation| {
                self.skill_policy
                    .allows(&self.actor_context, operation, descriptor.kind)
            }),
            SkillLayer::Session => false,
        }
    }

    pub fn list_managed_skills(&self) -> Result<Vec<SkillPackageStatus>> {
        self.tokio.block_on(
            self.skill_management
                .list_managed_skills(&self.actor_context),
        )
    }

    pub fn get_skill_detail(
        &self,
        package_id: &str,
    ) -> Result<agent_runtime::skill_management::SkillPackageDetail> {
        let package_id = SkillPackageId::parse(package_id)?;
        self.tokio.block_on(
            self.skill_management
                .get_skill_detail(&self.actor_context, &package_id),
        )
    }

    pub fn create_skill_draft(
        &self,
        request: CreateSkillDraftRequest,
    ) -> Result<SkillDraftSummary> {
        self.create_skill_draft_with_files(request, Vec::new())
    }

    pub fn create_skill_draft_with_files(
        &self,
        request: CreateSkillDraftRequest,
        files: Vec<DraftFileUpdate>,
    ) -> Result<SkillDraftSummary> {
        self.tokio
            .block_on(self.skill_management.create_draft_with_files(
                &self.actor_context,
                request,
                files,
            ))
    }

    pub fn update_skill_draft(
        &self,
        revision_id: &str,
        files: Vec<DraftFileUpdate>,
    ) -> Result<SkillDraftSummary> {
        self.tokio.block_on(self.skill_management.update_draft(
            &self.actor_context,
            revision_id,
            files,
        ))
    }

    pub fn validate_skill_draft(&self, revision_id: &str) -> Result<SkillDraftValidation> {
        self.tokio.block_on(
            self.skill_management
                .validate_draft(&self.actor_context, revision_id),
        )
    }

    pub fn request_skill_activation(&self, revision_id: &str) -> Result<serde_json::Value> {
        let approval = self.tokio.block_on(
            self.skill_management
                .request_activation(&self.actor_context, revision_id),
        )?;
        Ok(approval_value(&approval))
    }

    pub fn resolve_skill_approval(
        &self,
        approval_id: &str,
        approve: bool,
    ) -> Result<serde_json::Value> {
        if approve {
            let report = self.tokio.block_on(
                self.skill_management
                    .approve_pending_skill_operation(approval_id, &self.actor_context),
            )?;
            self.record_reload(report.active_generation);
            let mut value = reload_report_value(&report);
            value["status"] = serde_json::json!("approved");
            Ok(value)
        } else {
            let approval = self.tokio.block_on(
                self.skill_management
                    .reject_pending_skill_operation(approval_id, &self.actor_context),
            )?;
            Ok(approval_value(&approval))
        }
    }

    pub fn disable_managed_skill(&self, package_id: &str) -> Result<serde_json::Value> {
        let package_id = SkillPackageId::parse(package_id)?;
        let report = self.tokio.block_on(
            self.skill_management
                .disable_managed_skill(&self.actor_context, &package_id),
        )?;
        self.record_reload(report.active_generation);
        Ok(reload_report_value(&report))
    }

    pub fn rollback_managed_skill(
        &self,
        package_id: &str,
        revision_id: &str,
    ) -> Result<serde_json::Value> {
        let package_id = SkillPackageId::parse(package_id)?;
        let outcome = self
            .tokio
            .block_on(self.skill_management.rollback_managed_skill(
                &self.actor_context,
                &package_id,
                revision_id,
            ))?;
        match outcome {
            SkillRollbackOutcome::Published(report) => {
                self.record_reload(report.generation);
                Ok(serde_json::to_value(report)?)
            }
            SkillRollbackOutcome::ApprovalRequired(approval) => Ok(approval_value(&approval)),
        }
    }

    pub fn request_skill_removal(&self, package_id: &str) -> Result<serde_json::Value> {
        let package_id = SkillPackageId::parse(package_id)?;
        let approval = self.tokio.block_on(
            self.skill_management
                .request_removal(&self.actor_context, &package_id),
        )?;
        Ok(approval_value(&approval))
    }

    pub fn synchronize_skills(&self) -> Result<MobileDiagnostics> {
        let recovery = self
            .tokio
            .block_on(self.skill_manager.startup_reconcile())
            .context("managed skill synchronization failed")?;
        self.record_reload(recovery.generation);
        self.diagnostics()
    }

    fn record_reload(&self, generation: u64) {
        self.reload_status.record(generation);
    }

    pub fn create_session(&self, title: &str) -> Result<MobileSessionDto> {
        let title = title.trim();
        if title.is_empty() {
            anyhow::bail!("session title is required");
        }
        self.tokio
            .block_on(
                self.storage
                    .create_scoped_session(&self.conversation_scope, title),
            )
            .map(Into::into)
    }

    pub fn list_sessions(&self) -> Result<Vec<MobileSessionDto>> {
        self.tokio
            .block_on(self.storage.list_scoped_sessions(&self.conversation_scope))
            .map(|sessions| sessions.into_iter().map(Into::into).collect())
    }

    pub fn get_messages(&self, session_id: &str) -> Result<Vec<MobileMessageDto>> {
        self.tokio
            .block_on(
                self.storage
                    .list_scoped_messages(&self.conversation_scope, session_id),
            )
            .map(|messages| messages.into_iter().map(Into::into).collect())
    }

    pub fn delete_session(&self, session_id: &str) -> Result<()> {
        if let Some(memory) = &self.memory_tools {
            self.tokio
                .block_on(memory.on_session_end(session_id, Vec::new()))?;
        }
        self.tokio.block_on(
            self.storage
                .delete_scoped_session(&self.conversation_scope, session_id),
        )
    }

    pub fn save_model_config(&self, config: MobileModelConfigDto) -> Result<()> {
        let stored = StoredModelConfig::try_from(config)?;
        self.tokio
            .block_on(self.storage.save_model_config(&stored))?;
        self.model_configured.store(true, Ordering::Release);
        Ok(())
    }

    pub fn load_model_config(&self) -> Result<Option<MobileModelConfigDto>> {
        self.tokio
            .block_on(self.storage.load_model_config())
            .map(|config| config.map(Into::into))
    }

    pub fn list_memories(&self, query: &str, limit: usize) -> Result<serde_json::Value> {
        let memory = self
            .memory_tools
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("Memory Foundation is disabled"))?;
        self.tokio.block_on(memory.execute(
            "memory_search",
            serde_json::json!({"query": query, "limit": limit}),
        ))
    }

    pub fn forget_memory(
        &self,
        memory_id: &str,
        expected_version: u64,
    ) -> Result<serde_json::Value> {
        let memory = self
            .memory_tools
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("Memory Foundation is disabled"))?;
        self.tokio.block_on(memory.execute(
            "memory_forget",
            serde_json::json!({
                "id": memory_id,
                "expectedVersion": expected_version,
                "reason": "user_request"
            }),
        ))
    }

    pub fn export_memories(&self) -> Result<serde_json::Value> {
        let memory = self
            .memory_tools
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("Memory Foundation is disabled"))?;
        self.tokio.block_on(memory.execute(
            "memory_export",
            serde_json::json!({"includeProposals": false, "includeTombstones": false}),
        ))
    }

    pub fn list_mail_accounts(&self) -> Result<serde_json::Value> {
        self.execute_mail("mail_accounts_list", serde_json::json!({}), false)
    }

    pub fn mail_account_status(&self, account_id: &str) -> Result<serde_json::Value> {
        self.execute_mail(
            "mail_account_status",
            serde_json::json!({"accountId": account_id}),
            false,
        )
    }

    pub fn connect_mail_account(&self, account_id: &str) -> Result<serde_json::Value> {
        self.execute_mail(
            "mail_account_connect",
            serde_json::json!({"accountId": account_id}),
            true,
        )
    }

    pub fn disconnect_mail_account(&self, account_id: &str) -> Result<serde_json::Value> {
        self.execute_mail(
            "mail_account_disconnect",
            serde_json::json!({"accountId": account_id}),
            true,
        )
    }

    pub fn list_foundation_actions(
        &self,
    ) -> Result<Vec<agent_runtime::foundation_actions::PendingFoundationAction>> {
        self.tokio.block_on(
            self.mail_actions
                .as_ref()
                .ok_or_else(|| anyhow::anyhow!("Foundation action service is disabled"))?
                .list_actions(),
        )
    }

    pub fn resolve_foundation_action(
        &self,
        approval_id: &str,
        decision: agent_runtime::approval::ApprovalDecision,
    ) -> Result<agent_runtime::foundation_actions::FoundationActionResolution> {
        self.ensure_external_side_effect_allowed()?;
        self.tokio.block_on(
            self.mail_actions
                .as_ref()
                .ok_or_else(|| anyhow::anyhow!("Foundation action service is disabled"))?
                .resolve(approval_id, decision, "local-user", chrono::Utc::now()),
        )
    }

    fn execute_mail(
        &self,
        tool: &str,
        arguments: serde_json::Value,
        trusted_host_action: bool,
    ) -> Result<serde_json::Value> {
        let tools = self
            .connector_tools
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("Mail Foundation is disabled"))?;
        let call_id = Uuid::new_v4().to_string();
        let envelope = if trusted_host_action {
            self.tokio
                .block_on(tools.execute_trusted_host_action(tool, &call_id, arguments))?
        } else {
            self.tokio
                .block_on(tools.execute(tool, &call_id, arguments))?
        };
        envelope
            .get("output")
            .cloned()
            .ok_or_else(|| anyhow::anyhow!("connector output is missing"))
    }

    pub fn send_message(
        &self,
        session_id: &str,
        content: &str,
        api_key: Option<String>,
    ) -> Result<MobileTurnDto> {
        if self.cancellation.is_cancelled() {
            anyhow::bail!("runtime closed");
        }
        self.tokio.block_on(async {
            if !self
                .storage
                .session_exists_scoped(&self.conversation_scope, session_id)
                .await?
            {
                anyhow::bail!("session not found");
            }
            self.storage
                .append_scoped_message(&self.conversation_scope, session_id, "user", content)
                .await?;
            Ok::<_, anyhow::Error>(())
        })?;
        let cancellation = self.cancellation.clone();
        let result = self.tokio.block_on(async {
            let turn = async {
                let config = self
                    .storage
                    .load_model_config()
                    .await?
                    .ok_or_else(|| anyhow::anyhow!("model configuration is required"))?;
                if config.secret_id.is_some()
                    && api_key
                        .as_deref()
                        .map(str::trim)
                        .filter(|value| !value.is_empty())
                        .is_none()
                {
                    anyhow::bail!("model API key is unavailable");
                }
                let host = HttpMobileRuntimeHost::new_with_manager(
                    self.storage.clone(),
                    self.skill_manager.clone(),
                    self.runtime_config.clone(),
                    self.init.clone(),
                    config,
                    TransientSecretResolver::new(api_key),
                )?
                .with_app_prompt(self.app_prompt.clone())
                .with_foundations(self.memory_tools.clone(), self.connector_tools.clone())
                .with_mail_actions(self.mail_actions.clone())
                .with_owner_turn_context(self.skill_management.clone(), self.actor_context.clone());
                host.send_message_after_user_persisted(session_id, content)
                    .await
            };
            tokio::select! {
                biased;
                _ = cancellation.cancelled() => anyhow::bail!("runtime closed"),
                result = tokio::time::timeout(Duration::from_secs(60), turn) => match result {
                    Ok(result) => result,
                    Err(_) => anyhow::bail!("model turn timed out"),
                },
            }
        })?;
        Ok(MobileTurnDto {
            assistant_text: result.assistant_text,
        })
    }

    pub fn close(&self) {
        self.cancellation.cancel();
    }
}

async fn resolve_mobile_memory(
    storage: &Storage,
    app_prompt: &AppPromptConfig,
) -> Result<Option<MemoryToolRuntime>> {
    if !app_prompt
        .identity
        .enabled_capabilities
        .iter()
        .any(|capability| capability == "memory-provider")
    {
        return Ok(None);
    }
    let provider = Arc::new(storage.local_memory_provider());
    provider.initialize().await?;
    Ok(Some(MemoryToolRuntime::new(
        provider,
        MemoryScope::new(&app_prompt.identity.app_id, "local", "local-user")?,
    )?))
}

async fn resolve_mobile_mail(
    storage: &Storage,
    app_prompt: &AppPromptConfig,
    runtime_config: &RuntimeConfig,
) -> Result<Option<(ConnectorToolRuntime, MailActionService)>> {
    if !app_prompt
        .identity
        .enabled_capabilities
        .iter()
        .any(|capability| capability == "mail-connector")
    {
        return Ok(None);
    }
    if runtime_config
        .agent_app_policy
        .as_ref()
        .is_some_and(|policy| {
            policy.network() == AppNetworkPolicy::Deny
                || !policy
                    .declares_connector(agent_runtime::mail_connector_transport::MAIL_CONNECTOR_ID)
        })
    {
        return Ok(None);
    }
    let mail = Arc::new(FakeMailConnector::new());
    mail.add_account(MailAccount {
        id: "primary".into(),
        display_name: "Example Mail".into(),
        primary_address: MailAddress {
            name: Some("Local User".into()),
            address: "local@example.test".into(),
        },
        addresses: Vec::new(),
        provider_reference: None,
    })?;
    let ledger = Arc::new(SqliteConnectorActionLedger::from_storage(storage).await?);
    let vault = CredentialVault::new(Arc::new(InMemorySecretStore::default()));
    let runtime = Arc::new(ConnectorRuntime::new_with_ledger(
        Some(vault),
        ledger,
        256 * 1024,
    )?);
    runtime
        .register(
            MailConnectorTransport::descriptor("Fake Mail", true),
            Arc::new(MailConnectorTransport::new(mail)),
        )
        .await?;
    let scope = CredentialScope {
        app_id: app_prompt.identity.app_id.clone(),
        tenant_id: "local".into(),
        user_id: "local-user".into(),
    };
    let context = Arc::new(EphemeralConnectorContextProvider::fail_closed(
        scope.clone(),
        Duration::from_secs(30),
    )?);
    let tools = ConnectorToolRuntime::load(runtime, context.clone())?;
    let actions = MailActionService::new(
        storage,
        tools.clone(),
        context,
        scope,
        "agentweave.mobile.foundation-actions.v1",
    )
    .await?;
    Ok(Some((tools, actions)))
}
