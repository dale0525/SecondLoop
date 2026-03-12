use secondloop_rust::db;

#[test]
fn purge_message_attachments_cascades_video_derivations() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    let conn = db::open(&app_dir).expect("open db");
    let key = [9u8; 32];

    let conversation = db::get_or_create_loop_home_conversation(&conn, &key).expect("conversation");
    let message =
        db::insert_message(&conn, &key, &conversation.id, "user", "video").expect("message");

    let manifest = db::insert_attachment(
        &conn,
        &key,
        &app_dir,
        b"manifest",
        "application/x.secondloop.video+json",
    )
    .expect("manifest");
    let segment =
        db::insert_attachment(&conn, &key, &app_dir, b"segment", "video/mp4").expect("segment");
    let poster =
        db::insert_attachment(&conn, &key, &app_dir, b"poster", "image/jpeg").expect("poster");

    db::link_attachment_to_message(&conn, &key, &message.id, &manifest.sha256).expect("link");
    db::upsert_attachment_derivation(
        &conn,
        &manifest.sha256,
        &manifest.sha256,
        "root_manifest",
        1000,
    )
    .expect("root derivation");
    db::upsert_attachment_derivation(
        &conn,
        &manifest.sha256,
        &segment.sha256,
        "proxy_segment",
        1001,
    )
    .expect("segment derivation");
    db::upsert_attachment_derivation(&conn, &manifest.sha256, &poster.sha256, "poster", 1002)
        .expect("poster derivation");

    let deleted = db::purge_message_attachments(&conn, &key, &app_dir, &message.id).expect("purge");
    assert_eq!(deleted, 3);

    for sha in [&manifest.sha256, &segment.sha256, &poster.sha256] {
        let count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM attachments WHERE sha256 = ?1",
                rusqlite::params![sha],
                |row| row.get(0),
            )
            .expect("count attachment");
        assert_eq!(count, 0, "attachment should be deleted: {sha}");
    }

    let derivation_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM attachment_derivations WHERE root_sha256 = ?1 OR child_sha256 = ?1",
            rusqlite::params![manifest.sha256.as_str()],
            |row| row.get(0),
        )
        .expect("count derivations");
    assert_eq!(derivation_count, 0);
}
