use secondloop_rust::auth;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::db;

#[test]
fn db_smoke_insert_list_persists_across_restart() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");

    let conn = db::open(&app_dir).expect("open db");
    let conversation =
        db::create_conversation(&conn, &key, "Inbox").expect("create conversation");
    db::insert_message(&conn, &key, &conversation.id, "user", "hello")
        .expect("insert message");
    let messages = db::list_messages(&conn, &key, &conversation.id).expect("list messages");
    assert_eq!(messages.len(), 1);
    assert_eq!(messages[0].content, "hello");
    drop(conn);

    let conn2 = db::open(&app_dir).expect("open db again");
    let messages2 = db::list_messages(&conn2, &key, &conversation.id).expect("list messages");
    assert_eq!(messages2.len(), 1);
    assert_eq!(messages2[0].content, "hello");
}

#[test]
fn db_smoke_wrong_key_cannot_decrypt() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let wrong_key = [0u8; 32];

    let conn = db::open(&app_dir).expect("open db");
    let conversation =
        db::create_conversation(&conn, &key, "Inbox").expect("create conversation");
    db::insert_message(&conn, &key, &conversation.id, "user", "hello")
        .expect("insert message");

    let result = db::list_messages(&conn, &wrong_key, &conversation.id);
    assert!(result.is_err());
}

#[test]
fn db_smoke_requires_unlock_via_auth_file() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    assert!(!auth::is_initialized(&app_dir));

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");

    assert!(auth::is_initialized(&app_dir));

    let unlocked = auth::unlock_with_password(&app_dir, "pw").expect("unlock ok");
    assert_eq!(key, unlocked);
}
