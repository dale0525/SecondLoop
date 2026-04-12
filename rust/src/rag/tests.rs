use super::{
    build_external_document_direct_source, build_message_direct_source, format_history_line,
    should_include_actions_context, ContextItem, ContextSource,
};
use crate::auth;
use crate::crypto::KdfParams;
use crate::db;
use crate::knowledge::{
    KnowledgeAnchorSet, KnowledgeContextBlock, KnowledgeRole, KnowledgeSourceKind,
    KnowledgeUnitKind,
};
use crate::message_citations::AnswerEvidenceDirectSource;
use crate::rag::evidence::filter_direct_sources_for_question;
use crate::rag::evidence::{
    build_direct_sources_for_context_candidate, build_direct_sources_from_knowledge_entry,
    build_memory_card_from_document,
};
use crate::rag::knowledge_contexts::KnowledgeRenderedContextEntry;
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
fn knowledge_attachment_direct_sources_preserve_kind_and_chunk_target() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let entry = KnowledgeRenderedContextEntry {
        block: KnowledgeContextBlock {
            document_id: "attachment:sha-doc:readable_text".to_string(),
            unit_id: Some("attachment:sha-doc:readable_text:chunk:0004".to_string()),
            unit_kind: Some(KnowledgeUnitKind::Chunk),
            source_kind: KnowledgeSourceKind::ReadableText,
            role: KnowledgeRole::Evidence,
            anchors: KnowledgeAnchorSet {
                attachment_sha256: Some("sha-doc".to_string()),
                source_filename: Some("notes.txt".to_string()),
                ..KnowledgeAnchorSet::default()
            },
            score: 0.9,
            rendered_text: "Relevant launch notes".to_string(),
        },
        rendered_text: "Relevant launch notes".to_string(),
    };

    let direct_sources = build_direct_sources_from_knowledge_entry(&conn, &key, &entry);
    let source = direct_sources
        .first()
        .expect("attachment direct source from knowledge entry");

    assert_eq!(
        source.href,
        "secondloop://attachment/sha-doc?kind=readable_text_full&chunk=4"
    );
    assert_eq!(
        source.document_id.as_deref(),
        Some("attachment:sha-doc:readable_text")
    );
    assert_eq!(
        source.unit_id.as_deref(),
        Some("attachment:sha-doc:readable_text:chunk:0004")
    );
}

#[test]
fn generated_memory_cards_use_corrected_feedback_fields() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");

    db::insert_message(
        &conn,
        &key,
        &conversation.id,
        "user",
        "Please answer in Chinese and keep responses short and practical.",
    )
    .expect("preference");

    crate::knowledge::ensure_knowledge_rebuild_requested(&conn).expect("request rebuild");
    crate::knowledge::process_pending_knowledge_index_jobs_active(&conn, &key, 256)
        .expect("process jobs");

    crate::db::upsert_knowledge_memory_feedback(
        &conn,
        "generated:preference:response-language",
        Some(crate::knowledge::KnowledgeMemoryStatus::Confirmed),
        true,
        false,
        false,
        Some("Preferred reply language".to_string()),
        Some("Always reply in Chinese unless I ask for another language.".to_string()),
    )
    .expect("update generated memory");

    let card = build_memory_card_from_document(
        &conn,
        &key,
        "generated:preference:response-language",
        "How should you answer me?",
    )
    .expect("generated memory card");

    assert_eq!(card.title.as_deref(), Some("Preferred reply language"));
    assert_eq!(
        card.summary.as_deref(),
        Some("Always reply in Chinese unless I ask for another language.")
    );
    assert_eq!(
        card.body.as_deref(),
        Some("Always reply in Chinese unless I ask for another language.")
    );
}

#[test]
fn external_document_direct_source_percent_encodes_deeplink_targets() {
    let source = build_external_document_direct_source(
        "doc/with slash",
        7,
        "Budget notes",
        "Relevant chunk text",
        1,
    );

    assert_eq!(
        source.document_id.as_deref(),
        Some("external:doc/with slash")
    );
    assert_eq!(
        source.unit_id.as_deref(),
        Some("external:doc/with slash:chunk:0007")
    );
    assert!(
        source
            .href
            .contains("secondloop://knowledge-document/external%3Adoc%2Fwith%20slash"),
        "expected encoded document id in href: {}",
        source.href
    );
    assert!(
        source
            .href
            .contains("unit=external%3Adoc%2Fwith%20slash%3Achunk%3A0007"),
        "expected encoded unit id in href: {}",
        source.href
    );
}
