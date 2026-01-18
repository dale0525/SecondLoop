use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;
use secondloop_rust::sync::RemoteStore;

#[test]
fn pull_recovers_after_pruned_initial_ops() {
    let remote_root = "SecondLoopTest";

    // Device A creates some data locally (two conversations so later ops still work if early ops are pruned).
    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");

    let conv1 = db::create_conversation(&conn_a, &key_a, "Inbox").expect("create convo 1");
    db::insert_message(&conn_a, &key_a, &conv1.id, "user", "hello").expect("insert msg 1");

    let conv2 = db::create_conversation(&conn_a, &key_a, "Later").expect("create convo 2");
    db::insert_message(&conn_a, &key_a, &conv2.id, "user", "hi").expect("insert msg 2");

    let device_id_a: String = conn_a
        .query_row(
            r#"SELECT value FROM kv WHERE key = 'device_id'"#,
            [],
            |row| row.get(0),
        )
        .expect("device_id exists");

    // Push A -> remote.
    let remote = sync::InMemoryRemoteStore::new();
    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");
    let pushed = sync::push(&conn_a, &key_a, &sync_key, &remote, remote_root).expect("push");
    assert!(pushed >= 4, "expected at least 4 ops pushed, got {pushed}");

    // Simulate remote pruning: remove the initial ops files for device A.
    let remote_root_dir = format!("/{}/", remote_root.trim_matches('/'));
    remote
        .delete(&format!(
            "{remote_root_dir}{device_id_a}/ops/op_1.json"
        ))
        .expect("delete op_1");
    remote
        .delete(&format!(
            "{remote_root_dir}{device_id_a}/ops/op_2.json"
        ))
        .expect("delete op_2");

    // Device B pulls from a remote where ops start at a higher seq.
    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let applied = sync::pull(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("pull");
    assert!(applied > 0, "expected pull to apply ops after pruning");

    let convs_b = db::list_conversations(&conn_b, &key_b).expect("list convs B");
    assert!(
        convs_b.iter().any(|c| c.title == "Later"),
        "expected 'Later' conversation to be pulled"
    );
}
