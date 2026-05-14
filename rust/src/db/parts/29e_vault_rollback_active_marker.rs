const VAULT_ROLLBACK_ACTIVE_MARKER_SUFFIX: &str = ".active";
const VAULT_ROLLBACK_ACTIVE_METADATA_PATH: &str = ".vault_rollback_active.json";
const VAULT_ROLLBACK_ACTIVE_MARKER_VERSION: i64 = 1;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
struct VaultRollbackActiveMarker {
    schema_version: i64,
    snapshot_file_name: String,
    token: String,
}

fn migration_archive_active_rollback_snapshots() -> &'static std::sync::Mutex<BTreeSet<PathBuf>> {
    static ACTIVE: std::sync::OnceLock<std::sync::Mutex<BTreeSet<PathBuf>>> =
        std::sync::OnceLock::new();
    ACTIVE.get_or_init(|| std::sync::Mutex::new(BTreeSet::new()))
}

fn migration_archive_normalized_path(path: &Path) -> PathBuf {
    fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf())
}

fn migration_archive_rollback_snapshot_file_name(snapshot_path: &Path) -> Result<String> {
    snapshot_path
        .file_name()
        .and_then(|value| value.to_str())
        .map(str::to_owned)
        .ok_or_else(|| anyhow!("invalid rollback snapshot path"))
}

fn migration_archive_rollback_active_marker_path(snapshot_path: &Path) -> Result<PathBuf> {
    let file_name = migration_archive_rollback_snapshot_file_name(snapshot_path)?;
    Ok(snapshot_path.with_file_name(format!(
        "{file_name}{VAULT_ROLLBACK_ACTIVE_MARKER_SUFFIX}"
    )))
}

fn migration_archive_snapshot_path_from_active_marker(marker_path: &Path) -> Option<PathBuf> {
    let file_name = marker_path.file_name()?.to_str()?;
    let snapshot_file_name = file_name.strip_suffix(VAULT_ROLLBACK_ACTIVE_MARKER_SUFFIX)?;
    Some(marker_path.with_file_name(snapshot_file_name))
}

fn migration_archive_snapshot_path_has_rollback_layout(snapshot_path: &Path) -> bool {
    snapshot_path
        .parent()
        .and_then(|parent| parent.file_name())
        .and_then(|name| name.to_str())
        == Some("rollback")
        && snapshot_path
            .parent()
            .and_then(|parent| parent.parent())
            .and_then(|parent| parent.file_name())
            .and_then(|name| name.to_str())
            == Some("migration_archive")
}

fn vault_rollback_new_active_marker(snapshot_path: &Path) -> Result<VaultRollbackActiveMarker> {
    Ok(VaultRollbackActiveMarker {
        schema_version: VAULT_ROLLBACK_ACTIVE_MARKER_VERSION,
        snapshot_file_name: migration_archive_rollback_snapshot_file_name(snapshot_path)?,
        token: uuid::Uuid::new_v4().to_string(),
    })
}

fn vault_rollback_active_marker_matches_snapshot_path(
    marker: &VaultRollbackActiveMarker,
    snapshot_path: &Path,
) -> bool {
    marker.schema_version == VAULT_ROLLBACK_ACTIVE_MARKER_VERSION
        && migration_archive_rollback_snapshot_file_name(snapshot_path)
            .map(|file_name| marker.snapshot_file_name == file_name)
            .unwrap_or(false)
}

fn vault_rollback_read_active_marker_file(marker_path: &Path) -> Result<VaultRollbackActiveMarker> {
    Ok(serde_json::from_slice(&fs::read(marker_path)?)?)
}

fn vault_rollback_write_active_marker_metadata(
    stage_dir: &Path,
    marker: &VaultRollbackActiveMarker,
) -> Result<()> {
    fs::write(
        stage_dir.join(VAULT_ROLLBACK_ACTIVE_METADATA_PATH),
        serde_json::to_vec(marker)?,
    )?;
    Ok(())
}

