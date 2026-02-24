use secondloop_rust::api::oplog_maintenance::{db_run_oplog_maintenance, OplogMaintenanceBackend};
use secondloop_rust::{auth, crypto, db, sync};

#[test]
fn api_can_run_oplog_maintenance_for_localdir_scope() {
    let remote_dir = tempfile::tempdir().expect("remote dir");
    let remote = sync::localdir::LocalDirRemoteStore::new(remote_dir.path().to_path_buf())
        .expect("create localdir remote");

    let app_temp = tempfile::tempdir().expect("temp dir");
    let app_dir = app_temp.path().join("secondloop_app");
    let key = auth::init_master_password(&app_dir, "pw-a", crypto::KdfParams::for_test())
        .expect("init key");
    let conn = db::open(&app_dir).expect("open db");

    let conv = db::get_or_create_loop_home_conversation(&conn, &key).expect("loop home");
    for i in 0..40 {
        db::insert_message(&conn, &key, &conv.id, "user", &format!("message #{i}"))
            .expect("insert message");
    }

    let sync_key = crypto::derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &crypto::KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pushed = sync::push(&conn, &key, &sync_key, &remote, "SecondLoopTest").expect("push");
    assert!(pushed > 0);

    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES ('oplog.retention.keep_recent_ops', '0')
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        [],
    )
    .expect("set keep_recent_ops");
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES ('oplog.retention.keep_recent_days', '0')
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        [],
    )
    .expect("set keep_recent_days");

    let scope_key: String = conn
        .query_row(
            r#"SELECT key FROM kv WHERE key LIKE 'sync.last_pushed_seq:%' LIMIT 1"#,
            [],
            |row| row.get(0),
        )
        .expect("scope key");
    let scope_id = scope_key
        .strip_prefix("sync.last_pushed_seq:")
        .expect("scope key prefix")
        .to_string();

    let before = conn
        .query_row(r#"SELECT COUNT(*) FROM oplog"#, [], |row| {
            row.get::<_, i64>(0)
        })
        .expect("count before")
        .max(0) as u64;

    let stats = db_run_oplog_maintenance(
        app_dir.to_string_lossy().to_string(),
        key.to_vec(),
        OplogMaintenanceBackend::LocalDir,
        scope_id,
    )
    .expect("run maintenance");

    assert_eq!(stats.before_count, before);
    assert!(stats.pruned_count > 0);
    assert!(stats.after_count < stats.before_count);
}
