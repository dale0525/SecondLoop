use anyhow::Result;
use rusqlite::Connection;

use crate::knowledge;

use super::Focus;

fn append_history_citation_if_missing(mut rendered: String, message_id: &str) -> String {
    let trimmed = message_id.trim();
    if trimmed.is_empty() {
        return rendered;
    }

    let citation = format!("[History](secondloop://message/{trimmed})");
    if rendered.contains(&citation) {
        return rendered;
    }
    if !rendered.is_empty() && !rendered.ends_with('\n') {
        rendered.push('\n');
    }
    rendered.push_str(&citation);
    rendered
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
        conversation_scope,
        None,
        Some(top_k.max(1)),
        Some(1200),
        None,
    );
    if let Some((start_ms, end_ms)) = time_window {
        request.time_start_ms = Some(start_ms);
        request.time_end_ms = Some(end_ms);
    }

    Ok(knowledge::retrieve_context_blocks(conn, key, &request)?
        .into_iter()
        .map(|block| {
            let rendered = block.rendered_text;
            match block.anchors.message_id.as_deref() {
                Some(message_id) => append_history_citation_if_missing(rendered, message_id),
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
    use super::{append_history_citation_if_missing, merge_knowledge_and_legacy_contexts};

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
        let empty = append_history_citation_if_missing(String::new(), "abc");
        assert_eq!(empty, "[History](secondloop://message/abc)");

        let single = append_history_citation_if_missing("body".to_string(), "abc");
        assert_eq!(single, "body\n[History](secondloop://message/abc)");

        let trailing_newline = append_history_citation_if_missing("body\n".to_string(), "abc");
        assert_eq!(
            trailing_newline,
            "body\n[History](secondloop://message/abc)"
        );
    }
}
