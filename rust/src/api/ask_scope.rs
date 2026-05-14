use std::path::Path;

use anyhow::{anyhow, Result};
use rusqlite::Connection;

use crate::db;
use crate::frb_generated::StreamSink;
use crate::message_citations::append_message_citation_if_missing;
use crate::{llm, rag};

const ASK_AI_ERROR_PREFIX: &str = "\u{001e}SL_ERROR\u{001e}";

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

fn is_scope_separator(ch: char) -> bool {
    ch.is_whitespace()
        || ch.is_ascii_punctuation()
        || matches!(
            ch,
            '，' | '。'
                | '、'
                | '；'
                | '：'
                | '！'
                | '？'
                | '（'
                | '）'
                | '［'
                | '］'
                | '【'
                | '】'
                | '｛'
                | '｝'
                | '〈'
                | '〉'
                | '《'
                | '》'
                | '「'
                | '」'
                | '『'
                | '』'
                | '〔'
                | '〕'
                | '〖'
                | '〗'
                | '〘'
                | '〙'
                | '〚'
                | '〛'
                | '—'
                | '―'
                | '…'
                | '‥'
                | '·'
                | '・'
                | '／'
                | '＼'
                | '｜'
                | '＂'
                | '＇'
                | '｀'
                | '～'
                | '．'
        )
}

fn normalize_scope_match_text(raw: &str) -> String {
    let mut out = String::new();
    let mut previous_was_space = false;

    for ch in raw.trim().chars() {
        let mapped = if ch.is_ascii_alphanumeric() {
            ch.to_ascii_lowercase()
        } else if is_scope_separator(ch) {
            ' '
        } else {
            ch
        };

        if mapped == ' ' {
            if !previous_was_space {
                out.push(' ');
            }
            previous_was_space = true;
            continue;
        }

        out.push(mapped);
        previous_was_space = false;
    }

    out.trim().to_string()
}

fn contains_ascii_scope_phrase(haystack: &str, needle: &str) -> bool {
    let needle = needle.trim();
    if haystack.is_empty() || needle.is_empty() {
        return false;
    }

    let padded_haystack = format!(" {haystack} ");
    let padded_needle = format!(" {needle} ");
    padded_haystack.contains(&padded_needle)
}

const NON_ASCII_SCOPE_PREFIX_CUES: &[&str] = &[
    "写",
    "寫",
    "写下",
    "寫下",
    "写个",
    "寫個",
    "写一份",
    "寫一份",
    "写一下",
    "寫一下",
    "做",
    "做个",
    "做個",
    "做一份",
    "列",
    "列出",
    "整理",
    "总结",
    "總結",
    "汇总",
    "彙總",
    "复盘",
    "復盤",
    "回顾",
    "回顧",
    "盘点",
    "盤點",
    "查看",
    "看看",
    "聊聊",
    "说说",
    "說說",
    "关于",
    "關於",
    "有关",
    "有關",
    "最近",
    "本周",
    "这周",
    "這週",
    "本月",
    "这个月",
    "這個月",
    "今天",
    "今日",
];

const NON_ASCII_SCOPE_SUFFIX_CUES: &[&str] = &[
    "周报", "週報", "日报", "日報", "月报", "月報", "总结", "總結", "汇报", "匯報", "报告", "報告",
    "计划", "計劃", "规划", "規劃", "安排", "事项", "事項", "任务", "任務", "进展", "進展", "内容",
    "內容", "相关", "相關", "情况", "情況", "问题", "問題", "目标", "目標", "项目", "項目", "方向",
    "清单", "清單", "复盘", "復盤",
];

fn is_non_ascii_scope_linker(ch: char) -> bool {
    matches!(
        ch,
        '的' | '地'
            | '得'
            | '和'
            | '及'
            | '与'
            | '與'
            | '或'
            | '在'
            | '上'
            | '中'
            | '内'
            | '內'
            | '里'
            | '裡'
    )
}

fn has_non_ascii_scope_prefix_cue(prefix: &str) -> bool {
    NON_ASCII_SCOPE_PREFIX_CUES
        .iter()
        .any(|candidate| prefix.ends_with(candidate))
}

fn has_non_ascii_scope_suffix_cue(suffix: &str) -> bool {
    NON_ASCII_SCOPE_SUFFIX_CUES
        .iter()
        .any(|candidate| suffix.starts_with(candidate))
}

fn two_char_non_ascii_scope_match_has_context(prefix: &str, suffix: &str) -> bool {
    let left_ok = match prefix.chars().next_back() {
        None => true,
        Some(ch) => is_scope_separator(ch) || is_non_ascii_scope_linker(ch),
    } || has_non_ascii_scope_prefix_cue(prefix);

    let right_ok = match suffix.chars().next() {
        None => true,
        Some(ch) => is_scope_separator(ch) || is_non_ascii_scope_linker(ch),
    } || has_non_ascii_scope_suffix_cue(suffix);

    left_ok && right_ok
}

fn contains_non_ascii_scope_phrase(haystack: &str, needle: &str) -> bool {
    let needle = needle.trim();
    let needle_chars = needle.chars().count();
    if haystack.is_empty() || needle_chars < 2 {
        return false;
    }

    if needle_chars >= 3 {
        return haystack.contains(needle);
    }

    haystack.match_indices(needle).any(|(index, _)| {
        let prefix = &haystack[..index];
        let suffix = &haystack[index + needle.len()..];
        two_char_non_ascii_scope_match_has_context(prefix, suffix)
    })
}

