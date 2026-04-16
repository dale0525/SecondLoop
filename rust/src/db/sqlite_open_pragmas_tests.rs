use super::{sqlite_open_pragmas_for_mode, SqliteOpenPragmas};
use crate::platform::sqlite_runtime::SqlitePersistenceMode;

#[test]
fn native_filesystem_keeps_wal_defaults() {
    assert_eq!(
        sqlite_open_pragmas_for_mode(SqlitePersistenceMode::NativeFilesystem),
        SqliteOpenPragmas {
            journal_mode: "WAL",
            synchronous: None,
        },
    );
}

#[test]
fn relaxed_idb_uses_delete_journal_and_synchronous_off() {
    assert_eq!(
        sqlite_open_pragmas_for_mode(SqlitePersistenceMode::RelaxedIdb),
        SqliteOpenPragmas {
            journal_mode: "DELETE",
            synchronous: Some("OFF"),
        },
    );
}
