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
fn ask_ai_agenda_includes_actions_context() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");

    db::upsert_todo(
        &conn,
        &key,
        "todo:1",
        "Buy milk",
        Some(0),
        "open",
        None,
        None,
        None,
        None,
    )
    .expect("todo");

    let now_ms: i64 = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("clock")
        .as_millis()
        .try_into()
        .expect("ms");
    db::upsert_event(
        &conn,
        &key,
        "event:1",
        "Lunch with Alice",
        now_ms + 30 * 60 * 1000,
        now_ms + 90 * 60 * 1000,
        "UTC",
        None,
    )
    .expect("event");

    let provider = FakeProvider::default();
    rag::ask_ai_with_provider(
        &conn,
        &key,
        &conversation.id,
        "What should I do today?",
        0,
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
    assert!(prompt.contains("Buy milk"));
    assert!(prompt.contains("Lunch with Alice"));
}
