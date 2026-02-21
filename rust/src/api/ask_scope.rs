use std::path::Path;

use anyhow::{anyhow, Result};
use rusqlite::Connection;

use crate::db;
use crate::frb_generated::StreamSink;
use crate::{llm, rag};

const ASK_AI_ERROR_PREFIX: &str = "\u{001e}SL_ERROR\u{001e}";
const ASK_AI_META_PREFIX: &str = "\u{001e}SL_META\u{001e}";
const ASK_AI_META_REQUEST_ID_ROLE_PREFIX: &str = "secondloop_request_id:";

fn key_from_bytes(bytes: Vec<u8>) -> Result<[u8; 32]> {
    if bytes.len() != 32 {
        return Err(anyhow!("invalid key length"));
    }
    let mut key = [0u8; 32];
    key.copy_from_slice(&bytes);
    Ok(key)
}

fn finish_ask_ai_stream(sink: &StreamSink<String>, result: Result<()>) -> Result<()> {
    match result {
        Ok(()) => Ok(()),
        Err(e) if e.is::<rag::StreamCancelled>() => Ok(()),
        Err(e) => {
            let _ = sink.add(format!("{ASK_AI_ERROR_PREFIX}{e}"));
            Ok(())
        }
    }
}

fn emit_ask_ai_meta_if_any(sink: &StreamSink<String>, role: Option<&str>) -> Result<()> {
    let Some(role) = role else {
        return Ok(());
    };
    let Some(request_id) = role.strip_prefix(ASK_AI_META_REQUEST_ID_ROLE_PREFIX) else {
        return Ok(());
    };
    if request_id.trim().is_empty() {
        return Ok(());
    }

    let payload = format!(
        "{ASK_AI_META_PREFIX}{{\"type\":\"cloud_request_id\",\"request_id\":\"{request_id}\"}}"
    );
    if sink.add(payload).is_err() {
        return Err(rag::StreamCancelled.into());
    }
    Ok(())
}

fn normalize_tag_ids(raw: &[String]) -> Vec<String> {
    let mut set = std::collections::BTreeSet::<String>::new();
    for value in raw {
        let trimmed = value.trim();
        if trimmed.is_empty() {
            continue;
        }
        set.insert(trimmed.to_string());
    }
    set.into_iter().collect()
}

fn list_conversation_message_ids(conn: &Connection, conversation_id: &str) -> Result<Vec<String>> {
    let mut stmt = conn.prepare(
        r#"SELECT id
           FROM messages
           WHERE conversation_id = ?1
             AND COALESCE(is_deleted, 0) = 0
           ORDER BY created_at DESC, id DESC"#,
    )?;

    let mut rows = stmt.query([conversation_id])?;
    let mut out = Vec::<String>::new();
    while let Some(row) = rows.next()? {
        out.push(row.get(0)?);
    }
    Ok(out)
}

fn list_all_message_ids(conn: &Connection) -> Result<Vec<String>> {
    let mut stmt = conn.prepare(
        r#"SELECT id
           FROM messages
           WHERE COALESCE(is_deleted, 0) = 0
           ORDER BY created_at DESC, id DESC"#,
    )?;

    let mut rows = stmt.query([])?;
    let mut out = Vec::<String>::new();
    while let Some(row) = rows.next()? {
        out.push(row.get(0)?);
    }
    Ok(out)
}

#[derive(Clone, Copy)]
struct TimeScope {
    start_ms_inclusive: i64,
    end_ms_exclusive: i64,
}

#[derive(Clone, Copy)]
enum ScopedFocus {
    Conversation,
    AllMemories,
}

fn list_message_ids_by_tag_scope(
    conn: &Connection,
    conversation_id: &str,
    tag_ids: &[String],
    focus: ScopedFocus,
) -> Result<Vec<String>> {
    if tag_ids.is_empty() {
        return Ok(Vec::new());
    }

    match focus {
        ScopedFocus::Conversation => {
            db::list_message_ids_by_tag_ids(conn, conversation_id, tag_ids)
        }
        ScopedFocus::AllMemories => db::list_message_ids_by_tag_ids_all(conn, tag_ids),
    }
}

