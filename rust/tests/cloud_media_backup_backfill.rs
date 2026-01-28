use secondloop_rust::db;

#[test]
fn cloud_media_backup_backfill_enqueues_images_only() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    let conn = db::open(&app_dir).expect("open db");

    let key = [1u8; 32];
    let img = db::insert_attachment(&conn, &key, &app_dir, b"img", "image/png").expect("img");
    let doc = db::insert_attachment(&conn, &key, &app_dir, b"doc", "application/pdf").expect("doc");

    let affected =
        db::backfill_cloud_media_backup_images(&conn, "original", 1234).expect("backfill");
    assert!(affected > 0);

    let due = db::list_due_cloud_media_backups(&conn, 1234, 100).expect("list due");
    assert_eq!(due.len(), 1);
    assert_eq!(due[0].attachment_sha256, img.sha256);

    // Ensure the non-image attachment was not enqueued.
    assert_ne!(due[0].attachment_sha256, doc.sha256);
}
