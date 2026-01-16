use secondloop_rust::crypto::KdfParams;
use secondloop_rust::{auth, db};

#[test]
fn vector_search_can_be_scoped_to_conversation() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let c1 = db::create_conversation(&conn, &key, "Inbox").expect("c1");
    let c2 = db::create_conversation(&conn, &key, "Other").expect("c2");

    db::insert_message(&conn, &key, &c1.id, "user", "apple").expect("m1");
    db::insert_message(&conn, &key, &c2.id, "user", "apple pie").expect("m2");
    db::process_pending_message_embeddings_default(&conn, &key, 100).expect("embed");

    let global = db::search_similar_messages_default(&conn, &key, "apple pie", 1).expect("global");
    assert_eq!(global.len(), 1);
    assert_eq!(global[0].message.conversation_id, c2.id);
    assert_eq!(global[0].message.content, "apple pie");

    let scoped =
        db::search_similar_messages_in_conversation_default(&conn, &key, &c1.id, "apple pie", 1)
            .expect("scoped");
    assert_eq!(scoped.len(), 1);
    assert_eq!(scoped[0].message.conversation_id, c1.id);
    assert_eq!(scoped[0].message.content, "apple");
}
