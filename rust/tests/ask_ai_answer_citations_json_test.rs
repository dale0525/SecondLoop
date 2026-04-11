use anyhow::Result;
use rusqlite::params;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::llm::ChatDelta;
use secondloop_rust::{auth, db, rag};
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Default)]
struct FakeProvider;

impl rag::AnswerProvider for FakeProvider {
    fn stream_answer(
        &self,
        _prompt: &str,
        on_event: &mut dyn FnMut(ChatDelta) -> Result<()>,
    ) -> Result<()> {
        on_event(ChatDelta {
            role: Some("assistant".to_string()),
            text_delta: "The prior note is still relevant.".to_string(),
            done: false,
        })?;
        on_event(ChatDelta {
            role: None,
            text_delta: String::new(),
            done: true,
        })?;
        Ok(())
    }
}

fn write_text(path: &Path, text: &str) {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).expect("create parent");
    }
    fs::write(path, text).expect("write text");
}

fn create_external_markdown_source(root: &Path) -> PathBuf {
    let source = root.join("markdown-library");
    write_text(
        &source.join("travel/plan.md"),
        "# Trip Plan\n\nBudget checklist and hotel notes.\n",
    );
    write_text(
        &source.join("travel/expense-sheet.markdown"),
        "# Expense Sheet\n\nRemember the flight refund and budget cap.\n",
    );
    source
}

#[test]
fn ask_ai_saves_structured_citations_json_on_assistant_message() {
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
        "Project kickoff moved to Friday afternoon.",
    )
    .expect("seed");
    db::process_pending_message_embeddings_default(&conn, &key, 100).expect("embed");

    let provider = FakeProvider;
    let result = rag::ask_ai_with_provider(
        &conn,
        &key,
        &conversation.id,
        "What changed?",
        3,
        rag::Focus::ThisThread,
        &provider,
        &mut |_event| Ok(()),
    )
    .expect("ask ai");

    let assistant = db::get_message_by_id_optional(&conn, &key, &result.assistant_message_id)
        .expect("message lookup")
        .expect("assistant message");
    let raw = assistant.citations_json.as_deref().expect("citations json");
    let value: serde_json::Value = serde_json::from_str(raw).expect("valid json");
    let direct_sources = value["direct_sources"]
        .as_array()
        .expect("direct_sources array");

    assert!(!direct_sources.is_empty());
    assert_eq!(direct_sources[0]["source_type"].as_str(), Some("message"));
    assert_eq!(
        direct_sources[0]["source_type_label"].as_str(),
        Some("chat_message")
    );
}

#[test]
fn ask_ai_citations_json_includes_external_document_direct_sources() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    let source = create_external_markdown_source(temp_dir.path());

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");

    db::run_external_import_with_callbacks(&app_dir, &key, &source, &mut |_| {}, &|| false)
        .expect("import external docs");

    let provider = FakeProvider;
    let result = rag::ask_ai_with_provider(
        &conn,
        &key,
        &conversation.id,
        "Where is the budget cap documented?",
        4,
        rag::Focus::AllMemories,
        &provider,
        &mut |_event| Ok(()),
    )
    .expect("ask ai");

    let assistant = db::get_message_by_id_optional(&conn, &key, &result.assistant_message_id)
        .expect("message lookup")
        .expect("assistant message");
    let raw = assistant.citations_json.as_deref().expect("citations json");
    let value: serde_json::Value = serde_json::from_str(raw).expect("valid json");
    let direct_sources = value["direct_sources"]
        .as_array()
        .expect("direct_sources array");

    assert!(direct_sources.iter().any(|source| {
        source["source_type"].as_str() == Some("document")
            && source["document_id"]
                .as_str()
                .is_some_and(|value| value.starts_with("external:"))
            && source["unit_id"]
                .as_str()
                .is_some_and(|value| value.starts_with("external:") && value.contains(":chunk:"))
            && source["href"].as_str().is_some_and(|value| {
                value.contains("secondloop://knowledge-document/") && value.contains("unit=")
            })
    }));
}

#[test]
fn ask_ai_citations_json_includes_attachment_resource_direct_sources_for_time_window_catalog() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    db::set_active_embedding_model_name(&conn, secondloop_rust::embedding::DEFAULT_MODEL_NAME)
        .expect("model");
    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");

    let message = db::insert_message(
        &conn,
        &key,
        &conversation.id,
        "user",
        "Please summarize the launch brief attachment.",
    )
    .expect("message");
    let time_start_ms: i64 = 5_000_000;
    let time_end_ms: i64 = time_start_ms + 86_400_000;
    conn.execute(
        "UPDATE messages SET created_at = ?2, updated_at = ?2 WHERE id = ?1",
        params![message.id, time_start_ms + 10],
    )
    .expect("update message ts");
    let attachment = db::insert_attachment(
        &conn,
        &key,
        &app_dir,
        b"Launch brief line one.\nLaunch brief line two.",
        "text/plain",
    )
    .expect("attachment");
    db::link_attachment_to_message(&conn, &key, &message.id, &attachment.sha256)
        .expect("link attachment");
    db::upsert_attachment_metadata(
        &conn,
        &key,
        &attachment.sha256,
        Some("Launch brief"),
        &["launch-brief.txt".to_string()],
        &[],
    )
    .expect("metadata");
    db::process_attachment_text_chunks(&conn, &key, 256).expect("chunk attachment");

    let provider = FakeProvider;
    let result = rag::ask_ai_with_provider_using_active_embeddings_time_window(
        &conn,
        &key,
        &app_dir,
        &conversation.id,
        "What does the launch brief say?",
        4,
        rag::Focus::ThisThread,
        time_start_ms,
        time_end_ms,
        &provider,
        &mut |_event| Ok(()),
    )
    .expect("ask ai");

    let assistant = db::get_message_by_id_optional(&conn, &key, &result.assistant_message_id)
        .expect("message lookup")
        .expect("assistant message");
    let raw = assistant.citations_json.as_deref().expect("citations json");
    let value: serde_json::Value = serde_json::from_str(raw).expect("valid json");
    let direct_sources = value["direct_sources"]
        .as_array()
        .expect("direct_sources array");
    let attachment_source = direct_sources
        .iter()
        .find(|source| source["source_type"].as_str() == Some("attachment"))
        .unwrap_or_else(|| panic!("attachment direct source missing from {value}"));
    let snippet = attachment_source["snippet"]
        .as_str()
        .expect("attachment snippet");

    assert!(
        attachment_source["href"].as_str()
            == Some(&format!("secondloop://attachment/{}", attachment.sha256)),
        "expected attachment resource deep link: {value}"
    );
    assert!(
        snippet == "Launch brief",
        "expected attachment resource label snippet: {snippet}"
    );
}
