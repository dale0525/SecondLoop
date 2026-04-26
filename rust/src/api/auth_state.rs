use std::fs;
use std::path::Path;

use crate::{auth, db};
use anyhow::{anyhow, Result};
use rusqlite::{params, Connection, OpenFlags};

#[path = "auth_state_deferred_probe.rs"]
mod auth_state_deferred_probe;
use auth_state_deferred_probe::{missing_auth_key_probe, MissingAuthKeyProbe};

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
    "llm_usage_daily",
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
    let staged_attachments_exist = db::attachment_reset_staging_dirs_have_entries(app_dir)?;
    let embedding_artifacts_exist = dir_has_entries(&app_dir.join("embedding_artifacts"))?;
    let external_readonly_exists = db::external_readonly_has_user_data(app_dir)?;
    let db_path = app_dir.join("secondloop.sqlite3");
    if !db_path.exists() {
        return Ok(attachments_exist
            || staged_attachments_exist
            || embedding_artifacts_exist
            || external_readonly_exists);
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
    if db::dynamic_embedding_tables_have_rows(&conn)? {
        return Ok(true);
    }
    Ok(attachments_exist
        || staged_attachments_exist
        || embedding_artifacts_exist
        || external_readonly_exists)
}

pub(crate) fn has_user_data_without_auth_file(app_dir: &Path) -> Result<bool> {
    vault_has_user_data_without_auth(app_dir)
}

pub(crate) fn auth_is_initialized(app_dir: &Path) -> bool {
    auth::is_initialized(app_dir)
}

