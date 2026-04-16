use anyhow::{anyhow, Result};
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct WebDavSyncManifest {
    pub protocol_version: u32,
    pub backend: String,
    pub generation_id: String,
    pub updated_at_ms: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct WebDavDeviceManifest {
    pub protocol_version: u32,
    pub device_id: String,
    pub max_seq: i64,
    #[serde(default)]
    pub history_min_seq: i64,
    pub updated_at_ms: i64,
}

pub fn sync_manifest_path(remote_root: &str) -> String {
    format!("{}sync_manifest.json", super::normalize_dir(remote_root))
}

pub fn device_manifest_path(remote_root: &str, device_id: &str) -> String {
    format!(
        "{}{}/device_manifest.json",
        super::normalize_dir(remote_root),
        device_id.trim()
    )
}

pub(crate) fn local_generation_key(scope_id: &str) -> String {
    format!("sync.webdav.generation_id:{scope_id}")
}

pub(crate) fn load_local_generation_id(
    conn: &Connection,
    scope_id: &str,
) -> Result<Option<String>> {
    conn.query_row(
        r#"SELECT value FROM kv WHERE key = ?1"#,
        params![local_generation_key(scope_id)],
        |row| row.get(0),
    )
    .optional()
    .map_err(Into::into)
}

pub(crate) fn store_local_generation_id(
    conn: &Connection,
    scope_id: &str,
    generation_id: &str,
) -> Result<()> {
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES (?1, ?2)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        params![local_generation_key(scope_id), generation_id],
    )?;
    Ok(())
}

pub(crate) fn clear_local_scope_state(conn: &Connection, scope_id: &str) -> Result<()> {
    let exact_keys = [
        format!("sync.last_pushed_seq:{scope_id}"),
        format!("sync.attachments.bytes_backfilled:{scope_id}"),
        format!("sync.embedding_artifacts.bytes_backfilled:{scope_id}"),
        format!("sync.ops_packs_backfilled:{scope_id}"),
        local_generation_key(scope_id),
    ];
    for key in exact_keys {
        let _ = conn.execute(r#"DELETE FROM kv WHERE key = ?1"#, params![key])?;
    }
    let prefixes = [format!("sync.last_pulled_seq:{scope_id}:")];
    for prefix in prefixes {
        let pattern = format!("{prefix}%");
        let _ = conn.execute(r#"DELETE FROM kv WHERE key LIKE ?1"#, params![pattern])?;
    }
    super::blob_repair::clear_blob_repairs_for_scope(conn, scope_id)?;
    Ok(())
}

pub fn read_sync_manifest(
    remote: &impl super::RemoteStore,
    remote_root: &str,
) -> Result<Option<WebDavSyncManifest>> {
    let path = sync_manifest_path(remote_root);
    let bytes = match remote.get(&path) {
        Ok(bytes) => bytes,
        Err(error) if error.is::<super::NotFound>() => return Ok(None),
        Err(error) => return Err(error),
    };
    serde_json::from_slice(&bytes)
        .map(Some)
        .map_err(|error| anyhow!("invalid webdav sync manifest: {error}"))
}

pub fn read_device_manifest(
    remote: &impl super::RemoteStore,
    remote_root: &str,
    device_id: &str,
) -> Result<Option<WebDavDeviceManifest>> {
    let path = device_manifest_path(remote_root, device_id);
    let bytes = match remote.get(&path) {
        Ok(bytes) => bytes,
        Err(error) if error.is::<super::NotFound>() => return Ok(None),
        Err(error) => return Err(error),
    };
    serde_json::from_slice(&bytes)
        .map(Some)
        .map_err(|error| anyhow!("invalid webdav device manifest: {error}"))
}

pub fn write_sync_manifest(
    remote: &impl super::RemoteStore,
    remote_root: &str,
    manifest: &WebDavSyncManifest,
) -> Result<()> {
    remote.put(
        &sync_manifest_path(remote_root),
        serde_json::to_vec(manifest)?,
    )?;
    Ok(())
}

pub fn write_device_manifest(
    remote: &impl super::RemoteStore,
    remote_root: &str,
    manifest: &WebDavDeviceManifest,
) -> Result<()> {
    let device_dir = format!(
        "{}{}/",
        super::normalize_dir(remote_root),
        manifest.device_id
    );
    remote.mkdir_all(&device_dir)?;
    remote.put(
        &device_manifest_path(remote_root, &manifest.device_id),
        serde_json::to_vec(manifest)?,
    )?;
    Ok(())
}
