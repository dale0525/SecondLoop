use crate::approval::{ApprovalDecision, ApprovalRecord, ApprovalStatus};
use crate::calendar::{ApprovedCalendarMutation, CalendarEvent, CalendarMutationPreview};
use crate::calendar_action_envelope::{
    CALENDAR_APPLY_OPERATION, CanonicalCalendarActionEnvelope, is_calendar_action_kind,
};
use crate::calendar_connector_transport::CALENDAR_CONNECTOR_ID;
use crate::connector::{ConnectorExecutionResult, connector_action_hash};
use crate::connector_tools::{ConnectorToolRuntime, EphemeralConnectorContextProvider};
use crate::credential::CredentialScope;
use crate::durable_run::{
    ActionOutcome, ActionStatus, DurableAction, DurableRunStore, OutboxStatus, RunScope, RunStatus,
};
use crate::foundation_action_envelope::{
    DurableFoundationActionStore, FoundationActionEnvelope, FoundationActionRequest,
};
use crate::foundation_actions::FoundationActionResolution;
use crate::storage::Storage;
use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::sync::Arc;

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct PendingCalendarAction {
    pub approval: ApprovalRecord,
    pub action: DurableAction,
    pub preview: CalendarMutationPreview,
    pub envelope: FoundationActionEnvelope,
}

#[derive(Clone)]
pub struct CalendarActionService {
    store: DurableRunStore,
    envelopes: DurableFoundationActionStore,
    tools: ConnectorToolRuntime,
    context: Arc<EphemeralConnectorContextProvider>,
    scope: CredentialScope,
    policy_version: String,
}

