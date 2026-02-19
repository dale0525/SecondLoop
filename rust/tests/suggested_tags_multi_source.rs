use rusqlite::params;
use secondloop_rust::auth;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::db;

#[test]
fn suggested_tags_collects_audio_document_and_url_sources() {
    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init auth");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Main").expect("create conversation");
    let message = db::insert_message(&conn, &key, &conversation.id, "user", "collect tags")
        .expect("insert message");

    let audio = db::insert_attachment(&conn, &key, &app_dir, b"audio", "audio/mp4")
        .expect("insert audio attachment");
    db::link_attachment_to_message(&conn, &key, &message.id, &audio.sha256)
        .expect("link audio attachment");

    let document = db::insert_attachment(&conn, &key, &app_dir, b"document", "application/pdf")
        .expect("insert document attachment");
    db::link_attachment_to_message(&conn, &key, &message.id, &document.sha256)
        .expect("link document attachment");

    let url_manifest = db::insert_attachment(
        &conn,
        &key,
        &app_dir,
        b"url",
        "application/x.secondloop.url+json",
    )
    .expect("insert url attachment");
    db::link_attachment_to_message(&conn, &key, &message.id, &url_manifest.sha256)
        .expect("link url attachment");

    conn.execute(
        r#"UPDATE message_attachments
           SET created_at = ?3
           WHERE message_id = ?1
             AND attachment_sha256 = ?2"#,
        params![message.id, audio.sha256, 1i64],
    )
    .expect("set audio order");
    conn.execute(
        r#"UPDATE message_attachments
           SET created_at = ?3
           WHERE message_id = ?1
             AND attachment_sha256 = ?2"#,
        params![message.id, document.sha256, 2i64],
    )
    .expect("set document order");
    conn.execute(
        r#"UPDATE message_attachments
           SET created_at = ?3
           WHERE message_id = ?1
             AND attachment_sha256 = ?2"#,
        params![message.id, url_manifest.sha256, 3i64],
    )
    .expect("set url order");

    db::mark_attachment_annotation_ok(
        &conn,
        &key,
        &audio.sha256,
        "en",
        "whisper-1",
        &serde_json::json!({
            "schema": "secondloop.audio_transcript.v1",
            "tags": ["work", "work"]
        }),
        1_700_000_000_001,
    )
    .expect("mark audio annotation");

    db::mark_attachment_annotation_ok(
        &conn,
        &key,
        &document.sha256,
        "en",
        "document_extract.v1",
        &serde_json::json!({
            "schema": "secondloop.document_extract.v1",
            "semantic_parse": {
                "domain": "finance",
                "domain_confidence": 0.93,
                "topic": "hobby",
                "topic_confidence": 0.40
            },
            "analysis": {
                "topics": [
                    {"name": "study", "confidence": 0.40}
                ]
            }
        }),
        1_700_000_000_002,
    )
    .expect("mark document annotation");

    db::mark_attachment_annotation_ok(
        &conn,
        &key,
        &url_manifest.sha256,
        "en",
        "url_extract.v1",
        &serde_json::json!({
            "schema": "secondloop.url_extract.v1",
            "suggestedTags": ["trip"]
        }),
        1_700_000_000_003,
    )
    .expect("mark url annotation");

    let suggested =
        db::list_message_suggested_tags(&conn, &key, &message.id).expect("list suggested tags");

    assert_eq!(suggested.len(), 3);
    assert!(suggested.contains(&"work".to_string()));
    assert!(suggested.contains(&"finance".to_string()));
    assert!(suggested.contains(&"travel".to_string()));
    assert!(!suggested.contains(&"hobby".to_string()));
    assert!(!suggested.contains(&"study".to_string()));
}
