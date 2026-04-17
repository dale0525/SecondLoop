use rusqlite::Connection;

use crate::db;
use crate::message_citations::{
    encode_answer_evidence_json, message_citation_href, AnswerEvidenceDirectSource,
};

use super::context_selection::{self, ContextItem, ContextSource};
use super::ContextWithEvidence;

pub(super) fn compact_snippet(value: &str, max_chars: usize) -> String {
    let normalized = value
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty() && !line.starts_with('['))
        .collect::<Vec<_>>()
        .join(" ");
    let trimmed = normalized.trim();
    if trimmed.chars().count() <= max_chars {
        return trimmed.to_string();
    }
    let mut out = String::new();
    for ch in trimmed.chars().take(max_chars.saturating_sub(1)) {
        out.push(ch);
    }
    out.push('…');
    out
}

pub(super) fn build_message_direct_source(
    message: &db::Message,
) -> Option<AnswerEvidenceDirectSource> {
    let href = message_citation_href(&message.id)?;
    let snippet = compact_snippet(&message.content, 180);
    let title = message
        .content
        .lines()
        .map(str::trim)
        .find(|line| !line.is_empty())
        .map(|line| compact_snippet(line, 80));
    if snippet.trim().is_empty() && title.as_deref().unwrap_or_default().trim().is_empty() {
        return None;
    }
    Some(AnswerEvidenceDirectSource {
        id: format!("message:{}", message.id),
        href,
        source_type: "message".to_string(),
        label: "History".to_string(),
        source_type_label: Some("chat_message".to_string()),
        scope_label: None,
        confidence_label: None,
        title,
        snippet: snippet.clone(),
        highlighted_text: Some(snippet),
        created_at_ms: Some(message.created_at_ms),
        updated_at_ms: Some(message.created_at_ms),
        anchors: None,
        document_id: None,
        unit_id: None,
    })
}

pub(super) fn build_todo_direct_source(
    todo: &db::Todo,
    snippet_source: &str,
    created_at_ms: i64,
) -> AnswerEvidenceDirectSource {
    let snippet = compact_snippet(snippet_source, 180);
    AnswerEvidenceDirectSource {
        id: format!("todo:{}", todo.id),
        href: format!("secondloop://todo/{}", todo.id),
        source_type: "item".to_string(),
        label: "Item".to_string(),
        source_type_label: Some("item".to_string()),
        scope_label: None,
        confidence_label: None,
        title: Some(todo.title.clone()),
        snippet,
        highlighted_text: None,
        created_at_ms: Some(created_at_ms),
        updated_at_ms: Some(todo.updated_at_ms),
        anchors: None,
        document_id: None,
        unit_id: None,
    }
}

pub(super) fn build_attachment_direct_source(
    attachment_sha256: &str,
    kind: &str,
    chunk_index: i64,
    text: &str,
    created_at_ms: i64,
) -> AnswerEvidenceDirectSource {
    let snippet = compact_snippet(text, 180);
    AnswerEvidenceDirectSource {
        id: format!("attachment:{attachment_sha256}:{kind}:{chunk_index}"),
        href: format!(
            "secondloop://attachment/{attachment_sha256}?kind={kind}&chunk={chunk_index}"
        ),
        source_type: "attachment".to_string(),
        label: "Attachment".to_string(),
        source_type_label: Some(readable_attachment_label(kind)),
        scope_label: None,
        confidence_label: None,
        title: Some(format!("{kind} #{chunk_index}")),
        snippet: snippet.clone(),
        highlighted_text: Some(snippet),
        created_at_ms: Some(created_at_ms),
        updated_at_ms: Some(created_at_ms),
        anchors: None,
        document_id: None,
        unit_id: None,
    }
}

fn strip_attachment_context_markup(text: &str) -> String {
    let cleaned = text
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .filter(|line| !line.starts_with("ATTACHMENT_CHUNK "))
        .filter(|line| !line.starts_with("[Attachment]("))
        .collect::<Vec<_>>()
        .join(" ");
    compact_snippet(cleaned.trim(), 180)
}

pub(super) fn build_attachment_resource_direct_source(
    attachment_sha256: &str,
    label: &str,
    created_at_ms: i64,
) -> AnswerEvidenceDirectSource {
    AnswerEvidenceDirectSource {
        id: format!("attachment-resource:{attachment_sha256}"),
        href: format!("secondloop://attachment/{attachment_sha256}"),
        source_type: "attachment".to_string(),
        label: "Attachment".to_string(),
        source_type_label: Some("attachment".to_string()),
        scope_label: None,
        confidence_label: None,
        title: Some(label.trim().to_string()).filter(|value| !value.is_empty()),
        snippet: label.trim().to_string(),
        highlighted_text: None,
        created_at_ms: Some(created_at_ms),
        updated_at_ms: Some(created_at_ms),
        anchors: None,
        document_id: None,
        unit_id: None,
    }
}

