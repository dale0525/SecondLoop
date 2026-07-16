use crate::event_persistence::project_runtime_event_for_persistence;
use crate::events::RuntimeEvent;
use crate::session::ConversationScope;
use crate::storage::Storage;
use crate::structured_content::{
    StructuredActionBindingRequest, StructuredActionBindingView, StructuredActionExecution,
    StructuredActionIntent, StructuredActionReceipt, StructuredContent, StructuredContentAudience,
    validate_id, validate_input, validate_public_payload,
};
use crate::structured_content_error::StructuredContentError;
#[cfg(test)]
use crate::structured_content_payload::AGENTWEAVE_CARD_MIME;
use crate::structured_content_payload::{supports_interactive_mime, validate_payload_for_mime};
use crate::structured_content_preview::apply_authoritative_action_preview as preview;
use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest, Sha256};
use sqlx::{Row, Sqlite, Transaction};
use std::collections::{BTreeMap, BTreeSet};
use std::str::FromStr;
use uuid::Uuid;
const ACTION_LEASE_SECONDS: i64 = 120;
#[path = "structured_content_updates.rs"]
mod updates;
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PublishStructuredContentRequest {
    #[serde(default)]
    pub content_id: Option<String>,
    #[serde(default)]
    pub expected_revision: Option<u64>,
    pub mime_type: String,
    pub schema_version: String,
    pub payload: Value,
    pub fallback_text: String,
    #[serde(default = "default_audience")]
    pub audience: StructuredContentAudience,
    #[serde(default)]
    pub bindings: Vec<StructuredActionBindingRequest>,
}
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PublishedStructuredContent {
    pub content: StructuredContent,
    pub bindings: Vec<StructuredActionBindingView>,
}
#[derive(Clone, Debug, PartialEq)]
pub enum StructuredActionClaim {
    Execute(StructuredActionExecution),
    Replay(StructuredActionReceipt),
}
#[derive(Clone)]
pub struct StructuredContentService {
    storage: Storage,
    scope: ConversationScope,
    owner: String,
}
impl StructuredContentService {
    pub fn new(
        storage: Storage,
        scope: ConversationScope,
        owner: impl Into<String>,
    ) -> anyhow::Result<Self> {
        scope.validate()?;
        let owner = owner.into();
        validate_id(&owner, "content owner")?;
        Ok(Self {
            storage,
            scope,
            owner,
        })
    }

