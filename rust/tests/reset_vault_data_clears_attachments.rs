use std::path::Path;

use secondloop_rust::auth;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::db;

#[test]
fn reset_vault_data_deletes_attachments_and_exif() {
    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(Path::new(&app_dir), "pw", KdfParams::for_test())
        .expect("init master password");
    let conn = db::open(&app_dir).expect("open db");

    let attachment = db::insert_attachment(
        &conn,
        &key,
        &app_dir,
        b"not a real image, just bytes",
        "image/png",
    )
    .expect("insert attachment");
    db::upsert_attachment_exif_metadata(
        &conn,
        &key,
        &attachment.sha256,
        Some(123),
        Some(1.23),
        Some(4.56),
    )
    .expect("upsert exif");

    let attachments_dir = app_dir.join("attachments");
    let attachment_path = app_dir.join(format!("attachments/{}.bin", attachment.sha256));
    assert!(attachments_dir.exists(), "attachments dir should exist");
    assert!(attachment_path.exists(), "attachment file should exist");

    let attachments_before: i64 = conn
        .query_row("SELECT count(*) FROM attachments", [], |row| row.get(0))
        .expect("count attachments before reset");
    assert_eq!(attachments_before, 1);
    let exif_before: i64 = conn
        .query_row("SELECT count(*) FROM attachment_exif", [], |row| row.get(0))
        .expect("count exif before reset");
    assert_eq!(exif_before, 1);

    db::reset_vault_data_preserving_llm_profiles(&conn).expect("reset vault data");

    let attachments_after: i64 = conn
        .query_row("SELECT count(*) FROM attachments", [], |row| row.get(0))
        .expect("count attachments after reset");
    assert_eq!(attachments_after, 0);
    let exif_after: i64 = conn
        .query_row("SELECT count(*) FROM attachment_exif", [], |row| row.get(0))
        .expect("count exif after reset");
    assert_eq!(exif_after, 0);

    assert!(
        !attachments_dir.exists(),
        "attachments dir should be deleted after reset"
    );
    assert!(
        !attachment_path.exists(),
        "attachment file should be deleted after reset"
    );
}
