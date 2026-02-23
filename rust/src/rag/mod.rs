use anyhow::{anyhow, Result};
use rusqlite::Connection;
use std::path::Path;

use crate::db;
use crate::embedding::Embedder;
use crate::llm::ChatDelta;

const DEFAULT_MAX_CONTEXT_CHARS: usize = 6000;
const DEFAULT_MAX_HISTORY_MESSAGES: usize = 6;
const DEFAULT_MAX_HISTORY_MESSAGE_CHARS: usize = 1200;
const DEFAULT_COMPRESS_SENTENCES: usize = 3;
const DEFAULT_MMR_LAMBDA: f64 = 0.55;

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

pub trait AnswerProvider {
    fn stream_answer(
        &self,
        prompt: &str,
        on_event: &mut dyn FnMut(ChatDelta) -> Result<()>,
    ) -> Result<()>;
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum ContextSource {
    Message,
    TodoThread,
    Event,
    TodoActivity,
}

#[derive(Clone, Debug)]
struct ContextItem {
    source: ContextSource,
    id: String,
    created_at_ms: i64,
    distance: Option<f64>,
    text: String,
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

fn build_prompt_with_actions(question: &str, contexts: &[String], actions: Option<&str>) -> String {
    build_prompt_with_actions_and_history(question, contexts, actions, None)
}

fn build_prompt_with_actions_and_history(
    question: &str,
    contexts: &[String],
    actions: Option<&str>,
    history: Option<&str>,
) -> String {
    let mut out = String::new();
    out.push_str("You are SecondLoop, a helpful personal assistant.\n");
    out.push_str("IMPORTANT: Reply in the same language as the user's question. Ignore any configured UI language. Only switch languages if the user explicitly asks.\n");

    if let Some(history) = history {
        if !history.trim().is_empty() {
            out.push_str("\nRecent conversation (most recent last):\n");
            out.push_str(history);
        }
    }

    if !contexts.is_empty() {
        out.push_str("\nRelevant memories (quoted):\n");
        for (i, ctx) in contexts.iter().enumerate() {
            out.push_str(&format!("{}. \"{}\"\n", i + 1, ctx));
        }
    }

    if let Some(actions) = actions {
        out.push('\n');
        out.push_str(actions);
    }

    out.push_str(
        "\nAnswer the user's question. If the memories are irrelevant, answer normally.\n",
    );
    out.push_str(
        "\nIf you suggest actionable todos or calendar events, append ONE machine-readable block like:\n",
    );
    out.push_str("```secondloop_actions\n");
    out.push_str("{\"version\":1,\"suggestions\":[{\"type\":\"todo\",\"title\":\"...\",\"when\":\"...\"}]}\n");
    out.push_str("```\n");
    out.push_str(
        "- `suggestions[].type` must be `todo` or `event`\n- `title` is required\n- `when` is optional natural language (do NOT compute absolute dates)\n- Omit the block entirely if you have no suggestions\n",
    );
    out.push_str("\nQuestion: ");
    out.push_str(question);
    out.push('\n');
    out
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
        kept.push((role.to_string(), truncated));
        if kept.len() >= DEFAULT_MAX_HISTORY_MESSAGES {
            break;
        }
    }

    if kept.is_empty() {
        return Ok(None);
    }

    kept.reverse();

    let mut out = String::new();
    for (role, content) in kept {
        out.push_str(&role);
        out.push_str(": ");
        out.push_str(&content);
        out.push('\n');
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
        kept.push((role.to_string(), truncated));
        if kept.len() >= DEFAULT_MAX_HISTORY_MESSAGES {
            break;
        }
    }

    if kept.is_empty() {
        return Ok(None);
    }

    kept.reverse();