    pub async fn publish(
        &self,
        session_id: &str,
        turn_id: Option<&str>,
        request: PublishStructuredContentRequest,
        now: DateTime<Utc>,
    ) -> anyhow::Result<PublishedStructuredContent> {
        validate_session_id(session_id)?;
        if let Some(turn_id) = turn_id {
            validate_id(turn_id, "turn id")?;
        }
        anyhow::ensure!(
            request.bindings.len() <= 16,
            "too many structured action bindings"
        );
        for binding in &request.bindings {
            binding.validate(now)?;
        }
        let payload = preview(&request.mime_type, request.payload, &request.bindings, now)?;
        validate_binding_action_ids(&payload, &request.bindings, &request.mime_type)?;
        let content_id = request
            .content_id
            .unwrap_or_else(|| Uuid::new_v4().to_string());
        validate_id(&content_id, "content id")?;

        let mut tx = self.storage.pool().begin_with("BEGIN IMMEDIATE").await?;
        ensure_scoped_session(&mut tx, &self.scope, session_id).await?;
        let previous = content_state(&mut tx, session_id, &content_id).await?;
        ensure_no_executing_action(&mut tx, session_id, &content_id, now).await?;
        let revision = match previous {
            None => {
                anyhow::ensure!(
                    request.expected_revision.is_none(),
                    "initial structured content cannot have an expected revision"
                );
                1
            }
            Some((owner, revision, deleted, _)) => {
                anyhow::ensure!(
                    owner == self.owner,
                    "structured content owner cannot change"
                );
                anyhow::ensure!(
                    !deleted,
                    "deleted structured content identifier cannot be reused"
                );
                anyhow::ensure!(
                    request.expected_revision == Some(revision),
                    "structured content revision conflict"
                );
                revision + 1
            }
        };
        let binding_ids = request
            .bindings
            .iter()
            .map(|binding| (binding.action_id.clone(), Uuid::new_v4().to_string()))
            .collect::<BTreeMap<_, _>>();
        let payload = attach_public_binding_ids(payload, &binding_ids)?;
        validate_payload_for_mime(&request.mime_type, &request.schema_version, &payload)?;
        let content = StructuredContent {
            content_id: content_id.clone(),
            mime_type: request.mime_type,
            schema_version: request.schema_version,
            payload,
            fallback_text: request.fallback_text,
            audience: request.audience,
            owner: self.owner.clone(),
            revision,
        };
        content.validate()?;
        let content_json = serde_json::to_string(&content)?;
        sqlx::query(
            r#"INSERT INTO structured_content_state
               (session_id, content_id, owner, revision, deleted, content_json, updated_at)
               VALUES (?, ?, ?, ?, 0, ?, ?)
               ON CONFLICT(session_id, content_id) DO UPDATE SET
                 owner = excluded.owner,
                 revision = excluded.revision,
                 deleted = 0,
                 content_json = excluded.content_json,
                 updated_at = excluded.updated_at"#,
        )
        .bind(session_id)
        .bind(&content_id)
        .bind(&self.owner)
        .bind(i64::try_from(revision)?)
        .bind(content_json)
        .bind(now.to_rfc3339())
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            "UPDATE structured_action_bindings SET state = 'superseded', updated_at = ? WHERE session_id = ? AND content_id = ? AND state = 'pending'",
        )
        .bind(now.to_rfc3339())
        .bind(session_id)
        .bind(&content_id)
        .execute(&mut *tx)
        .await?;
        let mut views = Vec::with_capacity(request.bindings.len());
        for binding in request.bindings {
            let binding_id = binding_ids
                .get(&binding.action_id)
                .expect("validated binding identifier")
                .clone();
            insert_binding(
                &mut tx,
                session_id,
                &content_id,
                revision,
                &binding_id,
                &binding,
                now,
            )
            .await?;
            views.push(StructuredActionBindingView {
                binding_id,
                action_id: binding.action_id,
                intent: binding.intent,
                expires_at: binding.expires_at,
            });
        }
        append_session_event(
            &mut tx,
            session_id,
            turn_id,
            &RuntimeEvent::StructuredContentPublished {
                content: content.clone(),
            },
            now,
        )
        .await?;
        tx.commit().await?;
        Ok(PublishedStructuredContent {
            content,
            bindings: views,
        })
    }

    pub async fn delete(
        &self,
        session_id: &str,
        turn_id: Option<&str>,
        content_id: &str,
        expected_revision: u64,
        now: DateTime<Utc>,
    ) -> anyhow::Result<bool> {
        validate_session_id(session_id)?;
        validate_id(content_id, "content id")?;
        anyhow::ensure!(
            expected_revision > 0,
            "structured content revision is invalid"
        );
        let mut tx = self.storage.pool().begin_with("BEGIN IMMEDIATE").await?;
        ensure_scoped_session(&mut tx, &self.scope, session_id).await?;
        let Some((owner, current_revision, deleted, content_json)) =
            content_state(&mut tx, session_id, content_id).await?
        else {
            tx.rollback().await?;
            return Ok(false);
        };
        anyhow::ensure!(owner == self.owner, "structured content owner mismatch");
        if deleted {
            tx.rollback().await?;
            return Ok(false);
        }
        let audience = serde_json::from_str::<StructuredContent>(
            content_json
                .as_deref()
                .ok_or_else(|| anyhow::anyhow!("structured content payload is missing"))?,
        )?
        .audience;
        ensure_no_executing_action(&mut tx, session_id, content_id, now).await?;
        anyhow::ensure!(
            current_revision == expected_revision,
            "structured content revision conflict"
        );
        let tombstone_revision = current_revision + 1;
        sqlx::query(
            "UPDATE structured_content_state SET revision = ?, deleted = 1, content_json = NULL, updated_at = ? WHERE session_id = ? AND content_id = ? AND revision = ? AND deleted = 0",
        )
        .bind(i64::try_from(tombstone_revision)?)
        .bind(now.to_rfc3339())
        .bind(session_id)
        .bind(content_id)
        .bind(i64::try_from(current_revision)?)
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            "UPDATE structured_action_bindings SET state = 'cancelled', updated_at = ? WHERE session_id = ? AND content_id = ? AND state = 'pending'",
        )
        .bind(now.to_rfc3339())
        .bind(session_id)
        .bind(content_id)
        .execute(&mut *tx)
        .await?;
        append_session_event(
            &mut tx,
            session_id,
            turn_id,
            &RuntimeEvent::StructuredContentDeleted {
                content_id: content_id.to_string(),
                owner: self.owner.clone(),
                revision: tombstone_revision,
                audience,
            },
            now,
        )
        .await?;
        tx.commit().await?;
        Ok(true)
    }

    pub async fn get(
        &self,
        session_id: &str,
        content_id: &str,
    ) -> anyhow::Result<Option<StructuredContent>> {
        validate_session_id(session_id)?;
        validate_id(content_id, "content id")?;
        let value: Option<String> = sqlx::query_scalar(
            "SELECT c.content_json FROM structured_content_state c INNER JOIN sessions s ON s.id = c.session_id WHERE c.session_id = ? AND c.content_id = ? AND c.deleted = 0 AND s.app_id = ? AND s.agent_id = ? AND s.tenant_id = ? AND s.user_id = ? AND s.device_id = ?",
        )
        .bind(session_id)
        .bind(content_id)
        .bind(&self.scope.app_id)
        .bind(&self.scope.agent_id)
        .bind(&self.scope.tenant_id)
        .bind(&self.scope.user_id)
        .bind(&self.scope.device_id)
        .fetch_optional(self.storage.pool())
        .await?
        .flatten();
        value
            .map(|value| serde_json::from_str(&value).map_err(Into::into))
            .transpose()
    }

    pub async fn replay(
        &self,
        session_id: &str,
        audience: StructuredContentAudience,
    ) -> anyhow::Result<Vec<StructuredContent>> {
        validate_session_id(session_id)
            .map_err(|error| StructuredContentError::invalid(error.to_string()))?;
        let rows = sqlx::query(
            "SELECT c.content_json FROM structured_content_state c INNER JOIN sessions s ON s.id = c.session_id WHERE c.session_id = ? AND c.deleted = 0 AND s.app_id = ? AND s.agent_id = ? AND s.tenant_id = ? AND s.user_id = ? AND s.device_id = ? ORDER BY c.updated_at, c.content_id",
        )
        .bind(session_id)
        .bind(&self.scope.app_id)
        .bind(&self.scope.agent_id)
        .bind(&self.scope.tenant_id)
        .bind(&self.scope.user_id)
        .bind(&self.scope.device_id)
        .fetch_all(self.storage.pool())
        .await?;
        let mut content = Vec::new();
        for row in rows {
            let value: String = row.try_get("content_json")?;
            let item: StructuredContent = serde_json::from_str(&value)?;
            if item.audience == audience {
                content.push(item);
            }
        }
        Ok(content)
    }

    pub async fn claim_action(
        &self,
        session_id: &str,
        binding_id: &str,
        input: Value,
        now: DateTime<Utc>,
    ) -> anyhow::Result<StructuredActionClaim> {
        validate_session_id(session_id)
            .map_err(|error| StructuredContentError::invalid(error.to_string()))?;
        validate_id(binding_id, "action binding id")
            .map_err(|error| StructuredContentError::invalid(error.to_string()))?;
        let mut tx = self.storage.pool().begin_with("BEGIN IMMEDIATE").await?;
        ensure_scoped_session(&mut tx, &self.scope, session_id).await?;
        if let Some(receipt) =
            receipt_for_binding(&mut tx, &self.scope, session_id, binding_id).await?
        {
            tx.commit().await?;
            return Ok(StructuredActionClaim::Replay(StructuredActionReceipt {
                replayed: true,
                ..receipt
            }));
        }
        let row = sqlx::query(
            "SELECT b.* FROM structured_action_bindings b INNER JOIN structured_content_state c ON c.session_id = b.session_id AND c.content_id = b.content_id WHERE b.binding_id = ? AND b.session_id = ? AND c.deleted = 0",
        )
        .bind(binding_id)
        .bind(session_id)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or_else(|| {
            StructuredContentError::not_found("structured action binding is unavailable")
        })?;
        let expires_at = parse_time(&row.try_get::<String, _>("expires_at")?)?;
        anyhow::ensure!(
            expires_at > now,
            StructuredContentError::expired("structured action binding expired")
        );
        let state: String = row.try_get("state")?;
        let lease_expires_at = row
            .try_get::<Option<String>, _>("lease_expires_at")?
            .as_deref()
            .map(parse_time)
            .transpose()?;
        anyhow::ensure!(
            state == "pending"
                || (state == "executing" && lease_expires_at.is_some_and(|lease| lease <= now)),
            StructuredContentError::conflict("structured action binding is not executable")
        );
        let content_id: String = row.try_get("content_id")?;
        let content_revision = u64::try_from(row.try_get::<i64, _>("content_revision")?)?;
        let current_revision: i64 = sqlx::query_scalar(
            "SELECT revision FROM structured_content_state WHERE session_id = ? AND content_id = ? AND deleted = 0",
        )
        .bind(session_id)
        .bind(&content_id)
        .fetch_one(&mut *tx)
        .await?;
        anyhow::ensure!(
            u64::try_from(current_revision)? == content_revision,
            StructuredContentError::conflict("structured action revision is stale")
        );
        let input_schema: Value =
            serde_json::from_str(&row.try_get::<String, _>("input_schema_json")?)?;
        validate_input(&input_schema, &input)
            .map_err(|error| StructuredContentError::invalid(error.to_string()))?;
        release_expired_content_claims(&mut tx, session_id, &content_id, now).await?;
        let lease_expires_at = now + Duration::seconds(ACTION_LEASE_SECONDS);
        let claim_token = Uuid::new_v4().to_string();
        let claim_epoch = u64::try_from(row.try_get::<i64, _>("claim_epoch")?)?
            .checked_add(1)
            .ok_or_else(|| anyhow::anyhow!("structured action claim epoch overflow"))?;
        let updated = sqlx::query(
            r#"UPDATE structured_action_bindings
               SET state = 'executing', lease_expires_at = ?, claim_token = ?,
                   claim_epoch = ?, updated_at = ?
               WHERE binding_id = ? AND session_id = ? AND content_id = ? AND state = 'pending'
                 AND NOT EXISTS(
                     SELECT 1 FROM structured_action_bindings active
                     WHERE active.session_id = ? AND active.content_id = ?
                       AND active.state = 'executing'
                 )"#,
        )
        .bind(lease_expires_at.to_rfc3339())
        .bind(&claim_token)
        .bind(i64::try_from(claim_epoch)?)
        .bind(now.to_rfc3339())
        .bind(binding_id)
        .bind(session_id)
        .bind(&content_id)
        .bind(session_id)
        .bind(&content_id)
        .execute(&mut *tx)
        .await?;
        anyhow::ensure!(
            updated.rows_affected() == 1,
            StructuredContentError::conflict("structured action claim conflict")
        );
        let execution = StructuredActionExecution {
            binding_id: binding_id.to_string(),
            claim_token,
            claim_epoch,
            session_id: session_id.to_string(),
            content_id,
            content_revision,
            action_id: row.try_get("action_id")?,
            intent: StructuredActionIntent::from_str(&row.try_get::<String, _>("intent")?)?,
            parameters: serde_json::from_str(&row.try_get::<String, _>("parameters_json")?)?,
            input,
            constraints: serde_json::from_str(&row.try_get::<String, _>("constraints_json")?)?,
            idempotency_key: row.try_get("idempotency_key")?,
        };
        tx.commit().await?;
        Ok(StructuredActionClaim::Execute(execution))
    }

    pub async fn complete_action(
        &self,
        execution: &StructuredActionExecution,
        result: Value,
        now: DateTime<Utc>,
    ) -> anyhow::Result<StructuredActionReceipt> {
        validate_public_payload(&result)?;
        let mut tx = self.storage.pool().begin_with("BEGIN IMMEDIATE").await?;
        ensure_scoped_session(&mut tx, &self.scope, &execution.session_id).await?;
        let row = sqlx::query(
            r#"SELECT b.state, b.claim_token, b.claim_epoch, b.content_id, b.action_id,
                      b.intent, b.lease_expires_at
               FROM structured_action_bindings b
               INNER JOIN sessions s ON s.id = b.session_id
               WHERE b.binding_id = ? AND b.session_id = ?
                 AND s.app_id = ? AND s.agent_id = ? AND s.tenant_id = ?
                 AND s.user_id = ? AND s.device_id = ?"#,
        )
        .bind(&execution.binding_id)
        .bind(&execution.session_id)
        .bind(&self.scope.app_id)
        .bind(&self.scope.agent_id)
        .bind(&self.scope.tenant_id)
        .bind(&self.scope.user_id)
        .bind(&self.scope.device_id)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or_else(|| {
            StructuredContentError::not_found("structured action binding is unavailable")
        })?;
        let state: String = row.try_get("state")?;
        let claim_token: Option<String> = row.try_get("claim_token")?;
        let claim_epoch = u64::try_from(row.try_get::<i64, _>("claim_epoch")?)?;
        anyhow::ensure!(
            claim_token.as_deref() == Some(&execution.claim_token)
                && claim_epoch == execution.claim_epoch,
            StructuredContentError::conflict("structured action claim conflict")
        );
        anyhow::ensure!(
            row.try_get::<String, _>("content_id")? == execution.content_id
                && row.try_get::<String, _>("action_id")? == execution.action_id
                && StructuredActionIntent::from_str(&row.try_get::<String, _>("intent")?)?
                    == execution.intent,
            StructuredContentError::conflict(
                "structured action execution does not match its binding"
            )
        );
        if state == "completed" {
            let receipt = receipt_for_binding(
                &mut tx,
                &self.scope,
                &execution.session_id,
                &execution.binding_id,
            )
            .await?
            .ok_or_else(|| anyhow::anyhow!("structured action receipt is missing"))?;
            tx.commit().await?;
            return Ok(StructuredActionReceipt {
                replayed: true,
                ..receipt
            });
        }
        anyhow::ensure!(
            state == "executing",
            StructuredContentError::conflict("structured action is not executing")
        );
        let lease_expires_at = row
            .try_get::<Option<String>, _>("lease_expires_at")?
            .as_deref()
            .map(parse_time)
            .transpose()?;
        anyhow::ensure!(
            lease_expires_at.is_some_and(|lease| lease > now),
            StructuredContentError::conflict("structured action lease expired")
        );
        let receipt = StructuredActionReceipt {
            binding_id: Some(execution.binding_id.clone()),
            action_id: execution.action_id.clone(),
            content_id: execution.content_id.clone(),
            content_revision: execution.content_revision,
            intent: Some(execution.intent),
            replayed: false,
            payload: result,
        };
        let updated = sqlx::query(
            r#"UPDATE structured_action_bindings
               SET state = 'completed', lease_expires_at = NULL, updated_at = ?
               WHERE binding_id = ? AND session_id = ? AND content_id = ?
                 AND state = 'executing' AND claim_token = ? AND claim_epoch = ?"#,
        )
        .bind(now.to_rfc3339())
        .bind(&execution.binding_id)
        .bind(&execution.session_id)
        .bind(&execution.content_id)
        .bind(&execution.claim_token)
        .bind(i64::try_from(execution.claim_epoch)?)
        .execute(&mut *tx)
        .await?;
        anyhow::ensure!(
            updated.rows_affected() == 1,
            StructuredContentError::conflict("structured action completion conflict")
        );
        sqlx::query(
            "INSERT INTO structured_action_receipts(binding_id, result_json, completed_at) VALUES (?, ?, ?)",
        )
        .bind(&execution.binding_id)
        .bind(serde_json::to_string(&receipt)?)
        .bind(now.to_rfc3339())
        .execute(&mut *tx)
        .await?;
        append_session_event(
            &mut tx,
            &execution.session_id,
            None,
            &RuntimeEvent::StructuredContentActionAccepted {
                receipt: receipt.clone(),
            },
            now,
        )
        .await?;
        updates::advance_content_for_result(
            &mut tx,
            &execution.session_id,
            &execution.content_id,
            &execution.action_id,
            execution.intent,
            &receipt.payload,
            now + Duration::microseconds(1),
        )
        .await?;
        tx.commit().await?;
        Ok(receipt)
    }

    pub async fn release_action(
        &self,
        execution: &StructuredActionExecution,
        now: DateTime<Utc>,
    ) -> anyhow::Result<()> {
        let mut tx = self.storage.pool().begin_with("BEGIN IMMEDIATE").await?;
        ensure_scoped_session(&mut tx, &self.scope, &execution.session_id).await?;
        let updated = sqlx::query(
            r#"UPDATE structured_action_bindings
               SET state = 'pending', lease_expires_at = NULL, claim_token = NULL, updated_at = ?
               WHERE binding_id = ? AND session_id = ? AND content_id = ?
                 AND state = 'executing' AND claim_token = ? AND claim_epoch = ?"#,
        )
        .bind(now.to_rfc3339())
        .bind(&execution.binding_id)
        .bind(&execution.session_id)
        .bind(&execution.content_id)
        .bind(&execution.claim_token)
        .bind(i64::try_from(execution.claim_epoch)?)
        .execute(&mut *tx)
        .await?;
        anyhow::ensure!(
            updated.rows_affected() == 1,
            StructuredContentError::conflict("structured action release conflict")
        );
        tx.commit().await?;
        Ok(())
    }
}

