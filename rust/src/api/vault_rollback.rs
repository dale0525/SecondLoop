use crate::db;
use anyhow::{anyhow, Result};
use std::path::Path;

fn key_array(key: &[u8]) -> Result<[u8; 32]> {
    <[u8; 32]>::try_from(key).map_err(|_| anyhow!("invalid key length"))
}

pub fn vault_rollback_create_snapshot(app_dir: String, key: Vec<u8>) -> Result<Option<String>> {
    let app_dir = Path::new(&app_dir);
    let key = key_array(&key)?;
    crate::api::auth_state::validate_reset_vault_data_access(app_dir, &key)?;
    db::migration_archive_create_rollback_snapshot(app_dir, &key)
        .map(|path| path.map(|path| path.to_string_lossy().into_owned()))
}

pub fn vault_rollback_restore_snapshot(
    app_dir: String,
    key: Vec<u8>,
    snapshot_path: String,
) -> Result<()> {
    let app_dir = Path::new(&app_dir);
    let key = key_array(&key)?;

    let snapshot_path = Path::new(&snapshot_path);
    if !db::migration_archive_is_active_rollback_snapshot(app_dir, &key, snapshot_path)? {
        validate_inactive_rollback_snapshot_restore_access(app_dir, &key)?;
    }

    db::migration_archive_restore_rollback_snapshot(app_dir, &key, snapshot_path)
}

// Only active rollback snapshots may bypass current auth for retry; inactive paths are arbitrary files.
fn validate_inactive_rollback_snapshot_restore_access(
    app_dir: &Path,
    key: &[u8; 32],
) -> Result<()> {
    if crate::api::auth_state::auth_is_initialized(app_dir) {
        return crate::api::auth_state::validate_reset_vault_data_access(app_dir, key);
    }
    if crate::api::auth_state::has_user_data_without_auth_file(app_dir)? {
        return Err(anyhow!("vault data exists but auth file is missing"));
    }
    Ok(())
}

pub fn vault_rollback_remove_snapshot(snapshot_path: String) -> Result<()> {
    db::migration_archive_remove_rollback_snapshot(Path::new(&snapshot_path))
}
