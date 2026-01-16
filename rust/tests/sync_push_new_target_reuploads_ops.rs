use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;

#[test]
fn sync_push_to_new_target_reuploads_ops() {
    let remote_a = sync::InMemoryRemoteStore::new();
    let remote_b = sync::InMemoryRemoteStore::new();
    let remote_root = "SecondLoopTest";

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let conv = db::create_conversation(&conn, &key, "Inbox").expect("create convo");
    db::insert_message(&conn, &key, &conv.id, "user", "hello").expect("insert msg");

    let sync_key =
        derive_root_key("sync-passphrase", b"secondloop-sync1", &KdfParams::for_test())
            .expect("derive sync key");

    let pushed_a = sync::push(&conn, &key, &sync_key, &remote_a, remote_root).expect("push A");
    assert!(pushed_a > 0);

    // Switching the remote target should not reuse the previous cursor state.
    let pushed_b = sync::push(&conn, &key, &sync_key, &remote_b, remote_root).expect("push B");
    assert!(
        pushed_b > 0,
        "expected ops to be uploaded to the new target, got {pushed_b}"
    );
}