async fn insert_binding(
    tx: &mut Transaction<'_, Sqlite>,
    session_id: &str,
    content_id: &str,
    content_revision: u64,
    binding_id: &str,
    binding: &StructuredActionBindingRequest,
    now: DateTime<Utc>,
) -> anyhow::Result<()> {
    let parameters_json = serde_json::to_string(&binding.parameters)?;
    let parameters_sha256 = hex::encode(Sha256::digest(parameters_json.as_bytes()));
    sqlx::query(
        r#"INSERT INTO structured_action_bindings
           (binding_id, session_id, content_id, content_revision, action_id, intent,
            parameters_json, parameters_sha256, input_schema_json, constraints_json,
            expires_at, idempotency_key, state, lease_expires_at, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', NULL, ?, ?)"#,
    )
    .bind(binding_id)
    .bind(session_id)
    .bind(content_id)
    .bind(i64::try_from(content_revision)?)
    .bind(&binding.action_id)
    .bind(binding.intent.as_str())
    .bind(parameters_json)
    .bind(parameters_sha256)
    .bind(serde_json::to_string(&binding.input_schema)?)
    .bind(serde_json::to_string(&binding.constraints)?)
    .bind(binding.expires_at.to_rfc3339())
    .bind(&binding.idempotency_key)
    .bind(now.to_rfc3339())
    .bind(now.to_rfc3339())
    .execute(&mut **tx)
    .await?;
    Ok(())
}

async fn content_state(
    tx: &mut Transaction<'_, Sqlite>,
    session_id: &str,
    content_id: &str,
) -> anyhow::Result<Option<(String, u64, bool, Option<String>)>> {
    let row = sqlx::query(
        "SELECT owner, revision, deleted, content_json FROM structured_content_state WHERE session_id = ? AND content_id = ?",
    )
    .bind(session_id)
    .bind(content_id)
    .fetch_optional(&mut **tx)
    .await?;
    row.map(|row| {
        Ok((
            row.try_get("owner")?,
            u64::try_from(row.try_get::<i64, _>("revision")?)?,
            row.try_get::<i64, _>("deleted")? != 0,
            row.try_get("content_json")?,
        ))
    })
    .transpose()
}

async fn receipt_for_binding(
    tx: &mut Transaction<'_, Sqlite>,
    scope: &ConversationScope,
    session_id: &str,
    binding_id: &str,
) -> anyhow::Result<Option<StructuredActionReceipt>> {
    let value: Option<String> = sqlx::query_scalar(
        r#"SELECT r.result_json
           FROM structured_action_receipts r
           INNER JOIN structured_action_bindings b ON b.binding_id = r.binding_id
           INNER JOIN sessions s ON s.id = b.session_id
           WHERE r.binding_id = ? AND b.session_id = ?
             AND s.app_id = ? AND s.agent_id = ? AND s.tenant_id = ?
             AND s.user_id = ? AND s.device_id = ?"#,
    )
    .bind(binding_id)
    .bind(session_id)
    .bind(&scope.app_id)
    .bind(&scope.agent_id)
    .bind(&scope.tenant_id)
    .bind(&scope.user_id)
    .bind(&scope.device_id)
    .fetch_optional(&mut **tx)
    .await?;
    value
        .map(|value| serde_json::from_str(&value).map_err(Into::into))
        .transpose()
}

async fn ensure_scoped_session(
    tx: &mut Transaction<'_, Sqlite>,
    scope: &ConversationScope,
    session_id: &str,
) -> anyhow::Result<()> {
    let exists: i64 = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM sessions WHERE id = ? AND app_id = ? AND agent_id = ? AND tenant_id = ? AND user_id = ? AND device_id = ?)",
    )
    .bind(session_id)
    .bind(&scope.app_id)
    .bind(&scope.agent_id)
    .bind(&scope.tenant_id)
    .bind(&scope.user_id)
    .bind(&scope.device_id)
    .fetch_one(&mut **tx)
    .await?;
    anyhow::ensure!(
        exists != 0,
        StructuredContentError::not_found("session not found in structured content scope")
    );
    Ok(())
}

