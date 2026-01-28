use secondloop_rust::db;

#[test]
fn db_open_enables_wal() {
    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let conn = db::open(&app_dir).expect("open db");

    let journal_mode: String = conn
        .query_row("PRAGMA journal_mode;", [], |row| row.get(0))
        .expect("read journal_mode");
    assert_eq!(journal_mode.to_lowercase(), "wal");

    let busy_timeout_ms: i64 = conn
        .query_row("PRAGMA busy_timeout;", [], |row| row.get(0))
        .expect("read busy_timeout");
    assert!(
        busy_timeout_ms >= 5_000,
        "expected busy_timeout >= 5000ms, got {busy_timeout_ms}"
    );
}
