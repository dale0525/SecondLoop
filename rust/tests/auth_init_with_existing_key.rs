use secondloop_rust::auth;
use secondloop_rust::crypto::KdfParams;
use tempfile::tempdir;

#[test]
fn init_with_existing_key_keeps_session_key() {
    let tmp = tempdir().expect("tempdir");
    let app_dir = tmp.path();
    let session_key = [7u8; 32];

    let key = auth::init_master_password_with_existing_key(
        app_dir,
        "pw",
        KdfParams::for_test(),
        session_key,
    )
    .expect("init with key");
    assert_eq!(key, session_key);

    let unlocked = auth::unlock_with_password(app_dir, "pw").expect("unlock");
    assert_eq!(unlocked, session_key);

    auth::validate_key(app_dir, &session_key).expect("validate key");
}
