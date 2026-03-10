use std::path::PathBuf;

use rusqlite::Connection;

use crate::db;
use crate::knowledge::{
    ensure_knowledge_rebuild_requested, process_pending_knowledge_index_jobs_active,
};

pub(crate) struct RetrievalFixture {
    pub(crate) _dir: tempfile::TempDir,
    pub(crate) app_dir: PathBuf,
    pub(crate) conn: Connection,
    pub(crate) key: [u8; 32],
    pub(crate) conversation_id: String,
    pub(crate) transcript_document_id: String,
    pub(crate) metadata_document_id: String,
}

fn repeated_words(prefix: &str, count: usize) -> String {
    (0..count)
        .map(|index| format!("{prefix}{index}"))
        .collect::<Vec<_>>()
        .join(" ")
}

pub(crate) fn seeded_fixture() -> RetrievalFixture {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let conn = db::open(&app_dir).expect("open");
    let key = [44u8; 32];

    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    let msg = db::insert_message(
        &conn,
        &key,
        &conv.id,
        "user",
        "apple orchard planning with quarterly budget freeze follow-up",
    )
    .expect("message");
    conn.execute(
        "UPDATE messages SET is_memory = 1, needs_embedding = 1 WHERE id = ?1",
        rusqlite::params![msg.id.clone()],
    )
    .expect("mark memory");

    let other = db::insert_message(
        &conn,
        &key,
        &conv.id,
        "user",
        "completely unrelated travel checklist",
    )
    .expect("other message");
    conn.execute(
        "UPDATE messages SET is_memory = 1, needs_embedding = 1 WHERE id = ?1",
        rusqlite::params![other.id.clone()],
    )
    .expect("mark other memory");

    let attachment = db::insert_attachment(&conn, &key, &app_dir, b"pdf bytes", "application/pdf")
        .expect("attachment");
    db::link_attachment_to_message(&conn, &key, &msg.id, &attachment.sha256).expect("link");
    db::upsert_attachment_metadata(
        &conn,
        &key,
        &attachment.sha256,
        Some("Budget freeze overview"),
        &["roadmap-q1.pdf".to_string()],
        &[],
    )
    .expect("metadata");

    let transcript = [
        format!(
            "Speaker Alice: intro-signal {}",
            repeated_words("intro", 90)
        ),
        format!(
            "Speaker Bob: alignment-signal {}",
            repeated_words("align", 90)
        ),
        format!(
            "Speaker Charlie: freeze-signal budget decision {}",
            repeated_words("freeze", 90)
        ),
        format!(
            "Speaker Dana: execution-signal {}",
            repeated_words("execute", 90)
        ),
        format!("Speaker Erin: wrap-signal {}", repeated_words("wrap", 90)),
    ]
    .join("\n\n");

    db::mark_attachment_annotation_ok(
        &conn,
        &key,
        &attachment.sha256,
        "en",
        "document_extract.v1",
        &serde_json::json!({
            "schema": "secondloop.document_extract.v1",
            "readable_text_full": "Quarterly roadmap summary with milestone gating and release notes.",
            "ocr_text_full": "Page 3 budget freeze stamp and orchard invoice total.",
            "transcript_full": transcript,
            "caption_long": "Whiteboard milestone photo with launch readiness notes.",
            "mime_type": "application/pdf"
        }),
        1000,
    )
    .expect("annotation");

    ensure_knowledge_rebuild_requested(&conn).expect("request rebuild");
    process_pending_knowledge_index_jobs_active(&conn, &key, 256).expect("process jobs");

    RetrievalFixture {
        _dir: dir,
        app_dir,
        conn,
        key,
        conversation_id: conv.id,
        transcript_document_id: format!("attachment:{}:transcript", attachment.sha256),
        metadata_document_id: format!("attachment:{}:metadata", attachment.sha256),
    }
}
