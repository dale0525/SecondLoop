#[cfg(test)]
mod migrate_tail_tests {
    use super::*;

    #[test]
    fn add_column_migration_tolerates_duplicate_column_errors() {
        let conn = Connection::open_in_memory().expect("open in memory");
        conn.execute_batch(
            r#"
CREATE TABLE messages (
  id TEXT PRIMARY KEY,
  citations_json TEXT
);
"#,
        )
        .expect("create table");

        execute_batch_allowing_duplicate_columns(
            &conn,
            r#"
ALTER TABLE messages
  ADD COLUMN citations_json TEXT;
"#,
        )
        .expect("duplicate column should be ignored");
    }

    #[test]
    fn add_column_migration_still_surfaces_real_sql_errors() {
        let conn = Connection::open_in_memory().expect("open in memory");

        let err = execute_batch_allowing_duplicate_columns(
            &conn,
            "ALTER TABLE missing_table ADD COLUMN citations_json TEXT;",
        )
        .expect_err("missing table should still fail");

        assert!(err.to_string().contains("missing_table"));
    }

    #[test]
    fn v42_detached_claim_migration_recovers_from_stale_temp_table() {
        let conn = Connection::open_in_memory().expect("open in memory");
        conn.execute_batch(
            r#"
CREATE TABLE detached_ask_completion_claims (
  request_id TEXT NOT NULL,
  conversation_id TEXT NOT NULL,
  user_message_id TEXT,
  assistant_message_id TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  PRIMARY KEY(request_id, conversation_id)
);
INSERT INTO detached_ask_completion_claims(
  request_id,
  conversation_id,
  user_message_id,
  assistant_message_id,
  created_at_ms,
  updated_at_ms
)
VALUES ('req-1', 'conv-1', 'user-1', 'assistant-1', 10, 20);

CREATE TABLE detached_ask_completion_claims_v42 (
  request_id TEXT NOT NULL,
  conversation_id TEXT NOT NULL,
  user_message_id TEXT,
  assistant_message_id TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  PRIMARY KEY(request_id, conversation_id)
);
"#,
        )
        .expect("seed pre-migration state");

        migrate_from_v41_to_v42(&conn).expect("rerun v42 migration");

        let row: (String, String, String, String, i64, i64) = conn
            .query_row(
                r#"SELECT request_id,
                          conversation_id,
                          user_message_id,
                          assistant_message_id,
                          created_at_ms,
                          updated_at_ms
                   FROM detached_ask_completion_claims"#,
                [],
                |row| {
                    Ok((
                        row.get(0)?,
                        row.get(1)?,
                        row.get(2)?,
                        row.get(3)?,
                        row.get(4)?,
                        row.get(5)?,
                    ))
                },
            )
            .expect("migrated row");

        assert_eq!(
            row,
            (
                "req-1".to_string(),
                "conv-1".to_string(),
                "user-1".to_string(),
                "assistant-1".to_string(),
                10,
                20,
            )
        );
    }

    #[test]
    fn v46_knowledge_rebuild_state_migration_tolerates_partially_applied_columns() {
        let conn = Connection::open_in_memory().expect("open in memory");
        conn.execute_batch(
            r#"
CREATE TABLE knowledge_rebuild_state (
  state_key INTEGER PRIMARY KEY,
  pages_refresh_required INTEGER NOT NULL DEFAULT 1
);
"#,
        )
        .expect("seed partial table");

        migrate_from_v45_to_v46(&conn).expect("rerun v46 migration");

        let mut stmt = conn
            .prepare("PRAGMA table_info(knowledge_rebuild_state)")
            .expect("prepare table info");
        let column_names = stmt
            .query_map([], |row| row.get::<_, String>(1))
            .expect("query table info")
            .collect::<std::result::Result<Vec<_>, _>>()
            .expect("collect column names");
        assert!(column_names.contains(&"pages_refresh_required".to_string()));
        assert!(column_names.contains(&"last_pages_refresh_completed_at_ms".to_string()));
    }

