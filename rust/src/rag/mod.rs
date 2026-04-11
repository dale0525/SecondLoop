use anyhow::{anyhow, Result};
use rusqlite::Connection;
use std::path::Path;

use crate::db;
use crate::embedding::Embedder;
use crate::knowledge;
use crate::llm::ChatDelta;
use crate::message_citations::{
    append_message_citation_if_missing as append_message_citation, encode_answer_evidence_json,
    message_citation_href, message_citation_link, AnswerEvidenceDirectSource,
    AnswerEvidenceMemoryCard,
};

mod attachment_resources;
mod citations_prompt;
mod context_selection;
mod fallback;
#[cfg(test)]
mod knowledge_ask_ai_tests;
mod knowledge_contexts;

use attachment_resources::{
    collect_attachment_resources_active, collect_attachment_resources_by_embedding,
    collect_attachment_resources_default, collect_attachment_resources_for_attachment_shas,
};
use citations_prompt::{build_prompt as build_prompt_base, build_prompt_with_actions_and_history};
use context_selection::{build_contexts_v2, ContextItem, ContextSource};
use knowledge_contexts::{
    merge_knowledge_and_legacy_contexts, try_build_knowledge_context_entries,
    KnowledgeRenderedContextEntry,
};

const DEFAULT_MAX_HISTORY_MESSAGES: usize = 6;
const DEFAULT_MAX_HISTORY_MESSAGE_CHARS: usize = 1200;
const DETACHED_ASK_REQUEST_ID_ROLE_PREFIX: &str = "secondloop_request_id:";

fn format_history_line(role: &str, message_id: &str, content: &str) -> String {
    match message_citation_link(message_id) {
        Some(citation) => {
            let sep = if content.ends_with('\n') { "" } else { "\n" };
            format!("{role}: {content}{sep}{citation}\n")
        }
        None => format!("{role}: {content}\n"),
    }
}

#[derive(Debug)]
pub struct StreamCancelled;

impl std::fmt::Display for StreamCancelled {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "stream cancelled")
    }
}

