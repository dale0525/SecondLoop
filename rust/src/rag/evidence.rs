use rusqlite::Connection;

use crate::db;
use crate::knowledge::{self};
use crate::message_citations::{
    encode_answer_evidence_json, message_citation_href, AnswerEvidenceDirectSource,
    AnswerEvidenceMemoryCard,
};

use super::context_selection::{self, ContextItem, ContextSource};
use super::knowledge_contexts::KnowledgeRenderedContextEntry;
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

pub(super) fn context_usage_reason(question: &str) -> String {
    question.trim().to_string()
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

fn attachment_content_kind_for_document_id(document_id: &str) -> Option<&'static str> {
    match document_id.split(':').next_back()?.trim() {
        "extracted_text" => Some("extracted_text_full"),
        "readable_text" => Some("readable_text_full"),
        "ocr_text" => Some("ocr_text_full"),
        "transcript" => Some("transcript_full"),
        "summary" => Some("summary"),
        "metadata" => Some("metadata"),
        _ => None,
    }
}

fn attachment_chunk_index_from_unit_id(unit_id: Option<&str>) -> Option<i64> {
    unit_id
        .and_then(|value| value.trim().rsplit_once(":chunk:"))
        .and_then(|(_, raw_chunk)| raw_chunk.parse::<i64>().ok())
}

fn build_attachment_knowledge_direct_source_href(
    attachment_sha256: &str,
    document_id: &str,
    unit_id: Option<&str>,
) -> String {
    let mut href = format!("secondloop://attachment/{attachment_sha256}");
    let Some(kind) = attachment_content_kind_for_document_id(document_id) else {
        return href;
    };

    href.push_str(&format!("?kind={kind}"));
    if let Some(chunk_index) = attachment_chunk_index_from_unit_id(unit_id) {
        href.push_str(&format!("&chunk={chunk_index}"));
    }
    href
}

pub(super) fn build_external_document_direct_source(
    doc_id: &str,
    chunk_index: i64,
    title: &str,
    snippet: &str,
    created_at_ms: i64,
) -> AnswerEvidenceDirectSource {
    let document_id = format!("external:{doc_id}");
    let unit_id = format!("{document_id}:chunk:{chunk_index:04}");
    let normalized_title = title.trim();
    let normalized_snippet = compact_snippet(snippet, 180);
    let encoded_document_id = encode_deeplink_component(&document_id);
    let encoded_unit_id = encode_deeplink_component(&unit_id);
    AnswerEvidenceDirectSource {
        id: format!("external-document:{doc_id}:{chunk_index}"),
        href: format!(
            "secondloop://knowledge-document/{encoded_document_id}?chunk={chunk_index}&unit={encoded_unit_id}",
        ),
        source_type: "document".to_string(),
        label: "Document".to_string(),
        source_type_label: Some("document".to_string()),
        scope_label: None,
        confidence_label: None,
        title: Some(normalized_title.to_string()).filter(|value| !value.is_empty()),
        snippet: normalized_snippet.clone(),
        highlighted_text: Some(normalized_snippet),
        created_at_ms: Some(created_at_ms),
        updated_at_ms: Some(created_at_ms),
        anchors: None,
        document_id: Some(document_id),
        unit_id: Some(unit_id),
    }
}

fn encode_deeplink_component(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    for byte in value.bytes() {
        let is_unreserved =
            byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'.' | b'_' | b'~');
        if is_unreserved {
            out.push(char::from(byte));
        } else {
            out.push('%');
            out.push_str(&format!("{byte:02X}"));
        }
    }
    out
}

fn build_external_document_direct_source_from_context(
    doc_id: &str,
    chunk_index: i64,
    context: &str,
    created_at_ms: i64,
) -> AnswerEvidenceDirectSource {
    let mut title = "";
    let mut snippet = "";
    for line in context.lines() {
        let trimmed = line.trim();
        if let Some(value) = trimmed.strip_prefix("title:") {
            title = value.trim();
            continue;
        }
        if let Some(value) = trimmed.strip_prefix("content:") {
            snippet = value.trim();
            break;
        }
    }
    if snippet.is_empty() {
        snippet = context.trim();
    }
    build_external_document_direct_source(doc_id, chunk_index, title, snippet, created_at_ms)
}