async fn ensure_no_executing_action(
    tx: &mut Transaction<'_, Sqlite>,
    session_id: &str,
    content_id: &str,
    now: DateTime<Utc>,
) -> anyhow::Result<()> {
    release_expired_content_claims(tx, session_id, content_id, now).await?;
    let executing: i64 = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM structured_action_bindings WHERE session_id = ? AND content_id = ? AND state = 'executing')",
    )
    .bind(session_id)
    .bind(content_id)
    .fetch_one(&mut **tx)
    .await?;
    anyhow::ensure!(
        executing == 0,
        StructuredContentError::conflict(
            "structured content action is executing; retry after completion"
        )
    );
    Ok(())
}

async fn release_expired_content_claims(
    tx: &mut Transaction<'_, Sqlite>,
    session_id: &str,
    content_id: &str,
    now: DateTime<Utc>,
) -> anyhow::Result<()> {
    sqlx::query(
        r#"UPDATE structured_action_bindings
           SET state = 'pending', lease_expires_at = NULL, claim_token = NULL, updated_at = ?
           WHERE session_id = ? AND content_id = ? AND state = 'executing'
             AND lease_expires_at IS NOT NULL AND lease_expires_at <= ?"#,
    )
    .bind(now.to_rfc3339())
    .bind(session_id)
    .bind(content_id)
    .bind(now.to_rfc3339())
    .execute(&mut **tx)
    .await?;
    Ok(())
}

