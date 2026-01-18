use anyhow::Result;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::embedding::{Embedder, DEFAULT_EMBED_DIM};
use secondloop_rust::{auth, db};

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
            out.push(v);
        }
        Ok(out)
    }
}

#[test]
fn vector_search_dedupes_duplicate_message_contents() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    let _m1 = db::insert_message(&conn, &key, &conversation.id, "user", "apple").expect("m1");
    let _m2 = db::insert_message(&conn, &key, &conversation.id, "user", "apple").expect("m2");
    let _m3 = db::insert_message(&conn, &key, &conversation.id, "user", "apple pie").expect("m3");

    let embedder = TestEmbedder;
    db::process_pending_message_embeddings(&conn, &key, &embedder, 100).expect("index");

    let results = db::search_similar_messages(&conn, &key, &embedder, "apple", 2).expect("search");
    assert_eq!(results.len(), 2);
    assert_eq!(results[0].message.content, "apple");
    assert_eq!(results[1].message.content, "apple pie");
    assert!(results[0].distance <= results[1].distance);
}
