use crate::knowledge::embedding_batch::estimate_tokens;
use crate::knowledge::{KnowledgeContextBlock, KnowledgeRole, KnowledgeSourceKind};

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
        return text.to_string();
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

fn is_planning_or_summary_query(query: &str) -> bool {
    let normalized = query.trim().to_lowercase();
    normalized.contains("plan")
        || normalized.contains("agenda")
        || normalized.contains("schedule")
        || normalized.contains("week")
        || normalized.contains("summary")
        || normalized.contains("summarize")
        || query.contains("计划")
        || query.contains("安排")
        || query.contains("总结")
        || query.contains("整理")
}

fn candidate_pack_priority(
    request: &NormalizedRetrievalRequest,
    candidate: &KnowledgeCandidate,
) -> i32 {
    if !is_planning_or_summary_query(&request.query_text) {
        return 0;
    }
    match (candidate.source_kind(), candidate.role) {
        (KnowledgeSourceKind::Summary, _) | (_, KnowledgeRole::Summary) => 2,
        (_, KnowledgeRole::Evidence) => -1,
        _ => 0,
    }
}

pub(crate) fn pack_context_blocks(
    request: &NormalizedRetrievalRequest,
    candidates: &[KnowledgeCandidate],
) -> Vec<KnowledgeContextBlock> {
    let mut used_tokens = 0usize;
    let mut out = Vec::<KnowledgeContextBlock>::new();
    let mut ordered = candidates.to_vec();
    ordered.sort_by(|left, right| {
        candidate_pack_priority(request, right)
            .cmp(&candidate_pack_priority(request, left))
            .then_with(|| {
                right
                    .score
                    .partial_cmp(&left.score)
                    .unwrap_or(std::cmp::Ordering::Equal)
            })
    });

    for candidate in &ordered {
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

#[cfg(test)]
mod tests {
    use super::{candidate_pack_priority, is_planning_or_summary_query, truncate_to_token_budget};
    use crate::knowledge::models::GeneratedMemoryKind;
    use crate::knowledge::retrieval::{normalize_retrieval_request, KnowledgeCandidate};
    use crate::knowledge::{
        ContentKnowledgeDocument, KnowledgeAnchorSet, KnowledgeOriginType, KnowledgeRetrievalLayer,
        KnowledgeRole, KnowledgeSourceKind, KnowledgeVersionSet,
    };

    #[test]
    fn truncate_to_token_budget_preserves_formatting_when_not_truncated() {
        let text = "Speaker A:\n  hello\n\nSpeaker B:\n  world";
        let out = truncate_to_token_budget(text, 999);
        assert_eq!(out, text);
    }

    #[test]
    fn truncate_to_token_budget_appends_ellipsis_when_truncated() {
        let text = "a b c d";
        let out = truncate_to_token_budget(text, 2);
        assert_eq!(out, "a …");
    }

    #[test]
    fn planning_queries_prioritize_summary_candidates() {
        assert!(is_planning_or_summary_query("plan my week"));
        let request =
            normalize_retrieval_request("plan my week", None, None, Some(4), Some(64), None);
        let candidate = KnowledgeCandidate::from_document(
            &ContentKnowledgeDocument {
                document_id: format!(
                    "generated:{}:active-task-focus",
                    GeneratedMemoryKind::Pattern.as_str()
                ),
                origin_type: KnowledgeOriginType::Generated,
                source_kind: KnowledgeSourceKind::Summary,
                role: KnowledgeRole::Summary,
                language: None,
                quality_score: 1.0,
                created_at_ms: 0,
                updated_at_ms: 0,
                versions: KnowledgeVersionSet::current(),
                anchors: KnowledgeAnchorSet::default(),
                title: Some("Active task pattern".to_string()),
                summary: Some("digest".to_string()),
                raw_text: "session digest".to_string(),
                normalized_text: "session digest".to_string(),
            },
            0.2,
            0.1,
        );
        assert_eq!(candidate.layer, KnowledgeRetrievalLayer::Document);
        assert!(candidate_pack_priority(&request, &candidate) > 0);
    }
}
