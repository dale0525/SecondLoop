use std::fs;
use std::path::Path;

use crate::{auth, db};
use anyhow::{anyhow, Result};

fn dir_has_entries(path: &Path) -> Result<bool> {
    match fs::read_dir(path) {
        Ok(mut entries) => Ok(entries.next().is_some()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(e) => Err(e.into()),
    }
}

fn vault_has_user_data_without_auth(app_dir: &Path) -> Result<bool> {
    let attachments_exist = dir_has_entries(&app_dir.join("attachments"))?;
    let db_path = app_dir.join("secondloop.sqlite3");
    if !db_path.exists() {
        return Ok(attachments_exist);
    }

    let conn = db::open(app_dir)?;
    let db_has_user_data: bool = conn.query_row(
        r#"
SELECT
  EXISTS(SELECT 1 FROM conversations LIMIT 1) OR
  EXISTS(SELECT 1 FROM messages LIMIT 1) OR
  EXISTS(SELECT 1 FROM attachments LIMIT 1) OR
  EXISTS(SELECT 1 FROM todos LIMIT 1) OR
  EXISTS(SELECT 1 FROM tags LIMIT 1) OR
  EXISTS(SELECT 1 FROM events LIMIT 1) OR
  EXISTS(SELECT 1 FROM knowledge_documents LIMIT 1)
"#,
        [],
        |row| row.get(0),
    )?;
    Ok(db_has_user_data || attachments_exist)
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
}
