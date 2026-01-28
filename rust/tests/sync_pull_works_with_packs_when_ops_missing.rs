use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;
use secondloop_rust::sync::RemoteStore;

#[test]
fn pull_works_with_packs_when_ops_files_are_missing() {
    let remote = sync::InMemoryRemoteStore::new();
    let remote_root = "SecondLoopTest";

    // Device A creates data locally.
    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");
    let conv_a = db::create_conversation(&conn_a, &key_a, "Inbox").expect("create convo A");
    db::insert_message(&conn_a, &key_a, &conv_a.id, "user", "hello").expect("insert msg A");

    let device_id_a: String = conn_a
        .query_row(
            r#"SELECT value FROM kv WHERE key = 'device_id'"#,
            [],
            |row| row.get(0),
        )
        .expect("device_id exists");

    // Shared sync key derived from a shared passphrase (same on both devices).
    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pushed = sync::push(&conn_a, &key_a, &sync_key, &remote, remote_root).expect("push");
    assert!(pushed > 0);

    // Simulate a WebDAV implementation that doesn't keep per-op files (or lost them), but keeps
    // pack files.
    let remote_root_dir = format!("/{}/", remote_root.trim_matches('/'));
    let ops_dir = format!("{remote_root_dir}{device_id_a}/ops/");
    remote.delete(&ops_dir).expect("delete ops dir");

    // Device B is a fresh install (different local root key).
    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let applied = sync::pull(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("pull");
    assert!(
        applied > 0,
        "expected pull to apply ops even if per-op files are missing"
    );

    let convs_b = db::list_conversations(&conn_b, &key_b).expect("list convs B");
    assert_eq!(convs_b.len(), 1);
    assert_eq!(convs_b[0].title, "Inbox");
    assert_eq!(convs_b[0].id, conv_a.id);

    let msgs_b = db::list_messages(&conn_b, &key_b, &convs_b[0].id).expect("list msgs B");
    assert_eq!(msgs_b.len(), 1);
    assert_eq!(msgs_b[0].content, "hello");
}