impl CalendarActionService {
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
        Ok(Self {
            store: DurableRunStore::from_storage(storage).await?,
            envelopes: DurableFoundationActionStore::from_storage(storage).await?,
            tools,
            context,
            scope,
            policy_version,
        })
    }

    pub async fn request(
        &self,
        preview: CalendarMutationPreview,
        session_id: Option<String>,
        now: DateTime<Utc>,
    ) -> anyhow::Result<PendingCalendarAction> {
        preview.validate()?;
        let envelope = CanonicalCalendarActionEnvelope::from_preview(preview.clone())?
            .into_foundation_action()?;
        let pending = self
            .envelopes
            .request(
                FoundationActionRequest {
                    scope: self.run_scope(session_id),
                    envelope: envelope.clone(),
                    policy_version: self.policy_version.clone(),
                    expires_at: now + Duration::minutes(15),
                },
                now,
            )
            .await?;
        Ok(PendingCalendarAction {
            approval: pending.approval,
            action: pending.action,
            preview,
            envelope,
        })
    }

    pub async fn list_actions(&self) -> anyhow::Result<Vec<PendingCalendarAction>> {
        let approvals = self
            .store
            .list_approvals_for_scope(
                &self.scope.app_id,
                &self.scope.tenant_id,
                &self.scope.user_id,
            )
            .await?;
        let mut actions = Vec::new();
        for approval in approvals {
            let action = self
                .store
                .get_action(&approval.binding.action_id)
                .await?
                .ok_or_else(|| anyhow::anyhow!("approved action is missing"))?;
            if !is_calendar_action_kind(&action.action_name) {
                continue;
            }
            actions.push(self.pending(approval, action)?);
        }
        Ok(actions)
    }

    pub async fn handles_approval(&self, approval_id: &str) -> anyhow::Result<bool> {
        let Some(approval) = self.store.get_approval(approval_id).await? else {
            return Ok(false);
        };
        Ok(approval.binding.app_id == self.scope.app_id
            && approval.binding.actor_id == self.scope.user_id
            && is_calendar_action_kind(&approval.binding.action_name))
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
            current.binding.app_id == self.scope.app_id
                && current.binding.actor_id == resolver
                && is_calendar_action_kind(&current.binding.action_name),
            "approval is not a Calendar action for this user"
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
        if action_is_terminal(action.status) {
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
            anyhow::bail!(
                "Calendar action execution outcome is uncertain and requires reconciliation"
            );
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
        let envelope = FoundationActionEnvelope::from_action(&action)?;
        let canonical = CanonicalCalendarActionEnvelope::from_foundation_action(&envelope)?;
        let preview = canonical.preview;
        let connector_arguments = serde_json::json!({
            "accountId": preview.account_id,
            "approval": ApprovedCalendarMutation {
                preview_id: preview.preview_id.clone(),
                preview_hash: preview.preview_hash.clone(),
                approval_id: approval.approval_id.clone(),
            }
        });
        let action_hash = connector_action_hash(
            CALENDAR_CONNECTOR_ID,
            CALENDAR_APPLY_OPERATION,
            &connector_arguments,
        )?;
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
            "Calendar outbox was claimed elsewhere"
        );
        let result = self
            .tools
            .execute(
                CALENDAR_APPLY_OPERATION,
                &format!("resume:{}", action.action_id),
                connector_arguments,
            )
            .await;
        let connector_result = match result {
            Ok(value) => serde_json::from_value::<ConnectorExecutionResult>(value)?,
            Err(error) => {
                self.finish_uncertain(&action, &outbox.outbox_id).await?;
                return Err(error.context("Calendar mutation outcome requires reconciliation"));
            }
        };
        let event = serde_json::from_value::<CalendarEvent>(connector_result.output.clone())?;
        validate_result(&event)?;
        let provider_reference = event.provider_id.as_deref().unwrap_or(&event.id);
        self.store
            .finish_outbox(
                &outbox.outbox_id,
                OutboxStatus::Delivered,
                Some(provider_reference),
                None,
                Utc::now(),
            )
            .await?;
        self.store
            .complete_action(
                &action.action_id,
                ActionOutcome::Succeeded,
                connector_result.output.clone(),
                None,
                Utc::now(),
            )
            .await?;
        self.finish_run(&action.run_id, RunStatus::Succeeded, Utc::now())
            .await?;
        self.resolution(approval, Some(connector_result)).await
    }

    async fn finish_uncertain(
        &self,
        action: &DurableAction,
        outbox_id: &str,
    ) -> anyhow::Result<()> {
        let now = Utc::now();
        self.store
            .finish_outbox(
                outbox_id,
                OutboxStatus::Uncertain,
                None,
                Some("connector execution failed after outbox claim"),
                now,
            )
            .await?;
        self.store
            .complete_action(
                &action.action_id,
                ActionOutcome::Uncertain,
                Value::Null,
                Some("connector execution outcome requires reconciliation"),
                now,
            )
            .await?;
        self.finish_run(&action.run_id, RunStatus::Uncertain, now)
            .await
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
        let status = if approval.status == ApprovalStatus::Expired {
            RunStatus::Expired
        } else {
            RunStatus::Cancelled
        };
        self.finish_run(&action.run_id, status, now).await
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

    fn pending(
        &self,
        approval: ApprovalRecord,
        action: DurableAction,
    ) -> anyhow::Result<PendingCalendarAction> {
        let envelope = FoundationActionEnvelope::from_action(&action)?;
        let preview = CanonicalCalendarActionEnvelope::from_foundation_action(&envelope)?.preview;
        Ok(PendingCalendarAction {
            approval,
            action,
            preview,
            envelope,
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

fn action_is_terminal(status: ActionStatus) -> bool {
    matches!(
        status,
        ActionStatus::Succeeded
            | ActionStatus::Failed
            | ActionStatus::Cancelled
            | ActionStatus::Uncertain
    )
}

fn validate_result(event: &CalendarEvent) -> anyhow::Result<()> {
    anyhow::ensure!(!event.id.trim().is_empty(), "Calendar event id is required");
    anyhow::ensure!(event.id.len() <= 512, "Calendar event id is too long");
    anyhow::ensure!(event.version > 0, "Calendar event version is invalid");
    event.content.validate()?;
    Ok(())
}

#[cfg(test)]
#[path = "calendar_actions_tests.rs"]
mod tests;
