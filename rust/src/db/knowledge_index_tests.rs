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
        "idx_knowledge_page_history_created",
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
fn reset_knowledge_index_resets_page_refresh_state() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");

    conn.execute(
        r#"UPDATE knowledge_rebuild_state
           SET pages_refresh_required = 0,
               last_pages_refresh_completed_at_ms = 12345
           WHERE state_key = 1"#,
        [],
    )
    .expect("seed page refresh state");

    reset_knowledge_index(&conn).expect("reset knowledge index");

    let state: (i64, Option<i64>) = conn
        .query_row(
            r#"SELECT pages_refresh_required, last_pages_refresh_completed_at_ms
               FROM knowledge_rebuild_state
               WHERE state_key = 1"#,
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("load page refresh state");

    assert_eq!(state, (1, None));
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
    target_page.related_page_ids = vec!["page:topics:source".to_string()];
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
    source_page.related_page_ids = vec!["page:topics:target".to_string()];
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
    target_page.related_page_ids = vec!["page:topics:source".to_string()];
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
    source_page.related_page_ids = vec!["page:topics:target".to_string()];
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

#[test]
fn merge_knowledge_page_into_recomputes_conflict_count_from_merged_claims() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = [78u8; 32];
    let now = 1_710_000_000_000i64;

    let mut target_page = crate::knowledge::KnowledgePage::new(
        "page:topics:target",
        crate::knowledge::KnowledgePageType::Topics,
        "Target Topic",
        now,
    );
    target_page.current_summary = "Target summary".to_string();
    target_page.current_body = "Target detail".to_string();
    target_page.related_page_ids = vec!["page:topics:source".to_string()];
    target_page.source_count = 1;
    target_page.conflict_count = 0;

    let mut source_page = crate::knowledge::KnowledgePage::new(
        "page:topics:source",
        crate::knowledge::KnowledgePageType::Topics,
        "Source Topic",
        now + 1,
    );
    source_page.current_summary = "Source summary".to_string();
    source_page.current_body = "Source detail".to_string();
    source_page.related_page_ids = vec!["page:topics:target".to_string()];
    source_page.source_count = 1;
    source_page.conflict_count = 0;

    replace_knowledge_claims(
        &conn,
        &key,
        &[
            crate::knowledge::KnowledgeClaim {
                claim_id: "claim:target".to_string(),
                subject_id: "user:self".to_string(),
                claim_type: crate::knowledge::KnowledgeClaimType::Topic,
                facet_key: "launch-plan".to_string(),
                statement: "Freeze work this week.".to_string(),
                normalized_value: None,
                time_scope: crate::knowledge::KnowledgeClaimTimeScope::Current,
                valid_from_ms: None,
                valid_until_ms: None,
                confidence: 0.8,
                source_ref_ids: vec!["doc:target".to_string()],
                source_count: 1,
                conflict_with_claim_ids: vec![],
                status: crate::knowledge::KnowledgeClaimStatus::Active,
                human_confirmed: false,
                human_corrected: false,
                answer_allowed: true,
                created_at_ms: now,
                updated_at_ms: now,
            },
            crate::knowledge::KnowledgeClaim {
                claim_id: "claim:source".to_string(),
                subject_id: "user:self".to_string(),
                claim_type: crate::knowledge::KnowledgeClaimType::Topic,
                facet_key: "launch-plan".to_string(),
                statement: "Keep launch prep moving this week.".to_string(),
                normalized_value: None,
                time_scope: crate::knowledge::KnowledgeClaimTimeScope::Current,
                valid_from_ms: None,
                valid_until_ms: None,
                confidence: 0.7,
                source_ref_ids: vec!["doc:source".to_string()],
                source_count: 1,
                conflict_with_claim_ids: vec![],
                status: crate::knowledge::KnowledgeClaimStatus::Active,
                human_confirmed: false,
                human_corrected: false,
                answer_allowed: true,
                created_at_ms: now + 1,
                updated_at_ms: now + 1,
            },
        ],
    )
    .expect("seed claims");

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
    assert_eq!(target_detail.page.conflict_count, 1);
}

