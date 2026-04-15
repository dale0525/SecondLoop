use crate::db;
use crate::rag::knowledge_contexts::{
    collect_compiled_page_contexts, collect_matching_page_context_blocks,
};
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
fn collect_compiled_page_contexts_reads_preferences_page() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    let key = [61u8; 32];
    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");

    for index in 0..64 {
        insert_document(
            &conn,
            &key,
            &format!("message:seed-{index:03}"),
            "message",
            10_000 - index,
            Some(&conv.id),
            "source memory",
        );
    }
    insert_document(
        &conn,
        &key,
        "generated:preference:response-language",
        "generated",
        1,
        Some(&conv.id),
        "User prefers responses in Chinese.",
    );

    let blocks = collect_compiled_page_contexts(&conn, &key, "plan my week", 4, Some(&conv.id))
        .expect("compiled page contexts");

    assert!(blocks
        .iter()
        .any(|block| block.document_id == "page:preferences"));
    assert!(blocks
        .iter()
        .any(|block| block.rendered_text.contains("source=wiki_page")));
}

#[test]
fn collect_compiled_page_contexts_skips_deleted_generated_documents() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    let key = [64u8; 32];
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
    crate::db::upsert_knowledge_memory_feedback(
        &conn,
        &key,
        "generated:preference:response-language",
        Some(crate::knowledge::KnowledgeMemoryStatus::Confirmed),
        true,
        true,
        false,
        None,
        None,
    )
    .expect("mark deleted");

    let blocks = collect_compiled_page_contexts(&conn, &key, "plan my week", 4, Some(&conv.id))
        .expect("compiled page contexts");

    assert!(
        blocks
            .iter()
            .all(|block| block.document_id != "page:preferences"),
        "blocks: {blocks:?}"
    );
}

#[test]
fn collect_compiled_page_contexts_matches_keywords_found_only_in_page_body() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    let key = [94u8; 32];
    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");

    insert_document(
        &conn,
        &key,
        "generated:preference:response-language",
        "generated",
        10,
        Some(&conv.id),
        "User prefers bilingual replies.",
    );
    crate::knowledge::compiler::refresh_knowledge_pages(&conn, &key).expect("refresh pages");
    crate::db::apply_knowledge_page_correction(
        &conn,
        &key,
        "page:preferences",
        None,
        Some("Language guidance stays generic.".to_string()),
        Some("Reply in Mandarin when the user asks for Chinese.".to_string()),
    )
    .expect("correct page");

    let blocks = collect_compiled_page_contexts(&conn, &key, "Mandarin", 4, Some(&conv.id))
        .expect("compiled page contexts");

    assert!(
        blocks
            .iter()
            .any(|block| block.document_id == "page:preferences"),
        "blocks: {blocks:?}"
    );
}

#[test]
fn collect_compiled_page_contexts_matches_cjk_query_against_page_body() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    let key = [96u8; 32];
    let conv = db::create_conversation(&conn, &key, "Inbox").expect("conversation");

    insert_document(
        &conn,
        &key,
        "generated:preference:response-language",
        "generated",
        10,
        Some(&conv.id),
        "User prefers concise replies.",
    );
    crate::knowledge::compiler::refresh_knowledge_pages(&conn, &key).expect("refresh pages");
    crate::db::apply_knowledge_page_correction(
        &conn,
        &key,
        "page:preferences",
        None,
        Some("语言偏好保持最新。".to_string()),
        Some("回答时使用中文，并保持简洁。".to_string()),
    )
    .expect("correct page");

    let blocks = collect_compiled_page_contexts(&conn, &key, "请用中文回复", 4, Some(&conv.id))
        .expect("compiled page contexts");

    assert!(
        blocks
            .iter()
            .any(|block| block.document_id == "page:preferences"),
        "blocks: {blocks:?}"
    );
}

