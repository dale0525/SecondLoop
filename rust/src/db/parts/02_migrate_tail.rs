fn migrate_from_v29_to_v30(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        r#"
CREATE TABLE IF NOT EXISTS embedding_artifact_manifests (
  artifact_id TEXT PRIMARY KEY,
  source_kind TEXT NOT NULL,
  source_id TEXT NOT NULL,
  source_revision INTEGER NOT NULL,
  chunk_hash TEXT NOT NULL,
  chunk_ordinal INTEGER NOT NULL DEFAULT 0,
  profile_id TEXT NOT NULL,
  producer_device_id TEXT,
  producer_class TEXT NOT NULL,
  quality_tier TEXT NOT NULL DEFAULT 'full',
  vector_format TEXT NOT NULL,
  dimension INTEGER NOT NULL,
  blob_ref TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'ready',
  supersedes_artifact_id TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_embedding_artifact_identity
  ON embedding_artifact_manifests(
    source_kind,
    source_id,
    source_revision,
    chunk_hash,
    profile_id,
    status
  );
CREATE INDEX IF NOT EXISTS idx_embedding_artifact_source_revision
  ON embedding_artifact_manifests(
    source_kind,
    source_id,
    source_revision,
    profile_id,
    status,
    chunk_ordinal,
    created_at_ms
  );
CREATE INDEX IF NOT EXISTS idx_embedding_artifact_chunk_profile
  ON embedding_artifact_manifests(chunk_hash, profile_id, status, created_at_ms);

PRAGMA user_version = 30;
"#,
    )?;
    Ok(())
}

fn migrate_from_v30_to_v31(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        r#"
CREATE TABLE IF NOT EXISTS attachment_derivations (
  root_sha256 TEXT NOT NULL,
  child_sha256 TEXT NOT NULL,
  role TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  PRIMARY KEY(root_sha256, child_sha256, role)
);
CREATE INDEX IF NOT EXISTS idx_attachment_derivations_root_sha256
  ON attachment_derivations(root_sha256);
CREATE INDEX IF NOT EXISTS idx_attachment_derivations_child_sha256
  ON attachment_derivations(child_sha256);

PRAGMA user_version = 31;
"#,
    )?;
    Ok(())
}

