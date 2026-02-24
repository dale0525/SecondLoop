use anyhow::Result;
use secondloop_rust::auth;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::db;
use secondloop_rust::embedding::Embedder;

struct KeywordEmbedder;

impl Embedder for KeywordEmbedder {
    fn model_name(&self) -> &str {
        "fake-attachment-chunk"
    }

    fn dim(&self) -> usize {
        8
    }

    fn embed(&self, texts: &[String]) -> Result<Vec<Vec<f32>>> {
        Ok(texts.iter().map(|text| embed_text(text)).collect())
    }
}

fn embed_text(text: &str) -> Vec<f32> {
    let mut out = vec![0.0f32; 8];
    let lower = text.to_ascii_lowercase();

    if lower.contains("orion") {
        out[0] = 1.0;
    }
    if lower.contains("beacon") {
        out[1] = 1.0;
    }
    if lower.contains("jupiter") {
        out[2] = 1.0;
    }
    if lower.contains("ledger") {
        out[3] = 1.0;
    }

    out
}

#[test]
fn attachment_chunk_search_returns_matching_chunk_snippet() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let embedder = KeywordEmbedder;
    db::set_active_embedding_model(&conn, embedder.model_name(), 8).expect("set embedding model");

    let a_orion =
        db::insert_attachment(&conn, &key, &app_dir, b"orion", "text/plain").expect("insert a1");
    let a_jupiter =
        db::insert_attachment(&conn, &key, &app_dir, b"jupiter", "text/plain").expect("insert a2");

    db::mark_attachment_annotation_ok(
        &conn,
        &key,
        &a_orion.sha256,
        "en",
        "test-model",
        &serde_json::json!({
            "extracted_text_full": "orion beacon daily log from mission control"
        }),
        1_700_000_000_100,
    )
    .expect("annotate a1");

    db::mark_attachment_annotation_ok(
        &conn,
        &key,
        &a_jupiter.sha256,
        "en",
        "test-model",
        &serde_json::json!({
            "extracted_text_full": "jupiter ledger for supply manifests"
        }),
        1_700_000_000_200,
    )
    .expect("annotate a2");

    db::process_attachment_text_chunks(&conn, &key, 16).expect("chunk index");
    let processed = db::process_pending_attachment_chunk_embeddings(&conn, &key, &embedder, 128)
        .expect("embed chunks");
    assert!(processed >= 2);

    let hits = db::search_similar_attachment_chunks(&conn, &key, &embedder, "orion beacon", 5)
        .expect("search chunks");
    assert!(!hits.is_empty());
    assert_eq!(hits[0].attachment_sha256, a_orion.sha256);
    assert!(hits[0].snippet.to_ascii_lowercase().contains("orion"));
}
