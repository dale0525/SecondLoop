use rusqlite::OptionalExtension;
use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;
use std::fs;

#[path = "support/managed_vault_v2_test_server.rs"]
mod managed_vault_v2_test_server;

use managed_vault_v2_test_server::{managed_vault_v2_scope_id, start_mock_v2_server};

fn oplog_count(conn: &rusqlite::Connection) -> i64 {
    conn.query_row(r#"SELECT COUNT(*) FROM oplog"#, [], |row| row.get(0))
        .expect("count oplog")
}

#[test]
fn managed_vault_v2_push_and_pull_roundtrip() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");
    let conv_a = db::create_conversation(&conn_a, &key_a, "Inbox").expect("create convo A");
    db::insert_message(&conn_a, &key_a, &conv_a.id, "user", "hello").expect("insert msg A");

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pushed =
        sync::managed_vault::push(&conn_a, &key_a, &sync_key, &base_url, &vault_id, &id_token)
            .expect("push");
    assert!(pushed > 0);

    let pulled =
        sync::managed_vault::pull(&conn_b, &key_b, &sync_key, &base_url, &vault_id, &id_token)
            .expect("pull");
    assert!(pulled > 0);

    let convs_b = db::list_conversations(&conn_b, &key_b).expect("list convs B");
    assert_eq!(convs_b.len(), 1);
    let msgs_b = db::list_messages(&conn_b, &key_b, &convs_b[0].id).expect("list msgs B");
    assert_eq!(msgs_b.len(), 1);
    assert_eq!(msgs_b[0].content, "hello");

    let requests = state.lock().expect("lock").requests.join("\n\n");
    assert!(requests.contains("/v2/vaults/v1/sync/push"));
    assert!(requests.contains("/v2/vaults/v1/sync/pull"));
    assert!(!requests.contains("/v2/vaults/v1/sync/head"));

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_v2_push_with_progress_reports_completed_work() {
    let (base_url, stop_tx, _state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("create convo");
    db::insert_message(&conn, &key, &conversation.id, "user", "hello").expect("insert msg");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let mut seen_progress = Vec::new();
    let pushed = sync::managed_vault::push_with_progress(
        &conn,
        &key,
        &sync_key,
        &base_url,
        &vault_id,
        &id_token,
        &mut |done, total| seen_progress.push((done, total)),
    )
    .expect("push with progress");

    assert!(pushed > 0);
    assert!(
        seen_progress
            .iter()
            .any(|(done, total)| *done > 0 && *done == *total),
        "expected push progress callback to report completed work, got {seen_progress:?}"
    );
    assert_eq!(seen_progress.last().copied(), Some((pushed, pushed)));

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_v2_generation_mismatch_preserves_local_data_until_pull_recovers() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let conv = db::create_conversation(&conn, &key, "Inbox").expect("create convo");
    db::insert_message(&conn, &key, &conv.id, "user", "hello").expect("insert msg");

    let first_push =
        sync::managed_vault::push_ops_only(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
            .expect("first push");
    assert!(first_push > 0);

    {
        let mut server = state.lock().expect("lock");
        server.generation_id = "generation-reset".to_string();
        server.latest_global_seq = 0;
        server.ops.clear();
    }

    db::insert_message(&conn, &key, &conv.id, "user", "after reset")
        .expect("insert msg after reset");

    let second_push_error =
        sync::managed_vault::push_ops_only(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
            .expect_err("second push should fail");
    assert!(
        second_push_error
            .to_string()
            .contains("generation_mismatch"),
        "unexpected error: {second_push_error:#}"
    );

    let convs_before_pull = db::list_conversations(&conn, &key).expect("list convs before pull");
    assert_eq!(convs_before_pull.len(), 1);

    let recovery_pull_error =
        sync::managed_vault::pull(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
            .expect_err("recovery pull should protect local pending changes");
    assert!(
        recovery_pull_error
            .to_string()
            .contains("local_unpushed_changes"),
        "unexpected error: {recovery_pull_error:#}"
    );

    let convs_after_pull = db::list_conversations(&conn, &key).expect("list convs after pull");
    assert_eq!(convs_after_pull.len(), 1);
    let msgs_after_pull = db::list_messages(&conn, &key, &convs_after_pull[0].id)
        .expect("list msgs after guarded pull");
    assert_eq!(msgs_after_pull.len(), 2);
    assert_eq!(msgs_after_pull[1].content, "after reset");

    let state = state.lock().expect("lock");
    assert_eq!(state.latest_global_seq, 0);
    assert_eq!(state.ops.len(), 0);

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_v2_missing_local_generation_preserves_local_data_until_pull_recovers() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    {
        let mut server = state.lock().expect("lock");
        server.require_generation_for_push_without_id = true;
    }

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let conv = db::create_conversation(&conn, &key, "Inbox").expect("create convo");
    db::insert_message(&conn, &key, &conv.id, "user", "hello").expect("insert msg");

    let push_error =
        sync::managed_vault::push_ops_only(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
            .expect_err("push should fail");
    assert!(
        push_error.to_string().contains("generation_required"),
        "unexpected error: {push_error:#}"
    );

    let convs_before_pull = db::list_conversations(&conn, &key).expect("list convs before pull");
    assert_eq!(convs_before_pull.len(), 1);

    let recovery_pull =
        sync::managed_vault::pull(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
            .expect("recovery pull");
    assert_eq!(recovery_pull, 0);
    let convs_after_pull = db::list_conversations(&conn, &key).expect("list convs after pull");
    assert_eq!(convs_after_pull.len(), 1);

    let requests = state.lock().expect("lock").requests.join("\n\n");
    assert!(
        requests.contains("\"error\":\"generation_required\"")
            || requests.contains("/v2/vaults/v1/sync/push")
    );
    drop(requests);

    let state = state.lock().expect("lock");
    assert_eq!(state.ops.len(), 0);

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_v2_invalid_batch_is_reported_explicitly() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    {
        let mut server = state.lock().expect("lock");
        server.invalid_batch_once = true;
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
            .expect_err("push should fail");
    assert!(
        push_error.to_string().contains("rejected local batch"),
        "unexpected error: {push_error:#}"
    );
    assert!(
        push_error.to_string().contains("invalid_batch"),
        "unexpected error: {push_error:#}"
    );

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

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

#[test]
fn managed_vault_v2_push_uploads_new_attachment_bytes_after_initial_backfill() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    let _attachment =
        db::insert_attachment(&conn, &key, &app_dir, b"fresh attachment", "image/png")
            .expect("insert attachment");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let scope_id = managed_vault_v2_scope_id(&base_url, &vault_id);
    conn.execute(
        "INSERT INTO kv(key, value) VALUES (?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        rusqlite::params![
            format!("managed_vault.attachments.bytes_backfilled:{scope_id}"),
            "1"
        ],
    )
    .expect("seed attachment backfill flag");
    conn.execute(
        "INSERT INTO kv(key, value) VALUES (?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        rusqlite::params![
            format!("managed_vault.embedding_artifacts.bytes_backfilled:{scope_id}"),
            "1"
        ],
    )
    .expect("seed artifact backfill flag");

    let pushed = sync::managed_vault::push(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
        .expect("push");
    assert!(pushed > 0);

    let requests = state.lock().expect("lock").requests.join("\n\n");
    assert!(requests.contains("/v2/vaults/v1/sync/push"));
    assert!(requests.contains("/v1/vaults/v1/attachments/"));

    let attachment_count = state.lock().expect("lock").attachments.len();
    assert_eq!(attachment_count, 1);

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_v2_push_does_not_upload_attachment_bytes_before_commit() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    {
        let mut server = state.lock().expect("lock");
        server.require_generation_for_push_without_id = true;
    }

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    let _attachment =
        db::insert_attachment(&conn, &key, &app_dir, b"fresh attachment", "image/png")
            .expect("insert attachment");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let scope_id = managed_vault_v2_scope_id(&base_url, &vault_id);
    conn.execute(
        "INSERT INTO kv(key, value) VALUES (?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        rusqlite::params![
            format!("managed_vault.attachments.bytes_backfilled:{scope_id}"),
            "1"
        ],
    )
    .expect("seed attachment backfill flag");
    conn.execute(
        "INSERT INTO kv(key, value) VALUES (?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        rusqlite::params![
            format!("managed_vault.embedding_artifacts.bytes_backfilled:{scope_id}"),
            "1"
        ],
    )
    .expect("seed artifact backfill flag");

    let error = sync::managed_vault::push(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
        .expect_err("push should fail before commit");
    assert!(
        error.to_string().contains("generation_required"),
        "unexpected error: {error:#}"
    );

    let state = state.lock().expect("lock");
    assert!(state.attachments.is_empty());
    let requests = state.requests.join("\n\n");
    assert!(requests.contains("/v2/vaults/v1/sync/push"));
    assert!(
        !requests.contains("/v1/vaults/v1/attachments/"),
        "unexpected pre-commit attachment upload: {requests}"
    );

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_v2_push_does_not_delete_remote_attachment_bytes_before_commit() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    {
        let mut server = state.lock().expect("lock");
        server.require_generation_for_push_without_id = true;
    }

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("create convo");
    let message =
        db::insert_message(&conn, &key, &conversation.id, "user", "hello").expect("insert msg");
    let attachment = db::insert_attachment(&conn, &key, &app_dir, b"fresh attachment", "image/png")
        .expect("insert attachment");
    db::link_attachment_to_message(&conn, &key, &message.id, &attachment.sha256).expect("link");
    let deleted = db::purge_message_attachments(&conn, &key, &app_dir, &message.id)
        .expect("purge message attachments");
    assert_eq!(deleted, 1);

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let scope_id = managed_vault_v2_scope_id(&base_url, &vault_id);
    conn.execute(
        "INSERT INTO kv(key, value) VALUES (?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        rusqlite::params![
            format!("managed_vault.attachments.bytes_backfilled:{scope_id}"),
            "1"
        ],
    )
    .expect("seed attachment backfill flag");
    conn.execute(
        "INSERT INTO kv(key, value) VALUES (?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        rusqlite::params![
            format!("managed_vault.embedding_artifacts.bytes_backfilled:{scope_id}"),
            "1"
        ],
    )
    .expect("seed artifact backfill flag");

    {
        let mut server = state.lock().expect("lock");
        server
            .attachments
            .insert(attachment.sha256.clone(), b"remote attachment".to_vec());
    }

    let error = sync::managed_vault::push(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
        .expect_err("push should fail before commit");
    assert!(
        error.to_string().contains("generation_required"),
        "unexpected error: {error:#}"
    );

    let state = state.lock().expect("lock");
    assert_eq!(
        state.attachments.get(&attachment.sha256),
        Some(&b"remote attachment".to_vec())
    );
    let requests = state.requests.join("\n\n");
    assert!(requests.contains("/v2/vaults/v1/sync/push"));
    assert!(
        !requests.contains("DELETE /v1/vaults/v1/attachments/"),
        "unexpected pre-commit attachment delete: {requests}"
    );

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_v2_push_retries_remote_attachment_delete_repairs() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("create convo");
    let message =
        db::insert_message(&conn, &key, &conversation.id, "user", "hello").expect("insert msg");
    let attachment = db::insert_attachment(&conn, &key, &app_dir, b"fresh attachment", "image/png")
        .expect("insert attachment");
    db::link_attachment_to_message(&conn, &key, &message.id, &attachment.sha256).expect("link");
    let deleted = db::purge_message_attachments(&conn, &key, &app_dir, &message.id)
        .expect("purge message attachments");
    assert_eq!(deleted, 1);

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let scope_id = managed_vault_v2_scope_id(&base_url, &vault_id);
    conn.execute(
        "INSERT INTO kv(key, value) VALUES (?1, '1'), (?2, '1')
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        rusqlite::params![
            format!("managed_vault.attachments.bytes_backfilled:{scope_id}"),
            format!("managed_vault.embedding_artifacts.bytes_backfilled:{scope_id}"),
        ],
    )
    .expect("seed backfill flags");

    {
        let mut server = state.lock().expect("lock");
        server
            .attachments
            .insert(attachment.sha256.clone(), b"remote attachment".to_vec());
        server
            .delete_attachment_failures
            .insert(attachment.sha256.clone(), 2);
    }

    let pushed = sync::managed_vault::push(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
        .expect("first push");
    assert!(pushed > 0);

    let diagnostics = sync::blob_repair::load_blob_repair_diagnostics(&conn, &scope_id)
        .expect("blob repair diagnostics after failed delete");
    assert_eq!(diagnostics.queued_count, 1);
    assert!(
        state
            .lock()
            .expect("lock")
            .attachments
            .contains_key(&attachment.sha256),
        "remote attachment should still exist after failed delete"
    );

    let pushed_again =
        sync::managed_vault::push(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
            .expect("second push should drain delete repair");
    assert_eq!(pushed_again, 0);

    let diagnostics_after_retry = sync::blob_repair::load_blob_repair_diagnostics(&conn, &scope_id)
        .expect("blob repair diagnostics after retry");
    assert_eq!(diagnostics_after_retry.queued_count, 0);
    assert!(
        !state
            .lock()
            .expect("lock")
            .attachments
            .contains_key(&attachment.sha256),
        "remote attachment should be deleted after repair retry"
    );

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_legacy_full_push_only_marks_backfill_complete_when_local_media_exists() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let attachment = db::insert_attachment(&conn, &key, &app_dir, b"fresh attachment", "image/png")
        .expect("insert attachment");
    fs::remove_file(app_dir.join(&attachment.path)).expect("remove local attachment bytes");

    db::record_embedding_artifact_manifest(
        &conn,
        db::EmbeddingArtifactManifestInput {
            source_kind: "message",
            source_id: "message-1",
            source_revision: 1,
            chunk_hash: "chunk-1",
            chunk_ordinal: 0,
            profile_id: "profile-1",
            producer_device_id: Some("device-a"),
            producer_class: "desktop",
            quality_tier: "full",
            vector_format: "f32",
            dimension: 384,
            blob_ref: "blob/missing-artifact",
            created_at_ms: Some(100),
        },
    )
    .expect("record missing artifact manifest");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pushed = sync::managed_vault::push(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
        .expect("push should succeed while queueing repairs");
    assert!(pushed > 0);

    let scope_id = managed_vault_v2_scope_id(&base_url, &vault_id);
    let attachment_backfill: Option<String> = conn
        .query_row(
            "SELECT value FROM kv WHERE key = ?1",
            rusqlite::params![format!(
                "managed_vault.attachments.bytes_backfilled:{scope_id}"
            )],
            |row| row.get(0),
        )
        .optional()
        .expect("load attachment backfill");
    assert_eq!(attachment_backfill, None);

    let artifact_backfill: Option<String> = conn
        .query_row(
            "SELECT value FROM kv WHERE key = ?1",
            rusqlite::params![format!(
                "managed_vault.embedding_artifacts.bytes_backfilled:{scope_id}"
            )],
            |row| row.get(0),
        )
        .optional()
        .expect("load artifact backfill");
    assert_eq!(artifact_backfill, None);

    let diagnostics = sync::blob_repair::load_blob_repair_diagnostics(&conn, &scope_id)
        .expect("blob repair diagnostics");
    assert_eq!(diagnostics.queued_count, 2);
    assert!(state.lock().expect("lock").attachments.is_empty());

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_v2_post_commit_missing_attachment_is_queued_for_repair_and_recovers() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let attachment =
        db::insert_attachment(&conn, &key, &app_dir, b"repairable attachment", "image/png")
            .expect("insert attachment");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let scope_id = managed_vault_v2_scope_id(&base_url, &vault_id);
    conn.execute(
        "INSERT INTO kv(key, value) VALUES (?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        rusqlite::params![
            format!("managed_vault.attachments.bytes_backfilled:{scope_id}"),
            "1"
        ],
    )
    .expect("seed attachment backfill flag");
    conn.execute(
        "INSERT INTO kv(key, value) VALUES (?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        rusqlite::params![
            format!("managed_vault.embedding_artifacts.bytes_backfilled:{scope_id}"),
            "1"
        ],
    )
    .expect("seed artifact backfill flag");

    fs::remove_file(app_dir.join(&attachment.path)).expect("remove local attachment before push");

    let pushed = sync::managed_vault::push(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
        .expect("push should succeed and queue repair");
    assert!(pushed > 0);

    let diagnostics = sync::blob_repair::load_blob_repair_diagnostics(&conn, &scope_id)
        .expect("blob repair diagnostics after queued repair");
    assert_eq!(diagnostics.queued_count, 1);

    let requests_after_first_push = state.lock().expect("lock").requests.join("\n\n");
    assert!(
        requests_after_first_push.contains("/v2/vaults/v1/sync/push")
            || requests_after_first_push.contains("/v1/vaults/v1/ops:push"),
        "expected a sync push request, got {requests_after_first_push}"
    );
    assert!(
        !requests_after_first_push.contains("/v1/vaults/v1/attachments/"),
        "unexpected attachment upload before repairable local file exists: {requests_after_first_push}"
    );
    drop(requests_after_first_push);

    let attachment_backfill_after_first_push: Option<String> = conn
        .query_row(
            "SELECT value FROM kv WHERE key = ?1",
            rusqlite::params![format!(
                "managed_vault.attachments.bytes_backfilled:{scope_id}"
            )],
            |row| row.get(0),
        )
        .optional()
        .expect("load attachment backfill after queued repair");
    assert_eq!(attachment_backfill_after_first_push, None);

    let restored_attachment =
        db::insert_attachment(&conn, &key, &app_dir, b"repairable attachment", "image/png")
            .expect("restore attachment bytes");
    assert_eq!(restored_attachment.sha256, attachment.sha256);

    let second_push =
        sync::managed_vault::push(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
            .expect("second push should drain repair queue");
    assert_eq!(second_push, 0);

    let diagnostics_after_repair =
        sync::blob_repair::load_blob_repair_diagnostics(&conn, &scope_id)
            .expect("blob repair diagnostics after draining repair");
    assert_eq!(diagnostics_after_repair.queued_count, 0);

    let state = state.lock().expect("lock");
    assert!(state.attachments.contains_key(&attachment.sha256));
    let requests = state.requests.join("\n\n");
    assert!(requests.contains("/v1/vaults/v1/attachments/"));

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_v2_post_commit_attachment_upload_failure_queues_repair_without_failing_push() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let attachment = db::insert_attachment(&conn, &key, &app_dir, b"upload failure", "image/png")
        .expect("insert attachment");

    state
        .lock()
        .expect("lock")
        .put_attachment_failures
        .insert(attachment.sha256.clone(), 2);

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let scope_id = managed_vault_v2_scope_id(&base_url, &vault_id);
    conn.execute(
        "INSERT INTO kv(key, value) VALUES (?1, '1'), (?2, '1')
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        rusqlite::params![
            format!("managed_vault.attachments.bytes_backfilled:{scope_id}"),
            format!("managed_vault.embedding_artifacts.bytes_backfilled:{scope_id}"),
        ],
    )
    .expect("seed backfill flags");

    let pushed = sync::managed_vault::push(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
        .expect("push should succeed while queueing post-commit repair");
    assert!(pushed > 0);

    let diagnostics = sync::blob_repair::load_blob_repair_diagnostics(&conn, &scope_id)
        .expect("blob repair diagnostics after failed post-commit upload");
    assert_eq!(diagnostics.queued_count, 1);

    let last_pushed_seq: Option<i64> = conn
        .query_row(
            "SELECT value FROM kv WHERE key LIKE 'managed_vault_v2.last_pushed_seq:%' LIMIT 1",
            [],
            |row| row.get::<_, String>(0),
        )
        .optional()
        .expect("load last pushed seq")
        .and_then(|raw| raw.parse::<i64>().ok());
    assert!(last_pushed_seq.unwrap_or(0) > 0);

    assert!(
        !state
            .lock()
            .expect("lock")
            .attachments
            .contains_key(&attachment.sha256),
        "attachment upload should have failed on first post-commit attempt"
    );

    let second_push =
        sync::managed_vault::push(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
            .expect("second push should drain queued repair");
    assert_eq!(second_push, 0);

    let diagnostics_after_retry = sync::blob_repair::load_blob_repair_diagnostics(&conn, &scope_id)
        .expect("blob repair diagnostics after retry");
    assert_eq!(diagnostics_after_retry.queued_count, 0);
    assert!(state
        .lock()
        .expect("lock")
        .attachments
        .contains_key(&attachment.sha256));

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

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
