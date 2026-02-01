use rusqlite::params;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::{api, auth, db, embedding};

#[test]
fn todo_search_does_not_process_pending_embeddings() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    db::set_active_embedding_model_name(&conn, embedding::DEFAULT_MODEL_NAME).expect("model");

    db::upsert_todo(
        &conn, &key, "todo_1", "Buy milk", None, "open", None, None, None, None,
    )
    .expect("upsert todo");

    let before: Option<i64> = conn
        .query_row(
            r#"SELECT needs_embedding FROM todos WHERE id = ?1"#,
            params!["todo_1"],
            |row| row.get(0),
        )
        .expect("query before");
    assert_eq!(before.unwrap_or(0), 1);

    api::core::db_search_similar_todo_threads(
        app_dir.to_string_lossy().to_string(),
        key.to_vec(),
        "milk".to_string(),
        5,
    )
    .expect("search");

    let after: Option<i64> = conn
        .query_row(
            r#"SELECT needs_embedding FROM todos WHERE id = ?1"#,
            params!["todo_1"],
            |row| row.get(0),
        )
        .expect("query after");
    assert_eq!(after.unwrap_or(0), 1);
}
