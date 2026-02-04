use std::path::{Path, PathBuf};

use anyhow::{anyhow, Result};

use crate::frb_generated::StreamSink;
use crate::{db, sync};

fn key_from_bytes(bytes: Vec<u8>) -> Result<[u8; 32]> {
    if bytes.len() != 32 {
        return Err(anyhow!("invalid key length"));
    }
    let mut key = [0u8; 32];
    key.copy_from_slice(&bytes);
    Ok(key)
}

fn sync_key_from_bytes(bytes: Vec<u8>) -> Result<[u8; 32]> {
    key_from_bytes(bytes)
}

fn emit_progress(sink: &StreamSink<String>, last: &mut Option<(u64, u64)>, done: u64, total: u64) {
    let next = (done, total);
    if last.as_ref() == Some(&next) {
        return;
    }
    *last = Some(next);
    let payload = serde_json::json!({
        "type": "progress",
        "done": done,
        "total": total,
    })
    .to_string();
    let _ = sink.add(payload);
}

fn emit_result(sink: &StreamSink<String>, count: u64) {
    let payload = serde_json::json!({
        "type": "result",
        "count": count,
    })
    .to_string();
    let _ = sink.add(payload);
}

#[flutter_rust_bridge::frb]
pub fn sync_webdav_pull_progress(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    base_url: String,
    username: Option<String>,
    password: Option<String>,
    remote_root: String,
    sink: StreamSink<String>,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let sync_key = sync_key_from_bytes(sync_key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let remote = sync::webdav::WebDavRemoteStore::new(base_url, username, password)?;

    let mut last: Option<(u64, u64)> = None;
    let mut on_progress = |done: u64, total: u64| {
        emit_progress(&sink, &mut last, done, total);
    };

    let pulled = sync::pull_with_progress(
        &conn,
        &key,
        &sync_key,
        &remote,
        &remote_root,
        &mut on_progress,
    )?;
    emit_result(&sink, pulled);
    Ok(())
}

#[flutter_rust_bridge::frb]
pub fn sync_webdav_push_ops_only_progress(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    base_url: String,
    username: Option<String>,
    password: Option<String>,
    remote_root: String,
    sink: StreamSink<String>,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let sync_key = sync_key_from_bytes(sync_key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let remote = sync::webdav::WebDavRemoteStore::new(base_url, username, password)?;

    let mut last: Option<(u64, u64)> = None;
    let mut on_progress = |done: u64, total: u64| {
        emit_progress(&sink, &mut last, done, total);
    };

    let pushed = sync::push_ops_only_with_progress(
        &conn,
        &key,
        &sync_key,
        &remote,
        &remote_root,
        &mut on_progress,
    )?;
    emit_result(&sink, pushed);
    Ok(())
}

#[flutter_rust_bridge::frb]
pub fn sync_localdir_pull_progress(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    local_dir: String,
    remote_root: String,
    sink: StreamSink<String>,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let sync_key = sync_key_from_bytes(sync_key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let remote = sync::localdir::LocalDirRemoteStore::new(PathBuf::from(local_dir))?;

    let mut last: Option<(u64, u64)> = None;
    let mut on_progress = |done: u64, total: u64| {
        emit_progress(&sink, &mut last, done, total);
    };

    let pulled = sync::pull_with_progress(
        &conn,
        &key,
        &sync_key,
        &remote,
        &remote_root,
        &mut on_progress,
    )?;
    emit_result(&sink, pulled);
    Ok(())
}

#[flutter_rust_bridge::frb]
pub fn sync_localdir_push_progress(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    local_dir: String,
    remote_root: String,
    sink: StreamSink<String>,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let sync_key = sync_key_from_bytes(sync_key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let remote = sync::localdir::LocalDirRemoteStore::new(PathBuf::from(local_dir))?;

    let mut last: Option<(u64, u64)> = None;
    let mut on_progress = |done: u64, total: u64| {
        emit_progress(&sink, &mut last, done, total);
    };

    let pushed = sync::push_with_progress(
        &conn,
        &key,
        &sync_key,
        &remote,
        &remote_root,
        &mut on_progress,
    )?;
    emit_result(&sink, pushed);
    Ok(())
}

#[flutter_rust_bridge::frb]
pub fn sync_managed_vault_pull_progress(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    base_url: String,
    vault_id: String,
    id_token: String,
    sink: StreamSink<String>,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let sync_key = sync_key_from_bytes(sync_key)?;
    let conn = db::open(Path::new(&app_dir))?;

    let mut last: Option<(u64, u64)> = None;
    let mut on_progress = |done: u64, total: u64| {
        emit_progress(&sink, &mut last, done, total);
    };

    let pulled = sync::managed_vault::pull_with_progress(
        &conn,
        &key,
        &sync_key,
        &base_url,
        &vault_id,
        &id_token,
        &mut on_progress,
    )?;
    emit_result(&sink, pulled);
    Ok(())
}

#[flutter_rust_bridge::frb]
pub fn sync_managed_vault_push_ops_only_progress(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    base_url: String,
    vault_id: String,
    id_token: String,
    sink: StreamSink<String>,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let sync_key = sync_key_from_bytes(sync_key)?;
    let conn = db::open(Path::new(&app_dir))?;

    let mut last: Option<(u64, u64)> = None;
    let mut on_progress = |done: u64, total: u64| {
        emit_progress(&sink, &mut last, done, total);
    };

    let pushed = sync::managed_vault::push_ops_only_with_progress(
        &conn,
        &key,
        &sync_key,
        &base_url,
        &vault_id,
        &id_token,
        &mut on_progress,
    )?;
    emit_result(&sink, pushed);
    Ok(())
}
