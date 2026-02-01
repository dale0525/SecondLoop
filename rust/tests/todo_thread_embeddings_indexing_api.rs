use rusqlite::params;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::{api, auth, db, embedding};

#[test]
fn todo_thread_indexing_api_processes_pending_embeddings() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    db::set_active_embedding_model_name(&conn, embedding::DEFAULT_MODEL_NAME).expect("model");

    db::upsert_todo(
        &conn, &key, "todo_1", "Buy milk", None, "open", None, None, None, None,
    )
    .expect("upsert todo");
    db::append_todo_note(&conn, &key, "todo_1", "Remember oat milk", None).expect("note");

    let todo_needs_before: Option<i64> = conn
        .query_row(
            r#"SELECT needs_embedding FROM todos WHERE id = ?1"#,
            params!["todo_1"],
            |row| row.get(0),
        )
        .expect("query todo before");
    assert_eq!(todo_needs_before.unwrap_or(0), 1);

    let activity_needs_before: Option<i64> = conn
        .query_row(
            r#"SELECT needs_embedding FROM todo_activities WHERE todo_id = ?1"#,
            params!["todo_1"],
            |row| row.get(0),
        )
        .expect("query activity before");
    assert_eq!(activity_needs_before.unwrap_or(0), 1);

    let processed = api::core::db_process_pending_todo_thread_embeddings(
        app_dir.to_string_lossy().to_string(),
        key.to_vec(),
        32,
        64,
    )
    .expect("process");
    assert!(processed > 0);

    let todo_needs_after: Option<i64> = conn
        .query_row(
            r#"SELECT needs_embedding FROM todos WHERE id = ?1"#,
            params!["todo_1"],
            |row| row.get(0),
        )
        .expect("query todo after");
    assert_eq!(todo_needs_after.unwrap_or(0), 0);

    let activity_needs_after: Option<i64> = conn
        .query_row(
            r#"SELECT needs_embedding FROM todo_activities WHERE todo_id = ?1"#,
            params!["todo_1"],
            |row| row.get(0),
        )
        .expect("query activity after");
    assert_eq!(activity_needs_after.unwrap_or(0), 0);
}