#[test]
fn collect_compiled_page_contexts_matches_single_cjk_character_query() {
    let dir = tempfile::tempdir().expect("tempdir");
    let conn = db::open(dir.path()).expect("open");
    let key = [96u8; 32];

    insert_document(
        &conn,
        &key,
        "generated:pattern:cat-habit",
        "generated",
        1,
        None,
        "猫咪相关偏好与习惯。",
    );
    crate::knowledge::compiler::refresh_knowledge_pages(&conn, &key).expect("refresh pages");

    let blocks =
        collect_compiled_page_contexts(&conn, &key, "猫", 4, None).expect("compiled page contexts");

    assert!(
        blocks
            .iter()
            .any(|block| block.document_id == "page:topics:cat_habit"),
        "blocks: {blocks:?}"
    );
}

#[test]
fn collect_matching_page_context_blocks_keeps_late_candidates_available_for_reranking() {
    let mut inspected_bodies = Vec::<String>::new();
    let mut loaded_pages = Vec::<String>::new();
    let candidate_summaries = vec![
        (_summary("page:match", "Alpha", "Generic summary"), 1),
        (_summary("page:2", "Page 2", "Generic summary"), 0),
        (_summary("page:3", "Page 3", "Generic summary"), 0),
        (_summary("page:4", "Page 4", "Generic summary"), 0),
        (_summary("page:5", "Page 5", "Generic summary"), 0),
        (_summary("page:6", "Page 6", "Generic summary"), 0),
        (_summary("page:7", "Page 7", "Generic summary"), 0),
        (_summary("page:8", "Page 8", "Generic summary"), 0),
        (_summary("page:late", "Late Page", "Generic summary"), 0),
    ];

    let blocks = collect_matching_page_context_blocks(
        "Alpha",
        1,
        false,
        candidate_summaries,
        |page_id| {
            inspected_bodies.push(page_id.to_string());
            Some(if page_id == "page:match" {
                "Generic body".to_string()
            } else {
                "Generic body".to_string()
            })
        },
        |page_id| {
            loaded_pages.push(page_id.to_string());
            Some(if page_id == "page:match" {
                _page(page_id, "Alpha summary", "Generic body")
            } else {
                _page(page_id, "Generic summary", "Generic body")
            })
        },
    );

    assert_eq!(
        blocks
            .iter()
            .map(|block| block.document_id.as_str())
            .collect::<Vec<_>>(),
        vec!["page:match"]
    );
    assert_eq!(inspected_bodies.len(), 9);
    assert!(inspected_bodies
        .iter()
        .any(|page_id| page_id == "page:late"));
    assert_eq!(loaded_pages, vec!["page:match"]);
}

#[test]
fn collect_matching_page_context_blocks_falls_back_to_late_body_match_when_needed() {
    let mut inspected_bodies = Vec::<String>::new();
    let mut loaded_pages = Vec::<String>::new();
    let candidate_summaries = vec![
        (_summary("page:1", "Page 1", "Generic summary"), 0),
        (_summary("page:2", "Page 2", "Generic summary"), 0),
        (_summary("page:3", "Page 3", "Generic summary"), 0),
        (_summary("page:4", "Page 4", "Generic summary"), 0),
        (_summary("page:5", "Page 5", "Generic summary"), 0),
        (_summary("page:6", "Page 6", "Generic summary"), 0),
        (_summary("page:7", "Page 7", "Generic summary"), 0),
        (_summary("page:8", "Page 8", "Generic summary"), 0),
        (_summary("page:late", "Late Page", "Generic summary"), 0),
    ];

    let blocks = collect_matching_page_context_blocks(
        "Mandarin",
        1,
        false,
        candidate_summaries,
        |page_id| {
            inspected_bodies.push(page_id.to_string());
            Some(if page_id == "page:late" {
                "Reply in Mandarin when asked.".to_string()
            } else {
                "Generic body".to_string()
            })
        },
        |page_id| {
            loaded_pages.push(page_id.to_string());
            Some(_page(page_id, "Generic summary", "Generic body"))
        },
    );

    assert_eq!(
        blocks
            .iter()
            .map(|block| block.document_id.as_str())
            .collect::<Vec<_>>(),
        vec!["page:late"]
    );
    assert_eq!(inspected_bodies.len(), 9);
    assert_eq!(loaded_pages, vec!["page:late"]);
}

