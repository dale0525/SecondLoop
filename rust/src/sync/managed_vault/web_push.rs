use anyhow::Result;
use rusqlite::Connection;
use serde::{Deserialize, Serialize};

const PUSH_LIMIT: i64 = 500;

#[derive(Debug, Serialize)]
struct WebPushRequest {
    base_global_seq: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    generation_id: Option<String>,
    batch_id: String,
    ops: Vec<super::global_log_protocol::GlobalLogPushOp>,
}

#[derive(Debug, Serialize)]
struct WebPushBatch {
    has_ops: bool,
    device_id: String,
    last_pushed_seq: i64,
    max_seq: i64,
    op_count: u64,
    request: Option<WebPushRequest>,
}

#[derive(Debug, Deserialize)]
struct WebPushBatchReceipt {
    has_ops: bool,
    device_id: String,
    max_seq: i64,
    op_count: u64,
}

#[derive(Debug, Serialize)]
struct WebPushApplyResult {
    accepted: u64,
    generation_id: String,
    remote_latest_global_seq: i64,
}

pub fn prepare_web_push_batch(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    base_url: &str,
    vault_id: &str,
) -> Result<String> {
    let scope_id = super::runtime::scope_id(base_url, vault_id);
    let device_id = super::super::get_or_create_device_id(conn)?;
    let last_pushed_seq =
        super::global_log_state::read_last_pushed_local_seq(conn, &scope_id, &device_id)?;

    crate::db::backfill_attachments_oplog_if_needed(conn, db_key)?;
    let batch = super::global_log_client::collect_local_push_ops_for_web(
        conn,
        db_key,
        sync_key,
        &device_id,
        last_pushed_seq,
        PUSH_LIMIT,
    )?;
    if batch.ops.is_empty() {
        return Ok(serde_json::to_string(&WebPushBatch {
            has_ops: false,
            device_id,
            last_pushed_seq,
            max_seq: batch.max_seq,
            op_count: 0,
            request: None,
        })?);
    }

    let request = WebPushRequest {
        base_global_seq: super::global_log_state::read_last_applied_global_seq(conn, &scope_id)?,
        generation_id: super::global_log_state::read_generation_id(conn, &scope_id)?,
        batch_id: uuid::Uuid::new_v4().to_string(),
        ops: batch.ops,
    };
    Ok(serde_json::to_string(&WebPushBatch {
        has_ops: true,
        device_id,
        last_pushed_seq,
        max_seq: batch.max_seq,
        op_count: request.ops.len() as u64,
        request: Some(request),
    })?)
}

pub fn apply_web_push_response(
    conn: &Connection,
    base_url: &str,
    vault_id: &str,
    batch_json: &str,
    response_json: &str,
) -> Result<String> {
    let batch: WebPushBatchReceipt = serde_json::from_str(batch_json)?;
    if !batch.has_ops {
        return Ok(serde_json::to_string(&WebPushApplyResult {
            accepted: 0,
            generation_id: String::new(),
            remote_latest_global_seq: 0,
        })?);
    }

    let response: super::global_log_protocol::GlobalLogPushResponse =
        serde_json::from_str(response_json)?;
    super::global_log_client::ensure_complete_push_acceptance_for_count(&response, batch.op_count)?;

    let scope_id = super::runtime::scope_id(base_url, vault_id);
    super::global_log_state::write_generation_id(conn, &scope_id, &response.generation_id)?;
    super::global_log_state::write_last_pushed_local_seq(
        conn,
        &scope_id,
        &batch.device_id,
        batch.max_seq,
    )?;
    if response.accepted > 0 {
        super::maybe_run_managed_vault_retention(conn, &scope_id)?;
    }

    Ok(serde_json::to_string(&WebPushApplyResult {
        accepted: response.accepted,
        generation_id: response.generation_id,
        remote_latest_global_seq: response.remote_latest_global_seq,
    })?)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn web_push_prepare_and_apply_stay_local_only() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = crate::db::open(dir.path()).expect("open");
        let db_key = [7u8; 32];
        let sync_key = [9u8; 32];
        let base_url = "http://127.0.0.1:9";
        let vault_id = "vault-1";

        let conversation =
            crate::db::create_conversation(&conn, &db_key, "web").expect("create conversation");
        crate::db::insert_message(&conn, &db_key, &conversation.id, "user", "hello from web")
            .expect("insert message");

        let batch_json = prepare_web_push_batch(&conn, &db_key, &sync_key, base_url, vault_id)
            .expect("prepare web push batch");
        let batch: serde_json::Value = serde_json::from_str(&batch_json).expect("batch json");
        assert_eq!(batch["has_ops"].as_bool(), Some(true));
        assert_eq!(batch["request"]["base_global_seq"].as_i64(), Some(0));
        assert!(batch["request"]["batch_id"]
            .as_str()
            .is_some_and(|value| !value.is_empty()));
        let op_count = batch["op_count"].as_u64().expect("op count");
        assert!(op_count > 0);

        let response_json = serde_json::json!({
            "generation_id": "generation-1",
            "accepted": op_count,
            "committed_from_seq": 1,
            "committed_to_seq": op_count,
            "remote_latest_global_seq": op_count,
        })
        .to_string();
        let applied_json =
            apply_web_push_response(&conn, base_url, vault_id, &batch_json, &response_json)
                .expect("apply web push response");
        let applied: serde_json::Value = serde_json::from_str(&applied_json).expect("applied json");
        assert_eq!(applied["accepted"].as_u64(), Some(op_count));

        let next_batch_json = prepare_web_push_batch(&conn, &db_key, &sync_key, base_url, vault_id)
            .expect("prepare next web push batch");
        let next_batch: serde_json::Value =
            serde_json::from_str(&next_batch_json).expect("next batch json");
        assert_eq!(next_batch["has_ops"].as_bool(), Some(false));
    }
}
