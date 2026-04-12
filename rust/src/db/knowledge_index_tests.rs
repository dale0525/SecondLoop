use super::*;

fn sqlite_table_exists(conn: &Connection, table_name: &str) -> bool {
    conn.query_row(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1",
        params![table_name],
        |row| row.get::<_, i64>(0),
    )
    .optional()
    .expect("table lookup")
    .is_some()
}

fn sqlite_index_exists(conn: &Connection, index_name: &str) -> bool {
    conn.query_row(
        "SELECT 1 FROM sqlite_master WHERE type = 'index' AND name = ?1",
        params![index_name],
        |row| row.get::<_, i64>(0),
    )
    .optional()
    .expect("index lookup")
    .is_some()
}

#[test]
fn knowledge_schema_migration_creates_versioned_tables_and_indexes() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");

    for table_name in [
        "knowledge_documents",
        "knowledge_units",
        "knowledge_embeddings",
        "knowledge_index_jobs",
        "knowledge_rebuild_state",
    ] {
        assert!(
            sqlite_table_exists(&conn, table_name),
            "missing {table_name}"
        );
    }

    for index_name in [
        "idx_knowledge_documents_origin_updated",
        "idx_knowledge_units_document_parent_kind",
        "idx_knowledge_units_anchor_lookup",
        "idx_knowledge_embeddings_target",
        "idx_knowledge_index_jobs_status_due",
    ] {
        assert!(
            sqlite_index_exists(&conn, index_name),
            "missing {index_name}"
        );
    }
}

#[test]
fn knowledge_schema_migration_seeds_rebuild_policy_versions() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");

    let row: (i64, i64, i64, i64, i64) = conn
        .query_row(
            r#"SELECT knowledge_schema_version,
                      normalization_version,
                      segmentation_version,
                      embedding_policy_version,
                      retrieval_policy_version
               FROM knowledge_rebuild_state
               WHERE state_key = 1"#,
            [],
            |row| {
                Ok((
                    row.get(0)?,
                    row.get(1)?,
                    row.get(2)?,
                    row.get(3)?,
                    row.get(4)?,
                ))
            },
        )
        .expect("rebuild state row");

    assert_eq!(row, (1, 1, 1, 1, 1));
}

#[test]
fn load_knowledge_memory_feedback_map_returns_defaults_for_missing_rows() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = [71u8; 32];

    upsert_knowledge_memory_feedback(
        &conn,
        &key,
        "generated:preference:hidden",
        Some(crate::knowledge::KnowledgeMemoryStatus::Confirmed),
        false,
        false,
        false,
        None,
        None,
    )
    .expect("upsert feedback");

    let document_ids = std::collections::BTreeSet::from([
        "generated:preference:hidden".to_string(),
        "generated:preference:missing".to_string(),
    ]);
    let feedback = load_knowledge_memory_feedback_map(&conn, &document_ids).expect("load map");

    assert_eq!(feedback.len(), 2);
    assert!(!feedback["generated:preference:hidden"].use_for_ask_ai);
    assert_eq!(
        feedback["generated:preference:missing"],
        crate::knowledge::KnowledgeMemoryFeedback::default()
    );
}

#[test]
fn backfill_knowledge_memory_feedback_oplog_rolls_back_partial_progress_on_error() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = [72u8; 32];

    conn.execute(
        r#"INSERT INTO knowledge_document_feedback(
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
           ) VALUES (?1, NULL, 1, 0, 0, NULL, NULL, ?2, ?2, '', 0)"#,
        params!["generated:preference:first", 100i64],
    )
    .expect("insert first feedback");
    conn.execute(
        r#"INSERT INTO knowledge_document_feedback(
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
           ) VALUES (?1, NULL, 1, 0, 0, NULL, NULL, ?2, ?2, '', 0)"#,
        params!["generated:preference:second", 200i64],
    )
    .expect("insert second feedback");
    conn.execute_batch(
        r#"CREATE TRIGGER abort_second_feedback_backfill
           BEFORE UPDATE ON knowledge_document_feedback
           WHEN NEW.document_id = 'generated:preference:second'
           BEGIN
             SELECT RAISE(ABORT, 'stop backfill');
           END;"#,
    )
    .expect("create abort trigger");

    let error = backfill_knowledge_memory_feedback_oplog_if_needed(&conn, &key)
        .expect_err("backfill should abort");
    assert!(error.to_string().contains("stop backfill"));

    let oplog_rows: i64 = conn
        .query_row("SELECT COUNT(*) FROM oplog", [], |row| row.get(0))
        .expect("oplog count");
    assert_eq!(oplog_rows, 0);

    let updated_rows: i64 = conn
        .query_row(
            r#"SELECT COUNT(*) FROM knowledge_document_feedback
               WHERE updated_by_device_id != '' OR updated_by_seq != 0"#,
            [],
            |row| row.get(0),
        )
        .expect("updated rows count");
    assert_eq!(updated_rows, 0);

    let sentinel = conn
        .query_row(
            "SELECT value FROM kv WHERE key = 'oplog.backfill.knowledge_memory_feedback.v1'",
            [],
            |row| row.get::<_, String>(0),
        )
        .optional()
        .expect("sentinel lookup");
    assert!(sentinel.is_none());
}
