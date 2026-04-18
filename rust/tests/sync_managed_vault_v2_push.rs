use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;

#[path = "support/managed_vault_v2_test_server.rs"]
mod managed_vault_v2_test_server;

use managed_vault_v2_test_server::{managed_vault_v2_scope_id, start_mock_v2_server};

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
