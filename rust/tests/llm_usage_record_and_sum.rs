use secondloop_rust::auth;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::db;

#[test]
fn llm_usage_daily_records_and_sums_by_purpose() {
    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");
    let conn = db::open(&app_dir).expect("open db");

    let profile1 = db::create_llm_profile(
        &conn,
        &key,
        "OpenAI",
        "openai-compatible",
        Some("https://api.openai.com/v1"),
        Some("sk-test"),
        "gpt-4o-mini",
        true,
    )
    .expect("create profile1");

    let profile2 = db::create_llm_profile(
        &conn,
        &key,
        "Gemini",
        "gemini-compatible",
        Some("https://generativelanguage.googleapis.com/v1beta"),
        Some("sk-test"),
        "gemini-1.5-flash",
        false,
    )
    .expect("create profile2");

    db::record_llm_usage_daily(
        &conn,
        "2026-01-26",
        &profile1.id,
        "ask_ai",
        Some(10),
        Some(20),
        Some(30),
    )
    .expect("record with usage");

    db::record_llm_usage_daily(
        &conn,
        "2026-01-26",
        &profile1.id,
        "ask_ai",
        None,
        None,
        None,
    )
    .expect("record without usage");

    db::record_llm_usage_daily(
        &conn,
        "2026-01-27",
        &profile1.id,
        "media_annotation",
        Some(1),
        Some(2),
        Some(3),
    )
    .expect("record other purpose");

    db::record_llm_usage_daily(
        &conn,
        "2026-01-26",
        &profile2.id,
        "ask_ai",
        Some(100),
        Some(200),
        Some(300),
    )
    .expect("record other profile");

    let day1 = db::sum_llm_usage_daily_by_purpose(&conn, &profile1.id, "2026-01-26", "2026-01-26")
        .expect("sum day1");
    assert_eq!(day1.len(), 1);
    assert_eq!(day1[0].purpose, "ask_ai");
    assert_eq!(day1[0].requests, 2);
    assert_eq!(day1[0].requests_with_usage, 1);
    assert_eq!(day1[0].input_tokens, 10);
    assert_eq!(day1[0].output_tokens, 20);
    assert_eq!(day1[0].total_tokens, 30);

    let range = db::sum_llm_usage_daily_by_purpose(&conn, &profile1.id, "2026-01-26", "2026-01-27")
        .expect("sum range");
    assert_eq!(range.len(), 2);
    assert_eq!(range[0].purpose, "ask_ai");
    assert_eq!(range[1].purpose, "media_annotation");
}
