use secondloop_rust::auth;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::db;

#[test]
fn list_recent_attachments_returns_latest_first() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");
    let conn = db::open(&app_dir).expect("open db");

    let a1 =
        db::insert_attachment(&conn, &key, &app_dir, b"first", "text/plain").expect("insert 1");
    std::thread::sleep(std::time::Duration::from_millis(3));
    let a2 =
        db::insert_attachment(&conn, &key, &app_dir, b"second", "text/plain").expect("insert 2");

    let recent = db::list_recent_attachments(&conn, &key, 10).expect("list recent");
    assert!(recent.len() >= 2);
    assert_eq!(recent[0].sha256, a2.sha256);
    assert!(recent.iter().any(|a| a.sha256 == a1.sha256));
}
