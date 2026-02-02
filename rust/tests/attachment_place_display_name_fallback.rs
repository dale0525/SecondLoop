use std::fs;

use rusqlite::{params, Connection};

fn insert_dummy_attachment(conn: &Connection, sha256: &str) {
    conn.execute(
        r#"
INSERT INTO attachments(sha256, mime_type, path, byte_len, created_at)
VALUES (?1, 'image/jpeg', 'attachments/test.bin', 0, 0)
"#,
        params![sha256],
    )
    .expect("insert attachment");
}

#[test]
fn attachment_place_display_name_falls_back_to_city_and_district() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    fs::create_dir_all(&app_dir).expect("create app dir");

    let conn = secondloop_rust::db::open(&app_dir).expect("open");
    let key = [7u8; 32];
    insert_dummy_attachment(&conn, "sha1");

    secondloop_rust::db::mark_attachment_place_ok(
        &conn,
        &key,
        "sha1",
        "zh-CN",
        &serde_json::json!({
            "ok": true,
            "lang": "zh-cn",
            "city": { "id": 1796236, "name": "上海", "distance_m": 123 },
            "district": { "id": 1796231, "name": "浦东新区", "distance_m": 45 },
        }),
        1,
    )
    .expect("mark ok");

    let got = secondloop_rust::db::read_attachment_place_display_name(&conn, &key, "sha1")
        .expect("read display name");
    assert_eq!(got.as_deref(), Some("浦东新区, 上海"));
}

#[test]
fn attachment_place_display_name_prefers_display_name_field() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    fs::create_dir_all(&app_dir).expect("create app dir");

    let conn = secondloop_rust::db::open(&app_dir).expect("open");
    let key = [7u8; 32];
    insert_dummy_attachment(&conn, "sha2");

    secondloop_rust::db::mark_attachment_place_ok(
        &conn,
        &key,
        "sha2",
        "en-US",
        &serde_json::json!({
            "ok": true,
            "lang": "en",
            "display_name": "Pudong, Shanghai",
            "city": { "id": 1796236, "name": "Shanghai", "distance_m": 123 },
            "district": { "id": 1796231, "name": "Pudong", "distance_m": 45 },
        }),
        1,
    )
    .expect("mark ok");

    let got = secondloop_rust::db::read_attachment_place_display_name(&conn, &key, "sha2")
        .expect("read display name");
    assert_eq!(got.as_deref(), Some("Pudong, Shanghai"));
}
