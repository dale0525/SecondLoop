use secondloop_rust::auth;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::db;

fn due_ms(day_offset: i64) -> i64 {
    1_730_808_000_000i64 + day_offset * 24 * 60 * 60 * 1000
}

#[test]
fn this_and_future_shifts_current_and_following_occurrences_only() {
    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    db::upsert_todo(
        &conn,
        &key,
        "todo:seed",
        "Daily standup",
        Some(due_ms(0)),
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert seed");

    db::upsert_todo_recurrence_with_sync(
        &conn,
        &key,
        "todo:seed",
        "series:scope:test",
        r#"{"freq":"daily","interval":1}"#,
    )
    .expect("upsert recurrence");

    db::set_todo_status(&conn, &key, "todo:seed", "done", None).expect("done #0");
    db::set_todo_status(&conn, &key, "todo:series:scope:test:1", "done", None).expect("done #1");

    let updated = db::update_todo_due_with_scope(
        &conn,
        &key,
        "todo:series:scope:test:1",
        due_ms(3),
        db::TodoRecurrenceEditScope::ThisAndFuture,
    )
    .expect("update due with scope");
    assert_eq!(updated.due_at_ms, Some(due_ms(3)));

    let first = db::get_todo(&conn, &key, "todo:seed").expect("first");
    let second = db::get_todo(&conn, &key, "todo:series:scope:test:1").expect("second");
    let third = db::get_todo(&conn, &key, "todo:series:scope:test:2").expect("third");

    assert_eq!(first.due_at_ms, Some(due_ms(0)));
    assert_eq!(second.due_at_ms, Some(due_ms(3)));
    assert_eq!(third.due_at_ms, Some(due_ms(4)));
}

#[test]
fn whole_series_shifts_all_existing_occurrences() {
    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    db::upsert_todo(
        &conn,
        &key,
        "todo:seed",
        "Daily standup",
        Some(due_ms(0)),
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("upsert seed");

    db::upsert_todo_recurrence_with_sync(
        &conn,
        &key,
        "todo:seed",
        "series:scope:test",
        r#"{"freq":"daily","interval":1}"#,
    )
    .expect("upsert recurrence");

    db::set_todo_status(&conn, &key, "todo:seed", "done", None).expect("done #0");
    db::set_todo_status(&conn, &key, "todo:series:scope:test:1", "done", None).expect("done #1");

    let updated = db::update_todo_due_with_scope(
        &conn,
        &key,
        "todo:series:scope:test:2",
        due_ms(1),
        db::TodoRecurrenceEditScope::WholeSeries,
    )
    .expect("update due with scope");
    assert_eq!(updated.due_at_ms, Some(due_ms(1)));

    let first = db::get_todo(&conn, &key, "todo:seed").expect("first");
    let second = db::get_todo(&conn, &key, "todo:series:scope:test:1").expect("second");
    let third = db::get_todo(&conn, &key, "todo:series:scope:test:2").expect("third");

    assert_eq!(first.due_at_ms, Some(due_ms(-1)));
    assert_eq!(second.due_at_ms, Some(due_ms(0)));
    assert_eq!(third.due_at_ms, Some(due_ms(1)));
}
