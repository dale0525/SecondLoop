use anyhow::Result;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::embedding::{Embedder, DEFAULT_EMBED_DIM};
use secondloop_rust::{auth, db};
use zerocopy::IntoBytes;

fn space_id(model_name: &str, dim: usize) -> String {
    let mut s = String::new();
    for ch in model_name.chars() {
        if ch.is_ascii_alphanumeric() {
            s.push(ch.to_ascii_lowercase());
        } else {
            s.push('_');
        }
    }
    while s.contains("__") {
        s = s.replace("__", "_");
    }
    let s = s.trim_matches('_');
    let s = if s.is_empty() { "unknown" } else { s };
    format!("s_{s}_{dim}")
}

#[derive(Clone, Debug, Default)]
struct TestEmbedder;

impl Embedder for TestEmbedder {
    fn model_name(&self) -> &str {
        "test-embedder"
    }

    fn dim(&self) -> usize {
        DEFAULT_EMBED_DIM
    }

    fn embed(&self, texts: &[String]) -> Result<Vec<Vec<f32>>> {
        let mut out = Vec::with_capacity(texts.len());
        for text in texts {
            let mut v = vec![0.0f32; DEFAULT_EMBED_DIM];
            let t = text.to_lowercase();
            if t.contains("apple") {
                v[0] += 1.0;
            }
            if t.contains("pie") {
                v[0] += 1.0;
            }
            if t.contains("banana") {
                v[1] += 1.0;
            }
            out.push(v);
        }
        Ok(out)
    }
}

#[test]
fn vector_search_topk() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    let _m1 = db::insert_message(&conn, &key, &conversation.id, "user", "apple").expect("m1");
    let _m2 = db::insert_message(&conn, &key, &conversation.id, "user", "apple pie").expect("m2");
    let _m3 = db::insert_message(&conn, &key, &conversation.id, "user", "banana").expect("m3");

    let embedder = TestEmbedder;
    db::process_pending_message_embeddings(&conn, &key, &embedder, 100).expect("index");

    let results = db::search_similar_messages(&conn, &key, &embedder, "apple", 2).expect("search");
    assert_eq!(results.len(), 2);
    assert_eq!(results[0].message.content, "apple");
    assert_eq!(results[1].message.content, "apple pie");
    assert!(results[0].distance <= results[1].distance);
}

#[test]
fn vector_search_ignores_other_model() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    let _m1 = db::insert_message(&conn, &key, &conversation.id, "user", "apple").expect("m1");
    let _m2 = db::insert_message(&conn, &key, &conversation.id, "user", "apple pie").expect("m2");
    let m3 = db::insert_message(&conn, &key, &conversation.id, "user", "banana").expect("m3");

    let embedder = TestEmbedder;
    db::process_pending_message_embeddings(&conn, &key, &embedder, 100).expect("index");

    let space = space_id(embedder.model_name(), embedder.dim());
    let message_table = format!("message_embeddings__{space}");

    // Poison one row with a different model_name to simulate another embedding space.
    // Without model_name filtering, this would become the #1 result.
    let m3_rowid: i64 = conn
        .query_row(
            "SELECT rowid FROM messages WHERE id = ?1",
            rusqlite::params![m3.id.as_str()],
            |row| row.get(0),
        )
        .expect("m3 rowid");
    let mut query_vecs = embedder.embed(&["apple".to_string()]).expect("embed query");
    let query_vec = query_vecs.remove(0);
    conn.execute(
        &format!("UPDATE \"{message_table}\" SET embedding = ?1, model_name = ?2 WHERE rowid = ?3"),
        rusqlite::params![query_vec.as_bytes(), "other-model", m3_rowid],
    )
    .expect("insert other-model row");

    let results = db::search_similar_messages(&conn, &key, &embedder, "apple", 2).expect("search");
    assert_eq!(results.len(), 2);
    assert_eq!(results[0].message.content, "apple");
    assert_eq!(results[1].message.content, "apple pie");
}
