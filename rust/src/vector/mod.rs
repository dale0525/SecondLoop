use anyhow::Result;
#[cfg(not(target_family = "wasm"))]
use rusqlite::ffi::sqlite3_auto_extension;
#[cfg(not(target_family = "wasm"))]
use sqlite_vec::sqlite3_vec_init;
#[cfg(not(target_family = "wasm"))]
use std::sync::OnceLock;

#[cfg(not(target_family = "wasm"))]
static SQLITE_VEC_REGISTERED: OnceLock<()> = OnceLock::new();

pub const fn is_available() -> bool {
    !cfg!(target_family = "wasm")
}

#[cfg(not(target_family = "wasm"))]
type Sqlite3ExtensionInit = unsafe extern "C" fn(
    *mut rusqlite::ffi::sqlite3,
    *mut *mut std::os::raw::c_char,
    *const rusqlite::ffi::sqlite3_api_routines,
) -> std::os::raw::c_int;

pub fn register_sqlite_vec() -> Result<()> {
    if !is_available() {
        return Ok(());
    }

    #[cfg(not(target_family = "wasm"))]
    SQLITE_VEC_REGISTERED.get_or_init(|| unsafe {
        sqlite3_auto_extension(Some(
            std::mem::transmute::<*const (), Sqlite3ExtensionInit>(sqlite3_vec_init as *const ()),
        ));
    });
    Ok(())
}
