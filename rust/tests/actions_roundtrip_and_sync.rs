use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;

#[test]
fn sync_push_then_pull_copies_todos_and_events() {
    let remote = sync::InMemoryRemoteStore::new();
    let remote_root = "SecondLoopTest";

    // Device A creates actions locally.
    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");

    db::upsert_todo(
        &conn_a,
        &key_a,
        "todo:1",
        "Buy milk",
        Some(1_800_000),
        "open",
        None,
        Some(0),
        Some(1_800_000),
        Some(1_700_000),
    )
    .expect("todo A");

    db::upsert_event(
        &conn_a,
        &key_a,
        "event:1",
        "Lunch with Alice",
        1_700_000,
        1_800_000,
        "UTC",
        None,
    )
    .expect("event A");

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

    let todos_b = db::list_todos(&conn_b, &key_b).expect("list todos B");
    assert_eq!(todos_b.len(), 1);
    assert_eq!(todos_b[0].id, "todo:1");
    assert_eq!(todos_b[0].title, "Buy milk");
    assert_eq!(todos_b[0].due_at_ms, Some(1_800_000));
    assert_eq!(todos_b[0].status, "open");
    assert_eq!(todos_b[0].review_stage, Some(0));
    assert_eq!(todos_b[0].next_review_at_ms, Some(1_800_000));
    assert_eq!(todos_b[0].last_review_at_ms, Some(1_700_000));

    let events_b = db::list_events(&conn_b, &key_b).expect("list events B");
    assert_eq!(events_b.len(), 1);
    assert_eq!(events_b[0].id, "event:1");
    assert_eq!(events_b[0].title, "Lunch with Alice");
    assert_eq!(events_b[0].start_at_ms, 1_700_000);
    assert_eq!(events_b[0].end_at_ms, 1_800_000);
    assert_eq!(events_b[0].tz, "UTC");

    // Re-pulling should be idempotent.
    let applied2 =
        sync::pull(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("pull again");
    assert_eq!(applied2, 0);
}