#[test]
fn merge_knowledge_page_into_preserves_manual_content_and_provenance_on_recompile() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = [76u8; 32];
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
    target_page.related_page_ids = vec!["page:topics:source".to_string()];
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
    source_page.related_page_ids = vec!["page:topics:target".to_string()];
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

    let mut recompiled_target_page = crate::knowledge::KnowledgePage::new(
        "page:topics:target",
        crate::knowledge::KnowledgePageType::Topics,
        "Target Topic",
        now + 100,
    );
    recompiled_target_page.current_summary = "Fresh compiled target summary".to_string();
    recompiled_target_page.current_body = "Fresh compiled target detail".to_string();
    recompiled_target_page.primary_evidence_ids = vec!["doc:target:new".to_string()];
    recompiled_target_page.source_count = 2;

    upsert_compiled_knowledge_pages(
        &conn,
        &key,
        &[crate::knowledge::compiler::CompiledKnowledgePageRecord {
            page: recompiled_target_page,
            source_document_ids: vec!["doc:target:new".to_string()],
            claim_ids: vec!["claim:target:new".to_string()],
        }],
    )
    .expect("recompile target");

    let target_detail = get_knowledge_page_detail(&conn, &key, "page:topics:target")
        .expect("load target detail")
        .expect("target detail after recompile");
    assert!(target_detail
        .page
        .current_summary
        .contains("Target summary"));
    assert!(target_detail
        .page
        .current_summary
        .contains("Source summary"));
    assert!(target_detail.page.current_body.contains("Target detail"));
    assert!(target_detail.page.current_body.contains("Source detail"));
    assert_eq!(target_detail.page.source_count, 7);
    assert!(target_detail
        .source_document_ids
        .iter()
        .any(|document_id| document_id == "doc:source"));
    assert!(target_detail
        .claim_ids
        .iter()
        .any(|claim_id| claim_id == "claim:source"));
}

#[test]
fn merge_knowledge_page_into_keeps_merged_source_archived_during_refresh_cleanup() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = [80u8; 32];
    let now = 1_710_000_000_000i64;

    let mut target_page = crate::knowledge::KnowledgePage::new(
        "page:topics:target",
        crate::knowledge::KnowledgePageType::Topics,
        "Target Topic",
        now,
    );
    target_page.current_summary = "Target summary".to_string();
    target_page.current_body = "Target detail".to_string();
    target_page.related_page_ids = vec!["page:topics:source".to_string()];

    let mut source_page = crate::knowledge::KnowledgePage::new(
        "page:topics:source",
        crate::knowledge::KnowledgePageType::Topics,
        "Source Topic",
        now + 1,
    );
    source_page.current_summary = "Source summary".to_string();
    source_page.current_body = "Source detail".to_string();
    source_page.related_page_ids = vec!["page:topics:target".to_string()];

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

    mark_missing_knowledge_pages_removed(&conn, &key, &[String::from("page:topics:target")])
        .expect("mark missing pages");

    let source_detail = get_knowledge_page_detail(&conn, &key, "page:topics:source")
        .expect("load source detail")
        .expect("source detail after cleanup");
    assert_eq!(
        source_detail.page.state,
        crate::knowledge::KnowledgePageState::Archived
    );

    let summaries = list_knowledge_page_summaries(&conn, &key).expect("list summaries");
    assert!(
        summaries
            .iter()
            .all(|page| page.page_id != "page:topics:source"),
        "summaries: {summaries:?}"
    );
}

