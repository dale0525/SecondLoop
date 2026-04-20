use std::path::Path;

use anyhow::{anyhow, Result};

use crate::db;

fn key_from_bytes(bytes: Vec<u8>) -> Result<[u8; 32]> {
    bytes
        .try_into()
        .map_err(|_| anyhow!("expected 32-byte key"))
}

#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub fn db_complete_semantic_parse_followup_if_current_attempt(
    app_dir: String,
    key: Vec<u8>,
    message_id: String,
    expected_attempt_id: i64,
    todo_id: String,
    todo_title: Option<String>,
    new_status: Option<String>,
    due_at_ms: Option<i64>,
    pending_suggested_tags: Option<Vec<String>>,
    auto_apply_suggested_tags: Option<Vec<String>>,
    suggested_tag_confidence: Option<f64>,
    now_ms: i64,
) -> Result<bool> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::complete_semantic_parse_followup_if_current_attempt(
        &conn,
        &key,
        &message_id,
        expected_attempt_id,
        &todo_id,
        todo_title.as_deref(),
        new_status.as_deref(),
        due_at_ms,
        pending_suggested_tags.as_deref(),
        auto_apply_suggested_tags.as_deref(),
        suggested_tag_confidence,
        now_ms,
    )
}
