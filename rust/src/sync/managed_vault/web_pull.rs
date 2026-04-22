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
    sync_key: &[u8; 32],
    base_url: &str,
    vault_id: &str,
    id_token: &str,
    applied_ops: u64,
) -> Result<()> {
    super::finalize_v2_pull_blob_backfill(
        conn,
        db_key,
        sync_key,
        base_url,
        vault_id,
        id_token,
        applied_ops,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

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
}
