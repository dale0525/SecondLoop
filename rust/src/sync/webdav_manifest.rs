use anyhow::{anyhow, Result};
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
