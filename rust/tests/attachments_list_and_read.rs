use secondloop_rust::db;

#[test]
fn attachments_list_and_read_roundtrip() {
    let tmp = tempfile::tempdir().expect("tempdir");
    let app_dir = tmp.path();
    let conn = db::open(app_dir).expect("open db");

    let key = [7u8; 32];
    let conversation =
        db::get_or_create_loop_home_conversation(&conn, &key).expect("get loop home conversation");
    let message =
        db::insert_message(&conn, &key, &conversation.id, "user", "hello").expect("insert message");

    let bytes1 = vec![0x89, 0x50, 0x4e, 0x47, 1, 2, 3, 4];
    let bytes2 = vec![0x89, 0x50, 0x4e, 0x47, 9, 8, 7, 6];
    let meta1 =
        db::insert_attachment(&conn, &key, app_dir, &bytes1, "image/png").expect("insert a1");
    let meta2 =
        db::insert_attachment(&conn, &key, app_dir, &bytes2, "image/png").expect("insert a2");

    db::link_attachment_to_message(&conn, &key, &message.id, &meta1.sha256)
        .expect("link a1 -> message");
    db::link_attachment_to_message(&conn, &key, &message.id, &meta2.sha256)
        .expect("link a2 -> message");

    let listed = db::list_message_attachments(&conn, &key, &message.id).expect("list attachments");
    assert_eq!(listed.len(), 2);

    let mut expected = vec![
        (meta1.created_at_ms, meta1.sha256.clone()),
        (meta2.created_at_ms, meta2.sha256.clone()),
    ];
    expected.sort();
    let listed_ids: Vec<String> = listed.into_iter().map(|a| a.sha256).collect();
    let expected_ids: Vec<String> = expected.into_iter().map(|(_, sha)| sha).collect();
    assert_eq!(listed_ids, expected_ids);

    let roundtrip = db::read_attachment_bytes(&conn, &key, app_dir, &meta1.sha256)
        .expect("read attachment bytes");
    assert_eq!(roundtrip, bytes1);
}
