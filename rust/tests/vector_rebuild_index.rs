use secondloop_rust::crypto::KdfParams;
use secondloop_rust::{auth, db};

#[test]
fn vector_rebuild_index_preserves_search_results() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    db::insert_message(&conn, &key, &conversation.id, "user", "apple").expect("m1");
    db::insert_message(&conn, &key, &conversation.id, "user", "apple pie").expect("m2");
    db::insert_message(&conn, &key, &conversation.id, "user", "banana").expect("m3");

    let processed =
        db::process_pending_message_embeddings_default(&conn, &key, 100).expect("process");
    assert_eq!(processed, 3);

    let before = db::search_similar_messages_default(&conn, &key, "apple", 2).expect("search");
    assert_eq!(before.len(), 2);
    assert_eq!(before[0].message.content, "apple");
    assert_eq!(before[1].message.content, "apple pie");

    let rebuilt = db::rebuild_message_embeddings_default(&conn, &key, 100).expect("rebuild");
    assert_eq!(rebuilt, 3);

    let pending: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM messages WHERE needs_embedding = 1",
            [],
            |row| row.get(0),
        )
        .expect("pending count");
    assert_eq!(pending, 0);

    let embedding_rows: i64 = conn
        .query_row("SELECT COUNT(*) FROM message_embeddings", [], |row| {
            row.get(0)
        })
        .expect("embedding rows");
    assert_eq!(embedding_rows, 3);

    let after = db::search_similar_messages_default(&conn, &key, "apple", 2).expect("search");
    assert_eq!(after.len(), 2);
    assert_eq!(after[0].message.content, "apple");
    assert_eq!(after[1].message.content, "apple pie");
    assert!(after[0].distance <= after[1].distance);
}
