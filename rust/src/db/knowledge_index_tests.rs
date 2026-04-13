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
        "knowledge_claims",
        "knowledge_pages",
        "knowledge_page_history",
        "knowledge_page_versions",
        "knowledge_page_lints",
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
        "idx_knowledge_claims_subject_status",
        "idx_knowledge_pages_state_updated",
        "idx_knowledge_page_history_page_created",
        "idx_knowledge_page_versions_page_created",
        "idx_knowledge_page_lints_page_created",
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

#[test]
fn upsert_knowledge_memory_feedback_rolls_back_when_oplog_insert_fails() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = [73u8; 32];

    conn.execute_batch(
        r#"CREATE TRIGGER abort_knowledge_feedback_oplog_insert
           BEFORE INSERT ON oplog
           BEGIN
             SELECT RAISE(ABORT, 'stop oplog');
           END;"#,
    )
    .expect("create oplog abort trigger");

    let error = upsert_knowledge_memory_feedback(
        &conn,
        &key,
        "generated:preference:atomicity",
        Some(crate::knowledge::KnowledgeMemoryStatus::Confirmed),
        false,
        false,
        false,
        Some("trimmed title".to_string()),
        Some("trimmed summary".to_string()),
    )
    .expect_err("upsert should abort when oplog insert fails");
    assert!(error.to_string().contains("stop oplog"));

    let feedback_row_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM knowledge_document_feedback WHERE document_id = ?1",
            params!["generated:preference:atomicity"],
            |row| row.get(0),
        )
        .expect("feedback row count");
    assert_eq!(feedback_row_count, 0);

    let oplog_rows: i64 = conn
        .query_row("SELECT COUNT(*) FROM oplog", [], |row| row.get(0))
        .expect("oplog count");
    assert_eq!(oplog_rows, 0);
}

#[test]
fn merge_knowledge_page_into_preserves_target_answer_policy_override() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = [74u8; 32];
    let now = 1_710_000_000_000i64;

    let mut target_page = crate::knowledge::KnowledgePage::new(
        "page:topics:target",
        crate::knowledge::KnowledgePageType::Topics,
        "Target Topic",
        now,
    );
    target_page.current_summary = "Target summary".to_string();
    target_page.current_body = "Target detail".to_string();
    target_page.primary_evidence_ids = vec!["doc:target".to_string()];
    target_page.source_count = 4;

    let mut source_page = crate::knowledge::KnowledgePage::new(
        "page:topics:source",
        crate::knowledge::KnowledgePageType::Topics,
        "Source Topic",
        now + 1,
    );
    source_page.current_summary = "Source summary".to_string();
    source_page.current_body = "Source detail".to_string();
    source_page.primary_evidence_ids = vec!["doc:source".to_string()];
    source_page.source_count = 3;

    upsert_compiled_knowledge_pages(
        &conn,
        &key,
        &[
            crate::knowledge::compiler::CompiledKnowledgePageRecord {
                page: target_page,
                source_document_ids: vec!["doc:target".to_string()],
                claim_ids: vec!["claim:target".to_string()],
            },
            crate::knowledge::compiler::CompiledKnowledgePageRecord {
                page: source_page,
                source_document_ids: vec!["doc:source".to_string()],
                claim_ids: vec!["claim:source".to_string()],
            },
        ],
    )
    .expect("seed pages");

    let muted_target = set_knowledge_page_answer_allowed(
        &conn,
        &key,
        "page:topics:target",
        false,
        Some("Keep this page muted.".to_string()),
    )
    .expect("mute target");
    assert!(!muted_target.page.answer_policy.default_allowed);

    merge_knowledge_page_into(
        &conn,
        &key,
        "page:topics:source",
        "page:topics:target",
        None,
    )
    .expect("merge knowledge page");

    let target_detail = get_knowledge_page_detail(&conn, &key, "page:topics:target")
        .expect("load target detail")
        .expect("target detail after merge");
    assert!(
        !target_detail.page.answer_policy.default_allowed,
        "target answer policy override should be preserved after merge"
    );
}

#[test]
fn merge_knowledge_page_into_preserves_combined_source_count() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = [75u8; 32];
    let now = 1_710_000_000_000i64;

    let mut target_page = crate::knowledge::KnowledgePage::new(
        "page:topics:target",
        crate::knowledge::KnowledgePageType::Topics,
        "Target Topic",
        now,
    );
    target_page.current_summary = "Target summary".to_string();
    target_page.current_body = "Target detail".to_string();
    target_page.primary_evidence_ids = vec!["doc:target".to_string()];
    target_page.source_count = 4;

    let mut source_page = crate::knowledge::KnowledgePage::new(
        "page:topics:source",
        crate::knowledge::KnowledgePageType::Topics,
        "Source Topic",
        now + 1,
    );
    source_page.current_summary = "Source summary".to_string();
    source_page.current_body = "Source detail".to_string();
    source_page.primary_evidence_ids = vec!["doc:source".to_string()];
    source_page.source_count = 3;

    upsert_compiled_knowledge_pages(
        &conn,
        &key,
        &[
            crate::knowledge::compiler::CompiledKnowledgePageRecord {
                page: target_page,
                source_document_ids: vec!["doc:target".to_string()],
                claim_ids: vec!["claim:target".to_string()],
            },
            crate::knowledge::compiler::CompiledKnowledgePageRecord {
                page: source_page,
                source_document_ids: vec!["doc:source".to_string()],
                claim_ids: vec!["claim:source".to_string()],
            },
        ],
    )
    .expect("seed pages");

    merge_knowledge_page_into(
        &conn,
        &key,
        "page:topics:source",
        "page:topics:target",
        None,
    )
    .expect("merge knowledge page");

    let target_detail = get_knowledge_page_detail(&conn, &key, "page:topics:target")
        .expect("load target detail")
        .expect("target detail after merge");
    assert_eq!(target_detail.page.source_count, 7);
}
