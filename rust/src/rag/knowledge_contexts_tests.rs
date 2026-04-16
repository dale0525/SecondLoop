use crate::db;
use crate::knowledge;
use crate::message_citations::append_message_citation_if_missing;
use crate::rag::knowledge_contexts::{
    collect_compiled_page_contexts, filter_disabled_generated_memory_blocks,
    merge_knowledge_and_legacy_contexts, rebalance_planning_contexts,
    should_exclude_generated_document_for_page_policies, try_build_knowledge_context_entries,
    try_build_knowledge_contexts,
};
use crate::rag::Focus;
use rusqlite::params;

fn insert_document(
    conn: &rusqlite::Connection,
    key: &[u8; 32],
    document_id: &str,
    origin_type: &str,
    updated_at_ms: i64,
    conversation_id: Option<&str>,
    text: &str,
) {
    let anchor_json = serde_json::to_string(&crate::knowledge::KnowledgeAnchorSet {
        conversation_id: conversation_id.map(|value| value.to_string()),
        ..crate::knowledge::KnowledgeAnchorSet::default()
    })
    .expect("anchor json");
    let raw =
        db::encode_knowledge_document_text(key, document_id, "raw", text).expect("encode raw");
    let normalized = db::encode_knowledge_document_text(key, document_id, "normalized", text)
        .expect("encode normalized");
    conn.execute(
        r#"INSERT INTO knowledge_documents(
               document_id,
               origin_type,
               source_kind,
               role,
               language,
               quality_score,
               title,
               summary,
               anchor_json,
               raw_text,
               normalized_text,
               created_at_ms,
               updated_at_ms,
               schema_version,
               normalization_version,
               segmentation_version,
               embedding_policy_version,
               retrieval_policy_version,
               last_indexed_at_ms
           ) VALUES (?1, ?2, 'summary', 'summary', NULL, 1.0, NULL, NULL, ?3, ?4, ?5, 1, ?6, ?7, ?8, ?9, ?10, ?11, NULL)"#,
        params![
            document_id,
            origin_type,
            anchor_json,
            raw,
            normalized,
            updated_at_ms,
            crate::knowledge::KNOWLEDGE_SCHEMA_VERSION,
            crate::knowledge::KNOWLEDGE_NORMALIZATION_VERSION,
            crate::knowledge::KNOWLEDGE_SEGMENTATION_VERSION,
            crate::knowledge::KNOWLEDGE_EMBEDDING_POLICY_VERSION,
            crate::knowledge::KNOWLEDGE_RETRIEVAL_POLICY_VERSION,
        ],
    )
    .expect("insert document");
}

#[test]
fn merge_contexts_prefers_knowledge_for_top_k_one() {
    let out = merge_knowledge_and_legacy_contexts(
        vec!["knowledge".to_string()],
        vec!["legacy".to_string()],
        1,
    );
    assert_eq!(out, vec!["knowledge".to_string()]);
}

#[test]
fn merge_contexts_falls_back_to_legacy_for_top_k_one() {
    let out = merge_knowledge_and_legacy_contexts(vec![], vec!["legacy".to_string()], 1);
    assert_eq!(out, vec!["legacy".to_string()]);
}

#[test]
fn merge_contexts_orders_knowledge_before_legacy() {
    let out = merge_knowledge_and_legacy_contexts(
        vec!["knowledge".to_string()],
        vec!["legacy".to_string()],
        2,
    );
    assert_eq!(out, vec!["knowledge".to_string(), "legacy".to_string()]);
}

#[test]
fn append_history_citation_avoids_leading_or_double_newlines() {
    let empty = append_message_citation_if_missing(String::new(), "abc");
    assert_eq!(empty, "[History](secondloop://message/abc)");

    let single = append_message_citation_if_missing("body".to_string(), "abc");
    assert_eq!(single, "body\n[History](secondloop://message/abc)");

    let trailing_newline = append_message_citation_if_missing("body\n".to_string(), "abc");
    assert_eq!(
        trailing_newline,
        "body\n[History](secondloop://message/abc)"
    );
}

