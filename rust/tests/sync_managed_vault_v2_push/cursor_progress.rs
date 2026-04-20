use super::*;

#[test]
fn managed_vault_v2_partial_acceptance_does_not_advance_local_push_cursor() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    {
        let mut server = state.lock().expect("lock");
        server.partial_accept_count_once = Some(1);
    }

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    let conv = db::create_conversation(&conn, &key, "Inbox").expect("create convo");
    db::insert_message(&conn, &key, &conv.id, "user", "hello").expect("insert msg");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let push_error =
        sync::managed_vault::push_ops_only(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
            .expect_err("push should fail on partial acceptance");
    assert!(
        push_error.to_string().contains("partial acceptance"),
        "unexpected error: {push_error:#}"
    );

    let device_id: String = conn
        .query_row("SELECT value FROM kv WHERE key = 'device_id'", [], |row| {
            row.get(0)
        })
        .expect("device id");
    let scope_id = managed_vault_v2_scope_id(&base_url, &vault_id);
    let last_pushed: Option<String> = conn
        .query_row(
            "SELECT value FROM kv WHERE key = ?1",
            rusqlite::params![format!(
                "managed_vault_v2.last_pushed_seq:{scope_id}:{device_id}"
            )],
            |row| row.get(0),
        )
        .optional()
        .expect("load last pushed");
    assert_eq!(last_pushed, None);

    let state = state.lock().expect("lock");
    assert_eq!(state.latest_global_seq, 1);

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_v2_zero_acceptance_does_not_advance_local_push_cursor() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    {
        let mut server = state.lock().expect("lock");
        server.partial_accept_count_once = Some(0);
    }

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    let conv = db::create_conversation(&conn, &key, "Inbox").expect("create convo");
    db::insert_message(&conn, &key, &conv.id, "user", "hello").expect("insert msg");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let push_error =
        sync::managed_vault::push_ops_only(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
            .expect_err("push should fail on zero acceptance");
    assert!(
        push_error.to_string().contains("accepted=0 for"),
        "unexpected error: {push_error:#}"
    );

    let device_id: String = conn
        .query_row("SELECT value FROM kv WHERE key = 'device_id'", [], |row| {
            row.get(0)
        })
        .expect("device id");
    let scope_id = managed_vault_v2_scope_id(&base_url, &vault_id);
    let last_pushed: Option<String> = conn
        .query_row(
            "SELECT value FROM kv WHERE key = ?1",
            rusqlite::params![format!(
                "managed_vault_v2.last_pushed_seq:{scope_id}:{device_id}"
            )],
            |row| row.get(0),
        )
        .optional()
        .expect("load last pushed");
    assert_eq!(last_pushed, None);

    let state = state.lock().expect("lock");
    assert_eq!(state.latest_global_seq, 0);
    assert!(state.ops.is_empty());

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_v2_identical_replay_advances_local_push_cursor() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    let conv = db::create_conversation(&conn, &key, "Inbox").expect("create convo");
    db::insert_message(&conn, &key, &conv.id, "user", "hello").expect("insert msg");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let initial_pushed =
        sync::managed_vault::push_ops_only(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
            .expect("initial push");
    assert!(initial_pushed > 0);

    let device_id: String = conn
        .query_row("SELECT value FROM kv WHERE key = 'device_id'", [], |row| {
            row.get(0)
        })
        .expect("device id");
    let scope_id = managed_vault_v2_scope_id(&base_url, &vault_id);
    conn.execute(
        "DELETE FROM kv WHERE key = ?1",
        rusqlite::params![format!(
            "managed_vault_v2.last_pushed_seq:{scope_id}:{device_id}"
        )],
    )
    .expect("clear local push cursor");

    let pushed =
        sync::managed_vault::push_ops_only(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
            .expect("push should treat replay as success");
    assert_eq!(pushed, initial_pushed);

    let last_pushed: Option<String> = conn
        .query_row(
            "SELECT value FROM kv WHERE key = ?1",
            rusqlite::params![format!(
                "managed_vault_v2.last_pushed_seq:{scope_id}:{device_id}"
            )],
            |row| row.get(0),
        )
        .optional()
        .expect("load last pushed");
    let expected_last_pushed = initial_pushed.to_string();
    assert_eq!(last_pushed.as_deref(), Some(expected_last_pushed.as_str()));
    assert_eq!(
        state.lock().expect("lock").latest_global_seq,
        initial_pushed as i64
    );

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_v2_mixed_replay_and_new_ops_advance_local_push_cursor() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    let conv = db::create_conversation(&conn, &key, "Inbox").expect("create convo");
    db::insert_message(&conn, &key, &conv.id, "user", "hello").expect("insert msg");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let initial_pushed =
        sync::managed_vault::push_ops_only(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
            .expect("initial push");
    assert!(initial_pushed > 0);

    let device_id: String = conn
        .query_row("SELECT value FROM kv WHERE key = 'device_id'", [], |row| {
            row.get(0)
        })
        .expect("device id");
    let scope_id = managed_vault_v2_scope_id(&base_url, &vault_id);
    conn.execute(
        "DELETE FROM kv WHERE key = ?1",
        rusqlite::params![format!(
            "managed_vault_v2.last_pushed_seq:{scope_id}:{device_id}"
        )],
    )
    .expect("clear local push cursor");

    db::insert_message(&conn, &key, &conv.id, "user", "after replay").expect("insert second msg");

    let remote_global_seq;
    {
        let mut server = state.lock().expect("lock");
        remote_global_seq = server.latest_global_seq + 1;
        server.latest_global_seq = remote_global_seq;
        server.ops.push(serde_json::json!({
            "global_seq": remote_global_seq,
            "device_id": "dev-remote",
            "seq": 1,
            "op_id": "remote-op",
            "client_op_id": "remote-op",
            "ciphertext_b64": "WA==",
        }));
    }

    let pushed =
        sync::managed_vault::push_ops_only(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
            .expect("mixed replay push should succeed");
    assert!(pushed >= initial_pushed);

    let last_pushed: Option<String> = conn
        .query_row(
            "SELECT value FROM kv WHERE key = ?1",
            rusqlite::params![format!(
                "managed_vault_v2.last_pushed_seq:{scope_id}:{device_id}"
            )],
            |row| row.get(0),
        )
        .optional()
        .expect("load last pushed");
    let expected_last_pushed = pushed.to_string();
    assert_eq!(last_pushed.as_deref(), Some(expected_last_pushed.as_str()));

    let state = state.lock().expect("lock");
    assert_eq!(state.latest_global_seq, remote_global_seq + 1);
    assert!(
        state
            .ops
            .iter()
            .any(|op| op["client_op_id"].as_str() == Some("remote-op")),
        "expected mixed replay scenario to preserve the interleaved remote op",
    );

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}
