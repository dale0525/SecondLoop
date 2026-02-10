use std::fs;

use rusqlite::OptionalExtension;
use secondloop_rust::auth;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::db;

fn kv_value(conn: &rusqlite::Connection, key: &str) -> Option<String> {
    conn.query_row(r#"SELECT value FROM kv WHERE key = ?1"#, [key], |row| {
        row.get(0)
    })
    .optional()
    .expect("query kv")
}

#[test]
fn content_enrichment_kv_defaults_exist_and_match_plan() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    fs::create_dir_all(&app_dir).expect("create app dir");

    let _key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");
    let conn = db::open(&app_dir).expect("open db");

    let mb50 = 50i64 * 1024 * 1024;
    let gb2 = 2i64 * 1024 * 1024 * 1024;
    let mb10 = 10i64 * 1024 * 1024;

    let cases: Vec<(&str, String)> = vec![
        ("content_enrichment.url_fetch_enabled", "1".to_string()),
        (
            "content_enrichment.document_extract_enabled",
            "1".to_string(),
        ),
        (
            "content_enrichment.document_keep_original_max_bytes",
            mb50.to_string(),
        ),
        (
            "content_enrichment.audio_transcribe_enabled",
            "1".to_string(),
        ),
        (
            "content_enrichment.audio_transcribe_engine",
            "whisper".to_string(),
        ),
        ("content_enrichment.video_extract_enabled", "1".to_string()),
        ("content_enrichment.video_proxy_enabled", "1".to_string()),
        (
            "content_enrichment.video_proxy_max_duration_ms",
            "3600000".to_string(),
        ),
        (
            "content_enrichment.video_proxy_max_bytes",
            "209715200".to_string(),
        ),
        ("content_enrichment.ocr_enabled", "1".to_string()),
        (
            "content_enrichment.ocr_engine_mode",
            "platform_native".to_string(),
        ),
        (
            "content_enrichment.ocr_language_hints",
            "device_plus_en".to_string(),
        ),
        ("content_enrichment.ocr_pdf_dpi", "180".to_string()),
        ("content_enrichment.ocr_pdf_auto_max_pages", "0".to_string()),
        ("content_enrichment.ocr_pdf_max_pages", "0".to_string()),
        (
            "content_enrichment.mobile_background_enabled",
            "1".to_string(),
        ),
        (
            "content_enrichment.mobile_background_requires_wifi",
            "1".to_string(),
        ),
        (
            "content_enrichment.mobile_background_requires_charging",
            "1".to_string(),
        ),
        ("storage_policy.auto_purge_enabled", "1".to_string()),
        (
            "storage_policy.auto_purge_keep_recent_days",
            "30".to_string(),
        ),
        ("storage_policy.auto_purge_max_cache_bytes", gb2.to_string()),
        (
            "storage_policy.auto_purge_min_candidate_bytes",
            mb10.to_string(),
        ),
        ("storage_policy.auto_purge_include_images", "0".to_string()),
    ];

    for (key, expected) in cases {
        let actual = kv_value(&conn, key);
        assert_eq!(
            actual.as_deref(),
            Some(expected.as_str()),
            "unexpected kv default for {key}"
        );
    }
}

#[test]
fn content_enrichment_ocr_pdf_settings_are_fixed_on_write() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    fs::create_dir_all(&app_dir).expect("create app dir");

    let _key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");
    let conn = db::open(&app_dir).expect("open db");

    let mut cfg = db::get_content_enrichment_config(&conn).expect("read config");
    cfg.audio_transcribe_engine = "local_runtime".to_string();
    cfg.ocr_pdf_dpi = 300;
    cfg.ocr_pdf_auto_max_pages = 50;
    cfg.ocr_pdf_max_pages = 1000;
    cfg.ocr_language_hints = "zh_en".to_string();
    cfg.ocr_engine_mode = "multimodal_llm".to_string();
    db::set_content_enrichment_config(&conn, &cfg).expect("write config");

    let next = db::get_content_enrichment_config(&conn).expect("read updated config");
    assert_eq!(next.audio_transcribe_engine.as_str(), "local_runtime");
    assert_eq!(next.ocr_pdf_dpi, 180);
    assert_eq!(next.ocr_pdf_auto_max_pages, 0);
    assert_eq!(next.ocr_pdf_max_pages, 0);
    assert_eq!(next.ocr_language_hints.as_str(), "device_plus_en");
    assert_eq!(next.ocr_engine_mode.as_str(), "multimodal_llm");
    assert_eq!(
        kv_value(&conn, "content_enrichment.audio_transcribe_engine").as_deref(),
        Some("local_runtime")
    );
    assert_eq!(
        kv_value(&conn, "content_enrichment.ocr_pdf_dpi").as_deref(),
        Some("180")
    );
    assert_eq!(
        kv_value(&conn, "content_enrichment.ocr_pdf_auto_max_pages").as_deref(),
        Some("0")
    );
    assert_eq!(
        kv_value(&conn, "content_enrichment.ocr_pdf_max_pages").as_deref(),
        Some("0")
    );
    assert_eq!(
        kv_value(&conn, "content_enrichment.ocr_language_hints").as_deref(),
        Some("device_plus_en")
    );
    assert_eq!(
        kv_value(&conn, "content_enrichment.ocr_engine_mode").as_deref(),
        Some("multimodal_llm")
    );
}
