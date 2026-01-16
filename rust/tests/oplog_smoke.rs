use secondloop_rust::auth;
use secondloop_rust::crypto::{decrypt_bytes, KdfParams};
use secondloop_rust::db;

#[test]
fn oplog_records_local_writes_and_is_encrypted_at_rest() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");

    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("create conversation");
    let message =
        db::insert_message(&conn, &key, &conversation.id, "user", "hello").expect("insert message");

    let device_id: String = conn
        .query_row(
            r#"SELECT value FROM kv WHERE key = 'device_id'"#,
            [],
            |row| row.get(0),
        )
        .expect("device_id exists");

    let mut stmt = conn
        .prepare(r#"SELECT op_id, device_id, seq, op_json FROM oplog ORDER BY seq ASC"#)
        .expect("prepare oplog query");
    let mut rows = stmt.query([]).expect("query oplog");

    let mut seen_message_op = false;
    let mut seen_conversation_op = false;

    while let Some(row) = rows.next().expect("next row") {
        let op_id: String = row.get(0).expect("op_id");
        let op_device_id: String = row.get(1).expect("device_id");
        let seq: i64 = row.get(2).expect("seq");
        let op_json_blob: Vec<u8> = row.get(3).expect("op_json");

        assert_eq!(op_device_id, device_id);
        assert!(seq >= 1);

        let plaintext = decrypt_bytes(
            &key,
            &op_json_blob,
            format!("oplog.op_json:{op_id}").as_bytes(),
        )
        .expect("decrypt oplog payload");

        let value: serde_json::Value =
            serde_json::from_slice(&plaintext).expect("oplog json parses");

        assert_eq!(value["op_id"].as_str(), Some(op_id.as_str()));
        assert_eq!(value["device_id"].as_str(), Some(device_id.as_str()));
        assert_eq!(value["seq"].as_i64(), Some(seq));

        match value["type"].as_str().unwrap_or_default() {
            "conversation.upsert.v1" => {
                assert_eq!(
                    value["payload"]["conversation_id"].as_str(),
                    Some(conversation.id.as_str())
                );
                assert_eq!(value["payload"]["title"].as_str(), Some("Inbox"));
                seen_conversation_op = true;
            }
            "message.insert.v1" => {
                assert_eq!(
                    value["payload"]["message_id"].as_str(),
                    Some(message.id.as_str())
                );
                assert_eq!(
                    value["payload"]["conversation_id"].as_str(),
                    Some(conversation.id.as_str())
                );
                assert_eq!(value["payload"]["role"].as_str(), Some("user"));
                assert_eq!(value["payload"]["content"].as_str(), Some("hello"));
                seen_message_op = true;
            }
            other => panic!("unexpected oplog type: {other}"),
        }
    }

    assert!(seen_conversation_op, "expected conversation oplog entry");
    assert!(seen_message_op, "expected message oplog entry");

    // Ensure the stored payload is not just raw JSON in plaintext.
    let stored: Vec<u8> = conn
        .query_row(
            r#"SELECT op_json FROM oplog WHERE op_id = (SELECT op_id FROM oplog LIMIT 1)"#,
            [],
            |row| row.get(0),
        )
        .expect("select stored oplog payload");
    assert!(!stored
        .windows(b"\"hello\"".len())
        .any(|w| w == b"\"hello\""));
    assert!(!stored
        .windows(b"\"Inbox\"".len())
        .any(|w| w == b"\"Inbox\""));
}
