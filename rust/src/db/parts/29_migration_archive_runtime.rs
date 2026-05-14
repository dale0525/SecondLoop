const VAULT_ROLLBACK_SNAPSHOT_AAD: &[u8] = b"vault.rollback_snapshot.v1";

fn migration_archive_remove_rollback_snapshots_except_active(app_dir: &Path) -> Result<()> {
    let rollback_dir = migration_archive_root_dir(app_dir).join("rollback");
    if !rollback_dir.exists() {
        return Ok(());
    }
    let active_snapshots = migration_archive_active_rollback_snapshot_paths(app_dir)?;
    if active_snapshots.is_empty() {
        return best_effort_remove_dir_all(&rollback_dir);
    }
    for entry in fs::read_dir(&rollback_dir)? {
        let entry = entry?;
        let path = entry.path();
        let normalized = migration_archive_normalized_path(&path);
        let active_marker = migration_archive_snapshot_path_from_active_marker(&path)
            .map(|snapshot_path| {
                active_snapshots.contains(&migration_archive_normalized_path(&snapshot_path))
            })
            .unwrap_or(false);
        if active_snapshots.contains(&normalized) || active_marker {
            continue;
        }
        if path.is_dir() {
            best_effort_remove_dir_all(&path)?;
        } else {
            best_effort_remove_file(&path)?;
        }
    }
    Ok(())
}

fn collect_files_recursively(root: &Path, out: &mut Vec<PathBuf>) -> Result<()> {
    if !root.exists() {
        return Ok(());
    }
    for entry in fs::read_dir(root)? {
        let entry = entry?;
        let path = entry.path();
        if path.is_dir() {
            collect_files_recursively(&path, out)?;
        } else {
            out.push(path);
        }
    }
    Ok(())
}

fn migration_archive_write_zip_to_writer<W: std::io::Write + std::io::Seek>(
    stage_dir: &Path,
    writer: W,
) -> Result<W> {
    let mut writer = zip::ZipWriter::new(writer);
    let options =
        zip::write::FileOptions::default().compression_method(zip::CompressionMethod::Deflated);
    let mut files = Vec::<PathBuf>::new();
    collect_files_recursively(stage_dir, &mut files)?;
    files.sort();
    for path in files {
        let rel = path
            .strip_prefix(stage_dir)
            .unwrap_or(&path)
            .to_string_lossy()
            .replace('\\', "/");
        writer.start_file(rel, options)?;
        let mut file = fs::File::open(&path)?;
        std::io::copy(&mut file, &mut writer)?;
    }
    Ok(writer.finish()?)
}

fn migration_archive_write_zip(stage_dir: &Path, output_path: &Path) -> Result<()> {
    if let Some(parent) = output_path.parent() {
        fs::create_dir_all(parent)?;
    }
    let file = fs::File::create(output_path)?;
    let _ = migration_archive_write_zip_to_writer(stage_dir, file)?;
    Ok(())
}

fn vault_rollback_copy_dir_recursive(src: &Path, dst: &Path) -> Result<()> {
    if !src.exists() {
        return Ok(());
    }
    fs::create_dir_all(dst)?;
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let file_type = entry.file_type()?;
        let dst_path = dst.join(entry.file_name());
        if file_type.is_dir() {
            vault_rollback_copy_dir_recursive(&entry.path(), &dst_path)?;
        } else if file_type.is_file() {
            if let Some(parent) = dst_path.parent() {
                fs::create_dir_all(parent)?;
            }
            fs::copy(entry.path(), dst_path)?;
        }
    }
    Ok(())
}

fn vault_rollback_write_encrypted_snapshot(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    snapshot_path: &Path,
    active_marker: &VaultRollbackActiveMarker,
) -> Result<()> {
    let stage_dir = migration_archive_staging_dir(app_dir).join(uuid::Uuid::new_v4().to_string());
    fs::create_dir_all(&stage_dir)?;

    let snapshot_result = (|| -> Result<()> {
        let db_snapshot_path = stage_dir.join("secondloop.sqlite3");
        let db_snapshot_path_string = db_snapshot_path.to_string_lossy().into_owned();
        conn.execute("VACUUM main INTO ?1", params![db_snapshot_path_string])?;
        vault_rollback_copy_file_dirs(app_dir, &stage_dir)?;
        vault_rollback_write_active_marker_metadata(&stage_dir, active_marker)?;
        let zip_path = stage_dir.with_extension("zip.tmp");
        let zip_result = (|| -> Result<()> {
            migration_archive_write_zip(&stage_dir, &zip_path)?;
            vault_rollback_encrypt_zip_file_to_snapshot(key, &zip_path, snapshot_path)?;
            Ok(())
        })();
        let _ = fs::remove_file(&zip_path);
        zip_result
    })();

    let _ = fs::remove_dir_all(&stage_dir);
    snapshot_result
}

fn vault_rollback_extract_zip_bytes(app_dir: &Path, zip_bytes: &[u8]) -> Result<PathBuf> {
    vault_rollback_extract_zip_archive(app_dir, std::io::Cursor::new(zip_bytes))
}

