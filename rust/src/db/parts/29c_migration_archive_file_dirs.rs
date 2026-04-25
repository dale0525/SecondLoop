const VAULT_ROLLBACK_FILE_DIRS: &[&str] =
    &["attachments", "external_readonly", "embedding_artifacts"];

struct VaultRollbackFileDirSwap {
    name: &'static str,
    current: PathBuf,
    temp: PathBuf,
    backup: PathBuf,
    had_existing: bool,
    backed_up: bool,
    replaced: bool,
}

fn vault_rollback_copy_file_dirs(app_dir: &Path, stage_dir: &Path) -> Result<()> {
    for dir_name in VAULT_ROLLBACK_FILE_DIRS {
        vault_rollback_copy_dir_recursive(&app_dir.join(dir_name), &stage_dir.join(dir_name))?;
    }
    Ok(())
}

fn vault_rollback_prepare_file_dir_swaps(
    app_dir: &Path,
    stage_dir: &Path,
) -> Result<Vec<VaultRollbackFileDirSwap>> {
    let mut swaps = Vec::new();
    let prepare_result = (|| -> Result<()> {
        for dir_name in VAULT_ROLLBACK_FILE_DIRS {
            let current = app_dir.join(dir_name);
            if current.exists() && !current.is_dir() {
                return Err(anyhow!("{dir_name} path is not a directory"));
            }

            let temp = app_dir.join(format!("{dir_name}.restore-{}.tmp", uuid::Uuid::new_v4()));
            let backup = app_dir.join(format!(
                "{dir_name}.restore-backup-{}.tmp",
                uuid::Uuid::new_v4()
            ));
            let had_existing = current.exists();
            swaps.push(VaultRollbackFileDirSwap {
                name: dir_name,
                current,
                temp,
                backup,
                had_existing,
                backed_up: false,
                replaced: false,
            });

            let swap = swaps.last().expect("swap just pushed");
            let staged = stage_dir.join(dir_name);
            if staged.exists() {
                vault_rollback_copy_dir_recursive(&staged, &swap.temp)?;
            } else {
                fs::create_dir_all(&swap.temp)?;
            }
        }
        Ok(())
    })();

    if prepare_result.is_err() {
        vault_rollback_cleanup_file_dir_swaps(&swaps);
    }
    prepare_result.map(|_| swaps)
}

fn vault_rollback_apply_file_dir_swaps(swaps: &mut [VaultRollbackFileDirSwap]) -> Result<()> {
    for swap in swaps {
        if swap.had_existing {
            fs::rename(&swap.current, &swap.backup)?;
            swap.backed_up = true;
        }
        fs::rename(&swap.temp, &swap.current)?;
        swap.replaced = true;
    }
    Ok(())
}

fn vault_rollback_undo_file_dir_swaps(
    swaps: &mut [VaultRollbackFileDirSwap],
) -> Option<anyhow::Error> {
    let mut rollback_error = None;
    for swap in swaps.iter_mut().rev() {
        if swap.replaced {
            if let Err(err) = best_effort_remove_dir_all(&swap.current) {
                rollback_error = Some(anyhow!("remove restored {} failed: {err}", swap.name));
            }
        }
        if swap.backed_up {
            if let Err(err) = fs::rename(&swap.backup, &swap.current) {
                rollback_error = Some(anyhow!("restore {} failed: {err}", swap.name));
            }
        }
    }
    vault_rollback_cleanup_file_dir_swaps(swaps);
    rollback_error
}

fn vault_rollback_cleanup_file_dir_swaps(swaps: &[VaultRollbackFileDirSwap]) {
    for swap in swaps {
        let _ = best_effort_remove_dir_all(&swap.temp);
        let _ = best_effort_remove_dir_all(&swap.backup);
    }
}
