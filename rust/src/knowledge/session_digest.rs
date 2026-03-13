use crate::knowledge::retrieval::{KnowledgeCandidate, NormalizedRetrievalRequest};
use crate::knowledge::{
    KnowledgeAnchorSet, KnowledgeContextBlock, KnowledgeOriginType, KnowledgeRole,
    KnowledgeSourceKind,
};

const MAX_TOPIC_CHARS: usize = 96;
const MAX_LINE_CHARS: usize = 120;
const MAX_SECTION_ITEMS: usize = 2;

const PLANNING_KEYWORDS: &[&str] = &[
    "plan",
    "agenda",
    "schedule",
    "week",
    "summary",
    "summarize",
    "roadmap",
    "next step",
    "next steps",
    "计划",
    "安排",
    "总结",
    "整理",
    "路线图",
    "下一步",
];

const DETAIL_KEYWORDS: &[&str] = &[
    "exact",
    "quote",
    "details",
    "detail",
    "specifically",
    "what exactly",
    "verbatim",
    "引用",
    "原文",
    "具体",
    "细节",
];

const OPEN_LOOP_KEYWORDS: &[&str] = &[
    "follow up",
    "todo",
    "next",
    "pending",
    "need to",
    "open loop",
    "action item",
    "待办",
    "跟进",
    "下一步",
    "需要",
    "未完成",
];

const DECISION_KEYWORDS: &[&str] = &[
    "decision", "decide", "decided", "agreed", "ship", "freeze", "chosen", "决定", "确定", "结论",
    "已定",
];

#[derive(Clone, Debug, Default, PartialEq, Eq)]
struct DigestParts {
    topic: Option<String>,
    user_intent: String,
    open_loops: Vec<String>,
    decisions: Vec<String>,
    relevant_preferences: Vec<String>,
}

pub fn is_planning_or_summary_query(query: &str) -> bool {
    let normalized = normalize_text(query);
    !normalized.is_empty()
        && PLANNING_KEYWORDS
            .iter()
            .any(|keyword| normalized.contains(keyword))
}

pub fn is_detail_or_factual_query(query: &str) -> bool {
    let normalized = normalize_text(query);
    !normalized.is_empty()
        && DETAIL_KEYWORDS
            .iter()
            .any(|keyword| normalized.contains(keyword))
}

pub(crate) fn build_digest_from_candidates(
    request: &NormalizedRetrievalRequest,
    candidates: &[KnowledgeCandidate],
) -> Option<KnowledgeContextBlock> {
    if !is_planning_or_summary_query(&request.query_text) {
        return None;
    }
    let items = candidates.iter().map(|candidate| DigestItem {
        document_id: candidate.document.document_id.clone(),
        origin_type: Some(candidate.document.origin_type),
        body: body_from_text(&candidate.raw_text, &candidate.normalized_text),
        score: candidate.score,
    });
    build_digest_block(
        &request.query_text,
        request.conversation_id.as_deref(),
        items.collect(),
    )
}

pub(crate) fn build_digest_from_blocks(
    question: &str,
    conversation_id: Option<&str>,
    blocks: &[KnowledgeContextBlock],
) -> Option<KnowledgeContextBlock> {
    if !is_planning_or_summary_query(question) {
        return None;
    }
    let items = blocks.iter().map(|block| DigestItem {
        document_id: block.document_id.clone(),
        origin_type: None,
        body: extract_body_from_rendered_text(&block.rendered_text),
        score: block.score,
    });
    build_digest_block(question, conversation_id, items.collect())
}

#[derive(Clone, Debug)]
struct DigestItem {
    document_id: String,
    origin_type: Option<KnowledgeOriginType>,
    body: String,
    score: f64,
}

