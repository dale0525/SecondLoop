use crate::db;
use crate::knowledge::{
    collect_source_knowledge_documents, KnowledgeOriginType, KnowledgeSourceKind,
};

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
