use std::fs;

use secondloop_rust::db;

#[test]
fn attachments_roundtrip_encrypts_and_restores_bytes() {
    let tmp = tempfile::tempdir().expect("tempdir");
    let app_dir = tmp.path();
    let conn = db::open(app_dir).expect("open db");

    let key = [7u8; 32];
    let bytes = vec![0x89, 0x50, 0x4e, 0x47, 1, 2, 3, 4];

    let meta = db::insert_attachment(&conn, &key, app_dir, &bytes, "image/png")
        .expect("insert attachment");

    let count: i64 = conn
        .query_row("SELECT COUNT(*) FROM attachments", [], |row| row.get(0))
        .expect("count attachments");
    assert_eq!(count, 1);

    assert_eq!(meta.mime_type, "image/png");
    assert_eq!(meta.byte_len, bytes.len() as i64);

    let encrypted_blob = fs::read(app_dir.join(&meta.path)).expect("read attachment file");
    assert_ne!(encrypted_blob, bytes);

    let roundtrip = db::read_attachment_bytes(&conn, &key, app_dir, &meta.sha256)
        .expect("read attachment bytes");
    assert_eq!(roundtrip, bytes);
}
