use crate::approval::{ApprovalBinding, ApprovalRecord, ApprovalRisk, immutable_arguments_hash};
use crate::durable_run::{DurableAction, DurableRun, DurableRunStore, RunScope};
use crate::storage::Storage;
use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sqlx::Row;
use uuid::Uuid;

const FOUNDATION_ACTION_SCHEMA_VERSION: u32 = 1;
const FOUNDATION_ACTION_STORE_VERSION: i64 = 1;
const MAX_PAYLOAD_BYTES: usize = 256 * 1024;
const MAX_PREVIEW_BYTES: usize = 64 * 1024;

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum FoundationActionEffect {
    ReadSensitive,
    ExternalWrite,
    DestructiveWrite,
    CredentialAccess,
}

impl FoundationActionEffect {
    fn approval_risk(self) -> ApprovalRisk {
        match self {
            Self::ReadSensitive => ApprovalRisk::ReadSensitive,
            Self::ExternalWrite => ApprovalRisk::ExternalWrite,
            Self::DestructiveWrite => ApprovalRisk::DestructiveWrite,
            Self::CredentialAccess => ApprovalRisk::CredentialAccess,
        }
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct FoundationActionResource {
    pub resource_type: String,
    pub resource_id: String,
    pub expected_revision: Option<String>,
}

impl FoundationActionResource {
    pub fn new(
        resource_type: impl Into<String>,
        resource_id: impl Into<String>,
        expected_revision: Option<String>,
    ) -> anyhow::Result<Self> {
        let resource = Self {
            resource_type: resource_type.into(),
            resource_id: resource_id.into(),
            expected_revision,
        };
        resource.validate()?;
        Ok(resource)
    }

    fn validate(&self) -> anyhow::Result<()> {
        validate_identifier(&self.resource_type, "resource type")?;
        validate_bounded_text(&self.resource_id, 512, "resource id")?;
        if let Some(revision) = &self.expected_revision {
            validate_bounded_text(revision, 255, "resource revision")?;
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct FoundationActionPreview {
    pub summary: String,
    pub details: Value,
}

impl FoundationActionPreview {
    pub fn new(summary: impl Into<String>, details: Value) -> anyhow::Result<Self> {
        let preview = Self {
            summary: summary.into(),
            details,
        };
        preview.validate()?;
        Ok(preview)
    }

    fn validate(&self) -> anyhow::Result<()> {
        validate_bounded_text(&self.summary, 1024, "action preview summary")?;
        anyhow::ensure!(
            serde_json::to_vec(&self.details)?.len() <= MAX_PREVIEW_BYTES,
            "action preview details exceed limit"
        );
        Ok(())
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct FoundationActionEnvelope {
    pub schema_version: u32,
    pub kind: String,
    pub connector_id: String,
    pub operation: String,
    pub account_id: String,
    pub resource: FoundationActionResource,
    pub effect: FoundationActionEffect,
    pub idempotency_key: String,
    pub payload: Value,
    pub payload_sha256: String,
    pub preview: FoundationActionPreview,
}

impl FoundationActionEnvelope {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        kind: impl Into<String>,
        connector_id: impl Into<String>,
        operation: impl Into<String>,
        account_id: impl Into<String>,
        resource: FoundationActionResource,
        effect: FoundationActionEffect,
        idempotency_key: impl Into<String>,
        payload: Value,
        preview: FoundationActionPreview,
    ) -> anyhow::Result<Self> {
        let payload_sha256 = immutable_arguments_hash(&payload)?;
        let envelope = Self {
            schema_version: FOUNDATION_ACTION_SCHEMA_VERSION,
            kind: kind.into(),
            connector_id: connector_id.into(),
            operation: operation.into(),
            account_id: account_id.into(),
            resource,
            effect,
            idempotency_key: idempotency_key.into(),
            payload,
            payload_sha256,
            preview,
        };
        envelope.validate()?;
        Ok(envelope)
    }

    pub fn validate(&self) -> anyhow::Result<()> {
        anyhow::ensure!(
            self.schema_version == FOUNDATION_ACTION_SCHEMA_VERSION,
            "unsupported Foundation Action envelope version"
        );
        validate_kind(&self.kind)?;
        validate_identifier(&self.connector_id, "connector id")?;
        validate_identifier(&self.operation, "connector operation")?;
        validate_bounded_text(&self.account_id, 255, "connector account id")?;
        self.resource.validate()?;
        validate_bounded_text(&self.idempotency_key, 512, "action idempotency key")?;
        anyhow::ensure!(self.payload.is_object(), "action payload must be an object");
        anyhow::ensure!(
            serde_json::to_vec(&self.payload)?.len() <= MAX_PAYLOAD_BYTES,
            "action payload exceeds limit"
        );
        anyhow::ensure!(
            self.payload_sha256 == immutable_arguments_hash(&self.payload)?,
            "action payload hash does not match payload"
        );
        self.preview.validate()?;
        anyhow::ensure!(
            self.resource_target().len() <= 1024,
            "action resource target is too long"
        );
        Ok(())
    }

    pub fn envelope_sha256(&self) -> anyhow::Result<String> {
        self.validate()?;
        immutable_arguments_hash(&serde_json::to_value(self)?)
    }

    pub fn resource_target(&self) -> String {
        format!(
            "connector:{}:account:{}:resource:{}:{}",
            self.connector_id,
            self.account_id,
            self.resource.resource_type,
            self.resource.resource_id
        )
    }

    pub fn from_action(action: &DurableAction) -> anyhow::Result<Self> {
        let envelope: Self = serde_json::from_value(action.arguments.clone())?;
        envelope.validate()?;
        anyhow::ensure!(
            envelope.kind == action.action_name
                && envelope.idempotency_key == action.idempotency_key
                && envelope.resource_target() == action.resource_target
                && envelope.envelope_sha256()? == action.arguments_sha256,
            "persisted Foundation Action envelope binding is invalid"
        );
        Ok(envelope)
    }
}

pub struct FoundationActionRequest {
    pub scope: RunScope,
    pub envelope: FoundationActionEnvelope,
    pub policy_version: String,
    pub expires_at: DateTime<Utc>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct PendingFoundationActionEnvelope {
    pub run: DurableRun,
    pub action: DurableAction,
    pub approval: ApprovalRecord,
    pub envelope: FoundationActionEnvelope,
    pub replayed: bool,
}

#[derive(Clone)]
pub struct DurableFoundationActionStore {
    store: DurableRunStore,
}

impl DurableFoundationActionStore {
    pub async fn from_storage(storage: &Storage) -> anyhow::Result<Self> {
        let store = DurableRunStore::from_storage(storage).await?;
        let service = Self { store };
        service.migrate().await?;
        Ok(service)
    }

    pub async fn request(
        &self,
        request: FoundationActionRequest,
        now: DateTime<Utc>,
    ) -> anyhow::Result<PendingFoundationActionEnvelope> {
        validate_request(&request, now)?;
        let envelope_value = serde_json::to_value(&request.envelope)?;
        let envelope_sha256 = request.envelope.envelope_sha256()?;
        let session_key = session_key(&request.scope)?;
        let operation_id = Uuid::new_v4().to_string();
        let run_id = Uuid::new_v4().to_string();
        let step_id = Uuid::new_v4().to_string();
        let action_id = Uuid::new_v4().to_string();
        let approval_id = Uuid::new_v4().to_string();
        let resource_target = request.envelope.resource_target();
        let binding = ApprovalBinding {
            actor_id: request.scope.user_id.clone(),
            app_id: request.scope.app_id.clone(),
            run_id: run_id.clone(),
            action_id: action_id.clone(),
            action_name: request.envelope.kind.clone(),
            arguments_sha256: envelope_sha256.clone(),
            resource_target: resource_target.clone(),
            policy_version: request.policy_version.clone(),
            risk: request.envelope.effect.approval_risk(),
            risk_summary: request.envelope.preview.summary.clone(),
            session_id: request.scope.session_id.clone(),
            expires_at: request.expires_at,
        };
        binding.validate()?;

        let mut tx = self.store.pool().begin().await?;
        let inserted = sqlx::query(
            r#"INSERT OR IGNORE INTO foundation_action_requests(
                app_id, agent_id, tenant_id, user_id, session_key, action_kind,
                idempotency_key, envelope_sha256, operation_id, run_id, action_id,
                approval_id, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL, ?)"#,
        )
        .bind(&request.scope.app_id)
        .bind(&request.scope.agent_id)
        .bind(&request.scope.tenant_id)
        .bind(&request.scope.user_id)
        .bind(&session_key)
        .bind(&request.envelope.kind)
        .bind(&request.envelope.idempotency_key)
        .bind(&envelope_sha256)
        .bind(&operation_id)
        .bind(now.to_rfc3339())
        .execute(&mut *tx)
        .await?;
        if inserted.rows_affected() == 0 {
            let row = load_registry_row(
                &mut tx,
                &request.scope,
                &session_key,
                &request.envelope.kind,
                &request.envelope.idempotency_key,
            )
            .await?;
            anyhow::ensure!(
                row.envelope_sha256 == envelope_sha256,
                "Foundation Action idempotency key conflicts with another envelope"
            );
            tx.commit().await?;
            return self
                .load_registered(
                    row,
                    &request.scope,
                    &request.policy_version,
                    request.envelope,
                    true,
                )
                .await;
        }

        let checkpoint = json!({"actionId": action_id, "approvalId": approval_id});
        sqlx::query(
            r#"INSERT INTO durable_runs(
                run_id, app_id, agent_id, tenant_id, user_id, session_id, objective,
                status, checkpoint_json, version, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, 'waiting_approval', ?, 3, ?, ?)"#,
        )
        .bind(&run_id)
        .bind(&request.scope.app_id)
        .bind(&request.scope.agent_id)
        .bind(&request.scope.tenant_id)
        .bind(&request.scope.user_id)
        .bind(&request.scope.session_id)
        .bind(format!(
            "Execute Foundation Action {}",
            request.envelope.kind
        ))
        .bind(serde_json::to_string(&checkpoint)?)
        .bind(now.to_rfc3339())
        .bind(now.to_rfc3339())
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            r#"INSERT INTO run_steps(
                step_id, run_id, sequence, kind, status, input_json, output_json,
                error_json, attempt_count, version, created_at, updated_at
            ) VALUES (?, ?, 0, ?, 'waiting_approval', ?, NULL, NULL, 0, 1, ?, ?)"#,
        )
        .bind(&step_id)
        .bind(&run_id)
        .bind(&request.envelope.kind)
        .bind(serde_json::to_string(&envelope_value)?)
        .bind(now.to_rfc3339())
        .bind(now.to_rfc3339())
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            r#"INSERT INTO durable_actions(
                action_id, run_id, step_id, action_name, arguments_json,
                arguments_sha256, resource_target, idempotency_key, status,
                approval_id, result_json, last_error, version, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'waiting_approval', ?, NULL, NULL, 2, ?, ?)"#,
        )
        .bind(&action_id)
        .bind(&run_id)
        .bind(&step_id)
        .bind(&request.envelope.kind)
        .bind(serde_json::to_string(&envelope_value)?)
        .bind(&envelope_sha256)
        .bind(&resource_target)
        .bind(&request.envelope.idempotency_key)
        .bind(&approval_id)
        .bind(now.to_rfc3339())
        .bind(now.to_rfc3339())
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            r#"INSERT INTO run_approvals(
                approval_id, run_id, action_id, binding_json, status, decision,
                resolved_by, resolved_at, consumed_at, created_at
            ) VALUES (?, ?, ?, ?, 'pending', NULL, NULL, NULL, NULL, ?)"#,
        )
        .bind(&approval_id)
        .bind(&run_id)
        .bind(&action_id)
        .bind(serde_json::to_string(&binding)?)
        .bind(now.to_rfc3339())
        .execute(&mut *tx)
        .await?;
        let completed = sqlx::query(
            r#"UPDATE foundation_action_requests
            SET run_id = ?, action_id = ?, approval_id = ?
            WHERE app_id = ? AND agent_id = ? AND tenant_id = ? AND user_id = ?
                AND session_key = ? AND action_kind = ? AND idempotency_key = ?
                AND operation_id = ? AND run_id IS NULL AND action_id IS NULL
                AND approval_id IS NULL"#,
        )
        .bind(&run_id)
        .bind(&action_id)
        .bind(&approval_id)
        .bind(&request.scope.app_id)
        .bind(&request.scope.agent_id)
        .bind(&request.scope.tenant_id)
        .bind(&request.scope.user_id)
        .bind(&session_key)
        .bind(&request.envelope.kind)
        .bind(&request.envelope.idempotency_key)
        .bind(&operation_id)
        .execute(&mut *tx)
        .await?;
        anyhow::ensure!(
            completed.rows_affected() == 1,
            "Foundation Action request ownership changed"
        );
        tx.commit().await?;
        self.load_registered(
            RegistryRow {
                envelope_sha256,
                run_id: Some(run_id),
                action_id: Some(action_id),
                approval_id: Some(approval_id),
            },
            &request.scope,
            &request.policy_version,
            request.envelope,
            false,
        )
        .await
    }

    async fn load_registered(
        &self,
        row: RegistryRow,
        expected_scope: &RunScope,
        expected_policy_version: &str,
        expected: FoundationActionEnvelope,
        replayed: bool,
    ) -> anyhow::Result<PendingFoundationActionEnvelope> {
        let run_id = required_registry_id(row.run_id, "run")?;
        let action_id = required_registry_id(row.action_id, "action")?;
        let approval_id = required_registry_id(row.approval_id, "approval")?;
        let run = self
            .store
            .get_run(&run_id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("registered Foundation Action run is missing"))?;
        let mut action = self
            .store
            .get_action(&action_id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("registered Foundation Action is missing"))?;
        let approval = self
            .store
            .get_approval(&approval_id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("registered Foundation Action approval is missing"))?;
        let envelope = FoundationActionEnvelope::from_action(&action)?;
        anyhow::ensure!(
            run.scope == *expected_scope
                && envelope == expected
                && envelope.envelope_sha256()? == row.envelope_sha256
                && action.run_id == run.run_id
                && action.approval_id.as_deref() == Some(&approval.approval_id)
                && approval.binding.actor_id == expected_scope.user_id
                && approval.binding.app_id == expected_scope.app_id
                && approval.binding.run_id == run.run_id
                && approval.binding.action_id == action.action_id
                && approval.binding.action_name == envelope.kind
                && approval.binding.arguments_sha256 == row.envelope_sha256
                && approval.binding.resource_target == envelope.resource_target()
                && approval.binding.policy_version == expected_policy_version
                && approval.binding.risk == envelope.effect.approval_risk()
                && approval.binding.risk_summary == envelope.preview.summary
                && approval.binding.session_id == expected_scope.session_id,
            "registered Foundation Action binding is invalid"
        );
        action.replayed = replayed;
        Ok(PendingFoundationActionEnvelope {
            run,
            action,
            approval,
            envelope,
            replayed,
        })
    }

    async fn migrate(&self) -> anyhow::Result<()> {
        let mut tx = self.store.pool().begin().await?;
        sqlx::query(
            "CREATE TABLE IF NOT EXISTS foundation_action_schema(version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL)",
        )
        .execute(&mut *tx)
        .await?;
        let future: Option<i64> = sqlx::query_scalar(
            "SELECT MAX(version) FROM foundation_action_schema WHERE version > ?",
        )
        .bind(FOUNDATION_ACTION_STORE_VERSION)
        .fetch_one(&mut *tx)
        .await?;
        anyhow::ensure!(
            future.is_none(),
            "Foundation Action schema is newer than this runtime"
        );
        sqlx::query(
            r#"CREATE TABLE IF NOT EXISTS foundation_action_requests(
                app_id TEXT NOT NULL, agent_id TEXT NOT NULL, tenant_id TEXT NOT NULL,
                user_id TEXT NOT NULL, session_key TEXT NOT NULL, action_kind TEXT NOT NULL,
                idempotency_key TEXT NOT NULL, envelope_sha256 TEXT NOT NULL,
                operation_id TEXT NOT NULL, run_id TEXT, action_id TEXT, approval_id TEXT,
                created_at TEXT NOT NULL,
                PRIMARY KEY(app_id, agent_id, tenant_id, user_id, session_key,
                    action_kind, idempotency_key),
                CHECK ((run_id IS NULL AND action_id IS NULL AND approval_id IS NULL)
                    OR (run_id IS NOT NULL AND action_id IS NOT NULL AND approval_id IS NOT NULL))
            )"#,
        )
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            "INSERT OR IGNORE INTO foundation_action_schema(version, applied_at) VALUES (?, ?)",
        )
        .bind(FOUNDATION_ACTION_STORE_VERSION)
        .bind(Utc::now().to_rfc3339())
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        Ok(())
    }
}

