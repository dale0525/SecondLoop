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

fn capture_prompt(provider: &FakeProvider) -> String {
    provider
        .last_prompt
        .lock()
        .unwrap()
        .clone()
        .expect("prompt")
}

#[test]
fn ask_ai_time_window_past_actions_use_activity_timestamps_not_due_dates() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    db::set_active_embedding_model_name(&conn, embedding::DEFAULT_MODEL_NAME).expect("model");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    let time_start_ms: i64 = 300_000;
    let time_end_ms: i64 = time_start_ms + 86_400_000;

    db::upsert_todo(
        &conn,
        &key,
        "todo:due-only",
        "Due-only completed item",
        Some(time_start_ms + 500),
        "done",
        None,
        None,
        None,
        None,
        None,
        None,
    )
    .expect("due only todo");

    db::upsert_todo(
        &conn,
        &key,
        "todo:activity-based",
        "Activity-based completion",
        None,
        "open",
        None,
        None,
        None,
        None,
        None,
        None,
    )
    .expect("activity todo");
    db::set_todo_status(&conn, &key, "todo:activity-based", "done", None)
        .expect("set activity todo done");
    let activity = db::list_todo_activities(&conn, &key, "todo:activity-based")
        .expect("activities")
        .into_iter()
        .last()
        .expect("done activity");
    conn.execute(
        "UPDATE todo_activities SET created_at_ms = ?2 WHERE id = ?1",
        params![activity.id, time_start_ms + 1_000],
    )
    .expect("update activity ts");

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

    let prompt = capture_prompt(&provider);
    assert!(
        prompt.contains("Activity-based completion"),
        "expected activity-timestamped todo in past actions context: {prompt}"
    );
    assert!(
        !prompt.contains("Due-only completed item"),
        "due date alone should not count as completed past action: {prompt}"
    );
}

#[test]
fn ask_ai_time_window_todo_thread_excludes_out_of_range_activities() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    db::set_active_embedding_model_name(&conn, embedding::DEFAULT_MODEL_NAME).expect("model");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    let time_start_ms: i64 = 400_000;
    let time_end_ms: i64 = time_start_ms + 86_400_000;

    db::upsert_todo(
        &conn,
        &key,
        "todo:fundraising",
        "Fundraising follow-up",
        Some(time_start_ms + 500),
        "open",
        None,
        None,
        None,
        None,
        None,
        None,
    )
    .expect("todo");

    let old_note = db::append_todo_note(
        &conn,
        &key,
        "todo:fundraising",
        "Legacy investor note that should stay out of range",
        None,
    )
    .expect("old note");
    conn.execute(
        "UPDATE todo_activities SET created_at_ms = ?2 WHERE id = ?1",
        params![old_note.id, time_start_ms - 100],
    )
    .expect("set old note ts");

    let in_range_note = db::append_todo_note(
        &conn,
        &key,
        "todo:fundraising",
        "Fresh investor update inside the selected day",
        None,
    )
    .expect("in-range note");
    conn.execute(
        "UPDATE todo_activities SET created_at_ms = ?2 WHERE id = ?1",
        params![in_range_note.id, time_start_ms + 100],
    )
    .expect("set in-range note ts");

    let provider = FakeProvider::default();
    rag::ask_ai_with_provider_using_active_embeddings_time_window(
        &conn,
        &key,
        &app_dir,
        &conversation.id,
        "What should I do about fundraising today?",
        4,
        rag::Focus::AllMemories,
        time_start_ms,
        time_end_ms,
        &provider,
        &mut |_ev| Ok(()),
    )
    .expect("ask");

    let prompt = capture_prompt(&provider);
    assert!(
        prompt.contains("Fresh investor update inside the selected day"),
        "expected in-range todo activity in prompt: {prompt}"
    );
    assert!(
        !prompt.contains("Legacy investor note that should stay out of range"),
        "out-of-range todo activity leaked through todo thread context: {prompt}"
    );
}

#[test]
fn ask_ai_time_window_candidate_limits_keep_recent_todo_activity_matches() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    db::set_active_embedding_model_name(&conn, embedding::DEFAULT_MODEL_NAME).expect("model");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    let time_start_ms: i64 = 500_000;
    let time_end_ms: i64 = time_start_ms + 86_400_000;

    db::upsert_todo(
        &conn,
        &key,
        "todo:activity-limit",
        "Candidate limit check",
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

    for index in 0..305 {
        let content = if index == 304 {
            "recent needle for time-window ranking"
        } else {
            "background note"
        };
        let activity =
            db::append_todo_note(&conn, &key, "todo:activity-limit", content, None).expect("note");
        conn.execute(
            "UPDATE todo_activities SET created_at_ms = ?2 WHERE id = ?1",
            params![activity.id, time_start_ms + index as i64],
        )
        .expect("set note ts");
    }

    let provider = FakeProvider::default();
    rag::ask_ai_with_provider_using_active_embeddings_time_window(
        &conn,
        &key,
        &app_dir,
        &conversation.id,
        "Where is the recent needle?",
        4,
        rag::Focus::AllMemories,
        time_start_ms,
        time_end_ms,
        &provider,
        &mut |_ev| Ok(()),
    )
    .expect("ask");

    let prompt = capture_prompt(&provider);
    assert!(
        prompt.contains("recent needle for time-window ranking"),
        "expected newest matching todo activity to survive candidate limit: {prompt}"
    );
}