#[test]
fn collect_matching_page_context_blocks_keeps_searching_when_early_match_is_weaker() {
    let mut inspected_bodies = Vec::<String>::new();
    let mut loaded_pages = Vec::<String>::new();
    let candidate_summaries = vec![
        (_summary("page:weak", "Weak Page", "Mandarin"), 1),
        (_summary("page:2", "Page 2", "Generic summary"), 0),
        (_summary("page:3", "Page 3", "Generic summary"), 0),
        (_summary("page:4", "Page 4", "Generic summary"), 0),
        (_summary("page:5", "Page 5", "Generic summary"), 0),
        (_summary("page:6", "Page 6", "Generic summary"), 0),
        (_summary("page:7", "Page 7", "Generic summary"), 0),
        (_summary("page:8", "Page 8", "Generic summary"), 0),
        (_summary("page:late", "Late Page", "Generic summary"), 0),
    ];

    let blocks = collect_matching_page_context_blocks(
        "Mandarin Chinese",
        1,
        false,
        candidate_summaries,
        |page_id| {
            inspected_bodies.push(page_id.to_string());
            Some(if page_id == "page:weak" {
                "Generic body".to_string()
            } else if page_id == "page:late" {
                "Reply in Mandarin Chinese.".to_string()
            } else {
                "Generic body".to_string()
            })
        },
        |page_id| {
            loaded_pages.push(page_id.to_string());
            Some(if page_id == "page:weak" {
                _page(page_id, "Mandarin", "Generic body")
            } else if page_id == "page:late" {
                _page(page_id, "Generic summary", "Reply in Mandarin Chinese.")
            } else {
                _page(page_id, "Generic summary", "Generic body")
            })
        },
    );

    assert_eq!(
        blocks
            .iter()
            .map(|block| block.document_id.as_str())
            .collect::<Vec<_>>(),
        vec!["page:late"]
    );
    assert_eq!(inspected_bodies.len(), 9);
    assert_eq!(loaded_pages, vec!["page:late"]);
}

#[test]
fn collect_matching_page_context_blocks_scans_past_first_window_for_stronger_late_body_match() {
    let mut inspected_bodies = Vec::<String>::new();
    let mut loaded_pages = Vec::<String>::new();
    let mut candidate_summaries = vec![(_summary("page:weak", "Weak Page", "Mandarin"), 1)];
    for index in 2..=12 {
        candidate_summaries.push((
            _summary(
                &format!("page:{index}"),
                &format!("Page {index}"),
                "Generic summary",
            ),
            0,
        ));
    }
    candidate_summaries.push((_summary("page:late", "Late Page", "Generic summary"), 0));

    let blocks = collect_matching_page_context_blocks(
        "Mandarin Chinese",
        1,
        false,
        candidate_summaries,
        |page_id| {
            inspected_bodies.push(page_id.to_string());
            Some(if page_id == "page:weak" {
                "Generic body".to_string()
            } else if page_id == "page:late" {
                "Reply in Mandarin Chinese.".to_string()
            } else {
                "Generic body".to_string()
            })
        },
        |page_id| {
            loaded_pages.push(page_id.to_string());
            Some(if page_id == "page:weak" {
                _page(page_id, "Mandarin", "Generic body")
            } else if page_id == "page:late" {
                _page(page_id, "Generic summary", "Reply in Mandarin Chinese.")
            } else {
                _page(page_id, "Generic summary", "Generic body")
            })
        },
    );

    assert_eq!(
        blocks
            .iter()
            .map(|block| block.document_id.as_str())
            .collect::<Vec<_>>(),
        vec!["page:late"]
    );
    assert_eq!(inspected_bodies.len(), 13);
    assert_eq!(loaded_pages, vec!["page:late"]);
}

#[test]
fn collect_matching_page_context_blocks_preserves_incoming_rank_for_tied_scores() {
    let mut loaded_pages = Vec::<String>::new();
    let candidate_summaries = vec![
        (_summary("page:zeta", "Zeta Page", "Mandarin"), 1),
        (_summary("page:alpha", "Alpha Page", "Mandarin"), 1),
    ];

    let blocks = collect_matching_page_context_blocks(
        "Mandarin",
        1,
        false,
        candidate_summaries,
        |_| Some("Generic body".to_string()),
        |page_id| {
            loaded_pages.push(page_id.to_string());
            Some(_page(page_id, "Mandarin", "Generic body"))
        },
    );

    assert_eq!(
        blocks
            .iter()
            .map(|block| block.document_id.as_str())
            .collect::<Vec<_>>(),
        vec!["page:zeta"]
    );
    assert_eq!(loaded_pages, vec!["page:zeta"]);
}

