use anyhow::{anyhow, Result};

use super::RemoteStore;

#[derive(Clone, Debug)]
pub struct WebDavRemoteStore {
    target_id: String,
}

impl WebDavRemoteStore {
    pub fn new(
        base_url: String,
        _username: Option<String>,
        _password: Option<String>,
    ) -> Result<Self> {
        Ok(Self {
            target_id: format!("webdav:{}", base_url.trim()),
        })
    }

    pub fn ensure_dir_exists(&self, _dir: &str) -> Result<()> {
        Err(anyhow!("sync_webdav_unsupported_on_wasm"))
    }
}

impl RemoteStore for WebDavRemoteStore {
    fn target_id(&self) -> &str {
        &self.target_id
    }

    fn mkdir_all(&self, _path: &str) -> Result<()> {
        Err(anyhow!("sync_webdav_unsupported_on_wasm"))
    }

    fn list(&self, _dir: &str) -> Result<Vec<String>> {
        Err(anyhow!("sync_webdav_unsupported_on_wasm"))
    }

    fn get(&self, _path: &str) -> Result<Vec<u8>> {
        Err(anyhow!("sync_webdav_unsupported_on_wasm"))
    }

    fn put(&self, _path: &str, _bytes: Vec<u8>) -> Result<()> {
        Err(anyhow!("sync_webdav_unsupported_on_wasm"))
    }

    fn delete(&self, _path: &str) -> Result<()> {
        Err(anyhow!("sync_webdav_unsupported_on_wasm"))
    }
}
