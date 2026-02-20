use secondloop_rust::auth;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::db;

#[test]
fn tag_merge_suggestion_can_be_applied_to_reassign_messages() {
    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init auth");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Main").expect("create conversation");
    let message_a = db::insert_message(&conn, &key, &conversation.id, "user", "weekly summary")
        .expect("insert message_a");
    let message_b = db::insert_message(&conn, &key, &conversation.id, "user", "weekly retro")
        .expect("insert message_b");

    let primary = db::upsert_tag(&conn, &key, "Weekly Review").expect("upsert primary");
    let alias = db::upsert_tag(&conn, &key, "weekly-review").expect("upsert alias");

    db::set_message_tags(
        &conn,
        &key,
        &message_a.id,
        std::slice::from_ref(&primary.id),
    )
    .expect("set message_a tags");
    db::set_message_tags(
        &conn,
        &key,
        &message_b.id,
        &[alias.id.clone(), primary.id.clone()],
    )
    .expect("set message_b tags");

    let suggestions =
        db::list_tag_merge_suggestions(&conn, &key, 10).expect("list merge suggestions");
    let suggestion = suggestions
        .iter()
        .find(|item| item.source_tag.id == alias.id && item.target_tag.id == primary.id)
        .expect("find expected merge suggestion");

    assert!(suggestion.score > 0.8);

    let updated = db::merge_tags(&conn, &key, &alias.id, &primary.id).expect("merge tags");
    assert_eq!(updated, 1);

    let message_b_tags =
        db::list_message_tags(&conn, &key, &message_b.id).expect("list message_b tags");
    let ids = message_b_tags
        .iter()
        .map(|tag| tag.id.as_str())
        .collect::<std::collections::BTreeSet<_>>();
    assert!(ids.contains(primary.id.as_str()));
    assert!(!ids.contains(alias.id.as_str()));

    let suggestions_after = db::list_tag_merge_suggestions(&conn, &key, 10)
        .expect("list merge suggestions after apply");
    assert!(!suggestions_after
        .iter()
        .any(|item| item.source_tag.id == alias.id));

    let tags_after_merge = db::list_tags(&conn, &key).expect("list tags after merge");
    assert!(!tags_after_merge.iter().any(|tag| tag.id == alias.id));
}

#[test]
fn merge_tags_rejects_system_source_tag() {
    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init auth");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Main").expect("create conversation");
    let message =
        db::insert_message(&conn, &key, &conversation.id, "user", "hello").expect("insert message");

    let system_work = db::upsert_tag(&conn, &key, "work").expect("upsert system work");
    assert!(system_work.is_system);
    let custom = db::upsert_tag(&conn, &key, "Project Alpha").expect("upsert custom");

    db::set_message_tags(
        &conn,
        &key,
        &message.id,
        std::slice::from_ref(&system_work.id),
    )
    .expect("set message tags");

    let err = db::merge_tags(&conn, &key, &system_work.id, &custom.id)
        .expect_err("system source should be rejected");
    assert!(err
        .to_string()
        .contains("system tags cannot be merged into other tags"));
}

#[test]
fn merge_tags_rejects_missing_tags() {
    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init auth");
    let conn = db::open(&app_dir).expect("open db");

    let target = db::upsert_tag(&conn, &key, "Project Alpha").expect("upsert target");
    let missing_source_error = db::merge_tags(&conn, &key, "missing.source", &target.id)
        .expect_err("missing source should fail");
    assert!(missing_source_error
        .to_string()
        .contains("source tag not found"));

    let source = db::upsert_tag(&conn, &key, "Project Beta").expect("upsert source");
    let missing_target_error = db::merge_tags(&conn, &key, &source.id, "missing.target")
        .expect_err("missing target should fail");
    assert!(missing_target_error
        .to_string()
        .contains("target tag not found"));
}