pub(crate) fn validate_reset_vault_data_access(app_dir: &Path, key: &[u8; 32]) -> Result<()> {
    if auth::is_initialized(app_dir) {
        auth::validate_key(app_dir, key)?;
    } else if vault_has_user_data_without_auth(app_dir)? {
        match missing_auth_key_probe(app_dir, key)? {
            MissingAuthKeyProbe::ValidKey => return Ok(()),
            MissingAuthKeyProbe::UnableToValidate => {
                return Err(anyhow!(
                    "unable to validate key against existing vault data"
                ));
            }
            MissingAuthKeyProbe::NoEncryptedData => {}
        }
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

    fn write_empty_migration_archive(path: &Path) {
        let file = fs::File::create(path).expect("create migration archive");
        let mut writer = zip::ZipWriter::new(file);
        let options = zip::write::FileOptions::default();
        let manifest = db::MigrationArchiveManifest {
            schema_version: db::MIGRATION_ARCHIVE_SCHEMA_VERSION,
            archive_kind: "migration".to_string(),
            exported_at_ms: 1,
            app_version: "1.0.0".to_string(),
            items: vec![],
            attachments: vec![],
            relations: vec![],
        };
        writer
            .start_file("export-manifest.json", options)
            .expect("manifest entry");
        use std::io::Write as _;
        writer
            .write_all(
                serde_json::to_string(&manifest)
                    .expect("manifest json")
                    .as_bytes(),
            )
            .expect("write manifest");
        writer.finish().expect("finish migration archive");
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
    fn migration_archive_import_rejects_invalid_key_before_resetting_vault() {
        let dir = tempfile::tempdir().expect("tempdir");
        let valid_key = [8u8; 32];
        auth::init_master_password_with_existing_key(
            dir.path(),
            "password",
            crate::crypto::KdfParams::for_test(),
            valid_key,
        )
        .expect("initialize auth");
        let conn = db::open(dir.path()).expect("open db");
        let conversation =
            db::create_conversation(&conn, &valid_key, "keep me").expect("seed conversation");
        drop(conn);
        let archive_path = dir.path().join("empty-import.zip");
        write_empty_migration_archive(&archive_path);

        let result = crate::api::migration_archive::migration_archive_import(
            dir.path().to_string_lossy().into_owned(),
            vec![9u8; 32],
            archive_path.to_string_lossy().into_owned(),
        );

        let error = result.expect_err("invalid key should reject migration import");
        assert!(
            error.to_string().contains("invalid key"),
            "unexpected error: {error}"
        );
        let conn = db::open(dir.path()).expect("reopen db");
        let conversations = db::list_conversations(&conn, &valid_key).expect("list conversations");
        assert!(conversations.iter().any(|item| item.id == conversation.id));
    }

    #[test]
    fn reset_vault_data_preserving_llm_profiles_rejects_invalid_deferred_key() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = db::open(dir.path()).expect("open db");
        let valid_key = [3u8; 32];
        db::create_conversation(&conn, &valid_key, "hello").expect("seed conversation");

        let result = crate::api::core::db_reset_vault_data_preserving_llm_profiles(
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
    }

    #[test]
    fn reset_vault_data_preserving_llm_profiles_allows_missing_auth_with_valid_deferred_key() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = db::open(dir.path()).expect("open db");
        let key = [3u8; 32];
        db::create_conversation(&conn, &key, "hello").expect("seed conversation");
        drop(conn);

        let result = crate::api::core::db_reset_vault_data_preserving_llm_profiles(
            dir.path().to_string_lossy().into_owned(),
            key.to_vec(),
        );

        assert!(
            result.is_ok(),
            "valid deferred session key should allow reset without auth.json: {result:?}"
        );
        let conn = db::open(dir.path()).expect("reopen db");
        let conversations = db::list_conversations(&conn, &key).expect("list conversations");
        assert!(conversations.is_empty());
    }

    #[test]
    fn reset_vault_data_preserving_llm_profiles_skips_short_probe_rows() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = db::open(dir.path()).expect("open db");
        conn.execute(
            r#"INSERT INTO conversations(id, title, created_at, updated_at)
               VALUES ('legacy-short', X'68656C6C6F', 1, 1)"#,
            [],
        )
        .expect("insert short legacy row");
        let key = [3u8; 32];
        db::create_conversation(&conn, &key, "hello").expect("seed encrypted conversation");
        drop(conn);

        let result = crate::api::core::db_reset_vault_data_preserving_llm_profiles(
            dir.path().to_string_lossy().into_owned(),
            key.to_vec(),
        );

        assert!(
            result.is_ok(),
            "valid deferred key should be found after short probe rows: {result:?}"
        );
    }

    #[test]
    fn reset_vault_data_preserving_llm_profiles_rejects_mixed_deferred_keys() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = db::open(dir.path()).expect("open db");
        let first_key = [3u8; 32];
        let second_key = [4u8; 32];
        db::create_conversation(&conn, &first_key, "first").expect("seed first conversation");
        db::create_conversation(&conn, &second_key, "second").expect("seed second conversation");
        drop(conn);

        let result = crate::api::core::db_reset_vault_data_preserving_llm_profiles(
            dir.path().to_string_lossy().into_owned(),
            first_key.to_vec(),
        );

        let error = result.expect_err("mixed deferred keys should be rejected");
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
        assert_eq!(count, 2);
    }

    #[test]
    fn reset_vault_data_preserving_llm_profiles_allows_message_probe_fallback() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = db::open(dir.path()).expect("open db");
        let key = [3u8; 32];
        let conversation =
            db::create_conversation(&conn, &key, "hello").expect("seed conversation");
        db::insert_message(&conn, &key, &conversation.id, "user", "message").expect("seed message");
        conn.execute_batch(
            r#"
PRAGMA foreign_keys = OFF;
DELETE FROM conversations;
PRAGMA foreign_keys = ON;
"#,
        )
        .expect("remove conversation probe rows");
        drop(conn);

        let result = crate::api::core::db_reset_vault_data_preserving_llm_profiles(
            dir.path().to_string_lossy().into_owned(),
            key.to_vec(),
        );

        assert!(
            result.is_ok(),
            "valid deferred key should be accepted from message probe fallback: {result:?}"
        );
    }

    #[test]
    fn reset_vault_data_preserving_llm_profiles_allows_todo_probe_fallback() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = db::open(dir.path()).expect("open db");
        let key = [3u8; 32];
        db::upsert_todo(
            &conn, &key, "todo-1", "todo", None, "open", None, None, None, None, None, None,
        )
        .expect("seed todo");
        drop(conn);

        let result = crate::api::core::db_reset_vault_data_preserving_llm_profiles(
            dir.path().to_string_lossy().into_owned(),
            key.to_vec(),
        );

        assert!(
            result.is_ok(),
            "valid deferred key should be accepted from todo probe fallback: {result:?}"
        );
    }

    #[test]
    fn reset_vault_data_preserving_llm_profiles_allows_event_probe_fallback() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = db::open(dir.path()).expect("open db");
        let key = [3u8; 32];
        db::upsert_event(&conn, &key, "event-1", "event", 1, 2, "UTC", None).expect("seed event");
        drop(conn);

        let result = crate::api::core::db_reset_vault_data_preserving_llm_profiles(
            dir.path().to_string_lossy().into_owned(),
            key.to_vec(),
        );

        assert!(
            result.is_ok(),
            "valid deferred key should be accepted from event probe fallback: {result:?}"
        );
    }

    #[test]
    fn rollback_snapshot_creation_allows_missing_auth_with_valid_deferred_key() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = db::open(dir.path()).expect("open db");
        let key = [3u8; 32];
        db::create_conversation(&conn, &key, "hello").expect("seed conversation");
        drop(conn);

        let snapshot = crate::api::migration_archive::migration_archive_create_rollback_snapshot(
            dir.path().to_string_lossy().into_owned(),
            key.to_vec(),
        );

        let snapshot_path = snapshot
            .expect("valid deferred key should allow rollback snapshot")
            .expect("snapshot path");
        assert!(Path::new(&snapshot_path).is_file());
    }

    #[test]
    fn reset_vault_data_preserving_llm_profiles_rejects_missing_auth_when_staged_attachments_exist()
    {
        let dir = tempfile::tempdir().expect("tempdir");
        let staged_dir = dir.path().join("attachments.reset-staged-stale");
        fs::create_dir_all(&staged_dir).expect("create staged attachments");
        fs::write(staged_dir.join("orphan.bin"), b"orphan").expect("write staged attachment");

        let result = crate::api::core::db_reset_vault_data_preserving_llm_profiles(
            dir.path().to_string_lossy().into_owned(),
            vec![9u8; 32],
        );

        let error = result.expect_err("staged attachment data without auth should be rejected");
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
    fn reset_vault_data_preserving_llm_profiles_rejects_missing_auth_when_embedding_artifacts_exist(
    ) {
        let dir = tempfile::tempdir().expect("tempdir");
        let artifact_dir = dir.path().join("embedding_artifacts");
        fs::create_dir_all(&artifact_dir).expect("create embedding artifact dir");
        fs::write(artifact_dir.join("orphan.bin"), b"artifact").expect("write artifact blob");

        let result = crate::api::core::db_reset_vault_data_preserving_llm_profiles(
            dir.path().to_string_lossy().into_owned(),
            vec![9u8; 32],
        );

        let error = result.expect_err("embedding artifacts without auth should be rejected");
        assert!(
            error
                .to_string()
                .contains("vault data exists but auth file is missing"),
            "unexpected error: {error}"
        );
    }

    #[test]
    fn reset_vault_data_preserving_llm_profiles_rejects_missing_auth_when_dynamic_embeddings_exist()
    {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = db::open(dir.path()).expect("open db");
        conn.execute_batch(
            r#"
CREATE TABLE message_embeddings__s_review_4(embedding BLOB, message_id TEXT, model_name TEXT);
INSERT INTO message_embeddings__s_review_4 VALUES (X'01', 'message-1', 'review');
"#,
        )
        .expect("seed dynamic embedding table");

        let result = crate::api::core::db_reset_vault_data_preserving_llm_profiles(
            dir.path().to_string_lossy().into_owned(),
            vec![9u8; 32],
        );

        let error = result.expect_err("dynamic embeddings without auth should be rejected");
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
    fn reset_vault_data_preserving_llm_profiles_rejects_missing_auth_when_llm_usage_exists() {
        let dir = tempfile::tempdir().expect("tempdir");
        let conn = db::open(dir.path()).expect("open db");
        let key = [3u8; 32];
        let profile = db::create_llm_profile(
            &conn,
            &key,
            "OpenAI",
            "openai-compatible",
            Some("https://api.openai.com/v1"),
            None,
            "gpt-test",
            true,
        )
        .expect("create profile");
        db::record_llm_usage_daily(
            &conn,
            "2026-04-25",
            &profile.id,
            "ask_ai",
            Some(10),
            Some(20),
            Some(30),
        )
        .expect("record usage");

        let result = crate::api::core::db_reset_vault_data_preserving_llm_profiles(
            dir.path().to_string_lossy().into_owned(),
            vec![9u8; 32],
        );

        let error = result.expect_err("llm usage without auth should be rejected");
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
    fn rollback_snapshot_restore_allows_active_snapshot_when_auth_file_is_missing() {
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

        assert!(
            result.is_ok(),
            "active rollback snapshot should restore without current auth: {result:?}"
        );
    }

    #[test]
    fn rollback_snapshot_restore_failure_keeps_active_marker_for_authless_retry() {
        let dir = tempfile::tempdir().expect("tempdir");
        let key = [5u8; 32];
        auth::init_master_password_with_existing_key(
            dir.path(),
            "password",
            crate::crypto::KdfParams::for_test(),
            key,
        )
        .expect("initialize auth");
        let conn = db::open(dir.path()).expect("open db");
        let snapshot_conversation =
            db::create_conversation(&conn, &key, "snapshot").expect("seed snapshot conversation");
        let attachments_dir = dir.path().join("attachments");
        fs::create_dir_all(&attachments_dir).expect("create attachments dir");
        fs::write(attachments_dir.join("snapshot.bin"), b"snapshot")
            .expect("write snapshot attachment");
        let snapshot_path = db::migration_archive_create_rollback_snapshot(dir.path(), &key)
            .expect("create snapshot")
            .expect("snapshot path");
        db::create_conversation(&conn, &key, "current").expect("seed current conversation");
        drop(conn);
        fs::remove_dir_all(&attachments_dir).expect("remove attachments dir");
        fs::write(&attachments_dir, b"blocker").expect("write attachments blocker");

        let first_result =
            crate::api::migration_archive::migration_archive_restore_rollback_snapshot(
                dir.path().to_string_lossy().into_owned(),
                key.to_vec(),
                snapshot_path.to_string_lossy().into_owned(),
            );
        assert!(
            first_result.is_err(),
            "blocked restore should fail: {first_result:?}"
        );
        assert!(snapshot_path.exists());

        fs::remove_file(dir.path().join("auth.json")).expect("remove auth file");
        fs::remove_file(&attachments_dir).expect("remove attachments blocker");
        let retry_result =
            crate::api::migration_archive::migration_archive_restore_rollback_snapshot(
                dir.path().to_string_lossy().into_owned(),
                key.to_vec(),
                snapshot_path.to_string_lossy().into_owned(),
            );

        assert!(
            retry_result.is_ok(),
            "active rollback snapshot should retry without auth after a failed restore: {retry_result:?}"
        );
        let conn = db::open(dir.path()).expect("reopen db");
        let conversations = db::list_conversations(&conn, &key).expect("list conversations");
        assert!(conversations
            .iter()
            .any(|item| item.id == snapshot_conversation.id));
    }

    #[test]
    fn rollback_snapshot_restore_still_rejects_inactive_snapshot_when_auth_file_is_missing() {
        let dir = tempfile::tempdir().expect("tempdir");
        let key = [4u8; 32];
        let conn = db::open(dir.path()).expect("open db");
        db::create_conversation(&conn, &key, "hello").expect("seed conversation");
        drop(conn);
        let snapshot_path = dir.path().join("migration_archive/rollback/inactive.bin");
        fs::create_dir_all(snapshot_path.parent().expect("snapshot parent"))
            .expect("create rollback dir");
        fs::write(&snapshot_path, b"inactive").expect("write inactive snapshot");

        let result = crate::api::migration_archive::migration_archive_restore_rollback_snapshot(
            dir.path().to_string_lossy().into_owned(),
            key.to_vec(),
            snapshot_path.to_string_lossy().into_owned(),
        );

        let error = result.expect_err("inactive snapshot without auth should be rejected");
        assert!(
            error
                .to_string()
                .contains("vault data exists but auth file is missing"),
            "unexpected error: {error}"
        );
    }

    #[test]
    fn rollback_snapshot_restore_rejects_inactive_snapshot_copy_with_valid_deferred_key() {
        let dir = tempfile::tempdir().expect("tempdir");
        let key = [4u8; 32];
        let conn = db::open(dir.path()).expect("open db");
        db::create_conversation(&conn, &key, "hello").expect("seed conversation");
        drop(conn);
        let active_snapshot = db::migration_archive_create_rollback_snapshot(dir.path(), &key)
            .expect("create active snapshot")
            .expect("snapshot path");
        let inactive_snapshot = active_snapshot.with_file_name("inactive-copy.bin");
        fs::copy(&active_snapshot, &inactive_snapshot).expect("copy snapshot");

        let result = crate::api::migration_archive::migration_archive_restore_rollback_snapshot(
            dir.path().to_string_lossy().into_owned(),
            key.to_vec(),
            inactive_snapshot.to_string_lossy().into_owned(),
        );

        let error = result.expect_err("inactive snapshot copy should stay fail-closed");
        assert!(
            error
                .to_string()
                .contains("vault data exists but auth file is missing"),
            "unexpected error: {error}"
        );
    }
}