#[allow(clippy::too_many_arguments)]
fn collect_scoped_contexts(
    conn: &Connection,
    key: &[u8; 32],
    conversation_id: &str,
    include_tag_ids: &[String],
    exclude_tag_ids: &[String],
    top_k: usize,
    time_scope: Option<TimeScope>,
    focus: ScopedFocus,
) -> Result<Vec<String>> {
    let include_tag_ids = normalize_tag_ids(include_tag_ids);
    let exclude_tag_ids = normalize_tag_ids(exclude_tag_ids);

    if include_tag_ids.is_empty() && exclude_tag_ids.is_empty() && time_scope.is_none() {
        return Ok(Vec::new());
    }

    let mut message_ids = match focus {
        ScopedFocus::Conversation => list_conversation_message_ids(conn, conversation_id)?,
        ScopedFocus::AllMemories => list_all_message_ids(conn)?,
    };

    if !include_tag_ids.is_empty() {
        let tagged_ids =
            list_message_ids_by_tag_scope(conn, conversation_id, &include_tag_ids, focus)?;
        if tagged_ids.is_empty() {
            return Ok(Vec::new());
        }
        let tagged_set = tagged_ids
            .into_iter()
            .collect::<std::collections::BTreeSet<_>>();
        message_ids.retain(|id| tagged_set.contains(id));
    }

    if message_ids.is_empty() {
        return Ok(Vec::new());
    }

    if !exclude_tag_ids.is_empty() {
        let excluded_ids =
            list_message_ids_by_tag_scope(conn, conversation_id, &exclude_tag_ids, focus)?;
        if !excluded_ids.is_empty() {
            let excluded_set = excluded_ids
                .into_iter()
                .collect::<std::collections::BTreeSet<_>>();
            message_ids.retain(|id| !excluded_set.contains(id));
        }
    }

    if message_ids.is_empty() {
        return Ok(Vec::new());
    }

    let mut contexts = Vec::<String>::new();

    let limit = top_k.max(1);
    for message_id in message_ids {
        if contexts.len() >= limit {
            break;
        }

        let Some(message) = db::get_message_by_id_optional(conn, key, &message_id)? else {
            continue;
        };
        if matches!(focus, ScopedFocus::Conversation) && message.conversation_id != conversation_id
        {
            continue;
        }
        if !message.is_memory {
            continue;
        }
        if let Some(scope) = time_scope {
            if message.created_at_ms < scope.start_ms_inclusive
                || message.created_at_ms >= scope.end_ms_exclusive
            {
                continue;
            }
        }

        let context = db::build_message_rag_context(conn, key, &message.id, &message.content)
            .unwrap_or_else(|_| message.content.clone());
        let trimmed = context.trim();
        if trimmed.is_empty() {
            continue;
        }

        contexts.push(trimmed.to_string());
    }

    contexts.reverse();
    Ok(contexts)
}

fn build_scoped_prompt(question: &str, contexts: &[String]) -> String {
    let mut out = String::new();
    out.push_str("You are SecondLoop, a helpful personal assistant.\n");
    out.push_str("IMPORTANT: Reply in the same language as the user's question.\n");
    out.push_str("IMPORTANT: Use only the scoped memories below as evidence.\n");
    out.push_str(
        "If the scoped memories are insufficient, explicitly say no matching records.\n\n",
    );

    if contexts.is_empty() {
        out.push_str("Scoped memories: (none)\n");
    } else {
        out.push_str("Scoped memories (quoted):\n");
        for (index, context) in contexts.iter().enumerate() {
            out.push_str(&format!("{}. \"{}\"\n", index + 1, context));
        }
    }

    out.push_str("\nQuestion: ");
    out.push_str(question.trim());
    out.push('\n');
    out
}

