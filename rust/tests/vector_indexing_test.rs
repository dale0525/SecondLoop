use anyhow::Result;
use secondloop_rust::{auth, db};
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::embedding::{Embedder, DEFAULT_EMBED_DIM};

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
fn vector_indexing_test() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    let _m1 = db::insert_message(&conn, &key, &conversation.id, "user", "apple").expect("m1");
    let _m2 = db::insert_message(&conn, &key, &conversation.id, "user", "banana").expect("m2");

    let pending: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM messages WHERE needs_embedding = 1",
            [],
            |row| row.get(0),
        )
        .expect("pending count");
    assert_eq!(pending, 2);

    let embedder = TestEmbedder::default();
    let processed =
        db::process_pending_message_embeddings(&conn, &key, &embedder, 100).expect("process");
    assert_eq!(processed, 2);

    let pending_after: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM messages WHERE needs_embedding = 1",
            [],
            |row| row.get(0),
        )
        .expect("pending count");
    assert_eq!(pending_after, 0);

    let embedding_rows: i64 = conn
        .query_row("SELECT COUNT(*) FROM message_embeddings", [], |row| row.get(0))
        .expect("embedding rows");
    assert_eq!(embedding_rows, 2);
}