fn vault_rollback_snapshot_contains_active_marker(
    app_dir: &Path,
    key: &[u8; 32],
    snapshot_path: &Path,
    marker: &VaultRollbackActiveMarker,
) -> Result<bool> {
    let stage_dir = match vault_rollback_extract_snapshot_to_stage(app_dir, key, snapshot_path) {
        Ok(stage_dir) => stage_dir,
        Err(_) => return Ok(false),
    };
    let metadata_matches = (|| -> Result<bool> {
        let metadata_path = stage_dir.join(VAULT_ROLLBACK_ACTIVE_METADATA_PATH);
        let snapshot_marker: VaultRollbackActiveMarker =
            serde_json::from_slice(&fs::read(metadata_path)?)?;
        Ok(&snapshot_marker == marker
            && vault_rollback_active_marker_matches_snapshot_path(&snapshot_marker, snapshot_path))
    })();
    let _ = fs::remove_dir_all(&stage_dir);
    Ok(metadata_matches.unwrap_or(false))
}

fn migration_archive_collect_persisted_active_rollback_snapshots(
    app_dir: &Path,
) -> Result<BTreeSet<PathBuf>> {
    let rollback_dir = migration_archive_root_dir(app_dir).join("rollback");
    let mut persisted = BTreeSet::new();
    match fs::read_dir(&rollback_dir) {
        Ok(entries) => {
            for entry in entries {
                let marker_path = entry?.path();
                let Some(snapshot_path) =
                    migration_archive_snapshot_path_from_active_marker(&marker_path)
                else {
                    continue;
                };
                let marker_is_valid = snapshot_path.exists()
                    && vault_rollback_read_active_marker_file(&marker_path)
                        .map(|marker| {
                            vault_rollback_active_marker_matches_snapshot_path(
                                &marker,
                                &snapshot_path,
                            )
                        })
                        .unwrap_or(false);
                if marker_is_valid {
                    persisted.insert(migration_archive_normalized_path(&snapshot_path));
                } else {
                    let _ = fs::remove_file(marker_path);
                }
            }
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
        Err(e) => return Err(e.into()),
    }
    Ok(persisted)
}

fn migration_archive_mark_active_rollback_snapshot(
    snapshot_path: &Path,
    marker: &VaultRollbackActiveMarker,
) -> Result<()> {
    let marker_path = migration_archive_rollback_active_marker_path(snapshot_path)?;
    fs::write(marker_path, serde_json::to_vec(marker)?)?;
    let mut active = migration_archive_active_rollback_snapshots()
        .lock()
        .map_err(|_| anyhow!("active rollback snapshot registry poisoned"))?;
    active.insert(migration_archive_normalized_path(snapshot_path));
    Ok(())
}

fn migration_archive_active_rollback_snapshot_paths(app_dir: &Path) -> Result<BTreeSet<PathBuf>> {
    let rollback_dir =
        migration_archive_normalized_path(&migration_archive_root_dir(app_dir).join("rollback"));
    let persisted = migration_archive_collect_persisted_active_rollback_snapshots(app_dir)?;
    let mut active = migration_archive_active_rollback_snapshots()
        .lock()
        .map_err(|_| anyhow!("active rollback snapshot registry poisoned"))?;
    active.extend(persisted);
    active.retain(|path| path.exists());
    Ok(active
        .iter()
        .filter(|path| path.parent() == Some(rollback_dir.as_path()))
        .cloned()
        .collect())
}

pub(crate) fn migration_archive_is_active_rollback_snapshot(
    app_dir: &Path,
    key: &[u8; 32],
    snapshot_path: &Path,
) -> Result<bool> {
    let normalized = migration_archive_normalized_path(snapshot_path);
    let in_memory_active = {
        let mut active = migration_archive_active_rollback_snapshots()
            .lock()
            .map_err(|_| anyhow!("active rollback snapshot registry poisoned"))?;
        active.retain(|path| path.exists());
        active.contains(&normalized) || active.contains(snapshot_path)
    };
    if in_memory_active {
        return Ok(true);
    }

    let marker_path = migration_archive_rollback_active_marker_path(snapshot_path)?;
    let marker = match vault_rollback_read_active_marker_file(&marker_path) {
        Ok(marker) if vault_rollback_active_marker_matches_snapshot_path(&marker, snapshot_path) => {
            marker
        }
        _ => return Ok(false),
    };
    vault_rollback_snapshot_contains_active_marker(app_dir, key, snapshot_path, &marker)
}

fn migration_archive_clear_active_rollback_marker_for_snapshot(snapshot_path: &Path) {
    if let Ok(mut active) = migration_archive_active_rollback_snapshots().lock() {
        active.remove(snapshot_path);
        active.remove(&migration_archive_normalized_path(snapshot_path));
    }
    if let Ok(marker_path) = migration_archive_rollback_active_marker_path(snapshot_path) {
        let _ = fs::remove_file(marker_path);
    }
}