fn build_scoped_empty_answer(locale_language: &str) -> String {
    let locale = locale_language.trim().to_lowercase();
    if locale.starts_with("zh") {
        return [
            "在当前范围内未找到结果（时间窗口 + 标签 + 范围）。",
            "你可以尝试：",
            "1. 扩大时间窗口",
            "2. 移除包含标签",
            "3. 切换范围到 All",
        ]
        .join("\n");
    }

    [
        "No results found in the current scope (time window + tags + focus).",
        "You can try:",
        "1. Expand the time window",
        "2. Remove include tags",
        "3. Switch scope to All",
    ]
    .join("\n")
}

fn emit_scoped_empty_answer(
    conn: &Connection,
    key: &[u8; 32],
    conversation_id: &str,
    question: &str,
    locale_language: &str,
    sink: &StreamSink<String>,
) -> Result<()> {
    let answer = build_scoped_empty_answer(locale_language);

    if sink.add(answer.clone()).is_err() {
        return Err(rag::StreamCancelled.into());
    }
    if sink.add(String::new()).is_err() {
        return Err(rag::StreamCancelled.into());
    }

    let _ = db::insert_message_non_memory(conn, key, conversation_id, "user", question)?;
    let _ = db::insert_message_non_memory(conn, key, conversation_id, "assistant", &answer)?;

    Ok(())
}

fn stream_scoped_ask_with_provider(
    conn: &Connection,
    key: &[u8; 32],
    conversation_id: &str,
    question: &str,
    contexts: &[String],
    provider: &(impl rag::AnswerProvider + ?Sized),
    sink: &StreamSink<String>,
    emit_meta: bool,
) -> Result<()> {
    let prompt = build_scoped_prompt(question, contexts);

    let mut has_text = false;
    let mut assistant_text = String::new();
    let result = provider.stream_answer(&prompt, &mut |ev| {
        if emit_meta {
            emit_ask_ai_meta_if_any(sink, ev.role.as_deref())?;
        }

        if ev.done {
            if sink.add(String::new()).is_err() {
                return Err(rag::StreamCancelled.into());
            }
            return Ok(());
        }

        if ev.text_delta.is_empty() {
            return Ok(());
        }

        has_text = true;
        assistant_text.push_str(&ev.text_delta);
        if sink.add(ev.text_delta).is_err() {
            return Err(rag::StreamCancelled.into());
        }

        Ok(())
    });

    match result {
        Ok(()) => {
            if !has_text {
                return Err(anyhow!("empty response from LLM"));
            }

            let _ = db::insert_message_non_memory(conn, key, conversation_id, "user", question)?;
            let _ = db::insert_message_non_memory(
                conn,
                key,
                conversation_id,
                "assistant",
                &assistant_text,
            )?;
            Ok(())
        }
        Err(e) => Err(e),
    }
}

#[allow(clippy::too_many_arguments)]
#[flutter_rust_bridge::frb]
pub fn rag_ask_ai_stream_scoped(
    app_dir: String,
    key: Vec<u8>,
    conversation_id: String,
    question: String,
    top_k: u32,
    this_thread_only: bool,
    time_start_ms: Option<i64>,
    time_end_ms: Option<i64>,
    include_tag_ids: Vec<String>,
    exclude_tag_ids: Vec<String>,
    strict_mode: bool,
    locale_language: String,
    local_day: String,
    sink: StreamSink<String>,
) -> Result<()> {
    let result = (|| -> Result<()> {
        let key = key_from_bytes(key)?;
        let conn = db::open(Path::new(&app_dir))?;

        let (profile_id, profile) = db::load_active_llm_profile_config(&conn, &key)?
            .ok_or_else(|| anyhow!("no active LLM profile configured"))?;

        let time_scope = match (time_start_ms, time_end_ms) {
            (Some(start), Some(end)) if start < end => Some(TimeScope {
                start_ms_inclusive: start,
                end_ms_exclusive: end,
            }),
            _ => None,
        };

        let focus = if this_thread_only {
            ScopedFocus::Conversation
        } else {
            ScopedFocus::AllMemories
        };

        let contexts = collect_scoped_contexts(
            &conn,
            &key,
            &conversation_id,
            &include_tag_ids,
            &exclude_tag_ids,
            top_k as usize,
            time_scope,
            focus,
        )?;

        let stream_result = if strict_mode && contexts.is_empty() {
            emit_scoped_empty_answer(
                &conn,
                &key,
                &conversation_id,
                &question,
                &locale_language,
                &sink,
            )
        } else {
            let provider = llm::answer_provider_from_profile(&profile)?;
            stream_scoped_ask_with_provider(
                &conn,
                &key,
                &conversation_id,
                &question,
                &contexts,
                provider.as_ref(),
                &sink,
                false,
            )
        };

        let day = local_day.trim();
        if !day.is_empty() {
            let _ = db::record_llm_usage_daily(&conn, day, &profile_id, "ask_ai", None, None, None);
        }

        stream_result
    })();

    finish_ask_ai_stream(&sink, result)
}

