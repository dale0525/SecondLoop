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
fn ask_ai_prompt_includes_history() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");

    db::insert_message(&conn, &key, &conversation.id, "user", "HISTORY_USER_1").expect("seed u1");
    db::insert_message(
        &conn,
        &key,
        &conversation.id,
        "assistant",
        "HISTORY_ASSISTANT_1",
    )
    .expect("seed a1");
    db::insert_message(&conn, &key, &conversation.id, "user", "HISTORY_USER_2").expect("seed u2");
    db::insert_message(
        &conn,
        &key,
        &conversation.id,
        "assistant",
        "HISTORY_ASSISTANT_2",
    )
    .expect("seed a2");

    let provider = FakeProvider::default();
    rag::ask_ai_with_provider_using_active_embeddings(
        &conn,
        &key,
        &app_dir,
        &conversation.id,
        "what now?",
        0,
        rag::Focus::ThisThread,
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

    assert!(prompt.contains("HISTORY_USER_1"));
    assert!(prompt.contains("HISTORY_ASSISTANT_1"));
    assert!(prompt.contains("HISTORY_USER_2"));
    assert!(prompt.contains("HISTORY_ASSISTANT_2"));
}
