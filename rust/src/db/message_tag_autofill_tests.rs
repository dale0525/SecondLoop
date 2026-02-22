use tempfile::tempdir;

use super::*;

fn table_exists(conn: &Connection, table_name: &str) -> bool {
    conn.query_row(
        r#"SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1"#,
        params![table_name],
        |row| row.get::<_, i64>(0),
    )
    .optional()
    .expect("query sqlite_master")
    .is_some()
}

#[test]
fn message_tag_autofill_schema_tables_exist() {
    let dir = tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");

    assert!(table_exists(&conn, "message_tag_autofill_jobs"));
    assert!(table_exists(&conn, "message_tag_autofill_events"));
}

#[test]
fn plain_text_message_produces_shadow_suggested_tag_without_applying_message_tags() {
    let dir = tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");

    kv_set_string(&conn, KV_MESSAGE_TAG_AUTOFILL_APPLY_ENABLED, "false").expect("disable apply");

    let key = [17u8; 32];
    let conversation = get_or_create_loop_home_conversation(&conn, &key).expect("conversation");
    let message = insert_message(
        &conn,
        &key,
        &conversation.id,
        "user",
        "work meeting recap and next actions",
    )
    .expect("insert message");

    let suggested = list_message_suggested_tags(&conn, &key, &message.id).expect("suggested");
    assert!(
        suggested.iter().any(|value| value == "work"),
        "expected `work` in suggestions, got: {suggested:?}"
    );

    let message_tags = list_message_tags(&conn, &key, &message.id).expect("message tags");
    assert!(
        message_tags.is_empty(),
        "shadow mode should not auto-apply message tags"
    );

    let event_count: i64 = conn
        .query_row(
            r#"SELECT COUNT(*) FROM message_tag_autofill_events WHERE message_id = ?1"#,
            params![message.id],
            |row| row.get(0),
        )
        .expect("event count");
    assert!(event_count > 0, "expected at least one autofill event");
}

#[test]
fn default_mode_allows_high_confidence_autofill_to_write_message_tag() {
    let dir = tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");

    let key = [23u8; 32];
    let conversation = get_or_create_loop_home_conversation(&conn, &key).expect("conversation");
    let message = insert_message(
        &conn,
        &key,
        &conversation.id,
        "user",
        "work sprint planning and deliverables",
    )
    .expect("insert message");

    let message_tags = list_message_tags(&conn, &key, &message.id).expect("message tags");
    assert!(
        message_tags.iter().any(|tag| tag.name == "work"),
        "expected applied system tag `work`, got: {message_tags:?}"
    );

    let applied_events: i64 = conn
        .query_row(
            r#"SELECT COUNT(*) FROM message_tag_autofill_events WHERE message_id = ?1 AND applied = 1"#,
            params![message.id],
            |row| row.get(0),
        )
        .expect("applied events");
    assert!(
        applied_events > 0,
        "expected at least one applied autofill event"
    );
}

#[test]
fn attachment_annotation_enqueues_and_processes_autofill_for_linked_messages() {
    let dir = tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let conn = open(&app_dir).expect("open");

    let key = [31u8; 32];
    let conversation = get_or_create_loop_home_conversation(&conn, &key).expect("conversation");
    let message = insert_message(
        &conn,
        &key,
        &conversation.id,
        "user",
        "weekly receipt archive",
    )
    .expect("insert message");
    let attachment =
        insert_attachment(&conn, &key, &app_dir, b"img", "image/png").expect("attachment");
    link_attachment_to_message(&conn, &key, &message.id, &attachment.sha256).expect("link");

    mark_attachment_annotation_ok(
        &conn,
        &key,
        &attachment.sha256,
        "und",
        "vision.v1",
        &serde_json::json!({
            "suggested_tags": ["finance"]
        }),
        12_000,
    )
    .expect("mark annotation ok");

    let suggested = list_message_suggested_tags(&conn, &key, &message.id).expect("suggested tags");
    assert!(
        suggested.iter().any(|value| value == "finance"),
        "expected `finance` in suggestions, got: {suggested:?}"
    );

    let event_count: i64 = conn
        .query_row(
            r#"SELECT COUNT(*) FROM message_tag_autofill_events WHERE message_id = ?1 AND candidate_tag = 'finance'"#,
            params![message.id],
            |row| row.get(0),
        )
        .expect("event count");
    assert!(
        event_count > 0,
        "expected autofill event with attachment-driven candidate"
    );

    let message_tags = list_message_tags(&conn, &key, &message.id).expect("message tags");
    assert!(
        message_tags.is_empty(),
        "shadow mode should not auto-apply from attachment suggestions"
    );
}