fn migrate_from_v31_to_v32(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        r#"
CREATE TABLE IF NOT EXISTS knowledge_document_usage (
  document_id TEXT PRIMARY KEY,
  retrieve_count INTEGER NOT NULL DEFAULT 0,
  last_retrieved_at_ms INTEGER,
  FOREIGN KEY(document_id) REFERENCES knowledge_documents(document_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_knowledge_document_usage_recent
  ON knowledge_document_usage(last_retrieved_at_ms DESC, retrieve_count DESC);

PRAGMA user_version = 32;
"#,
    )?;
    Ok(())
}

fn migrate_from_v32_to_v33(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        r#"
CREATE TABLE IF NOT EXISTS todo_checklist_items (
  id TEXT PRIMARY KEY,
  todo_id TEXT NOT NULL,
  content BLOB NOT NULL,
  is_done INTEGER NOT NULL DEFAULT 0,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  FOREIGN KEY(todo_id) REFERENCES todos(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_todo_checklist_items_todo_sort
  ON todo_checklist_items(todo_id, sort_order, created_at_ms);
CREATE INDEX IF NOT EXISTS idx_todo_checklist_items_todo_done
  ON todo_checklist_items(todo_id, is_done);

CREATE TABLE IF NOT EXISTS todo_checklist_suggestions (
  id TEXT PRIMARY KEY,
  todo_id TEXT NOT NULL,
  content BLOB NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  state TEXT NOT NULL,
  source TEXT NOT NULL,
  generation_key TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  dismissed_at_ms INTEGER,
  applied_checklist_item_id TEXT,
  FOREIGN KEY(todo_id) REFERENCES todos(id) ON DELETE CASCADE,
  FOREIGN KEY(applied_checklist_item_id) REFERENCES todo_checklist_items(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS idx_todo_checklist_suggestions_todo_state
  ON todo_checklist_suggestions(todo_id, state, sort_order);
CREATE INDEX IF NOT EXISTS idx_todo_checklist_suggestions_generation_key
  ON todo_checklist_suggestions(generation_key);

PRAGMA user_version = 33;
"#,
    )?;
    Ok(())
}


fn migrate_from_v33_to_v34(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        r#"
UPDATE todo_checklist_suggestions
SET state = 'pending',
    updated_at_ms = CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER)
WHERE state = 'applied' AND applied_checklist_item_id IS NULL;

CREATE TRIGGER IF NOT EXISTS trg_todo_checklist_suggestions_revert_deleted_item
BEFORE DELETE ON todo_checklist_items
FOR EACH ROW
BEGIN
  UPDATE todo_checklist_suggestions
  SET state = 'pending',
      updated_at_ms = CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER),
      applied_checklist_item_id = NULL
  WHERE applied_checklist_item_id = OLD.id
    AND state = 'applied';
END;

PRAGMA user_version = 34;
"#,
    )?;
    Ok(())
}

fn execute_batch_allowing_duplicate_columns(conn: &Connection, sql: &str) -> Result<()> {
    match conn.execute_batch(sql) {
        Ok(()) => Ok(()),
        Err(err) if err.to_string().contains("duplicate column name") => Ok(()),
        Err(err) => Err(err.into()),
    }
}

fn table_has_column(conn: &Connection, table_name: &str, column_name: &str) -> Result<bool> {
    let mut stmt = conn.prepare(&format!("PRAGMA table_info({table_name})"))?;
    let mut rows = stmt.query([])?;
    while let Some(row) = rows.next()? {
        let name: String = row.get(1)?;
        if name == column_name {
            return Ok(true);
        }
    }
    Ok(false)
}

fn ensure_todo_manual_nudge_columns(conn: &Connection) -> Result<()> {
    let has_manual_importance_nudge_score: bool = {
        let mut stmt = conn.prepare(r#"PRAGMA table_info(todos);"#)?;
        let mut rows = stmt.query([])?;
        let mut found = false;
        while let Some(row) = rows.next()? {
            let name: String = row.get(1)?;
            if name == "manual_importance_nudge_score" {
                found = true;
                break;
            }
        }
        found
    };
    if !has_manual_importance_nudge_score {
        execute_batch_allowing_duplicate_columns(
            conn,
            "ALTER TABLE todos ADD COLUMN manual_importance_nudge_score INTEGER NOT NULL DEFAULT 0;",
        )?;
    }

    let has_manual_urgency_nudge_score: bool = {
        let mut stmt = conn.prepare(r#"PRAGMA table_info(todos);"#)?;
        let mut rows = stmt.query([])?;
        let mut found = false;
        while let Some(row) = rows.next()? {
            let name: String = row.get(1)?;
            if name == "manual_urgency_nudge_score" {
                found = true;
                break;
            }
        }
        found
    };
    if !has_manual_urgency_nudge_score {
        execute_batch_allowing_duplicate_columns(
            conn,
            "ALTER TABLE todos ADD COLUMN manual_urgency_nudge_score INTEGER NOT NULL DEFAULT 0;",
        )?;
    }

    Ok(())
}

fn migrate_from_v34_to_v35(conn: &Connection) -> Result<()> {
    ensure_todo_manual_nudge_columns(conn)?;

    conn.execute_batch("PRAGMA user_version = 35;")?;
    Ok(())
}

fn migrate_from_v35_to_v36(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        r#"
CREATE TABLE IF NOT EXISTS todo_followup_suggestions (
  id TEXT PRIMARY KEY,
  todo_id TEXT NOT NULL,
  content BLOB NOT NULL,
  state TEXT NOT NULL,
  source TEXT NOT NULL,
  generation_mode TEXT NOT NULL,
  generation_key TEXT,
  citations_json TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  dismissed_at_ms INTEGER,
  applied_activity_id TEXT,
  FOREIGN KEY(todo_id) REFERENCES todos(id) ON DELETE CASCADE,
  FOREIGN KEY(applied_activity_id) REFERENCES todo_activities(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS idx_todo_followup_suggestions_todo_state
  ON todo_followup_suggestions(todo_id, state, created_at_ms);
CREATE INDEX IF NOT EXISTS idx_todo_followup_suggestions_generation_key
  ON todo_followup_suggestions(generation_key);

CREATE TABLE IF NOT EXISTS todo_followup_generation_jobs (
  todo_id TEXT PRIMARY KEY,
  trigger_kind TEXT NOT NULL,
  status TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  next_retry_at_ms INTEGER,
  last_error TEXT,
  include_manual_followups INTEGER NOT NULL DEFAULT 0,
  manual_override_followup INTEGER NOT NULL DEFAULT 0,
  task_type_hint TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  FOREIGN KEY(todo_id) REFERENCES todos(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_todo_followup_generation_jobs_status_due
  ON todo_followup_generation_jobs(status, next_retry_at_ms, updated_at_ms);
"#,
    )?;

    let mut stmt = conn.prepare("PRAGMA table_info(todo_followup_generation_jobs)")?;
    let columns: Vec<String> = stmt
        .query_map([], |row| row.get(1))?
        .collect::<std::result::Result<Vec<_>, _>>()?;

    if !columns.iter().any(|column| column == "manual_override_followup") {
        conn.execute_batch(
            "ALTER TABLE todo_followup_generation_jobs ADD COLUMN manual_override_followup INTEGER NOT NULL DEFAULT 0;",
        )?;
    }

    if !columns.iter().any(|column| column == "task_type_hint") {
        conn.execute_batch(
            "ALTER TABLE todo_followup_generation_jobs ADD COLUMN task_type_hint TEXT;",
        )?;
    }

    conn.execute_batch("PRAGMA user_version = 36;")?;
    Ok(())
}

fn migrate_from_v36_to_v37(conn: &Connection) -> Result<()> {
    let mut stmt = conn.prepare("PRAGMA table_info(semantic_parse_jobs)")?;
    let columns: Vec<String> = stmt
        .query_map([], |row| row.get(1))?
        .collect::<std::result::Result<Vec<_>, _>>()?;

    if !columns.iter().any(|column| column == "attempt_id") {
        execute_batch_allowing_duplicate_columns(
            conn,
            r#"
ALTER TABLE semantic_parse_jobs
  ADD COLUMN attempt_id INTEGER NOT NULL DEFAULT 0;
"#,
        )?;
    }

    conn.execute_batch("PRAGMA user_version = 37;")?;
    Ok(())
}

fn migrate_from_v37_to_v38(conn: &Connection) -> Result<()> {
    let mut stmt = conn.prepare("PRAGMA table_info(messages)")?;
    let columns: Vec<String> = stmt
        .query_map([], |row| row.get(1))?
        .collect::<std::result::Result<Vec<_>, _>>()?;

    if !columns.iter().any(|column| column == "citations_json") {
        execute_batch_allowing_duplicate_columns(
            conn,
            r#"
ALTER TABLE messages
  ADD COLUMN citations_json TEXT;
"#,
        )?;
    }

    conn.execute_batch("PRAGMA user_version = 38;")?;
    Ok(())
}

fn migrate_from_v38_to_v39(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        r#"
CREATE TABLE IF NOT EXISTS knowledge_document_feedback (
  document_id TEXT PRIMARY KEY,
  status TEXT,
  use_for_ask_ai INTEGER NOT NULL DEFAULT 1,
  is_deleted INTEGER NOT NULL DEFAULT 0,
  marked_inaccurate INTEGER NOT NULL DEFAULT 0,
  corrected_title TEXT,
  corrected_summary TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  FOREIGN KEY(document_id) REFERENCES knowledge_documents(document_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_knowledge_document_feedback_visibility
  ON knowledge_document_feedback(is_deleted, use_for_ask_ai, updated_at_ms DESC);

PRAGMA user_version = 39;
"#,
    )?;
    Ok(())
}

fn migrate_from_v39_to_v40(conn: &Connection) -> Result<()> {
    execute_batch_allowing_duplicate_columns(
        conn,
        "ALTER TABLE knowledge_documents ADD COLUMN memory_section TEXT;",
    )?;
    execute_batch_allowing_duplicate_columns(
        conn,
        "ALTER TABLE knowledge_documents ADD COLUMN memory_source_count INTEGER NOT NULL DEFAULT 0;",
    )?;
    conn.execute_batch("PRAGMA user_version = 40;")?;
    Ok(())
}

fn migrate_from_v40_to_v41(conn: &Connection) -> Result<()> {
    execute_batch_allowing_duplicate_columns(
        conn,
        "ALTER TABLE detached_ask_completion_claims ADD COLUMN user_message_id TEXT;",
    )?;
    execute_batch_allowing_duplicate_columns(
        conn,
        "ALTER TABLE detached_ask_completion_claims ADD COLUMN assistant_message_id TEXT;",
    )?;
    conn.execute_batch("PRAGMA user_version = 41;")?;
    Ok(())
}

fn migrate_from_v41_to_v42(conn: &Connection) -> Result<()> {
    conn.execute_batch("BEGIN IMMEDIATE;")?;
    let result: Result<()> = (|| {
        conn.execute_batch(
            r#"
DROP TABLE IF EXISTS detached_ask_completion_claims_v42;

CREATE TABLE detached_ask_completion_claims_v42 (
  request_id TEXT NOT NULL,
  conversation_id TEXT NOT NULL,
  user_message_id TEXT,
  assistant_message_id TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  PRIMARY KEY(request_id, conversation_id)
);

INSERT INTO detached_ask_completion_claims_v42(
  request_id,
  conversation_id,
  user_message_id,
  assistant_message_id,
  created_at_ms,
  updated_at_ms
)
SELECT request_id,
       conversation_id,
       user_message_id,
       assistant_message_id,
       created_at_ms,
       updated_at_ms
  FROM detached_ask_completion_claims;

DROP TABLE detached_ask_completion_claims;
ALTER TABLE detached_ask_completion_claims_v42 RENAME TO detached_ask_completion_claims;
CREATE INDEX IF NOT EXISTS idx_detached_ask_completion_claims_conversation
  ON detached_ask_completion_claims(conversation_id, created_at_ms DESC);

PRAGMA user_version = 42;
"#,
        )?;
        Ok(())
    })();

    match result {
        Ok(()) => {
            conn.execute_batch("COMMIT;")?;
            Ok(())
        }
        Err(err) => {
            let _ = conn.execute_batch("ROLLBACK;");
            Err(err)
        }
    }
}

fn migrate_from_v42_to_v43(conn: &Connection) -> Result<()> {
    conn.execute_batch("BEGIN IMMEDIATE;")?;
    let result: Result<()> = (|| {
        conn.execute_batch(
            r#"
DROP TABLE IF EXISTS knowledge_document_feedback_v43;

CREATE TABLE knowledge_document_feedback_v43 (
  document_id TEXT PRIMARY KEY,
  status TEXT,
  use_for_ask_ai INTEGER NOT NULL DEFAULT 1,
  is_deleted INTEGER NOT NULL DEFAULT 0,
  marked_inaccurate INTEGER NOT NULL DEFAULT 0,
  corrected_title TEXT,
  corrected_summary TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  updated_by_device_id TEXT NOT NULL DEFAULT '',
  updated_by_seq INTEGER NOT NULL DEFAULT 0
);

INSERT INTO knowledge_document_feedback_v43(
  document_id,
  status,
  use_for_ask_ai,
  is_deleted,
  marked_inaccurate,
  corrected_title,
  corrected_summary,
  created_at_ms,
  updated_at_ms,
  updated_by_device_id,
  updated_by_seq
)
SELECT document_id,
       status,
       use_for_ask_ai,
       is_deleted,
       marked_inaccurate,
       corrected_title,
       corrected_summary,
       created_at_ms,
       updated_at_ms,
       '',
       0
  FROM knowledge_document_feedback;

DROP TABLE knowledge_document_feedback;
ALTER TABLE knowledge_document_feedback_v43 RENAME TO knowledge_document_feedback;
CREATE INDEX IF NOT EXISTS idx_knowledge_document_feedback_visibility
  ON knowledge_document_feedback(is_deleted, use_for_ask_ai, updated_at_ms DESC);

PRAGMA user_version = 43;
"#,
        )?;
        Ok(())
    })();

    match result {
        Ok(()) => {
            conn.execute_batch("COMMIT;")?;
            Ok(())
        }
        Err(err) => {
            let _ = conn.execute_batch("ROLLBACK;");
            Err(err)
        }
    }
}

fn migrate_from_v43_to_v44(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        r#"
CREATE TABLE IF NOT EXISTS knowledge_claims (
  claim_id TEXT PRIMARY KEY,
  subject_id TEXT NOT NULL,
  claim_type TEXT NOT NULL,
  facet_key TEXT NOT NULL,
  statement BLOB NOT NULL,
  normalized_value BLOB,
  time_scope TEXT NOT NULL,
  valid_from_ms INTEGER,
  valid_until_ms INTEGER,
  confidence REAL NOT NULL,
  source_ref_ids_json TEXT NOT NULL,
  source_count INTEGER NOT NULL DEFAULT 0,
  conflict_with_claim_ids_json TEXT NOT NULL,
  status TEXT NOT NULL,
  human_confirmed INTEGER NOT NULL DEFAULT 0,
  human_corrected INTEGER NOT NULL DEFAULT 0,
  answer_allowed INTEGER NOT NULL DEFAULT 1,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_knowledge_claims_subject_status
  ON knowledge_claims(subject_id, status, updated_at_ms DESC);

CREATE TABLE IF NOT EXISTS knowledge_pages (
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
CREATE INDEX IF NOT EXISTS idx_knowledge_pages_state_updated
  ON knowledge_pages(state, updated_at_ms DESC);

CREATE TABLE IF NOT EXISTS knowledge_page_history (
  change_id TEXT PRIMARY KEY,
  page_id TEXT NOT NULL,
  change_type TEXT NOT NULL,
  actor TEXT NOT NULL,
  reason TEXT,
  answer_impacted INTEGER NOT NULL DEFAULT 0,
  created_at_ms INTEGER NOT NULL,
  FOREIGN KEY(page_id) REFERENCES knowledge_pages(page_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_knowledge_page_history_page_created
  ON knowledge_page_history(page_id, created_at_ms DESC);

CREATE TABLE IF NOT EXISTS knowledge_page_lints (
  lint_id TEXT PRIMARY KEY,
  page_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  summary TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  FOREIGN KEY(page_id) REFERENCES knowledge_pages(page_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_knowledge_page_lints_page_created
  ON knowledge_page_lints(page_id, created_at_ms DESC);

PRAGMA user_version = 44;
"#,
    )?;
    Ok(())
}

fn migrate_from_v44_to_v45(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        r#"
CREATE TABLE IF NOT EXISTS knowledge_page_versions (
  version_id TEXT PRIMARY KEY,
  page_id TEXT NOT NULL,
  change_type TEXT NOT NULL,
  actor TEXT NOT NULL,
  reason TEXT,
  state TEXT NOT NULL,
  answer_default_allowed INTEGER NOT NULL DEFAULT 1,
  answer_requires_temporal_framing INTEGER NOT NULL DEFAULT 0,
  confidence_level REAL NOT NULL DEFAULT 0,
  source_count INTEGER NOT NULL DEFAULT 0,
  conflict_count INTEGER NOT NULL DEFAULT 0,
  human_corrected INTEGER NOT NULL DEFAULT 0,
  title BLOB NOT NULL,
  summary BLOB NOT NULL,
  body BLOB NOT NULL,
  created_at_ms INTEGER NOT NULL,
  FOREIGN KEY(page_id) REFERENCES knowledge_pages(page_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_knowledge_page_versions_page_created
  ON knowledge_page_versions(page_id, created_at_ms DESC);

PRAGMA user_version = 45;
"#,
    )?;
    Ok(())
}

fn migrate_from_v45_to_v46(conn: &Connection) -> Result<()> {
    if !table_has_column(conn, "knowledge_rebuild_state", "pages_refresh_required")? {
        execute_batch_allowing_duplicate_columns(
            conn,
            r#"
ALTER TABLE knowledge_rebuild_state
  ADD COLUMN pages_refresh_required INTEGER NOT NULL DEFAULT 1;
"#,
        )?;
    }
    if !table_has_column(
        conn,
        "knowledge_rebuild_state",
        "last_pages_refresh_completed_at_ms",
    )? {
        execute_batch_allowing_duplicate_columns(
            conn,
            r#"
ALTER TABLE knowledge_rebuild_state
  ADD COLUMN last_pages_refresh_completed_at_ms INTEGER;
"#,
        )?;
    }
    conn.execute_batch("PRAGMA user_version = 46;")?;
    Ok(())
}

fn migrate_from_v46_to_v47(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        r#"
CREATE INDEX IF NOT EXISTS idx_knowledge_page_history_created
  ON knowledge_page_history(created_at_ms DESC, change_id DESC);

PRAGMA user_version = 47;
"#,
    )?;
    Ok(())
}

fn migrate_from_v47_to_v48(conn: &Connection) -> Result<()> {
    if !table_has_column(
        conn,
        "knowledge_pages",
        "state_before_answer_muted",
    )? {
        execute_batch_allowing_duplicate_columns(
            conn,
            r#"
ALTER TABLE knowledge_pages
  ADD COLUMN state_before_answer_muted TEXT;
"#,
        )?;
    }

    conn.execute_batch("PRAGMA user_version = 48;")?;
    Ok(())
}

fn migrate_from_v48_to_v49(conn: &Connection) -> Result<()> {
    if !table_has_column(
        conn,
        "semantic_parse_jobs",
        "applied_prev_todo_due_at_ms",
    )? {
        execute_batch_allowing_duplicate_columns(
            conn,
            r#"
ALTER TABLE semantic_parse_jobs
  ADD COLUMN applied_prev_todo_due_at_ms INTEGER;
"#,
        )?;
    }

    if !table_has_column(conn, "semantic_parse_jobs", "applied_due_changed")? {
        execute_batch_allowing_duplicate_columns(
            conn,
            r#"
ALTER TABLE semantic_parse_jobs
  ADD COLUMN applied_due_changed INTEGER NOT NULL DEFAULT 0;
"#,
        )?;
    }

    conn.execute_batch("PRAGMA user_version = 49;")?;
    Ok(())
}

pub(crate) fn app_dir_from_conn(conn: &Connection) -> Result<PathBuf> {
    let mut stmt = conn.prepare("PRAGMA database_list")?;
    let mut rows = stmt.query([])?;
    while let Some(row) = rows.next()? {
        let name: String = row.get(1)?;
        if name != "main" {
            continue;
        }
        let file: String = row.get(2)?;
        if file.trim().is_empty() {
            break;
        }

        let path = PathBuf::from(file);
        let Some(parent) = path.parent() else {
            break;
        };
        return Ok(parent.to_path_buf());
    }
    Err(anyhow!("unable to derive app_dir from sqlite connection"))
}

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
}

pub fn reset_vault_data_preserving_llm_profiles(conn: &Connection) -> Result<()> {
    let app_dir = app_dir_from_conn(conn).ok();
    conn.execute_batch("BEGIN IMMEDIATE;")?;

    let result: Result<()> = (|| {
        conn.execute_batch(
            r#"
DELETE FROM message_embeddings;
DELETE FROM todo_embeddings;
DELETE FROM todo_activity_embeddings;
DELETE FROM semantic_parse_jobs;
DELETE FROM todo_followup_generation_jobs;
DELETE FROM tag_merge_feedback;
DELETE FROM message_tag_autofill_events;
DELETE FROM message_tag_autofill_jobs;
DELETE FROM message_tags;
DELETE FROM message_attachments;
DELETE FROM attachment_derivations;
DELETE FROM cloud_media_backup;
DELETE FROM attachment_variants;
DELETE FROM attachment_exif;
DELETE FROM attachment_metadata;
DELETE FROM attachment_places;
DELETE FROM attachment_annotations;
DELETE FROM attachment_chunk_embedding_jobs;
DELETE FROM attachment_text_chunks;
DELETE FROM attachment_deletions;
DELETE FROM attachments;
DELETE FROM messages;
DELETE FROM tags;
DELETE FROM conversations;
DELETE FROM todo_deletions;
DELETE FROM todo_checklist_suggestions;
DELETE FROM todo_followup_suggestions;
DELETE FROM todo_checklist_items;
DELETE FROM todos;
DELETE FROM todo_activity_attachments;
DELETE FROM todo_activities;
DELETE FROM todo_recurrences;
DELETE FROM todo_series;
DELETE FROM events;
DELETE FROM detached_ask_completion_claims;
DELETE FROM embedding_artifact_manifests;
DELETE FROM knowledge_document_usage;
DELETE FROM knowledge_document_feedback;
DELETE FROM knowledge_page_lints;
DELETE FROM knowledge_page_history;
DELETE FROM knowledge_page_versions;
DELETE FROM knowledge_pages;
DELETE FROM knowledge_claims;
DELETE FROM knowledge_embeddings;
DELETE FROM knowledge_index_jobs;
DELETE FROM knowledge_units;
DELETE FROM knowledge_documents;
UPDATE knowledge_rebuild_state
SET status = 'empty',
    rebuild_required = 0,
    stale_reason = NULL,
    last_error = NULL,
    last_rebuild_started_at_ms = NULL,
    last_rebuild_completed_at_ms = NULL,
    current_document_id = NULL,
    current_stage = NULL,
    documents_indexed = 0,
    units_indexed = 0,
    embeddings_indexed = 0,
    total_documents = 0,
    cancel_requested = 0,
    pages_refresh_required = 1,
    last_pages_refresh_completed_at_ms = NULL,
    last_indexed_model_name = NULL,
    last_indexed_dim = NULL;
DELETE FROM oplog;
DELETE FROM kv WHERE key != 'embedding.active_model_name';
"#,
        )?;
        Ok(())
    })();

    match result {
        Ok(()) => {
            conn.execute_batch("COMMIT;")?;
            if let Some(app_dir) = app_dir {
                let _ = best_effort_remove_dir_all(&app_dir.join("attachments"));
            }
            Ok(())
        }
        Err(e) => {
            let _ = conn.execute_batch("ROLLBACK;");
            Err(e)
        }
    }
}
