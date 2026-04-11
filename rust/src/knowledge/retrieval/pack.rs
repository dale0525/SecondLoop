use crate::knowledge::embedding_batch::estimate_tokens;
use crate::knowledge::session_digest;
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

fn candidate_pack_priority(
    request: &NormalizedRetrievalRequest,
    candidate: &KnowledgeCandidate,
) -> i32 {
    if session_digest::is_planning_or_summary_query(&request.query_text) {
        return match (candidate.source_kind(), candidate.role) {
            (KnowledgeSourceKind::Summary, _) | (_, KnowledgeRole::Summary) => 2,
            (_, KnowledgeRole::Evidence) => 1,
            (_, KnowledgeRole::Metadata) => -1,
            _ => 0,
        };
    }
    if session_digest::is_detail_or_factual_query(&request.query_text) {
        return match candidate.role {
            KnowledgeRole::Evidence => 1,
            KnowledgeRole::Summary => -1,
            _ => 0,
        };
    }
    0
}

fn maybe_push_prebuilt_block(
    out: &mut Vec<KnowledgeContextBlock>,
    used_tokens: &mut usize,
    token_budget: usize,
    block: KnowledgeContextBlock,
) {
    let mut rendered_text = block.rendered_text.clone();
    let mut block_tokens = estimate_tokens(&rendered_text);
    if block_tokens == 0 {
        return;
    }
    if *used_tokens + block_tokens > token_budget {
        if out.is_empty() {
            rendered_text = truncate_to_token_budget(&rendered_text, token_budget);
            block_tokens = estimate_tokens(&rendered_text);
        } else {
            return;
        }
    }
    if *used_tokens + block_tokens > token_budget {
        return;
    }
    *used_tokens += block_tokens;
    out.push(KnowledgeContextBlock {
        rendered_text,
        ..block
    });
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

    // Keep the digest fallback here for direct retrieval-pack callers. The higher-level
    // planning path in `try_build_knowledge_contexts` will rebuild the digest after merging
    // generated memories, so this candidate-only digest is superseded there.
    if let Some(mut digest) = session_digest::build_digest_from_candidates(request, &ordered) {
        let digest_budget = request.token_budget.min((request.token_budget / 2).max(24));
        if estimate_tokens(&digest.rendered_text) > digest_budget {
            digest.rendered_text = truncate_to_token_budget(&digest.rendered_text, digest_budget);
        }
        maybe_push_prebuilt_block(&mut out, &mut used_tokens, request.token_budget, digest);
    }

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
                continue;
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
    use super::{candidate_pack_priority, truncate_to_token_budget};
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
                memory_display: None,
                memory_feedback: crate::knowledge::KnowledgeMemoryFeedback::default(),
            },
            0.2,
            0.1,
        );
        assert_eq!(candidate.layer, KnowledgeRetrievalLayer::Document);
        assert!(candidate_pack_priority(&request, &candidate) > 0);
    }

    #[test]
    fn detail_queries_prioritize_evidence_candidates() {
        let request = normalize_retrieval_request(
            "quote the exact decision",
            None,
            None,
            Some(4),
            Some(64),
            None,
        );
        let candidate = KnowledgeCandidate::from_document(
            &ContentKnowledgeDocument {
                document_id: "message:decision".to_string(),
                origin_type: KnowledgeOriginType::Message,
                source_kind: KnowledgeSourceKind::RawText,
                role: KnowledgeRole::Evidence,
                language: None,
                quality_score: 1.0,
                created_at_ms: 0,
                updated_at_ms: 0,
                versions: KnowledgeVersionSet::current(),
                anchors: KnowledgeAnchorSet::default(),
                title: None,
                summary: None,
                raw_text: "Budget freeze decision".to_string(),
                normalized_text: "Budget freeze decision".to_string(),
                memory_display: None,
                memory_feedback: crate::knowledge::KnowledgeMemoryFeedback::default(),
            },
            0.2,
            0.1,
        );
        assert!(candidate_pack_priority(&request, &candidate) > 0);
    }
}