#[test]
fn collect_compiled_page_contexts_planning_fallback_paginates_until_it_finds_allowed_memory() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    let key = [68u8; 32];
    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");

    insert_document(
        &conn,
        &key,
        "generated:misc:muted-first",
        "generated",
        30,
        Some(&conv.id),
        "Muted planning signal.",
    );
    insert_document(
        &conn,
        &key,
        "generated:misc:allowed-second",
        "generated",
        20,
        Some(&conv.id),
        "Allowed planning signal.",
    );
    crate::db::upsert_knowledge_memory_feedback(
        &conn,
        &key,
        "generated:misc:muted-first",
        Some(crate::knowledge::KnowledgeMemoryStatus::Confirmed),
        false,
        false,
        false,
        None,
        None,
    )
    .expect("mute first generated memory");

    let blocks = collect_compiled_page_contexts(&conn, &key, "plan my week", 1, Some(&conv.id))
        .expect("compiled page contexts");

    assert_eq!(blocks.len(), 1);
    assert_eq!(blocks[0].document_id, "generated:misc:allowed-second");
}

#[test]
fn collect_compiled_page_contexts_planning_fallback_skips_marked_inaccurate_memory() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    let key = [69u8; 32];
    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");

    insert_document(
        &conn,
        &key,
        "generated:misc:incorrect-first",
        "generated",
        30,
        Some(&conv.id),
        "Incorrect planning signal.",
    );
    insert_document(
        &conn,
        &key,
        "generated:misc:allowed-second",
        "generated",
        20,
        Some(&conv.id),
        "Allowed planning signal.",
    );
    crate::db::upsert_knowledge_memory_feedback(
        &conn,
        &key,
        "generated:misc:incorrect-first",
        Some(crate::knowledge::KnowledgeMemoryStatus::Confirmed),
        true,
        false,
        true,
        None,
        None,
    )
    .expect("mark generated memory inaccurate");

    let blocks = collect_compiled_page_contexts(&conn, &key, "plan my week", 1, Some(&conv.id))
        .expect("compiled page contexts");

    assert_eq!(blocks.len(), 1);
    assert_eq!(blocks[0].document_id, "generated:misc:allowed-second");
}

#[test]
fn collect_compiled_page_contexts_planning_fallback_respects_thread_scope() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    let key = [72u8; 32];
    let planning_conv =
        db::create_conversation(&conn, &key, "Planning").expect("planning conversation");
    let other_conv = db::create_conversation(&conn, &key, "Other").expect("other conversation");

    insert_document(
        &conn,
        &key,
        "generated:misc:other-thread-plan",
        "generated",
        20,
        Some(&other_conv.id),
        "Other thread planning signal.",
    );
    insert_document(
        &conn,
        &key,
        "generated:misc:this-thread-plan",
        "generated",
        10,
        Some(&planning_conv.id),
        "Current thread planning signal.",
    );

    let blocks =
        collect_compiled_page_contexts(&conn, &key, "plan my week", 1, Some(&planning_conv.id))
            .expect("compiled page contexts");

    assert_eq!(blocks.len(), 1);
    assert_eq!(blocks[0].document_id, "generated:misc:this-thread-plan");
    assert!(blocks[0]
        .rendered_text
        .contains("Current thread planning signal."));
    assert!(
        !blocks[0]
            .rendered_text
            .contains("Other thread planning signal."),
        "blocks: {blocks:?}"
    );
    assert!(
        blocks[0]
            .rendered_text
            .contains(&format!("conversation_id={}", planning_conv.id)),
        "blocks: {blocks:?}"
    );
}

