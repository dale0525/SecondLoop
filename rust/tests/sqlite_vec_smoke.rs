use rusqlite::Connection;

#[test]
fn sqlite_vec_is_available() {
    secondloop_rust::vector::register_sqlite_vec().expect("register sqlite-vec");

    let conn = Connection::open_in_memory().expect("open");
    let version: String = conn
        .query_row("select vec_version()", [], |row| row.get(0))
        .expect("vec_version()");

    assert!(version.starts_with('v'));
}

