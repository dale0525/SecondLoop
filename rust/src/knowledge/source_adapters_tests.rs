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

#[test]
fn knowledge_adapter_attachment_document_ids_use_snake_case_source_kind() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let conn = db::open(&app_dir).expect("open");
    let key = [9u8; 32];

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
            "extracted_text_full": "Useful body text.",
            "mime_type": "application/pdf"
        }),
        1000,
    )
    .expect("annotation");

    let documents = collect_source_knowledge_documents(&conn, &key).expect("collect docs");
    let extracted = documents
        .into_iter()
        .find(|doc| {
            doc.origin_type == KnowledgeOriginType::Attachment
                && doc.source_kind == KnowledgeSourceKind::ExtractedText
                && doc.anchors.attachment_sha256.as_deref() == Some(attachment.sha256.as_str())
        })
        .expect("extracted attachment doc");

    assert_eq!(
        extracted.document_id,
        format!("attachment:{}:extracted_text", attachment.sha256)
    );
}

#[test]
fn knowledge_adapter_skips_attachments_with_invalid_metadata_ciphertext() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let conn = db::open(&app_dir).expect("open");
    let key = [10u8; 32];

    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    let msg =
        db::insert_message(&conn, &key, &conv.id, "user", "hello from chat").expect("message");

    let good_attachment =
        db::insert_attachment(&conn, &key, &app_dir, b"good pdf", "application/pdf")
            .expect("good attachment");
    db::link_attachment_to_message(&conn, &key, &msg.id, &good_attachment.sha256)
        .expect("link good");
    db::mark_attachment_annotation_ok(
        &conn,
        &key,
        &good_attachment.sha256,
        "en",
        "document_extract.v1",
        &serde_json::json!({
            "schema": "secondloop.document_extract.v1",
            "extracted_text_full": "Healthy attachment body.",
            "mime_type": "application/pdf"
        }),
        1000,
    )
    .expect("good annotation");

    let bad_attachment =
        db::insert_attachment(&conn, &key, &app_dir, b"bad pdf", "application/pdf")
            .expect("bad attachment");
    db::link_attachment_to_message(&conn, &key, &msg.id, &bad_attachment.sha256).expect("link bad");
    db::mark_attachment_annotation_ok(
        &conn,
        &key,
        &bad_attachment.sha256,
        "en",
        "document_extract.v1",
        &serde_json::json!({
            "schema": "secondloop.document_extract.v1",
            "extracted_text_full": "This metadata row will be corrupted.",
            "mime_type": "application/pdf"
        }),
        1000,
    )
    .expect("bad annotation");
    db::upsert_attachment_metadata(
        &conn,
        &key,
        &bad_attachment.sha256,
        Some("Broken title"),
        &[],
        &[],
    )
    .expect("bad metadata seed");

    conn.execute(
        "UPDATE attachment_metadata SET title = ?2 WHERE attachment_sha256 = ?1",
        params![bad_attachment.sha256, vec![1u8, 2u8, 3u8]],
    )
    .expect("poison metadata title");

    let documents = collect_source_knowledge_documents(&conn, &key).expect("collect docs");

    assert!(documents.iter().any(|doc| {
        doc.origin_type == KnowledgeOriginType::Attachment
            && doc.source_kind == KnowledgeSourceKind::ExtractedText
            && doc.anchors.attachment_sha256.as_deref() == Some(good_attachment.sha256.as_str())
    }));
    assert!(!documents.iter().any(|doc| {
        doc.origin_type == KnowledgeOriginType::Attachment
            && doc.anchors.attachment_sha256.as_deref() == Some(bad_attachment.sha256.as_str())
    }));
}