#[test]
fn collect_compiled_page_contexts_planning_fallback_prioritizes_thread_documents_before_global() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    let key = [73u8; 32];
    let planning_conv =
        db::create_conversation(&conn, &key, "Planning").expect("planning conversation");

    insert_document(
        &conn,
        &key,
        "generated:misc:global-plan",
        "generated",
        30,
        None,
        "Global planning signal.",
    );
    insert_document(
        &conn,
        &key,
        "generated:misc:this-thread-plan",
        "generated",
        10,
        Some(&planning_conv.id),
        "Current thread planning signal.",
    );

    let blocks =
        collect_compiled_page_contexts(&conn, &key, "plan my week", 1, Some(&planning_conv.id))
            .expect("compiled page contexts");

    assert_eq!(blocks.len(), 1);
    assert_eq!(blocks[0].document_id, "generated:misc:this-thread-plan");
    assert!(
        !blocks[0].rendered_text.contains("Global planning signal."),
        "blocks: {blocks:?}"
    );
    assert!(blocks[0]
        .rendered_text
        .contains("Current thread planning signal."));
}

#[test]
fn filter_disabled_generated_memory_blocks_uses_bulk_feedback_and_keeps_real_documents() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    let key = [65u8; 32];

    crate::db::upsert_knowledge_memory_feedback(
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
    .expect("disable generated memory");
    crate::db::upsert_knowledge_memory_feedback(
        &conn,
        &key,
        "generated:profile:deleted",
        Some(crate::knowledge::KnowledgeMemoryStatus::Confirmed),
        true,
        true,
        false,
        None,
        None,
    )
    .expect("delete generated memory");

    let filtered = filter_disabled_generated_memory_blocks(
        &conn,
        &key,
        vec![
            knowledge::KnowledgeContextBlock {
                document_id: "generated:preference:visible".to_string(),
                unit_id: None,
                unit_kind: None,
                source_kind: knowledge::KnowledgeSourceKind::Summary,
                role: knowledge::KnowledgeRole::Summary,
                anchors: knowledge::KnowledgeAnchorSet::default(),
                score: 0.5,
                rendered_text: "visible".to_string(),
            },
            knowledge::KnowledgeContextBlock {
                document_id: "generated:preference:hidden".to_string(),
                unit_id: None,
                unit_kind: None,
                source_kind: knowledge::KnowledgeSourceKind::Summary,
                role: knowledge::KnowledgeRole::Summary,
                anchors: knowledge::KnowledgeAnchorSet::default(),
                score: 0.4,
                rendered_text: "hidden".to_string(),
            },
            knowledge::KnowledgeContextBlock {
                document_id: "generated:profile:deleted".to_string(),
                unit_id: None,
                unit_kind: None,
                source_kind: knowledge::KnowledgeSourceKind::Summary,
                role: knowledge::KnowledgeRole::Summary,
                anchors: knowledge::KnowledgeAnchorSet::default(),
                score: 0.3,
                rendered_text: "deleted".to_string(),
            },
            knowledge::KnowledgeContextBlock {
                document_id: "message:evidence-1".to_string(),
                unit_id: None,
                unit_kind: None,
                source_kind: knowledge::KnowledgeSourceKind::RawText,
                role: knowledge::KnowledgeRole::Evidence,
                anchors: knowledge::KnowledgeAnchorSet::default(),
                score: 0.2,
                rendered_text: "evidence".to_string(),
            },
        ],
    )
    .expect("filter blocks");

    let document_ids = filtered
        .iter()
        .map(|block| block.document_id.as_str())
        .collect::<Vec<_>>();
    assert_eq!(
        document_ids,
        vec!["generated:preference:visible", "message:evidence-1"]
    );
}

#[test]
fn filter_disabled_generated_memory_blocks_excludes_marked_inaccurate_generated_memory() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    let key = [70u8; 32];

    crate::db::upsert_knowledge_memory_feedback(
        &conn,
        &key,
        "generated:preference:incorrect",
        Some(crate::knowledge::KnowledgeMemoryStatus::Confirmed),
        true,
        false,
        true,
        None,
        None,
    )
    .expect("mark generated memory inaccurate");

    let filtered = filter_disabled_generated_memory_blocks(
        &conn,
        &key,
        vec![knowledge::KnowledgeContextBlock {
            document_id: "generated:preference:incorrect".to_string(),
            unit_id: None,
            unit_kind: None,
            source_kind: knowledge::KnowledgeSourceKind::Summary,
            role: knowledge::KnowledgeRole::Summary,
            anchors: knowledge::KnowledgeAnchorSet::default(),
            score: 0.5,
            rendered_text: "incorrect".to_string(),
        }],
    )
    .expect("filter blocks");

    assert!(filtered.is_empty(), "filtered: {filtered:?}");
}

