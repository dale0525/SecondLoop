use secondloop_rust::db;

#[test]
fn video_attachment_derivations_roundtrip() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    let conn = db::open(&app_dir).expect("open db");
    let key = [7u8; 32];

    let root = db::insert_attachment(
        &conn,
        &key,
        &app_dir,
        b"manifest",
        "application/x.secondloop.video+json",
    )
    .expect("insert root");
    let segment = db::insert_attachment(&conn, &key, &app_dir, b"segment", "video/mp4")
        .expect("insert segment");
    let poster = db::insert_attachment(&conn, &key, &app_dir, b"poster", "image/jpeg")
        .expect("insert poster");

    db::upsert_attachment_derivation(&conn, &root.sha256, &root.sha256, "root_manifest", 1000)
        .expect("root derivation");
    db::upsert_attachment_derivation(&conn, &root.sha256, &segment.sha256, "proxy_segment", 1001)
        .expect("segment derivation");
    db::upsert_attachment_derivation(&conn, &root.sha256, &poster.sha256, "poster", 1002)
        .expect("poster derivation");

    let derivations =
        db::list_attachment_derivations_by_root(&conn, &root.sha256).expect("list derivations");
    assert_eq!(derivations.len(), 3);
    assert_eq!(derivations[0].child_sha256, root.sha256);
    assert_eq!(derivations[0].role, "root_manifest");
    assert_eq!(derivations[1].child_sha256, segment.sha256);
    assert_eq!(derivations[1].role, "proxy_segment");
    assert_eq!(derivations[2].child_sha256, poster.sha256);
    assert_eq!(derivations[2].role, "poster");

    let roots = db::list_attachment_derivation_roots_by_child(&conn, &segment.sha256)
        .expect("list roots by child");
    assert_eq!(roots, vec![root.sha256.clone()]);

    db::upsert_attachment_derivation(&conn, &root.sha256, &poster.sha256, "poster", 999)
        .expect("idempotent derivation");
    let derivations_after = db::list_attachment_derivations_by_root(&conn, &root.sha256)
        .expect("list derivations after");
    assert_eq!(derivations_after.len(), 3);
}