    #[test]
    fn v48_knowledge_pages_migration_adds_previous_muted_state_column() {
        let conn = Connection::open_in_memory().expect("open in memory");
        conn.execute_batch(
            r#"
CREATE TABLE knowledge_pages (
  page_id TEXT PRIMARY KEY,
  page_type TEXT NOT NULL,
  state TEXT NOT NULL,
  answer_default_allowed INTEGER NOT NULL DEFAULT 1,
  answer_requires_temporal_framing INTEGER NOT NULL DEFAULT 0,
  confidence_level REAL NOT NULL DEFAULT 0,
  source_count INTEGER NOT NULL DEFAULT 0,
  conflict_count INTEGER NOT NULL DEFAULT 0,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  last_used_at_ms INTEGER,
  human_corrected INTEGER NOT NULL DEFAULT 0,
  tags_json TEXT NOT NULL,
  primary_evidence_json TEXT NOT NULL,
  related_page_ids_json TEXT NOT NULL,
  source_document_ids_json TEXT NOT NULL,
  claim_ids_json TEXT NOT NULL,
  compiled_title BLOB NOT NULL,
  compiled_summary BLOB NOT NULL,
  compiled_body BLOB NOT NULL,
  manual_title BLOB,
  manual_summary BLOB,
  manual_body BLOB
);
"#,
        )
        .expect("seed pre-v48 knowledge_pages");

        migrate_from_v47_to_v48(&conn).expect("rerun v48 migration");

        let mut stmt = conn
            .prepare("PRAGMA table_info(knowledge_pages)")
            .expect("prepare table info");
        let column_names = stmt
            .query_map([], |row| row.get::<_, String>(1))
            .expect("query table info")
            .collect::<std::result::Result<Vec<_>, _>>()
            .expect("collect column names");
        assert!(column_names.contains(&"state_before_answer_muted".to_string()));
    }

    #[test]
    fn v49_semantic_parse_jobs_migration_adds_due_undo_columns() {
        let conn = Connection::open_in_memory().expect("open in memory");
        conn.execute_batch(
            r#"
CREATE TABLE semantic_parse_jobs (
  message_id TEXT PRIMARY KEY,
  status TEXT NOT NULL,
  attempt_id INTEGER NOT NULL DEFAULT 0,
  attempts INTEGER NOT NULL DEFAULT 0,
  next_retry_at_ms INTEGER,
  last_error TEXT,
  applied_action_kind TEXT,
  applied_todo_id TEXT,
  applied_todo_title BLOB,
  applied_prev_todo_status TEXT,
  undone_at_ms INTEGER,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);
"#,
        )
        .expect("seed pre-v49 semantic_parse_jobs");

        migrate_from_v48_to_v49(&conn).expect("rerun v49 migration");

        let mut stmt = conn
            .prepare("PRAGMA table_info(semantic_parse_jobs)")
            .expect("prepare table info");
        let column_names = stmt
            .query_map([], |row| row.get::<_, String>(1))
            .expect("query table info")
            .collect::<std::result::Result<Vec<_>, _>>()
            .expect("collect column names");
        assert!(column_names.contains(&"applied_prev_todo_due_at_ms".to_string()));
        assert!(column_names.contains(&"applied_due_changed".to_string()));
    }

    #[test]
    fn v50_cloud_media_backup_migration_rebuilds_scope_primary_key() {
        let conn = Connection::open_in_memory().expect("open in memory");
        conn.execute_batch(
            r#"
CREATE TABLE attachments (
  sha256 TEXT PRIMARY KEY
);
CREATE TABLE cloud_media_backup (
  attachment_sha256 TEXT PRIMARY KEY,
  desired_variant TEXT NOT NULL,
  status TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  next_retry_at INTEGER,
  last_error TEXT,
  updated_at INTEGER NOT NULL
);
INSERT INTO cloud_media_backup(
  attachment_sha256,
  desired_variant,
  status,
  attempts,
  next_retry_at,
  last_error,
  updated_at
) VALUES ('sha-1', 'original', 'pending', 0, NULL, NULL, 1234);
INSERT INTO attachments(sha256) VALUES ('sha-1');
PRAGMA user_version = 49;
"#,
        )
        .expect("seed pre-v50 cloud_media_backup");

        migrate_from_v49_to_v50(&conn).expect("run v50 migration");

        let mut stmt = conn
            .prepare("PRAGMA table_info(cloud_media_backup)")
            .expect("prepare table info");
        let columns = stmt
            .query_map([], |row| Ok((row.get::<_, String>(1)?, row.get::<_, i64>(5)?)))
            .expect("query table info")
            .collect::<std::result::Result<Vec<_>, _>>()
            .expect("collect columns");
        assert!(
            columns.iter().any(|(name, pk)| name == "scope_id" && *pk == 1),
            "scope_id should be the first primary-key column"
        );
        assert!(
            columns
                .iter()
                .any(|(name, pk)| name == "attachment_sha256" && *pk == 2),
            "attachment_sha256 should be the second primary-key column"
        );

        let migrated: Vec<(String, String, String)> = conn
            .prepare(
                r#"SELECT scope_id, attachment_sha256, status
                   FROM cloud_media_backup
                   ORDER BY attachment_sha256 ASC"#,
            )
            .expect("prepare migrated rows")
            .query_map([], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)))
            .expect("query migrated rows")
            .collect::<std::result::Result<Vec<_>, _>>()
            .expect("collect migrated rows");
        assert!(
            migrated.is_empty(),
            "v50 migration should drop legacy cloud media backup rows rather than risking a wrong scoped upload"
        );

        let user_version: i64 = conn
            .query_row("PRAGMA user_version", [], |row| row.get(0))
            .expect("user_version");
        assert_eq!(user_version, 50);
    }
}
