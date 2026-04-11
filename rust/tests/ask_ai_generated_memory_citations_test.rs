use anyhow::Result;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::llm::ChatDelta;
use secondloop_rust::{auth, db, knowledge, rag};

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
            text_delta: "Keep the weekly plan concise.".to_string(),
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

fn ask_ai_citations_json_fixture() -> serde_json::Value {
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
    db::insert_message(
        &conn,
        &key,
        &conversation.id,
        "user",
        "Budget freeze decision: freeze-signal budget decision. Follow up with Alice on Monday.",
    )
    .expect("evidence");

    knowledge::ensure_knowledge_rebuild_requested(&conn).expect("request rebuild");
    knowledge::process_pending_knowledge_index_jobs_active(&conn, &key, 256).expect("process jobs");

    let provider = FakeProvider;
    let result = rag::ask_ai_with_provider_using_active_embeddings(
        &conn,
        &key,
        &app_dir,
        &conversation.id,
        "Plan my week in my usual style around the budget freeze.",
        6,
        rag::Focus::ThisThread,
        &provider,
        &mut |_event| Ok(()),
    )
    .expect("ask ai");

    let assistant = db::get_message_by_id_optional(&conn, &key, &result.assistant_message_id)
        .expect("message lookup")
        .expect("assistant message");
    let raw = assistant.citations_json.as_deref().expect("citations json");
    serde_json::from_str(raw).expect("valid json")
}

#[test]
fn ask_ai_citations_json_includes_generated_memory_entries() {
    let value = ask_ai_citations_json_fixture();

    let direct_sources = value["direct_sources"]
        .as_array()
        .expect("direct_sources array");
    let memory_cards = value["memory_cards"]
        .as_array()
        .expect("memory_cards array");

    assert!(!direct_sources.is_empty());
    assert!(!memory_cards.is_empty());
    assert_eq!(
        memory_cards[0]["document_id"]
            .as_str()
            .map(|value| value.starts_with("generated:")),
        Some(true)
    );
    assert_eq!(memory_cards[0]["status"].as_str(), Some("inferred"));
    assert!(direct_sources[0]["source_type_label"]
        .as_str()
        .is_some_and(|value| !value.trim().is_empty()));
    assert!(direct_sources[0]["highlighted_text"]
        .as_str()
        .is_some_and(|value| !value.trim().is_empty()));
}

#[test]
fn ask_ai_citations_json_preserves_readable_source_labels_and_highlight_text() {
    let value = ask_ai_citations_json_fixture();

    let direct_sources = value["direct_sources"]
        .as_array()
        .expect("direct_sources array");
    let first = &direct_sources[0];

    assert_eq!(first["source_type"].as_str(), Some("message"));
    assert_eq!(first["source_type_label"].as_str(), Some("Chat message"));
    assert!(first["highlighted_text"]
        .as_str()
        .is_some_and(|value| value.contains("Chinese") || value.contains("budget")));
}
