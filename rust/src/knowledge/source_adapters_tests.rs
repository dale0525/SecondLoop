use crate::crypto::encrypt_bytes;
use crate::db;
use crate::knowledge::{
    collect_source_knowledge_documents, KnowledgeOriginType, KnowledgeSourceKind,
};
use rusqlite::params;

#[test]
fn knowledge_adapter_maps_message_and_attachment_sources() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let conn = db::open(&app_dir).expect("open");
    let key = [5u8; 32];

    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    let msg =
        db::insert_message(&conn, &key, &conv.id, "user", "hello from chat").expect("message");

    let attachment = db::insert_attachment(&conn, &key, &app_dir, b"pdf bytes", "application/pdf")
        .expect("attachment");
    db::link_attachment_to_message(&conn, &key, &msg.id, &attachment.sha256).expect("link");
    db::mark_attachment_annotation_ok(
        &conn,
        &key,
        &attachment.sha256,
        "en",
        "document_extract.v1",
        &serde_json::json!({
            "schema": "secondloop.document_extract.v1",
            "extracted_text_full": "Page 1\n\nUseful body text.",
            "readable_text_excerpt": "Useful body text.",
            "transcript_full": "Speaker A: transcript",
            "mime_type": "application/pdf"
        }),
        1000,
    )
    .expect("annotation");

    let documents = collect_source_knowledge_documents(&conn, &key).expect("collect docs");

    assert!(documents.iter().any(|doc| {
        doc.origin_type == KnowledgeOriginType::Message
            && doc.source_kind == KnowledgeSourceKind::RawText
            && doc.anchors.message_id.as_deref() == Some(msg.id.as_str())
    }));
    assert!(documents.iter().any(|doc| {
        doc.origin_type == KnowledgeOriginType::Attachment
            && doc.source_kind == KnowledgeSourceKind::ExtractedText
            && doc.anchors.attachment_sha256.as_deref() == Some(attachment.sha256.as_str())
    }));
    assert!(documents.iter().any(|doc| {
        doc.origin_type == KnowledgeOriginType::Attachment
            && doc.source_kind == KnowledgeSourceKind::Transcript
    }));
}

#[test]
fn knowledge_adapter_message_documents_do_not_use_role_as_title() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let conn = db::open(&app_dir).expect("open");
    let key = [6u8; 32];

    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    let msg =
        db::insert_message(&conn, &key, &conv.id, "user", "hello from chat").expect("message");

    let documents = collect_source_knowledge_documents(&conn, &key).expect("collect docs");
    let message_doc = documents
        .into_iter()
        .find(|doc| doc.anchors.message_id.as_deref() == Some(msg.id.as_str()))
        .expect("message doc");

    assert_eq!(message_doc.title, None);
}

#[test]
fn knowledge_adapter_skips_messages_with_invalid_ciphertext() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let conn = db::open(&app_dir).expect("open");
    let key = [7u8; 32];

    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    let good =
        db::insert_message(&conn, &key, &conv.id, "user", "healthy message").expect("good message");
    let bad =
        db::insert_message(&conn, &key, &conv.id, "user", "broken message").expect("bad message");
    conn.execute(
        "UPDATE messages SET content = ?2 WHERE id = ?1",
        params![bad.id, vec![1u8, 2u8, 3u8]],
    )
    .expect("corrupt message content");

    let documents = collect_source_knowledge_documents(&conn, &key).expect("collect docs");

    assert!(documents
        .iter()
        .any(|doc| doc.anchors.message_id.as_deref() == Some(good.id.as_str())));
    assert!(!documents
        .iter()
        .any(|doc| doc.anchors.message_id.as_deref() == Some(bad.id.as_str())));
}

#[test]
fn knowledge_adapter_skips_messages_with_invalid_utf8() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let conn = db::open(&app_dir).expect("open");
    let key = [8u8; 32];

    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    let good =
        db::insert_message(&conn, &key, &conv.id, "user", "healthy message").expect("good message");
    let bad =
        db::insert_message(&conn, &key, &conv.id, "user", "broken message").expect("bad message");
    let invalid_utf8 =
        encrypt_bytes(&key, &[0xff, 0xfe], b"message.content").expect("encrypt invalid utf8");
    conn.execute(
        "UPDATE messages SET content = ?2 WHERE id = ?1",
        params![bad.id, invalid_utf8],
    )
    .expect("replace message content");

    let documents = collect_source_knowledge_documents(&conn, &key).expect("collect docs");

    assert!(documents
        .iter()
        .any(|doc| doc.anchors.message_id.as_deref() == Some(good.id.as_str())));
    assert!(!documents
        .iter()
        .any(|doc| doc.anchors.message_id.as_deref() == Some(bad.id.as_str())));
}