#[allow(clippy::too_many_arguments)]
#[flutter_rust_bridge::frb]
pub fn rag_ask_ai_stream_cloud_gateway_scoped(
    app_dir: String,
    key: Vec<u8>,
    conversation_id: String,
    question: String,
    top_k: u32,
    this_thread_only: bool,
    time_start_ms: Option<i64>,
    time_end_ms: Option<i64>,
    include_tag_ids: Vec<String>,
    exclude_tag_ids: Vec<String>,
    strict_mode: bool,
    locale_language: String,
    gateway_base_url: String,
    firebase_id_token: String,
    model_name: String,
    sink: StreamSink<String>,
) -> Result<()> {
    let result = (|| -> Result<()> {
        if gateway_base_url.trim().is_empty() {
            return Err(anyhow!("missing gateway_base_url"));
        }
        if firebase_id_token.trim().is_empty() {
            return Err(anyhow!("missing firebase_id_token"));
        }

        let key = key_from_bytes(key)?;
        let conn = db::open(Path::new(&app_dir))?;

        let time_scope = match (time_start_ms, time_end_ms) {
            (Some(start), Some(end)) if start < end => Some(TimeScope {
                start_ms_inclusive: start,
                end_ms_exclusive: end,
            }),
            _ => None,
        };

        let focus = if this_thread_only {
            ScopedFocus::Conversation
        } else {
            ScopedFocus::AllMemories
        };

        let contexts = collect_scoped_contexts(
            &conn,
            &key,
            &conversation_id,
            &include_tag_ids,
            &exclude_tag_ids,
            top_k as usize,
            time_scope,
            focus,
        )?;

        if strict_mode && contexts.is_empty() {
            return emit_scoped_empty_answer(
                &conn,
                &key,
                &conversation_id,
                &question,
                &locale_language,
                &sink,
            );
        }

        let provider = llm::gateway::CloudGatewayProvider::new(
            gateway_base_url,
            firebase_id_token,
            model_name,
            None,
        );

        stream_scoped_ask_with_provider(
            &conn,
            &key,
            &conversation_id,
            &question,
            &contexts,
            &provider,
            &sink,
            true,
        )
    })();

    finish_ask_ai_stream(&sink, result)
}

#[cfg(test)]
mod tests {
    use tempfile::tempdir;

    use crate::auth;
    use crate::crypto::KdfParams;

    use super::*;

