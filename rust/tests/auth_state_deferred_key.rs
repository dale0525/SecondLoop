use std::fs;

use secondloop_rust::{api::core, crypto, db};

const OVERSIZED_DB_PROBE_BYTES: usize = 17 * 1024 * 1024;

fn insert_attachment_row(
    conn: &rusqlite::Connection,
    sha256: &str,
    stored_path: &str,
    byte_len: i64,
    created_at: i64,
) {
    conn.execute(
        r#"INSERT INTO attachments(sha256, mime_type, path, byte_len, created_at)
           VALUES (?1, 'application/octet-stream', ?2, ?3, ?4)"#,
        rusqlite::params![sha256, stored_path, byte_len, created_at],
    )
    .expect("insert attachment row");
}

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
        error
            .to_string()
            .contains("unable to validate key against existing vault data"),
        "unexpected error: {error}"
    );
    let conn = db::open(dir.path()).expect("reopen db");
    let count: i64 = conn
        .query_row("SELECT COUNT(*) FROM messages", [], |row| row.get(0))
        .expect("count messages");
    assert_eq!(count, 1);
}

#[test]
fn reset_rejects_same_table_mixed_deferred_key_after_probe_window() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open db");
    let first_key = [3u8; 32];
    let second_key = [4u8; 32];
    for index in 0..64 {
        db::create_conversation(&conn, &first_key, &format!("first-{index}"))
            .expect("seed first-key conversation");
    }
    db::create_conversation(&conn, &second_key, "second-after-window")
        .expect("seed second-key conversation");
    drop(conn);

    let result = core::db_reset_vault_data_preserving_llm_profiles(
        dir.path().to_string_lossy().into_owned(),
        first_key.to_vec(),
    );

    let error = result.expect_err("mixed keys after the old probe window should be rejected");
    assert!(
        error
            .to_string()
            .contains("unable to validate key against existing vault data"),
        "unexpected error: {error}"
    );
    let conn = db::open(dir.path()).expect("reopen db");
    let count: i64 = conn
        .query_row("SELECT COUNT(*) FROM conversations", [], |row| row.get(0))
        .expect("count conversations");
    assert_eq!(count, 65);
}

#[test]
fn reset_rejects_valid_plus_corrupt_deferred_data_without_reporting_invalid_key() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open db");
    let key = [3u8; 32];
    let conversation = db::create_conversation(&conn, &key, "valid").expect("seed conversation");
    let corrupt_blob = vec![0xA5u8; 48];
    conn.execute(
        r#"INSERT INTO messages(id, conversation_id, role, content, created_at)
           VALUES ('corrupt-message', ?1, 'user', ?2, 1)"#,
        rusqlite::params![conversation.id, corrupt_blob],
    )
    .expect("seed corrupt message");
    drop(conn);

    let result = core::db_reset_vault_data_preserving_llm_profiles(
        dir.path().to_string_lossy().into_owned(),
        key.to_vec(),
    );

    let error = result.expect_err("corrupt mixed data should fail closed");
    assert!(
        error
            .to_string()
            .contains("unable to validate key against existing vault data"),
        "unexpected error: {error}"
    );
    assert!(
        !error.to_string().contains("invalid key"),
        "corrupt data should not be reported as a definitive invalid key: {error}"
    );
}

#[test]
fn reset_rejects_oversized_db_probe_without_reporting_invalid_key() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open db");
    let key = [4u8; 32];
    let conversation = db::create_conversation(&conn, &key, "valid").expect("seed conversation");
    let oversized_plaintext = vec![b'x'; OVERSIZED_DB_PROBE_BYTES];
    let oversized_blob = crypto::encrypt_bytes(&key, &oversized_plaintext, b"message.content")
        .expect("encrypt oversized message");
    conn.execute(
        r#"INSERT INTO messages(id, conversation_id, role, content, created_at)
           VALUES ('oversized-message', ?1, 'user', ?2, 1)"#,
        rusqlite::params![conversation.id, oversized_blob],
    )
    .expect("seed oversized message");
    drop(conn);

    let result = core::db_reset_vault_data_preserving_llm_profiles(
        dir.path().to_string_lossy().into_owned(),
        key.to_vec(),
    );

    let error = result.expect_err("oversized DB probe should fail closed");
    assert!(
        error
            .to_string()
            .contains("unable to validate key against existing vault data"),
        "unexpected error: {error}"
    );
    assert!(
        !error.to_string().contains("invalid key"),
        "oversized DB probe should not be reported as a definitive invalid key: {error}"
    );
    let conn = db::open(dir.path()).expect("reopen db");
    let count: i64 = conn
        .query_row("SELECT COUNT(*) FROM messages", [], |row| row.get(0))
        .expect("count messages");
    assert_eq!(count, 1);
}

