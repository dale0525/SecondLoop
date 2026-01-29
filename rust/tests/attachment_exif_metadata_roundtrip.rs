use secondloop_rust::db;

#[test]
fn attachment_exif_metadata_roundtrip_persists_and_reads_back() {
    let tmp = tempfile::tempdir().expect("tempdir");
    let app_dir = tmp.path();
    let conn = db::open(app_dir).expect("open db");

    let key = [7u8; 32];
    let bytes = vec![0x89, 0x50, 0x4e, 0x47, 1, 2, 3, 4];
    let attachment = db::insert_attachment(&conn, &key, app_dir, &bytes, "image/png")
        .expect("insert attachment");

    db::upsert_attachment_exif_metadata(
        &conn,
        &key,
        &attachment.sha256,
        Some(1_706_000_000_000),
        Some(37.5),
        Some(-122.4),
    )
    .expect("upsert exif metadata");

    let meta = db::read_attachment_exif_metadata(&conn, &key, &attachment.sha256)
        .expect("read exif metadata")
        .expect("has metadata");

    assert_eq!(meta.captured_at_ms, Some(1_706_000_000_000));
    assert_eq!(meta.latitude, Some(37.5));
    assert_eq!(meta.longitude, Some(-122.4));
}
