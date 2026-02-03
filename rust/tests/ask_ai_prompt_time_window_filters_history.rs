use anyhow::Result;
use rusqlite::params;
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
fn ask_ai_time_window_prompt_filters_conversation_history_by_range() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");

    // Set up a time window (like "today").
    let time_start_ms: i64 = 1_000_000;
    let time_end_ms: i64 = time_start_ms + 86_400_000;

    // Seed an "old" message that should NOT be included.
    let old_user = db::insert_message(&conn, &key, &conversation.id, "user", "HISTORY_OLD_USER")
        .expect("old user");
    conn.execute(
        "UPDATE messages SET created_at = ?2, updated_at = ?2 WHERE id = ?1",
        params![old_user.id, time_start_ms - 7 * 86_400_000],
    )
    .expect("update old user ts");

    let old_assistant = db::insert_message(
        &conn,
        &key,
        &conversation.id,
        "assistant",
        "HISTORY_OLD_ASSISTANT",
    )
    .expect("old assistant");
    conn.execute(
        "UPDATE messages SET created_at = ?2, updated_at = ?2 WHERE id = ?1",
        params![old_assistant.id, time_start_ms - 7 * 86_400_000 + 1],
    )
    .expect("update old assistant ts");

    // Seed an "in range" message that SHOULD be included.
    let new_user = db::insert_message(
        &conn,
        &key,
        &conversation.id,
        "user",
        "HISTORY_IN_RANGE_USER",
    )
    .expect("new user");
    conn.execute(
        "UPDATE messages SET created_at = ?2, updated_at = ?2 WHERE id = ?1",
        params![new_user.id, time_start_ms + 1],
    )
    .expect("update new user ts");

    let provider = FakeProvider::default();
    rag::ask_ai_with_provider_using_active_embeddings_time_window(
        &conn,
        &key,
        &app_dir,
        &conversation.id,
        "今天有哪些事要做？",
        0,
        rag::Focus::ThisThread,
        time_start_ms,
        time_end_ms,
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
        prompt.contains("HISTORY_IN_RANGE_USER"),
        "expected in-range history missing: {prompt}"
    );
    assert!(
        !prompt.contains("HISTORY_OLD_USER"),
        "expected old history to be filtered out: {prompt}"
    );
    assert!(
        !prompt.contains("HISTORY_OLD_ASSISTANT"),
        "expected old history to be filtered out: {prompt}"
    );
}