impl std::error::Error for StreamCancelled {}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Focus {
    AllMemories,
    ThisThread,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AskAiResult {
    pub user_message_id: String,
    pub assistant_message_id: String,
}

#[cfg(test)]
pub(crate) fn try_build_knowledge_contexts_for_tests(
    conn: &Connection,
    key: &[u8; 32],
    question: &str,
    top_k: usize,
    focus: Focus,
    conversation_id: &str,
    time_window: Option<(i64, i64)>,
) -> Result<Vec<String>> {
    knowledge_contexts::try_build_knowledge_contexts(
        conn,
        key,
        question,
        top_k,
        focus,
        conversation_id,
        time_window,
    )
}

pub trait AnswerProvider {
    fn stream_answer(
        &self,
        prompt: &str,
        on_event: &mut dyn FnMut(ChatDelta) -> Result<()>,
    ) -> Result<()>;
}

#[derive(Clone, Debug, Default)]
struct ContextWithEvidence {
    text: String,
    direct_sources: Vec<AnswerEvidenceDirectSource>,
    memory_cards: Vec<AnswerEvidenceMemoryCard>,
}

fn compact_snippet(value: &str, max_chars: usize) -> String {
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

fn context_usage_reason(question: &str) -> String {
    question.trim().to_string()
}

fn build_message_direct_source(message: &db::Message) -> Option<AnswerEvidenceDirectSource> {
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

fn build_attachment_direct_source(
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

fn build_attachment_resource_direct_source(
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

fn build_external_document_direct_source(
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
    AnswerEvidenceDirectSource {
        id: format!("external-document:{doc_id}:{chunk_index}"),
        href: format!(
            "secondloop://knowledge-document/{}?chunk={chunk_index}&unit={unit_id}",
            document_id,
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

fn build_memory_card_from_document(
    conn: &Connection,
    key: &[u8; 32],
    document_id: &str,
    why_used: &str,
) -> Option<AnswerEvidenceMemoryCard> {
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
        anchors: document.anchors,
    })
}

fn build_direct_sources_from_knowledge_entry(
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
            href: format!("secondloop://attachment/{attachment_sha256}"),
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

fn encode_context_evidence_json_for_question(
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

fn filter_direct_sources_for_question(
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

fn now_ms() -> i64 {
    use std::time::{SystemTime, UNIX_EPOCH};

    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
        .try_into()
        .unwrap_or(i64::MAX)
}

fn agenda_horizon_ms(question: &str, now_ms: i64) -> Option<i64> {
    let q = question.trim().to_lowercase();
    if q.is_empty() {
        return None;
    }

    let is_today = q.contains("today")
        || q.contains("tonight")
        || q.contains("today's")
        || question.contains("今天")
        || question.contains("今日");
    if is_today {
        return Some(now_ms.saturating_add(36 * 60 * 60 * 1000));
    }

    let is_this_week = q.contains("this week")
        || q.contains("week agenda")
        || q.contains("weekly agenda")
        || q.contains("this week's")
        || question.contains("本周")
        || question.contains("这周")
        || question.contains("這週");
    if is_this_week {
        return Some(now_ms.saturating_add(8 * 24 * 60 * 60 * 1000));
    }

    let is_agenda = q.contains("agenda")
        || q.contains("schedule")
        || q.contains("calendar")
        || question.contains("日程")
        || question.contains("行程")
        || question.contains("安排");
    let has_timeframe = is_today
        || is_this_week
        || q.contains("tomorrow")
        || q.contains("next week")
        || question.contains("明天")
        || question.contains("本周")
        || question.contains("这周")
        || question.contains("這週")
        || question.contains("今天")
        || question.contains("今日");
    let has_explicit_agenda_intent = q.contains("agenda")
        || q.contains("schedule")
        || q.contains("calendar")
        || q.contains("todo")
        || q.contains("to-do")
        || q.contains("priority")
        || q.contains("priorities")
        || q.contains("what should i do")
        || q.contains("what do i need to do")
        || q.contains("what's on my schedule")
        || q.contains("what is on my schedule")
        || q.contains("what's on my calendar")
        || q.contains("what is on my calendar")
        || q.contains("upcoming")
        || q.contains("due today")
        || question.contains("待办")
        || question.contains("待辦")
        || question.contains("日程")
        || question.contains("行程")
        || question.contains("提醒")
        || question.contains("优先级")
        || question.contains("優先級")
        || question.contains("要做")
        || question.contains("有哪些事");
    let has_generic_task_words = q.contains("task")
        || q.contains("tasks")
        || question.contains("任务")
        || question.contains("任務")
        || question.contains("计划")
        || question.contains("計劃");
    if !(has_explicit_agenda_intent || (has_generic_task_words && has_timeframe)) {
        return None;
    }
    if is_agenda {
        return Some(now_ms.saturating_add(8 * 24 * 60 * 60 * 1000));
    }

    None
}

fn should_include_actions_context(question: &str) -> bool {
    agenda_horizon_ms(question, 0).is_some()
}

fn build_actions_context(
    conn: &Connection,
    key: &[u8; 32],
    question: &str,
) -> Result<Option<String>> {
    if !should_include_actions_context(question) {
        return Ok(None);
    }

    let now = now_ms();
    let horizon = agenda_horizon_ms(question, now).unwrap_or(now);
    let mut lines: Vec<String> = Vec::new();

    for todo in db::list_todos(conn, key)? {
        if todo.status == "done" || todo.status == "dismissed" {
            continue;
        }

        let due = todo.due_at_ms;
        let review = todo.next_review_at_ms;
        let is_due = due.is_some_and(|ms| ms <= horizon);
        let is_review_due = review.is_some_and(|ms| ms <= horizon);
        if !is_due && !is_review_due {
            continue;
        }

        let mut item = format!("TODO [{}] {}", todo.status, todo.title);
        if let Some(ms) = due {
            item.push_str(&format!(" (due_at_ms={ms})"));
        }
        if let Some(ms) = review {
            item.push_str(&format!(" (next_review_at_ms={ms})"));
        }
        lines.push(item);
    }

    for event in db::list_events(conn, key)? {
        if event.end_at_ms < now {
            continue;
        }
        if event.start_at_ms > horizon {
            continue;
        }
        lines.push(format!(
            "EVENT {} (start_at_ms={}, end_at_ms={}, tz={})",
            event.title, event.start_at_ms, event.end_at_ms, event.tz
        ));
    }

    if lines.is_empty() {
        return Ok(None);
    }

    let mut out = String::new();
    out.push_str("Upcoming actions (from local todos/events):\n");
    for line in lines.into_iter().take(40) {
        out.push_str("- ");
        out.push_str(&line);
        out.push('\n');
    }
    Ok(Some(out))
}

fn build_recent_conversation_history(
    conn: &Connection,
    key: &[u8; 32],
    conversation_id: &str,
) -> Result<Option<String>> {
    let page = db::list_messages_page(conn, key, conversation_id, None, None, 32)?;

    let mut kept = Vec::new();
    for msg in page {
        let content = msg.content.trim();
        if content.is_empty() {
            continue;
        }

        let role = match msg.role.as_str() {
            "user" => "User",
            "assistant" => "Assistant",
            other => other,
        };

        let truncated: String = content
            .chars()
            .take(DEFAULT_MAX_HISTORY_MESSAGE_CHARS)
            .collect();
        kept.push((role.to_string(), msg.id.clone(), truncated));
        if kept.len() >= DEFAULT_MAX_HISTORY_MESSAGES {
            break;
        }
    }

    if kept.is_empty() {
        return Ok(None);
    }

    kept.reverse();

    let mut out = String::new();
    for (role, message_id, content) in kept {
        out.push_str(&format_history_line(&role, &message_id, &content));
    }

    Ok(Some(out))
}

fn build_recent_conversation_history_in_range(
    conn: &Connection,
    key: &[u8; 32],
    conversation_id: &str,
    start_at_ms_inclusive: i64,
    end_at_ms_exclusive: i64,
) -> Result<Option<String>> {
    // Use a larger page so that "last week" (or similar) can skip current messages and still
    // include enough in-range history.
    let page = db::list_messages_page(conn, key, conversation_id, None, None, 200)?;

    let mut kept = Vec::new();
    for msg in page {
        if msg.created_at_ms < start_at_ms_inclusive {
            break;
        }
        if msg.created_at_ms >= end_at_ms_exclusive {
            continue;
        }

        let content = msg.content.trim();
        if content.is_empty() {
            continue;
        }

        let role = match msg.role.as_str() {
            "user" => "User",
            "assistant" => "Assistant",
            other => other,
        };

        let truncated: String = content
            .chars()
            .take(DEFAULT_MAX_HISTORY_MESSAGE_CHARS)
            .collect();
        kept.push((role.to_string(), msg.id.clone(), truncated));
        if kept.len() >= DEFAULT_MAX_HISTORY_MESSAGES {
            break;
        }
    }

    if kept.is_empty() {
        return Ok(None);
    }

    kept.reverse();

    let mut out = String::new();
    for (role, message_id, content) in kept {
        out.push_str(&format_history_line(&role, &message_id, &content));
    }

    Ok(Some(out))
}

fn build_todo_thread_context(conn: &Connection, key: &[u8; 32], todo_id: &str) -> Result<String> {
    let todo = db::get_todo(conn, key, todo_id)?;
    let activities = db::list_todo_activities(conn, key, todo_id)?;

    let mut out = String::new();
    out.push_str(&format!("TODO_THREAD todo_id={}\n", todo.id));

    out.push_str(&format!("TODO [{}] {}", todo.status, todo.title));
    if let Some(ms) = todo.due_at_ms {
        out.push_str(&format!(" (due_at_ms={ms})"));
    }
    out.push('\n');

    if !activities.is_empty() {
        out.push_str("Activities:\n");
        for a in activities {
            out.push_str(&format!(
                "- (created_at_ms={}) type={}",
                a.created_at_ms, a.activity_type
            ));
            if let Some(from) = a.from_status.as_deref() {
                out.push_str(&format!(" from={from}"));
            }
            if let Some(to) = a.to_status.as_deref() {
                out.push_str(&format!(" to={to}"));
            }
            if let Some(content) = a.content.as_deref() {
                out.push_str(&format!(" content={content}"));
            }
            out.push('\n');
        }
    }

    Ok(out)
}

fn collect_time_window_attachment_resources(
    conn: &Connection,
    key: &[u8; 32],
    conversation_id: Option<&str>,
    time_start_ms: i64,
    time_end_ms: i64,
) -> Result<attachment_resources::AttachmentResourcesBundle> {
    let attachment_shas = list_attachment_shas_in_time_window(
        conn,
        key,
        conversation_id,
        time_start_ms,
        time_end_ms,
    )?;
    collect_attachment_resources_for_attachment_shas(conn, key, attachment_shas)
}

fn list_attachment_shas_in_time_window(
    conn: &Connection,
    key: &[u8; 32],
    conversation_id: Option<&str>,
    time_start_ms: i64,
    time_end_ms: i64,
) -> Result<Vec<String>> {
    let mut attachment_shas = Vec::<String>::new();
    for message in db::list_memory_messages_in_range_recent(
        conn,
        key,
        conversation_id,
        time_start_ms,
        time_end_ms,
        800,
    )? {
        for attachment in db::list_message_attachments(conn, key, &message.id)? {
            attachment_shas.push(attachment.sha256);
        }
    }
    Ok(attachment_shas)
}

fn build_direct_sources_for_context_candidate(
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
            vec![build_attachment_direct_source(
                attachment_sha256,
                kind,
                chunk_index,
                &candidate.text,
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

fn ask_ai_stream_and_persist(
    conn: &Connection,
    key: &[u8; 32],
    conversation_id: &str,
    question: &str,
    prompt: &str,
    contexts: &[ContextWithEvidence],
    extra_direct_sources: &[AnswerEvidenceDirectSource],
    provider: &(impl AnswerProvider + ?Sized),
    on_event: &mut dyn FnMut(ChatDelta) -> Result<()>,
) -> Result<AskAiResult> {
    let mut has_text = false;
    let mut assistant_text = String::new();
    let mut detached_request_id: Option<String> = None;
    let result = provider.stream_answer(prompt, &mut |ev| {
        let done = ev.done;
        let text_delta = ev.text_delta.clone();
        if detached_request_id.is_none() {
            detached_request_id = ev
                .role
                .as_deref()
                .and_then(|role| role.strip_prefix(DETACHED_ASK_REQUEST_ID_ROLE_PREFIX))
                .map(str::trim)
                .filter(|request_id| !request_id.is_empty())
                .map(ToOwned::to_owned);
        }
        on_event(ev)?;

        if !done && !text_delta.is_empty() {
            has_text = true;
            assistant_text.push_str(&text_delta);
        }

        Ok(())
    });

    match result {
        Ok(()) => {
            if !has_text {
                return Err(anyhow!("empty response from LLM"));
            }

            conn.execute_batch("BEGIN IMMEDIATE;")?;
            let persist_result: Result<AskAiResult> = (|| {
                if let Some(request_id) = detached_request_id.as_deref() {
                    let claimed = db::claim_detached_ask_completion_request_id(
                        conn,
                        request_id,
                        conversation_id,
                    )?;
                    if !claimed {
                        let (user_message_id, assistant_message_id) =
                            db::get_detached_ask_completion_message_ids(conn, request_id)?
                                .unwrap_or_default();
                        return Ok(AskAiResult {
                            user_message_id,
                            assistant_message_id,
                        });
                    }
                }

                let user_message =
                    db::insert_message_non_memory(conn, key, conversation_id, "user", question)?;
                let citations_json = encode_context_evidence_json_for_question(
                    question,
                    contexts,
                    extra_direct_sources,
                );
                let assistant_message = db::insert_message_non_memory_with_citations(
                    conn,
                    key,
                    conversation_id,
                    "assistant",
                    &assistant_text,
                    citations_json.as_deref(),
                )?;
                if let Some(request_id) = detached_request_id.as_deref() {
                    db::record_detached_ask_completion_message_ids(
                        conn,
                        request_id,
                        &user_message.id,
                        &assistant_message.id,
                    )?;
                }

                Ok(AskAiResult {
                    user_message_id: user_message.id,
                    assistant_message_id: assistant_message.id,
                })
            })();

            match persist_result {
                Ok(result) => {
                    conn.execute_batch("COMMIT;")?;
                    Ok(result)
                }
                Err(err) => {
                    let _ = conn.execute_batch("ROLLBACK;");
                    Err(err)
                }
            }
        }
        Err(e) => Err(e),
    }
}

pub fn build_prompt(question: &str, contexts: &[String]) -> String {
    build_prompt_base(question, contexts)
}

pub fn ask_ai_with_provider(
    conn: &Connection,
    key: &[u8; 32],
    conversation_id: &str,
    question: &str,
    top_k: usize,
    focus: Focus,
    provider: &(impl AnswerProvider + ?Sized),
    on_event: &mut dyn FnMut(ChatDelta) -> Result<()>,
) -> Result<AskAiResult> {
    // Ensure existing messages are embedded before searching.
    db::process_pending_message_embeddings_default(conn, key, 1024)?;
    db::process_pending_todo_embeddings_default(conn, key, 1024)?;
    db::process_pending_todo_activity_embeddings_default(conn, key, 1024)?;

    let top_k = top_k.max(1);

    let similar_messages = match focus {
        Focus::AllMemories => db::search_similar_messages_default(conn, key, question, top_k)?,
        Focus::ThisThread => db::search_similar_messages_in_conversation_default(
            conn,
            key,
            conversation_id,
            question,
            top_k,
        )?,
    };
    let similar_todos = db::search_similar_todo_threads_default(conn, key, question, top_k)?;
    let attachment_resources =
        collect_attachment_resources_default(conn, key, question, top_k).unwrap_or_default();
    let app_dir = db::app_dir_from_conn(conn).ok();
    let external_chunks = app_dir
        .as_ref()
        .map(|app_dir| {
            db::search_similar_external_document_chunks_default(app_dir, key, question, top_k)
                .unwrap_or_default()
        })
        .unwrap_or_default();

    let mut contexts_with_distance: Vec<(f64, ContextWithEvidence)> = Vec::new();
    for sm in similar_messages {
        let context = db::build_message_rag_context(conn, key, &sm.message.id, &sm.message.content)
            .unwrap_or_else(|_| sm.message.content.clone());
        let context = append_message_citation(context, &sm.message.id);
        let direct_sources = build_message_direct_source(&sm.message)
            .into_iter()
            .collect::<Vec<_>>();
        contexts_with_distance.push((
            sm.distance,
            ContextWithEvidence {
                text: context,
                direct_sources,
                memory_cards: Vec::new(),
            },
        ));
    }
    let mut seen_todos = std::collections::HashSet::new();
    for st in similar_todos {
        if !seen_todos.insert(st.todo_id.clone()) {
            continue;
        }
        let ctx = match build_todo_thread_context(conn, key, &st.todo_id) {
            Ok(v) => v,
            Err(_) => continue,
        };
        contexts_with_distance.push((
            st.distance,
            ContextWithEvidence {
                text: ctx,
                direct_sources: Vec::new(),
                memory_cards: Vec::new(),
            },
        ));
    }
    for chunk in attachment_resources.chunks {
        let citation = format!(
            "[Attachment](secondloop://attachment/{}?kind={}&chunk={})",
            chunk.attachment_sha256, chunk.kind, chunk.chunk_index
        );
        let context = format!(
            "ATTACHMENT_CHUNK {} {}#{}\n{}\n{}",
            chunk.attachment_sha256, chunk.kind, chunk.chunk_index, chunk.text, citation
        );
        contexts_with_distance.push((
            chunk.distance,
            ContextWithEvidence {
                text: context,
                direct_sources: vec![build_attachment_direct_source(
                    &chunk.attachment_sha256,
                    &chunk.kind,
                    chunk.chunk_index,
                    &chunk.text,
                    chunk.created_at_ms,
                )],
                memory_cards: Vec::new(),
            },
        ));
    }
    if let Some(app_dir) = app_dir.as_ref() {
        for chunk in external_chunks {
            let context = match db::build_external_document_chunk_rag_context(
                app_dir,
                key,
                &chunk.doc_id,
                chunk.chunk_index,
            ) {
                Ok(v) => v,
                Err(_) => continue,
            };
            contexts_with_distance.push((
                chunk.distance,
                ContextWithEvidence {
                    text: context,
                    direct_sources: vec![build_external_document_direct_source(
                        &chunk.doc_id,
                        chunk.chunk_index,
                        &chunk.title,
                        &chunk.snippet,
                        chunk.created_at_ms,
                    )],
                    memory_cards: Vec::new(),
                },
            ));
        }
    }
    contexts_with_distance
        .sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));
    contexts_with_distance.truncate(top_k);
    let contexts: Vec<ContextWithEvidence> = contexts_with_distance
        .into_iter()
        .map(|(_, ctx)| ctx)
        .collect();
    let actions = build_actions_context(conn, key, question)?;
    let history = build_recent_conversation_history(conn, key, conversation_id)?;
    let attachment_direct_sources = attachment_resources
        .resources
        .iter()
        .map(|resource| {
            build_attachment_resource_direct_source(
                &resource.attachment_sha256,
                &resource.label,
                resource.created_at_ms,
            )
        })
        .collect::<Vec<_>>();
    let prompt = build_prompt_with_actions_and_history(
        question,
        &contexts
            .iter()
            .map(|ctx| ctx.text.clone())
            .collect::<Vec<_>>(),
        actions.as_deref(),
        history.as_deref(),
        attachment_resources.catalog_markdown.as_deref(),
    );

    ask_ai_stream_and_persist(
        conn,
        key,
        conversation_id,
        question,
        &prompt,
        &contexts,
        &attachment_direct_sources,
        provider,
        on_event,
    )
}

#[allow(clippy::too_many_arguments)]
pub fn ask_ai_with_provider_using_embedder<E: Embedder + ?Sized>(
    conn: &Connection,
    key: &[u8; 32],
    embedder: &E,
    conversation_id: &str,
    question: &str,
    top_k: usize,
    focus: Focus,
    provider: &(impl AnswerProvider + ?Sized),
    on_event: &mut dyn FnMut(ChatDelta) -> Result<()>,
) -> Result<AskAiResult> {
    let mut contexts: Vec<ContextWithEvidence> = Vec::new();
    let mut resources_catalog: Option<String> = None;
    let mut attachment_direct_sources = Vec::<AnswerEvidenceDirectSource>::new();
    if top_k > 0 {
        // Avoid wiping the current index if the embedder is misconfigured/unreachable.
        let mut probe = embedder.embed(&[format!("query: {question}")])?;
        if probe.len() != 1 {
            return Err(anyhow!(
                "embedder output length mismatch: expected 1, got {}",
                probe.len()
            ));
        }
        let query_vector = probe.pop().unwrap_or_default();
        let dim = query_vector.len();
        if dim == 0 {
            return Err(anyhow!("embedder returned empty embeddings"));
        }

        db::set_active_embedding_model(conn, embedder.model_name(), dim)?;
        db::process_pending_message_embeddings(conn, key, embedder, 1024)?;
        db::process_pending_todo_embeddings(conn, key, embedder, 1024)?;
        db::process_pending_todo_activity_embeddings(conn, key, embedder, 1024)?;

        let top_k = top_k.max(1);

        let similar_messages = match focus {
            Focus::AllMemories => db::search_similar_messages_by_embedding(
                conn,
                key,
                embedder.model_name(),
                &query_vector,
                top_k,
            )?,
            Focus::ThisThread => db::search_similar_messages_in_conversation_by_embedding(
                conn,
                key,
                embedder.model_name(),
                conversation_id,
                &query_vector,
                top_k,
            )?,
        };

        let similar_todos = db::search_similar_todo_threads_by_embedding(
            conn,
            embedder.model_name(),
            &query_vector,
            top_k,
        )?;
        let attachment_resources = collect_attachment_resources_by_embedding(
            conn,
            key,
            embedder.model_name(),
            &query_vector,
            top_k,
        )
        .unwrap_or_default();
        attachment_direct_sources = attachment_resources
            .resources
            .iter()
            .map(|resource| {
                build_attachment_resource_direct_source(
                    &resource.attachment_sha256,
                    &resource.label,
                    resource.created_at_ms,
                )
            })
            .collect();
        let app_dir = db::app_dir_from_conn(conn).ok();
        let external_chunks = app_dir
            .as_ref()
            .map(|app_dir| {
                let _ =
                    db::process_pending_external_document_embeddings(app_dir, key, embedder, 1024);
                db::search_similar_external_document_chunks_by_embedding(
                    app_dir,
                    key,
                    embedder.model_name(),
                    &query_vector,
                    top_k,
                )
                .unwrap_or_default()
            })
            .unwrap_or_default();

        let mut contexts_with_distance: Vec<(f64, ContextWithEvidence)> = Vec::new();
        for sm in similar_messages {
            let context =
                db::build_message_rag_context(conn, key, &sm.message.id, &sm.message.content)
                    .unwrap_or_else(|_| sm.message.content.clone());
            let context = append_message_citation(context, &sm.message.id);
            let direct_sources = build_message_direct_source(&sm.message)
                .into_iter()
                .collect::<Vec<_>>();
            contexts_with_distance.push((
                sm.distance,
                ContextWithEvidence {
                    text: context,
                    direct_sources,
                    memory_cards: Vec::new(),
                },
            ));
        }
        let mut seen_todos = std::collections::HashSet::new();
        for st in similar_todos {
            if !seen_todos.insert(st.todo_id.clone()) {
                continue;
            }
            let ctx = match build_todo_thread_context(conn, key, &st.todo_id) {
                Ok(v) => v,
                Err(_) => continue,
            };
            contexts_with_distance.push((
                st.distance,
                ContextWithEvidence {
                    text: ctx,
                    direct_sources: Vec::new(),
                    memory_cards: Vec::new(),
                },
            ));
        }
        for chunk in attachment_resources.chunks {
            let citation = format!(
                "[Attachment](secondloop://attachment/{}?kind={}&chunk={})",
                chunk.attachment_sha256, chunk.kind, chunk.chunk_index
            );
            let context = format!(
                "ATTACHMENT_CHUNK {} {}#{}\n{}\n{}",
                chunk.attachment_sha256, chunk.kind, chunk.chunk_index, chunk.text, citation
            );
            contexts_with_distance.push((
                chunk.distance,
                ContextWithEvidence {
                    text: context,
                    direct_sources: vec![build_attachment_direct_source(
                        &chunk.attachment_sha256,
                        &chunk.kind,
                        chunk.chunk_index,
                        &chunk.text,
                        chunk.created_at_ms,
                    )],
                    memory_cards: Vec::new(),
                },
            ));
        }
        if let Some(app_dir) = app_dir.as_ref() {
            for chunk in external_chunks {
                let context = match db::build_external_document_chunk_rag_context(
                    app_dir,
                    key,
                    &chunk.doc_id,
                    chunk.chunk_index,
                ) {
                    Ok(v) => v,
                    Err(_) => continue,
                };
                contexts_with_distance.push((
                    chunk.distance,
                    ContextWithEvidence {
                        text: context,
                        direct_sources: vec![build_external_document_direct_source(
                            &chunk.doc_id,
                            chunk.chunk_index,
                            &chunk.title,
                            &chunk.snippet,
                            chunk.created_at_ms,
                        )],
                        memory_cards: Vec::new(),
                    },
                ));
            }
        }
        contexts_with_distance
            .sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));
        contexts_with_distance.truncate(top_k);
        contexts = contexts_with_distance
            .into_iter()
            .map(|(_, ctx)| ctx)
            .collect();

        resources_catalog = attachment_resources.catalog_markdown;
    }
    let actions = build_actions_context(conn, key, question)?;
    let history = build_recent_conversation_history(conn, key, conversation_id)?;
    let prompt = build_prompt_with_actions_and_history(
        question,
        &contexts
            .iter()
            .map(|ctx| ctx.text.clone())
            .collect::<Vec<_>>(),
        actions.as_deref(),
        history.as_deref(),
        resources_catalog.as_deref(),
    );

    ask_ai_stream_and_persist(
        conn,
        key,
        conversation_id,
        question,
        &prompt,
        &contexts,
        &attachment_direct_sources,
        provider,
        on_event,
    )
}

#[allow(clippy::too_many_arguments)]
pub fn ask_ai_with_provider_using_active_embeddings(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    conversation_id: &str,
    question: &str,
    top_k: usize,
    focus: Focus,
    provider: &(impl AnswerProvider + ?Sized),
    on_event: &mut dyn FnMut(ChatDelta) -> Result<()>,
) -> Result<AskAiResult> {
    let mut contexts: Vec<ContextWithEvidence> = Vec::new();
    let mut resources_catalog: Option<String> = None;
    let mut attachment_direct_sources = Vec::<AnswerEvidenceDirectSource>::new();
    if top_k > 0 {
        let knowledge_entries = try_build_knowledge_context_entries(
            conn,
            key,
            question,
            top_k,
            focus,
            conversation_id,
            None,
        )?;
        let knowledge_contexts = knowledge_entries
            .iter()
            .map(|entry| entry.rendered_text.clone())
            .collect::<Vec<_>>();
        if !fallback::should_use_legacy_retrieval_fallback(&knowledge_contexts) {
            let why_used = context_usage_reason(question);
            contexts = knowledge_entries
                .into_iter()
                .map(|entry| ContextWithEvidence {
                    text: entry.rendered_text.clone(),
                    direct_sources: build_direct_sources_from_knowledge_entry(conn, key, &entry),
                    memory_cards: build_memory_card_from_document(
                        conn,
                        key,
                        &entry.block.document_id,
                        &why_used,
                    )
                    .into_iter()
                    .collect(),
                })
                .collect();
        } else {
            db::process_pending_message_embeddings_active(conn, key, app_dir, 1024)?;
            db::process_pending_todo_embeddings_active(conn, key, app_dir, 1024)?;
            db::process_pending_todo_activity_embeddings_active(conn, key, app_dir, 1024)?;

            let legacy_top_k = top_k.saturating_sub(knowledge_contexts.len()).max(1);

            let top_k_candidate_messages =
                (legacy_top_k.saturating_mul(8)).min(200).max(legacy_top_k);
            let top_k_candidate_todos = (legacy_top_k.saturating_mul(4)).min(80).max(legacy_top_k);

            let similar_messages = match focus {
                Focus::AllMemories => db::search_similar_messages_active(
                    conn,
                    key,
                    app_dir,
                    question,
                    top_k_candidate_messages,
                )?,
                Focus::ThisThread => db::search_similar_messages_in_conversation_active(
                    conn,
                    key,
                    app_dir,
                    conversation_id,
                    question,
                    top_k_candidate_messages,
                )?,
            };

            let similar_todos = db::search_similar_todo_threads_active(
                conn,
                key,
                app_dir,
                question,
                top_k_candidate_todos,
            )?;
            let attachment_resources =
                collect_attachment_resources_active(conn, key, app_dir, question, legacy_top_k)
                    .unwrap_or_default();
            attachment_direct_sources = attachment_resources
                .resources
                .iter()
                .map(|resource| {
                    build_attachment_resource_direct_source(
                        &resource.attachment_sha256,
                        &resource.label,
                        resource.created_at_ms,
                    )
                })
                .collect();
            let external_chunks = db::search_similar_external_document_chunks_active(
                app_dir,
                key,
                question,
                top_k_candidate_messages,
            )
            .unwrap_or_default();

            let mut candidates: Vec<ContextItem> = Vec::new();
            for sm in similar_messages {
                let context =
                    db::build_message_rag_context(conn, key, &sm.message.id, &sm.message.content)
                        .unwrap_or_else(|_| sm.message.content.clone());
                candidates.push(ContextItem {
                    source: ContextSource::Message,
                    id: sm.message.id.clone(),
                    created_at_ms: sm.message.created_at_ms,
                    distance: Some(sm.distance),
                    text: context,
                    citation_suffix: message_citation_link(&sm.message.id),
                });
            }

            let mut seen_todos = std::collections::HashSet::new();
            for st in similar_todos {
                if !seen_todos.insert(st.todo_id.clone()) {
                    continue;
                }
                let todo = match db::get_todo(conn, key, &st.todo_id) {
                    Ok(v) => v,
                    Err(_) => continue,
                };
                let ctx = match build_todo_thread_context(conn, key, &st.todo_id) {
                    Ok(v) => v,
                    Err(_) => continue,
                };
                candidates.push(ContextItem {
                    source: ContextSource::TodoThread,
                    id: st.todo_id,
                    created_at_ms: todo.created_at_ms,
                    distance: Some(st.distance),
                    text: ctx,
                    citation_suffix: None,
                });
            }

            for chunk in attachment_resources.chunks {
                let citation = format!(
                    "[Attachment](secondloop://attachment/{}?kind={}&chunk={})",
                    chunk.attachment_sha256, chunk.kind, chunk.chunk_index
                );
                let context = format!("{}\n{}", chunk.text, citation,);
                candidates.push(ContextItem {
                    source: ContextSource::AttachmentChunk,
                    id: format!(
                        "{}:{}:{}",
                        chunk.attachment_sha256, chunk.kind, chunk.chunk_index
                    ),
                    created_at_ms: chunk.created_at_ms,
                    distance: Some(chunk.distance),
                    text: context,
                    citation_suffix: None,
                });
            }

            for chunk in external_chunks {
                let context = match db::build_external_document_chunk_rag_context(
                    app_dir,
                    key,
                    &chunk.doc_id,
                    chunk.chunk_index,
                ) {
                    Ok(v) => v,
                    Err(_) => continue,
                };
                candidates.push(ContextItem {
                    source: ContextSource::ExternalDocument,
                    id: format!("{}:{}", chunk.doc_id, chunk.chunk_index),
                    created_at_ms: chunk.created_at_ms,
                    distance: Some(chunk.distance),
                    text: context,
                    citation_suffix: None,
                });
            }

            let legacy_contexts = build_contexts_v2(question, candidates.clone(), legacy_top_k);
            let merged = merge_knowledge_and_legacy_contexts(
                knowledge_contexts.clone(),
                legacy_contexts,
                top_k,
            );
            let why_used = context_usage_reason(question);
            let mut context_by_text =
                std::collections::HashMap::<String, ContextWithEvidence>::new();
            for entry in knowledge_entries {
                context_by_text.insert(
                    entry.rendered_text.clone(),
                    ContextWithEvidence {
                        text: entry.rendered_text.clone(),
                        direct_sources: build_direct_sources_from_knowledge_entry(
                            conn, key, &entry,
                        ),
                        memory_cards: build_memory_card_from_document(
                            conn,
                            key,
                            &entry.block.document_id,
                            &why_used,
                        )
                        .into_iter()
                        .collect(),
                    },
                );
            }
            for candidate in candidates {
                let direct_sources =
                    build_direct_sources_for_context_candidate(conn, key, &candidate);
                context_by_text.insert(
                    candidate.text.clone(),
                    ContextWithEvidence {
                        text: candidate.text,
                        direct_sources,
                        memory_cards: Vec::new(),
                    },
                );
            }
            contexts = merged
                .into_iter()
                .filter_map(|text| context_by_text.remove(&text))
                .collect();
            resources_catalog = attachment_resources.catalog_markdown;
        }
    }
    let actions = build_actions_context(conn, key, question)?;
    let history = build_recent_conversation_history(conn, key, conversation_id)?;
    let prompt = build_prompt_with_actions_and_history(
        question,
        &contexts
            .iter()
            .map(|ctx| ctx.text.clone())
            .collect::<Vec<_>>(),
        actions.as_deref(),
        history.as_deref(),
        resources_catalog.as_deref(),
    );

    ask_ai_stream_and_persist(
        conn,
        key,
        conversation_id,
        question,
        &prompt,
        &contexts,
        &attachment_direct_sources,
        provider,
        on_event,
    )
}

#[allow(clippy::too_many_arguments)]
pub fn ask_ai_with_provider_using_active_embeddings_time_window(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    conversation_id: &str,
    question: &str,
    top_k: usize,
    focus: Focus,
    time_start_ms: i64,
    time_end_ms: i64,
    provider: &(impl AnswerProvider + ?Sized),
    on_event: &mut dyn FnMut(ChatDelta) -> Result<()>,
) -> Result<AskAiResult> {
    let mut contexts: Vec<ContextWithEvidence> = Vec::new();
    let conversation_filter = match focus {
        Focus::AllMemories => None,
        Focus::ThisThread => Some(conversation_id),
    };
    if top_k > 0 {
        let knowledge_entries = try_build_knowledge_context_entries(
            conn,
            key,
            question,
            top_k.max(1),
            focus,
            conversation_id,
            Some((time_start_ms, time_end_ms)),
        )?;
        let knowledge_contexts = knowledge_entries
            .iter()
            .map(|entry| entry.rendered_text.clone())
            .collect::<Vec<_>>();
        if fallback::should_use_legacy_retrieval_fallback(&knowledge_contexts) {
            let legacy_top_k = top_k.saturating_sub(knowledge_contexts.len()).max(1);
            let mut candidates: Vec<ContextItem> = Vec::new();

            for m in db::list_memory_messages_in_range(
                conn,
                key,
                conversation_filter,
                time_start_ms,
                time_end_ms,
                800,
            )? {
                let context = db::build_message_rag_context(conn, key, &m.id, &m.content)
                    .unwrap_or(m.content);
                let citation_suffix = message_citation_link(&m.id);
                candidates.push(ContextItem {
                    source: ContextSource::Message,
                    id: m.id,
                    created_at_ms: m.created_at_ms,
                    distance: None,
                    text: context,
                    citation_suffix,
                });
            }

            for a in db::list_todo_activities_in_range(conn, key, time_start_ms, time_end_ms)?
                .into_iter()
                .take(300)
            {
                let mut text = format!(
                    "TODO_ACTIVITY todo_id={} type={} created_at_ms={}",
                    a.todo_id, a.activity_type, a.created_at_ms
                );
                if let Some(from) = a.from_status.as_deref() {
                    text.push_str(&format!(" from={from}"));
                }
                if let Some(to) = a.to_status.as_deref() {
                    text.push_str(&format!(" to={to}"));
                }
                if let Some(content) = a.content.as_deref() {
                    text.push_str(&format!(" content={content}"));
                }
                candidates.push(ContextItem {
                    source: ContextSource::TodoActivity,
                    id: a.id,
                    created_at_ms: a.created_at_ms,
                    distance: None,
                    text,
                    citation_suffix: None,
                });
            }

            for e in db::list_events_in_range(conn, key, time_start_ms, time_end_ms)?
                .into_iter()
                .take(200)
            {
                let text = format!(
                    "EVENT {} (start_at_ms={}, end_at_ms={}, tz={})",
                    e.title, e.start_at_ms, e.end_at_ms, e.tz
                );
                candidates.push(ContextItem {
                    source: ContextSource::Event,
                    id: e.id,
                    created_at_ms: e.start_at_ms,
                    distance: None,
                    text,
                    citation_suffix: None,
                });
            }

            let mut seen_todos: std::collections::HashSet<String> =
                std::collections::HashSet::new();
            for todo in db::list_todos(conn, key)?.into_iter() {
                if !seen_todos.insert(todo.id.clone()) {
                    continue;
                }
                let due_in_range = todo
                    .due_at_ms
                    .is_some_and(|ms| ms >= time_start_ms && ms < time_end_ms);
                let review_in_range = todo
                    .next_review_at_ms
                    .is_some_and(|ms| ms >= time_start_ms && ms < time_end_ms);
                if !due_in_range && !review_in_range {
                    continue;
                }

                let ctx = build_todo_thread_context(conn, key, &todo.id)?;
                candidates.push(ContextItem {
                    source: ContextSource::TodoThread,
                    id: todo.id,
                    created_at_ms: todo.created_at_ms,
                    distance: None,
                    text: ctx,
                    citation_suffix: None,
                });
            }

            let attachment_shas = list_attachment_shas_in_time_window(
                conn,
                key,
                conversation_filter,
                time_start_ms,
                time_end_ms,
            )?;
            if !attachment_shas.is_empty() {
                let allowed_attachment_shas = attachment_shas
                    .into_iter()
                    .collect::<std::collections::HashSet<_>>();
                db::process_attachment_text_chunks(conn, key, 256)?;
                for chunk in db::search_similar_attachment_chunks_active(
                    conn,
                    key,
                    app_dir,
                    question,
                    legacy_top_k.saturating_mul(2).max(legacy_top_k),
                )?
                .into_iter()
                .filter(|chunk| allowed_attachment_shas.contains(&chunk.attachment_sha256))
                .take(legacy_top_k)
                {
                    let text = match db::read_attachment_chunk_text(
                        conn,
                        key,
                        &chunk.attachment_sha256,
                        &chunk.kind,
                        chunk.chunk_index,
                    ) {
                        Ok(value) => value,
                        Err(_) => continue,
                    };
                    let created_at_ms =
                        db::read_attachment_by_sha256(conn, &chunk.attachment_sha256)
                            .ok()
                            .flatten()
                            .map(|attachment| attachment.created_at_ms)
                            .unwrap_or_default();
                    let citation = format!(
                        "[Attachment](secondloop://attachment/{}?kind={}&chunk={})",
                        chunk.attachment_sha256, chunk.kind, chunk.chunk_index
                    );
                    let context = format!(
                        "ATTACHMENT_CHUNK {} {}#{}\n{}\n{}",
                        chunk.attachment_sha256, chunk.kind, chunk.chunk_index, text, citation
                    );
                    candidates.push(ContextItem {
                        source: ContextSource::AttachmentChunk,
                        id: format!(
                            "{}:{}:{}",
                            chunk.attachment_sha256, chunk.kind, chunk.chunk_index
                        ),
                        created_at_ms,
                        distance: Some(chunk.distance),
                        text: context,
                        citation_suffix: None,
                    });
                }
            }

            for chunk in db::search_similar_external_document_chunks_active(
                app_dir,
                key,
                question,
                legacy_top_k,
            )
            .unwrap_or_default()
            {
                let context = match db::build_external_document_chunk_rag_context(
                    app_dir,
                    key,
                    &chunk.doc_id,
                    chunk.chunk_index,
                ) {
                    Ok(value) => value,
                    Err(_) => continue,
                };
                candidates.push(ContextItem {
                    source: ContextSource::ExternalDocument,
                    id: format!("{}:{}", chunk.doc_id, chunk.chunk_index),
                    created_at_ms: chunk.created_at_ms,
                    distance: Some(chunk.distance),
                    text: context,
                    citation_suffix: None,
                });
            }

            let legacy_contexts = build_contexts_v2(question, candidates.clone(), legacy_top_k);
            let merged = merge_knowledge_and_legacy_contexts(
                knowledge_contexts.clone(),
                legacy_contexts,
                top_k.max(1),
            );
            let why_used = context_usage_reason(question);
            let mut context_by_text =
                std::collections::HashMap::<String, ContextWithEvidence>::new();
            for entry in knowledge_entries {
                context_by_text.insert(
                    entry.rendered_text.clone(),
                    ContextWithEvidence {
                        text: entry.rendered_text.clone(),
                        direct_sources: build_direct_sources_from_knowledge_entry(
                            conn, key, &entry,
                        ),
                        memory_cards: build_memory_card_from_document(
                            conn,
                            key,
                            &entry.block.document_id,
                            &why_used,
                        )
                        .into_iter()
                        .collect(),
                    },
                );
            }
            for candidate in candidates {
                let direct_sources =
                    build_direct_sources_for_context_candidate(conn, key, &candidate);
                context_by_text.insert(
                    candidate.text.clone(),
                    ContextWithEvidence {
                        text: candidate.text,
                        direct_sources,
                        memory_cards: Vec::new(),
                    },
                );
            }
            contexts = merged
                .into_iter()
                .filter_map(|text| context_by_text.remove(&text))
                .collect();
        } else {
            let why_used = context_usage_reason(question);
            contexts = knowledge_entries
                .into_iter()
                .map(|entry| ContextWithEvidence {
                    text: entry.rendered_text.clone(),
                    direct_sources: build_direct_sources_from_knowledge_entry(conn, key, &entry),
                    memory_cards: build_memory_card_from_document(
                        conn,
                        key,
                        &entry.block.document_id,
                        &why_used,
                    )
                    .into_iter()
                    .collect(),
                })
                .collect();
        }
    }

    let attachment_resources = collect_time_window_attachment_resources(
        conn,
        key,
        conversation_filter,
        time_start_ms,
        time_end_ms,
    )?;
    let actions = build_actions_context(conn, key, question)?;
    let history = build_recent_conversation_history_in_range(
        conn,
        key,
        conversation_id,
        time_start_ms,
        time_end_ms,
    )?;
    let attachment_direct_sources = attachment_resources
        .resources
        .iter()
        .map(|resource| {
            build_attachment_resource_direct_source(
                &resource.attachment_sha256,
                &resource.label,
                resource.created_at_ms,
            )
        })
        .collect::<Vec<_>>();
    let prompt = build_prompt_with_actions_and_history(
        question,
        &contexts
            .iter()
            .map(|ctx| ctx.text.clone())
            .collect::<Vec<_>>(),
        actions.as_deref(),
        history.as_deref(),
        attachment_resources.catalog_markdown.as_deref(),
    );

    ask_ai_stream_and_persist(
        conn,
        key,
        conversation_id,
        question,
        &prompt,
        &contexts,
        &attachment_direct_sources,
        provider,
        on_event,
    )
}

#[cfg(test)]
mod tests {
    use super::{
        build_message_direct_source, filter_direct_sources_for_question, format_history_line,
        should_include_actions_context,
    };
    use crate::db;
    use crate::message_citations::AnswerEvidenceDirectSource;

    #[test]
    fn format_history_line_moves_citation_below_content() {
        let line = format_history_line("User", "history-1", "Project kickoff moved to Friday.");
        assert_eq!(
            line,
            "User: Project kickoff moved to Friday.
[History](secondloop://message/history-1)
"
        );
    }

    #[test]
    fn format_history_line_preserves_trailing_newline_before_citation() {
        let line = format_history_line(
            "Assistant",
            "history-2",
            "Line one
",
        );
        assert_eq!(
            line,
            "Assistant: Line one
[History](secondloop://message/history-2)
"
        );
    }

    #[test]
    fn build_message_direct_source_omits_blank_messages() {
        let message = db::Message {
            id: "blank-message".to_string(),
            conversation_id: "conv".to_string(),
            role: "user".to_string(),
            content: "   \n\t  ".to_string(),
            created_at_ms: 1,
            is_memory: true,
            citations_json: None,
        };

        assert!(build_message_direct_source(&message).is_none());
    }

    #[test]
    fn generic_today_query_does_not_trigger_actions_context() {
        assert!(!should_include_actions_context(
            "分析一下我今天拍的视频开头台词"
        ));
        assert!(!should_include_actions_context(
            "Summarize today's video intro"
        ));
    }

    #[test]
    fn today_task_query_triggers_actions_context() {
        assert!(should_include_actions_context("今天有哪些事要做？"));
        assert!(should_include_actions_context("What should I do today?"));
    }

    #[test]
    fn project_planning_queries_do_not_trigger_actions_context() {
        assert!(!should_include_actions_context("帮我写项目计划"));
        assert!(!should_include_actions_context(
            "Summarize the active task pattern"
        ));
    }

    #[test]
    fn filter_direct_sources_prefers_question_matching_messages() {
        fn source(id: &str, text: &str) -> AnswerEvidenceDirectSource {
            AnswerEvidenceDirectSource {
                id: id.to_string(),
                href: format!("secondloop://message/{id}"),
                source_type: "message".to_string(),
                label: "History".to_string(),
                source_type_label: Some("chat_message".to_string()),
                scope_label: None,
                confidence_label: None,
                title: Some(text.to_string()),
                snippet: text.to_string(),
                highlighted_text: Some(text.to_string()),
                created_at_ms: Some(1),
                updated_at_ms: Some(1),
                anchors: None,
                document_id: None,
                unit_id: None,
            }
        }

        let filtered = filter_direct_sources_for_question(
            "分析最近的视频开头台词",
            vec![
                source("video-1", "分析叁月聚粮最近的视频，尤其是开头部分的台词"),
                source("video-2", "今天要上传短视频"),
                source("work", "今天要上班"),
                source("url", "https://github.com/QwenLM/Qwen3-ASR"),
                source("test", "test"),
            ],
        );

        let ids = filtered
            .into_iter()
            .map(|source| source.id)
            .collect::<Vec<_>>();
        assert_eq!(ids, vec!["video-1".to_string(), "video-2".to_string()]);
    }
}
