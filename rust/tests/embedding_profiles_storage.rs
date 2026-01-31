use rusqlite::params;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::{auth, db};

#[test]
fn embedding_profiles_are_encrypted_and_loadable() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let profile = db::create_embedding_profile(
        &conn,
        &key,
        "Test",
        "openai-compatible",
        Some("https://example.com/v1"),
        Some("sk-emb-test"),
        "multilingual-e5-small",
        true,
    )
    .expect("create profile");
    assert!(profile.is_active);

    let encrypted: Vec<u8> = conn
        .query_row(
            "SELECT api_key FROM embedding_profiles WHERE id = ?1",
            params![profile.id.as_str()],
            |row| row.get(0),
        )
        .expect("read raw api_key");
    assert_ne!(encrypted, b"sk-emb-test".to_vec());

    let (_active_id, active) = db::load_active_embedding_profile_config(&conn, &key)
        .expect("load active")
        .expect("has active");
    assert_eq!(active.provider_type, "openai-compatible");
    assert_eq!(active.base_url.as_deref(), Some("https://example.com/v1"));
    assert_eq!(active.api_key.as_deref(), Some("sk-emb-test"));
    assert_eq!(active.model_name, "multilingual-e5-small");
}

#[test]
fn embedding_profiles_can_be_listed_and_activated() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let p1 = db::create_embedding_profile(
        &conn,
        &key,
        "P1",
        "openai-compatible",
        Some("https://example.com/v1"),
        Some("sk-p1"),
        "multilingual-e5-small",
        true,
    )
    .expect("create profile p1");
    assert!(p1.is_active);

    let p2 = db::create_embedding_profile(
        &conn,
        &key,
        "P2",
        "openai-compatible",
        Some("https://example.com/v1"),
        Some("sk-p2"),
        "multilingual-e5-small",
        false,
    )
    .expect("create profile p2");
    assert!(!p2.is_active);

    let profiles = db::list_embedding_profiles(&conn).expect("list");
    assert_eq!(profiles.len(), 2);
    let p1_listed = profiles.iter().find(|p| p.id == p1.id).expect("p1");
    let p2_listed = profiles.iter().find(|p| p.id == p2.id).expect("p2");
    assert!(p1_listed.is_active);
    assert!(!p2_listed.is_active);

    db::set_active_embedding_profile(&conn, &p2.id).expect("set active");

    let profiles2 = db::list_embedding_profiles(&conn).expect("list2");
    let p1_listed2 = profiles2.iter().find(|p| p.id == p1.id).expect("p1");
    let p2_listed2 = profiles2.iter().find(|p| p.id == p2.id).expect("p2");
    assert!(!p1_listed2.is_active);
    assert!(p2_listed2.is_active);

    let (_active_id, active) = db::load_active_embedding_profile_config(&conn, &key)
        .expect("load active")
        .expect("has active");
    assert_eq!(active.api_key.as_deref(), Some("sk-p2"));
}