pub(super) fn build_memory_card_from_document(
    conn: &Connection,
    key: &[u8; 32],
    document_id: &str,
    why_used: &str,
) -> Option<AnswerEvidenceMemoryCard> {
    if document_id.starts_with("page:") {
        let _ = knowledge::compiler::refresh_knowledge_pages_if_required(conn, key).ok()?;
        let detail = crate::db::get_knowledge_page_detail(conn, key, document_id)
            .ok()
            .flatten()?;
        let why_used = why_used.trim();
        let status = if detail.page.human_corrected {
            knowledge::KnowledgeMemoryStatus::Confirmed
        } else if detail.page.state == knowledge::KnowledgePageState::Outdated {
            knowledge::KnowledgeMemoryStatus::MaybeOutdated
        } else {
            knowledge::KnowledgeMemoryStatus::Inferred
        };
        return Some(AnswerEvidenceMemoryCard {
            document_id: detail.page.page_id,
            title: Some(detail.page.title),
            summary: Some(detail.page.current_summary),
            body: Some(detail.page.current_body),
            source_kind: knowledge::KnowledgeSourceKind::Summary,
            role: knowledge::KnowledgeRole::Summary,
            created_at_ms: detail.page.created_at_ms,
            updated_at_ms: detail.page.updated_at_ms,
            status,
            source_count: detail.page.source_count,
            why_used: if why_used.is_empty() {
                None
            } else {
                Some(why_used.to_string())
            },
            use_for_ask_ai: detail.page.answer_policy.default_allowed,
            is_deleted: detail.page.state == knowledge::KnowledgePageState::Removed,
            marked_inaccurate: detail.page.state == knowledge::KnowledgePageState::NeedsReview,
            anchors: knowledge::KnowledgeAnchorSet::default(),
        });
    }
    if !document_id.starts_with("generated:")
        || document_id.starts_with("generated:session-digest:")
    {
        return None;
    }
    let document = knowledge::get_knowledge_document(conn, key, document_id)
        .ok()
        .flatten()?;
    let display = document.memory_display.as_ref();
    let why_used = why_used.trim();
    Some(AnswerEvidenceMemoryCard {
        document_id: document.document_id,
        title: document.title,
        summary: document.summary,
        body: Some(document.raw_text),
        source_kind: document.source_kind,
        role: document.role,
        created_at_ms: document.created_at_ms,
        updated_at_ms: document.updated_at_ms,
        status: display.map(|value| value.status).unwrap_or_else(|| {
            knowledge::infer_memory_status(
                document_id,
                document.updated_at_ms,
                &document.memory_feedback,
            )
        }),
        source_count: display.map(|value| value.source_count).unwrap_or(1),
        why_used: if why_used.is_empty() {
            None
        } else {
            Some(why_used.to_string())
        },
        use_for_ask_ai: document.memory_feedback.use_for_ask_ai,
        is_deleted: document.memory_feedback.is_deleted,
        marked_inaccurate: document.memory_feedback.marked_inaccurate,
        anchors: document.anchors,
    })
}

