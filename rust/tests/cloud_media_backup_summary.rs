use secondloop_rust::db;

#[test]
fn cloud_media_backup_summary_reports_counts_and_timestamps() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    let conn = db::open(&app_dir).expect("open db");

    let key = [2u8; 32];
    let attachment =
        db::insert_attachment(&conn, &key, &app_dir, b"img", "image/png").expect("img");

    db::enqueue_cloud_media_backup(&conn, &attachment.sha256, "original", 1000).expect("enqueue");
    let s = db::cloud_media_backup_summary(&conn).expect("summary");
    assert_eq!(s.pending, 1);
    assert_eq!(s.failed, 0);
    assert_eq!(s.uploaded, 0);
    assert!(s.last_uploaded_at_ms.is_none());
    assert!(s.last_error.is_none());

    db::mark_cloud_media_backup_failed(&conn, &attachment.sha256, 1, 2000, "boom", 1000)
        .expect("failed");
    let s = db::cloud_media_backup_summary(&conn).expect("summary failed");
    assert_eq!(s.pending, 0);
    assert_eq!(s.failed, 1);
    assert_eq!(s.uploaded, 0);
    assert_eq!(s.last_error.as_deref(), Some("boom"));
    assert_eq!(s.last_error_at_ms, Some(1000));

    db::mark_cloud_media_backup_uploaded(&conn, &attachment.sha256, 3000).expect("uploaded");
    let s = db::cloud_media_backup_summary(&conn).expect("summary uploaded");
    assert_eq!(s.pending, 0);
    assert_eq!(s.failed, 0);
    assert_eq!(s.uploaded, 1);
    assert_eq!(s.last_uploaded_at_ms, Some(3000));
    assert!(s.last_error.is_none());
}
