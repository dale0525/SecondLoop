use rusqlite::params;
use secondloop_rust::auth;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::db;

#[test]
fn attachment_chunk_index_builds_offsets_from_annotation_payload() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let attachment = db::insert_attachment(&conn, &key, &app_dir, b"attachment body", "text/plain")
        .expect("insert attachment");

    let extracted_text = [
        "alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima",
        "mike november oscar papa quebec romeo sierra tango uniform victor whiskey",
        "xray yankee zulu",
    ]
    .join("\n");

    let payload = serde_json::json!({
        "extracted_text_full": extracted_text,
    });

    db::mark_attachment_annotation_ok(
        &conn,
        &key,
        &attachment.sha256,
        "en",
        "test-model",
        &payload,
        1_700_000_000_000,
    )
    .expect("mark annotation");

    let processed = db::process_attachment_text_chunks(&conn, &key, 16).expect("process chunks");
    assert_eq!(processed, 1);

    let chunk_count: i64 = conn
        .query_row(
            r#"SELECT COUNT(*) FROM attachment_text_chunks WHERE attachment_sha256 = ?1"#,
            params![attachment.sha256],
            |row| row.get(0),
        )
        .expect("count chunks");
    assert!(chunk_count > 0);

    let (min_start, max_end, min_len): (i64, i64, i64) = conn
        .query_row(
            r#"
SELECT MIN(start_offset), MAX(end_offset), MIN(text_len)
FROM attachment_text_chunks
WHERE attachment_sha256 = ?1
"#,
            params![attachment.sha256],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("chunk offsets");

    assert_eq!(min_start, 0);
    assert!(max_end > min_start);
    assert!(min_len > 0);

    let processed_again =
        db::process_attachment_text_chunks(&conn, &key, 16).expect("process chunks again");
    assert_eq!(processed_again, 0);
}
