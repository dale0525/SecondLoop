use secondloop_rust::auth;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::db;

#[test]
fn attachment_chunk_index_builds_and_searches_chunks() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init auth");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    let message = db::insert_message(&conn, &key, &conversation.id, "user", "project note")
        .expect("insert message");

    let attachment = db::insert_attachment(&conn, &key, &app_dir, b"doc", "application/pdf")
        .expect("attachment");
    db::link_attachment_to_message(&conn, &key, &message.id, &attachment.sha256)
        .expect("link attachment");

    let payload = serde_json::json!({
        "mime_type": "application/pdf",
        "extracted_text_full": "Alpha design review decisions.\n\nBeta API follow-ups and open risks.",
        "extracted_text_excerpt": "Alpha design review decisions.",
    });
    db::mark_attachment_annotation_ok(
        &conn,
        &key,
        &attachment.sha256,
        "und",
        "document_extract.v1",
        &payload,
        message.created_at_ms,
    )
    .expect("mark annotation ok");

    let indexed = db::process_attachment_chunk_index_default(&conn, &key, 16)
        .expect("process attachment chunk index");
    assert_eq!(indexed, 1);

    let embedded = db::process_pending_attachment_chunk_embeddings_default(&conn, &key, 64)
        .expect("process attachment chunk embeddings");
    assert!(embedded >= 1);

    let hits = db::search_similar_attachment_chunks_default(&conn, &key, "open risks", 5)
        .expect("search attachment chunks");
    assert!(!hits.is_empty(), "expected at least one chunk hit");

    let first = &hits[0];
    assert_eq!(first.attachment_sha256, attachment.sha256);
    assert!(first.text.to_lowercase().contains("open risks"));
    assert_eq!(first.chunk_index, 0);
    assert_eq!(first.kind, "extracted_text_full");
}