fn build_digest_block(
    question: &str,
    conversation_id: Option<&str>,
    mut items: Vec<DigestItem>,
) -> Option<KnowledgeContextBlock> {
    items.retain(|item| !item.body.trim().is_empty());
    if items.is_empty() {
        return None;
    }
    items.sort_by(|left, right| {
        right
            .score
            .partial_cmp(&left.score)
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    let parts = collect_digest_parts(question, &items);
    if parts.topic.is_none()
        && parts.open_loops.is_empty()
        && parts.decisions.is_empty()
        && parts.relevant_preferences.is_empty()
    {
        return None;
    }

    let body = render_digest_text(&parts);
    let anchors = KnowledgeAnchorSet {
        conversation_id: conversation_id.map(str::to_string),
        section_label: Some("session_digest".to_string()),
        ..KnowledgeAnchorSet::default()
    };
    let scope = anchors
        .conversation_id
        .as_deref()
        .map(|value| format!("conversation_id={value}"))
        .unwrap_or_else(|| "generated_memory=global".to_string());

    Some(KnowledgeContextBlock {
        document_id: digest_document_id(conversation_id),
        unit_id: None,
        unit_kind: None,
        source_kind: KnowledgeSourceKind::Summary,
        role: KnowledgeRole::Summary,
        anchors,
        score: items.first().map(|item| item.score + 0.01).unwrap_or(1.0),
        rendered_text: format!(
            "{scope}\n[knowledge layer=document source=summary role=summary]\n{body}"
        ),
    })
}

fn collect_digest_parts(question: &str, items: &[DigestItem]) -> DigestParts {
    let mut parts = DigestParts {
        topic: None,
        user_intent: truncate_text(question.trim(), MAX_LINE_CHARS),
        open_loops: Vec::new(),
        decisions: Vec::new(),
        relevant_preferences: Vec::new(),
    };

    for item in items {
        if parts.topic.is_none() && !is_preference_item(item) {
            if let Some(fragment) = first_fragment(&item.body) {
                parts.topic = Some(truncate_text(&fragment, MAX_TOPIC_CHARS));
            }
        }

        if is_preference_item(item) {
            if let Some(fragment) = first_fragment(&item.body) {
                push_unique(
                    &mut parts.relevant_preferences,
                    truncate_text(&fragment, MAX_LINE_CHARS),
                    MAX_SECTION_ITEMS,
                );
            }
            continue;
        }

        for fragment in fragments(&item.body) {
            let normalized = normalize_text(&fragment);
            if normalized.is_empty() {
                continue;
            }
            if matches_any_keyword(&normalized, OPEN_LOOP_KEYWORDS) {
                push_unique(
                    &mut parts.open_loops,
                    truncate_text(&fragment, MAX_LINE_CHARS),
                    MAX_SECTION_ITEMS,
                );
            }
            if matches_any_keyword(&normalized, DECISION_KEYWORDS) {
                push_unique(
                    &mut parts.decisions,
                    truncate_text(&fragment, MAX_LINE_CHARS),
                    MAX_SECTION_ITEMS,
                );
            }
            if parts.open_loops.len() >= MAX_SECTION_ITEMS
                && parts.decisions.len() >= MAX_SECTION_ITEMS
            {
                break;
            }
        }
    }

    if parts.topic.is_none() {
        parts.topic = items
            .iter()
            .find_map(|item| first_fragment(&item.body))
            .map(|fragment| truncate_text(&fragment, MAX_TOPIC_CHARS));
    }

    parts
}

fn digest_document_id(conversation_id: Option<&str>) -> String {
    match conversation_id {
        Some(value) if !value.trim().is_empty() => format!("generated:session-digest:{value}"),
        _ => "generated:session-digest:global".to_string(),
    }
}

fn render_digest_text(parts: &DigestParts) -> String {
    let mut lines = vec!["session digest".to_string()];
    if let Some(topic) = parts.topic.as_deref() {
        lines.push(format!("topic: {topic}"));
    }
    if !parts.user_intent.is_empty() {
        lines.push(format!("user_intent: {}", parts.user_intent));
    }
    append_section(
        &mut lines,
        "relevant_preferences",
        &parts.relevant_preferences,
    );
    append_section(&mut lines, "open_loops", &parts.open_loops);
    append_section(&mut lines, "decisions", &parts.decisions);
    lines.join("\n")
}

fn append_section(lines: &mut Vec<String>, label: &str, values: &[String]) {
    if values.is_empty() {
        return;
    }
    lines.push(format!("{label}:"));
    for value in values {
        lines.push(format!("- {value}"));
    }
}

fn is_preference_item(item: &DigestItem) -> bool {
    if item.document_id.starts_with("generated:preference:") {
        return true;
    }
    item.origin_type == Some(KnowledgeOriginType::Generated)
        && item.document_id.contains(":preference:")
}

fn body_from_text(raw_text: &str, normalized_text: &str) -> String {
    if raw_text.trim().is_empty() {
        normalized_text.trim().to_string()
    } else {
        raw_text.trim().to_string()
    }
}

fn extract_body_from_rendered_text(rendered_text: &str) -> String {
    let mut lines = rendered_text.lines();
    let _prefix = lines.next();
    let _header = lines.next();
    lines.collect::<Vec<_>>().join("\n").trim().to_string()
}

fn first_fragment(text: &str) -> Option<String> {
    fragments(text).into_iter().next()
}

fn fragments(text: &str) -> Vec<String> {
    let mut out = Vec::<String>::new();
    let mut current = String::new();
    for ch in text.chars() {
        let boundary = matches!(ch, '\n' | '.' | '!' | '?' | '。' | '！' | '？' | ';' | '；');
        if boundary {
            push_fragment(&mut out, &mut current);
            continue;
        }
        current.push(ch);
    }
    push_fragment(&mut out, &mut current);
    out
}

fn push_fragment(out: &mut Vec<String>, current: &mut String) {
    let trimmed = current.trim();
    if !trimmed.is_empty() {
        let candidate = trimmed.split_whitespace().collect::<Vec<_>>().join(" ");
        if !candidate.is_empty() && !out.contains(&candidate) {
            out.push(candidate);
        }
    }
    current.clear();
}

fn normalize_text(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for ch in text.chars() {
        if ch.is_alphanumeric() || ('\u{4e00}'..='\u{9fff}').contains(&ch) {
            out.extend(ch.to_lowercase());
        } else {
            out.push(' ');
        }
    }
    out.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn truncate_text(text: &str, max_chars: usize) -> String {
    let trimmed = text.trim();
    if trimmed.chars().count() <= max_chars.max(1) {
        return trimmed.to_string();
    }
    let kept = trimmed
        .chars()
        .take(max_chars.saturating_sub(1).max(1))
        .collect::<String>();
    format!("{}…", kept.trim_end())
}

fn matches_any_keyword(normalized: &str, keywords: &[&str]) -> bool {
    keywords.iter().any(|keyword| normalized.contains(keyword))
}

fn push_unique(target: &mut Vec<String>, value: String, max_items: usize) {
    if value.is_empty() || target.contains(&value) || target.len() >= max_items {
        return;
    }
    target.push(value);
}

#[cfg(test)]
mod tests {
    use super::{
        build_digest_from_blocks, is_detail_or_factual_query, is_planning_or_summary_query,
    };
    use crate::knowledge::{
        KnowledgeAnchorSet, KnowledgeContextBlock, KnowledgeRole, KnowledgeSourceKind,
    };

    #[test]
    fn session_digest_detects_planning_and_detail_queries() {
        assert!(is_planning_or_summary_query("plan my week"));
        assert!(is_planning_or_summary_query("请帮我总结一下"));
        assert!(is_detail_or_factual_query("quote the exact line"));
        assert!(is_detail_or_factual_query("给我具体原文"));
    }

    #[test]
    fn session_digest_builds_sections_from_blocks() {
        let digest = build_digest_from_blocks(
            "plan my week around the freeze",
            Some("conv-1"),
            &[
                KnowledgeContextBlock {
                    document_id: "generated:preference:response-language".to_string(),
                    unit_id: None,
                    unit_kind: None,
                    source_kind: KnowledgeSourceKind::Summary,
                    role: KnowledgeRole::Summary,
                    anchors: KnowledgeAnchorSet::default(),
                    score: 0.9,
                    rendered_text: "conversation_id=conv-1\n[knowledge layer=document source=summary role=summary]\nUser prefers responses in Chinese.".to_string(),
                },
                KnowledgeContextBlock {
                    document_id: "message:1".to_string(),
                    unit_id: None,
                    unit_kind: None,
                    source_kind: KnowledgeSourceKind::RawText,
                    role: KnowledgeRole::Evidence,
                    anchors: KnowledgeAnchorSet::default(),
                    score: 0.8,
                    rendered_text: "conversation_id=conv-1\n[knowledge layer=document source=raw_text role=evidence]\nBudget freeze decision. Follow up with Alice on Monday.".to_string(),
                },
            ],
        )
        .expect("digest");

        assert!(digest.rendered_text.contains("session digest"));
        assert!(digest.rendered_text.contains("relevant_preferences:"));
        assert!(digest.rendered_text.contains("open_loops:"));
        assert!(digest.rendered_text.contains("decisions:"));
    }

    #[test]
    fn session_digest_does_not_treat_plain_text_preference_phrases_as_generated_preferences() {
        let digest = build_digest_from_blocks(
            "plan my week around the freeze",
            Some("conv-1"),
            &[
                KnowledgeContextBlock {
                    document_id: "message:topic".to_string(),
                    unit_id: None,
                    unit_kind: None,
                    source_kind: KnowledgeSourceKind::RawText,
                    role: KnowledgeRole::Evidence,
                    anchors: KnowledgeAnchorSet::default(),
                    score: 0.9,
                    rendered_text: "conversation_id=conv-1
[knowledge layer=document source=raw_text role=evidence]
Project launch checklist."
                        .to_string(),
                },
                KnowledgeContextBlock {
                    document_id: "message:note".to_string(),
                    unit_id: None,
                    unit_kind: None,
                    source_kind: KnowledgeSourceKind::RawText,
                    role: KnowledgeRole::Evidence,
                    anchors: KnowledgeAnchorSet::default(),
                    score: 0.8,
                    rendered_text: "conversation_id=conv-1
[knowledge layer=document source=raw_text role=evidence]
The team prefers responses to be logged in the tracker."
                        .to_string(),
                },
            ],
        )
        .expect("digest");

        assert!(!digest.rendered_text.contains("relevant_preferences:"));
        assert!(digest
            .rendered_text
            .contains("topic: Project launch checklist"));
    }
}
