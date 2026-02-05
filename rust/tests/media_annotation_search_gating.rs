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
fn media_annotation_search_gating_gates_embedding_enrichment() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    fs::create_dir_all(&app_dir).expect("create app dir");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("create conversation");
    let message =
        db::insert_message(&conn, &key, &conversation.id, "user", "").expect("insert message");

    let attachment =
        db::insert_attachment(&conn, &key, &app_dir, b"img", "image/jpeg").expect("attachment");
    db::link_attachment_to_message(&conn, &key, &message.id, &attachment.sha256)
        .expect("link attachment");

    let now = message.created_at_ms;
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

    // Explicitly disable annotation search enrichment.
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES ('media_annotation.search_enabled', '0')
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        [],
    )
    .expect("set search_enabled=0");

    let embedder = CaptureEmbedder::new(384);
    let processed = db::process_pending_message_embeddings(&conn, &key, &embedder, 10)
        .expect("process embeddings");
    assert_eq!(processed, 1);

    let seen = embedder.seen_texts();
    assert_eq!(seen.len(), 1);
    assert!(!seen[0].contains("keyword_caption"));
}

#[test]
fn media_annotation_search_toggle_marks_memory_messages_for_reembedding() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    fs::create_dir_all(&app_dir).expect("create app dir");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("create conversation");
    let message =
        db::insert_message(&conn, &key, &conversation.id, "user", "").expect("insert message");
    let non_memory_message =
        db::insert_message(&conn, &key, &conversation.id, "user", "").expect("insert message");
    conn.execute(
        r#"UPDATE messages SET is_memory = 0, needs_embedding = 0 WHERE id = ?1"#,
        [&non_memory_message.id],
    )
    .expect("set non-memory message");

    let attachment =
        db::insert_attachment(&conn, &key, &app_dir, b"img", "image/jpeg").expect("attachment");
    db::link_attachment_to_message(&conn, &key, &message.id, &attachment.sha256)
        .expect("link attachment");

    let now = message.created_at_ms;
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

    // Start with search disabled and build embeddings.
    let mut config = db::get_media_annotation_config(&conn).expect("read config");
    config.search_enabled = false;
    db::set_media_annotation_config(&conn, &config).expect("write config");

    let embedder = CaptureEmbedder::new(384);
    let processed = db::process_pending_message_embeddings(&conn, &key, &embedder, 10)
        .expect("process embeddings");
    assert_eq!(processed, 1);

    let needs_embedding: i64 = conn
        .query_row(
            r#"SELECT COALESCE(needs_embedding, 0) FROM messages WHERE id = ?1"#,
            [&message.id],
            |row| row.get(0),
        )
        .expect("query needs_embedding");
    assert_eq!(needs_embedding, 0);

    // Toggle search enabled and ensure memory messages are re-embedded.
    config.search_enabled = true;
    db::set_media_annotation_config(&conn, &config).expect("write config");

    let needs_embedding_after: i64 = conn
        .query_row(
            r#"SELECT COALESCE(needs_embedding, 0) FROM messages WHERE id = ?1"#,
            [&message.id],
            |row| row.get(0),
        )
        .expect("query needs_embedding after");
    assert_eq!(needs_embedding_after, 1);

    let non_memory_needs_embedding: i64 = conn
        .query_row(
            r#"SELECT COALESCE(needs_embedding, 0) FROM messages WHERE id = ?1"#,
            [&non_memory_message.id],
            |row| row.get(0),
        )
        .expect("query non-memory needs_embedding");
    assert_eq!(non_memory_needs_embedding, 0);
}