#[test]
fn filter_disabled_generated_memory_blocks_excludes_documents_backed_by_muted_pages() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    let key = [66u8; 32];
    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");

    insert_document(
        &conn,
        &key,
        "generated:preference:response-language",
        "generated",
        1,
        Some(&conv.id),
        "User prefers responses in Chinese.",
    );
    crate::knowledge::compiler::refresh_knowledge_pages(&conn, &key).expect("refresh pages");
    crate::db::set_knowledge_page_answer_allowed(&conn, &key, "page:preferences", false, None)
        .expect("mute page");

    let filtered = filter_disabled_generated_memory_blocks(
        &conn,
        &key,
        vec![knowledge::KnowledgeContextBlock {
            document_id: "generated:preference:response-language".to_string(),
            unit_id: None,
            unit_kind: None,
            source_kind: knowledge::KnowledgeSourceKind::Summary,
            role: knowledge::KnowledgeRole::Summary,
            anchors: knowledge::KnowledgeAnchorSet::default(),
            score: 0.5,
            rendered_text: "preference".to_string(),
        }],
    )
    .expect("filter blocks");

    assert!(filtered.is_empty(), "filtered: {filtered:?}");
}

#[test]
fn filter_disabled_generated_memory_blocks_excludes_documents_backed_by_archived_or_removed_pages()
{
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    let key = [67u8; 32];
    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");

    insert_document(
        &conn,
        &key,
        "generated:preference:response-language",
        "generated",
        1,
        Some(&conv.id),
        "User prefers responses in Chinese.",
    );
    insert_document(
        &conn,
        &key,
        "generated:event:project-launch",
        "generated",
        2,
        Some(&conv.id),
        "The launch moved to next month.",
    );
    crate::knowledge::compiler::refresh_knowledge_pages(&conn, &key).expect("refresh pages");
    crate::db::archive_knowledge_page(&conn, &key, "page:preferences", None).expect("archive page");
    crate::db::remove_knowledge_page(&conn, &key, "page:recent-events", None).expect("remove page");

    let filtered = filter_disabled_generated_memory_blocks(
        &conn,
        &key,
        vec![
            knowledge::KnowledgeContextBlock {
                document_id: "generated:preference:response-language".to_string(),
                unit_id: None,
                unit_kind: None,
                source_kind: knowledge::KnowledgeSourceKind::Summary,
                role: knowledge::KnowledgeRole::Summary,
                anchors: knowledge::KnowledgeAnchorSet::default(),
                score: 0.5,
                rendered_text: "preference".to_string(),
            },
            knowledge::KnowledgeContextBlock {
                document_id: "generated:event:project-launch".to_string(),
                unit_id: None,
                unit_kind: None,
                source_kind: knowledge::KnowledgeSourceKind::Summary,
                role: knowledge::KnowledgeRole::Summary,
                anchors: knowledge::KnowledgeAnchorSet::default(),
                score: 0.4,
                rendered_text: "event".to_string(),
            },
        ],
    )
    .expect("filter blocks");

    assert!(filtered.is_empty(), "filtered: {filtered:?}");
}

#[test]
fn shared_generated_document_is_not_excluded_when_one_related_page_is_blocked() {
    let excluded = std::collections::HashSet::from([String::from("page:current-focus")]);

    assert!(!should_exclude_generated_document_for_page_policies(
        "generated:pattern:active-task-focus",
        &excluded,
    ));
}

#[test]
fn generated_document_is_excluded_when_all_related_pages_are_blocked() {
    let excluded = std::collections::HashSet::from([
        String::from("page:current-focus"),
        String::from("page:active-threads"),
    ]);

    assert!(should_exclude_generated_document_for_page_policies(
        "generated:pattern:active-task-focus",
        &excluded,
    ));
}

