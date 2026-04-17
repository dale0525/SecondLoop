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
fn ask_ai_agenda_query_injects_actions_context() {
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
    assert!(
        prompt.contains("Upcoming actions (from local todos/events):"),
        "agenda prompts should inject synthetic actions context again: {prompt}"
    );
    assert!(
        prompt.contains("Lunch with Alice"),
        "agenda prompts should include matching calendar events in synthetic context: {prompt}"
    );
    assert!(
        prompt.contains("TODO [open] Buy milk"),
        "agenda prompts should include open todos in synthetic context: {prompt}"
    );
}

#[test]
fn ask_ai_schedule_query_without_time_words_injects_actions_context() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");

    db::upsert_todo(
        &conn,
        &key,
        "todo:schedule-1",
        "Prepare weekly brief",
        Some(0),
        "open",
        None,
        None,
        None,
        None,
        None,
        None,
    )
    .expect("todo");

    let provider = FakeProvider::default();
    rag::ask_ai_with_provider(
        &conn,
        &key,
        &conversation.id,
        "What is on my schedule?",
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
    assert!(
        prompt.contains("Upcoming actions (from local todos/events):"),
        "schedule prompts without explicit time words should still inject actions context: {prompt}"
    );
    assert!(
        prompt.contains("Prepare weekly brief"),
        "schedule prompts without explicit time words should include matching actions: {prompt}"
    );
}

#[test]
fn ask_ai_tomorrow_query_injects_actions_context() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");

    let now_ms: i64 = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("clock")
        .as_millis()
        .try_into()
        .expect("ms");
    db::upsert_event(
        &conn,
        &key,
        "event:tomorrow-review",
        "Tomorrow review",
        now_ms + 24 * 60 * 60 * 1000,
        now_ms + 25 * 60 * 60 * 1000,
        "UTC",
        None,
    )
    .expect("event");

    let provider = FakeProvider::default();
    rag::ask_ai_with_provider(
        &conn,
        &key,
        &conversation.id,
        "What should I do tomorrow?",
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
    assert!(
        prompt.contains("Upcoming actions (from local todos/events):"),
        "tomorrow prompts should inject actions context: {prompt}"
    );
    assert!(
        prompt.contains("Tomorrow review"),
        "tomorrow prompts should include matching events: {prompt}"
    );
}

#[test]
fn ask_ai_agenda_query_sorts_events_with_todos_before_truncation() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");

    let now_ms: i64 = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("clock")
        .as_millis()
        .try_into()
        .expect("ms");

    for index in 0..45 {
        db::upsert_todo(
            &conn,
            &key,
            &format!("todo:upcoming:{index:02}"),
            &format!("Upcoming todo {index:02}"),
            Some(now_ms + ((index + 1) as i64) * 10 * 60 * 1000),
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
        now_ms + 205 * 60 * 1000,
        now_ms + 235 * 60 * 1000,
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
    assert!(
        prompt.contains("Critical sync in the middle of the day"),
        "expected in-range event to survive synthetic action truncation: {prompt}"
    );
    assert!(
        !prompt.contains("Upcoming todo 40"),
        "expected later todos to be truncated after global ordering: {prompt}"
    );
}

#[test]
fn ask_ai_agenda_query_persists_synthetic_action_direct_sources() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");

    db::upsert_todo(
        &conn,
        &key,
        "todo:agenda-source",
        "Agenda source todo",
        Some(0),
        "open",
        None,
        None,
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
        "event:agenda-source",
        "Agenda source event",
        now_ms + 30 * 60 * 1000,
        now_ms + 60 * 60 * 1000,
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

    let messages = db::list_messages(&conn, &key, &conversation.id).expect("list messages");
    let assistant = messages.last().expect("assistant");
    let raw = assistant
        .citations_json
        .as_deref()
        .expect("citations json should be stored");
    let value: serde_json::Value = serde_json::from_str(raw).expect("valid json");
    let direct_sources = value["direct_sources"]
        .as_array()
        .expect("direct_sources array");

    assert!(
        direct_sources
            .iter()
            .any(|source| source["href"].as_str() == Some("secondloop://todo/todo:agenda-source")),
        "expected synthetic todo direct source to be persisted: {value}"
    );
    assert!(
        direct_sources.iter().any(|source| {
            source["href"].as_str() == Some("secondloop://event/event:agenda-source")
        }),
        "expected synthetic event direct source to be persisted: {value}"
    );
}

#[test]
fn ask_ai_project_plan_question_does_not_inject_actions_context() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");

    db::upsert_todo(
        &conn,
        &key,
        "todo:1",
        "Ship the release checklist",
        Some(0),
        "open",
        None,
        None,
        None,
        None,
        None,
        None,
    )
    .expect("todo");

    let provider = FakeProvider::default();
    rag::ask_ai_with_provider(
        &conn,
        &key,
        &conversation.id,
        "帮我写项目计划",
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
    assert!(
        !prompt.contains("Upcoming actions (from local todos/events):"),
        "project-planning prompts should not inject agenda context: {prompt}"
    );
    assert!(
        !prompt.contains("Ship the release checklist"),
        "project-planning prompts should not inject todo titles: {prompt}"
    );
}
