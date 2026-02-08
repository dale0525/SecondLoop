use std::fs;

use secondloop_rust::auth;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::db;

#[test]
fn media_annotation_defaults_enable_media_understanding() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    fs::create_dir_all(&app_dir).expect("create app dir");

    let _key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");
    let conn = db::open(&app_dir).expect("open db");

    let cfg = db::get_media_annotation_config(&conn).expect("read config");
    assert!(cfg.annotate_enabled);
    assert!(cfg.search_enabled);
    assert!(!cfg.allow_cellular);
    assert_eq!(cfg.provider_mode.as_str(), "follow_ask_ai");
}