    let mut out = String::new();
    for (role, content) in kept {
        out.push_str(&role);
        out.push_str(": ");
        out.push_str(&content);
        out.push('\n');
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

fn lite_normalize_text(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for ch in text.chars() {
        if ch.is_alphanumeric() {
            out.extend(ch.to_lowercase());
        } else {
            out.push(' ');
        }
    }
    out.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn lite_compact_text(text: &str) -> String {
    text.chars().filter(|c| !c.is_whitespace()).collect()
}

fn lite_collect_bigrams(chars: &[char]) -> std::collections::HashSet<u64> {
    let mut set = std::collections::HashSet::new();
    if chars.len() < 2 {
        return set;
    }
    for i in 0..(chars.len() - 1) {
        let a = chars[i] as u64;
        let b = chars[i + 1] as u64;
        set.insert((a << 32) | b);
    }
    set
}

fn lite_score(query: &str, candidate: &str) -> u64 {
    let query_norm = lite_normalize_text(query);
    let query_compact = lite_compact_text(&query_norm);
    if query_compact.is_empty() {
        return 0;
    }

    let cand_norm = lite_normalize_text(candidate);
    if cand_norm.is_empty() {
        return 0;
    }

    let cand_compact = lite_compact_text(&cand_norm);
    if cand_compact.is_empty() {
        return 0;
    }

    let query_chars: Vec<char> = query_compact.chars().collect();
    let query_bigrams = lite_collect_bigrams(&query_chars);

    let mut score = 0u64;

    if cand_norm == query_norm {
        score = score.saturating_add(10_000);
    }

    if !query_norm.is_empty() && cand_norm.contains(&query_norm) {
        score = score.saturating_add(500);
        score = score.saturating_add((query_compact.chars().count() as u64).saturating_mul(50));
    }

    for token in query_norm.split_whitespace() {
        if token.len() < 2 {
            continue;
        }
        if cand_norm.contains(token) {
            score = score.saturating_add((token.chars().count() as u64).saturating_mul(200));
        }
    }

    if !query_bigrams.is_empty() {
        let cand_chars: Vec<char> = cand_compact.chars().collect();
        let cand_bigrams = lite_collect_bigrams(&cand_chars);
        let overlap = query_bigrams.intersection(&cand_bigrams).count() as u64;
        score = score.saturating_add(overlap.saturating_mul(50));
    }

    score
}

fn lite_score_strict(query: &str, candidate: &str) -> u64 {
    let query_norm = lite_normalize_text(query);
    let query_compact = lite_compact_text(&query_norm);
    if query_compact.is_empty() {
        return 0;
    }

    let cand_norm = lite_normalize_text(candidate);
    if cand_norm.is_empty() {
        return 0;
    }

    let cand_compact = lite_compact_text(&cand_norm);
    if cand_compact.is_empty() {
        return 0;
    }

    let mut score = 0u64;

    if cand_norm == query_norm {
        score = score.saturating_add(10_000);
    }

    if !query_norm.is_empty() && cand_norm.contains(&query_norm) {
        score = score.saturating_add(500);
        score = score.saturating_add((query_compact.chars().count() as u64).saturating_mul(50));
    }

    for token in query_norm.split_whitespace() {
        if token.len() < 3 {
            continue;
        }
        if cand_norm.contains(token) {
            score = score.saturating_add((token.chars().count() as u64).saturating_mul(300));
        }
    }

    score
}

fn lite_similarity(a: &str, b: &str) -> f64 {
    let a_norm = lite_normalize_text(a);
    let a_compact = lite_compact_text(&a_norm);
    let b_norm = lite_normalize_text(b);
    let b_compact = lite_compact_text(&b_norm);
    if a_compact.is_empty() || b_compact.is_empty() {
        return 0.0;
    }
    let a_chars: Vec<char> = a_compact.chars().collect();
    let b_chars: Vec<char> = b_compact.chars().collect();
    let a_bigrams = lite_collect_bigrams(&a_chars);
    let b_bigrams = lite_collect_bigrams(&b_chars);
    if a_bigrams.is_empty() || b_bigrams.is_empty() {
        return 0.0;
    }
    let inter = a_bigrams.intersection(&b_bigrams).count() as f64;
    let union = a_bigrams.union(&b_bigrams).count() as f64;
    if union <= 0.0 {
        0.0
    } else {
        (inter / union).clamp(0.0, 1.0)
    }
}

fn split_sentences(text: &str) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    let mut buf = String::new();
    for ch in text.chars() {
        let is_boundary = ch == '\n'
            || ch == '.'
            || ch == '!'
            || ch == '?'
            || ch == '。'
            || ch == '！'
            || ch == '？';

        if is_boundary {
            let trimmed = buf.trim();
            if !trimmed.is_empty() {
                out.push(trimmed.to_string());
            }
            buf.clear();
            continue;
        }

        buf.push(ch);
    }
    let trimmed = buf.trim();
    if !trimmed.is_empty() {
        out.push(trimmed.to_string());
    }
    out
}

fn compress_context_text(query: &str, text: &str) -> String {
    let sentences = split_sentences(text);
    if sentences.is_empty() {
        return String::new();
    }

    let mut scored: Vec<(usize, u64)> = Vec::new();
    for (i, s) in sentences.iter().enumerate() {
        let score = lite_score_strict(query, s);
        if score == 0 {
            continue;
        }
        scored.push((i, score));
    }

    if scored.is_empty() {
        let take_n = DEFAULT_COMPRESS_SENTENCES.min(sentences.len());
        return sentences
            .into_iter()
            .take(take_n)
            .collect::<Vec<_>>()
            .join("\n");
    }

    scored.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0)));
    if scored.len() > DEFAULT_COMPRESS_SENTENCES {
        scored.truncate(DEFAULT_COMPRESS_SENTENCES);
    }
    scored.sort_by(|a, b| a.0.cmp(&b.0));