#[test]
fn knowledge_adapter_visits_external_documents_in_ascending_updated_order() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let conn = db::open(&app_dir).expect("open");
    let key = [10u8; 32];
    let external = db::open_external_readonly_db(&app_dir).expect("open external db");

    external
        .execute(
            r#"INSERT INTO external_import_batches(
                   batch_id, source_kind, source_label, status, created_at_ms, updated_at_ms, completed_at_ms, stats_json, last_error
               ) VALUES (?1, 'folder', 'Fixture', 'completed', 1, 1, 1, '{}', NULL)"#,
            params!["batch-1"],
        )
        .expect("insert batch");

    let older_title = encrypt_bytes(&key, b"Older Title", b"external_document.title:doc-older")
        .expect("encrypt older title");
    let older_body = encrypt_bytes(
        &key,
        b"Older external body",
        b"external_document.body:doc-older",
    )
    .expect("encrypt older body");
    let older_tags = encrypt_bytes(&key, b"[]", b"external_document.tags:doc-older")
        .expect("encrypt older tags");
    external
        .execute(
            r#"INSERT INTO external_documents(
                   doc_id, batch_id, external_origin_id, source_rel_path, title, body_markdown, tags_json,
                   created_at_ms, updated_at_ms, checksum_sha256, is_deleted
               ) VALUES (?1, ?2, NULL, ?3, ?4, ?5, ?6, 1, 10, 'older', 0)"#,
            params![
                "doc-older",
                "batch-1",
                "older.md",
                older_title,
                older_body,
                older_tags,
            ],
        )
        .expect("insert older doc");

    let newer_title = encrypt_bytes(&key, b"Newer Title", b"external_document.title:doc-newer")
        .expect("encrypt newer title");
    let newer_body = encrypt_bytes(
        &key,
        b"Newer external body",
        b"external_document.body:doc-newer",
    )
    .expect("encrypt newer body");
    let newer_tags = encrypt_bytes(&key, b"[]", b"external_document.tags:doc-newer")
        .expect("encrypt newer tags");
    external
        .execute(
            r#"INSERT INTO external_documents(
                   doc_id, batch_id, external_origin_id, source_rel_path, title, body_markdown, tags_json,
                   created_at_ms, updated_at_ms, checksum_sha256, is_deleted
               ) VALUES (?1, ?2, NULL, ?3, ?4, ?5, ?6, 2, 20, 'newer', 0)"#,
            params![
                "doc-newer",
                "batch-1",
                "newer.md",
                newer_title,
                newer_body,
                newer_tags,
            ],
        )
        .expect("insert newer doc");

    let mut external_document_ids = Vec::<String>::new();
    crate::knowledge::source_adapters::visit_source_knowledge_documents_with_external(
        &conn,
        Some(&external),
        &key,
        |document| {
            if document.document_id.starts_with("external:") {
                external_document_ids.push(document.document_id);
            }
            Ok(())
        },
    )
    .expect("visit docs");

    assert_eq!(
        external_document_ids,
        vec![
            "external:doc-older".to_string(),
            "external:doc-newer".to_string(),
        ]
    );
}

