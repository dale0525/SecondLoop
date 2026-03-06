use secondloop_rust::auth;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::db;

fn find_suggestion<'a>(
    suggestions: &'a [db::TagMergeSuggestion],
    source_tag_id: &str,
) -> &'a db::TagMergeSuggestion {
    suggestions
        .iter()
        .find(|item| item.source_tag.id == source_tag_id)
        .expect("missing expected merge suggestion")
}

fn has_pair_suggestion(
    suggestions: &[db::TagMergeSuggestion],
    source_tag_id: &str,
    target_tag_id: &str,
) -> bool {
    suggestions
        .iter()
        .any(|item| item.source_tag.id == source_tag_id && item.target_tag.id == target_tag_id)
}

#[test]
fn tag_merge_feedback_adjusts_suggestion_scores() {
    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init auth");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Main").expect("create conversation");

    let canonical = db::upsert_tag(&conn, &key, "Weekly Review").expect("upsert canonical");
    let alias_compact = db::upsert_tag(&conn, &key, "weekly-review").expect("upsert compact alias");
    let alias_contains = db::upsert_tag(&conn, &key, "weekly revi").expect("upsert contains alias");

    for index in 0..4 {
        let message = db::insert_message(
            &conn,
            &key,
            &conversation.id,
            "user",
            &format!("canonical message {index}"),
        )
        .expect("insert canonical message");
        db::set_message_tags(
            &conn,
            &key,
            &message.id,
            std::slice::from_ref(&canonical.id),
        )
        .expect("set canonical tag");
    }

    let compact_message = db::insert_message(
        &conn,
        &key,
        &conversation.id,
        "user",
        "compact alias message",
    )
    .expect("insert compact alias message");
    db::set_message_tags(
        &conn,
        &key,
        &compact_message.id,
        std::slice::from_ref(&alias_compact.id),
    )
    .expect("set compact alias tag");

    let contains_message = db::insert_message(
        &conn,
        &key,
        &conversation.id,
        "user",
        "contains alias message",
    )
    .expect("insert contains alias message");
    db::set_message_tags(
        &conn,
        &key,
        &contains_message.id,
        std::slice::from_ref(&alias_contains.id),
    )
    .expect("set contains alias tag");

    let before = db::list_tag_merge_suggestions(&conn, &key, 10).expect("list suggestions before");
    let compact_before = find_suggestion(&before, &alias_compact.id);
    let contains_before = find_suggestion(&before, &alias_contains.id);

    assert_eq!(compact_before.target_tag.id, canonical.id);
    assert_eq!(compact_before.reason, "name_compact_match");
    assert_eq!(contains_before.target_tag.id, canonical.id);
    assert_eq!(contains_before.reason, "name_contains");

    db::record_tag_merge_feedback(
        &conn,
        &alias_compact.id,
        &canonical.id,
        &compact_before.reason,
        "later",
    )
    .expect("record compact later");
    db::record_tag_merge_feedback(
        &conn,
        &alias_compact.id,
        &canonical.id,
        &compact_before.reason,
        "later",
    )
    .expect("record compact later");

    for _ in 0..3 {
        db::record_tag_merge_feedback(
            &conn,
            &alias_contains.id,
            &canonical.id,
            &contains_before.reason,
            "later",
        )
        .expect("record contains later");
    }

    let after_negative =
        db::list_tag_merge_suggestions(&conn, &key, 10).expect("list suggestions after negative");
    let compact_after_negative = find_suggestion(&after_negative, &alias_compact.id);
    let contains_after_negative = find_suggestion(&after_negative, &alias_contains.id);

    assert!(compact_after_negative.score < compact_before.score);
    assert!(contains_after_negative.score < contains_before.score);

    for _ in 0..3 {
        db::record_tag_merge_feedback(
            &conn,
            &alias_compact.id,
            &canonical.id,
            &compact_before.reason,
            "accept",
        )
        .expect("record compact accept");
    }

    let after_positive =
        db::list_tag_merge_suggestions(&conn, &key, 10).expect("list suggestions after positive");
    let compact_after_positive = find_suggestion(&after_positive, &alias_compact.id);

    assert!(compact_after_positive.score > compact_after_negative.score);
}

#[test]
fn tag_merge_feedback_rejects_invalid_inputs() {
    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let _key =
        auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init auth");
    let conn = db::open(&app_dir).expect("open db");

    let err = db::record_tag_merge_feedback(&conn, "", "target", "name_contains", "dismiss")
        .expect_err("empty source should fail");
    assert!(err.to_string().contains("source_tag_id cannot be empty"));

    let err = db::record_tag_merge_feedback(&conn, "source", "source", "name_contains", "dismiss")
        .expect_err("same source and target should fail");
    assert!(err
        .to_string()
        .contains("source_tag_id and target_tag_id must differ"));

    let err = db::record_tag_merge_feedback(&conn, "source", "target", "name_contains", "noop")
        .expect_err("invalid action should fail");
    assert!(err.to_string().contains("unsupported feedback action"));
}

#[test]
fn dismiss_feedback_hides_pair_but_later_keeps_it_visible() {
    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init auth");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Main").expect("create conversation");

    let canonical = db::upsert_tag(&conn, &key, "Weekly Review").expect("upsert canonical");
    let alias_dismiss = db::upsert_tag(&conn, &key, "weekly-review").expect("upsert dismiss alias");
    let alias_later = db::upsert_tag(&conn, &key, "weekly revi").expect("upsert later alias");

    for index in 0..4 {
        let message = db::insert_message(
            &conn,
            &key,
            &conversation.id,
            "user",
            &format!("canonical message {index}"),
        )
        .expect("insert canonical message");
        db::set_message_tags(
            &conn,
            &key,
            &message.id,
            std::slice::from_ref(&canonical.id),
        )
        .expect("set canonical tag");
    }

    let dismiss_message = db::insert_message(
        &conn,
        &key,
        &conversation.id,
        "user",
        "dismiss alias message",
    )
    .expect("insert dismiss alias message");
    db::set_message_tags(
        &conn,
        &key,
        &dismiss_message.id,
        std::slice::from_ref(&alias_dismiss.id),
    )
    .expect("set dismiss alias tag");

    let later_message =
        db::insert_message(&conn, &key, &conversation.id, "user", "later alias message")
            .expect("insert later alias message");
    db::set_message_tags(
        &conn,
        &key,
        &later_message.id,
        std::slice::from_ref(&alias_later.id),
    )
    .expect("set later alias tag");

    let before = db::list_tag_merge_suggestions(&conn, &key, 10).expect("list suggestions before");
    let dismiss_before = find_suggestion(&before, &alias_dismiss.id);
    let later_before = find_suggestion(&before, &alias_later.id);

    db::record_tag_merge_feedback(
        &conn,
        &alias_dismiss.id,
        &canonical.id,
        &dismiss_before.reason,
        "dismiss",
    )
    .expect("record dismiss feedback");
    db::record_tag_merge_feedback(
        &conn,
        &alias_later.id,
        &canonical.id,
        &later_before.reason,
        "later",
    )
    .expect("record later feedback");

    let after =
        db::list_tag_merge_suggestions(&conn, &key, 10).expect("list suggestions after feedback");

    assert!(!has_pair_suggestion(
        &after,
        &alias_dismiss.id,
        &canonical.id
    ));
    assert!(has_pair_suggestion(&after, &alias_later.id, &canonical.id));
}