struct RegistryRow {
    envelope_sha256: String,
    run_id: Option<String>,
    action_id: Option<String>,
    approval_id: Option<String>,
}

async fn load_registry_row(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    scope: &RunScope,
    session_key: &str,
    action_kind: &str,
    idempotency_key: &str,
) -> anyhow::Result<RegistryRow> {
    let row = sqlx::query(
        r#"SELECT envelope_sha256, run_id, action_id, approval_id
        FROM foundation_action_requests
        WHERE app_id = ? AND agent_id = ? AND tenant_id = ? AND user_id = ?
            AND session_key = ? AND action_kind = ? AND idempotency_key = ?"#,
    )
    .bind(&scope.app_id)
    .bind(&scope.agent_id)
    .bind(&scope.tenant_id)
    .bind(&scope.user_id)
    .bind(session_key)
    .bind(action_kind)
    .bind(idempotency_key)
    .fetch_one(&mut **tx)
    .await?;
    Ok(RegistryRow {
        envelope_sha256: row.try_get("envelope_sha256")?,
        run_id: row.try_get("run_id")?,
        action_id: row.try_get("action_id")?,
        approval_id: row.try_get("approval_id")?,
    })
}

fn validate_request(request: &FoundationActionRequest, now: DateTime<Utc>) -> anyhow::Result<()> {
    for value in [
        &request.scope.app_id,
        &request.scope.agent_id,
        &request.scope.tenant_id,
        &request.scope.user_id,
    ] {
        validate_bounded_text(value, 255, "Foundation Action scope")?;
    }
    session_key(&request.scope)?;
    request.envelope.validate()?;
    validate_bounded_text(
        &request.policy_version,
        1024,
        "Foundation Action policy version",
    )?;
    anyhow::ensure!(
        request.expires_at > now,
        "Foundation Action approval expiry must be in the future"
    );
    anyhow::ensure!(
        request.expires_at <= now + Duration::hours(24),
        "Foundation Action approval expiry exceeds limit"
    );
    Ok(())
}

