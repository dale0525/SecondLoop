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

#[test]
fn switching_embedding_model_triggers_full_reindex() {
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

    let rows_v1: i64 = conn
        .query_row("SELECT COUNT(*) FROM message_embeddings", [], |row| {
            row.get(0)
        })
        .expect("embeddings count v1");
    assert_eq!(rows_v1, 2);

    db::set_active_embedding_model(&conn, embedder_v1.model_name(), embedder_v1.dim())
        .expect("set active model v1");

    let embedder_v2 = FakeEmbedder::new("fake-embed-v2", 10.0, DEFAULT_EMBED_DIM);
    let changed =
        db::set_active_embedding_model(&conn, embedder_v2.model_name(), embedder_v2.dim())
            .expect("set active model v2");
    assert!(changed);

    let rows_after_switch: i64 = conn
        .query_row("SELECT COUNT(*) FROM message_embeddings", [], |row| {
            row.get(0)
        })
        .expect("embeddings after switch");
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
            "SELECT COUNT(*) FROM message_embeddings WHERE model_name != ?1",
            [embedder_v2.model_name()],
            |row| row.get(0),
        )
        .expect("model_name check");
    assert_eq!(bad_rows, 0);

    let changed_again =
        db::set_active_embedding_model(&conn, embedder_v2.model_name(), embedder_v2.dim())
            .expect("set active model v2 again");
    assert!(!changed_again);

    let rows_after_noop: i64 = conn
        .query_row("SELECT COUNT(*) FROM message_embeddings", [], |row| {
            row.get(0)
        })
        .expect("embeddings after noop");
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
}
