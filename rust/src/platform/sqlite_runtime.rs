use anyhow::Result;
use std::path::Path;

#[cfg(not(target_family = "wasm"))]
use std::fs;

#[cfg(target_family = "wasm")]
use core::time::Duration;

#[cfg(target_family = "wasm")]
use getrandom::getrandom;

#[cfg(target_family = "wasm")]
use js_sys::Date;

#[cfg(target_family = "wasm")]
use rsqlite_vfs::OsCallback;

#[cfg(target_family = "wasm")]
use std::sync::OnceLock;

#[cfg(target_family = "wasm")]
use sqlite_wasm_vfs::sahpool::{install as install_opfs_sahpool, OpfsSAHPoolCfg};

#[cfg(target_family = "wasm")]
static SQLITE_RUNTIME_READY: OnceLock<()> = OnceLock::new();

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

pub async fn ensure_ready() -> Result<()> {
    #[cfg(target_family = "wasm")]
    {
        if SQLITE_RUNTIME_READY.get().is_none() {
            install_opfs_sahpool::<WasmSqliteOsCallback>(&OpfsSAHPoolCfg::default(), true)
                .await
                .map_err(|error| anyhow::anyhow!("install opfs sahpool failed: {error:?}"))?;
            let _ = SQLITE_RUNTIME_READY.set(());
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
    use super::ensure_sqlite_parent_dir;

    #[test]
    fn ensure_sqlite_parent_dir_creates_missing_directory_on_native() {
        let temp_dir = tempfile::tempdir().expect("tempdir");
        let target = temp_dir.path().join("nested").join("sqlite");

        ensure_sqlite_parent_dir(&target).expect("create parent dir");

        assert!(target.is_dir());
    }
}
