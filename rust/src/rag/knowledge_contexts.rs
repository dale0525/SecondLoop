use anyhow::Result;
use rusqlite::Connection;

const FORCED_GENERATED_CONTEXT_SCORE: f64 = 0.0;

use crate::knowledge;
use crate::message_citations::append_message_citation_if_missing;

use super::Focus;

fn collect_generated_preferred_contexts(
    conn: &Connection,
    key: &[u8; 32],
    conversation_scope: Option<&str>,
    top_k: usize,
) -> Result<Vec<knowledge::KnowledgeContextBlock>> {
    let mut out = Vec::<knowledge::KnowledgeContextBlock>::new();
    let page_size = 128usize;
    let mut offset = 0usize;
    loop {
        let documents = knowledge::list_knowledge_documents_by_origin(
            conn,
            key,
            knowledge::KnowledgeOriginType::Generated,
            page_size,
            offset,
        )?;
        if documents.is_empty() {
            break;
        }
        for document in documents {
            if let Some(expected) = conversation_scope {
                if let Some(actual) = document.anchors.conversation_id.as_deref() {
                    if actual != expected {
                        continue;
                    }
                }
            }
            let body = if document.raw_text.trim().is_empty() {
                document.normalized_text.trim()
            } else {
                document.raw_text.trim()
            };
            if body.is_empty() {
                continue;
            }
            out.push(knowledge::KnowledgeContextBlock {
                document_id: document.document_id.clone(),
                unit_id: None,
                unit_kind: None,
                source_kind: document.source_kind,
                role: document.role,
                anchors: document.anchors.clone(),
                score: FORCED_GENERATED_CONTEXT_SCORE,
                rendered_text: format!(
                    "{}\n[knowledge layer=document source=summary role=summary]\n{}",
                    if let Some(conversation_id) = document.anchors.conversation_id.as_deref() {
                        format!("conversation_id={conversation_id}")
                    } else {
                        "generated_memory=global".to_string()
                    },
                    body
                ),
            });
            if out.len() >= top_k.max(1) {
                return Ok(out);
            }
        }
        offset += page_size;
    }
    Ok(out)
}

fn rebalance_planning_contexts(
    blocks: &mut Vec<knowledge::KnowledgeContextBlock>,
    max_items: usize,
) {
    let visible_len = blocks.len().min(max_items.max(1));
    if visible_len == 0 {
        return;
    }
    if blocks
        .iter()
        .take(visible_len)
        .any(|block| block.role == knowledge::KnowledgeRole::Evidence)
    {
        return;
    }
    let Some(evidence_index) = blocks
        .iter()
        .position(|block| block.role == knowledge::KnowledgeRole::Evidence)
    else {
        return;
    };
    let evidence = blocks.remove(evidence_index);
    let adjusted_visible_len = blocks.len().min(max_items.max(1));
    let replace_index = (0..adjusted_visible_len)
        .rev()
        .find(|index| {
            let block = &blocks[*index];
            !block.document_id.starts_with("generated:session-digest:")
        })
        .unwrap_or_else(|| adjusted_visible_len.saturating_sub(1));
    blocks.insert(replace_index, evidence);
}

pub(super) fn try_build_knowledge_contexts(
    conn: &Connection,
    key: &[u8; 32],
    question: &str,
    top_k: usize,
    focus: Focus,
    conversation_id: &str,
    time_window: Option<(i64, i64)>,
) -> Result<Vec<String>> {
    if top_k == 0 {
        return Ok(Vec::new());
    }

    let conversation_scope = match focus {
        Focus::AllMemories => None,
        Focus::ThisThread => Some(conversation_id.to_string()),
    };
    let mut request = knowledge::normalize_retrieval_request(
        question,
        conversation_scope.clone(),
        None,
        Some(top_k.max(1)),
        Some(1200),
        None,
    );
    if let Some((start_ms, end_ms)) = time_window {
        request.time_start_ms = Some(start_ms);
        request.time_end_ms = Some(end_ms);
    }

    let is_planning_query = knowledge::session_digest::is_planning_or_summary_query(question);
    let mut blocks = if is_planning_query {
        collect_generated_preferred_contexts(conn, key, conversation_scope.as_deref(), top_k)?
    } else {
        Vec::new()
    };
    let mut retrieved = knowledge::retrieve_context_blocks(conn, key, &request)?;
    blocks.append(&mut retrieved);

    if is_planning_query {
        blocks.retain(|block| !block.document_id.starts_with("generated:session-digest:"));
        if let Some(digest) = knowledge::session_digest::build_digest_from_blocks(
            question,
            conversation_scope.as_deref(),
            &blocks,
        ) {
            blocks.insert(0, digest);
        }
    }
    if is_planning_query {
        rebalance_planning_contexts(&mut blocks, top_k.max(1));
    }

    let mut seen_document_ids = std::collections::HashSet::<String>::new();
    blocks.retain(|block| seen_document_ids.insert(block.document_id.clone()));
    if blocks.len() > top_k.max(1) {
        blocks.truncate(top_k.max(1));
    }

    let used_document_ids = blocks
        .iter()
        .filter(|block| !block.document_id.starts_with("generated:session-digest:"))
        .map(|block| block.document_id.clone())
        .collect::<Vec<_>>();
    let _ = crate::db::touch_knowledge_documents_usage(
        conn,
        &used_document_ids,
        crate::knowledge::usage::now_ms(),
    );

    Ok(blocks
        .into_iter()
        .map(|block| {
            let rendered = block.rendered_text;
            match block.anchors.message_id.as_deref() {
                Some(message_id) => append_message_citation_if_missing(rendered, message_id),
                None => rendered,
            }
        })
        .collect())
}

pub(super) fn merge_knowledge_and_legacy_contexts(
    knowledge_contexts: Vec<String>,
    legacy_contexts: Vec<String>,
    top_k: usize,
) -> Vec<String> {
    let max_items = top_k.max(1);
    if max_items == 1 {
        if let Some(ctx) = knowledge_contexts
            .into_iter()
            .find(|ctx| !ctx.trim().is_empty())
        {
            return vec![ctx];
        }
        if let Some(ctx) = legacy_contexts
            .into_iter()
            .find(|ctx| !ctx.trim().is_empty())
        {
            return vec![ctx];
        }
        return Vec::new();
    }

    let mut out: Vec<String> = Vec::new();
    let mut seen: std::collections::HashSet<String> = std::collections::HashSet::new();

    for ctx in knowledge_contexts {
        if out.len() >= max_items {
            break;
        }
        if ctx.trim().is_empty() {
            continue;
        }
        if seen.insert(ctx.clone()) {
            out.push(ctx);
        }
    }

    for ctx in legacy_contexts {
        if out.len() >= max_items {
            break;
        }
        if ctx.trim().is_empty() {
            continue;
        }
        if seen.insert(ctx.clone()) {
            out.push(ctx);
        }
    }

    out
}

#[cfg(test)]
mod tests {
    use super::{
        collect_generated_preferred_contexts, merge_knowledge_and_legacy_contexts,
        rebalance_planning_contexts, try_build_knowledge_contexts,
    };
    use crate::db;
    use crate::knowledge;
    use crate::message_citations::append_message_citation_if_missing;
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
    fn collect_generated_preferred_contexts_pages_past_first_64_documents() {
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

        let blocks = collect_generated_preferred_contexts(&conn, &key, Some(&conv.id), 4)
            .expect("generated preferred contexts");

        assert!(blocks
            .iter()
            .any(|block| { block.document_id == "generated:preference:response-language" }));
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
}
