use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;

#[test]
fn sync_push_then_pull_copies_todo_activity_attachments() {
    let remote = sync::InMemoryRemoteStore::new();
    let remote_root = "SecondLoopTest";

    let bytes = b"attachment bytes";

    // Device A creates todo + activity + attachment link.
    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");

    db::upsert_todo(
        &conn_a,
        &key_a,
        "todo:1",
        "Afternoon client visit",
        None,
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("todo A");

    let activity =
        db::append_todo_note(&conn_a, &key_a, "todo:1", "Client arrived", None).expect("note");
    let attachment = db::insert_attachment(&conn_a, &key_a, &app_dir_a, bytes, "text/plain")
        .expect("insert attachment");
    db::link_attachment_to_todo_activity(&conn_a, &key_a, &activity.id, &attachment.sha256)
        .expect("link attachment");

    // Device B is a fresh install.
    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    // Attachments aren't synced via oplog yet; simulate file-level parity by inserting bytes on B.
    db::insert_attachment(&conn_b, &key_b, &app_dir_b, bytes, "text/plain")
        .expect("insert attachment B");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pushed = sync::push(&conn_a, &key_a, &sync_key, &remote, remote_root).expect("push");
    assert!(pushed > 0);

    let applied = sync::pull(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("pull");
    assert!(applied > 0);

    let listed = db::list_todo_activity_attachments(&conn_b, &key_b, &activity.id).expect("list B");
    assert_eq!(listed.len(), 1);
    assert_eq!(listed[0].sha256, attachment.sha256);
}