#[test]
fn ask_ai_time_window_candidate_limits_keep_recent_event_matches() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    db::set_active_embedding_model_name(&conn, embedding::DEFAULT_MODEL_NAME).expect("model");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    let time_start_ms: i64 = 600_000;
    let time_end_ms: i64 = time_start_ms + 86_400_000;

    for index in 0..205 {
        let title = if index == 204 {
            "Needle event at the end of the range"
        } else {
            "Background sync"
        };
        db::upsert_event(
            &conn,
            &key,
            &format!("event:{index}"),
            title,
            time_start_ms + index as i64 * 10,
            time_start_ms + index as i64 * 10 + 5,
            "UTC",
            None,
        )
        .expect("event");
    }

    let provider = FakeProvider::default();
    rag::ask_ai_with_provider_using_active_embeddings_time_window(
        &conn,
        &key,
        &app_dir,
        &conversation.id,
        "Tell me about the needle event",
        4,
        rag::Focus::AllMemories,
        time_start_ms,
        time_end_ms,
        &provider,
        &mut |_ev| Ok(()),
    )
    .expect("ask");

    let prompt = capture_prompt(&provider);
    assert!(
        prompt.contains("Needle event at the end of the range"),
        "expected newest matching event to survive candidate limit: {prompt}"
    );
}

#[test]
fn ask_ai_time_window_upcoming_actions_keep_in_range_events_when_truncated() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    db::set_active_embedding_model_name(&conn, embedding::DEFAULT_MODEL_NAME).expect("model");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    let time_start_ms: i64 = 700_000;
    let time_end_ms: i64 = time_start_ms + 86_400_000;

    for index in 0..41 {
        let due_at_ms = if index < 2 {
            time_start_ms + 100 + index as i64
        } else {
            time_start_ms + 10_000 + index as i64
        };
        db::upsert_todo(
            &conn,
            &key,
            &format!("todo:upcoming:{index:02}"),
            &format!("Upcoming todo {index:02}"),
            Some(due_at_ms),
            "open",
            None,
            None,
            None,
            None,
            None,
            None,
        )
        .expect("todo");
    }

    db::upsert_event(
        &conn,
        &key,
        "event:critical-sync",
        "Critical sync in the middle of the day",
        time_start_ms + 500,
        time_start_ms + 900,
        "UTC",
        None,
    )
    .expect("event");

    let provider = FakeProvider::default();
    rag::ask_ai_with_provider_using_active_embeddings_time_window(
        &conn,
        &key,
        &app_dir,
        &conversation.id,
        "What's on my schedule today?",
        0,
        rag::Focus::ThisThread,
        time_start_ms,
        time_end_ms,
        &provider,
        &mut |_ev| Ok(()),
    )
    .expect("ask");

    let prompt = capture_prompt(&provider);
    assert!(
        prompt.contains("Critical sync in the middle of the day"),
        "expected in-range event to survive upcoming actions truncation: {prompt}"
    );
    assert!(
        !prompt.contains("Upcoming todo 40"),
        "expected later todo to be truncated before in-range event: {prompt}"
    );
}

#[test]
fn ask_ai_time_window_past_actions_truncate_by_recency_not_todo_id() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    db::set_active_embedding_model_name(&conn, embedding::DEFAULT_MODEL_NAME).expect("model");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    let time_start_ms: i64 = 800_000;
    let time_end_ms: i64 = time_start_ms + 86_400_000;

    for index in 0..41 {
        let todo_id = format!("todo:past:{index:02}");
        db::upsert_todo(
            &conn,
            &key,
            &todo_id,
            &format!("Past action {index:02}"),
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
        let activity = db::append_todo_note(
            &conn,
            &key,
            &todo_id,
            &format!("completed note {index:02}"),
            None,
        )
        .expect("activity");
        conn.execute(
            "UPDATE todo_activities SET created_at_ms = ?2 WHERE id = ?1",
            params![activity.id, time_start_ms + index as i64],
        )
        .expect("set activity ts");
    }

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

    let prompt = capture_prompt(&provider);
    assert!(
        prompt.contains("Past action 40"),
        "expected latest action to survive truncation: {prompt}"
    );
    assert!(
        !prompt.contains("Past action 00"),
        "expected oldest action to be truncated first: {prompt}"
    );
}

#[test]
fn ask_ai_time_window_past_actions_keep_stable_order_when_timestamps_match() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    db::set_active_embedding_model_name(&conn, embedding::DEFAULT_MODEL_NAME).expect("model");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    let time_start_ms: i64 = 900_000;
    let time_end_ms: i64 = time_start_ms + 86_400_000;
    let shared_done_at_ms = time_start_ms + 1_000;

    for (todo_id, title) in [
        ("todo:beta", "Beta follow-up"),
        ("todo:alpha", "Alpha follow-up"),
    ] {
        db::upsert_todo(
            &conn, &key, todo_id, title, None, "open", None, None, None, None, None, None,
        )
        .expect("todo");
        db::set_todo_status(&conn, &key, todo_id, "done", None).expect("set done");
        let activity = db::list_todo_activities(&conn, &key, todo_id)
            .expect("activities")
            .into_iter()
            .last()
            .expect("done activity");
        conn.execute(
            "UPDATE todo_activities SET created_at_ms = ?2 WHERE id = ?1",
            params![activity.id, shared_done_at_ms],
        )
        .expect("set shared done ts");
    }

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

    let prompt = capture_prompt(&provider);
    let alpha_index = prompt.find("Alpha follow-up").expect("alpha in prompt");
    let beta_index = prompt.find("Beta follow-up").expect("beta in prompt");
    assert!(
        alpha_index < beta_index,
        "expected stable tie-break ordering for matching timestamps: {prompt}"
    );
}
