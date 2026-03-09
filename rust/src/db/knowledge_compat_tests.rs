use super::*;

#[test]
fn knowledge_compat_old_message_embeddings_still_work_before_knowledge_rebuild() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = [7u8; 32];

    let conv = create_conversation(&conn, &key, "Inbox").expect("conversation");
    insert_message(&conn, &key, &conv.id, "user", "apple orchard planning").expect("message 1");
    insert_message(&conn, &key, &conv.id, "user", "train station update").expect("message 2");

    let rebuilt = rebuild_message_embeddings_default(&conn, &key, 100).expect("rebuild messages");
    assert_eq!(rebuilt, 2);

    let hits = search_similar_messages_default(&conn, &key, "apple orchard", 3).expect("search");
    assert!(!hits.is_empty());
    assert!(hits[0].message.content.contains("apple orchard"));

    let status =
        crate::knowledge::read_knowledge_index_status(&conn, &key).expect("knowledge status");
    assert_eq!(status.status, "empty");
}

#[test]
fn knowledge_compat_rebuild_backfills_new_substrate_from_existing_local_entities() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let conn = open(&app_dir).expect("open");
    let key = [11u8; 32];

    let conv = create_conversation(&conn, &key, "Inbox").expect("conversation");
    let msg =
        insert_message(&conn, &key, &conv.id, "user", "trip notes for tokyo").expect("message");

    let attachment = insert_attachment(&conn, &key, &app_dir, b"pdf bytes", "application/pdf")
        .expect("attachment");
    link_attachment_to_message(&conn, &key, &msg.id, &attachment.sha256).expect("link");
    mark_attachment_annotation_ok(
        &conn,
        &key,
        &attachment.sha256,
        "en",
        "document_extract.v1",
        &serde_json::json!({
            "schema": "secondloop.document_extract.v1",
            "readable_text_full": "Tokyo itinerary with museum reservations",
            "readable_text_excerpt": "Tokyo itinerary",
            "mime_type": "application/pdf"
        }),
        1000,
    )
    .expect("annotation");

    crate::knowledge::ensure_knowledge_rebuild_requested(&conn).expect("request rebuild");
    let processed = crate::knowledge::process_pending_knowledge_index_jobs_active(&conn, &key, 64)
        .expect("process jobs");
    assert!(processed > 0);

    let docs = crate::knowledge::list_knowledge_documents(&conn, &key, 100, 0).expect("docs");
    assert!(docs
        .iter()
        .any(|doc| doc.document_id == format!("message:{}", msg.id)));
    assert!(docs.iter().any(|doc| {
        doc.anchors.attachment_sha256.as_deref() == Some(attachment.sha256.as_str())
            && doc.normalized_text.contains("Tokyo itinerary")
    }));

    let old_hits =
        search_similar_messages_default(&conn, &key, "tokyo trip", 3).expect("old search");
    assert!(!old_hits.is_empty());
}

#[test]
fn knowledge_rebuild_can_cancel_and_resume() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let conn = open(&app_dir).expect("open");
    let key = [12u8; 32];

    let conv = create_conversation(&conn, &key, "Inbox").expect("conversation");
    insert_message(
        &conn,
        &key,
        &conv.id,
        "user",
        "resume rebuild for knowledge index",
    )
    .expect("message");

    crate::knowledge::ensure_knowledge_rebuild_requested(&conn).expect("request rebuild");
    crate::knowledge::cancel_knowledge_rebuild(&conn, &key).expect("cancel");
    let processed = crate::knowledge::process_pending_knowledge_index_jobs_active(&conn, &key, 32)
        .expect("process after cancel");
    assert_eq!(processed, 0);
    let cancelled = crate::knowledge::read_knowledge_index_status(&conn, &key).expect("status");
    assert_eq!(cancelled.status, "cancelled");

    crate::knowledge::ensure_knowledge_rebuild_requested(&conn).expect("request rebuild again");
    let resumed = crate::knowledge::process_pending_knowledge_index_jobs_active(&conn, &key, 32)
        .expect("process resumed");
    assert!(resumed > 0);
    let status = crate::knowledge::read_knowledge_index_status(&conn, &key).expect("status");
    assert_eq!(status.status, "complete");
}
