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
    enqueue_cloud_media_backup(
        &conn,
        &attachment.sha256,
        "original",
        now_ms,
        Some("scope-a"),
    )
    .expect("enqueue");

    let due = list_due_cloud_media_backups(&conn, now_ms, 10, Some("scope-a")).expect("list due");
    assert_eq!(due.len(), 1);
    assert_eq!(due[0].attachment_sha256, attachment.sha256);
    assert_eq!(due[0].byte_len, bytes.len() as i64);
}

#[test]
fn backfill_cloud_media_backup_skips_attachments_without_local_bytes() {
    let dir = tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let conn = open(&app_dir).expect("open");

    let key = [4u8; 32];
    let local = insert_attachment(&conn, &key, &app_dir, b"local", "image/png")
        .expect("insert local attachment");

    conn.execute(
        r#"INSERT INTO attachments(sha256, mime_type, path, byte_len, created_at)
           VALUES (?1, ?2, ?3, ?4, ?5)"#,
        params![
            "remote-only-sha",
            "image/png",
            "attachments/remote-only-sha.bin",
            42i64,
            999i64
        ],
    )
    .expect("insert remote-only attachment metadata");

    let affected = backfill_cloud_media_backup_images(&conn, "original", 1_234, Some("scope-a"))
        .expect("backfill");
    assert_eq!(affected, 1, "only local attachments should be enqueued");

    let due = list_due_cloud_media_backups(&conn, 1_234, 10, Some("scope-a")).expect("list due");
    assert_eq!(due.len(), 1);
    assert_eq!(due[0].attachment_sha256, local.sha256);
}

#[test]
fn cloud_media_backup_prunes_rows_without_local_bytes() {
    let dir = tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let conn = open(&app_dir).expect("open");

    conn.execute(
        r#"INSERT INTO attachments(sha256, mime_type, path, byte_len, created_at)
           VALUES (?1, ?2, ?3, ?4, ?5)"#,
        params![
            "remote-only-sha",
            "image/png",
            "attachments/remote-only-sha.bin",
            42i64,
            999i64
        ],
    )
    .expect("insert remote-only attachment metadata");

    enqueue_cloud_media_backup(&conn, "remote-only-sha", "original", 1_000, Some("scope-a"))
        .expect("enqueue backup");
    mark_cloud_media_backup_failed(
        &conn,
        "remote-only-sha",
        1,
        1_000,
        "missing_local_attachment_bytes:remote-only-sha",
        1_000,
        Some("scope-a"),
    )
    .expect("mark failed");

    let due = list_due_cloud_media_backups(&conn, 1_000, 10, Some("scope-a")).expect("list due");
    assert!(due.is_empty(), "missing local files should not stay due");

    let summary = cloud_media_backup_summary(&conn, Some("scope-a")).expect("summary");
    assert_eq!(summary.pending, 0);
    assert_eq!(summary.failed, 0);
    assert_eq!(summary.uploaded, 0);

    let remaining: i64 = conn
        .query_row(r#"SELECT COUNT(*) FROM cloud_media_backup"#, [], |row| {
            row.get(0)
        })
        .expect("count backup rows");
    assert_eq!(remaining, 0, "stale rows should be pruned");
}

#[test]
fn purge_message_attachments_cleans_enrichment_and_backup_jobs() {
    let dir = tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let conn = open(&app_dir).expect("open");
    let key = [9u8; 32];

    let conversation = get_or_create_loop_home_conversation(&conn, &key).expect("conversation");
    let message = insert_message(&conn, &key, &conversation.id, "user", "pdf").expect("message");
    let attachment = insert_attachment(&conn, &key, &app_dir, b"%PDF-1.7", "application/pdf")
        .expect("insert attachment");
    link_attachment_to_message(&conn, &key, &message.id, &attachment.sha256).expect("link");

    let now_ms = 1_000i64;
    enqueue_attachment_annotation(&conn, &attachment.sha256, "und", now_ms)
        .expect("enqueue annotation");
    enqueue_attachment_place(&conn, &attachment.sha256, "und", now_ms).expect("enqueue place");
    enqueue_cloud_media_backup(
        &conn,
        &attachment.sha256,
        "original",
        now_ms,
        Some("scope-a"),
    )
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
fn cloud_media_backup_scope_filters_due_rows_and_summary() {
    let dir = tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let conn = open(&app_dir).expect("open");
    let key = [8u8; 32];

    let attachment_a =
        insert_attachment(&conn, &key, &app_dir, b"a", "image/png").expect("insert attachment a");
    let attachment_b =
        insert_attachment(&conn, &key, &app_dir, b"b", "image/png").expect("insert attachment b");

    enqueue_cloud_media_backup(
        &conn,
        &attachment_a.sha256,
        "original",
        1_000,
        Some("scope-a"),
    )
    .expect("enqueue scope a");
    enqueue_cloud_media_backup(
        &conn,
        &attachment_b.sha256,
        "original",
        1_000,
        Some("scope-b"),
    )
    .expect("enqueue scope b");

    let due_a = list_due_cloud_media_backups(&conn, 1_000, 10, Some("scope-a")).expect("due a");
    let due_b = list_due_cloud_media_backups(&conn, 1_000, 10, Some("scope-b")).expect("due b");
    assert_eq!(due_a.len(), 1);
    assert_eq!(due_a[0].attachment_sha256, attachment_a.sha256);
    assert_eq!(due_b.len(), 1);
    assert_eq!(due_b[0].attachment_sha256, attachment_b.sha256);

    let summary_a = cloud_media_backup_summary(&conn, Some("scope-a")).expect("summary a");
    let summary_b = cloud_media_backup_summary(&conn, Some("scope-b")).expect("summary b");
    assert_eq!(summary_a.pending, 1);
    assert_eq!(summary_b.pending, 1);
}

#[test]
fn cloud_media_backup_scoped_reads_ignore_legacy_unscoped_rows() {
    let dir = tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let conn = open(&app_dir).expect("open");
    let key = [6u8; 32];

    let attachment =
        insert_attachment(&conn, &key, &app_dir, b"legacy", "image/png").expect("insert");

    conn.execute(
        r#"INSERT INTO cloud_media_backup(
               scope_id,
               attachment_sha256,
               desired_variant,
               status,
               attempts,
               next_retry_at,
               last_error,
               updated_at
           ) VALUES ('', ?1, 'original', 'pending', 0, NULL, NULL, 1234)"#,
        params![attachment.sha256.as_str()],
    )
    .expect("seed legacy row");

    let due = list_due_cloud_media_backups(&conn, 1_500, 10, Some("scope-a")).expect("list scoped");
    assert!(
        due.is_empty(),
        "legacy unscoped rows must not leak into scoped queues"
    );

    let summary = cloud_media_backup_summary(&conn, Some("scope-a")).expect("summary");
    assert_eq!(summary.pending, 0);

    let scope_id: String = conn
        .query_row(
            r#"SELECT scope_id
               FROM cloud_media_backup
               WHERE attachment_sha256 = ?1"#,
            params![attachment.sha256.as_str()],
            |row| row.get(0),
        )
        .expect("load legacy scope");
    assert_eq!(scope_id, "");
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