    #[test]
    fn collect_scoped_contexts_applies_time_window_with_tag_filter() {
        use rusqlite::params;

        let temp = tempdir().expect("tempdir");
        let app_dir = temp.path().join("secondloop");
        let key =
            auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init auth");
        let conn = db::open(&app_dir).expect("open db");

        let conversation =
            db::create_conversation(&conn, &key, "Main").expect("create conversation");
        let old_work = db::insert_message(&conn, &key, &conversation.id, "user", "work monday")
            .expect("insert old_work");
        let in_window_work =
            db::insert_message(&conn, &key, &conversation.id, "user", "work friday")
                .expect("insert in_window_work");
        let in_window_other =
            db::insert_message(&conn, &key, &conversation.id, "user", "personal friday")
                .expect("insert in_window_other");

        let base = 1_700_000_000_000i64;
        conn.execute(
            "UPDATE messages SET created_at = ?2 WHERE id = ?1",
            params![old_work.id, base - 8 * 24 * 60 * 60 * 1000],
        )
        .expect("set old_work time");
        conn.execute(
            "UPDATE messages SET created_at = ?2 WHERE id = ?1",
            params![in_window_work.id, base - 2 * 24 * 60 * 60 * 1000],
        )
        .expect("set in_window_work time");
        conn.execute(
            "UPDATE messages SET created_at = ?2 WHERE id = ?1",
            params![in_window_other.id, base - 2 * 24 * 60 * 60 * 1000],
        )
        .expect("set in_window_other time");

        let work = db::upsert_tag(&conn, &key, "work").expect("upsert work tag");
        db::set_message_tags(&conn, &key, &old_work.id, std::slice::from_ref(&work.id))
            .expect("set old_work tags");
        db::set_message_tags(
            &conn,
            &key,
            &in_window_work.id,
            std::slice::from_ref(&work.id),
        )
        .expect("set in_window_work tags");

        let contexts = collect_scoped_contexts(
            &conn,
            &key,
            &conversation.id,
            std::slice::from_ref(&work.id),
            &[],
            10,
            Some(TimeScope {
                start_ms_inclusive: base - 7 * 24 * 60 * 60 * 1000,
                end_ms_exclusive: base,
            }),
            ScopedFocus::Conversation,
        )
        .expect("collect contexts");

        assert_eq!(contexts.len(), 1);
        assert!(contexts[0].contains("work friday"));
    }

    #[test]
    fn collect_scoped_contexts_applies_time_window_without_tag_filters() {
        use rusqlite::params;

        let temp = tempdir().expect("tempdir");
        let app_dir = temp.path().join("secondloop");
        let key =
            auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init auth");
        let conn = db::open(&app_dir).expect("open db");

        let conversation =
            db::create_conversation(&conn, &key, "Main").expect("create conversation");
        let old_note = db::insert_message(&conn, &key, &conversation.id, "user", "old note")
            .expect("insert old_note");
        let in_window_note =
            db::insert_message(&conn, &key, &conversation.id, "user", "in window note")
                .expect("insert in_window_note");

        let base = 1_700_000_000_000i64;
        conn.execute(
            "UPDATE messages SET created_at = ?2 WHERE id = ?1",
            params![old_note.id, base - 20 * 24 * 60 * 60 * 1000],
        )
        .expect("set old_note time");
        conn.execute(
            "UPDATE messages SET created_at = ?2 WHERE id = ?1",
            params![in_window_note.id, base - 2 * 24 * 60 * 60 * 1000],
        )
        .expect("set in_window_note time");

        let contexts = collect_scoped_contexts(
            &conn,
            &key,
            &conversation.id,
            &[],
            &[],
            10,
            Some(TimeScope {
                start_ms_inclusive: base - 7 * 24 * 60 * 60 * 1000,
                end_ms_exclusive: base,
            }),
            ScopedFocus::Conversation,
        )
        .expect("collect contexts");

        assert_eq!(contexts.len(), 1);
        assert!(contexts[0].contains("in window note"));
    }