#[test]
fn generated_document_without_page_mapping_is_not_excluded_by_page_policies() {
    let excluded = std::collections::HashSet::from([String::from("page:preferences")]);

    assert!(!should_exclude_generated_document_for_page_policies(
        "generated:misc:allowed-second",
        &excluded,
    ));
}

#[test]
fn filter_disabled_generated_memory_blocks_keeps_shared_document_when_one_related_page_is_muted() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    let key = [71u8; 32];

    insert_document(
        &conn,
        &key,
        "generated:pattern:active-task-focus",
        "generated",
        1,
        None,
        "User is actively working across these task threads: Draft roadmap [in_progress].",
    );
    crate::knowledge::compiler::refresh_knowledge_pages(&conn, &key).expect("refresh pages");
    crate::db::set_knowledge_page_answer_allowed(&conn, &key, "page:active-threads", false, None)
        .expect("mute active threads page");

    let filtered = filter_disabled_generated_memory_blocks(
        &conn,
        &key,
        vec![knowledge::KnowledgeContextBlock {
            document_id: "generated:pattern:active-task-focus".to_string(),
            unit_id: None,
            unit_kind: None,
            source_kind: knowledge::KnowledgeSourceKind::Summary,
            role: knowledge::KnowledgeRole::Summary,
            anchors: knowledge::KnowledgeAnchorSet::default(),
            score: 0.5,
            rendered_text: "shared".to_string(),
        }],
    )
    .expect("filter blocks");

    assert_eq!(
        filtered
            .iter()
            .map(|block| block.document_id.as_str())
            .collect::<Vec<_>>(),
        vec!["generated:pattern:active-task-focus"],
        "filtered: {filtered:?}"
    );
}

#[test]
fn try_build_knowledge_context_entries_promotes_related_page_over_generated_document() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    let key = [73u8; 32];
    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");

    insert_document(
        &conn,
        &key,
        "generated:preference:response-language",
        "generated",
        10,
        Some(&conv.id),
        "User prefers responses in Chinese.",
    );
    crate::knowledge::compiler::refresh_knowledge_pages(&conn, &key).expect("refresh pages");
    crate::db::apply_knowledge_page_correction(
        &conn,
        &key,
        "page:preferences",
        None,
        Some("Reply in Mandarin by default.".to_string()),
        Some("Reply in Mandarin by default.".to_string()),
    )
    .expect("correct page");

    let entries = try_build_knowledge_context_entries(
        &conn,
        &key,
        "Chinese",
        4,
        Focus::AllMemories,
        &conv.id,
        None,
    )
    .expect("knowledge context entries");

    assert!(
        entries
            .iter()
            .any(|entry| entry.block.document_id == "page:preferences"),
        "entries: {entries:?}"
    );
    assert!(
        entries
            .iter()
            .all(|entry| entry.block.document_id != "generated:preference:response-language"),
        "entries: {entries:?}"
    );
}

#[test]
fn try_build_knowledge_contexts_tracks_real_documents_without_digest_ids() {
    let fixture = crate::knowledge::retrieval::test_support::seeded_fixture();

    let contexts = try_build_knowledge_contexts(
        &fixture.conn,
        &fixture.key,
        "Plan my week around the budget freeze in my usual style.",
        6,
        Focus::ThisThread,
        &fixture.conversation_id,
        None,
    )
    .expect("knowledge contexts");

    assert!(contexts
        .iter()
        .any(|ctx| ctx.to_lowercase().contains("session digest")));

    let usage_rows: i64 = fixture
        .conn
        .query_row("SELECT COUNT(*) FROM knowledge_document_usage", [], |row| {
            row.get(0)
        })
        .expect("usage count");
    assert!(usage_rows > 0);

    let digest_rows: i64 = fixture
        .conn
        .query_row(
            "SELECT COUNT(*) FROM knowledge_document_usage WHERE document_id LIKE 'generated:session-digest:%'",
            [],
            |row| row.get(0),
        )
        .expect("digest usage count");
    assert_eq!(digest_rows, 0);
}