#[test]
fn knowledge_adapter_skips_external_documents_with_corrupt_blobs() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let conn = db::open(&app_dir).expect("open");
    let key = [10u8; 32];
    let external = db::open_external_readonly_db(&app_dir).expect("open external db");

    external
        .execute(
            r#"INSERT INTO external_import_batches(
                   batch_id, source_kind, source_label, status, created_at_ms, updated_at_ms, completed_at_ms, stats_json, last_error
               ) VALUES (?1, 'folder', 'Fixture', 'completed', 1, 1, 1, '{}', NULL)"#,
            params!["batch-1"],
        )
        .expect("insert batch");

    let good_title = encrypt_bytes(&key, b"Good Title", b"external_document.title:doc-good")
        .expect("encrypt good title");
    let good_body = encrypt_bytes(
        &key,
        b"Healthy external body",
        b"external_document.body:doc-good",
    )
    .expect("encrypt good body");
    let good_tags =
        encrypt_bytes(&key, b"[]", b"external_document.tags:doc-good").expect("encrypt good tags");
    external
        .execute(
            r#"INSERT INTO external_documents(
                   doc_id, batch_id, external_origin_id, source_rel_path, title, body_markdown, tags_json,
                   created_at_ms, updated_at_ms, checksum_sha256, is_deleted
               ) VALUES (?1, ?2, NULL, ?3, ?4, ?5, ?6, 1, 1, 'good', 0)"#,
            params![
                "doc-good",
                "batch-1",
                "good.md",
                good_title,
                good_body,
                good_tags,
            ],
        )
        .expect("insert good doc");

    let bad_tags =
        encrypt_bytes(&key, b"[]", b"external_document.tags:doc-bad").expect("encrypt bad tags");
    external
        .execute(
            r#"INSERT INTO external_documents(
                   doc_id, batch_id, external_origin_id, source_rel_path, title, body_markdown, tags_json,
                   created_at_ms, updated_at_ms, checksum_sha256, is_deleted
               ) VALUES (?1, ?2, NULL, ?3, ?4, ?5, ?6, 2, 2, 'bad', 0)"#,
            params![
                "doc-bad",
                "batch-1",
                "bad.md",
                vec![1u8, 2u8, 3u8],
                vec![4u8, 5u8, 6u8],
                bad_tags,
            ],
        )
        .expect("insert bad doc");

    let documents = collect_source_knowledge_documents(&conn, &key).expect("collect docs");

    assert!(documents
        .iter()
        .any(|doc| doc.document_id == "external:doc-good"));
    assert!(!documents
        .iter()
        .any(|doc| doc.document_id == "external:doc-bad"));
}

#[test]
fn knowledge_adapter_skips_attachments_with_invalid_annotation_json() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let conn = db::open(&app_dir).expect("open");
    let key = [11u8; 32];

    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    let msg =
        db::insert_message(&conn, &key, &conv.id, "user", "hello from chat").expect("message");

    let good_attachment =
        db::insert_attachment(&conn, &key, &app_dir, b"good pdf", "application/pdf")
            .expect("good attachment");
    db::link_attachment_to_message(&conn, &key, &msg.id, &good_attachment.sha256)
        .expect("link good");
    db::mark_attachment_annotation_ok(
        &conn,
        &key,
        &good_attachment.sha256,
        "en",
        "document_extract.v1",
        &serde_json::json!({
            "schema": "secondloop.document_extract.v1",
            "extracted_text_full": "Healthy attachment body.",
            "mime_type": "application/pdf"
        }),
        1000,
    )
    .expect("good annotation");

    let bad_attachment =
        db::insert_attachment(&conn, &key, &app_dir, b"bad pdf", "application/pdf")
            .expect("bad attachment");
    db::link_attachment_to_message(&conn, &key, &msg.id, &bad_attachment.sha256).expect("link bad");
    db::mark_attachment_annotation_ok(
        &conn,
        &key,
        &bad_attachment.sha256,
        "en",
        "document_extract.v1",
        &serde_json::json!({
            "schema": "secondloop.document_extract.v1",
            "extracted_text_full": "This will be corrupted.",
            "mime_type": "application/pdf"
        }),
        1000,
    )
    .expect("bad annotation seed");

    let invalid_json_blob = encrypt_bytes(
        &key,
        b"not json",
        format!("attachment.annotation:{}:en", bad_attachment.sha256).as_bytes(),
    )
    .expect("encrypt invalid json");
    conn.execute(
        "UPDATE attachment_annotations SET payload = ?2 WHERE attachment_sha256 = ?1",
        params![bad_attachment.sha256, invalid_json_blob],
    )
    .expect("poison annotation payload");

    let documents = collect_source_knowledge_documents(&conn, &key).expect("collect docs");

    assert!(documents.iter().any(|doc| {
        doc.origin_type == KnowledgeOriginType::Attachment
            && doc.source_kind == KnowledgeSourceKind::ExtractedText
            && doc.anchors.attachment_sha256.as_deref() == Some(good_attachment.sha256.as_str())
    }));
    assert!(!documents.iter().any(|doc| {
        doc.origin_type == KnowledgeOriginType::Attachment
            && doc.anchors.attachment_sha256.as_deref() == Some(bad_attachment.sha256.as_str())
    }));
}
