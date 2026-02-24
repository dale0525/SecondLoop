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

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum OplogMaintenanceBackend {
    WebDav,
    LocalDir,
    ManagedVault,
}

impl OplogMaintenanceBackend {
    fn into_db_backend(self) -> db::OplogRetentionBackend {
        match self {
            OplogMaintenanceBackend::WebDav => db::OplogRetentionBackend::WebDav,
            OplogMaintenanceBackend::LocalDir => db::OplogRetentionBackend::LocalDir,
            OplogMaintenanceBackend::ManagedVault => db::OplogRetentionBackend::ManagedVault,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct OplogMaintenanceStats {
    pub before_count: u64,
    pub after_count: u64,
    pub pruned_count: u64,
}

impl From<db::OplogRetentionMaintenanceStats> for OplogMaintenanceStats {
    fn from(value: db::OplogRetentionMaintenanceStats) -> Self {
        Self {
            before_count: value.before_count,
            after_count: value.after_count,
            pruned_count: value.pruned_count,
        }
    }
}

#[flutter_rust_bridge::frb]
pub fn db_run_oplog_maintenance(
    app_dir: String,
    key: Vec<u8>,
    backend: OplogMaintenanceBackend,
    scope_id: String,
) -> Result<OplogMaintenanceStats> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;

    // Ensure key is valid for this vault before mutating data.
    db::list_conversations(&conn, &key)?;

    let stats = db::run_oplog_retention_maintenance(&conn, backend.into_db_backend(), &scope_id)?;
    Ok(stats.into())
}
