use anyhow::{anyhow, Result};
use rusqlite::{params, Connection};
use std::path::Path;

use crate::db;
use crate::embedding::Embedder;
use crate::llm::ChatDelta;

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
    let mut out = String::new();
    out.push_str("You are SecondLoop, a helpful personal assistant.\n");

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

    let similar = match focus {
        Focus::AllMemories => db::search_similar_messages_default(conn, key, question, top_k)?,
        Focus::ThisThread => db::search_similar_messages_in_conversation_default(
            conn,
            key,
            conversation_id,
            question,
            top_k,
        )?,
    };
    let contexts: Vec<String> = similar.into_iter().map(|sm| sm.message.content).collect();
    let actions = build_actions_context(conn, key, question)?;
    let prompt = build_prompt_with_actions(question, &contexts, actions.as_deref());

    let user_message = db::insert_message_non_memory(conn, key, conversation_id, "user", question)?;
    let assistant_message =
        db::insert_message_non_memory(conn, key, conversation_id, "assistant", "")?;

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
                conn.execute(
                    r#"DELETE FROM messages WHERE id = ?1"#,
                    params![assistant_message.id.as_str()],
                )?;
                return Err(anyhow!("empty response from LLM"));
            }
            db::edit_message(conn, key, &assistant_message.id, &assistant_text)?;
        }
        Err(e) => {
            if e.is::<StreamCancelled>() {
                let _ = conn.execute(
                    r#"DELETE FROM message_embeddings WHERE message_id = ?1"#,
                    params![assistant_message.id.as_str()],
                );
                let _ = conn.execute(
                    r#"DELETE FROM message_embeddings WHERE message_id = ?1"#,
                    params![user_message.id.as_str()],
                );
                let _ = conn.execute(
                    r#"DELETE FROM messages WHERE id = ?1"#,
                    params![assistant_message.id.as_str()],
                );
                let _ = conn.execute(
                    r#"DELETE FROM messages WHERE id = ?1"#,
                    params![user_message.id.as_str()],
                );
                return Err(e);
            }

            if !has_text {
                let _ = conn.execute(
                    r#"DELETE FROM messages WHERE id = ?1"#,
                    params![assistant_message.id.as_str()],
                );
            } else {
                let _ = db::edit_message(conn, key, &assistant_message.id, &assistant_text);
            }
            return Err(e);
        }
    }

    Ok(AskAiResult {
        user_message_id: user_message.id,
        assistant_message_id: assistant_message.id,
    })
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
    db::set_active_embedding_model_name(conn, embedder.model_name())?;
    db::process_pending_message_embeddings(conn, key, embedder, 1024)?;

    let similar = match focus {
        Focus::AllMemories => db::search_similar_messages(conn, key, embedder, question, top_k)?,
        Focus::ThisThread => db::search_similar_messages_in_conversation(
            conn,
            key,
            embedder,
            conversation_id,
            question,
            top_k,
        )?,
    };

    let contexts: Vec<String> = similar.into_iter().map(|sm| sm.message.content).collect();
    let actions = build_actions_context(conn, key, question)?;
    let prompt = build_prompt_with_actions(question, &contexts, actions.as_deref());

    let user_message = db::insert_message_non_memory(conn, key, conversation_id, "user", question)?;
    let assistant_message =
        db::insert_message_non_memory(conn, key, conversation_id, "assistant", "")?;

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
                conn.execute(
                    r#"DELETE FROM messages WHERE id = ?1"#,
                    params![assistant_message.id.as_str()],
                )?;
                return Err(anyhow!("empty response from LLM"));
            }
            db::edit_message(conn, key, &assistant_message.id, &assistant_text)?;
        }
        Err(e) => {
            if e.is::<StreamCancelled>() {
                let _ = conn.execute(
                    r#"DELETE FROM message_embeddings WHERE message_id = ?1"#,
                    params![assistant_message.id.as_str()],
                );
                let _ = conn.execute(
                    r#"DELETE FROM message_embeddings WHERE message_id = ?1"#,
                    params![user_message.id.as_str()],
                );
                let _ = conn.execute(
                    r#"DELETE FROM messages WHERE id = ?1"#,
                    params![assistant_message.id.as_str()],
                );
                let _ = conn.execute(
                    r#"DELETE FROM messages WHERE id = ?1"#,
                    params![user_message.id.as_str()],
                );
                return Err(e);
            }

            if !has_text {
                let _ = conn.execute(
                    r#"DELETE FROM messages WHERE id = ?1"#,
                    params![assistant_message.id.as_str()],
                );
            } else {
                let _ = db::edit_message(conn, key, &assistant_message.id, &assistant_text);
            }
            return Err(e);
        }
    }

    Ok(AskAiResult {
        user_message_id: user_message.id,
        assistant_message_id: assistant_message.id,
    })
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
    db::process_pending_message_embeddings_active(conn, key, app_dir, 1024)?;

    let similar = match focus {
        Focus::AllMemories => {
            db::search_similar_messages_active(conn, key, app_dir, question, top_k)?
        }
        Focus::ThisThread => db::search_similar_messages_in_conversation_active(
            conn,
            key,
            app_dir,
            conversation_id,
            question,
            top_k,
        )?,
    };

    let contexts: Vec<String> = similar.into_iter().map(|sm| sm.message.content).collect();
    let actions = build_actions_context(conn, key, question)?;
    let prompt = build_prompt_with_actions(question, &contexts, actions.as_deref());

    let user_message = db::insert_message_non_memory(conn, key, conversation_id, "user", question)?;
    let assistant_message =
        db::insert_message_non_memory(conn, key, conversation_id, "assistant", "")?;

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
                conn.execute(
                    r#"DELETE FROM messages WHERE id = ?1"#,
                    params![assistant_message.id.as_str()],
                )?;
                return Err(anyhow!("empty response from LLM"));
            }
            db::edit_message(conn, key, &assistant_message.id, &assistant_text)?;
        }
        Err(e) => {
            if e.is::<StreamCancelled>() {
                let _ = conn.execute(
                    r#"DELETE FROM message_embeddings WHERE message_id = ?1"#,
                    params![assistant_message.id.as_str()],
                );
                let _ = conn.execute(
                    r#"DELETE FROM message_embeddings WHERE message_id = ?1"#,
                    params![user_message.id.as_str()],
                );
                let _ = conn.execute(
                    r#"DELETE FROM messages WHERE id = ?1"#,
                    params![assistant_message.id.as_str()],
                );
                let _ = conn.execute(
                    r#"DELETE FROM messages WHERE id = ?1"#,
                    params![user_message.id.as_str()],
                );
                return Err(e);
            }

            if !has_text {
                let _ = conn.execute(
                    r#"DELETE FROM messages WHERE id = ?1"#,
                    params![assistant_message.id.as_str()],
                );
            } else {
                let _ = db::edit_message(conn, key, &assistant_message.id, &assistant_text);
            }
            return Err(e);
        }
    }

    Ok(AskAiResult {
        user_message_id: user_message.id,
        assistant_message_id: assistant_message.id,
    })
}
