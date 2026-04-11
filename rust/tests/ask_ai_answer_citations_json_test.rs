use anyhow::Result;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::llm::ChatDelta;
use secondloop_rust::{auth, db, rag};

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
