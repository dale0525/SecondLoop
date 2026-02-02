use rusqlite::Connection;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::embedding::{Embedder, DEFAULT_EMBED_DIM};
use secondloop_rust::{auth, db};

#[derive(Clone)]
struct FakeEmbedder {
    model_name: String,
    bias: f32,
    dim: usize,
}

impl FakeEmbedder {
    fn new(model_name: &str, bias: f32, dim: usize) -> Self {
        Self {
            model_name: model_name.to_string(),
            bias,
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
                    v[0] = 1.0 + self.bias;
                }
                if lc.contains("banana") {
                    v[1] = 1.0 + self.bias;
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

fn count_rows(conn: &Connection, table: &str) -> i64 {
    conn.query_row(&format!("SELECT COUNT(*) FROM \"{table}\""), [], |row| {
        row.get(0)
    })
    .expect("count rows")
}

#[test]
fn switching_embedding_model_creates_separate_spaces_without_drop() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    db::insert_message(&conn, &key, &conversation.id, "user", "apple pie").expect("m1");
    db::insert_message(&conn, &key, &conversation.id, "user", "banana").expect("m2");

    let embedder_v1 = FakeEmbedder::new("fake-embed-v1", 0.0, DEFAULT_EMBED_DIM);
    let processed =
        db::process_pending_message_embeddings(&conn, &key, &embedder_v1, 100).expect("process v1");
    assert_eq!(processed, 2);

    let pending: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM messages WHERE needs_embedding = 1",
            [],
            |row| row.get(0),
        )
        .expect("pending count");
    assert_eq!(pending, 0);

    let space_v1 = space_id(embedder_v1.model_name(), embedder_v1.dim());
    let message_table_v1 = format!("message_embeddings__{space_v1}");
    let rows_v1 = count_rows(&conn, &message_table_v1);
    assert_eq!(rows_v1, 2);

    db::set_active_embedding_model(&conn, embedder_v1.model_name(), embedder_v1.dim())
        .expect("set active model v1");

    let embedder_v2 = FakeEmbedder::new("fake-embed-v2", 10.0, DEFAULT_EMBED_DIM);
    let changed =
        db::set_active_embedding_model(&conn, embedder_v2.model_name(), embedder_v2.dim())
            .expect("set active model v2");
    assert!(changed);

    let space_v2 = space_id(embedder_v2.model_name(), embedder_v2.dim());
    let message_table_v2 = format!("message_embeddings__{space_v2}");
    let rows_after_switch = count_rows(&conn, &message_table_v2);
    assert_eq!(rows_after_switch, 0);

    let pending_after_switch: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM messages WHERE needs_embedding = 1",
            [],
            |row| row.get(0),
        )
        .expect("pending after switch");
    assert_eq!(pending_after_switch, 2);

    let processed_v2 =
        db::process_pending_message_embeddings(&conn, &key, &embedder_v2, 100).expect("process v2");
    assert_eq!(processed_v2, 2);

    let bad_rows: i64 = conn
        .query_row(
            &format!("SELECT COUNT(*) FROM \"{message_table_v2}\" WHERE model_name != ?1"),
            [embedder_v2.model_name()],
            |row| row.get(0),
        )
        .expect("model_name check");
    assert_eq!(bad_rows, 0);

    let changed_again =
        db::set_active_embedding_model(&conn, embedder_v2.model_name(), embedder_v2.dim())
            .expect("set active model v2 again");
    assert!(!changed_again);

    let rows_after_noop = count_rows(&conn, &message_table_v2);
    assert_eq!(rows_after_noop, 2);

    let embedder_v2_wide = FakeEmbedder::new("fake-embed-v2", 10.0, 1024);
    let dim_changed = db::set_active_embedding_model(
        &conn,
        embedder_v2_wide.model_name(),
        embedder_v2_wide.dim(),
    )
    .expect("set active model v2 wide");
    assert!(dim_changed);

    let stored_dim = db::get_active_embedding_dim(&conn)
        .expect("get active embedding dim")
        .expect("stored embedding dim");
    assert_eq!(stored_dim, 1024);

    let processed_wide =
        db::process_pending_message_embeddings(&conn, &key, &embedder_v2_wide, 100)
            .expect("process v2 wide");
    assert_eq!(processed_wide, 2);

    let space_v2_wide = space_id(embedder_v2_wide.model_name(), embedder_v2_wide.dim());
    let message_table_v2_wide = format!("message_embeddings__{space_v2_wide}");
    let rows_wide = count_rows(&conn, &message_table_v2_wide);
    assert_eq!(rows_wide, 2);

    // v1 vectors are preserved after switching away and back.
    let rows_v1_preserved = count_rows(&conn, &message_table_v1);
    assert_eq!(rows_v1_preserved, 2);
}
