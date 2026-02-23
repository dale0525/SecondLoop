use tempfile::tempdir;

use super::*;

#[test]
fn list_due_cloud_media_backups_includes_byte_len() {
    let dir = tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");

    let key = [7u8; 32];
    let bytes = vec![1u8, 2, 3, 4, 5, 6, 7];
    let attachment =
        insert_attachment(&conn, &key, dir.path(), &bytes, "image/png").expect("insert attachment");

    let now_ms = 1_000i64;
    enqueue_cloud_media_backup(&conn, &attachment.sha256, "original", now_ms).expect("enqueue");

    let due = list_due_cloud_media_backups(&conn, now_ms, 10).expect("list due");
    assert_eq!(due.len(), 1);
    assert_eq!(due[0].attachment_sha256, attachment.sha256);
    assert_eq!(due[0].byte_len, bytes.len() as i64);
}

#[test]
fn purge_message_attachments_cleans_enrichment_and_backup_jobs() {
    let dir = tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let conn = open(&app_dir).expect("open");
    let key = [9u8; 32];

    let conversation = get_or_create_main_stream_conversation(&conn, &key).expect("conversation");
    let message = insert_message(&conn, &key, &conversation.id, "user", "pdf").expect("message");
    let attachment = insert_attachment(&conn, &key, &app_dir, b"%PDF-1.7", "application/pdf")
        .expect("insert attachment");
    link_attachment_to_message(&conn, &key, &message.id, &attachment.sha256).expect("link");

    let now_ms = 1_000i64;
    enqueue_attachment_annotation(&conn, &attachment.sha256, "und", now_ms)
        .expect("enqueue annotation");
    enqueue_attachment_place(&conn, &attachment.sha256, "und", now_ms).expect("enqueue place");
    enqueue_cloud_media_backup(&conn, &attachment.sha256, "original", now_ms)
        .expect("enqueue backup");

    let deleted = purge_message_attachments(&conn, &key, &app_dir, &message.id).expect("purge");
    assert_eq!(deleted, 1);

    let attachment_count: i64 = conn
        .query_row(
            r#"SELECT COUNT(*) FROM attachments WHERE sha256 = ?1"#,
            [attachment.sha256.as_str()],
            |row| row.get(0),
        )
        .expect("count attachments");
    assert_eq!(attachment_count, 0);

    for table in [
        "message_attachments",
        "attachment_annotations",
        "attachment_places",
        "cloud_media_backup",
    ] {
        let sql = format!("SELECT COUNT(*) FROM {table} WHERE attachment_sha256 = ?1");
        let count: i64 = conn
            .query_row(&sql, [attachment.sha256.as_str()], |row| row.get(0))
            .expect("count rows");
        assert_eq!(count, 0, "expected {table} rows to be removed");
    }
}

#[test]
fn mark_attachment_annotation_ok_is_noop_when_attachment_missing() {
    let dir = tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let conn = open(&app_dir).expect("open");
    let key = [3u8; 32];

    mark_attachment_annotation_ok(
        &conn,
        &key,
        "missing-sha",
        "und",
        "document_extract.v1",
        &serde_json::json!({
            "schema": "secondloop.document_extract.v1",
            "needs_ocr": true
        }),
        1234,
    )
    .expect("no-op when missing");

    let count: i64 = conn
        .query_row(
            r#"SELECT COUNT(*) FROM attachment_annotations WHERE attachment_sha256 = 'missing-sha'"#,
            [],
            |row| row.get(0),
        )
        .expect("count annotations");
    assert_eq!(count, 0);
}
