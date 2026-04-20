use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;

#[path = "support/managed_vault_v2_test_server.rs"]
mod managed_vault_v2_test_server;

use managed_vault_v2_test_server::start_mock_v2_server;

#[test]
fn managed_vault_v2_pull_fails_when_generation_keeps_switching_after_rebuild() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
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
    db::insert_message(&conn_a, &key_a, &conv_a.id, "user", "generation-a").expect("insert msg A");
    let pushed_a =
        sync::managed_vault::push(&conn_a, &key_a, &sync_key, &base_url, &vault_id, &id_token)
            .expect("push A");
    assert!(pushed_a > 0);

    let (generation_a, latest_a, ops_a) = {
        let server = state.lock().expect("lock");
        (
            server.generation_id.clone(),
            server.latest_global_seq,
            server.ops.clone(),
        )
    };

    {
        let mut server = state.lock().expect("lock");
        server.generation_id = "generation-b".to_string();
        server.latest_global_seq = 0;
        server.ops.clear();
    }

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");
    let conv_b = db::create_conversation(&conn_b, &key_b, "Inbox").expect("create convo B");
    db::insert_message(&conn_b, &key_b, &conv_b.id, "user", "generation-b").expect("insert msg B");
    let pushed_b =
        sync::managed_vault::push(&conn_b, &key_b, &sync_key, &base_url, &vault_id, &id_token)
            .expect("push B");
    assert!(pushed_b > 0);

    let (generation_b, latest_b, ops_b) = {
        let server = state.lock().expect("lock");
        (
            server.generation_id.clone(),
            server.latest_global_seq,
            server.ops.clone(),
        )
    };

    {
        let mut server = state.lock().expect("lock");
        server.generation_id = "generation-c".to_string();
        server.latest_global_seq = 0;
        server.ops.clear();
    }

    let temp_c = tempfile::tempdir().expect("tempdir C");
    let app_dir_c = temp_c.path().join("secondloop_c");
    let key_c =
        auth::init_master_password(&app_dir_c, "pw-c", KdfParams::for_test()).expect("init C");
    let conn_c = db::open(&app_dir_c).expect("open C db");
    let conv_c = db::create_conversation(&conn_c, &key_c, "Inbox").expect("create convo C");
    db::insert_message(&conn_c, &key_c, &conv_c.id, "user", "generation-c").expect("insert msg C");
    let pushed_c =
        sync::managed_vault::push(&conn_c, &key_c, &sync_key, &base_url, &vault_id, &id_token)
            .expect("push C");
    assert!(pushed_c > 0);

    let (generation_c, latest_c, ops_c) = {
        let server = state.lock().expect("lock");
        (
            server.generation_id.clone(),
            server.latest_global_seq,
            server.ops.clone(),
        )
    };

    {
        let mut server = state.lock().expect("lock");
        server.generation_id = generation_a;
        server.latest_global_seq = latest_a;
        server.ops = ops_a;
        server.pull_page_size = Some(1);
        server.queued_generation_switches = vec![
            (1, generation_b, latest_b, ops_b),
            (1, generation_c, latest_c, ops_c),
        ];
    }

    let temp_puller = tempfile::tempdir().expect("tempdir puller");
    let app_dir_puller = temp_puller.path().join("secondloop_puller");
    let key_puller = auth::init_master_password(&app_dir_puller, "pw-pull", KdfParams::for_test())
        .expect("init puller");
    let conn_puller = db::open(&app_dir_puller).expect("open puller db");

    let error = sync::managed_vault::pull(
        &conn_puller,
        &key_puller,
        &sync_key,
        &base_url,
        &vault_id,
        &id_token,
    )
    .expect_err("repeated generation mismatch should fail");
    assert!(
        error
            .to_string()
            .contains("generation mismatch persisted after local rebuild"),
        "unexpected error: {error:#}"
    );

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}
