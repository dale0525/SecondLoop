use secondloop_rust::auth;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::db;

#[test]
fn primary_loop_home_conversation_id_is_stable_and_deterministic() {
    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");
    let conn = db::open(&app_dir).expect("open db");

    let conv1 = db::get_or_create_loop_home_conversation(&conn, &key).expect("get loop");
    assert_eq!(conv1.id, "loop_home");
    assert_eq!(conv1.title, "Loop");

    let conv2 = db::get_or_create_loop_home_conversation(&conn, &key).expect("get loop again");
    assert_eq!(conv2.id, "loop_home");
}