    let mut selected: Vec<String> = Vec::new();
    for (idx, _) in scored {
        if let Some(s) = sentences.get(idx) {
            selected.push(s.to_string());
        }
    }
    selected.join("\n")
}

fn rank_context_items(question: &str, candidates: &[ContextItem]) -> Vec<(f64, usize)> {
    let now = now_ms();
    let mut scored: Vec<(f64, usize)> = Vec::new();

    for (i, item) in candidates.iter().enumerate() {
        let semantic = item
            .distance
            .map(|d| 1.0 / (1.0 + d.max(0.0)))
            .unwrap_or(0.0);

        let lex_score = lite_score(question, &item.text);
        let lexical = if lex_score == 0 {
            0.0
        } else {
            let s = lex_score as f64;
            (s / (s + 4000.0)).clamp(0.0, 1.0)
        };

        let age_ms = now.saturating_sub(item.created_at_ms).max(0) as f64;
        let age_days = age_ms / (24.0 * 60.0 * 60.0 * 1000.0);
        let recency = (-age_days / 14.0).exp().clamp(0.0, 1.0);

        // When distance is missing (e.g. time-window retrieval), lexical should dominate.
        let semantic_w = if item.distance.is_some() { 0.6 } else { 0.0 };
        let lexical_w = if item.distance.is_some() { 0.3 } else { 0.9 };
        let recency_w = 0.1;

        let relevance = (semantic_w * semantic) + (lexical_w * lexical) + (recency_w * recency);
        scored.push((relevance, i));
    }

    scored.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap_or(std::cmp::Ordering::Equal));
    scored
}

fn mmr_select_indices(question: &str, candidates: &[ContextItem], max_items: usize) -> Vec<usize> {
    let ranked = rank_context_items(question, candidates);
    let max_items = max_items.min(ranked.len());
    if max_items == 0 {
        return Vec::new();
    }

    let mut selected: Vec<usize> = Vec::new();
    let mut remaining: Vec<usize> = ranked.iter().map(|(_, idx)| *idx).collect();

    // Start with highest relevance.
    if let Some(first) = remaining.first().copied() {
        selected.push(first);
        remaining.retain(|i| *i != first);
    }

    let relevance_by_idx: std::collections::HashMap<usize, f64> = ranked
        .into_iter()
        .map(|(relevance, idx)| (idx, relevance))
        .collect();

    while selected.len() < max_items && !remaining.is_empty() {
        let mut best_idx: Option<usize> = None;
        let mut best_score: f64 = f64::NEG_INFINITY;

        for &idx in &remaining {
            let relevance = *relevance_by_idx.get(&idx).unwrap_or(&0.0);
            let mut max_sim = 0.0f64;
            for &sidx in &selected {
                let sim = lite_similarity(&candidates[idx].text, &candidates[sidx].text);
                if sim > max_sim {
                    max_sim = sim;
                }
            }
            let mmr_score =
                (DEFAULT_MMR_LAMBDA * relevance) - ((1.0 - DEFAULT_MMR_LAMBDA) * max_sim);
            if mmr_score > best_score {
                best_score = mmr_score;
                best_idx = Some(idx);
            }
        }

        let Some(chosen) = best_idx else { break };
        selected.push(chosen);
        remaining.retain(|i| *i != chosen);
    }

    selected
}