pub(super) fn build_direct_sources_from_knowledge_entry(
    conn: &Connection,
    key: &[u8; 32],
    entry: &KnowledgeRenderedContextEntry,
) -> Vec<AnswerEvidenceDirectSource> {
    let mut out = Vec::<AnswerEvidenceDirectSource>::new();
    let block = &entry.block;
    let highlighted_text = rendered_highlighted_text(&entry.rendered_text);
    let snippet = highlighted_text
        .clone()
        .unwrap_or_else(|| compact_snippet(&entry.rendered_text, 180));
    let scope_label = readable_scope_label(&block.anchors);
    let confidence_label = readable_confidence_label(block.score);
    if let Some(message_id) = block.anchors.message_id.as_deref() {
        if let Ok(Some(message)) = db::get_message_by_id_optional(conn, key, message_id) {
            if let Some(mut source) = build_message_direct_source(&message) {
                if scope_label.is_some() {
                    source.scope_label = scope_label.clone();
                }
                if confidence_label.is_some() {
                    source.confidence_label = confidence_label.clone();
                }
                if highlighted_text.is_some() {
                    source.highlighted_text = highlighted_text.clone();
                    source.snippet = snippet.clone();
                }
                out.push(source);
            }
        }
    }
    if let Some(attachment_sha256) = block.anchors.attachment_sha256.as_deref() {
        out.push(AnswerEvidenceDirectSource {
            id: format!(
                "knowledge-attachment:{}:{}",
                block.document_id,
                block.unit_id.as_deref().unwrap_or("document")
            ),
            href: build_attachment_knowledge_direct_source_href(
                attachment_sha256,
                &block.document_id,
                block.unit_id.as_deref(),
            ),
            source_type: "attachment".to_string(),
            label: "Attachment".to_string(),
            source_type_label: Some(readable_source_type_label(
                "attachment",
                Some(block.source_kind),
                block.unit_kind,
            )),
            scope_label,
            confidence_label,
            title: block.anchors.source_filename.clone(),
            snippet,
            highlighted_text,
            created_at_ms: Some(block.anchors.start_ms.unwrap_or_default()),
            updated_at_ms: Some(block.anchors.end_ms.unwrap_or_default()),
            anchors: Some(block.anchors.clone()),
            document_id: Some(block.document_id.clone()),
            unit_id: block.unit_id.clone(),
        });
        return out;
    }
    if let Some(doc_id) = block.document_id.strip_prefix("external:") {
        let chunk_index =
            attachment_chunk_index_from_unit_id(block.unit_id.as_deref()).unwrap_or(0);
        let external_document = knowledge::get_knowledge_document(conn, key, &block.document_id)
            .ok()
            .flatten();
        let title = external_document
            .as_ref()
            .and_then(|document| document.title.as_deref())
            .or(block.anchors.source_filename.as_deref())
            .unwrap_or_default();
        let created_at_ms = external_document
            .as_ref()
            .map(|document| document.created_at_ms)
            .or(block.anchors.start_ms)
            .unwrap_or_default();
        out.push(build_external_document_direct_source(
            doc_id,
            chunk_index,
            title,
            &snippet,
            created_at_ms,
        ));
    }
    out
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

fn readable_source_type_label(
    source_type: &str,
    source_kind: Option<knowledge::KnowledgeSourceKind>,
    unit_kind: Option<knowledge::KnowledgeUnitKind>,
) -> String {
    match source_type {
        "message" => "chat_message".to_string(),
        "attachment" => match source_kind {
            Some(knowledge::KnowledgeSourceKind::Transcript) => "attachment_transcript".to_string(),
            Some(knowledge::KnowledgeSourceKind::OcrText) => "attachment_ocr".to_string(),
            Some(knowledge::KnowledgeSourceKind::ReadableText) => "attachment_text".to_string(),
            Some(knowledge::KnowledgeSourceKind::Summary) => "attachment_summary".to_string(),
            Some(knowledge::KnowledgeSourceKind::Metadata) => "attachment_metadata".to_string(),
            _ => match unit_kind {
                Some(knowledge::KnowledgeUnitKind::Chunk) => "attachment_excerpt".to_string(),
                _ => "attachment".to_string(),
            },
        },
        _ => source_type.to_string(),
    }
}

fn readable_scope_label(anchors: &knowledge::KnowledgeAnchorSet) -> Option<String> {
    anchors
        .conversation_id
        .as_ref()
        .map(|_| "this_thread".to_string())
}

fn readable_confidence_label(score: f64) -> Option<String> {
    if score >= 0.85 {
        return Some("high_relevance".to_string());
    }
    if score >= 0.45 {
        return Some("relevant".to_string());
    }
    if score > 0.0 {
        return Some("possible_match".to_string());
    }
    None
}

fn rendered_highlighted_text(rendered_text: &str) -> Option<String> {
    let cleaned = rendered_text
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .filter(|line| {
            !line.starts_with("conversation_id=")
                && !line.starts_with("generated_memory=")
                && !line.starts_with("[knowledge ")
                && !line.starts_with("[History](")
                && !line.starts_with("[Attachment](")
        })
        .collect::<Vec<_>>()
        .join(" ");
    let normalized = compact_snippet(cleaned.trim(), 220);
    if normalized.trim().is_empty() {
        return None;
    }
    Some(normalized)
}

pub(super) fn encode_context_evidence_json_for_question(
    question: &str,
    contexts: &[ContextWithEvidence],
    extra_direct_sources: &[AnswerEvidenceDirectSource],
) -> Option<String> {
    let mut direct_sources = Vec::<AnswerEvidenceDirectSource>::new();
    let mut memory_cards = Vec::<AnswerEvidenceMemoryCard>::new();
    for context in contexts {
        direct_sources.extend(context.direct_sources.clone());
        memory_cards.extend(context.memory_cards.clone());
    }
    direct_sources.extend(extra_direct_sources.iter().cloned());
    let filtered_sources = filter_direct_sources_for_question(question, direct_sources);
    encode_answer_evidence_json(filtered_sources, memory_cards)
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
        ContextSource::ExternalDocument => {
            let mut parts = candidate.id.splitn(2, ':');
            let doc_id = parts.next().unwrap_or_default();
            let chunk_index = parts
                .next()
                .and_then(|value| value.parse::<i64>().ok())
                .unwrap_or_default();
            vec![build_external_document_direct_source_from_context(
                doc_id,
                chunk_index,
                &candidate.text,
                candidate.created_at_ms,
            )]
        }
        _ => Vec::new(),
    }
}
