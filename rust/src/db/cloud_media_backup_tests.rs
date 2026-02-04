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
