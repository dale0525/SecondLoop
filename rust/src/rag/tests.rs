use super::{
    build_message_direct_source, format_history_line, should_include_actions_context,
    should_include_actions_context_in_range,
};
use super::{ContextItem, ContextSource};
use crate::auth;
use crate::crypto::KdfParams;
use crate::db;
use crate::message_citations::AnswerEvidenceDirectSource;
use crate::rag::evidence::build_direct_sources_for_context_candidate;
use crate::rag::evidence::filter_direct_sources_for_question;
use rusqlite::params;

#[test]
fn format_history_line_moves_citation_below_content() {
    let line = format_history_line("User", "history-1", "Project kickoff moved to Friday.");
    assert_eq!(
        line,
        "User: Project kickoff moved to Friday.\n[History](secondloop://message/history-1)\n"
    );
}

#[test]
fn format_history_line_preserves_trailing_newline_before_citation() {
    let line = format_history_line("Assistant", "history-2", "Line one\n");
    assert_eq!(
        line,
        "Assistant: Line one\n[History](secondloop://message/history-2)\n"
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
fn yesterday_task_query_triggers_actions_context_in_range() {
    assert!(should_include_actions_context_in_range(
        "昨天我做了哪些事？"
    ));
    assert!(should_include_actions_context_in_range(
        "What did I do yesterday?"
    ));
}

#[test]
fn generic_yesterday_query_does_not_trigger_actions_context_in_range() {
    assert!(!should_include_actions_context_in_range(
        "分析一下我昨天拍的视频开头台词"
    ));
    assert!(!should_include_actions_context_in_range(
        "Summarize yesterday's video intro"
    ));
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

#[test]
fn attachment_direct_sources_use_plain_chunk_text_from_storage() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    let attachment = db::insert_attachment(
        &conn,
        &key,
        &app_dir,
        b"Launch brief line one.\nLaunch brief line two.",
        "text/plain",
    )
    .expect("attachment");
    db::mark_attachment_annotation_ok(
        &conn,
        &key,
        &attachment.sha256,
        "en",
        "test-model",
        &serde_json::json!({
            "mime_type": "text/plain",
            "readable_text_full": "Launch brief line one.\nLaunch brief line two.",
        }),
        1,
    )
    .expect("store attachment annotation");
    db::process_attachment_text_chunks(&conn, &key, 256).expect("chunk attachment");

    let (kind, chunk_index): (String, i64) = conn
        .query_row(
            r#"SELECT kind, chunk_index
               FROM attachment_text_chunks
               WHERE attachment_sha256 = ?1
               ORDER BY chunk_index ASC
               LIMIT 1"#,
            params![attachment.sha256],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("chunk row");
    let candidate = ContextItem {
        source: ContextSource::AttachmentChunk,
        id: format!("{}:{}:{}", attachment.sha256, kind, chunk_index),
        created_at_ms: attachment.created_at_ms,
        distance: Some(0.1),
        text: format!(
            "ATTACHMENT_CHUNK {} {}#{}\nLaunch brief line one.\n[Attachment](secondloop://attachment/{}?kind={}&chunk={})",
            attachment.sha256, kind, chunk_index, attachment.sha256, kind, chunk_index
        ),
        citation_suffix: None,
    };

    let direct_sources = build_direct_sources_for_context_candidate(&conn, &key, &candidate);
    let source = direct_sources.first().expect("attachment direct source");

    assert!(
        source.snippet.contains("Launch brief line one."),
        "expected plain attachment text snippet: {}",
        source.snippet
    );
    assert!(
        !source.snippet.contains("ATTACHMENT_CHUNK"),
        "expected internal attachment marker to stay out of snippet: {}",
        source.snippet
    );
    assert!(
        !source.snippet.contains("[Attachment]("),
        "expected markdown citation suffix to stay out of snippet: {}",
        source.snippet
    );
}

#[test]
fn attachment_direct_sources_strip_internal_markup_when_chunk_text_is_unavailable() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let candidate = ContextItem {
        source: ContextSource::AttachmentChunk,
        id: "missing-sha:readable_text_full:99".to_string(),
        created_at_ms: 1,
        distance: Some(0.1),
        text: "ATTACHMENT_CHUNK missing-sha readable_text_full#99\nLaunch brief line one.\nLaunch brief line two.\n[Attachment](secondloop://attachment/missing-sha?kind=readable_text_full&chunk=99)"
            .to_string(),
        citation_suffix: None,
    };

    let direct_sources = build_direct_sources_for_context_candidate(&conn, &key, &candidate);
    let source = direct_sources.first().expect("attachment direct source");

    assert!(
        source.snippet.contains("Launch brief line one."),
        "expected fallback snippet to keep plain attachment text: {}",
        source.snippet
    );
    assert!(
        !source.snippet.contains("ATTACHMENT_CHUNK"),
        "expected internal attachment marker to stay out of fallback snippet: {}",
        source.snippet
    );
    assert!(
        !source.snippet.contains("[Attachment]("),
        "expected markdown citation suffix to stay out of fallback snippet: {}",
        source.snippet
    );
}

#[test]
fn todo_thread_candidates_build_item_direct_sources() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let todo = db::upsert_todo(
        &conn,
        &key,
        "todo:budget-follow-up",
        "Prepare budget freeze follow-up",
        None,
        "open",
        None,
        None,
        None,
        None,
        None,
        None,
    )
    .expect("todo");
    let candidate = ContextItem {
        source: ContextSource::TodoThread,
        id: todo.id.clone(),
        created_at_ms: todo.created_at_ms,
        distance: Some(0.1),
        text: "TODO_THREAD todo_id=todo-1\nTODO [open] Prepare budget freeze follow-up".to_string(),
        citation_suffix: None,
    };

    let direct_sources = build_direct_sources_for_context_candidate(&conn, &key, &candidate);
    let source = direct_sources.first().expect("todo direct source");

    assert_eq!(source.source_type, "item");
    assert_eq!(source.href, format!("secondloop://todo/{}", todo.id));
    assert_eq!(
        source.title.as_deref(),
        Some("Prepare budget freeze follow-up")
    );
    assert!(
        source.snippet.contains("Prepare budget freeze follow-up"),
        "expected todo snippet to contain the todo title: {}",
        source.snippet
    );
}
