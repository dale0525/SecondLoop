use super::*;

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
fn managed_vault_v2_third_device_pulls_second_device_changes_after_initial_roundtrip() {
    let (base_url, stop_tx, _state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");
    let conv_a = db::create_conversation(&conn_a, &key_a, "Inbox").expect("create convo A");
    db::insert_message(&conn_a, &key_a, &conv_a.id, "user", "hello from A").expect("insert msg A");
    let pushed_a =
        sync::managed_vault::push(&conn_a, &key_a, &sync_key, &base_url, &vault_id, &id_token)
            .expect("push A");
    assert!(pushed_a > 0);

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");
    let pulled_b =
        sync::managed_vault::pull(&conn_b, &key_b, &sync_key, &base_url, &vault_id, &id_token)
            .expect("pull B");
    assert!(pulled_b > 0);

    let temp_c = tempfile::tempdir().expect("tempdir C");
    let app_dir_c = temp_c.path().join("secondloop_c");
    let key_c =
        auth::init_master_password(&app_dir_c, "pw-c", KdfParams::for_test()).expect("init C");
    let conn_c = db::open(&app_dir_c).expect("open C db");
    let pulled_c =
        sync::managed_vault::pull(&conn_c, &key_c, &sync_key, &base_url, &vault_id, &id_token)
            .expect("pull C");
    assert!(pulled_c > 0);

    let convs_b = db::list_conversations(&conn_b, &key_b).expect("list convs B");
    assert_eq!(convs_b.len(), 1);
    db::insert_message(&conn_b, &key_b, &convs_b[0].id, "user", "hello from B")
        .expect("insert msg B");
    let pushed_b =
        sync::managed_vault::push(&conn_b, &key_b, &sync_key, &base_url, &vault_id, &id_token)
            .expect("push B");
    assert!(pushed_b > 0);

    let pulled_c_again =
        sync::managed_vault::pull(&conn_c, &key_c, &sync_key, &base_url, &vault_id, &id_token)
            .expect("pull C again");
    assert!(pulled_c_again > 0);

    let convs_c = db::list_conversations(&conn_c, &key_c).expect("list convs C");
    assert_eq!(convs_c.len(), 1);
    let msgs_c = db::list_messages(&conn_c, &key_c, &convs_c[0].id).expect("list msgs C");
    assert_eq!(msgs_c.len(), 2);
    assert_eq!(msgs_c[0].content, "hello from A");
    assert_eq!(msgs_c[1].content, "hello from B");

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_v2_progress_paths_propagate_second_device_changes_to_third_device() {
    let (base_url, stop_tx, _state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");
    let conv_a = db::create_conversation(&conn_a, &key_a, "Inbox").expect("create convo A");
    db::insert_message(&conn_a, &key_a, &conv_a.id, "user", "hello from A").expect("insert msg A");
    let mut progress_a = Vec::new();
    let pushed_a = sync::managed_vault::push_ops_only_with_progress(
        &conn_a,
        &key_a,
        &sync_key,
        &base_url,
        &vault_id,
        &id_token,
        &mut |done, total| progress_a.push((done, total)),
    )
    .expect("push A");
    assert!(pushed_a > 0);
    assert_eq!(progress_a.last().copied(), Some((pushed_a, pushed_a)));

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");
    let mut pull_progress_b = Vec::new();
    let pulled_b = sync::managed_vault::pull_with_progress(
        &conn_b,
        &key_b,
        &sync_key,
        &base_url,
        &vault_id,
        &id_token,
        &mut |done, total| pull_progress_b.push((done, total)),
    )
    .expect("pull B");
    assert!(pulled_b > 0);
    assert!(pull_progress_b
        .iter()
        .any(|(done, total)| done == total && *done > 0));

    let temp_c = tempfile::tempdir().expect("tempdir C");
    let app_dir_c = temp_c.path().join("secondloop_c");
    let key_c =
        auth::init_master_password(&app_dir_c, "pw-c", KdfParams::for_test()).expect("init C");
    let conn_c = db::open(&app_dir_c).expect("open C db");
    let mut pull_progress_c = Vec::new();
    let pulled_c = sync::managed_vault::pull_with_progress(
        &conn_c,
        &key_c,
        &sync_key,
        &base_url,
        &vault_id,
        &id_token,
        &mut |done, total| pull_progress_c.push((done, total)),
    )
    .expect("pull C");
    assert!(pulled_c > 0);
    assert!(pull_progress_c
        .iter()
        .any(|(done, total)| done == total && *done > 0));

    let convs_b = db::list_conversations(&conn_b, &key_b).expect("list convs B");
    db::insert_message(&conn_b, &key_b, &convs_b[0].id, "user", "hello from B")
        .expect("insert msg B");
    let mut push_progress_b = Vec::new();
    let pushed_b = sync::managed_vault::push_ops_only_with_progress(
        &conn_b,
        &key_b,
        &sync_key,
        &base_url,
        &vault_id,
        &id_token,
        &mut |done, total| push_progress_b.push((done, total)),
    )
    .expect("push B");
    assert!(pushed_b > 0);
    assert_eq!(push_progress_b.last().copied(), Some((pushed_b, pushed_b)));

    let mut pull_progress_c_again = Vec::new();
    let pulled_c_again = sync::managed_vault::pull_with_progress(
        &conn_c,
        &key_c,
        &sync_key,
        &base_url,
        &vault_id,
        &id_token,
        &mut |done, total| pull_progress_c_again.push((done, total)),
    )
    .expect("pull C again");
    assert!(pulled_c_again > 0);
    assert!(pull_progress_c_again
        .iter()
        .any(|(done, total)| done == total && *done > 0));

    let convs_c = db::list_conversations(&conn_c, &key_c).expect("list convs C");
    assert_eq!(convs_c.len(), 1);
    let msgs_c = db::list_messages(&conn_c, &key_c, &convs_c[0].id).expect("list msgs C");
    assert_eq!(msgs_c.len(), 2);
    assert_eq!(msgs_c[0].content, "hello from A");
    assert_eq!(msgs_c[1].content, "hello from B");

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
