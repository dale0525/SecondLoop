use anyhow::Result;
use std::path::Path;

use crate::db;
use crate::sync;

fn key_from_bytes(bytes: Vec<u8>) -> Result<[u8; 32]> {
    bytes
        .try_into()
        .map_err(|_| anyhow::anyhow!("invalid_key_length"))
}

#[flutter_rust_bridge::frb(sync)]
pub fn sync_managed_vault_read_web_pull_state(
    app_dir: String,
    base_url: String,
    vault_id: String,
) -> Result<String> {
    let conn = db::open(Path::new(&app_dir))?;
    let state = sync::managed_vault::read_web_pull_state(&conn, &base_url, &vault_id)?;
    Ok(serde_json::to_string(&state)?)
}

#[flutter_rust_bridge::frb(sync)]
pub fn sync_managed_vault_apply_web_pull_page(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    base_url: String,
    vault_id: String,
    response_json: String,
) -> Result<String> {
    let key = key_from_bytes(key)?;
    let sync_key = key_from_bytes(sync_key)?;
    let page: sync::managed_vault::WebPullPage = serde_json::from_str(&response_json)?;
    let conn = db::open(Path::new(&app_dir))?;
    let result = sync::managed_vault::apply_web_pull_page(
        &conn, &key, &sync_key, &base_url, &vault_id, page,
    )?;
    Ok(serde_json::to_string(&result)?)
}

#[flutter_rust_bridge::frb(sync)]
pub fn sync_managed_vault_recover_web_pull_state(
    app_dir: String,
    key: Vec<u8>,
    base_url: String,
    vault_id: String,
) -> Result<String> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let state =
        sync::managed_vault::recover_web_pull_state_if_safe(&conn, &key, &base_url, &vault_id)?;
    Ok(serde_json::to_string(&state)?)
}

#[flutter_rust_bridge::frb(sync)]
pub fn sync_managed_vault_finalize_web_pull(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    base_url: String,
    vault_id: String,
    firebase_id_token: String,
    applied_ops: u64,
) -> Result<bool> {
    let key = key_from_bytes(key)?;
    let sync_key = key_from_bytes(sync_key)?;
    let conn = db::open(Path::new(&app_dir))?;
    sync::managed_vault::finalize_web_pull(
        &conn,
        &key,
        &sync_key,
        &base_url,
        &vault_id,
        &firebase_id_token,
        applied_ops,
    )?;
    Ok(true)
}