fn readable_attachment_label(kind: &str) -> String {
    match kind.trim().to_lowercase().as_str() {
        "ocr_text" => "attachment_ocr".to_string(),
        "transcript" => "attachment_transcript".to_string(),
        "readable_text" | "readable_text_full" => "attachment_text".to_string(),
        "summary" => "attachment_summary".to_string(),
        "metadata" => "attachment_metadata".to_string(),
        "chunk" => "attachment_excerpt".to_string(),
        _ => "attachment".to_string(),
    }
}

pub(super) fn encode_context_evidence_json_for_question(
    question: &str,
    contexts: &[ContextWithEvidence],
    extra_direct_sources: &[AnswerEvidenceDirectSource],
) -> Option<String> {
    let mut direct_sources = Vec::<AnswerEvidenceDirectSource>::new();
    for context in contexts {
        direct_sources.extend(context.direct_sources.clone());
    }
    direct_sources.extend(extra_direct_sources.iter().cloned());
    let filtered_sources = filter_direct_sources_for_question(question, direct_sources);
    encode_answer_evidence_json(filtered_sources)
}

pub(super) fn filter_direct_sources_for_question(
    question: &str,
    direct_sources: Vec<AnswerEvidenceDirectSource>,
) -> Vec<AnswerEvidenceDirectSource> {
    let mut seen_ids = std::collections::HashSet::<String>::new();
    let mut kept_non_messages = Vec::<AnswerEvidenceDirectSource>::new();
    let mut matched_messages = Vec::<(u64, AnswerEvidenceDirectSource)>::new();
    let mut fallback_messages = Vec::<AnswerEvidenceDirectSource>::new();

    for source in direct_sources {
        if !seen_ids.insert(source.id.clone()) {
            continue;
        }

        if source.source_type != "message" {
            kept_non_messages.push(source);
            continue;
        }

        let search_text = direct_source_search_text(&source);
        if search_text.trim().is_empty() {
            continue;
        }

        let score = context_selection::lite_score(question, &search_text);
        if score > 0 {
            matched_messages.push((score, source));
            continue;
        }

        if !is_low_signal_message_evidence_text(&search_text) {
            fallback_messages.push(source);
        }
    }

    matched_messages.sort_by(|left, right| right.0.cmp(&left.0));

    let mut out = kept_non_messages;
    if matched_messages.is_empty() {
        out.extend(fallback_messages.into_iter().take(3));
    } else {
        out.extend(
            matched_messages
                .into_iter()
                .map(|(_, source)| source)
                .take(5),
        );
    }
    out
}

fn direct_source_search_text(source: &AnswerEvidenceDirectSource) -> String {
    [
        source.title.as_deref(),
        source.highlighted_text.as_deref(),
        Some(source.snippet.as_str()),
    ]
    .into_iter()
    .flatten()
    .map(str::trim)
    .filter(|value| !value.is_empty())
    .collect::<Vec<_>>()
    .join("\n")
}

fn is_low_signal_message_evidence_text(text: &str) -> bool {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return true;
    }

    let lowercase = trimmed.to_lowercase();
    if matches!(
        lowercase.as_str(),
        "test" | "todo" | "hello" | "hi" | "ok" | "okay"
    ) {
        return true;
    }

    let without_urls = trimmed
        .split_whitespace()
        .filter(|token| {
            let token = token.trim();
            !token.starts_with("http://")
                && !token.starts_with("https://")
                && !token.starts_with("secondloop://")
        })
        .collect::<Vec<_>>()
        .join(" ");

    without_urls.trim().is_empty()
}

pub(super) fn build_direct_sources_for_context_candidate(
    conn: &Connection,
    key: &[u8; 32],
    candidate: &ContextItem,
) -> Vec<AnswerEvidenceDirectSource> {
    match candidate.source {
        ContextSource::Message => match db::get_message_by_id_optional(conn, key, &candidate.id) {
            Ok(Some(message)) => build_message_direct_source(&message)
                .into_iter()
                .collect::<Vec<_>>(),
            _ => Vec::new(),
        },
        ContextSource::TodoThread => match db::get_todo(conn, key, &candidate.id) {
            Ok(todo) => vec![build_todo_direct_source(
                &todo,
                &candidate.text,
                candidate.created_at_ms,
            )],
            Err(_) => Vec::new(),
        },
        ContextSource::AttachmentChunk => {
            let mut parts = candidate.id.splitn(3, ':');
            let attachment_sha256 = parts.next().unwrap_or_default();
            let kind = parts.next().unwrap_or("chunk");
            let chunk_index = parts
                .next()
                .and_then(|value| value.parse::<i64>().ok())
                .unwrap_or_default();
            let text =
                db::read_attachment_chunk_text(conn, key, attachment_sha256, kind, chunk_index)
                    .ok()
                    .filter(|value| !value.trim().is_empty())
                    .unwrap_or_else(|| strip_attachment_context_markup(&candidate.text));
            vec![build_attachment_direct_source(
                attachment_sha256,
                kind,
                chunk_index,
                &text,
                candidate.created_at_ms,
            )]
        }
    }
}
