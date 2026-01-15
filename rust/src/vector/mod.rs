use std::sync::OnceLock;

use anyhow::Result;
use rusqlite::ffi::sqlite3_auto_extension;
use sqlite_vec::sqlite3_vec_init;

static SQLITE_VEC_REGISTERED: OnceLock<()> = OnceLock::new();

pub fn register_sqlite_vec() -> Result<()> {
    SQLITE_VEC_REGISTERED.get_or_init(|| {
        unsafe {
            sqlite3_auto_extension(Some(std::mem::transmute(sqlite3_vec_init as *const ())));
        }
    });
    Ok(())
}