#[test]
fn collect_matching_page_context_blocks_planning_queries_still_search_late_candidates() {
    let mut inspected_bodies = Vec::<String>::new();
    let mut loaded_pages = Vec::<String>::new();
    let candidate_summaries = vec![
        (_summary("page:1", "Page 1", "Generic summary"), 0),
        (_summary("page:2", "Page 2", "Generic summary"), 0),
        (_summary("page:3", "Page 3", "Generic summary"), 0),
        (_summary("page:4", "Page 4", "Generic summary"), 0),
        (_summary("page:5", "Page 5", "Generic summary"), 0),
        (_summary("page:6", "Page 6", "Generic summary"), 0),
        (_summary("page:7", "Page 7", "Generic summary"), 0),
        (_summary("page:8", "Page 8", "Generic summary"), 0),
        (_summary("page:late", "Late Page", "Generic summary"), 0),
    ];

    let blocks = collect_matching_page_context_blocks(
        "plan my week with Mandarin practice",
        1,
        true,
        candidate_summaries,
        |page_id| {
            inspected_bodies.push(page_id.to_string());
            Some(if page_id == "page:late" {
                "Mandarin practice is still active.".to_string()
            } else {
                "Generic body".to_string()
            })
        },
        |page_id| {
            loaded_pages.push(page_id.to_string());
            Some(_page(page_id, "Generic summary", "Generic body"))
        },
    );

    assert_eq!(
        blocks
            .iter()
            .map(|block| block.document_id.as_str())
            .collect::<Vec<_>>(),
        vec!["page:late"]
    );
    assert_eq!(inspected_bodies.len(), 9);
    assert_eq!(loaded_pages, vec!["page:late"]);
}

#[test]
fn collect_matching_page_context_blocks_scans_all_candidate_bodies_but_only_loads_finalists() {
    let mut inspected_bodies = Vec::<String>::new();
    let mut loaded_pages = Vec::<String>::new();
    let candidate_summaries = (0..20)
        .map(|index| {
            let page_id = format!("page:{index}");
            let score = match index {
                3 => 3,
                11 => 2,
                _ => 0,
            };
            (
                _summary(&page_id, &format!("Page {index}"), "Generic summary"),
                score,
            )
        })
        .collect::<Vec<_>>();

    let blocks = collect_matching_page_context_blocks(
        "Mandarin project notes",
        2,
        false,
        candidate_summaries,
        |page_id| {
            inspected_bodies.push(page_id.to_string());
            Some(match page_id {
                "page:3" => "Mandarin project notes and vocabulary".to_string(),
                "page:11" => "Mandarin notes".to_string(),
                _ => "Generic body".to_string(),
            })
        },
        |page_id| {
            loaded_pages.push(page_id.to_string());
            Some(_page(page_id, "Generic summary", "Generic body"))
        },
    );

    assert_eq!(
        blocks
            .iter()
            .map(|block| block.document_id.as_str())
            .collect::<Vec<_>>(),
        vec!["page:3", "page:11"]
    );
    assert_eq!(inspected_bodies.len(), 20);
    assert_eq!(loaded_pages, vec!["page:3", "page:11"]);
}

