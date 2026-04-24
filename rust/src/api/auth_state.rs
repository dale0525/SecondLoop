use std::fs;
use std::path::Path;

use crate::{auth, db};
use anyhow::{anyhow, Result};
use rusqlite::{params, Connection, OpenFlags};

const USER_DATA_TABLES_WITHOUT_AUTH: &[&str] = &[
    "message_embeddings",
    "todo_embeddings",
    "todo_activity_embeddings",
    "semantic_parse_jobs",
    "todo_followup_generation_jobs",
    "tag_merge_feedback",
    "message_tag_autofill_events",
    "message_tag_autofill_jobs",
    "message_tags",
    "message_attachments",
    "attachment_derivations",
    "cloud_media_backup",
    "attachment_variants",
    "attachment_exif",
    "attachment_metadata",
    "attachment_places",
    "attachment_annotations",
    "attachment_chunk_embedding_jobs",
    "attachment_text_chunks",
    "attachment_deletions",
    "attachments",
    "messages",
    "tags",
    "conversations",
    "todo_deletions",
    "todo_checklist_suggestions",
    "todo_followup_suggestions",
    "todo_checklist_items",
    "todos",
    "todo_activity_attachments",
    "todo_activities",
    "todo_recurrences",
    "todo_series",
    "events",
    "detached_ask_completion_claims",
    "embedding_artifact_manifests",
    "knowledge_document_usage",
    "knowledge_document_feedback",
    "knowledge_page_lints",
    "knowledge_page_history",
    "knowledge_page_versions",
    "knowledge_pages",
    "knowledge_claims",
    "knowledge_embeddings",
    "knowledge_index_jobs",
    "knowledge_units",
    "knowledge_documents",
    "oplog",
];

