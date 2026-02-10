use std::fs;
use std::sync::Mutex;

use secondloop_rust::auth;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::db;
use secondloop_rust::embedding::Embedder;

struct CaptureEmbedder {
    dim: usize,
    seen: Mutex<Vec<String>>,
}

impl CaptureEmbedder {
    fn new(dim: usize) -> Self {
        Self {
            dim,
            seen: Mutex::new(Vec::new()),
        }
    }

    fn seen_texts(&self) -> Vec<String> {
        self.seen.lock().expect("lock").iter().cloned().collect()
    }
}

impl Embedder for CaptureEmbedder {
    fn model_name(&self) -> &str {
        "capture"
    }

    fn dim(&self) -> usize {
        self.dim
    }

    fn embed(&self, texts: &[String]) -> anyhow::Result<Vec<Vec<f32>>> {
        self.seen
            .lock()
            .expect("lock")
            .extend(texts.iter().cloned());

        Ok(vec![vec![0.0f32; self.dim]; texts.len()])
    }
}

#[test]
fn message_embedding_includes_attachment_enrichment() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    fs::create_dir_all(&app_dir).expect("create app dir");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");
    let conn = db::open(&app_dir).expect("open db");

    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES ('media_annotation.search_enabled', '1')
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        [],
    )
    .expect("enable media annotation search");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("create conversation");
    let message =
        db::insert_message(&conn, &key, &conversation.id, "user", "").expect("insert message");

    let attachment =
        db::insert_attachment(&conn, &key, &app_dir, b"img", "image/jpeg").expect("attachment");
    db::link_attachment_to_message(&conn, &key, &message.id, &attachment.sha256)
        .expect("link attachment");

    let now = message.created_at_ms;

    let place_json = serde_json::json!({
        "display_name": "keyword_place"
    });
    db::mark_attachment_place_ok(&conn, &key, &attachment.sha256, "en", &place_json, now)
        .expect("mark place ok");

    let ann_json = serde_json::json!({
        "caption_long": "keyword_caption",
        "tags": ["t1"],
        "ocr_text": null
    });
    db::mark_attachment_annotation_ok(
        &conn,
        &key,
        &attachment.sha256,
        "en",
        "test-model",
        &ann_json,
        now,
    )
    .expect("mark annotation ok");

    let embedder = CaptureEmbedder::new(384);
    let processed = db::process_pending_message_embeddings(&conn, &key, &embedder, 10)
        .expect("process embeddings");
    assert_eq!(processed, 1);

    let seen = embedder.seen_texts();
    assert_eq!(seen.len(), 1);
    assert!(seen[0].contains("keyword_place"));
    assert!(seen[0].contains("keyword_caption"));

    let place_json2 = serde_json::json!({
        "display_name": "keyword_place_2"
    });
    db::mark_attachment_place_ok(&conn, &key, &attachment.sha256, "en", &place_json2, now + 1)
        .expect("mark place ok again");

    let needs_embedding: i64 = conn
        .query_row(
            r#"SELECT COALESCE(needs_embedding, 0) FROM messages WHERE id = ?1"#,
            [&message.id],
            |row| row.get(0),
        )
        .expect("query needs_embedding");
    assert_eq!(needs_embedding, 1);
}

#[test]
fn message_embedding_includes_attachment_content_excerpt() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    fs::create_dir_all(&app_dir).expect("create app dir");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("create conversation");
    let message =
        db::insert_message(&conn, &key, &conversation.id, "user", "hello").expect("insert message");

    let attachment =
        db::insert_attachment(&conn, &key, &app_dir, b"doc", "text/plain").expect("attachment");
    db::link_attachment_to_message(&conn, &key, &message.id, &attachment.sha256)
        .expect("link attachment");

    let now = message.created_at_ms;
    let ann_json = serde_json::json!({
        "extracted_text_excerpt": "keyword_doc_excerpt",
        "extracted_text_full": "keyword_doc_full",
        "needs_ocr": false,
        "page_count": null
    });
    db::mark_attachment_annotation_ok(
        &conn,
        &key,
        &attachment.sha256,
        "und",
        "document_extract.v1",
        &ann_json,
        now,
    )
    .expect("mark annotation ok");

    let embedder = CaptureEmbedder::new(384);
    let processed = db::process_pending_message_embeddings(&conn, &key, &embedder, 10)
        .expect("process embeddings");
    assert_eq!(processed, 1);

    let seen = embedder.seen_texts();
    assert_eq!(seen.len(), 1);
    assert!(seen[0].contains("keyword_doc_excerpt"));
}

