use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;

#[test]
fn sync_pull_preserves_recurrence_and_spawned_occurrence() {
    let remote = sync::InMemoryRemoteStore::new();
    let remote_root = "SecondLoopRecurringSync";

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");

    let due_at_ms = 1_730_808_000_000i64; // 2024-11-01T10:00:00Z
    db::upsert_todo(
        &conn_a,
        &key_a,
        "todo:seed",
        "Daily sync check",
        Some(due_at_ms),
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("todo A");

    db::upsert_todo_recurrence_with_sync(
        &conn_a,
        &key_a,
        "todo:seed",
        "series:sync:daily",
        r#"{"freq":"daily","interval":1}"#,
    )
    .expect("recurrence A");

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

    let pushed_a = sync::push(&conn_a, &key_a, &sync_key, &remote, remote_root).expect("push A");
    assert!(pushed_a > 0);

    let pulled_b = sync::pull(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("pull B");
    assert!(pulled_b > 0);

    let seed_rule_b = db::get_todo_recurrence_rule_json(&conn_b, "todo:seed")
        .expect("rule B")
        .expect("seed recurrence on B");
    assert!(seed_rule_b.contains("\"daily\""));

    db::set_todo_status(&conn_b, &key_b, "todo:seed", "done", None).expect("done on B");

    let todos_b = db::list_todos(&conn_b, &key_b).expect("list B todos");
    assert_eq!(todos_b.len(), 2);

    let spawned_id = "todo:series:sync:daily:1";
    let spawned_b = todos_b
        .iter()
        .find(|todo| todo.id == spawned_id)
        .expect("spawned todo exists on B");
    assert_eq!(spawned_b.status, "open");
    assert_eq!(spawned_b.due_at_ms, Some(due_at_ms + 24 * 60 * 60 * 1000));

    let spawned_rule_b = db::get_todo_recurrence_rule_json(&conn_b, spawned_id)
        .expect("spawned rule B")
        .expect("spawned recurrence on B");
    assert!(spawned_rule_b.contains("\"daily\""));

    let pushed_b = sync::push(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("push B");
    assert!(pushed_b > 0);

    let pulled_a = sync::pull(&conn_a, &key_a, &sync_key, &remote, remote_root).expect("pull A");
    assert!(pulled_a > 0);

    let todos_a = db::list_todos(&conn_a, &key_a).expect("list A todos");
    assert_eq!(todos_a.len(), 2);

    let spawned_a = todos_a
        .iter()
        .find(|todo| todo.id == spawned_id)
        .expect("spawned todo exists on A");
    assert_eq!(spawned_a.status, "open");

    let spawned_rule_a = db::get_todo_recurrence_rule_json(&conn_a, spawned_id)
        .expect("spawned rule A")
        .expect("spawned recurrence on A");
    assert!(spawned_rule_a.contains("\"daily\""));
}
