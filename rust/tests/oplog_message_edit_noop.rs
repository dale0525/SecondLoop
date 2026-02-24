use secondloop_rust::auth;
use secondloop_rust::crypto::{decrypt_bytes, KdfParams};
use secondloop_rust::db;

fn count_oplog_rows(conn: &rusqlite::Connection) -> i64 {
    conn.query_row(r#"SELECT COUNT(*) FROM oplog"#, [], |row| row.get(0))
        .expect("count oplog")
}

fn latest_op_type(conn: &rusqlite::Connection, key: &[u8; 32]) -> String {
    let (op_id, ciphertext): (String, Vec<u8>) = conn
        .query_row(
            r#"SELECT op_id, op_json FROM oplog ORDER BY seq DESC LIMIT 1"#,
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("select latest oplog row");

    let plaintext = decrypt_bytes(
        key,
        &ciphertext,
        format!("oplog.op_json:{op_id}").as_bytes(),
    )
    .expect("decrypt latest op");
    let op: serde_json::Value = serde_json::from_slice(&plaintext).expect("parse op json");
    op.get("type")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .to_string()
}

#[test]
fn edit_message_with_same_content_does_not_append_oplog_entry() {
    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("create convo");
    let message =
        db::insert_message(&conn, &key, &conversation.id, "user", "same").expect("insert message");

    let before_count = count_oplog_rows(&conn);

    db::edit_message(&conn, &key, &message.id, "same").expect("edit message no-op");

    let after_count = count_oplog_rows(&conn);
    assert_eq!(after_count, before_count, "no-op edit should not append op");
}

#[test]
fn edit_message_with_new_content_appends_message_set_oplog_entry() {
    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test())
        .expect("init master password");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("create convo");
    let message = db::insert_message(&conn, &key, &conversation.id, "user", "before")
        .expect("insert message");

    let before_count = count_oplog_rows(&conn);

    db::edit_message(&conn, &key, &message.id, "after").expect("edit message changed");

    let after_count = count_oplog_rows(&conn);
    assert_eq!(
        after_count,
        before_count + 1,
        "changed edit should append op"
    );
    assert_eq!(latest_op_type(&conn, &key), "message.set.v2");
}
