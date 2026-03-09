use std::fmt::Write;

use rusqlite::params;

use crate::api::knowledge::db_request_knowledge_rebuild;
use crate::crypto::encrypt_bytes;
use crate::db;
use crate::knowledge::read_knowledge_index_status;

fn encode_blob_hex(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        write!(&mut out, "{byte:02x}").expect("write hex");
    }
    out
}

#[test]
fn request_knowledge_rebuild_succeeds_even_if_initial_job_batch_fails() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().to_path_buf();
    let app_dir_string = app_dir.to_string_lossy().into_owned();
    let conn = db::open(&app_dir).expect("open");
    let key = [31u8; 32];

    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    let msg = db::insert_message(
        &conn,
        &key,
        &conv.id,
        "user",
        "job failure after rebuild request",
    )
    .expect("message");
    conn.execute(
        "UPDATE messages SET is_memory = 1, needs_embedding = 1 WHERE id = ?1",
        params![msg.id],
    )
    .expect("mark memory");

    let document_id = format!("message:{}", msg.id);
    let corrupt_blob = encrypt_bytes(
        &key,
        &[0xff, 0xfe],
        format!("knowledge.document.raw:{document_id}").as_bytes(),
    )
    .expect("encrypt corrupt raw text");
    let corrupt_blob_hex = encode_blob_hex(&corrupt_blob);
    conn.execute_batch(&format!(
        r#"
CREATE TRIGGER corrupt_knowledge_document_after_insert
AFTER INSERT ON knowledge_documents
WHEN NEW.document_id = '{document_id}'
BEGIN
  UPDATE knowledge_documents
  SET raw_text = X'{corrupt_blob_hex}'
  WHERE document_id = NEW.document_id;
END;
"#
    ))
    .expect("create corruption trigger");

    db_request_knowledge_rebuild(app_dir_string, key.to_vec()).expect("request rebuild");

    let status = read_knowledge_index_status(&conn, &key).expect("status");
    assert_eq!(status.status, "failed");
    assert!(status
        .last_error
        .as_deref()
        .is_some_and(|value| value.contains("utf-8")));
}