#[test]
fn try_build_knowledge_contexts_only_tracks_page_usage_for_visible_page_blocks() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    let key = [92u8; 32];

    let conv = db::create_conversation(&conn, &key, "Planning").expect("conversation");
    db::insert_message(
        &conn,
        &key,
        &conv.id,
        "user",
        "Please answer in Chinese and keep responses short and practical.",
    )
    .expect("seed preference");
    crate::knowledge::ensure_knowledge_rebuild_requested(&conn).expect("request rebuild");
    crate::knowledge::process_pending_knowledge_index_jobs_active(&conn, &key, 256)
        .expect("process jobs");
    crate::knowledge::compiler::refresh_knowledge_pages(&conn, &key).expect("refresh pages");

    let entries = try_build_knowledge_context_entries(
        &conn,
        &key,
        "Plan my week around the budget freeze in my usual style.",
        1,
        Focus::ThisThread,
        &conv.id,
        None,
    )
    .expect("knowledge context entries");

    assert!(
        entries
            .iter()
            .all(|entry| !entry.block.document_id.starts_with("page:")),
        "entries: {entries:?}"
    );

    let last_used_at_ms: Option<i64> = conn
        .query_row(
            "SELECT last_used_at_ms FROM knowledge_pages WHERE page_id = 'page:preferences'",
            [],
            |row| row.get(0),
        )
        .expect("preferences page usage");
    assert_eq!(last_used_at_ms, None);
}

#[test]
fn try_build_knowledge_contexts_rebuilds_digest_with_generated_preferences() {
    let fixture = crate::knowledge::retrieval::test_support::seeded_fixture();
    insert_document(
        &fixture.conn,
        &fixture.key,
        "generated:preference:response-language",
        "generated",
        1,
        Some(&fixture.conversation_id),
        "User prefers responses in Chinese.",
    );

    let contexts = try_build_knowledge_contexts(
        &fixture.conn,
        &fixture.key,
        "Plan my week around the budget freeze in my usual style.",
        6,
        Focus::ThisThread,
        &fixture.conversation_id,
        None,
    )
    .expect("knowledge contexts");

    let digest = contexts
        .iter()
        .find(|ctx| ctx.to_lowercase().contains("session digest"))
        .expect("session digest context");
    assert!(digest.contains("User prefers responses in Chinese"));
}

#[test]
fn try_build_knowledge_contexts_keeps_global_preferences_visible_across_threads() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    let key = [62u8; 32];
    let preference_conv =
        db::create_conversation(&conn, &key, "Preferences").expect("preference conversation");
    let planning_conv =
        db::create_conversation(&conn, &key, "Planning").expect("planning conversation");

    db::insert_message(
        &conn,
        &key,
        &preference_conv.id,
        "user",
        "Please answer in Chinese and keep responses short and practical.",
    )
    .expect("preference");
    db::insert_message(
        &conn,
        &key,
        &planning_conv.id,
        "user",
        "I need to plan next week's launch checklist and follow-up tasks.",
    )
    .expect("planning source");

    crate::knowledge::ensure_knowledge_rebuild_requested(&conn).expect("request rebuild");
    crate::knowledge::process_pending_knowledge_index_jobs_active(&conn, &key, 256)
        .expect("process jobs");

    let contexts = try_build_knowledge_contexts(
        &conn,
        &key,
        "Plan my launch checklist for next week.",
        6,
        Focus::ThisThread,
        &planning_conv.id,
        None,
    )
    .expect("knowledge contexts");

    assert!(
        contexts
            .iter()
            .any(|ctx| ctx.contains("User prefers responses in Chinese.")),
        "contexts: {contexts:?}"
    );
}

