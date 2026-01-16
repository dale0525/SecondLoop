use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;

#[test]
fn sync_localdir_push_then_pull_copies_messages() {
    let remote_dir = tempfile::tempdir().expect("remote dir");
    let remote = sync::localdir::LocalDirRemoteStore::new(remote_dir.path().to_path_buf())
        .expect("create localdir remote");
    let remote_root = "SecondLoopTest";

    // Device A creates data locally.
    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a = auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test())
        .expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");
    let conv_a = db::get_or_create_main_stream_conversation(&conn_a, &key_a)
        .expect("main stream A");
    db::insert_message(&conn_a, &key_a, &conv_a.id, "user", "hello").expect("insert msg A");

    // Device B is a fresh install (different local root key).
    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b = auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test())
        .expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let sync_key = derive_root_key("sync-passphrase", b"secondloop-sync1", &KdfParams::for_test())
        .expect("derive sync key");

    let pushed = sync::push(&conn_a, &key_a, &sync_key, &remote, remote_root).expect("push");
    assert!(pushed > 0);

    let applied = sync::pull(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("pull");
    assert!(applied > 0);

    let msgs_b = db::list_messages(&conn_b, &key_b, &conv_a.id).expect("list msgs B");
    assert_eq!(msgs_b.len(), 1);
    assert_eq!(msgs_b[0].content, "hello");
}

