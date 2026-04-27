use rusqlite::params;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::{auth, db};

#[test]
fn llm_profiles_are_encrypted_and_loadable() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let profile = db::create_llm_profile(
        &conn,
        &key,
        "Test",
        "openai-compatible",
        Some("https://example.com/v1"),
        Some("sk-test"),
        "gpt-4o-mini",
        true,
    )
    .expect("create profile");
    assert!(profile.is_active);

    let encrypted: Vec<u8> = conn
        .query_row(
            "SELECT api_key FROM llm_profiles WHERE id = ?1",
            params![profile.id.as_str()],
            |row| row.get(0),
        )
        .expect("read raw api_key");
    assert_ne!(encrypted, b"sk-test".to_vec());

    let (_active_id, active) = db::load_active_llm_profile_config(&conn, &key)
        .expect("load active")
        .expect("has active");
    assert_eq!(active.provider_type, "openai-compatible");
    assert_eq!(active.base_url.as_deref(), Some("https://example.com/v1"));
    assert_eq!(active.api_key.as_deref(), Some("sk-test"));
    assert_eq!(active.model_name, "gpt-4o-mini");
}

#[test]
fn llm_profiles_can_be_listed_and_activated() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let p1 = db::create_llm_profile(
        &conn,
        &key,
        "P1",
        "openai-compatible",
        Some("https://example.com/v1"),
        Some("sk-p1"),
        "gpt-4o-mini",
        true,
    )
    .expect("create profile p1");
    assert!(p1.is_active);

    let p2 = db::create_llm_profile(
        &conn,
        &key,
        "P2",
        "openai-compatible",
        Some("https://example.com/v1"),
        Some("sk-p2"),
        "gpt-4o-mini",
        false,
    )
    .expect("create profile p2");
    assert!(!p2.is_active);

    let profiles = db::list_llm_profiles(&conn).expect("list");
    assert_eq!(profiles.len(), 2);
    let p1_listed = profiles.iter().find(|p| p.id == p1.id).expect("p1");
    let p2_listed = profiles.iter().find(|p| p.id == p2.id).expect("p2");
    assert!(p1_listed.is_active);
    assert!(!p2_listed.is_active);

    db::set_active_llm_profile(&conn, &p2.id).expect("set active");

    let profiles2 = db::list_llm_profiles(&conn).expect("list2");
    let p1_listed2 = profiles2.iter().find(|p| p.id == p1.id).expect("p1");
    let p2_listed2 = profiles2.iter().find(|p| p.id == p2.id).expect("p2");
    assert!(!p1_listed2.is_active);
    assert!(p2_listed2.is_active);

    let (_active_id, active) = db::load_active_llm_profile_config(&conn, &key)
        .expect("load active")
        .expect("has active");
    assert_eq!(active.api_key.as_deref(), Some("sk-p2"));
}

#[test]
fn llm_profiles_reject_unsupported_provider_types() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let err = db::create_llm_profile(
        &conn,
        &key,
        "Gemini",
        "gemini-compatible",
        Some("https://generativelanguage.googleapis.com/v1beta"),
        Some("sk-test"),
        "gemini-1.5-flash",
        true,
    )
    .expect_err("unsupported provider should be rejected");

    assert!(
        err.to_string()
            .contains("unsupported llm provider_type: gemini-compatible"),
        "unexpected error: {err}"
    );
}

#[test]
fn active_llm_profile_loader_ignores_unsupported_provider_types() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    conn.execute(
        r#"INSERT INTO llm_profiles
           (id, name, provider_type, base_url, api_key, model_name, is_active, created_at, updated_at)
           VALUES (?1, ?2, ?3, ?4, NULL, ?5, 1, 1, 1)"#,
        params![
            "unsupported-active",
            "Unsupported Active",
            "gemini-compatible",
            "https://generativelanguage.googleapis.com/v1beta",
            "gemini-1.5-flash",
        ],
    )
    .expect("insert unsupported active profile");

    let active = db::load_active_llm_profile_config(&conn, &key).expect("load active");

    assert!(active.is_none());
}