#[test]
fn try_build_knowledge_contexts_keeps_global_profile_visible_across_threads() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    let key = [63u8; 32];
    let profile_conv =
        db::create_conversation(&conn, &key, "Profile").expect("profile conversation");
    let planning_conv =
        db::create_conversation(&conn, &key, "Planning").expect("planning conversation");

    db::insert_message(&conn, &key, &profile_conv.id, "user", "I am a developer.")
        .expect("profile");
    db::insert_message(
        &conn,
        &key,
        &planning_conv.id,
        "user",
        "I need to plan next week's launch checklist and follow-up tasks.",
    )
    .expect("planning source");

    crate::knowledge::ensure_knowledge_rebuild_requested(&conn).expect("request rebuild");
    crate::knowledge::process_pending_knowledge_index_jobs_active(&conn, &key, 256)
        .expect("process jobs");

    let contexts = try_build_knowledge_contexts(
        &conn,
        &key,
        "Plan my launch checklist for next week.",
        6,
        Focus::ThisThread,
        &planning_conv.id,
        None,
    )
    .expect("knowledge contexts");

    assert!(
        contexts.iter().any(|ctx| ctx.contains("I am a developer.")),
        "contexts: {contexts:?}"
    );
}

#[test]
fn planning_contexts_keep_retrieved_matches_visible_when_zero_score_pages_exist() {
    let fixture = crate::knowledge::retrieval::test_support::seeded_fixture();

    insert_document(
        &fixture.conn,
        &fixture.key,
        "generated:preference:response-language",
        "generated",
        1,
        Some(&fixture.conversation_id),
        "User prefers responses in Chinese.",
    );
    insert_document(
        &fixture.conn,
        &fixture.key,
        "generated:profile:occupation",
        "generated",
        2,
        None,
        "I am a developer.",
    );
    insert_document(
        &fixture.conn,
        &fixture.key,
        "generated:pattern:active-task-focus",
        "generated",
        3,
        Some(&fixture.conversation_id),
        "Current focus is migration cleanup.",
    );
    crate::knowledge::compiler::refresh_knowledge_pages(&fixture.conn, &fixture.key)
        .expect("refresh pages");

    let entries = try_build_knowledge_context_entries(
        &fixture.conn,
        &fixture.key,
        "Plan my next steps around the quarterly budget freeze.",
        3,
        Focus::ThisThread,
        &fixture.conversation_id,
        None,
    )
    .expect("knowledge context entries");

    let visible_non_page_ids = entries
        .iter()
        .filter(|entry| {
            !entry
                .block
                .document_id
                .starts_with("generated:session-digest:")
                && !entry.block.document_id.starts_with("page:")
        })
        .map(|entry| entry.block.document_id.as_str())
        .collect::<Vec<_>>();

    assert!(visible_non_page_ids.len() >= 2, "entries: {entries:?}");
}

#[test]
fn rebalance_planning_contexts_moves_evidence_without_duplication() {
    let mut blocks = vec![
        knowledge::KnowledgeContextBlock {
            document_id: "generated:session-digest:conv-1".to_string(),
            unit_id: None,
            unit_kind: None,
            source_kind: knowledge::KnowledgeSourceKind::Summary,
            role: knowledge::KnowledgeRole::Summary,
            anchors: knowledge::KnowledgeAnchorSet::default(),
            score: 0.9,
            rendered_text: "digest".to_string(),
        },
        knowledge::KnowledgeContextBlock {
            document_id: "generated:profile:self-profile".to_string(),
            unit_id: None,
            unit_kind: None,
            source_kind: knowledge::KnowledgeSourceKind::Summary,
            role: knowledge::KnowledgeRole::Summary,
            anchors: knowledge::KnowledgeAnchorSet::default(),
            score: 0.8,
            rendered_text: "profile".to_string(),
        },
        knowledge::KnowledgeContextBlock {
            document_id: "message:evidence-1".to_string(),
            unit_id: None,
            unit_kind: None,
            source_kind: knowledge::KnowledgeSourceKind::RawText,
            role: knowledge::KnowledgeRole::Evidence,
            anchors: knowledge::KnowledgeAnchorSet::default(),
            score: 0.7,
            rendered_text: "evidence".to_string(),
        },
    ];

    rebalance_planning_contexts(&mut blocks, 2);

    assert_eq!(
        blocks
            .iter()
            .filter(|block| block.document_id == "message:evidence-1")
            .count(),
        1
    );
    assert_eq!(blocks.len(), 3);
    assert_eq!(blocks[1].document_id, "message:evidence-1");
}
