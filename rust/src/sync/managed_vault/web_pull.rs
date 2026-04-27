use anyhow::{anyhow, Result};
use rusqlite::Connection;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Deserialize)]
pub struct WebPullPage {
    pub generation_id: String,
    pub remote_latest_global_seq: i64,
    pub has_more: bool,
    pub(super) ops: Vec<super::global_log_protocol::GlobalLogPullOp>,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct WebPullState {
    pub generation_id: Option<String>,
    pub last_applied_global_seq: i64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum WebPullRecoveryReason {
    EmptyRemoteState,
    GenerationMismatch,
    NonContiguous,
}

impl WebPullRecoveryReason {
    const fn as_str(self) -> &'static str {
        match self {
            WebPullRecoveryReason::EmptyRemoteState => "empty_remote_state",
            WebPullRecoveryReason::GenerationMismatch => "generation_mismatch",
            WebPullRecoveryReason::NonContiguous => "non_contiguous",
        }
    }
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct WebPullApplyResult {
    pub applied_count: u64,
    pub generation_id: Option<String>,
    pub last_applied_global_seq: i64,
    pub remote_latest_global_seq: i64,
    pub has_more: bool,
    pub retry_required: bool,
    pub recovery_reason: Option<String>,
}

pub fn read_web_pull_state(
    conn: &Connection,
    base_url: &str,
    vault_id: &str,
) -> Result<WebPullState> {
    let scope_id = super::runtime::scope_id(base_url, vault_id);
    Ok(WebPullState {
        generation_id: super::global_log_state::read_generation_id(conn, &scope_id)?,
        last_applied_global_seq: super::global_log_state::read_last_applied_global_seq(
            conn, &scope_id,
        )?,
    })
}

pub fn recover_web_pull_state_if_safe(
    conn: &Connection,
    db_key: &[u8; 32],
    base_url: &str,
    vault_id: &str,
) -> Result<WebPullState> {
    let scope_id = super::runtime::scope_id(base_url, vault_id);
    super::global_log_client::rebuild_local_vault_if_safe(conn, db_key, &scope_id)?;
    read_web_pull_state(conn, base_url, vault_id)
}

fn recovered_result(
    recovered_state: WebPullState,
    page: &WebPullPage,
    reason: WebPullRecoveryReason,
) -> WebPullApplyResult {
    WebPullApplyResult {
        applied_count: 0,
        generation_id: recovered_state.generation_id,
        last_applied_global_seq: recovered_state.last_applied_global_seq,
        remote_latest_global_seq: page.remote_latest_global_seq,
        has_more: page.has_more,
        retry_required: true,
        recovery_reason: Some(reason.as_str().to_string()),
    }
}

pub fn apply_web_pull_page(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    base_url: &str,
    vault_id: &str,
    page: WebPullPage,
) -> Result<WebPullApplyResult> {
    let scope_id = super::runtime::scope_id(base_url, vault_id);
    let local_generation = super::global_log_state::read_generation_id(conn, &scope_id)?;
    let last_applied = super::global_log_state::read_last_applied_global_seq(conn, &scope_id)?;
    let response_generation = page.generation_id.trim();

    if response_generation.is_empty() {
        if page.remote_latest_global_seq == 0 && page.ops.is_empty() {
            if local_generation.is_some() || last_applied > 0 {
                let recovered_state =
                    recover_web_pull_state_if_safe(conn, db_key, base_url, vault_id)?;
                return Ok(recovered_result(
                    recovered_state,
                    &page,
                    WebPullRecoveryReason::EmptyRemoteState,
                ));
            }
            return Ok(WebPullApplyResult {
                applied_count: 0,
                generation_id: local_generation,
                last_applied_global_seq: last_applied,
                remote_latest_global_seq: page.remote_latest_global_seq,
                has_more: page.has_more,
                retry_required: false,
                recovery_reason: None,
            });
        }
        return Err(anyhow!(
            "managed-vault v2 pull returned an empty generation_id with remote_latest_global_seq={} ops={}",
            page.remote_latest_global_seq,
            page.ops.len()
        ));
    }

    if let Some(existing_generation) = &local_generation {
        if existing_generation != response_generation {
            let recovered_state = recover_web_pull_state_if_safe(conn, db_key, base_url, vault_id)?;
            return Ok(recovered_result(
                recovered_state,
                &page,
                WebPullRecoveryReason::GenerationMismatch,
            ));
        }
    }

    if page.ops.is_empty() {
        if page.has_more || page.remote_latest_global_seq > last_applied {
            return Err(anyhow!(
                "managed-vault v2 pull returned an empty page while more remote data is still advertised: after_global_seq={last_applied} remote_latest_global_seq={} has_more={}",
                page.remote_latest_global_seq,
                page.has_more
            ));
        }
        super::global_log_state::write_generation_id(conn, &scope_id, response_generation)?;
        return Ok(WebPullApplyResult {
            applied_count: 0,
            generation_id: Some(response_generation.to_string()),
            last_applied_global_seq: last_applied,
            remote_latest_global_seq: page.remote_latest_global_seq,
            has_more: false,
            retry_required: false,
            recovery_reason: None,
        });
    }

    if !super::global_log_client::pull_page_is_contiguous(&page.ops, last_applied) {
        if local_generation.is_some() || last_applied > 0 {
            let recovered_state = recover_web_pull_state_if_safe(conn, db_key, base_url, vault_id)?;
            return Ok(recovered_result(
                recovered_state,
                &page,
                WebPullRecoveryReason::NonContiguous,
            ));
        }
        return Err(anyhow!(
            "managed-vault v2 pull returned non-contiguous global_seq page after_global_seq={last_applied}"
        ));
    }

    super::global_log_state::write_generation_id(conn, &scope_id, response_generation)?;
    let applied_count =
        super::global_log_client::apply_v2_pull_ops(conn, db_key, sync_key, &scope_id, &page.ops)?;
    let next_last_applied = page
        .ops
        .last()
        .map(|item| item.global_seq)
        .unwrap_or(last_applied);
    if next_last_applied != last_applied {
        super::global_log_state::write_last_applied_global_seq(conn, &scope_id, next_last_applied)?;
    }

    Ok(WebPullApplyResult {
        applied_count,
        generation_id: Some(response_generation.to_string()),
        last_applied_global_seq: next_last_applied,
        remote_latest_global_seq: page.remote_latest_global_seq,
        has_more: page.has_more,
        retry_required: false,
        recovery_reason: None,
    })
}

pub fn finalize_web_pull(
    conn: &Connection,
    db_key: &[u8; 32],
    _sync_key: &[u8; 32],
    base_url: &str,
    vault_id: &str,
    _id_token: &str,
    _applied_ops: u64,
) -> Result<()> {
    let scope_id = super::runtime::scope_id(base_url, vault_id);
    let app_dir = super::super::app_dir_from_conn(conn)?;

    // Web pull fetches remote pages through Dart/Pages async HTTP. Keep this
    // finalization local-only so it never falls back to sync XHR on the UI
    // thread when remote media/artifact blobs are still missing.
    let _ = super::state_machine::transition(
        conn,
        &scope_id,
        super::state_machine::ManagedVaultSyncState::BlobBackfill,
    );
    super::media_state::update_v2_pull_backfill_markers(
        conn,
        db_key,
        app_dir.as_path(),
        &scope_id,
    )?;
    let _ = super::state_machine::transition(
        conn,
        &scope_id,
        super::state_machine::ManagedVaultSyncState::Completed,
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use base64::engine::general_purpose::STANDARD as B64_STD;
    use base64::Engine as _;

    fn encrypted_pull_op(
        sync_key: &[u8; 32],
        global_seq: i64,
        device_id: &str,
        seq: i64,
        op_json: serde_json::Value,
    ) -> super::super::global_log_protocol::GlobalLogPullOp {
        let plaintext = serde_json::to_vec(&op_json).expect("serialize op");
        let ciphertext = crate::crypto::encrypt_bytes(
            sync_key,
            &plaintext,
            format!("sync.ops:{device_id}:{seq}").as_bytes(),
        )
        .expect("encrypt op");
        let op_id = op_json["op_id"].as_str().expect("op_id").to_string();
        super::super::global_log_protocol::GlobalLogPullOp {
            global_seq,
            device_id: device_id.to_string(),
            seq,
            op_id: op_id.clone(),
            client_op_id: op_id,
            ciphertext_b64: B64_STD.encode(ciphertext),
        }
    }

    #[test]
    fn apply_web_pull_page_recovers_generation_mismatch_by_requesting_retry() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = crate::db::open(dir.path()).expect("open");
        let base_url = "https://service-vault.secondloop.app";
        let vault_id = "vault-1";
        let scope_id = super::super::runtime::scope_id(base_url, vault_id);

        super::super::global_log_state::write_generation_id(&conn, &scope_id, "generation-local")
            .expect("seed generation");
        super::super::global_log_state::write_last_applied_global_seq(&conn, &scope_id, 9)
            .expect("seed last applied");

        let result = apply_web_pull_page(
            &conn,
            &[7; 32],
            &[9; 32],
            base_url,
            vault_id,
            WebPullPage {
                generation_id: "generation-remote".to_string(),
                remote_latest_global_seq: 0,
                has_more: false,
                ops: vec![],
            },
        )
        .expect("apply page");

        assert!(result.retry_required);
        assert_eq!(
            result.recovery_reason.as_deref(),
            Some("generation_mismatch")
        );
        assert_eq!(result.generation_id, None);
        assert_eq!(result.last_applied_global_seq, 0);
        assert_eq!(
            super::super::global_log_state::read_generation_id(&conn, &scope_id)
                .expect("read generation"),
            None,
        );
        assert_eq!(
            super::super::global_log_state::read_last_applied_global_seq(&conn, &scope_id)
                .expect("read last applied"),
            0,
        );
    }

    #[test]
    fn apply_web_pull_page_recovers_non_contiguous_page_by_requesting_retry() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = crate::db::open(dir.path()).expect("open");
        let base_url = "https://service-vault.secondloop.app";
        let vault_id = "vault-1";
        let scope_id = super::super::runtime::scope_id(base_url, vault_id);

        super::super::global_log_state::write_generation_id(&conn, &scope_id, "generation-a")
            .expect("seed generation");
        super::super::global_log_state::write_last_applied_global_seq(&conn, &scope_id, 1)
            .expect("seed last applied");

        let result = apply_web_pull_page(
            &conn,
            &[7; 32],
            &[9; 32],
            base_url,
            vault_id,
            WebPullPage {
                generation_id: "generation-a".to_string(),
                remote_latest_global_seq: 3,
                has_more: true,
                ops: vec![super::super::global_log_protocol::GlobalLogPullOp {
                    global_seq: 3,
                    device_id: "device-a".to_string(),
                    seq: 11,
                    op_id: "op-3".to_string(),
                    client_op_id: "op-3".to_string(),
                    ciphertext_b64: "AQID".to_string(),
                }],
            },
        )
        .expect("apply page");

        assert!(result.retry_required);
        assert_eq!(result.recovery_reason.as_deref(), Some("non_contiguous"));
        assert_eq!(result.generation_id, None);
        assert_eq!(result.last_applied_global_seq, 0);
    }

    #[test]
    fn recover_web_pull_state_if_safe_blocks_on_local_unpushed_changes() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = crate::db::open(dir.path()).expect("open");
        let db_key = [7; 32];
        let base_url = "https://service-vault.secondloop.app";
        let vault_id = "vault-1";
        let scope_id = super::super::runtime::scope_id(base_url, vault_id);
        let device_id = crate::db::get_or_create_device_id(&conn).expect("device id");
        let op_id = "op-local-1";
        let op_json = serde_json::json!({
            "op_id": op_id,
            "device_id": device_id,
            "seq": 1,
            "ts_ms": 1i64,
            "type": "conversation.upsert.v1",
            "payload": {
                "conversation_id": "conversation-local-1",
                "title": "Local draft",
                "created_at_ms": 1i64,
                "updated_at_ms": 1i64,
            }
        });
        let plaintext = serde_json::to_vec(&op_json).expect("serialize op");
        let ciphertext = crate::crypto::encrypt_bytes(
            &db_key,
            &plaintext,
            format!("oplog.op_json:{op_id}").as_bytes(),
        )
        .expect("encrypt op");

        super::super::global_log_state::write_last_pushed_local_seq(
            &conn, &scope_id, &device_id, 0,
        )
        .expect("seed last pushed");
        conn.execute(
            r#"INSERT INTO oplog(op_id, device_id, seq, op_json, created_at)
               VALUES (?1, ?2, ?3, ?4, ?5)"#,
            rusqlite::params![op_id, device_id, 1, ciphertext, 1i64],
        )
        .expect("seed local oplog row");

        let error = recover_web_pull_state_if_safe(&conn, &db_key, base_url, vault_id)
            .expect_err("recovery should be blocked");

        assert!(error
            .to_string()
            .contains("managed-vault v2 recovery blocked: local_unpushed_changes"));
    }

