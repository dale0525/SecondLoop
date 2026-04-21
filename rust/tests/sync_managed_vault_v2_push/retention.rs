use super::*;

#[test]
fn managed_vault_v2_push_runs_managed_vault_retention_after_success() {
    let (base_url, stop_tx, _state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Retention").expect("create convo");
    for index in 0..8 {
        db::insert_message(
            &conn,
            &key,
            &conversation.id,
            "user",
            &format!("message-{index}"),
        )
        .expect("insert message");
    }

    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES (?1, ?2)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        rusqlite::params!["oplog.retention.enabled", "1"],
    )
    .expect("set retention enabled");
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES (?1, ?2)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        rusqlite::params!["oplog.retention.backend.managed_vault", "1"],
    )
    .expect("set managed retention enabled");
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES (?1, ?2)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        rusqlite::params!["oplog.retention.keep_recent_ops", "2"],
    )
    .expect("set keep recent ops");
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES (?1, ?2)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        rusqlite::params!["oplog.retention.keep_recent_days", "0"],
    )
    .expect("set keep recent days");

    let before = oplog_count(&conn);
    assert!(
        before > 2,
        "expected enough oplog rows before push, got {before}"
    );

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pushed = sync::managed_vault::push(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
        .expect("push");
    assert!(pushed > 0);

    let after = oplog_count(&conn);
    assert!(after < before, "expected retention to reduce oplog rows");
    assert!(after <= 2, "expected keep_recent_ops applied, got {after}");

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}