async fn append_session_event(
    tx: &mut Transaction<'_, Sqlite>,
    session_id: &str,
    turn_id: Option<&str>,
    event: &RuntimeEvent,
    created_at: DateTime<Utc>,
) -> anyhow::Result<()> {
    let event_index: i64 = sqlx::query_scalar(
        "SELECT COALESCE(MAX(event_index) + 1, 0) FROM conversation_events WHERE session_id = ?",
    )
    .bind(session_id)
    .fetch_one(&mut **tx)
    .await?;
    let payload = project_runtime_event_for_persistence(event)?;
    let kind = payload
        .get("type")
        .and_then(Value::as_str)
        .ok_or_else(|| anyhow::anyhow!("structured runtime event has no type"))?;
    sqlx::query(
        "INSERT INTO conversation_events(id, session_id, turn_id, event_index, kind, payload_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
    )
    .bind(Uuid::new_v4().to_string())
    .bind(session_id)
    .bind(turn_id)
    .bind(event_index)
    .bind(kind)
    .bind(serde_json::to_string(&payload)?)
    .bind(created_at.to_rfc3339())
    .execute(&mut **tx)
    .await?;
    Ok(())
}

fn attach_public_binding_ids(
    payload: Value,
    bindings: &BTreeMap<String, String>,
) -> anyhow::Result<Value> {
    let mut payload = payload
        .as_object()
        .cloned()
        .ok_or_else(|| anyhow::anyhow!("structured content payload must be an object"))?;
    anyhow::ensure!(
        !payload.contains_key("actionBindings"),
        "actionBindings is reserved by the runtime"
    );
    if !bindings.is_empty() {
        payload.insert(
            "actionBindings".into(),
            Value::Object(
                bindings
                    .iter()
                    .map(|(action_id, binding_id)| {
                        (action_id.clone(), Value::String(binding_id.clone()))
                    })
                    .collect(),
            ),
        );
    }
    Ok(Value::Object(payload))
}

