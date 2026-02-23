use std::time::Duration;

use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;

#[test]
fn sync_message_edit_delete_conflicts_resolve_with_lww_and_can_revive() {
    let remote = sync::InMemoryRemoteStore::new();
    let remote_root = "SecondLoopTest";

    // Device A creates initial state.
    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");
    let conv_a = db::get_or_create_loop_home_conversation(&conn_a, &key_a).expect("loop home A");
    let msg_a =
        db::insert_message(&conn_a, &key_a, &conv_a.id, "user", "hello").expect("insert msg A");

    // Device B starts empty.
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

    sync::push(&conn_a, &key_a, &sync_key, &remote, remote_root).expect("push A");
    sync::pull(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("pull B");

    let msgs_b = db::list_messages(&conn_b, &key_b, &conv_a.id).expect("list msgs B");
    assert_eq!(msgs_b.len(), 1);
    assert_eq!(msgs_b[0].id, msg_a.id);
    assert_eq!(msgs_b[0].content, "hello");

    // Concurrent conflicting updates: A edits, B deletes. Delete should be able to win, but is not permanent.
    db::edit_message(&conn_a, &key_a, &msg_a.id, "edited A").expect("edit A");
    std::thread::sleep(Duration::from_millis(5));
    db::set_message_deleted(&conn_b, &key_b, &msg_a.id, true).expect("delete B");

    sync::push(&conn_a, &key_a, &sync_key, &remote, remote_root).expect("push A2");
    sync::push(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("push B2");

    sync::pull(&conn_a, &key_a, &sync_key, &remote, remote_root).expect("pull A2");
    sync::pull(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("pull B2");

    let msgs_a2 = db::list_messages(&conn_a, &key_a, &conv_a.id).expect("list msgs A2");
    let msgs_b2 = db::list_messages(&conn_b, &key_b, &conv_a.id).expect("list msgs B2");
    assert_eq!(msgs_a2.len(), 0);
    assert_eq!(msgs_b2.len(), 0);

    // A later edit should revive the message.
    std::thread::sleep(Duration::from_millis(5));
    db::edit_message(&conn_a, &key_a, &msg_a.id, "revived").expect("revive A");

    sync::push(&conn_a, &key_a, &sync_key, &remote, remote_root).expect("push A3");
    sync::pull(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("pull B3");

    let msgs_b3 = db::list_messages(&conn_b, &key_b, &conv_a.id).expect("list msgs B3");
    assert_eq!(msgs_b3.len(), 1);
    assert_eq!(msgs_b3[0].id, msg_a.id);
    assert_eq!(msgs_b3[0].content, "revived");

    // Pull should be idempotent once applied.
    let applied_again =
        sync::pull(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("pull B again");
    assert_eq!(applied_again, 0);
    let msgs_b4 = db::list_messages(&conn_b, &key_b, &conv_a.id).expect("list msgs B4");
    assert_eq!(msgs_b4.len(), 1);
}