fn vault_rollback_restore_from_encrypted_snapshot(
    app_dir: &Path,
    key: &[u8; 32],
    snapshot_path: &Path,
) -> Result<()> {
    let stage_dir = vault_rollback_extract_snapshot_to_stage(app_dir, key, snapshot_path)?;

    let restore_result = (|| -> Result<()> {
        fs::create_dir_all(app_dir)?;
        let db_path = app_dir.join("secondloop.sqlite3");
        let staged_db = stage_dir.join("secondloop.sqlite3");
        if !staged_db.is_file() {
            return Err(anyhow!("rollback snapshot missing secondloop.sqlite3"));
        }
        let temp_db = app_dir.join(format!(
            "secondloop.sqlite3.restore-{}.tmp",
            uuid::Uuid::new_v4()
        ));

        let prepared_result = (|| -> Result<()> {
            fs::copy(&staged_db, &temp_db)?;
            {
                let validation_conn = Connection::open(&temp_db)?;
                let _: i64 =
                    validation_conn.pragma_query_value(None, "user_version", |row| row.get(0))?;
            }

            let mut file_dir_swaps = vault_rollback_prepare_file_dir_swaps(app_dir, &stage_dir)?;
            let backup_db = app_dir.join(format!(
                "secondloop.sqlite3.restore-backup-{}.tmp",
                uuid::Uuid::new_v4()
            ));
            let had_existing_db = db_path.exists();
            let mut db_replaced = false;

            let swap_result = (|| -> Result<()> {
                if had_existing_db {
                    fs::rename(&db_path, &backup_db)?;
                }
                fs::rename(&temp_db, &db_path)?;
                db_replaced = true;
                best_effort_remove_file(&app_dir.join("secondloop.sqlite3-wal"))?;
                best_effort_remove_file(&app_dir.join("secondloop.sqlite3-shm"))?;

                vault_rollback_apply_file_dir_swaps(&mut file_dir_swaps)?;
                Ok(())
            })();

            if let Err(error) = swap_result {
                let mut rollback_error = vault_rollback_undo_file_dir_swaps(&mut file_dir_swaps);
                if db_replaced {
                    if let Err(err) = best_effort_remove_file(&db_path) {
                        rollback_error = Some(anyhow!("remove restored db failed: {err}"));
                    }
                }
                if had_existing_db && backup_db.exists() {
                    if let Err(err) = fs::rename(&backup_db, &db_path) {
                        rollback_error = Some(anyhow!("restore db failed: {err}"));
                    }
                }
                let _ = best_effort_remove_file(&temp_db);
                if let Some(rollback_error) = rollback_error {
                    return Err(anyhow!("{error}; rollback failed: {rollback_error}"));
                }
                return Err(error);
            }

            best_effort_remove_file(&backup_db)?;
            vault_rollback_cleanup_file_dir_swaps(&file_dir_swaps);
            Ok(())
        })();
        if prepared_result.is_err() {
            let _ = best_effort_remove_file(&temp_db);
        }
        prepared_result
    })();

    let _ = fs::remove_dir_all(&stage_dir);
    if restore_result.is_ok() {
        let _ = migration_archive_remove_rollback_snapshot(snapshot_path);
    }
    restore_result
}

pub(crate) fn migration_archive_create_rollback_snapshot(
    app_dir: &Path,
    key: &[u8; 32],
) -> Result<Option<PathBuf>> {
    let conn = open(app_dir)?;
    let snapshot_dir = migration_archive_root_dir(app_dir).join("rollback");
    fs::create_dir_all(&snapshot_dir)?;
    let snapshot_path = snapshot_dir.join(format!("{}.bin", uuid::Uuid::new_v4()));
    let active_marker = vault_rollback_new_active_marker(&snapshot_path)?;
    vault_rollback_write_encrypted_snapshot(&conn, key, app_dir, &snapshot_path, &active_marker)?;
    migration_archive_mark_active_rollback_snapshot(&snapshot_path, &active_marker)?;
    Ok(Some(snapshot_path))
}

pub(crate) fn migration_archive_restore_rollback_snapshot(
    app_dir: &Path,
    key: &[u8; 32],
    snapshot_path: &Path,
) -> Result<()> {
    vault_rollback_restore_from_encrypted_snapshot(app_dir, key, snapshot_path)
}

pub(crate) fn migration_archive_remove_rollback_snapshot(snapshot_path: &Path) -> Result<()> {
    let normalized = migration_archive_normalized_path(snapshot_path);
    let in_memory_active = {
        let active = migration_archive_active_rollback_snapshots()
            .lock()
            .map_err(|_| anyhow!("active rollback snapshot registry poisoned"))?;
        active.contains(&normalized) || active.contains(snapshot_path)
    };
    let persisted_active = migration_archive_snapshot_path_has_rollback_layout(snapshot_path)
        && vault_rollback_read_active_marker_file(&migration_archive_rollback_active_marker_path(
            snapshot_path,
        )?)
        .map(|marker| vault_rollback_active_marker_matches_snapshot_path(&marker, snapshot_path))
        .unwrap_or(false);
    if !in_memory_active && !persisted_active {
        return Err(anyhow!("rollback snapshot is not active"));
    }
    best_effort_remove_file(snapshot_path)?;
    migration_archive_clear_active_rollback_marker_for_snapshot(snapshot_path);
    Ok(())
}
