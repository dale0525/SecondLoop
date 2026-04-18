use anyhow::Result;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::llm::ChatDelta;
use secondloop_rust::{auth, db, rag};

#[derive(Default)]
struct FakeProvider {
    last_prompt: std::sync::Mutex<Option<String>>,
}

impl rag::AnswerProvider for FakeProvider {
    fn stream_answer(
        &self,
        prompt: &str,
        on_event: &mut dyn FnMut(ChatDelta) -> Result<()>,
    ) -> Result<()> {
        *self.last_prompt.lock().unwrap() = Some(prompt.to_string());
        on_event(ChatDelta {
            role: Some("assistant".to_string()),
            text_delta: "OK".to_string(),
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
fn ask_ai_prompt_excludes_external_import_context() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    let source_dir = temp_dir.path().join("obsidian-vault");
    std::fs::create_dir_all(source_dir.join(".obsidian")).expect("obsidian dir");
    std::fs::write(
        source_dir.join("travel.md"),
        "# Trip Plan\n\nBudget checklist and flight refund notes.",
    )
    .expect("write note");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    db::run_external_import_with_callbacks(&app_dir, &key, &source_dir, &mut |_| {}, &|| false)
        .expect("import");

    let provider = FakeProvider::default();
    rag::ask_ai_with_provider(
        &conn,
        &key,
        &conversation.id,
        "Where is the flight refund note?",
        5,
        rag::Focus::AllMemories,
        &provider,
        &mut |_ev| Ok(()),
    )
    .expect("ask");

    let prompt = provider
        .last_prompt
        .lock()
        .unwrap()
        .clone()
        .expect("prompt");
    assert!(
        !prompt.contains("Budget checklist and flight refund notes."),
        "external import content should no longer enter ask-ai prompt: {prompt}"
    );
    assert!(
        !prompt.contains("EXTERNAL_DOCUMENT"),
        "legacy external-document marker should no longer appear in ask-ai prompt: {prompt}"
    );
}