fn build_contexts_v2(question: &str, candidates: Vec<ContextItem>, top_k: usize) -> Vec<String> {
    let max_items = top_k.max(1);
    let selected_indices = mmr_select_indices(question, &candidates, max_items);

    let mut out: Vec<String> = Vec::new();
    let mut seen: std::collections::HashSet<String> = std::collections::HashSet::new();
    let mut used_chars: usize = 0;

    for idx in selected_indices {
        let item = &candidates[idx];
        let mut text = compress_context_text(question, &item.text);
        if text.is_empty() {
            continue;
        }

        // Add lightweight source tags for debugability without bloating too much.
        let prefix = match item.source {
            ContextSource::Message => None,
            ContextSource::TodoThread => Some(format!("TODO_THREAD id={}\n", item.id)),
            ContextSource::Event => Some(format!("EVENT id={}\n", item.id)),
            ContextSource::TodoActivity => Some(format!("TODO_ACTIVITY id={}\n", item.id)),
        };
        if let Some(p) = prefix {
            let mut combined = String::with_capacity(p.len() + text.len());
            combined.push_str(&p);
            combined.push_str(&text);
            text = combined;
        }

        if !seen.insert(text.clone()) {
            continue;
        }

        let len = text.len();
        if used_chars > 0 && used_chars.saturating_add(len) > DEFAULT_MAX_CONTEXT_CHARS {
            break;
        }
        if used_chars == 0 && len > DEFAULT_MAX_CONTEXT_CHARS {
            // Still include one context rather than returning empty.
            out.push(text);
            break;
        }

        used_chars = used_chars.saturating_add(len);
        out.push(text);
    }

    out
}

pub fn build_prompt(question: &str, contexts: &[String]) -> String {
    build_prompt_with_actions(question, contexts, None)
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

    let mut contexts_with_distance: Vec<(f64, String)> = Vec::new();
    for sm in similar_messages {
        let context = db::build_message_rag_context(conn, key, &sm.message.id, &sm.message.content)
            .unwrap_or_else(|_| sm.message.content.clone());
        contexts_with_distance.push((sm.distance, context));
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
        contexts_with_distance.push((st.distance, ctx));
    }
    contexts_with_distance
        .sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));
    contexts_with_distance.truncate(top_k);
    let contexts: Vec<String> = contexts_with_distance
        .into_iter()
        .map(|(_, ctx)| ctx)
        .collect();
    let actions = build_actions_context(conn, key, question)?;
    let history = build_recent_conversation_history(conn, key, conversation_id)?;
    let prompt = build_prompt_with_actions_and_history(
        question,
        &contexts,
        actions.as_deref(),
        history.as_deref(),
    );

    let mut has_text = false;
    let mut assistant_text = String::new();
    let result = provider.stream_answer(&prompt, &mut |ev| {
        let done = ev.done;
        let text_delta = ev.text_delta.clone();
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

            let user_message =
                db::insert_message_non_memory(conn, key, conversation_id, "user", question)?;
            let assistant_message = db::insert_message_non_memory(
                conn,
                key,
                conversation_id,
                "assistant",
                &assistant_text,
            )?;

            Ok(AskAiResult {
                user_message_id: user_message.id,
                assistant_message_id: assistant_message.id,
            })
        }
        Err(e) => Err(e),
    }
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
    let mut contexts: Vec<String> = Vec::new();
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

        let mut contexts_with_distance: Vec<(f64, String)> = Vec::new();
        for sm in similar_messages {
            let context =
                db::build_message_rag_context(conn, key, &sm.message.id, &sm.message.content)
                    .unwrap_or_else(|_| sm.message.content.clone());
            contexts_with_distance.push((sm.distance, context));
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
            contexts_with_distance.push((st.distance, ctx));
        }
        contexts_with_distance
            .sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));
        contexts_with_distance.truncate(top_k);
        contexts = contexts_with_distance
            .into_iter()
            .map(|(_, ctx)| ctx)
            .collect();
    }
    let actions = build_actions_context(conn, key, question)?;
    let history = build_recent_conversation_history(conn, key, conversation_id)?;
    let prompt = build_prompt_with_actions_and_history(
        question,
        &contexts,
        actions.as_deref(),
        history.as_deref(),
    );

    let mut has_text = false;
    let mut assistant_text = String::new();
    let result = provider.stream_answer(&prompt, &mut |ev| {
        let done = ev.done;
        let text_delta = ev.text_delta.clone();
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

            let user_message =
                db::insert_message_non_memory(conn, key, conversation_id, "user", question)?;
            let assistant_message = db::insert_message_non_memory(
                conn,
                key,
                conversation_id,
                "assistant",
                &assistant_text,
            )?;

            Ok(AskAiResult {
                user_message_id: user_message.id,
                assistant_message_id: assistant_message.id,
            })
        }
        Err(e) => Err(e),
    }
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
    let mut contexts: Vec<String> = Vec::new();
    if top_k > 0 {
        db::process_pending_message_embeddings_active(conn, key, app_dir, 1024)?;
        db::process_pending_todo_embeddings_active(conn, key, app_dir, 1024)?;
        db::process_pending_todo_activity_embeddings_active(conn, key, app_dir, 1024)?;

        let top_k = top_k.max(1);

        let top_k_candidate_messages = (top_k.saturating_mul(8)).min(200).max(top_k);
        let top_k_candidate_todos = (top_k.saturating_mul(4)).min(80).max(top_k);

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
            });
        }

        contexts = build_contexts_v2(question, candidates, top_k);
    }
    let actions = build_actions_context(conn, key, question)?;
    let history = build_recent_conversation_history(conn, key, conversation_id)?;
    let prompt = build_prompt_with_actions_and_history(
        question,
        &contexts,
        actions.as_deref(),
        history.as_deref(),
    );

    let mut has_text = false;
    let mut assistant_text = String::new();
    let result = provider.stream_answer(&prompt, &mut |ev| {
        let done = ev.done;
        let text_delta = ev.text_delta.clone();
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

            let user_message =
                db::insert_message_non_memory(conn, key, conversation_id, "user", question)?;
            let assistant_message = db::insert_message_non_memory(
                conn,
                key,
                conversation_id,
                "assistant",
                &assistant_text,
            )?;

            Ok(AskAiResult {
                user_message_id: user_message.id,
                assistant_message_id: assistant_message.id,
            })
        }
        Err(e) => Err(e),
    }
}