fn system_tag_scope_aliases(system_key: &str) -> &'static [&'static str] {
    match system_key {
        "work" => &["work", "工作"],
        "personal" => &["personal", "个人", "個人"],
        "family" => &["family", "家庭"],
        "health" => &["health", "健康"],
        "finance" => &["finance", "财务", "財務"],
        "study" => &["study", "学习", "學習"],
        "travel" => &["travel", "旅行", "旅游", "旅遊"],
        "social" => &["social", "社交"],
        "home" => &["home", "居家", "家务", "家務"],
        "hobby" => &["hobby", "爱好", "愛好", "兴趣", "興趣"],
        _ => &[],
    }
}

fn question_mentions_tag(question_normalized: &str, tag: &db::Tag) -> bool {
    let normalized_tag_name = normalize_scope_match_text(&tag.name);
    if !normalized_tag_name.is_empty() {
        if normalized_tag_name.is_ascii() {
            if contains_ascii_scope_phrase(question_normalized, &normalized_tag_name) {
                return true;
            }
        } else if contains_non_ascii_scope_phrase(question_normalized, &normalized_tag_name) {
            return true;
        }
    }

    let Some(system_key) = tag.system_key.as_deref() else {
        return false;
    };

    for alias in system_tag_scope_aliases(system_key) {
        let normalized_alias = normalize_scope_match_text(alias);
        if normalized_alias.is_empty() {
            continue;
        }

        if normalized_alias.is_ascii() {
            if contains_ascii_scope_phrase(question_normalized, &normalized_alias) {
                return true;
            }
            continue;
        }

        if contains_non_ascii_scope_phrase(question_normalized, &normalized_alias) {
            return true;
        }
    }

    false
}

fn resolve_scoped_include_tag_ids(
    conn: &Connection,
    key: &[u8; 32],
    question: &str,
    include_tag_ids: &[String],
) -> Result<Vec<String>> {
    let include_tag_ids = normalize_tag_ids(include_tag_ids);
    if !include_tag_ids.is_empty() {
        return Ok(include_tag_ids);
    }

    let question_normalized = normalize_scope_match_text(question);
    if question_normalized.is_empty() {
        return Ok(Vec::new());
    }

    let mut inferred = std::collections::BTreeSet::<String>::new();
    for tag in db::list_tags(conn, key)? {
        if question_mentions_tag(&question_normalized, &tag) {
            inferred.insert(tag.id);
        }
    }

    Ok(inferred.into_iter().collect())
}

#[allow(clippy::too_many_arguments)]
fn resolve_scoped_contexts_snapshot(
    conn: &Connection,
    key: &[u8; 32],
    conversation_id: &str,
    question: &str,
    include_tag_ids: &[String],
    exclude_tag_ids: &[String],
    top_k: usize,
    time_scope: Option<TimeScope>,
    focus: ScopedFocus,
) -> Result<(Vec<String>, Vec<String>)> {
    // Keep tag inference and context collection on the same SQLite read snapshot.
    // Commit before any later writes or streaming-side effects.
    conn.execute_batch("BEGIN DEFERRED;")?;
    let result = (|| -> Result<(Vec<String>, Vec<String>)> {
        let include_tag_ids = resolve_scoped_include_tag_ids(conn, key, question, include_tag_ids)?;
        let contexts = collect_scoped_contexts(
            conn,
            key,
            conversation_id,
            &include_tag_ids,
            exclude_tag_ids,
            top_k,
            time_scope,
            focus,
        )?;
        Ok((include_tag_ids, contexts))
    })();

    match result {
        Ok(values) => {
            conn.execute_batch("COMMIT;")?;
            Ok(values)
        }
        Err(err) => {
            let _ = conn.execute_batch("ROLLBACK;");
            Err(err)
        }
    }
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

    // Preserve the pre-existing time-only fallback: if no tag filters are present
    // (including when tag inference finds none), still scan the full time window.
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

        contexts.push(append_message_citation_if_missing(
            trimmed.to_string(),
            &message.id,
        ));
    }

    contexts.reverse();
    Ok(contexts)
}

fn build_scoped_prompt(question: &str, contexts: &[String]) -> String {
    let mut out = String::new();
    out.push_str("You are SecondLoop, a helpful personal assistant.\n");
    out.push_str("IMPORTANT: Reply in the same language as the user's question.\n");
    out.push_str("IMPORTANT: Use only the scoped memories below as evidence.\n");
    out.push_str("IMPORTANT: If you cite attachment evidence, use only secondloop links.\n");
    out.push_str(
        "IMPORTANT: If you cite scoped memories/history, use only secondloop message links.\n",
    );
    out.push_str("- Resource citation: [label](secondloop://attachment/<sha>)\n");
    out.push_str(
        "- Chunk citation: [label](secondloop://attachment/<sha>?kind=<kind>&chunk=<i>)\n",
    );
    out.push_str("- History citation: [label](secondloop://message/<message_id>)\n");
    out.push_str(
        "Always emit citations as Markdown links, never raw message_id=... or bare secondloop:// URLs.\n",
    );
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
            crate::api::ask_ai_stream_controls::emit_request_meta_if_any(sink, ev.role.as_deref())?;
        }
        crate::api::ask_ai_stream_controls::emit_reasoning_if_any(sink, ev.role.as_deref())?;

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

        let (_, contexts) = resolve_scoped_contexts_snapshot(
            &conn,
            &key,
            &conversation_id,
            &question,
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

        let (_, contexts) = resolve_scoped_contexts_snapshot(
            &conn,
            &key,
            &conversation_id,
            &question,
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
mod tests;
