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

pub fn build_prompt(question: &str, contexts: &[String]) -> String {
    let mut out = String::new();
    out.push_str("You are SecondLoop, a helpful personal assistant.\n");

    if !contexts.is_empty() {
        out.push_str("\nRelevant memories (quoted):\n");
        for (i, ctx) in contexts.iter().enumerate() {
            out.push_str(&format!("{}. \"{}\"\n", i + 1, ctx));
        }
    }

    out.push_str(
        "\nAnswer the user's question. If the memories are irrelevant, answer normally.\n",
    );
    out.push_str("\nQuestion: ");
    out.push_str(question);
    out.push('\n');
    out
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
    let prompt = build_prompt(question, &contexts);

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
    let prompt = build_prompt(question, &contexts);

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
    let prompt = build_prompt(question, &contexts);

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