#[allow(clippy::too_many_arguments)]
pub fn ask_ai_with_provider_using_active_embeddings_time_window(
    conn: &Connection,
    key: &[u8; 32],
    _app_dir: &Path,
    conversation_id: &str,
    question: &str,
    top_k: usize,
    focus: Focus,
    time_start_ms: i64,
    time_end_ms: i64,
    provider: &(impl AnswerProvider + ?Sized),
    on_event: &mut dyn FnMut(ChatDelta) -> Result<()>,
) -> Result<AskAiResult> {
    let mut contexts: Vec<String> = Vec::new();
    if top_k > 0 {
        let conversation_filter = match focus {
            Focus::AllMemories => None,
            Focus::ThisThread => Some(conversation_id),
        };

        let mut candidates: Vec<ContextItem> = Vec::new();

        for m in db::list_memory_messages_in_range(
            conn,
            key,
            conversation_filter,
            time_start_ms,
            time_end_ms,
            800,
        )? {
            let context =
                db::build_message_rag_context(conn, key, &m.id, &m.content).unwrap_or(m.content);
            candidates.push(ContextItem {
                source: ContextSource::Message,
                id: m.id,
                created_at_ms: m.created_at_ms,
                distance: None,
                text: context,
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
            });
        }

        let mut seen_todos: std::collections::HashSet<String> = std::collections::HashSet::new();
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
            });
        }

        contexts = build_contexts_v2(question, candidates, top_k.max(1));
    }

    let actions = build_actions_context(conn, key, question)?;
    let history = build_recent_conversation_history_in_range(
        conn,
        key,
        conversation_id,
        time_start_ms,
        time_end_ms,
    )?;
    let prompt = build_prompt_with_actions_and_history(
        question,
        &contexts,
        actions.as_deref(),
        history.as_deref(),
    );

    let mut has_text = false;
    let mut assistant_text = String::new();
    let result = provider.stream_answer(&prompt, &mut |ev| {
        let done = ev.done;
        let text_delta = ev.text_delta.clone();
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

            let user_message =
                db::insert_message_non_memory(conn, key, conversation_id, "user", question)?;
            let assistant_message = db::insert_message_non_memory(
                conn,
                key,
                conversation_id,
                "assistant",
                &assistant_text,
            )?;

            Ok(AskAiResult {
                user_message_id: user_message.id,
                assistant_message_id: assistant_message.id,
            })
        }
        Err(e) => Err(e),
    }
}
