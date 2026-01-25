use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;

#[test]
fn sync_push_then_pull_copies_todo_activities() {
    let remote = sync::InMemoryRemoteStore::new();
    let remote_root = "SecondLoopTest";

    // Device A creates todo + activity timeline locally.
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

    db::set_todo_status(&conn_a, &key_a, "todo:1", "in_progress", None).expect("status change");
    db::append_todo_note(&conn_a, &key_a, "todo:1", "Client arrived", None).expect("note");

    // Device B is a fresh install (different local root key).
    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    // Shared sync key derived from a shared passphrase (same on both devices).
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

    let activities_b = db::list_todo_activities(&conn_b, &key_b, "todo:1").expect("list");
    assert_eq!(activities_b.len(), 2);
    assert!(activities_b.iter().any(
        |a| a.activity_type == "status_change" && a.to_status.as_deref() == Some("in_progress")
    ));
    assert!(activities_b
        .iter()
        .any(|a| a.activity_type == "note" && a.content.as_deref() == Some("Client arrived")));

    // Re-pulling should be idempotent.
    let applied2 =
        sync::pull(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("pull again");
    assert_eq!(applied2, 0);
    let activities_b2 = db::list_todo_activities(&conn_b, &key_b, "todo:1").expect("list");
    assert_eq!(activities_b2.len(), 2);
}
