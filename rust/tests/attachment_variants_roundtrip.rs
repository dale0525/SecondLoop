use secondloop_rust::db;

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
