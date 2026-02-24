use secondloop_rust::auth;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::db;

fn seed_ops(conn: &rusqlite::Connection, key: &[u8; 32], n_messages: usize) -> i64 {
    let conversation =
        db::create_conversation(conn, key, "Retention").expect("create conversation");
    for i in 0..n_messages {
        let content = format!("message-{i}");
        db::insert_message(conn, key, &conversation.id, "user", &content).expect("insert message");
    }
    conn.query_row(r#"SELECT MAX(seq) FROM oplog"#, [], |row| {
        row.get::<_, i64>(0)
    })
    .expect("max seq")
}

fn oplog_count(conn: &rusqlite::Connection) -> i64 {
    conn.query_row(r#"SELECT COUNT(*) FROM oplog"#, [], |row| row.get(0))
        .expect("count oplog")
}

fn init_db() -> (tempfile::TempDir, rusqlite::Connection, [u8; 32]) {
    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key =
        auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init master");
    let conn = db::open(&app_dir).expect("open db");
    (temp, conn, key)
}

#[test]
fn oplog_retention_prunes_for_webdav_backend() {
    let (_temp, conn, key) = init_db();
    let max_seq = seed_ops(&conn, &key, 8);

    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES (?1, ?2)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        rusqlite::params!["oplog.retention.enabled", "1"],
    )
    .expect("set enabled");
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES (?1, ?2)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        rusqlite::params!["oplog.retention.backend.webdav", "1"],
    )
    .expect("set webdav enabled");
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES (?1, ?2)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        rusqlite::params!["oplog.retention.keep_recent_ops", "2"],
    )
    .expect("set keep_recent_ops");
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES (?1, ?2)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        rusqlite::params!["oplog.retention.keep_recent_days", "0"],
    )
    .expect("set keep_recent_days");
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES (?1, ?2)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        rusqlite::params!["sync.last_pushed_seq:webdav_scope", max_seq.to_string()],
    )
    .expect("set last pushed");

    let before = oplog_count(&conn);
    let stats = db::run_oplog_retention_maintenance(
        &conn,
        db::OplogRetentionBackend::WebDav,
        "webdav_scope",
    )
    .expect("run maintenance");

    assert!(stats.pruned_count > 0, "expected webdav pruning");
    let after = oplog_count(&conn);
    assert!(after < before, "expected oplog rows reduced");
    assert!(after <= 2, "expected keep_recent_ops applied, got {after}");
}

#[test]
fn oplog_retention_prunes_for_localdir_backend() {
    let (_temp, conn, key) = init_db();
    let max_seq = seed_ops(&conn, &key, 8);

    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES (?1, ?2)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        rusqlite::params!["oplog.retention.enabled", "1"],
    )
    .expect("set enabled");
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES (?1, ?2)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        rusqlite::params!["oplog.retention.backend.localdir", "1"],
    )
    .expect("set localdir enabled");
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES (?1, ?2)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        rusqlite::params!["oplog.retention.keep_recent_ops", "3"],
    )
    .expect("set keep_recent_ops");
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES (?1, ?2)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        rusqlite::params!["oplog.retention.keep_recent_days", "0"],
    )
    .expect("set keep_recent_days");
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES (?1, ?2)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        rusqlite::params!["sync.last_pushed_seq:local_scope", max_seq.to_string()],
    )
    .expect("set last pushed");

    let stats = db::run_oplog_retention_maintenance(
        &conn,
        db::OplogRetentionBackend::LocalDir,
        "local_scope",
    )
    .expect("run maintenance");

    assert!(stats.pruned_count > 0, "expected localdir pruning");
    let after = oplog_count(&conn);
    assert!(after <= 3, "expected keep_recent_ops applied, got {after}");
}

#[test]
fn oplog_retention_prunes_for_managed_vault_backend() {
    let (_temp, conn, key) = init_db();
    let max_seq = seed_ops(&conn, &key, 9);
    let device_id: String = conn
        .query_row(
            r#"SELECT value FROM kv WHERE key = 'device_id'"#,
            [],
            |row| row.get(0),
        )
        .expect("device id");

    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES (?1, ?2)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        rusqlite::params!["oplog.retention.enabled", "1"],
    )
    .expect("set enabled");
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES (?1, ?2)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        rusqlite::params!["oplog.retention.backend.managed_vault", "1"],
    )
    .expect("set managed enabled");
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES (?1, ?2)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        rusqlite::params!["oplog.retention.keep_recent_ops", "4"],
    )
    .expect("set keep_recent_ops");
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES (?1, ?2)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        rusqlite::params!["oplog.retention.keep_recent_days", "0"],
    )
    .expect("set keep_recent_days");
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES (?1, ?2)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        rusqlite::params![
            format!("managed_vault.last_pushed_seq:mv_scope:{device_id}"),
            max_seq.to_string()
        ],
    )
    .expect("set managed last pushed");

    let stats = db::run_oplog_retention_maintenance(
        &conn,
        db::OplogRetentionBackend::ManagedVault,
        "mv_scope",
    )
    .expect("run maintenance");

    assert!(stats.pruned_count > 0, "expected managed vault pruning");
    let after = oplog_count(&conn);
    assert!(after <= 4, "expected keep_recent_ops applied, got {after}");
}

#[test]
fn oplog_retention_respects_backend_switch() {
    let (_temp, conn, key) = init_db();
    let max_seq = seed_ops(&conn, &key, 7);

    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES (?1, ?2)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        rusqlite::params!["oplog.retention.enabled", "1"],
    )
    .expect("set enabled");
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES (?1, ?2)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        rusqlite::params!["oplog.retention.backend.webdav", "0"],
    )
    .expect("disable webdav backend");
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES (?1, ?2)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        rusqlite::params!["oplog.retention.keep_recent_ops", "2"],
    )
    .expect("set keep_recent_ops");
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES (?1, ?2)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        rusqlite::params!["oplog.retention.keep_recent_days", "0"],
    )
    .expect("set keep_recent_days");
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES (?1, ?2)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        rusqlite::params!["sync.last_pushed_seq:webdav_scope", max_seq.to_string()],
    )
    .expect("set last pushed");

    let before = oplog_count(&conn);
    let stats = db::run_oplog_retention_maintenance(
        &conn,
        db::OplogRetentionBackend::WebDav,
        "webdav_scope",
    )
    .expect("run maintenance");
    let after = oplog_count(&conn);

    assert_eq!(stats.pruned_count, 0, "backend switch should block pruning");
    assert_eq!(after, before, "row count should remain unchanged");
}
