use std::fs;

use secondloop_rust::{api::core, crypto, db};

#[test]
fn reset_rejects_cross_table_mixed_deferred_keys() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open db");
    let first_key = [3u8; 32];
    let second_key = [4u8; 32];
    let conversation =
        db::create_conversation(&conn, &first_key, "first").expect("seed conversation");
    db::insert_message(
        &conn,
        &second_key,
        &conversation.id,
        "user",
        "second-key message",
    )
    .expect("seed mixed-key message");
    drop(conn);

    let result = core::db_reset_vault_data_preserving_llm_profiles(
        dir.path().to_string_lossy().into_owned(),
        first_key.to_vec(),
    );

    let error = result.expect_err("mixed table keys should be rejected");
    assert!(
        error.to_string().contains("invalid key"),
        "unexpected error: {error}"
    );
    let conn = db::open(dir.path()).expect("reopen db");
    let count: i64 = conn
        .query_row("SELECT COUNT(*) FROM messages", [], |row| row.get(0))
        .expect("count messages");
    assert_eq!(count, 1);
}

#[test]
fn reset_allows_missing_auth_with_valid_tag_only_deferred_key() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open db");
    let key = [5u8; 32];
    db::upsert_tag(&conn, &key, "Project Alpha").expect("seed tag");
    drop(conn);

    let result = core::db_reset_vault_data_preserving_llm_profiles(
        dir.path().to_string_lossy().into_owned(),
        key.to_vec(),
    );

    assert!(
        result.is_ok(),
        "valid tag-only deferred key should allow reset without auth.json: {result:?}"
    );
}

#[test]
fn reset_allows_missing_auth_with_valid_attachment_only_deferred_key() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open db");
    let key = [6u8; 32];
    db::insert_attachment(&conn, &key, dir.path(), b"attachment bytes", "text/plain")
        .expect("seed attachment");
    conn.execute("DELETE FROM oplog", [])
        .expect("keep this as an attachment-only probe");
    drop(conn);

    let result = core::db_reset_vault_data_preserving_llm_profiles(
        dir.path().to_string_lossy().into_owned(),
        key.to_vec(),
    );

    assert!(
        result.is_ok(),
        "valid attachment-only deferred key should allow reset without auth.json: {result:?}"
    );
}

#[test]
fn reset_allows_missing_auth_with_valid_external_attachment_only_deferred_key() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open_external_readonly_db(dir.path()).expect("open external readonly db");
    let key = [7u8; 32];
    let sha256 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    let stored_path = format!("external_readonly/storage/attachments/{sha256}.bin");
    let full_path = dir.path().join(&stored_path);
    fs::create_dir_all(full_path.parent().expect("external attachment parent"))
        .expect("create external attachment dir");
    let aad = format!("external_attachment.bytes:{sha256}");
    let blob = crypto::encrypt_bytes(&key, b"external attachment", aad.as_bytes())
        .expect("encrypt external attachment");
    fs::write(&full_path, blob).expect("write external attachment blob");
    conn.execute(
        r#"INSERT INTO external_attachments(
             sha256, stored_path, size_bytes, mime_type, ref_count, created_at_ms
           ) VALUES (?1, ?2, 19, 'text/plain', 1, 1)"#,
        rusqlite::params![sha256, stored_path],
    )
    .expect("seed external attachment row");
    drop(conn);

    let result = core::db_reset_vault_data_preserving_llm_profiles(
        dir.path().to_string_lossy().into_owned(),
        key.to_vec(),
    );

    assert!(
        result.is_ok(),
        "valid external attachment-only deferred key should allow reset without auth.json: {result:?}"
    );
}

#[test]
fn reset_rejects_unverifiable_deferred_key_without_reporting_invalid_key() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open db");
    let corrupt_blob = vec![0xA5u8; 48];
    conn.execute(
        r#"INSERT INTO conversations(id, title, created_at, updated_at)
           VALUES ('corrupt-conversation', ?1, 1, 1)"#,
        rusqlite::params![corrupt_blob],
    )
    .expect("seed corrupt encrypted row");
    drop(conn);

    let result = core::db_reset_vault_data_preserving_llm_profiles(
        dir.path().to_string_lossy().into_owned(),
        vec![9u8; 32],
    );

    let error = result.expect_err("unverifiable deferred key should be rejected");
    assert!(
        error
            .to_string()
            .contains("unable to validate key against existing vault data"),
        "unexpected error: {error}"
    );
    assert!(
        !error.to_string().contains("invalid key"),
        "corrupt data should not be reported as a definitively invalid key: {error}"
    );
}

#[test]
fn reset_allows_missing_auth_with_valid_oplog_only_deferred_key() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open db");
    let key = [8u8; 32];
    db::create_conversation(&conn, &key, "oplog only").expect("seed conversation and oplog");
    conn.execute("DELETE FROM conversations", [])
        .expect("keep this as an oplog-only probe");
    drop(conn);

    let result = core::db_reset_vault_data_preserving_llm_profiles(
        dir.path().to_string_lossy().into_owned(),
        key.to_vec(),
    );

    assert!(
        result.is_ok(),
        "valid oplog-only deferred key should allow reset without auth.json: {result:?}"
    );
}
