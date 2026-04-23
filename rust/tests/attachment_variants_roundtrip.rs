use secondloop_rust::db;
use std::fs;

#[test]
fn attachment_variants_roundtrip_encrypts_and_restores_bytes() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    let conn = db::open(&app_dir).expect("open db");

    let key = [7u8; 32];
    let attachment = db::insert_attachment(&conn, &key, &app_dir, b"original-bytes", "image/png")
        .expect("insert attachment");

    let variant = db::upsert_attachment_variant(
        &conn,
        &key,
        &app_dir,
        &attachment.sha256,
        "webp_q85",
        b"variant-bytes",
        "image/webp",
    )
    .expect("insert variant");

    assert_eq!(variant.attachment_sha256, attachment.sha256);
    assert_eq!(variant.variant, "webp_q85");
    assert_eq!(variant.mime_type, "image/webp");
    assert_eq!(variant.byte_len, 13);

    let read =
        db::read_attachment_variant_bytes(&conn, &key, &app_dir, &attachment.sha256, "webp_q85")
            .expect("read variant");
    assert_eq!(read, b"variant-bytes");
}

#[test]
fn read_attachment_variant_bytes_returns_variant_not_found_when_local_file_is_missing() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    let conn = db::open(&app_dir).expect("open db");

    let key = [7u8; 32];
    let attachment = db::insert_attachment(&conn, &key, &app_dir, b"original-bytes", "image/png")
        .expect("insert attachment");

    let variant = db::upsert_attachment_variant(
        &conn,
        &key,
        &app_dir,
        &attachment.sha256,
        "webp_q85",
        b"variant-bytes",
        "image/webp",
    )
    .expect("insert variant");

    fs::remove_file(app_dir.join(&variant.path)).expect("remove variant file");

    let err =
        db::read_attachment_variant_bytes(&conn, &key, &app_dir, &attachment.sha256, "webp_q85")
            .expect_err("missing local variant file should return an error");
    assert!(
        err.to_string().contains("attachment variant not found"),
        "unexpected error: {err:#}"
    );
    assert!(
        err.downcast_ref::<std::io::Error>()
            .is_some_and(|io| io.kind() == std::io::ErrorKind::NotFound),
        "missing local variant file should preserve io::ErrorKind::NotFound: {err:#}"
    );
}
