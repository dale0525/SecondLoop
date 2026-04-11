use anyhow::Result;
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
    }));
}