    #[test]
    fn finalize_web_pull_marks_scope_completed_when_backfill_runs() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = crate::db::open(dir.path()).expect("open");
        let base_url = "https://service-vault.secondloop.app";
        let vault_id = "vault-1";
        let scope_id = super::super::runtime::scope_id(base_url, vault_id);

        finalize_web_pull(&conn, &[7; 32], &[9; 32], base_url, vault_id, "token-1", 1)
            .expect("finalize pull");

        assert_eq!(
            super::super::state_machine::load_state(&conn, &scope_id).expect("load state"),
            Some(super::super::state_machine::ManagedVaultSyncState::Completed),
        );
    }

    #[test]
    fn finalize_web_pull_does_not_fetch_missing_artifact_blobs() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = crate::db::open(dir.path()).expect("open");
        let base_url = "http://127.0.0.1:9";
        let vault_id = "vault-1";
        let blob_ref = "blob/web-missing-artifact";

        crate::db::record_embedding_artifact_manifest(
            &conn,
            crate::db::EmbeddingArtifactManifestInput {
                source_kind: "message",
                source_id: "message-1",
                source_revision: 1,
                chunk_hash: "chunk-a",
                chunk_ordinal: 0,
                profile_id: "profile-1",
                producer_device_id: Some("web-device"),
                producer_class: "desktop",
                quality_tier: "full",
                vector_format: "f32",
                dimension: 384,
                blob_ref,
                created_at_ms: Some(100),
            },
        )
        .expect("record missing artifact manifest");
        assert!(!crate::db::has_embedding_artifact_blob(
            dir.path(),
            blob_ref
        ));

        finalize_web_pull(&conn, &[7; 32], &[9; 32], base_url, vault_id, "token-1", 1)
            .expect("web finalization should stay local-only");
    }

    #[test]
    fn apply_web_pull_page_replays_out_of_order_checklist_suggestion_ops_via_pending_apply() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = crate::db::open(dir.path()).expect("open");
        let base_url = "https://service-vault.secondloop.app";
        let vault_id = "vault-1";
        let sync_key = [9; 32];

        let suggestion_op = serde_json::json!({
            "op_id": "op-suggestion-1",
            "device_id": "device-a",
            "seq": 1,
            "ts_ms": 20i64,
            "type": "todo.checklist_suggestion.upsert.v1",
            "payload": {
                "suggestion_id": "suggestion-1",
                "todo_id": "todo-1",
                "content": "Draft checklist item",
                "sort_order": 0,
                "state": crate::db::TODO_CHECKLIST_SUGGESTION_STATE_PENDING,
                "source": "semantic_parse",
                "generation_key": "gen-1",
                "created_at_ms": 20i64,
                "updated_at_ms": 20i64,
                "dismissed_at_ms": serde_json::Value::Null,
                "applied_checklist_item_id": serde_json::Value::Null,
            }
        });
        let todo_op = serde_json::json!({
            "op_id": "op-todo-1",
            "device_id": "device-b",
            "seq": 1,
            "ts_ms": 21i64,
            "type": "todo.upsert.v1",
            "payload": {
                "todo_id": "todo-1",
                "title": "Checklist sync todo",
                "status": "open",
                "due_at_ms": serde_json::Value::Null,
                "source_entry_id": serde_json::Value::Null,
                "created_at_ms": 10i64,
                "updated_at_ms": 21i64,
                "review_stage": 0,
                "next_review_at_ms": serde_json::Value::Null,
                "last_review_at_ms": serde_json::Value::Null,
                "manual_importance_nudge_score": 0,
                "manual_urgency_nudge_score": 0,
            }
        });

        let result = apply_web_pull_page(
            &conn,
            &[7; 32],
            &sync_key,
            base_url,
            vault_id,
            WebPullPage {
                generation_id: "generation-a".to_string(),
                remote_latest_global_seq: 2,
                has_more: false,
                ops: vec![
                    encrypted_pull_op(&sync_key, 1, "device-a", 1, suggestion_op),
                    encrypted_pull_op(&sync_key, 2, "device-b", 1, todo_op),
                ],
            },
        )
        .expect("apply page");

        assert_eq!(result.applied_count, 2);
        assert_eq!(result.last_applied_global_seq, 2);

        let suggestions = crate::db::list_todo_checklist_suggestions(&conn, &[7; 32], "todo-1")
            .expect("list suggestions");
        assert_eq!(suggestions.len(), 1);
        assert_eq!(suggestions[0].id, "suggestion-1");
        assert_eq!(suggestions[0].content, "Draft checklist item");
    }
}
