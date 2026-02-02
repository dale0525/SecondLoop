use rusqlite::Connection;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::embedding::Embedder;
use secondloop_rust::{auth, db};

#[derive(Clone)]
struct FakeEmbedder {
    model_name: String,
    dim: usize,
}

impl FakeEmbedder {
    fn new(model_name: &str, dim: usize) -> Self {
        Self {
            model_name: model_name.to_string(),
            dim,
        }
    }
}

impl Embedder for FakeEmbedder {
    fn model_name(&self) -> &str {
        &self.model_name
    }

    fn dim(&self) -> usize {
        self.dim
    }

    fn embed(&self, texts: &[String]) -> anyhow::Result<Vec<Vec<f32>>> {
        Ok(texts
            .iter()
            .map(|t| {
                let mut v = vec![0.0f32; self.dim];
                let lc = t.to_lowercase();
                if lc.contains("apple") {
                    v[0] = 1.0;
                }
                if lc.contains("banana") {
                    v[1] = 1.0;
                }
                v
            })
            .collect())
    }
}

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

fn table_exists(conn: &Connection, name: &str) -> bool {
    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?1",
            [name],
            |row| row.get(0),
        )
        .expect("sqlite_master count");
    count > 0
}

#[test]
fn embeddings_multi_index_switching() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    db::insert_message(&conn, &key, &conversation.id, "user", "apple pie").expect("m1");
    db::insert_message(&conn, &key, &conversation.id, "user", "banana").expect("m2");

    let embedder_a = FakeEmbedder::new("space-A", 384);
    let embedder_b = FakeEmbedder::new("space-B", 1024);

    db::set_active_embedding_model(&conn, embedder_a.model_name(), embedder_a.dim())
        .expect("activate space A");
    let processed_a = db::process_pending_message_embeddings(&conn, &key, &embedder_a, 100)
        .expect("process space A");
    assert_eq!(processed_a, 2);

    let space_a = space_id(embedder_a.model_name(), embedder_a.dim());
    let message_table_a = format!("message_embeddings__{space_a}");

    db::set_active_embedding_model(&conn, embedder_b.model_name(), embedder_b.dim())
        .expect("activate space B");

    assert!(
        table_exists(&conn, &message_table_a),
        "expected prior vec0 index preserved as {message_table_a}"
    );

    let preserved_rows: i64 = conn
        .query_row(
            &format!("SELECT COUNT(*) FROM {message_table_a}"),
            [],
            |row| row.get(0),
        )
        .expect("count preserved rows");
    assert_eq!(preserved_rows, 2);

    db::insert_message(&conn, &key, &conversation.id, "user", "cherry").expect("m3");
    let processed_b = db::process_pending_message_embeddings(&conn, &key, &embedder_b, 100)
        .expect("process space B");
    assert_eq!(processed_b, 3);

    db::set_active_embedding_model(&conn, embedder_a.model_name(), embedder_a.dim())
        .expect("activate space A again");

    let pending_after_switch_back: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM messages WHERE COALESCE(needs_embedding, 1) = 1",
            [],
            |row| row.get(0),
        )
        .expect("pending after switch back");
    assert_eq!(pending_after_switch_back, 1);

    let processed_a2 = db::process_pending_message_embeddings(&conn, &key, &embedder_a, 100)
        .expect("process space A again");
    assert_eq!(processed_a2, 1);
}