#[test]
fn mark_missing_knowledge_pages_removed_preserves_manually_archived_pages() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = [84u8; 32];
    let now = 1_710_000_000_000i64;

    let mut archived_page = crate::knowledge::KnowledgePage::new(
        "page:topics:archived",
        crate::knowledge::KnowledgePageType::Topics,
        "Archived Topic",
        now,
    );
    archived_page.current_summary = "Archived summary".to_string();
    archived_page.current_body = "Archived detail".to_string();

    upsert_compiled_knowledge_pages(
        &conn,
        &key,
        &[crate::knowledge::compiler::CompiledKnowledgePageRecord {
            page: archived_page,
            source_document_ids: vec!["doc:archived".to_string()],
            claim_ids: vec!["claim:archived".to_string()],
        }],
    )
    .expect("seed archived page");

    archive_knowledge_page(
        &conn,
        &key,
        "page:topics:archived",
        Some("Keep only for audit.".to_string()),
    )
    .expect("archive page");

    mark_missing_knowledge_pages_removed(&conn, &key, &[]).expect("mark missing pages");

    let detail = get_knowledge_page_detail(&conn, &key, "page:topics:archived")
        .expect("load archived detail")
        .expect("archived detail should remain");
    assert_eq!(
        detail.page.state,
        crate::knowledge::KnowledgePageState::Archived
    );
}

#[test]
fn merged_page_recomputes_conflict_count_after_refresh_preserving_provenance() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = [88u8; 32];
    let now = 1_710_000_000_000i64;

    let mut target_page = crate::knowledge::KnowledgePage::new(
        "page:topics:target",
        crate::knowledge::KnowledgePageType::Topics,
        "Target Topic",
        now,
    );
    target_page.current_summary = "Target summary".to_string();
    target_page.current_body = "Target detail".to_string();
    target_page.related_page_ids = vec!["page:topics:source".to_string()];
    target_page.conflict_count = 1;

    let mut source_page = crate::knowledge::KnowledgePage::new(
        "page:topics:source",
        crate::knowledge::KnowledgePageType::Topics,
        "Source Topic",
        now + 1,
    );
    source_page.current_summary = "Source summary".to_string();
    source_page.current_body = "Source detail".to_string();
    source_page.related_page_ids = vec!["page:topics:target".to_string()];
    source_page.conflict_count = 1;

    replace_knowledge_claims(
        &conn,
        &key,
        &[
            crate::knowledge::KnowledgeClaim {
                claim_id: "claim:target".to_string(),
                subject_id: "user:self".to_string(),
                claim_type: crate::knowledge::KnowledgeClaimType::Topic,
                facet_key: "launch-plan".to_string(),
                statement: "Freeze work this week.".to_string(),
                normalized_value: None,
                time_scope: crate::knowledge::KnowledgeClaimTimeScope::Current,
                valid_from_ms: None,
                valid_until_ms: None,
                confidence: 0.8,
                source_ref_ids: vec!["generated:target".to_string()],
                source_count: 1,
                conflict_with_claim_ids: vec!["claim:source".to_string()],
                status: crate::knowledge::KnowledgeClaimStatus::Active,
                human_confirmed: false,
                human_corrected: false,
                answer_allowed: true,
                created_at_ms: now,
                updated_at_ms: now,
            },
            crate::knowledge::KnowledgeClaim {
                claim_id: "claim:source".to_string(),
                subject_id: "user:self".to_string(),
                claim_type: crate::knowledge::KnowledgeClaimType::Topic,
                facet_key: "launch-plan".to_string(),
                statement: "Keep shipping as planned.".to_string(),
                normalized_value: None,
                time_scope: crate::knowledge::KnowledgeClaimTimeScope::Current,
                valid_from_ms: None,
                valid_until_ms: None,
                confidence: 0.7,
                source_ref_ids: vec!["generated:source".to_string()],
                source_count: 1,
                conflict_with_claim_ids: vec!["claim:target".to_string()],
                status: crate::knowledge::KnowledgeClaimStatus::Active,
                human_confirmed: false,
                human_corrected: false,
                answer_allowed: true,
                created_at_ms: now + 1,
                updated_at_ms: now + 1,
            },
        ],
    )
    .expect("seed conflicting claims");

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
    .expect("merge pages");

    let merged_detail = get_knowledge_page_detail(&conn, &key, "page:topics:target")
        .expect("load merged detail")
        .expect("merged detail");
    assert_eq!(merged_detail.page.conflict_count, 1);

    replace_knowledge_claims(
        &conn,
        &key,
        &[crate::knowledge::KnowledgeClaim {
            claim_id: "claim:target".to_string(),
            subject_id: "user:self".to_string(),
            claim_type: crate::knowledge::KnowledgeClaimType::Topic,
            facet_key: "launch-plan".to_string(),
            statement: "Freeze work this week.".to_string(),
            normalized_value: None,
            time_scope: crate::knowledge::KnowledgeClaimTimeScope::Current,
            valid_from_ms: None,
            valid_until_ms: None,
            confidence: 0.8,
            source_ref_ids: vec!["generated:target".to_string()],
            source_count: 1,
            conflict_with_claim_ids: Vec::new(),
            status: crate::knowledge::KnowledgeClaimStatus::Active,
            human_confirmed: false,
            human_corrected: false,
            answer_allowed: true,
            created_at_ms: now,
            updated_at_ms: now + 2,
        }],
    )
    .expect("replace with resolved claims");

    let mut recompiled_target = crate::knowledge::KnowledgePage::new(
        "page:topics:target",
        crate::knowledge::KnowledgePageType::Topics,
        "Target Topic",
        now + 2,
    );
    recompiled_target.current_summary = "Resolved target summary".to_string();
    recompiled_target.current_body = "Resolved target detail".to_string();
    recompiled_target.related_page_ids = vec!["page:topics:source".to_string()];
    recompiled_target.conflict_count = 0;

    upsert_compiled_knowledge_pages(
        &conn,
        &key,
        &[crate::knowledge::compiler::CompiledKnowledgePageRecord {
            page: recompiled_target,
            source_document_ids: vec!["doc:target".to_string()],
            claim_ids: vec!["claim:target".to_string()],
        }],
    )
    .expect("recompile target page");

    let refreshed_detail = get_knowledge_page_detail(&conn, &key, "page:topics:target")
        .expect("load refreshed detail")
        .expect("refreshed detail");
    assert_eq!(refreshed_detail.page.conflict_count, 0);
}

