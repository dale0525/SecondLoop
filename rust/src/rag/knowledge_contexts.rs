use anyhow::Result;
use rusqlite::Connection;

use crate::knowledge;
use crate::message_citations::append_message_citation_if_missing;

use super::Focus;

fn is_planning_or_summary_query(question: &str) -> bool {
    let normalized = question.trim().to_lowercase();
    normalized.contains("plan")
        || normalized.contains("agenda")
        || normalized.contains("schedule")
        || normalized.contains("week")
        || normalized.contains("summary")
        || normalized.contains("summarize")
        || question.contains("计划")
        || question.contains("安排")
        || question.contains("总结")
        || question.contains("整理")
}

fn collect_generated_preferred_contexts(
    conn: &Connection,
    key: &[u8; 32],
    conversation_scope: Option<&str>,
    top_k: usize,
) -> Result<Vec<knowledge::KnowledgeContextBlock>> {
    let mut out = Vec::<knowledge::KnowledgeContextBlock>::new();
    for document in knowledge::list_knowledge_documents(conn, key, 64, 0)? {
        if document.origin_type != knowledge::KnowledgeOriginType::Generated {
            continue;
        }
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
            score: 1.0,
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
            break;
        }
    }
    Ok(out)
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

    let mut blocks = if is_planning_or_summary_query(question) {
        collect_generated_preferred_contexts(conn, key, conversation_scope.as_deref(), top_k)?
    } else {
        Vec::new()
    };
    let mut retrieved = knowledge::retrieve_context_blocks(conn, key, &request)?;
    blocks.append(&mut retrieved);

    let mut seen_document_ids = std::collections::HashSet::<String>::new();
    blocks.retain(|block| seen_document_ids.insert(block.document_id.clone()));
    if blocks.len() > top_k.max(1) {
        blocks.truncate(top_k.max(1));
    }

    let used_document_ids = blocks
        .iter()
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
    use super::merge_knowledge_and_legacy_contexts;
    use crate::message_citations::append_message_citation_if_missing;

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
}
