use anyhow::{anyhow, Result};
use rusqlite::Connection;
use std::path::Path;

use crate::db;
use crate::embedding::Embedder;
use crate::llm::ChatDelta;
use crate::message_citations::{
    append_message_citation_if_missing as append_message_citation, AnswerEvidenceDirectSource,
};

mod active_embeddings;
mod attachment_resources;
mod citations_prompt;
mod context_selection;
mod evidence;
#[cfg(test)]
mod fallback;
mod history;
#[cfg(test)]
mod knowledge_ask_ai_tests;
mod knowledge_contexts;
#[cfg(test)]
mod knowledge_contexts_page_tests;
#[cfg(test)]
mod knowledge_contexts_refresh_tests;
#[cfg(test)]
mod knowledge_contexts_scope_tests;
#[cfg(test)]
mod knowledge_contexts_tests;
#[cfg(test)]
mod tests;

use attachment_resources::{
    collect_attachment_resources_by_embedding, collect_attachment_resources_default,
};
use citations_prompt::{build_prompt as build_prompt_base, build_prompt_with_actions_and_history};
use context_selection::{ContextItem, ContextSource};
use evidence::{
    build_attachment_direct_source, build_attachment_resource_direct_source,
    build_message_direct_source, build_todo_direct_source,
    encode_context_evidence_json_for_question,
};
use history::{build_recent_conversation_history, build_recent_conversation_history_in_range};
const DETACHED_ASK_REQUEST_ID_ROLE_PREFIX: &str = "secondloop_request_id:";

