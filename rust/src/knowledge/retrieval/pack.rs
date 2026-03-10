use crate::knowledge::embedding_batch::estimate_tokens;
use crate::knowledge::KnowledgeContextBlock;

use super::query::NormalizedRetrievalRequest;
use super::{anchor_summary, KnowledgeCandidate};

fn enum_name<T: serde::Serialize>(value: &T) -> String {
    serde_json::to_string(value)
        .unwrap_or_else(|_| "\"unknown\"".to_string())
        .trim_matches('"')
        .to_string()
}

fn truncate_to_token_budget(text: &str, token_budget: usize) -> String {
    let words = text.split_whitespace().collect::<Vec<_>>();
    if words.len() <= token_budget.max(1) {
        return words.join(" ");
    }
    let take = token_budget.saturating_sub(1).max(1);
    let words = words.into_iter().take(take).collect::<Vec<_>>();
    let truncated = words.join(" ");
    if truncated.len() < text.len() {
        format!("{truncated} …")
    } else {
        truncated
    }
}

pub(crate) fn pack_context_blocks(
    request: &NormalizedRetrievalRequest,
    candidates: &[KnowledgeCandidate],
) -> Vec<KnowledgeContextBlock> {
    let mut used_tokens = 0usize;
    let mut out = Vec::<KnowledgeContextBlock>::new();

    for candidate in candidates {
        let body = if candidate.raw_text.trim().is_empty() {
            candidate.normalized_text.clone()
        } else {
            candidate.raw_text.clone()
        };
        if body.trim().is_empty() {
            continue;
        }
        let header = format!(
            "[knowledge layer={layer} source={source} role={role}]",
            layer = enum_name(&candidate.layer),
            source = enum_name(&candidate.source_kind()),
            role = enum_name(&candidate.role),
        );
        let anchors = anchor_summary(candidate.anchors());
        let mut rendered_text = format!("{anchors}\n{header}\n{}", body.trim());
        let mut block_tokens = estimate_tokens(&rendered_text);
        if block_tokens == 0 {
            continue;
        }
        if used_tokens + block_tokens > request.token_budget {
            if out.is_empty() {
                let prefix = format!("{anchors}\n{header}");
                let prefix_tokens = estimate_tokens(&prefix);
                let remaining_tokens = request.token_budget.saturating_sub(prefix_tokens);
                rendered_text = if remaining_tokens == 0 {
                    truncate_to_token_budget(&prefix, request.token_budget)
                } else {
                    format!(
                        "{prefix}\n{}",
                        truncate_to_token_budget(body.trim(), remaining_tokens)
                    )
                };
                block_tokens = estimate_tokens(&rendered_text);
            } else {
                break;
            }
        }
        if used_tokens + block_tokens > request.token_budget {
            continue;
        }
        used_tokens += block_tokens;
        out.push(KnowledgeContextBlock {
            document_id: candidate.document.document_id.clone(),
            unit_id: candidate.unit_id.clone(),
            unit_kind: candidate.unit_kind,
            source_kind: candidate.source_kind(),
            role: candidate.role,
            anchors: candidate.anchors().clone(),
            score: candidate.score,
            rendered_text,
        });
    }

    out
}