fn session_key(scope: &RunScope) -> anyhow::Result<String> {
    match &scope.session_id {
        Some(session_id) => {
            validate_bounded_text(session_id, 255, "Foundation Action session id")?;
            Ok(format!("session:{session_id}"))
        }
        None => Ok("global".into()),
    }
}

fn required_registry_id(value: Option<String>, kind: &str) -> anyhow::Result<String> {
    value.ok_or_else(|| anyhow::anyhow!("registered Foundation Action {kind} is incomplete"))
}

fn validate_kind(value: &str) -> anyhow::Result<()> {
    validate_identifier(value, "Foundation Action kind")?;
    anyhow::ensure!(
        value.contains('.'),
        "Foundation Action kind must be namespaced"
    );
    Ok(())
}

fn validate_identifier(value: &str, name: &str) -> anyhow::Result<()> {
    anyhow::ensure!(
        !value.is_empty()
            && value.len() <= 255
            && value.bytes().all(|byte| {
                byte.is_ascii_lowercase()
                    || byte.is_ascii_digit()
                    || matches!(byte, b'.' | b'_' | b'-')
            })
            && value.as_bytes().first().is_some_and(u8::is_ascii_lowercase),
        "{name} is invalid"
    );
    Ok(())
}

fn validate_bounded_text(value: &str, max: usize, name: &str) -> anyhow::Result<()> {
    anyhow::ensure!(!value.trim().is_empty(), "{name} is required");
    anyhow::ensure!(value.len() <= max, "{name} is too long");
    anyhow::ensure!(
        !value.chars().any(char::is_control),
        "{name} contains control characters"
    );
    Ok(())
}

#[cfg(test)]
#[path = "foundation_action_envelope_tests.rs"]
mod tests;