#[test]
fn list_knowledge_page_summaries_excludes_archived_pages_from_normal_surfaces() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = [77u8; 32];
    let now = 1_710_000_000_000i64;

    let mut active_page = crate::knowledge::KnowledgePage::new(
        "page:topics:active",
        crate::knowledge::KnowledgePageType::Topics,
        "Active Topic",
        now,
    );
    active_page.current_summary = "Active summary".to_string();

    let mut archived_page = crate::knowledge::KnowledgePage::new(
        "page:topics:archived",
        crate::knowledge::KnowledgePageType::Topics,
        "Archived Topic",
        now + 1,
    );
    archived_page.current_summary = "Archived summary".to_string();

    upsert_compiled_knowledge_pages(
        &conn,
        &key,
        &[
            crate::knowledge::compiler::CompiledKnowledgePageRecord {
                page: active_page,
                source_document_ids: vec!["doc:active".to_string()],
                claim_ids: vec!["claim:active".to_string()],
            },
            crate::knowledge::compiler::CompiledKnowledgePageRecord {
                page: archived_page,
                source_document_ids: vec!["doc:archived".to_string()],
                claim_ids: vec!["claim:archived".to_string()],
            },
        ],
    )
    .expect("seed pages");

    archive_knowledge_page(
        &conn,
        &key,
        "page:topics:archived",
        Some("Archive from current surfaces".to_string()),
    )
    .expect("archive page");

    let summaries = list_knowledge_page_summaries(&conn, &key).expect("list summaries");
    let page_ids = summaries
        .into_iter()
        .map(|page| page.page_id)
        .collect::<Vec<_>>();

    assert_eq!(page_ids, vec!["page:topics:active".to_string()]);
}

