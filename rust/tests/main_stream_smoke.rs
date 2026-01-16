use secondloop_rust::auth;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::db;

#[test]
fn main_stream_conversation_id_is_stable_and_deterministic() {
    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");
    let conn = db::open(&app_dir).expect("open db");

    let conv1 = db::get_or_create_main_stream_conversation(&conn, &key)
        .expect("get main stream");
    assert_eq!(conv1.id, "main_stream");
    assert_eq!(conv1.title, "Main Stream");

    let conv2 = db::get_or_create_main_stream_conversation(&conn, &key)
        .expect("get main stream again");
    assert_eq!(conv2.id, "main_stream");
}

