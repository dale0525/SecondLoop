use anyhow::Result;
use std::path::Path;

#[cfg(not(target_family = "wasm"))]
use std::fs;

#[cfg(target_family = "wasm")]
use core::time::Duration;

#[cfg(target_family = "wasm")]
use getrandom::getrandom;

#[cfg(target_family = "wasm")]
use js_sys::{Date, Reflect};

#[cfg(target_family = "wasm")]
use rsqlite_vfs::OsCallback;

#[cfg(target_family = "wasm")]
use sqlite_wasm_vfs::{
    relaxed_idb::{install as install_relaxed_idb, RelaxedIdbCfg},
    sahpool::{install as install_opfs_sahpool, OpfsSAHPoolCfg},
};

#[cfg(target_family = "wasm")]
use std::sync::OnceLock;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SqlitePersistenceMode {
    NativeFilesystem,
    OpfsSAHPool,
    RelaxedIdb,
}

pub const fn select_wasm_sqlite_persistence_mode(
    is_dedicated_worker: bool,
) -> SqlitePersistenceMode {
    if is_dedicated_worker {
        SqlitePersistenceMode::OpfsSAHPool
    } else {
        SqlitePersistenceMode::RelaxedIdb
    }
}

#[cfg(target_family = "wasm")]
static SQLITE_RUNTIME_READY: OnceLock<SqlitePersistenceMode> = OnceLock::new();

#[cfg(target_family = "wasm")]
struct WasmSqliteOsCallback;

#[cfg(target_family = "wasm")]
impl OsCallback for WasmSqliteOsCallback {
    fn sleep(_dur: Duration) {}

    fn random(buf: &mut [u8]) {
        let _ = getrandom(buf);
    }

    fn epoch_timestamp_in_ms() -> i64 {
        Date::new_0().get_time() as i64
    }
}

pub fn sqlite_persistence_mode() -> SqlitePersistenceMode {
    #[cfg(target_family = "wasm")]
    {
        SQLITE_RUNTIME_READY
            .get()
            .copied()
            .unwrap_or(SqlitePersistenceMode::RelaxedIdb)
    }

    #[cfg(not(target_family = "wasm"))]
    {
        SqlitePersistenceMode::NativeFilesystem
    }
}

#[cfg(target_family = "wasm")]
fn is_dedicated_worker_scope() -> bool {
    let global = js_sys::global();
    Reflect::has(&global, &"importScripts".into()).unwrap_or(false)
}

#[cfg(target_family = "wasm")]
async fn install_relaxed_idb_vfs() -> Result<()> {
    install_relaxed_idb::<WasmSqliteOsCallback>(&RelaxedIdbCfg::default(), true)
        .await
        .map_err(|error| anyhow::anyhow!("install relaxed idb failed: {error:?}"))?;
    Ok(())
}

#[cfg(target_family = "wasm")]
async fn install_wasm_sqlite_persistence(
    preferred_mode: SqlitePersistenceMode,
) -> Result<SqlitePersistenceMode> {
    match preferred_mode {
        SqlitePersistenceMode::OpfsSAHPool => {
            match install_opfs_sahpool::<WasmSqliteOsCallback>(&OpfsSAHPoolCfg::default(), true)
                .await
            {
                Ok(_) => Ok(SqlitePersistenceMode::OpfsSAHPool),
                Err(error) => {
                    install_relaxed_idb_vfs().await.map_err(|fallback_error| {
                        anyhow::anyhow!(
                            "install opfs sahpool failed: {error:?}; install relaxed idb failed: {fallback_error:?}"
                        )
                    })?;
                    Ok(SqlitePersistenceMode::RelaxedIdb)
                }
            }
        }
        SqlitePersistenceMode::RelaxedIdb => {
            install_relaxed_idb_vfs().await?;
            Ok(SqlitePersistenceMode::RelaxedIdb)
        }
        SqlitePersistenceMode::NativeFilesystem => Ok(SqlitePersistenceMode::NativeFilesystem),
    }
}

pub async fn ensure_ready() -> Result<()> {
    #[cfg(target_family = "wasm")]
    {
        if SQLITE_RUNTIME_READY.get().is_none() {
            let preferred_mode = select_wasm_sqlite_persistence_mode(is_dedicated_worker_scope());
            let resolved_mode = install_wasm_sqlite_persistence(preferred_mode).await?;
            let _ = SQLITE_RUNTIME_READY.set(resolved_mode);
        }
    }

    Ok(())
}

pub fn ensure_sqlite_parent_dir(path: &Path) -> Result<()> {
    #[cfg(not(target_family = "wasm"))]
    {
        fs::create_dir_all(path)?;
    }

    #[cfg(target_family = "wasm")]
    {
        let _ = path;
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{
        ensure_sqlite_parent_dir, select_wasm_sqlite_persistence_mode, SqlitePersistenceMode,
    };

    #[test]
    fn ensure_sqlite_parent_dir_creates_missing_directory_on_native() {
        let temp_dir = tempfile::tempdir().expect("tempdir");
        let target = temp_dir.path().join("nested").join("sqlite");

        ensure_sqlite_parent_dir(&target).expect("create parent dir");

        assert!(target.is_dir());
    }

    #[test]
    fn wasm_main_thread_uses_relaxed_idb_persistence() {
        assert_eq!(
            select_wasm_sqlite_persistence_mode(false),
            SqlitePersistenceMode::RelaxedIdb,
        );
    }

    #[test]
    fn wasm_dedicated_worker_prefers_opfs_sahpool() {
        assert_eq!(
            select_wasm_sqlite_persistence_mode(true),
            SqlitePersistenceMode::OpfsSAHPool,
        );
    }
}