    #[test]
    fn collect_scoped_contexts_supports_all_memories_scope_for_tag_filter() {
        let temp = tempdir().expect("tempdir");
        let app_dir = temp.path().join("secondloop");
        let key =
            auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init auth");
        let conn = db::open(&app_dir).expect("open db");

        let conversation_main =
            db::create_conversation(&conn, &key, "Main").expect("create main conversation");
        let conversation_side =
            db::create_conversation(&conn, &key, "Side").expect("create side conversation");

        let main_work =
            db::insert_message(&conn, &key, &conversation_main.id, "user", "main work note")
                .expect("insert main_work");
        let side_work =
            db::insert_message(&conn, &key, &conversation_side.id, "user", "side work note")
                .expect("insert side_work");

        let work = db::upsert_tag(&conn, &key, "work").expect("upsert work tag");
        db::set_message_tags(&conn, &key, &main_work.id, std::slice::from_ref(&work.id))
            .expect("set main_work tags");
        db::set_message_tags(&conn, &key, &side_work.id, std::slice::from_ref(&work.id))
            .expect("set side_work tags");

        let contexts = collect_scoped_contexts(
            &conn,
            &key,
            &conversation_main.id,
            std::slice::from_ref(&work.id),
            &[],
            10,
            None,
            ScopedFocus::AllMemories,
        )
        .expect("collect contexts");

        assert_eq!(contexts.len(), 2);
        assert!(contexts
            .iter()
            .any(|value| value.contains("main work note")));
        assert!(contexts
            .iter()
            .any(|value| value.contains("side work note")));
    }

    #[test]
    fn collect_scoped_contexts_applies_exclude_tags_without_include_tags() {
        let temp = tempdir().expect("tempdir");
        let app_dir = temp.path().join("secondloop");
        let key =
            auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init auth");
        let conn = db::open(&app_dir).expect("open db");

        let conversation =
            db::create_conversation(&conn, &key, "Main").expect("create conversation");

        let m_work = db::insert_message(&conn, &key, &conversation.id, "user", "work note")
            .expect("insert m_work");
        let _m_personal =
            db::insert_message(&conn, &key, &conversation.id, "user", "personal note")
                .expect("insert m_personal");

        let work = db::upsert_tag(&conn, &key, "work").expect("upsert work tag");
        db::set_message_tags(&conn, &key, &m_work.id, std::slice::from_ref(&work.id))
            .expect("set m_work tags");

        let contexts = collect_scoped_contexts(
            &conn,
            &key,
            &conversation.id,
            &[],
            std::slice::from_ref(&work.id),
            10,
            None,
            ScopedFocus::Conversation,
        )
        .expect("collect contexts");

        assert_eq!(contexts.len(), 1);
        assert!(contexts[0].contains("personal note"));
        assert!(contexts.iter().all(|v| !v.contains("work note")));
    }

    #[test]
    fn collect_scoped_contexts_applies_exclude_tags_after_include_tags() {
        let temp = tempdir().expect("tempdir");
        let app_dir = temp.path().join("secondloop");
        let key =
            auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init auth");
        let conn = db::open(&app_dir).expect("open db");

        let conversation =
            db::create_conversation(&conn, &key, "Main").expect("create conversation");

        let m_work_only = db::insert_message(&conn, &key, &conversation.id, "user", "work only")
            .expect("insert m_work_only");
        let m_work_social =
            db::insert_message(&conn, &key, &conversation.id, "user", "work and social")
                .expect("insert m_work_social");

        let work = db::upsert_tag(&conn, &key, "work").expect("upsert work tag");
        let social = db::upsert_tag(&conn, &key, "social").expect("upsert social tag");

        db::set_message_tags(&conn, &key, &m_work_only.id, std::slice::from_ref(&work.id))
            .expect("set m_work_only tags");
        db::set_message_tags(
            &conn,
            &key,
            &m_work_social.id,
            &[work.id.clone(), social.id.clone()],
        )
        .expect("set m_work_social tags");

        let contexts = collect_scoped_contexts(
            &conn,
            &key,
            &conversation.id,
            std::slice::from_ref(&work.id),
            std::slice::from_ref(&social.id),
            10,
            None,
            ScopedFocus::Conversation,
        )
        .expect("collect contexts");

        assert_eq!(contexts.len(), 1);
        assert!(contexts[0].contains("work only"));
    }
}
