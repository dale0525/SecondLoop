use std::path::Path;

use anyhow::{anyhow, Result};

use crate::db;
use crate::frb_generated::StreamSink;

fn key_from_bytes(bytes: Vec<u8>) -> Result<[u8; 32]> {
    if bytes.len() != 32 {
        return Err(anyhow!("invalid key length"));
    }
    let mut key = [0u8; 32];
    key.copy_from_slice(&bytes);
    Ok(key)
}

fn emit_progress(sink: &StreamSink<String>, progress: db::MigrationArchiveProgress) {
    let payload = serde_json::json!({
        "type": "progress",
        "operation": progress.operation,
        "stage": progress.stage,
        "done": progress.done,
        "total": progress.total,
        "status": progress.status,
    })
    .to_string();
    let _ = sink.add(payload);
}

fn emit_result(sink: &StreamSink<String>, operation: &str, manifest: db::MigrationArchiveManifest) {
    let payload = serde_json::json!({
        "type": "result",
        "operation": operation,
        "manifest": manifest,
    })
    .to_string();
    let _ = sink.add(payload);
}

#[flutter_rust_bridge::frb]
pub fn migration_archive_parse_manifest_json(
    manifest_json: String,
) -> Result<db::MigrationArchiveManifest> {
    db::parse_migration_archive_manifest_json(&manifest_json)
}

#[flutter_rust_bridge::frb]
pub fn migration_archive_markdown_path_for_item_id(item_id: String) -> String {
    db::migration_archive_markdown_path_for_id(&item_id)
}

#[flutter_rust_bridge::frb]
pub fn migration_archive_wikilink_for_item(item_id: String, title: String) -> String {
    db::migration_archive_wikilink(&item_id, &title)
}

#[flutter_rust_bridge::frb]
pub fn migration_archive_export_estimate(
    app_dir: String,
    key: Vec<u8>,
) -> Result<db::MigrationArchiveExportEstimate> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::migration_archive_export_estimate(&conn)
}

#[flutter_rust_bridge::frb]
pub fn migration_archive_export(
    app_dir: String,
    key: Vec<u8>,
    output_path: String,
) -> Result<db::MigrationArchiveManifest> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::export_migration_archive(&conn, &key, Path::new(&app_dir), Path::new(&output_path))
}

#[flutter_rust_bridge::frb]
pub fn migration_archive_export_progress(
    app_dir: String,
    key: Vec<u8>,
    output_path: String,
    sink: StreamSink<String>,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let mut on_event = |progress: db::MigrationArchiveProgress| {
        emit_progress(&sink, progress);
    };
    let manifest = db::export_migration_archive_with_callbacks(
        &conn,
        &key,
        Path::new(&app_dir),
        Path::new(&output_path),
        &mut on_event,
    )?;
    emit_result(&sink, "export", manifest);
    Ok(())
}

#[flutter_rust_bridge::frb]
pub fn migration_archive_import(
    app_dir: String,
    key: Vec<u8>,
    archive_path: String,
) -> Result<db::MigrationArchiveManifest> {
    let key = key_from_bytes(key)?;
    db::import_migration_archive(Path::new(&app_dir), &key, Path::new(&archive_path))
}

#[flutter_rust_bridge::frb]
pub fn migration_archive_create_rollback_snapshot(
    app_dir: String,
    key: Vec<u8>,
) -> Result<Option<String>> {
    let app_dir = Path::new(&app_dir);
    let key = key_from_bytes(key)?;
    crate::api::auth_state::validate_reset_vault_data_access(app_dir, &key)?;
    db::migration_archive_create_rollback_snapshot(app_dir, &key)
        .map(|path| path.map(|path| path.to_string_lossy().into_owned()))
}

#[flutter_rust_bridge::frb]
pub fn migration_archive_restore_rollback_snapshot(
    app_dir: String,
    key: Vec<u8>,
    snapshot_path: String,
) -> Result<()> {
    let app_dir = Path::new(&app_dir);
    let key = key_from_bytes(key)?;
    let snapshot_path = Path::new(&snapshot_path);
    if !db::migration_archive_is_active_rollback_snapshot(app_dir, snapshot_path)? {
        crate::api::auth_state::validate_reset_vault_data_access(app_dir, &key)?;
    }
    db::migration_archive_restore_rollback_snapshot(app_dir, &key, snapshot_path)
}

#[flutter_rust_bridge::frb]
pub fn migration_archive_remove_rollback_snapshot(snapshot_path: String) -> Result<()> {
    db::migration_archive_remove_rollback_snapshot(Path::new(&snapshot_path))
}

#[flutter_rust_bridge::frb]
pub fn migration_archive_import_progress(
    app_dir: String,
    key: Vec<u8>,
    archive_path: String,
    sink: StreamSink<String>,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let mut on_event = |progress: db::MigrationArchiveProgress| {
        emit_progress(&sink, progress);
    };
    let manifest = db::import_migration_archive_with_callbacks(
        Path::new(&app_dir),
        &key,
        Path::new(&archive_path),
        &mut on_event,
    )?;
    emit_result(&sink, "import", manifest);
    Ok(())
}

#[flutter_rust_bridge::frb]
pub fn migration_archive_inspect(
    app_dir: String,
    archive_path: String,
) -> Result<db::MigrationArchiveManifest> {
    db::inspect_migration_archive(Path::new(&app_dir), Path::new(&archive_path))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn remove_rollback_snapshot_rejects_untracked_path() {
        let dir = tempfile::tempdir().expect("tempdir");
        let outside_path = dir.path().join("outside.bin");
        std::fs::write(&outside_path, b"not a rollback snapshot").expect("write outside file");

        let result =
            migration_archive_remove_rollback_snapshot(outside_path.to_string_lossy().into_owned());

        assert!(
            result.is_err(),
            "untracked rollback snapshot removal should fail"
        );
        assert!(outside_path.exists());
    }

    #[test]
    fn remove_rollback_snapshot_allows_active_snapshot() {
        let dir = tempfile::tempdir().expect("tempdir");
        let app_dir = dir.path().join("app");
        let key = vec![7u8; 32];
        let snapshot_path =
            migration_archive_create_rollback_snapshot(app_dir.to_string_lossy().into_owned(), key)
                .expect("create rollback snapshot")
                .expect("snapshot path");

        assert!(Path::new(&snapshot_path).exists());

        migration_archive_remove_rollback_snapshot(snapshot_path.clone())
            .expect("remove active snapshot");

        assert!(!Path::new(&snapshot_path).exists());
    }
}
