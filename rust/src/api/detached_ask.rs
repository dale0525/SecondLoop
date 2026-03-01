use std::path::Path;

use anyhow::{anyhow, Result};

use crate::db;

fn key_from_bytes(bytes: Vec<u8>) -> Result<[u8; 32]> {
    if bytes.len() != 32 {
        return Err(anyhow!("invalid key length"));
    }
    let mut key = [0u8; 32];
    key.copy_from_slice(&bytes);
    Ok(key)
}

#[flutter_rust_bridge::frb]
pub fn db_apply_detached_ask_completion_once(
    app_dir: String,
    key: Vec<u8>,
    request_id: String,
    conversation_id: String,
    question: String,
    answer: String,
) -> Result<bool> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::apply_detached_ask_completion_once(
        &conn,
        &key,
        &request_id,
        &conversation_id,
        &question,
        &answer,
    )
}
