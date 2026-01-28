use rusqlite::OptionalExtension;
use secondloop_rust::db;

fn table_exists(conn: &rusqlite::Connection, name: &str) -> bool {
    conn.query_row(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1",
        rusqlite::params![name],
        |row| row.get::<_, i64>(0),
    )
    .optional()
    .ok()
    .flatten()
    .is_some()
}

#[test]
fn attachment_variants_schema_migrates() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    let conn = db::open(&app_dir).expect("open db");

    assert!(table_exists(&conn, "attachment_variants"));
    assert!(table_exists(&conn, "cloud_media_backup"));
}