#[test]
#[cfg(unix)]
fn reset_rejects_symlink_attachment_probe_without_following_link() {
    use std::os::unix::fs::symlink;

    let dir = tempfile::tempdir().expect("tempdir");
    let outside = tempfile::tempdir().expect("outside tempdir");
    let conn = db::open(dir.path()).expect("open db");
    let key = [5u8; 32];
    let sha256 = "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd";
    let stored_path = format!("attachments/{sha256}.bin");
    let link_path = dir.path().join(&stored_path);
    fs::create_dir_all(link_path.parent().expect("attachment parent"))
        .expect("create attachment dir");
    let outside_path = outside.path().join("target.bin");
    let aad = format!("attachment.bytes:{sha256}");
    let blob = crypto::encrypt_bytes(&key, b"outside attachment", aad.as_bytes())
        .expect("encrypt outside attachment");
    fs::write(&outside_path, blob).expect("write outside attachment");
    symlink(&outside_path, &link_path).expect("create attachment symlink");
    insert_attachment_row(&conn, sha256, &stored_path, 18, 1);
    drop(conn);

    let result = core::db_reset_vault_data_preserving_llm_profiles(
        dir.path().to_string_lossy().into_owned(),
        key.to_vec(),
    );

    let error = result.expect_err("symlink attachment probe should fail closed");
    assert!(
        error
            .to_string()
            .contains("unable to validate key against existing vault data"),
        "unexpected error: {error}"
    );
    let conn = db::open(dir.path()).expect("reopen db");
    let count: i64 = conn
        .query_row("SELECT COUNT(*) FROM attachments", [], |row| row.get(0))
        .expect("count attachments");
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
fn reset_allows_attachment_file_probe_after_many_missing_paths() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open db");
    let key = [6u8; 32];
    for index in 0..64 {
        let sha256 = format!("{index:064x}");
        let stored_path = format!("attachments/missing-{index}.bin");
        insert_attachment_row(&conn, &sha256, &stored_path, 10, index);
    }
    let sha256 = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
    let stored_path = format!("attachments/{sha256}.bin");
    let full_path = dir.path().join(&stored_path);
    fs::create_dir_all(full_path.parent().expect("attachment parent"))
        .expect("create attachment dir");
    let aad = format!("attachment.bytes:{sha256}");
    let blob = crypto::encrypt_bytes(&key, b"attachment bytes", aad.as_bytes())
        .expect("encrypt attachment");
    fs::write(&full_path, blob).expect("write attachment blob");
    insert_attachment_row(&conn, sha256, &stored_path, 16, 65);
    drop(conn);

    let result = core::db_reset_vault_data_preserving_llm_profiles(
        dir.path().to_string_lossy().into_owned(),
        key.to_vec(),
    );

    assert!(
        result.is_ok(),
        "valid attachment probe should be found after missing file rows: {result:?}"
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
fn reset_rejects_oversized_attachment_probe_without_reporting_invalid_key() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open db");
    let key = [6u8; 32];
    let oversized_sha256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    let oversized_path = format!("attachments/{oversized_sha256}.bin");
    let oversized_full_path = dir.path().join(&oversized_path);
    fs::create_dir_all(oversized_full_path.parent().expect("attachment parent"))
        .expect("create attachment dir");
    let oversized_file = fs::File::create(&oversized_full_path).expect("create oversized file");
    oversized_file
        .set_len(80 * 1024 * 1024)
        .expect("make sparse oversized file");
    insert_attachment_row(
        &conn,
        oversized_sha256,
        &oversized_path,
        80 * 1024 * 1024,
        1,
    );

    let valid_sha256 = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc";
    let valid_path = format!("attachments/{valid_sha256}.bin");
    let valid_full_path = dir.path().join(&valid_path);
    let aad = format!("attachment.bytes:{valid_sha256}");
    let blob =
        crypto::encrypt_bytes(&key, b"valid attachment", aad.as_bytes()).expect("encrypt valid");
    fs::write(&valid_full_path, blob).expect("write valid attachment");
    insert_attachment_row(&conn, valid_sha256, &valid_path, 16, 2);
    drop(conn);

    let result = core::db_reset_vault_data_preserving_llm_profiles(
        dir.path().to_string_lossy().into_owned(),
        key.to_vec(),
    );

    let error = result.expect_err("oversized file probe should fail closed");
    assert!(
        error
            .to_string()
            .contains("unable to validate key against existing vault data"),
        "unexpected error: {error}"
    );
    assert!(
        !error.to_string().contains("invalid key"),
        "oversized probe should not be reported as a definitive invalid key: {error}"
    );
}

#[test]
fn reset_allows_missing_auth_with_valid_external_attachment_only_deferred_key() {
    let dir = tempfile::tempdir().expect("tempdir");
    let key = [7u8; 32];
    let sha256 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    let stored_path = format!("external_readonly/storage/attachments/{sha256}.bin");
    let full_path = dir.path().join(&stored_path);
    fs::create_dir_all(full_path.parent().expect("external attachment parent"))
        .expect("create external attachment dir");
    let external_db_path = dir
        .path()
        .join("external_readonly/external_readonly.sqlite3");
    let conn = rusqlite::Connection::open(&external_db_path).expect("open external readonly db");
    conn.execute_batch(
        r#"
CREATE TABLE external_attachments (
  sha256 TEXT PRIMARY KEY,
  stored_path TEXT NOT NULL,
  size_bytes INTEGER NOT NULL,
  mime_type TEXT NOT NULL,
  ref_count INTEGER NOT NULL,
  created_at_ms INTEGER NOT NULL
);
"#,
    )
    .expect("create external attachment table");
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
