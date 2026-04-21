use anyhow::{anyhow, Result};

use crate::frb_generated::StreamSink;

fn unsupported() -> anyhow::Error {
    anyhow!("sync_progress_unsupported_on_wasm")
}

#[flutter_rust_bridge::frb]
pub fn sync_webdav_pull_progress(
    _app_dir: String,
    _key: Vec<u8>,
    _sync_key: Vec<u8>,
    _base_url: String,
    _username: Option<String>,
    _password: Option<String>,
    _remote_root: String,
    _sink: StreamSink<String>,
) -> Result<()> {
    Err(unsupported())
}

#[flutter_rust_bridge::frb]
pub fn sync_webdav_push_ops_only_progress(
    _app_dir: String,
    _key: Vec<u8>,
    _sync_key: Vec<u8>,
    _base_url: String,
    _username: Option<String>,
    _password: Option<String>,
    _remote_root: String,
    _sink: StreamSink<String>,
) -> Result<()> {
    Err(unsupported())
}

#[flutter_rust_bridge::frb]
pub fn sync_localdir_pull_progress(
    _app_dir: String,
    _key: Vec<u8>,
    _sync_key: Vec<u8>,
    _local_dir: String,
    _remote_root: String,
    _sink: StreamSink<String>,
) -> Result<()> {
    Err(unsupported())
}

#[flutter_rust_bridge::frb]
pub fn sync_localdir_push_progress(
    _app_dir: String,
    _key: Vec<u8>,
    _sync_key: Vec<u8>,
    _local_dir: String,
    _remote_root: String,
    _sink: StreamSink<String>,
) -> Result<()> {
    Err(unsupported())
}

#[flutter_rust_bridge::frb]
pub fn sync_managed_vault_pull_progress(
    _app_dir: String,
    _key: Vec<u8>,
    _sync_key: Vec<u8>,
    _base_url: String,
    _vault_id: String,
    _id_token: String,
    _sink: StreamSink<String>,
) -> Result<()> {
    Err(unsupported())
}

#[flutter_rust_bridge::frb]
pub fn sync_managed_vault_push_ops_only_progress(
    _app_dir: String,
    _key: Vec<u8>,
    _sync_key: Vec<u8>,
    _base_url: String,
    _vault_id: String,
    _id_token: String,
    _sink: StreamSink<String>,
) -> Result<()> {
    Err(unsupported())
}

#[flutter_rust_bridge::frb]
pub fn sync_managed_vault_push_progress(
    _app_dir: String,
    _key: Vec<u8>,
    _sync_key: Vec<u8>,
    _base_url: String,
    _vault_id: String,
    _id_token: String,
    _sink: StreamSink<String>,
) -> Result<()> {
    Err(unsupported())
}
