use secondloop_rust::db;

#[test]
fn cloud_media_backup_roundtrip_tracks_status_and_retry() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    let conn = db::open(&app_dir).expect("open db");

    let key = [3u8; 32];
    let attachment = db::insert_attachment(&conn, &key, &app_dir, b"original-bytes", "image/png")
        .expect("insert attachment");

    db::enqueue_cloud_media_backup(&conn, &attachment.sha256, "webp_q85", 1234).expect("enqueue");

    let due = db::list_due_cloud_media_backups(&conn, 1234, 100).expect("list due");
    assert_eq!(due.len(), 1);
    assert_eq!(due[0].attachment_sha256, attachment.sha256);
    assert_eq!(due[0].status, "pending");
    assert_eq!(due[0].attempts, 0);

    db::mark_cloud_media_backup_failed(&conn, &attachment.sha256, 1, 2000, "upload_failed", 1234)
        .expect("mark failed");

    let due = db::list_due_cloud_media_backups(&conn, 1500, 100).expect("list due after failed");
    assert!(due.is_empty(), "should not be due before next_retry_at");

    let due = db::list_due_cloud_media_backups(&conn, 2000, 100).expect("list due at retry time");
    assert_eq!(due.len(), 1);
    assert_eq!(due[0].attempts, 1);
    assert_eq!(due[0].status, "failed");

    db::mark_cloud_media_backup_uploaded(&conn, &attachment.sha256, 2222).expect("mark uploaded");
    let due = db::list_due_cloud_media_backups(&conn, 9999, 100).expect("list due after uploaded");
    assert!(due.is_empty());
}
