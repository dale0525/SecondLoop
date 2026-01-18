use secondloop_rust::crypto::KdfParams;
use secondloop_rust::{auth, db};

#[test]
fn set_active_embedding_model_only_marks_memory_messages_pending() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    db::insert_message(&conn, &key, &conversation.id, "user", "memory").expect("memory");
    db::insert_message_non_memory(&conn, &key, &conversation.id, "user", "non-memory")
        .expect("non-memory");

    db::set_active_embedding_model_name(&conn, "test-embed-v1").expect("set active model");

    let pending: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM messages WHERE COALESCE(needs_embedding, 1) = 1",
            [],
            |row| row.get(0),
        )
        .expect("pending count");
    assert_eq!(pending, 1);
}

#[test]
fn rebuild_message_embeddings_default_does_not_leave_non_memory_pending() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    db::insert_message(&conn, &key, &conversation.id, "user", "apple pie").expect("memory");
    db::insert_message_non_memory(&conn, &key, &conversation.id, "user", "apple")
        .expect("non-memory");

    db::rebuild_message_embeddings_default(&conn, &key, 100).expect("rebuild");

    let pending: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM messages WHERE COALESCE(needs_embedding, 1) = 1",
            [],
            |row| row.get(0),
        )
        .expect("pending count");
    assert_eq!(pending, 0);
}