#[test]
fn list_knowledge_page_summaries_excludes_removed_pages_from_normal_surfaces() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = [79u8; 32];
    let now = 1_710_000_000_000i64;

    let mut active_page = crate::knowledge::KnowledgePage::new(
        "page:topics:active",
        crate::knowledge::KnowledgePageType::Topics,
        "Active Topic",
        now,
    );
    active_page.current_summary = "Active summary".to_string();

    let mut removed_page = crate::knowledge::KnowledgePage::new(
        "page:topics:removed",
        crate::knowledge::KnowledgePageType::Topics,
        "Removed Topic",
        now + 1,
    );
    removed_page.current_summary = "Removed summary".to_string();

    upsert_compiled_knowledge_pages(
        &conn,
        &key,
        &[
            crate::knowledge::compiler::CompiledKnowledgePageRecord {
                page: active_page,
                source_document_ids: vec!["doc:active".to_string()],
                claim_ids: vec!["claim:active".to_string()],
            },
            crate::knowledge::compiler::CompiledKnowledgePageRecord {
                page: removed_page,
                source_document_ids: vec!["doc:removed".to_string()],
                claim_ids: vec!["claim:removed".to_string()],
            },
        ],
    )
    .expect("seed pages");

    remove_knowledge_page(
        &conn,
        &key,
        "page:topics:removed",
        Some("Removed pages should stay out of browse surfaces".to_string()),
    )
    .expect("remove page");

    let summaries = list_knowledge_page_summaries(&conn, &key).expect("list summaries");
    let page_ids = summaries
        .into_iter()
        .map(|page| page.page_id)
        .collect::<Vec<_>>();

    assert_eq!(page_ids, vec!["page:topics:active".to_string()]);
}

#[test]
fn list_knowledge_page_summaries_does_not_decode_page_body() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = [90u8; 32];
    let now = 1_710_000_000_000i64;

    let mut page = crate::knowledge::KnowledgePage::new(
        "page:topics:summary-only",
        crate::knowledge::KnowledgePageType::Topics,
        "Summary Only Topic",
        now,
    );
    page.current_summary = "Summary remains readable.".to_string();
    page.current_body = "Body should not be loaded by summaries.".to_string();

    upsert_compiled_knowledge_pages(
        &conn,
        &key,
        &[crate::knowledge::compiler::CompiledKnowledgePageRecord {
            page,
            source_document_ids: vec!["doc:summary-only".to_string()],
            claim_ids: vec!["claim:summary-only".to_string()],
        }],
    )
    .expect("seed page");

    conn.execute(
        "UPDATE knowledge_pages SET compiled_body = X'00' WHERE page_id = ?1",
        params!["page:topics:summary-only"],
    )
    .expect("corrupt compiled body");

    let summaries = list_knowledge_page_summaries(&conn, &key).expect("list summaries");
    let summary = summaries
        .into_iter()
        .find(|page| page.page_id == "page:topics:summary-only")
        .expect("summary-only page");
    assert_eq!(summary.title, "Summary Only Topic");
    assert_eq!(summary.current_summary, "Summary remains readable.");
}

#[test]
fn manual_correction_lints_use_all_source_documents_not_primary_evidence_only() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = open(dir.path()).expect("open");
    let key = [78u8; 32];
    let now = 1_710_000_000_000i64;

    let mut page = crate::knowledge::KnowledgePage::new(
        "page:topics:multi-source",
        crate::knowledge::KnowledgePageType::Topics,
        "Multi Source Topic",
        now,
    );
    page.current_summary = "Compiled summary".to_string();
    page.current_body = "Compiled body".to_string();
    page.primary_evidence_ids = vec!["doc:primary".to_string()];
    page.source_count = 2;

    upsert_compiled_knowledge_pages(
        &conn,
        &key,
        &[crate::knowledge::compiler::CompiledKnowledgePageRecord {
            page,
            source_document_ids: vec!["doc:primary".to_string(), "doc:secondary".to_string()],
            claim_ids: vec!["claim:primary".to_string(), "claim:secondary".to_string()],
        }],
    )
    .expect("seed page");

    let corrected = apply_knowledge_page_correction(
        &conn,
        &key,
        "page:topics:multi-source",
        None,
        Some("Manual summary".to_string()),
        None,
    )
    .expect("correct page");

    assert!(
        corrected
            .lint_records
            .iter()
            .all(|lint| lint.kind != crate::knowledge::KnowledgeLintKind::EvidenceWeakness),
        "lint records: {:?}",
        corrected.lint_records
    );
}