#[test]
fn message_embedding_prefers_extracted_excerpt_when_present() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    fs::create_dir_all(&app_dir).expect("create app dir");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("create conversation");
    let message =
        db::insert_message(&conn, &key, &conversation.id, "user", "hello").expect("insert message");

    let attachment = db::insert_attachment(&conn, &key, &app_dir, b"doc", "application/pdf")
        .expect("attachment");
    db::link_attachment_to_message(&conn, &key, &message.id, &attachment.sha256)
        .expect("link attachment");

    let now = message.created_at_ms;
    let ann_json = serde_json::json!({
        "extracted_text_excerpt": "keyword_doc_excerpt",
        "ocr_text_excerpt": "keyword_ocr_excerpt",
        "ocr_text_full": "keyword_ocr_full",
        "needs_ocr": false
    });
    db::mark_attachment_annotation_ok(
        &conn,
        &key,
        &attachment.sha256,
        "und",
        "document_extract.v1",
        &ann_json,
        now,
    )
    .expect("mark annotation ok");

    let embedder = CaptureEmbedder::new(384);
    let processed = db::process_pending_message_embeddings(&conn, &key, &embedder, 10)
        .expect("process embeddings");
    assert_eq!(processed, 1);

    let seen = embedder.seen_texts();
    assert_eq!(seen.len(), 1);
    assert!(seen[0].contains("keyword_doc_excerpt"));
}

#[test]
fn message_embedding_prefers_ocr_excerpt_when_extracted_looks_degraded() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    fs::create_dir_all(&app_dir).expect("create app dir");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("create conversation");
    let message =
        db::insert_message(&conn, &key, &conversation.id, "user", "hello").expect("insert message");

    let attachment = db::insert_attachment(&conn, &key, &app_dir, b"doc", "application/pdf")
        .expect("attachment");
    db::link_attachment_to_message(&conn, &key, &message.id, &attachment.sha256)
        .expect("link attachment");

    let now = message.created_at_ms;
    let ann_json = serde_json::json!({
        "extracted_text_excerpt": "A B C D E F G H I J K L M N O P",
        "ocr_text_excerpt": "keyword_ocr_excerpt",
        "ocr_text_full": "keyword_ocr_full",
        "needs_ocr": false
    });
    db::mark_attachment_annotation_ok(
        &conn,
        &key,
        &attachment.sha256,
        "und",
        "document_extract.v1",
        &ann_json,
        now,
    )
    .expect("mark annotation ok");

    let embedder = CaptureEmbedder::new(384);
    let processed = db::process_pending_message_embeddings(&conn, &key, &embedder, 10)
        .expect("process embeddings");
    assert_eq!(processed, 1);

    let seen = embedder.seen_texts();
    assert_eq!(seen.len(), 1);
    assert!(seen[0].contains("keyword_ocr_excerpt"));
}

#[test]
fn message_embedding_prefers_ocr_excerpt_for_spaced_cjk_garbled_extracted() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    fs::create_dir_all(&app_dir).expect("create app dir");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("create conversation");
    let message =
        db::insert_message(&conn, &key, &conversation.id, "user", "hello").expect("insert message");

    let attachment = db::insert_attachment(&conn, &key, &app_dir, b"doc", "application/pdf")
        .expect("attachment");
    db::link_attachment_to_message(&conn, &key, &message.id, &attachment.sha256)
        .expect("link attachment");

    let now = message.created_at_ms;
    let ann_json = serde_json::json!({
        "extracted_text_excerpt": "書 190 会丈森 女 不 公 合 不 因 不 留 高 单",
        "ocr_text_excerpt": "这是一个正常的中文句子用于测试 OCR 结果。",
        "ocr_text_full": "这是一个正常的中文句子用于测试 OCR 结果。",
        "needs_ocr": false
    });
    db::mark_attachment_annotation_ok(
        &conn,
        &key,
        &attachment.sha256,
        "und",
        "document_extract.v1",
        &ann_json,
        now,
    )
    .expect("mark annotation ok");

    let embedder = CaptureEmbedder::new(384);
    let processed = db::process_pending_message_embeddings(&conn, &key, &embedder, 10)
        .expect("process embeddings");
    assert_eq!(processed, 1);

    let seen = embedder.seen_texts();
    assert_eq!(seen.len(), 1);
    assert!(seen[0].contains("这是一个正常的中文句子用于测试 OCR 结果。"));
}

