use secondloop_rust::auth;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::db;

#[test]
fn primary_chat_conversation_id_is_stable_and_deterministic() {
    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");
    let conn = db::open(&app_dir).expect("open db");

    let conv1 = db::get_or_create_main_stream_conversation(&conn, &key).expect("get chat");
    assert_eq!(conv1.id, "chat_home");
    assert_eq!(conv1.title, "Chat");

    let conv2 = db::get_or_create_main_stream_conversation(&conn, &key).expect("get chat again");
    assert_eq!(conv2.id, "chat_home");
}