fn dir_has_entries(path: &Path) -> Result<bool> {
    match fs::read_dir(path) {
        Ok(mut entries) => Ok(entries.next().is_some()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(e) => Err(e.into()),
    }
}

fn table_has_rows(conn: &Connection, table: &str) -> Result<bool> {
    let table_exists: bool = conn.query_row(
        r#"SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1)"#,
        params![table],
        |row| row.get(0),
    )?;
    if !table_exists {
        return Ok(false);
    }

    let quoted_table = table.replace('"', "\"\"");
    let sql = format!(r#"SELECT EXISTS(SELECT 1 FROM "{quoted_table}" LIMIT 1)"#);
    let has_rows: bool = conn.query_row(&sql, [], |row| row.get(0))?;
    Ok(has_rows)
}

fn vault_has_user_data_without_auth(app_dir: &Path) -> Result<bool> {
    let attachments_exist = dir_has_entries(&app_dir.join("attachments"))?;
    let external_readonly_exists = db::external_readonly_has_user_data(app_dir)?;
    let db_path = app_dir.join("secondloop.sqlite3");
    if !db_path.exists() {
        return Ok(attachments_exist || external_readonly_exists);
    }

    let conn = Connection::open_with_flags(
        db_path,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )?;
    for table in USER_DATA_TABLES_WITHOUT_AUTH {
        if table_has_rows(&conn, table)? {
            return Ok(true);
        }
    }
    Ok(attachments_exist || external_readonly_exists)
}

pub(crate) fn auth_is_initialized(app_dir: &Path) -> bool {
    auth::is_initialized(app_dir)
}

pub(crate) fn validate_reset_vault_data_access(app_dir: &Path, key: &[u8; 32]) -> Result<()> {
    if auth::is_initialized(app_dir) {
        auth::validate_key(app_dir, key)?;
    } else if vault_has_user_data_without_auth(app_dir)? {
        return Err(anyhow!("vault data exists but auth file is missing"));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db;

    fn seed_external_import_batch(app_dir: &Path) {
        let conn = db::open_external_readonly_db(app_dir).expect("open external readonly db");
        conn.execute(
            r#"INSERT INTO external_import_batches(
              batch_id, source_kind, source_label, status,
              created_at_ms, updated_at_ms, stats_json
            ) VALUES ('batch-1', 'obsidian', 'External', 'completed', 1, 1, '{}')"#,
            [],
        )
        .expect("insert external batch");
    }

    #[test]
    fn reset_vault_data_preserving_llm_profiles_allows_missing_auth_file() {
        let dir = tempfile::tempdir().expect("tempdir");
        let key = vec![7u8; 32];

        let result = crate::api::core::db_reset_vault_data_preserving_llm_profiles(
            dir.path().to_string_lossy().into_owned(),
            key,
        );

        assert!(
            result.is_ok(),
            "expected reset to succeed without auth.json"
        );
    }

    #[test]
    fn reset_vault_data_preserving_llm_profiles_still_rejects_invalid_key_when_auth_exists() {
        let dir = tempfile::tempdir().expect("tempdir");
        let valid_key = [3u8; 32];
        auth::init_master_password_with_existing_key(
            dir.path(),
            "password",
            crate::crypto::KdfParams::for_test(),
            valid_key,
        )
        .expect("initialize auth");

        let result = crate::api::core::db_reset_vault_data_preserving_llm_profiles(
            dir.path().to_string_lossy().into_owned(),
            vec![9u8; 32],
        );

        let error = result.expect_err("invalid key should still be rejected");
        assert!(
            error.to_string().contains("invalid key"),
            "unexpected error: {error}"
        );
    }

    #[test]
    fn reset_vault_data_preserving_llm_profiles_rejects_missing_auth_when_vault_has_user_data() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = db::open(dir.path()).expect("open db");
        let valid_key = [3u8; 32];
        db::create_conversation(&conn, &valid_key, "hello").expect("seed conversation");

        let result = crate::api::core::db_reset_vault_data_preserving_llm_profiles(
            dir.path().to_string_lossy().into_owned(),
            vec![9u8; 32],
        );

        let error = result.expect_err("vault data without auth should be rejected");
        assert!(
            error
                .to_string()
                .contains("vault data exists but auth file is missing"),
            "unexpected error: {error}"
        );
    }

    #[test]
    fn reset_vault_data_preserving_llm_profiles_rejects_missing_auth_when_external_data_exists() {
        let dir = tempfile::tempdir().expect("tempdir");
        seed_external_import_batch(dir.path());

        let result = crate::api::core::db_reset_vault_data_preserving_llm_profiles(
            dir.path().to_string_lossy().into_owned(),
            vec![9u8; 32],
        );

        let error = result.expect_err("external data without auth should be rejected");
        assert!(
            error
                .to_string()
                .contains("vault data exists but auth file is missing"),
            "unexpected error: {error}"
        );
    }

    #[test]
    fn reset_vault_data_preserving_llm_profiles_rejects_missing_auth_when_only_oplog_exists() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = db::open(dir.path()).expect("open db");
        conn.execute(
            r#"INSERT INTO oplog(op_id, device_id, seq, op_json, created_at)
               VALUES ('op-1', 'device-1', 1, X'00', 1)"#,
            [],
        )
        .expect("insert oplog");

        let result = crate::api::core::db_reset_vault_data_preserving_llm_profiles(
            dir.path().to_string_lossy().into_owned(),
            vec![9u8; 32],
        );

        let error = result.expect_err("oplog without auth should be rejected");
        assert!(
            error
                .to_string()
                .contains("vault data exists but auth file is missing"),
            "unexpected error: {error}"
        );
    }

    #[test]
    fn missing_auth_user_data_check_does_not_migrate_legacy_db() {
        let dir = tempfile::tempdir().expect("tempdir");
        fs::create_dir_all(dir.path()).expect("create app dir");
        let db_path = dir.path().join("secondloop.sqlite3");
        let conn = Connection::open(&db_path).expect("open legacy db");
        conn.execute_batch(
            r#"
CREATE TABLE conversations (
  id TEXT PRIMARY KEY,
  title BLOB NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
INSERT INTO conversations(id, title, created_at, updated_at)
VALUES ('c1', X'68656C6C6F', 1, 1);
PRAGMA user_version = 1;
"#,
        )
        .expect("seed legacy db");
        drop(conn);

        let result = crate::api::core::db_reset_vault_data_preserving_llm_profiles(
            dir.path().to_string_lossy().into_owned(),
            vec![9u8; 32],
        );

        let error = result.expect_err("vault data without auth should be rejected");
        assert!(
            error
                .to_string()
                .contains("vault data exists but auth file is missing"),
            "unexpected error: {error}"
        );

        let conn = Connection::open(&db_path).expect("reopen legacy db");
        let user_version: i64 = conn
            .pragma_query_value(None, "user_version", |row| row.get(0))
            .expect("read user_version");
        assert_eq!(user_version, 1);

        let llm_profiles_exists: bool = conn
            .query_row(
                r#"SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'llm_profiles')"#,
                [],
                |row| row.get(0),
            )
            .expect("check llm_profiles");
        assert!(!llm_profiles_exists);
    }

    #[test]
    fn rollback_snapshot_creation_does_not_migrate_legacy_db_without_auth() {
        let dir = tempfile::tempdir().expect("tempdir");
        fs::create_dir_all(dir.path()).expect("create app dir");
        let db_path = dir.path().join("secondloop.sqlite3");
        let conn = Connection::open(&db_path).expect("open legacy db");
        conn.execute_batch(
            r#"
CREATE TABLE conversations (
  id TEXT PRIMARY KEY,
  title BLOB NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
INSERT INTO conversations(id, title, created_at, updated_at)
VALUES ('c1', X'68656C6C6F', 1, 1);
PRAGMA user_version = 1;
"#,
        )
        .expect("seed legacy db");
        drop(conn);

        let result = crate::api::migration_archive::migration_archive_create_rollback_snapshot(
            dir.path().to_string_lossy().into_owned(),
            vec![9u8; 32],
        );

        let error = result.expect_err("vault data without auth should be rejected");
        assert!(
            error
                .to_string()
                .contains("vault data exists but auth file is missing"),
            "unexpected error: {error}"
        );
        assert!(!dir.path().join("migration_archive").exists());

        let conn = Connection::open(&db_path).expect("reopen legacy db");
        let user_version: i64 = conn
            .pragma_query_value(None, "user_version", |row| row.get(0))
            .expect("read user_version");
        assert_eq!(user_version, 1);

        let llm_profiles_exists: bool = conn
            .query_row(
                r#"SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'llm_profiles')"#,
                [],
                |row| row.get(0),
            )
            .expect("check llm_profiles");
        assert!(!llm_profiles_exists);
    }

    #[test]
    fn auth_is_initialized_returns_false_when_auth_is_missing_but_vault_has_user_data() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = db::open(dir.path()).expect("open db");
        let valid_key = [3u8; 32];
        db::create_conversation(&conn, &valid_key, "hello").expect("seed conversation");

        assert!(!auth_is_initialized(dir.path()));
    }

    #[test]
    fn reset_vault_data_preserving_llm_profiles_allows_preserved_profiles_without_auth() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = db::open(dir.path()).expect("open db");
        conn.execute(
            r#"INSERT INTO llm_profiles(
              id, name, provider_type, base_url, api_key, model_name, is_active, created_at, updated_at
            ) VALUES ('p1', 'Profile', 'openai', NULL, NULL, 'gpt-test', 1, 1, 1)"#,
            [],
        )
        .expect("insert profile");

        let result = crate::api::core::db_reset_vault_data_preserving_llm_profiles(
            dir.path().to_string_lossy().into_owned(),
            vec![7u8; 32],
        );

        assert!(
            result.is_ok(),
            "preserved profile-only vault should reset without auth: {result:?}"
        );
    }

    #[test]
    fn rollback_snapshot_restore_rejects_missing_auth_when_vault_has_user_data() {
        let dir = tempfile::tempdir().expect("tempdir");
        let key = [3u8; 32];
        auth::init_master_password_with_existing_key(
            dir.path(),
            "password",
            crate::crypto::KdfParams::for_test(),
            key,
        )
        .expect("initialize auth");
        let conn = db::open(dir.path()).expect("open db");
        db::create_conversation(&conn, &key, "hello").expect("seed conversation");
        drop(conn);

        let snapshot_path = db::migration_archive_create_rollback_snapshot(dir.path(), &key)
            .expect("create snapshot")
            .expect("snapshot path");
        fs::remove_file(dir.path().join("auth.json")).expect("remove auth file");

        let result = crate::api::migration_archive::migration_archive_restore_rollback_snapshot(
            dir.path().to_string_lossy().into_owned(),
            key.to_vec(),
            snapshot_path.to_string_lossy().into_owned(),
        );

        let error = result.expect_err("vault data without auth should be rejected");
        assert!(
            error
                .to_string()
                .contains("vault data exists but auth file is missing"),
            "unexpected error: {error}"
        );
    }
}