#[test]
fn message_embedding_includes_legacy_ocr_text_field() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    fs::create_dir_all(&app_dir).expect("create app dir");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("create conversation");
    let message =
        db::insert_message(&conn, &key, &conversation.id, "user", "hello").expect("insert message");

    let attachment =
        db::insert_attachment(&conn, &key, &app_dir, b"img", "image/jpeg").expect("attachment");
    db::link_attachment_to_message(&conn, &key, &message.id, &attachment.sha256)
        .expect("link attachment");

    let now = message.created_at_ms;
    let ann_json = serde_json::json!({
        "caption_long": "ocr fallback caption",
        "ocr_text": "keyword_legacy_ocr_text"
    });
    db::mark_attachment_annotation_ok(
        &conn,
        &key,
        &attachment.sha256,
        "en",
        "manual_edit",
        &ann_json,
        now,
    )
    .expect("mark annotation ok");

    let embedder = CaptureEmbedder::new(384);
    let processed = db::process_pending_message_embeddings(&conn, &key, &embedder, 10)
        .expect("process embeddings");
    assert_eq!(processed, 1);

    let seen = embedder.seen_texts();
    assert_eq!(seen.len(), 1);
    assert!(seen[0].contains("keyword_legacy_ocr_text"));
}

#[test]
fn message_embedding_merges_docx_extracted_and_ocr_text() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    fs::create_dir_all(&app_dir).expect("create app dir");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("create conversation");
    let message =
        db::insert_message(&conn, &key, &conversation.id, "user", "hello").expect("insert message");

    let attachment = db::insert_attachment(
        &conn,
        &key,
        &app_dir,
        b"docx",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    )
    .expect("attachment");
    db::link_attachment_to_message(&conn, &key, &message.id, &attachment.sha256)
        .expect("link attachment");

    let now = message.created_at_ms;
    let ann_json = serde_json::json!({
        "schema": "secondloop.document_extract.v1",
        "mime_type": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "extracted_text_excerpt": "keyword_docx_body",
        "ocr_text_full": "keyword_docx_image"
    });
    db::mark_attachment_annotation_ok(
        &conn,
        &key,
        &attachment.sha256,
        "und",
        "document_extract.v1",
        &ann_json,
        now,
    )
    .expect("mark annotation ok");

    let embedder = CaptureEmbedder::new(384);
    let processed = db::process_pending_message_embeddings(&conn, &key, &embedder, 10)
        .expect("process embeddings");
    assert_eq!(processed, 1);

    let seen = embedder.seen_texts();
    assert_eq!(seen.len(), 1);
    assert!(seen[0].contains("keyword_docx_body"));
    assert!(seen[0].contains("keyword_docx_image"));
}

#[test]
fn message_embedding_includes_audio_transcript_excerpt() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    fs::create_dir_all(&app_dir).expect("create app dir");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("create conversation");
    let message = db::insert_message(&conn, &key, &conversation.id, "user", "voice memo")
        .expect("insert message");

    let attachment =
        db::insert_attachment(&conn, &key, &app_dir, b"m4a", "audio/mp4").expect("attachment");
    db::link_attachment_to_message(&conn, &key, &message.id, &attachment.sha256)
        .expect("link attachment");

    let now = message.created_at_ms;
    let transcript_json = serde_json::json!({
        "schema": "secondloop.audio_transcript.v1",
        "transcript_excerpt": "keyword_audio_excerpt",
        "transcript_full": "keyword_audio_full"
    });
    db::mark_attachment_annotation_ok(
        &conn,
        &key,
        &attachment.sha256,
        "en",
        "whisper-1",
        &transcript_json,
        now,
    )
    .expect("mark transcript ok");

    let embedder = CaptureEmbedder::new(384);
    let processed = db::process_pending_message_embeddings(&conn, &key, &embedder, 10)
        .expect("process embeddings");
    assert_eq!(processed, 1);

    let seen = embedder.seen_texts();
    assert_eq!(seen.len(), 1);
    assert!(seen[0].contains("keyword_audio_excerpt"));
}