fn validate_binding_action_ids(
    payload: &Value,
    bindings: &[StructuredActionBindingRequest],
    mime_type: &str,
) -> anyhow::Result<()> {
    let mut binding_ids = BTreeSet::new();
    for binding in bindings {
        anyhow::ensure!(
            binding_ids.insert(binding.action_id.as_str()),
            "duplicate structured action binding"
        );
    }
    if bindings.is_empty() {
        return Ok(());
    }
    anyhow::ensure!(
        supports_interactive_mime(mime_type),
        "interactive actions require a supported structured content MIME type"
    );
    let actions = payload
        .get("actions")
        .and_then(Value::as_array)
        .ok_or_else(|| anyhow::anyhow!("interactive structured content requires actions"))?;
    let action_ids = actions
        .iter()
        .map(|action| {
            action
                .get("id")
                .and_then(Value::as_str)
                .ok_or_else(|| anyhow::anyhow!("structured content action id is invalid"))
        })
        .collect::<anyhow::Result<BTreeSet<_>>>()?;
    anyhow::ensure!(
        action_ids.len() == actions.len(),
        "duplicate structured content action id"
    );
    anyhow::ensure!(
        action_ids == binding_ids,
        "structured content actions and bindings do not match"
    );
    Ok(())
}

fn validate_session_id(value: &str) -> anyhow::Result<()> {
    validate_id(value, "session id")
}

fn parse_time(value: &str) -> anyhow::Result<DateTime<Utc>> {
    Ok(DateTime::parse_from_rfc3339(value)?.with_timezone(&Utc))
}

fn default_audience() -> StructuredContentAudience {
    StructuredContentAudience::User
}

#[cfg(test)]
#[path = "structured_content_store_tests.rs"]
mod tests;
