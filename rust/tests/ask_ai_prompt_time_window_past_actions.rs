use anyhow::Result;
use rusqlite::params;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::embedding;
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
fn ask_ai_time_window_prompt_includes_done_items_for_past_agenda_queries() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    db::set_active_embedding_model_name(&conn, embedding::DEFAULT_MODEL_NAME).expect("model");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    let time_start_ms: i64 = 160_000;
    let time_end_ms: i64 = time_start_ms + 86_400_000;

    db::upsert_todo(
        &conn,
        &key,
        "todo:done-in-window",
        "Ship launch recap",
        None,
        "open",
        None,
        None,
        None,
        None,
        None,
        None,
    )
    .expect("window todo");
    db::set_todo_status(&conn, &key, "todo:done-in-window", "done", None)
        .expect("set window todo done");
    let window_activity = db::list_todo_activities(&conn, &key, "todo:done-in-window")
        .expect("window activities")
        .into_iter()
        .last()
        .expect("window activity");
    conn.execute(
        "UPDATE todo_activities SET created_at_ms = ?2 WHERE id = ?1",
        params![window_activity.id, time_start_ms + 500],
    )
    .expect("set window activity ts");

    db::upsert_todo(
        &conn,
        &key,
        "todo:done-outside-window",
        "Old completed item",
        None,
        "open",
        None,
        None,
        None,
        None,
        None,
        None,
    )
    .expect("old todo");
    db::set_todo_status(&conn, &key, "todo:done-outside-window", "done", None)
        .expect("set old todo done");
    let old_activity = db::list_todo_activities(&conn, &key, "todo:done-outside-window")
        .expect("old activities")
        .into_iter()
        .last()
        .expect("old activity");
    conn.execute(
        "UPDATE todo_activities SET created_at_ms = ?2 WHERE id = ?1",
        params![old_activity.id, time_start_ms - 86_400_000],
    )
    .expect("set old activity ts");

    let provider = FakeProvider::default();
    rag::ask_ai_with_provider_using_active_embeddings_time_window(
        &conn,
        &key,
        &app_dir,
        &conversation.id,
        "昨天我做了哪些事？",
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
        prompt.contains("Ship launch recap"),
        "expected completed in-range todo in past actions context: {prompt}"
    );
    assert!(
        !prompt.contains("Old completed item"),
        "expected out-of-range completed todo to stay out of prompt: {prompt}"
    );
}

#[test]
fn ask_ai_time_window_past_actions_keep_completion_semantics_after_later_note() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    db::set_active_embedding_model_name(&conn, embedding::DEFAULT_MODEL_NAME).expect("model");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    let time_start_ms: i64 = 220_000;
    let time_end_ms: i64 = time_start_ms + 86_400_000;

    db::upsert_todo(
        &conn,
        &key,
        "todo:done-then-noted",
        "Finish investor update",
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
    db::set_todo_status(&conn, &key, "todo:done-then-noted", "done", None).expect("set todo done");
    let done_activity = db::list_todo_activities(&conn, &key, "todo:done-then-noted")
        .expect("activities after done")
        .into_iter()
        .last()
        .expect("done activity");
    conn.execute(
        "UPDATE todo_activities SET created_at_ms = ?2 WHERE id = ?1",
        params![done_activity.id, time_start_ms + 100],
    )
    .expect("set done activity ts");

    let note_activity = db::append_todo_note(
        &conn,
        &key,
        "todo:done-then-noted",
        "Shared the final summary with Alice",
        None,
    )
    .expect("append note");
    conn.execute(
        "UPDATE todo_activities SET created_at_ms = ?2 WHERE id = ?1",
        params![note_activity.id, time_start_ms + 200],
    )
    .expect("set note ts");

    db::set_todo_status(&conn, &key, "todo:done-then-noted", "open", None)
        .expect("reopen todo after window semantics changed");

    let provider = FakeProvider::default();
    rag::ask_ai_with_provider_using_active_embeddings_time_window(
        &conn,
        &key,
        &app_dir,
        &conversation.id,
        "昨天我完成了什么？",
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
        prompt.contains("TODO [done] Finish investor update"),
        "expected completion entry to survive later note activity: {prompt}"
    );
    assert!(
        !prompt.contains("TODO_ACTIVITY [open] Finish investor update"),
        "expected current todo status to not rewrite past action semantics: {prompt}"
    );
}
