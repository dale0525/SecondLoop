use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;
use std::time::Duration;

fn recurrence_meta(conn: &rusqlite::Connection, todo_id: &str) -> (String, i64) {
    conn.query_row(
        r#"SELECT series_id, occurrence_index FROM todo_recurrences WHERE todo_id = ?1"#,
        [todo_id],
        |row| Ok((row.get(0)?, row.get(1)?)),
    )
    .expect("recurrence meta")
}

fn recurrence_rule(conn: &rusqlite::Connection, todo_id: &str) -> String {
    db::get_todo_recurrence_rule_json(conn, todo_id)
        .expect("recurrence rule query")
        .expect("recurrence rule missing")
}

fn bump_clock() {
    std::thread::sleep(Duration::from_millis(2));
}

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

#[test]
fn sync_pull_preserves_this_and_future_split_series() {
    let remote = sync::InMemoryRemoteStore::new();
    let remote_root = "SecondLoopRecurringSyncScope";

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");

    let due_at_ms = 1_730_808_000_000i64;
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
        "series:sync:scope",
        r#"{"freq":"daily","interval":1}"#,
    )
    .expect("recurrence A");

    db::set_todo_status(&conn_a, &key_a, "todo:seed", "done", None).expect("done #0 on A");
    db::set_todo_status(&conn_a, &key_a, "todo:series:sync:scope:1", "done", None)
        .expect("done #1 on A");

    bump_clock();
    db::update_todo_due_with_scope(
        &conn_a,
        &key_a,
        "todo:series:sync:scope:1",
        due_at_ms + 3 * 24 * 60 * 60 * 1000,
        db::TodoRecurrenceEditScope::ThisAndFuture,
    )
    .expect("scope update on A");

    let (seed_series_a, seed_idx_a) = recurrence_meta(&conn_a, "todo:seed");
    let (current_series_a, current_idx_a) = recurrence_meta(&conn_a, "todo:series:sync:scope:1");
    let (future_series_a, future_idx_a) = recurrence_meta(&conn_a, "todo:series:sync:scope:2");

    assert_eq!(seed_series_a, "series:sync:scope");
    assert_eq!(seed_idx_a, 0);
    assert_ne!(current_series_a, seed_series_a);
    assert_eq!(current_idx_a, 0);
    assert_eq!(future_series_a, current_series_a);
    assert_eq!(future_idx_a, 1);

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let pushed_a = sync::push(&conn_a, &key_a, &sync_key, &remote, remote_root).expect("push A");
    assert!(pushed_a > 0);

    let pulled_b = sync::pull(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("pull B");
    assert!(pulled_b > 0);

    let seed_b = db::get_todo(&conn_b, &key_b, "todo:seed").expect("seed B");
    let current_b = db::get_todo(&conn_b, &key_b, "todo:series:sync:scope:1").expect("current B");
    let future_b = db::get_todo(&conn_b, &key_b, "todo:series:sync:scope:2").expect("future B");

    assert_eq!(seed_b.due_at_ms, Some(due_at_ms));
    assert_eq!(
        current_b.due_at_ms,
        Some(due_at_ms + 3 * 24 * 60 * 60 * 1000)
    );
    assert_eq!(
        future_b.due_at_ms,
        Some(due_at_ms + 4 * 24 * 60 * 60 * 1000)
    );

    let (seed_series_b, seed_idx_b) = recurrence_meta(&conn_b, "todo:seed");
    let (current_series_b, current_idx_b) = recurrence_meta(&conn_b, "todo:series:sync:scope:1");
    let (future_series_b, future_idx_b) = recurrence_meta(&conn_b, "todo:series:sync:scope:2");

    assert_eq!(seed_series_b, seed_series_a);
    assert_eq!(seed_idx_b, seed_idx_a);
    assert_eq!(current_series_b, current_series_a);
    assert_eq!(current_idx_b, current_idx_a);
    assert_eq!(future_series_b, future_series_a);
    assert_eq!(future_idx_b, future_idx_a);

    db::set_todo_status(&conn_b, &key_b, "todo:series:sync:scope:2", "done", None)
        .expect("done #2 on B");
    let spawned_id = format!("todo:{}:2", current_series_b);
    let spawned_b = db::get_todo(&conn_b, &key_b, &spawned_id).expect("spawned on B");
    assert_eq!(
        spawned_b.due_at_ms,
        Some(due_at_ms + 5 * 24 * 60 * 60 * 1000)
    );

    let pushed_b = sync::push(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("push B");
    assert!(pushed_b > 0);

    let pulled_a = sync::pull(&conn_a, &key_a, &sync_key, &remote, remote_root).expect("pull A");
    assert!(pulled_a > 0);

    let spawned_a = db::get_todo(&conn_a, &key_a, &spawned_id).expect("spawned on A");
    assert_eq!(
        spawned_a.due_at_ms,
        Some(due_at_ms + 5 * 24 * 60 * 60 * 1000)
    );

    let (spawned_series_a, spawned_index_a) = recurrence_meta(&conn_a, &spawned_id);
    assert_eq!(spawned_series_a, current_series_a);
    assert_eq!(spawned_index_a, 2);
}

#[test]
fn sync_pull_preserves_this_and_future_status_scope_updates() {
    let remote = sync::InMemoryRemoteStore::new();
    let remote_root = "SecondLoopRecurringSyncStatusScope";

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");

    let due_at_ms = 1_730_808_000_000i64;
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
        "series:sync:status-scope",
        r#"{"freq":"daily","interval":1}"#,
    )
    .expect("recurrence A");

    db::set_todo_status(&conn_a, &key_a, "todo:seed", "done", None).expect("done #0 on A");
    db::set_todo_status(
        &conn_a,
        &key_a,
        "todo:series:sync:status-scope:1",
        "done",
        None,
    )
    .expect("done #1 on A");

    bump_clock();
    db::update_todo_status_with_scope(
        &conn_a,
        &key_a,
        "todo:series:sync:status-scope:1",
        "dismissed",
        None,
        db::TodoRecurrenceEditScope::ThisAndFuture,
    )
    .expect("status scope update on A");

    let (seed_series_a, seed_idx_a) = recurrence_meta(&conn_a, "todo:seed");
    let (current_series_a, current_idx_a) =
        recurrence_meta(&conn_a, "todo:series:sync:status-scope:1");
    let (future_series_a, future_idx_a) =
        recurrence_meta(&conn_a, "todo:series:sync:status-scope:2");

    assert_eq!(seed_series_a, "series:sync:status-scope");
    assert_eq!(seed_idx_a, 0);
    assert_ne!(current_series_a, seed_series_a);
    assert_eq!(current_idx_a, 0);
    assert_eq!(future_series_a, current_series_a);
    assert_eq!(future_idx_a, 1);

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let pushed_a = sync::push(&conn_a, &key_a, &sync_key, &remote, remote_root).expect("push A");
    assert!(pushed_a > 0);

    let pulled_b = sync::pull(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("pull B");
    assert!(pulled_b > 0);

    let seed_b = db::get_todo(&conn_b, &key_b, "todo:seed").expect("seed B");
    let current_b =
        db::get_todo(&conn_b, &key_b, "todo:series:sync:status-scope:1").expect("current B");
    let future_b =
        db::get_todo(&conn_b, &key_b, "todo:series:sync:status-scope:2").expect("future B");

    assert_eq!(seed_b.status, "done");
    assert_eq!(current_b.status, "dismissed");
    assert_eq!(future_b.status, "dismissed");

    let (seed_series_b, seed_idx_b) = recurrence_meta(&conn_b, "todo:seed");
    let (current_series_b, current_idx_b) =
        recurrence_meta(&conn_b, "todo:series:sync:status-scope:1");
    let (future_series_b, future_idx_b) =
        recurrence_meta(&conn_b, "todo:series:sync:status-scope:2");

    assert_eq!(seed_series_b, seed_series_a);
    assert_eq!(seed_idx_b, seed_idx_a);
    assert_eq!(current_series_b, current_series_a);
    assert_eq!(current_idx_b, current_idx_a);
    assert_eq!(future_series_b, future_series_a);
    assert_eq!(future_idx_b, future_idx_a);
}

#[test]
fn sync_pull_preserves_this_and_future_recurrence_rule_scope_updates() {
    let remote = sync::InMemoryRemoteStore::new();
    let remote_root = "SecondLoopRecurringSyncRuleScope";

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");

    let due_at_ms = 1_730_808_000_000i64;
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
        "series:sync:rule-scope",
        r#"{"freq":"daily","interval":1}"#,
    )
    .expect("recurrence A");

    db::set_todo_status(&conn_a, &key_a, "todo:seed", "done", None).expect("done #0 on A");
    db::set_todo_status(
        &conn_a,
        &key_a,
        "todo:series:sync:rule-scope:1",
        "done",
        None,
    )
    .expect("done #1 on A");

    bump_clock();
    db::update_todo_recurrence_rule_with_scope(
        &conn_a,
        &key_a,
        "todo:series:sync:rule-scope:1",
        r#"{"freq":"weekly","interval":1}"#,
        db::TodoRecurrenceEditScope::ThisAndFuture,
    )
    .expect("rule scope update on A");

    let (seed_series_a, seed_idx_a) = recurrence_meta(&conn_a, "todo:seed");
    let (current_series_a, current_idx_a) =
        recurrence_meta(&conn_a, "todo:series:sync:rule-scope:1");
    let (future_series_a, future_idx_a) = recurrence_meta(&conn_a, "todo:series:sync:rule-scope:2");

    assert_eq!(seed_series_a, "series:sync:rule-scope");
    assert_eq!(seed_idx_a, 0);
    assert_ne!(current_series_a, seed_series_a);
    assert_eq!(current_idx_a, 0);
    assert_eq!(future_series_a, current_series_a);
    assert_eq!(future_idx_a, 1);

    assert!(recurrence_rule(&conn_a, "todo:seed").contains("\"daily\""));
    assert!(recurrence_rule(&conn_a, "todo:series:sync:rule-scope:1").contains("\"weekly\""));
    assert!(recurrence_rule(&conn_a, "todo:series:sync:rule-scope:2").contains("\"weekly\""));

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let pushed_a = sync::push(&conn_a, &key_a, &sync_key, &remote, remote_root).expect("push A");
    assert!(pushed_a > 0);

    let pulled_b = sync::pull(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("pull B");
    assert!(pulled_b > 0);

    assert!(recurrence_rule(&conn_b, "todo:seed").contains("\"daily\""));
    assert!(recurrence_rule(&conn_b, "todo:series:sync:rule-scope:1").contains("\"weekly\""));
    assert!(recurrence_rule(&conn_b, "todo:series:sync:rule-scope:2").contains("\"weekly\""));

    let (seed_series_b, seed_idx_b) = recurrence_meta(&conn_b, "todo:seed");
    let (current_series_b, current_idx_b) =
        recurrence_meta(&conn_b, "todo:series:sync:rule-scope:1");
    let (future_series_b, future_idx_b) = recurrence_meta(&conn_b, "todo:series:sync:rule-scope:2");

    assert_eq!(seed_series_b, seed_series_a);
    assert_eq!(seed_idx_b, seed_idx_a);
    assert_eq!(current_series_b, current_series_a);
    assert_eq!(current_idx_b, current_idx_a);
    assert_eq!(future_series_b, future_series_a);
    assert_eq!(future_idx_b, future_idx_a);

    db::set_todo_status(
        &conn_b,
        &key_b,
        "todo:series:sync:rule-scope:2",
        "done",
        None,
    )
    .expect("done #2 on B");

    let spawned_id = format!("todo:{}:2", current_series_b);
    let spawned_b = db::get_todo(&conn_b, &key_b, &spawned_id).expect("spawned on B");
    assert_eq!(
        spawned_b.due_at_ms,
        Some(due_at_ms + 9 * 24 * 60 * 60 * 1000)
    );
    assert!(recurrence_rule(&conn_b, &spawned_id).contains("\"weekly\""));

    let pushed_b = sync::push(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("push B");
    assert!(pushed_b > 0);

    let pulled_a = sync::pull(&conn_a, &key_a, &sync_key, &remote, remote_root).expect("pull A");
    assert!(pulled_a > 0);

    let spawned_a = db::get_todo(&conn_a, &key_a, &spawned_id).expect("spawned on A");
    assert_eq!(
        spawned_a.due_at_ms,
        Some(due_at_ms + 9 * 24 * 60 * 60 * 1000)
    );
    assert!(recurrence_rule(&conn_a, &spawned_id).contains("\"weekly\""));
}

#[test]
fn sync_pull_preserves_combined_due_status_rule_updates_across_devices() {
    let remote = sync::InMemoryRemoteStore::new();
    let remote_root = "SecondLoopRecurringSyncComboScope";

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");

    let due_at_ms = 1_730_808_000_000i64;
    let day_ms = 24 * 60 * 60 * 1000;

    db::upsert_todo(
        &conn_a,
        &key_a,
        "todo:seed",
        "Daily sync combo check",
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
        "series:sync:combo",
        r#"{"freq":"daily","interval":1}"#,
    )
    .expect("recurrence A");

    db::set_todo_status(&conn_a, &key_a, "todo:seed", "done", None).expect("done #0 on A");
    db::set_todo_status(&conn_a, &key_a, "todo:series:sync:combo:1", "done", None)
        .expect("done #1 on A");

    bump_clock();
    db::update_todo_due_with_scope(
        &conn_a,
        &key_a,
        "todo:series:sync:combo:1",
        due_at_ms + 3 * day_ms,
        db::TodoRecurrenceEditScope::ThisAndFuture,
    )
    .expect("due scope update on A");

    bump_clock();
    db::update_todo_status_with_scope(
        &conn_a,
        &key_a,
        "todo:series:sync:combo:1",
        "in_progress",
        None,
        db::TodoRecurrenceEditScope::WholeSeries,
    )
    .expect("status scope update on A");

    bump_clock();
    db::update_todo_recurrence_rule_with_scope(
        &conn_a,
        &key_a,
        "todo:series:sync:combo:1",
        r#"{"freq":"weekly","interval":2}"#,
        db::TodoRecurrenceEditScope::WholeSeries,
    )
    .expect("rule scope update on A");

    let (seed_series_a, seed_idx_a) = recurrence_meta(&conn_a, "todo:seed");
    let (current_series_a, current_idx_a) = recurrence_meta(&conn_a, "todo:series:sync:combo:1");
    let (future_series_a, future_idx_a) = recurrence_meta(&conn_a, "todo:series:sync:combo:2");

    assert_eq!(seed_series_a, "series:sync:combo");
    assert_eq!(seed_idx_a, 0);
    assert_ne!(current_series_a, seed_series_a);
    assert_eq!(current_idx_a, 0);
    assert_eq!(future_series_a, current_series_a);
    assert_eq!(future_idx_a, 1);

    let seed_a = db::get_todo(&conn_a, &key_a, "todo:seed").expect("seed A");
    let current_a = db::get_todo(&conn_a, &key_a, "todo:series:sync:combo:1").expect("current A");
    let future_a = db::get_todo(&conn_a, &key_a, "todo:series:sync:combo:2").expect("future A");

    assert_eq!(seed_a.status, "done");
    assert_eq!(seed_a.due_at_ms, Some(due_at_ms));
    assert_eq!(current_a.status, "in_progress");
    assert_eq!(current_a.due_at_ms, Some(due_at_ms + 3 * day_ms));
    assert_eq!(future_a.status, "in_progress");
    assert_eq!(future_a.due_at_ms, Some(due_at_ms + 4 * day_ms));

    assert!(recurrence_rule(&conn_a, "todo:seed").contains("\"daily\""));
    assert!(recurrence_rule(&conn_a, "todo:series:sync:combo:1").contains("\"weekly\""));
    assert!(recurrence_rule(&conn_a, "todo:series:sync:combo:2").contains("\"weekly\""));

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let pushed_a = sync::push(&conn_a, &key_a, &sync_key, &remote, remote_root).expect("push A");
    assert!(pushed_a > 0);

    let pulled_b = sync::pull(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("pull B");
    assert!(pulled_b > 0);

    let seed_b = db::get_todo(&conn_b, &key_b, "todo:seed").expect("seed B");
    let current_b = db::get_todo(&conn_b, &key_b, "todo:series:sync:combo:1").expect("current B");
    let future_b = db::get_todo(&conn_b, &key_b, "todo:series:sync:combo:2").expect("future B");

    assert_eq!(seed_b.status, "done");
    assert_eq!(seed_b.due_at_ms, Some(due_at_ms));
    assert_eq!(current_b.status, "in_progress");
    assert_eq!(current_b.due_at_ms, Some(due_at_ms + 3 * day_ms));
    assert_eq!(future_b.status, "in_progress");
    assert_eq!(future_b.due_at_ms, Some(due_at_ms + 4 * day_ms));

    let (seed_series_b, seed_idx_b) = recurrence_meta(&conn_b, "todo:seed");
    let (current_series_b, current_idx_b) = recurrence_meta(&conn_b, "todo:series:sync:combo:1");
    let (future_series_b, future_idx_b) = recurrence_meta(&conn_b, "todo:series:sync:combo:2");

    assert_eq!(seed_series_b, seed_series_a);
    assert_eq!(seed_idx_b, seed_idx_a);
    assert_eq!(current_series_b, current_series_a);
    assert_eq!(current_idx_b, current_idx_a);
    assert_eq!(future_series_b, future_series_a);
    assert_eq!(future_idx_b, future_idx_a);

    assert!(recurrence_rule(&conn_b, "todo:seed").contains("\"daily\""));
    assert!(recurrence_rule(&conn_b, "todo:series:sync:combo:1").contains("\"weekly\""));
    assert!(recurrence_rule(&conn_b, "todo:series:sync:combo:2").contains("\"weekly\""));

    db::set_todo_status(&conn_b, &key_b, "todo:series:sync:combo:2", "done", None)
        .expect("done #2 on B");

    let spawned_id = format!("todo:{}:2", current_series_b);
    let spawned_b = db::get_todo(&conn_b, &key_b, &spawned_id).expect("spawned on B");
    assert_eq!(spawned_b.status, "open");
    assert_eq!(spawned_b.due_at_ms, Some(due_at_ms + 18 * day_ms));
    assert!(recurrence_rule(&conn_b, &spawned_id).contains("\"weekly\""));

    let (spawned_series_b, spawned_index_b) = recurrence_meta(&conn_b, &spawned_id);
    assert_eq!(spawned_series_b, current_series_b);
    assert_eq!(spawned_index_b, 2);

    let pushed_b = sync::push(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("push B");
    assert!(pushed_b > 0);

    let pulled_a = sync::pull(&conn_a, &key_a, &sync_key, &remote, remote_root).expect("pull A");
    assert!(pulled_a > 0);

    let spawned_a = db::get_todo(&conn_a, &key_a, &spawned_id).expect("spawned on A");
    assert_eq!(spawned_a.status, "open");
    assert_eq!(spawned_a.due_at_ms, Some(due_at_ms + 18 * day_ms));
    assert!(recurrence_rule(&conn_a, &spawned_id).contains("\"weekly\""));

    let (spawned_series_a, spawned_index_a) = recurrence_meta(&conn_a, &spawned_id);
    assert_eq!(spawned_series_a, current_series_a);
    assert_eq!(spawned_index_a, 2);
}