#[cfg(test)]
fn format_history_line(role: &str, message_id: &str, content: &str) -> String {
    match crate::message_citations::message_citation_link(message_id) {
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
}

fn now_ms() -> i64 {
    crate::platform::time::now_ms()
}

fn agenda_horizon_ms(question: &str, now_ms: i64) -> Option<i64> {
    let q = question.trim().to_lowercase();
    if q.is_empty() {
        return None;
    }

    let is_today = has_today_timeframe(question);
    let is_this_week = has_this_week_timeframe(question);
    let is_agenda = has_agenda_keywords(question);
    let has_timeframe = has_future_actions_timeframe(question);
    if !(has_agenda_request(question) && has_timeframe) {
        return None;
    }
    if is_today {
        return Some(now_ms.saturating_add(36 * 60 * 60 * 1000));
    }
    if is_this_week {
        return Some(now_ms.saturating_add(8 * 24 * 60 * 60 * 1000));
    }
    if is_agenda {
        return Some(now_ms.saturating_add(8 * 24 * 60 * 60 * 1000));
    }

    None
}

fn has_today_timeframe(question: &str) -> bool {
    let q = question.trim().to_lowercase();
    q.contains("today")
        || q.contains("tonight")
        || q.contains("today's")
        || question.contains("今天")
        || question.contains("今日")
}

fn has_this_week_timeframe(question: &str) -> bool {
    let q = question.trim().to_lowercase();
    q.contains("this week")
        || q.contains("week agenda")
        || q.contains("weekly agenda")
        || q.contains("this week's")
        || question.contains("本周")
        || question.contains("这周")
        || question.contains("這週")
}

fn has_future_actions_timeframe(question: &str) -> bool {
    let q = question.trim().to_lowercase();
    has_today_timeframe(question)
        || has_this_week_timeframe(question)
        || q.contains("tomorrow")
        || q.contains("next week")
        || question.contains("明天")
}

fn has_past_actions_timeframe(question: &str) -> bool {
    let q = question.trim().to_lowercase();
    q.contains("yesterday")
        || q.contains("last week")
        || question.contains("昨天")
        || question.contains("昨日")
        || question.contains("上周")
        || question.contains("上週")
}

fn has_agenda_keywords(question: &str) -> bool {
    let q = question.trim().to_lowercase();
    q.contains("agenda")
        || q.contains("schedule")
        || q.contains("calendar")
        || question.contains("日程")
        || question.contains("行程")
        || question.contains("安排")
}

fn has_explicit_agenda_intent(question: &str) -> bool {
    let q = question.trim().to_lowercase();
    q.contains("agenda")
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
        || question.contains("有哪些事")
}

fn has_generic_task_words(question: &str) -> bool {
    let q = question.trim().to_lowercase();
    q.contains("task")
        || q.contains("tasks")
        || question.contains("任务")
        || question.contains("任務")
        || question.contains("计划")
        || question.contains("計劃")
}

fn has_past_actions_intent(question: &str) -> bool {
    let q = question.trim().to_lowercase();
    q.contains("what did i do")
        || q.contains("what have i done")
        || q.contains("what did i finish")
        || q.contains("what have i finished")
        || question.contains("做了什么")
        || question.contains("做了哪些事")
        || question.contains("完成了什么")
}

fn has_agenda_request(question: &str) -> bool {
    has_explicit_agenda_intent(question)
        || (has_generic_task_words(question) && has_future_actions_timeframe(question))
}

fn should_include_actions_context(question: &str) -> bool {
    agenda_horizon_ms(question, 0).is_some()
}

fn should_include_actions_context_in_range(question: &str) -> bool {
    let has_timeframe =
        has_future_actions_timeframe(question) || has_past_actions_timeframe(question);
    has_timeframe
        && (has_explicit_agenda_intent(question)
            || (has_generic_task_words(question) && has_timeframe)
            || (has_past_actions_timeframe(question) && has_past_actions_intent(question)))
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

fn build_actions_context_in_range(
    conn: &Connection,
    key: &[u8; 32],
    question: &str,
    time_start_ms: i64,
    time_end_ms: i64,
) -> Result<Option<String>> {
    if !should_include_actions_context_in_range(question) {
        return Ok(None);
    }

    if has_past_actions_timeframe(question) {
        return build_past_actions_context_in_range(conn, key, time_start_ms, time_end_ms);
    }

    build_upcoming_actions_context_in_range(conn, key, time_start_ms, time_end_ms)
}

fn build_upcoming_actions_context_in_range(
    conn: &Connection,
    key: &[u8; 32],
    time_start_ms: i64,
    time_end_ms: i64,
) -> Result<Option<String>> {
    let mut lines: Vec<String> = Vec::new();

    for todo in db::list_todos(conn, key)? {
        if todo.status == "dismissed" || todo.status == "done" {
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

        let mut item = format!("TODO [{}] {}", todo.status, todo.title);
        if let Some(ms) = todo.due_at_ms {
            item.push_str(&format!(" (due_at_ms={ms})"));
        }
        if let Some(ms) = todo.next_review_at_ms {
            item.push_str(&format!(" (next_review_at_ms={ms})"));
        }
        lines.push(item);
    }

    for event in db::list_events(conn, key)? {
        let overlaps_range = event.end_at_ms > time_start_ms && event.start_at_ms < time_end_ms;
        if !overlaps_range {
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

fn build_past_actions_context_in_range(
    conn: &Connection,
    key: &[u8; 32],
    time_start_ms: i64,
    time_end_ms: i64,
) -> Result<Option<String>> {
    let mut lines: Vec<String> = Vec::new();
    let mut latest_activity_by_todo = std::collections::BTreeMap::<String, db::TodoActivity>::new();

    for activity in db::list_todo_activities_in_range(conn, key, time_start_ms, time_end_ms)? {
        let should_replace = latest_activity_by_todo
            .get(&activity.todo_id)
            .map(|current| activity.created_at_ms >= current.created_at_ms)
            .unwrap_or(true);
        if should_replace {
            latest_activity_by_todo.insert(activity.todo_id.clone(), activity);
        }
    }

    for activity in latest_activity_by_todo.into_values() {
        let todo = match db::get_todo(conn, key, &activity.todo_id) {
            Ok(value) => value,
            Err(_) => continue,
        };

        let line = match activity.to_status.as_deref() {
            Some("done") => format!(
                "TODO [done] {} (completed_at_ms={})",
                todo.title, activity.created_at_ms
            ),
            _ => match activity.content.as_deref() {
                Some(content) if !content.trim().is_empty() => format!(
                    "TODO_ACTIVITY [{}] {} (created_at_ms={}) content={}",
                    todo.status, todo.title, activity.created_at_ms, content
                ),
                _ => format!(
                    "TODO_ACTIVITY [{}] {} (created_at_ms={}) type={}",
                    todo.status, todo.title, activity.created_at_ms, activity.activity_type
                ),
            },
        };
        lines.push(line);
    }

    for event in db::list_events_in_range(conn, key, time_start_ms, time_end_ms)? {
        lines.push(format!(
            "EVENT {} (start_at_ms={}, end_at_ms={}, tz={})",
            event.title, event.start_at_ms, event.end_at_ms, event.tz
        ));
    }

    if lines.is_empty() {
        return Ok(None);
    }

    let mut out = String::new();
    out.push_str("Past actions (from local todos/events):\n");
    for line in lines.into_iter().take(40) {
        out.push_str("- ");
        out.push_str(&line);
        out.push('\n');
    }
    Ok(Some(out))
}

fn build_todo_thread_context(conn: &Connection, key: &[u8; 32], todo_id: &str) -> Result<String> {
    let todo = db::get_todo(conn, key, todo_id)?;
    let activities = db::list_todo_activities(conn, key, todo_id)?;

    build_todo_thread_context_from_activities(&todo, activities)
}

fn build_todo_thread_context_in_range(
    conn: &Connection,
    key: &[u8; 32],
    todo_id: &str,
    time_start_ms: i64,
    time_end_ms: i64,
) -> Result<String> {
    let todo = db::get_todo(conn, key, todo_id)?;
    let activities = db::list_todo_activities(conn, key, todo_id)?
        .into_iter()
        .filter(|activity| {
            activity.created_at_ms >= time_start_ms && activity.created_at_ms < time_end_ms
        })
        .collect::<Vec<_>>();

    build_todo_thread_context_from_activities(&todo, activities)
}

fn build_todo_thread_context_from_activities(
    todo: &db::Todo,
    activities: Vec<db::TodoActivity>,
) -> Result<String> {
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

#[allow(clippy::too_many_arguments)]
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
                        if let Some((user_message_id, assistant_message_id)) =
                            db::get_detached_ask_completion_message_ids(
                                conn,
                                request_id,
                                conversation_id,
                            )?
                        {
                            return Ok(AskAiResult {
                                user_message_id,
                                assistant_message_id,
                            });
                        }
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
                        conversation_id,
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
            },
        ));
    }
    let mut seen_todos = std::collections::HashSet::new();
    for st in similar_todos {
        if !seen_todos.insert(st.todo_id.clone()) {
            continue;
        }
        let todo = match db::get_todo(conn, key, &st.todo_id) {
            Ok(value) => value,
            Err(_) => continue,
        };
        let ctx = match build_todo_thread_context(conn, key, &st.todo_id) {
            Ok(v) => v,
            Err(_) => continue,
        };
        let direct_source = build_todo_direct_source(&todo, &ctx, todo.created_at_ms);
        contexts_with_distance.push((
            st.distance,
            ContextWithEvidence {
                text: ctx,
                direct_sources: vec![direct_source],
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
            },
        ));
    }
    contexts_with_distance
        .sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));
    contexts_with_distance.truncate(top_k);
    let contexts: Vec<ContextWithEvidence> = contexts_with_distance
        .into_iter()
        .map(|(_, ctx)| ctx)
        .collect();
    let history = build_recent_conversation_history(conn, key, conversation_id)?;
    let actions = build_actions_context(conn, key, question)?;
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
                },
            ));
        }
        let mut seen_todos = std::collections::HashSet::new();
        for st in similar_todos {
            if !seen_todos.insert(st.todo_id.clone()) {
                continue;
            }
            let todo = match db::get_todo(conn, key, &st.todo_id) {
                Ok(value) => value,
                Err(_) => continue,
            };
            let ctx = match build_todo_thread_context(conn, key, &st.todo_id) {
                Ok(v) => v,
                Err(_) => continue,
            };
            let direct_source = build_todo_direct_source(&todo, &ctx, todo.created_at_ms);
            contexts_with_distance.push((
                st.distance,
                ContextWithEvidence {
                    text: ctx,
                    direct_sources: vec![direct_source],
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
                },
            ));
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
    let history = build_recent_conversation_history(conn, key, conversation_id)?;
    let actions = build_actions_context(conn, key, question)?;
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
    active_embeddings::ask_ai_with_provider_using_active_embeddings(
        conn,
        key,
        app_dir,
        conversation_id,
        question,
        top_k,
        focus,
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
    active_embeddings::ask_ai_with_provider_using_active_embeddings_time_window(
        conn,
        key,
        app_dir,
        conversation_id,
        question,
        top_k,
        focus,
        time_start_ms,
        time_end_ms,
        provider,
        on_event,
    )
}