#[test]
fn collect_matching_page_context_blocks_scans_large_candidate_sets_globally() {
    let mut inspected_bodies = Vec::<String>::new();
    let mut loaded_pages = Vec::<String>::new();
    let candidate_summaries = (0..64)
        .map(|index| {
            let page_id = format!("page:{index}");
            let score = match index {
                3 => 3,
                11 => 2,
                _ => 0,
            };
            (
                _summary(&page_id, &format!("Page {index}"), "Generic summary"),
                score,
            )
        })
        .collect::<Vec<_>>();

    let blocks = collect_matching_page_context_blocks(
        "Mandarin project notes",
        2,
        false,
        candidate_summaries,
        |page_id| {
            inspected_bodies.push(page_id.to_string());
            Some(match page_id {
                "page:3" => "Mandarin project notes and vocabulary".to_string(),
                "page:11" => "Mandarin notes".to_string(),
                _ => "Generic body".to_string(),
            })
        },
        |page_id| {
            loaded_pages.push(page_id.to_string());
            Some(_page(page_id, "Generic summary", "Generic body"))
        },
    );

    assert_eq!(
        blocks
            .iter()
            .map(|block| block.document_id.as_str())
            .collect::<Vec<_>>(),
        vec!["page:3", "page:11"]
    );
    assert_eq!(inspected_bodies.len(), 64);
    assert_eq!(loaded_pages, vec!["page:3", "page:11"]);
}

#[test]
fn collect_matching_page_context_blocks_keeps_scanning_large_candidate_sets_until_late_match_found()
{
    let mut inspected_bodies = Vec::<String>::new();
    let mut loaded_pages = Vec::<String>::new();
    let candidate_summaries = (0..64)
        .map(|index| {
            let page_id = format!("page:{index}");
            (
                _summary(&page_id, &format!("Page {index}"), "Generic summary"),
                0,
            )
        })
        .collect::<Vec<_>>();

    let blocks = collect_matching_page_context_blocks(
        "Mandarin project notes",
        1,
        false,
        candidate_summaries,
        |page_id| {
            inspected_bodies.push(page_id.to_string());
            Some(match page_id {
                "page:27" => "Mandarin project notes and vocabulary".to_string(),
                _ => "Generic body".to_string(),
            })
        },
        |page_id| {
            loaded_pages.push(page_id.to_string());
            Some(_page(page_id, "Generic summary", "Generic body"))
        },
    );

    assert_eq!(
        blocks
            .iter()
            .map(|block| block.document_id.as_str())
            .collect::<Vec<_>>(),
        vec!["page:27"]
    );
    assert!(
        inspected_bodies.len() > 12,
        "inspected_bodies: {inspected_bodies:?}"
    );
    assert!(
        inspected_bodies.iter().any(|page_id| page_id == "page:27"),
        "inspected_bodies: {inspected_bodies:?}"
    );
    assert_eq!(loaded_pages, vec!["page:27"]);
}

fn _summary(
    page_id: &str,
    title: &str,
    current_summary: &str,
) -> crate::knowledge::KnowledgePageSummary {
    crate::knowledge::KnowledgePageSummary {
        page_id: page_id.to_string(),
        page_type: crate::knowledge::KnowledgePageType::Topics,
        title: title.to_string(),
        current_summary: current_summary.to_string(),
        state: crate::knowledge::KnowledgePageState::Active,
        answer_policy: crate::knowledge::KnowledgeAnswerPolicy {
            default_allowed: true,
            requires_temporal_framing: false,
        },
        updated_at_ms: 1,
        last_used_at_ms: Some(1),
        source_count: 1,
        conflict_count: 0,
        human_corrected: false,
        tags: Vec::new(),
        primary_evidence_ids: Vec::new(),
    }
}

fn _page(
    page_id: &str,
    current_summary: &str,
    current_body: &str,
) -> crate::knowledge::KnowledgePage {
    crate::knowledge::KnowledgePage {
        page_id: page_id.to_string(),
        page_type: crate::knowledge::KnowledgePageType::Topics,
        title: format!("Title for {page_id}"),
        current_summary: current_summary.to_string(),
        current_body: current_body.to_string(),
        state: crate::knowledge::KnowledgePageState::Active,
        answer_policy: crate::knowledge::KnowledgeAnswerPolicy {
            default_allowed: true,
            requires_temporal_framing: false,
        },
        confidence_level: 1.0,
        created_at_ms: 1,
        updated_at_ms: 1,
        last_used_at_ms: Some(1),
        source_count: 1,
        conflict_count: 0,
        human_corrected: false,
        tags: Vec::new(),
        primary_evidence_ids: Vec::new(),
        related_page_ids: Vec::new(),
    }
}
