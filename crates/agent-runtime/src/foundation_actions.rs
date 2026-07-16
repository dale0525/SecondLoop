use crate::approval::{ApprovalDecision, ApprovalRecord, ApprovalStatus};
use crate::connector::{ConnectorExecutionResult, connector_action_hash};
use crate::connector_tools::{ConnectorToolRuntime, EphemeralConnectorContextProvider};
use crate::credential::CredentialScope;
use crate::durable_run::{
    ActionOutcome, ActionStatus, DurableAction, DurableRunStore, OutboxStatus, RunScope, RunStatus,
};
use crate::foundation_action_envelope::{
    DurableFoundationActionStore, FoundationActionEnvelope, FoundationActionRequest,
};
use crate::mail::{
    ApprovedSendRequest, DeliveryState, PreviewSendRequest, SendPreview, sha256_hex,
};
use crate::mail_action_envelope::{
    CanonicalMailSendEnvelope, MAIL_SEND_ACTION_KIND, MAIL_SEND_OPERATION,
};
use crate::mail_connector_transport::MAIL_CONNECTOR_ID;
use crate::storage::Storage;
use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::sync::Arc;

const LEGACY_MAIL_SEND_ACTION: &str = "mail_send";
const MAIL_SEND_PREVIEW_ACTION: &str = "mail_send_preview";

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentMailSendPreviewRequest {
    pub account_id: String,
    pub draft_id: String,
    pub expected_revision: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FoundationActionTurnContext {
    session_id: String,
    turn_id: String,
}

impl FoundationActionTurnContext {
    pub fn new(session_id: impl Into<String>, turn_id: impl Into<String>) -> anyhow::Result<Self> {
        let context = Self {
            session_id: session_id.into(),
            turn_id: turn_id.into(),
        };
        anyhow::ensure!(
            !context.session_id.trim().is_empty(),
            "foundation action session id is required"
        );
        anyhow::ensure!(
            !context.turn_id.trim().is_empty(),
            "foundation action turn id is required"
        );
        Ok(context)
    }

    pub fn session_id(&self) -> &str {
        &self.session_id
    }

    pub fn turn_id(&self) -> &str {
        &self.turn_id
    }
}
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct PendingFoundationAction {
    pub approval: ApprovalRecord,
    pub action: DurableAction,
    pub preview: Option<SendPreview>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct FoundationActionResolution {
    pub approval: ApprovalRecord,
    pub action: DurableAction,
    pub connector_result: Option<ConnectorExecutionResult>,
}

#[derive(Clone)]
pub struct MailActionService {
    store: DurableRunStore,
    envelopes: DurableFoundationActionStore,
    tools: ConnectorToolRuntime,
    context: Arc<EphemeralConnectorContextProvider>,
    scope: CredentialScope,
    policy_version: String,
}

impl MailActionService {
    pub async fn new(
        storage: &Storage,
        tools: ConnectorToolRuntime,
        context: Arc<EphemeralConnectorContextProvider>,
        scope: CredentialScope,
        policy_version: impl Into<String>,
    ) -> anyhow::Result<Self> {
        scope.validate()?;
        let policy_version = policy_version.into();
        anyhow::ensure!(
            !policy_version.trim().is_empty(),
            "foundation action policy version is required"
        );
        let store = DurableRunStore::from_storage(storage).await?;
        let envelopes = DurableFoundationActionStore::from_storage(storage).await?;
        Ok(Self {
            store,
            envelopes,
            tools,
            context,
            scope,
            policy_version,
        })
    }

    pub async fn request_send_from_agent_preview(
        &self,
        request: AgentMailSendPreviewRequest,
        context: &FoundationActionTurnContext,
        call_id: &str,
        now: DateTime<Utc>,
    ) -> anyhow::Result<PendingFoundationAction> {
        anyhow::ensure!(
            !request.account_id.trim().is_empty(),
            "mail account id is required"
        );
        anyhow::ensure!(
            !request.draft_id.trim().is_empty(),
            "mail draft id is required"
        );
        anyhow::ensure!(
            request.expected_revision > 0,
            "mail draft revision must be positive"
        );
        anyhow::ensure!(
            !call_id.trim().is_empty(),
            "mail preview call id is required"
        );
        let idempotency_key = agent_preview_idempotency_key(&self.scope, context, call_id)?;
        let connector_request = PreviewSendRequest {
            account_id: request.account_id,
            draft_id: request.draft_id,
            expected_revision: request.expected_revision,
            idempotency_key: idempotency_key.clone(),
        };
        let connector_value = self
            .tools
            .execute(
                MAIL_SEND_PREVIEW_ACTION,
                call_id,
                serde_json::to_value(&connector_request)?,
            )
            .await?;
        let connector_result: ConnectorExecutionResult = serde_json::from_value(connector_value)?;
        anyhow::ensure!(
            connector_result.connector_id == MAIL_CONNECTOR_ID
                && connector_result.tool_name == MAIL_SEND_PREVIEW_ACTION,
            "mail preview connector result is invalid"
        );
        let preview: SendPreview = serde_json::from_value(connector_result.output)?;
        anyhow::ensure!(
            preview.account_id == connector_request.account_id
                && preview.draft_id == connector_request.draft_id
                && preview.draft_revision == connector_request.expected_revision,
            "mail preview does not match the requested draft revision"
        );
        anyhow::ensure!(
            preview.idempotency_key == idempotency_key,
            "mail preview idempotency key mismatch"
        );
        self.request_send(preview, Some(context.session_id.clone()), now)
            .await
    }

    pub async fn request_send(
        &self,
        preview: SendPreview,
        session_id: Option<String>,
        now: DateTime<Utc>,
    ) -> anyhow::Result<PendingFoundationAction> {
        validate_preview(&preview)?;
        let run_scope = self.run_scope(session_id);
        let legacy_arguments = serde_json::json!({"preview": preview});
        if let Some(existing) = self
            .store
            .find_scoped_action_by_idempotency(
                &run_scope,
                LEGACY_MAIL_SEND_ACTION,
                preview_idempotency_key(&legacy_arguments)?,
            )
            .await?
        {
            anyhow::ensure!(
                existing.arguments_sha256
                    == crate::approval::immutable_arguments_hash(&legacy_arguments)?,
                "mail send idempotency key conflicts with another preview"
            );
            return self.pending_from_action(existing).await;
        }
        let envelope =
            CanonicalMailSendEnvelope::from_preview(preview.clone())?.into_foundation_action()?;
        let pending = self
            .envelopes
            .request(
                FoundationActionRequest {
                    scope: run_scope,
                    envelope,
                    policy_version: self.policy_version.clone(),
                    expires_at: now + Duration::minutes(15),
                },
                now,
            )
            .await?;
        Ok(PendingFoundationAction {
            approval: pending.approval,
            action: pending.action,
            preview: Some(preview),
        })
    }

    pub async fn list_actions(&self) -> anyhow::Result<Vec<PendingFoundationAction>> {
        let approvals = self
            .store
            .list_approvals_for_scope(
                &self.scope.app_id,
                &self.scope.tenant_id,
                &self.scope.user_id,
            )
            .await?;
        let mut actions = Vec::with_capacity(approvals.len());
        for approval in approvals {
            let action = self
                .store
                .get_action(&approval.binding.action_id)
                .await?
                .ok_or_else(|| anyhow::anyhow!("approved action is missing"))?;
            if !is_mail_send_action(&action) {
                continue;
            }
            let preview = Some(preview_from_action(&action)?);
            actions.push(PendingFoundationAction {
                approval,
                action,
                preview,
            });
        }
        Ok(actions)
    }

    pub async fn handles_approval(&self, approval_id: &str) -> anyhow::Result<bool> {
        let Some(approval) = self.store.get_approval(approval_id).await? else {
            return Ok(false);
        };
        Ok(approval.binding.app_id == self.scope.app_id
            && approval.binding.actor_id == self.scope.user_id
            && is_mail_send_action_kind(&approval.binding.action_name))
    }

    pub async fn resolve(
        &self,
        approval_id: &str,
        decision: ApprovalDecision,
        resolver: &str,
        now: DateTime<Utc>,
    ) -> anyhow::Result<FoundationActionResolution> {
        anyhow::ensure!(resolver == self.scope.user_id, "approval actor mismatch");
        let current = self
            .store
            .get_approval(approval_id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("approval not found"))?;
        anyhow::ensure!(
            current.binding.app_id == self.scope.app_id,
            "approval App mismatch"
        );
        anyhow::ensure!(
            current.binding.actor_id == resolver,
            "approval actor mismatch"
        );
        anyhow::ensure!(
            is_mail_send_action_kind(&current.binding.action_name),
            "approval is not a Mail send action"
        );
        let resolved = self
            .store
            .resolve_approval(approval_id, decision, resolver, now)
            .await?;
        let action = self
            .store
            .get_action(&resolved.binding.action_id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("approved action is missing"))?;

        if matches!(
            resolved.status,
            ApprovalStatus::Rejected | ApprovalStatus::Cancelled | ApprovalStatus::Expired
        ) {
            self.finish_cancelled(&action, &resolved, now).await?;
            return self.resolution(resolved, None).await;
        }
        if action.status.is_terminal() {
            return Ok(FoundationActionResolution {
                approval: resolved,
                action,
                connector_result: None,
            });
        }
        anyhow::ensure!(
            matches!(
                resolved.status,
                ApprovalStatus::Approved | ApprovalStatus::Consumed
            ),
            "approval is not executable"
        );
        if action.status == ActionStatus::Executing {
            anyhow::bail!("mail action execution outcome is uncertain and requires reconciliation");
        }
        self.execute_approved(resolved, action, now).await
    }

    async fn execute_approved(
        &self,
        approval: ApprovalRecord,
        action: DurableAction,
        now: DateTime<Utc>,
    ) -> anyhow::Result<FoundationActionResolution> {
        if action.status == ActionStatus::WaitingApproval {
            self.store
                .consume_approval(&approval.approval_id, &approval.binding, now)
                .await?;
        }
        let action = self
            .store
            .get_action(&action.action_id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("approved action is missing"))?;
        anyhow::ensure!(
            action.status == ActionStatus::Ready,
            "approved action is not ready"
        );
        let run = self
            .store
            .get_run(&action.run_id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("foundation action run is missing"))?;
        if run.status == RunStatus::WaitingApproval {
            anyhow::ensure!(
                self.store
                    .transition_run(
                        &run.run_id,
                        run.version,
                        RunStatus::Running,
                        run.checkpoint,
                        now,
                    )
                    .await?,
                "approved action run was resumed elsewhere"
            );
        }
        anyhow::ensure!(
            self.store
                .begin_action(&action.action_id, action.version, now)
                .await?,
            "approved action was claimed elsewhere"
        );
        let preview = preview_from_action(&action)?;
        let request = ApprovedSendRequest {
            preview_id: preview.id.clone(),
            approval: preview.approval_grant(approval.approval_id.clone()),
        };
        let connector_arguments = serde_json::to_value(request)?;
        let action_hash =
            connector_action_hash(MAIL_CONNECTOR_ID, MAIL_SEND_OPERATION, &connector_arguments)?;
        self.context
            .grant_once(&action_hash, preview.idempotency_key.clone())?;
        let outbox = self
            .store
            .enqueue_outbox(
                &action.action_id,
                &preview.idempotency_key,
                connector_arguments.clone(),
                now,
            )
            .await?;
        anyhow::ensure!(
            self.store.claim_outbox(&outbox.outbox_id, now).await?,
            "mail outbox was claimed elsewhere"
        );
        let result = self
            .tools
            .execute(
                MAIL_SEND_OPERATION,
                &format!("resume:{}", action.action_id),
                connector_arguments,
            )
            .await;
        let connector_result = match result {
            Ok(value) => serde_json::from_value::<ConnectorExecutionResult>(value)?,
            Err(error) => {
                self.store
                    .finish_outbox(
                        &outbox.outbox_id,
                        OutboxStatus::Uncertain,
                        None,
                        Some("connector execution failed after outbox claim"),
                        Utc::now(),
                    )
                    .await?;
                self.store
                    .complete_action(
                        &action.action_id,
                        ActionOutcome::Uncertain,
                        Value::Null,
                        Some("connector execution outcome requires reconciliation"),
                        Utc::now(),
                    )
                    .await?;
                self.finish_run(&action.run_id, RunStatus::Uncertain, Utc::now())
                    .await?;
                return Err(error.context("mail send outcome requires reconciliation"));
            }
        };
        let delivery = serde_json::from_value::<crate::mail::DeliveryReceipt>(
            connector_result.output.clone(),
        )?;
        let (outbox_status, action_outcome, run_status) = match delivery.state {
            DeliveryState::Delivered => (
                OutboxStatus::Delivered,
                ActionOutcome::Succeeded,
                RunStatus::Succeeded,
            ),
            DeliveryState::Uncertain => (
                OutboxStatus::Uncertain,
                ActionOutcome::Uncertain,
                RunStatus::Uncertain,
            ),
            DeliveryState::Rejected | DeliveryState::Deferred => (
                OutboxStatus::Failed,
                ActionOutcome::Failed,
                RunStatus::Failed,
            ),
        };
        self.store
            .finish_outbox(
                &outbox.outbox_id,
                outbox_status,
                Some(&delivery.message_id),
                delivery.detail.as_deref(),
                Utc::now(),
            )
            .await?;
        self.store
            .complete_action(
                &action.action_id,
                action_outcome,
                connector_result.output.clone(),
                delivery.detail.as_deref(),
                Utc::now(),
            )
            .await?;
        self.finish_run(&action.run_id, run_status, Utc::now())
            .await?;
        self.resolution(approval, Some(connector_result)).await
    }

    async fn finish_cancelled(
        &self,
        action: &DurableAction,
        approval: &ApprovalRecord,
        now: DateTime<Utc>,
    ) -> anyhow::Result<()> {
        self.store
            .cancel_waiting_action(&action.action_id, "approval was not granted", now)
            .await?;
        let run_status = if approval.status == ApprovalStatus::Expired {
            RunStatus::Expired
        } else {
            RunStatus::Cancelled
        };
        self.finish_run(&action.run_id, run_status, now).await
    }

    async fn finish_run(
        &self,
        run_id: &str,
        status: RunStatus,
        now: DateTime<Utc>,
    ) -> anyhow::Result<()> {
        let run = self
            .store
            .get_run(run_id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("foundation action run is missing"))?;
        if !run.status.is_terminal() {
            anyhow::ensure!(
                self.store
                    .transition_run(run_id, run.version, status, run.checkpoint, now)
                    .await?,
                "foundation action run transition lost a race"
            );
        }
        Ok(())
    }

    async fn pending_from_action(
        &self,
        action: DurableAction,
    ) -> anyhow::Result<PendingFoundationAction> {
        let approval_id = action
            .approval_id
            .as_deref()
            .ok_or_else(|| anyhow::anyhow!("mail action approval is missing"))?;
        let approval = self
            .store
            .get_approval(approval_id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("mail action approval disappeared"))?;
        let preview = preview_from_action(&action)?;
        Ok(PendingFoundationAction {
            approval,
            action,
            preview: Some(preview),
        })
    }

    async fn resolution(
        &self,
        approval: ApprovalRecord,
        connector_result: Option<ConnectorExecutionResult>,
    ) -> anyhow::Result<FoundationActionResolution> {
        let approval = self
            .store
            .get_approval(&approval.approval_id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("resolved approval is missing"))?;
        let action = self
            .store
            .get_action(&approval.binding.action_id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("resolved action is missing"))?;
        Ok(FoundationActionResolution {
            approval,
            action,
            connector_result,
        })
    }

    fn run_scope(&self, session_id: Option<String>) -> RunScope {
        RunScope {
            app_id: self.scope.app_id.clone(),
            agent_id: "foundation-host".into(),
            tenant_id: self.scope.tenant_id.clone(),
            user_id: self.scope.user_id.clone(),
            session_id,
        }
    }
}

impl ActionStatus {
    fn is_terminal(self) -> bool {
        matches!(
            self,
            Self::Succeeded | Self::Failed | Self::Cancelled | Self::Uncertain
        )
    }
}

fn validate_preview(preview: &SendPreview) -> anyhow::Result<()> {
    anyhow::ensure!(!preview.id.trim().is_empty(), "mail preview id is required");
    anyhow::ensure!(
        !preview.idempotency_key.trim().is_empty(),
        "mail preview idempotency key is required"
    );
    anyhow::ensure!(
        !preview.preview_hash.trim().is_empty(),
        "mail preview hash is required"
    );
    Ok(())
}

fn preview_from_arguments(arguments: &Value) -> anyhow::Result<SendPreview> {
    let preview = arguments
        .get("preview")
        .ok_or_else(|| anyhow::anyhow!("mail action preview is missing"))?;
    serde_json::from_value(preview.clone()).map_err(Into::into)
}

fn preview_from_action(action: &DurableAction) -> anyhow::Result<SendPreview> {
    match action.action_name.as_str() {
        MAIL_SEND_ACTION_KIND => {
            let envelope = FoundationActionEnvelope::from_action(action)?;
            Ok(CanonicalMailSendEnvelope::from_foundation_action(&envelope)?.preview)
        }
        LEGACY_MAIL_SEND_ACTION => preview_from_arguments(&action.arguments),
        _ => anyhow::bail!("action is not a Mail send"),
    }
}

fn is_mail_send_action(action: &DurableAction) -> bool {
    is_mail_send_action_kind(&action.action_name)
}

fn is_mail_send_action_kind(action_name: &str) -> bool {
    matches!(action_name, MAIL_SEND_ACTION_KIND | LEGACY_MAIL_SEND_ACTION)
}

fn preview_idempotency_key(arguments: &Value) -> anyhow::Result<&str> {
    arguments
        .get("preview")
        .and_then(|preview| preview.get("idempotencyKey"))
        .and_then(Value::as_str)
        .ok_or_else(|| anyhow::anyhow!("mail preview idempotency key is missing"))
}

fn agent_preview_idempotency_key(
    scope: &CredentialScope,
    context: &FoundationActionTurnContext,
    call_id: &str,
) -> anyhow::Result<String> {
    let material = serde_json::to_vec(&(
        "agentweave.foundation.mail.send.v1",
        &scope.app_id,
        &scope.tenant_id,
        &scope.user_id,
        context.session_id(),
        context.turn_id(),
        call_id,
    ))?;
    Ok(format!("agent-mail-send-v1-{}", sha256_hex(material)))
}

#[cfg(test)]
#[path = "foundation_actions_agent_tests.rs"]
mod agent_tests;
