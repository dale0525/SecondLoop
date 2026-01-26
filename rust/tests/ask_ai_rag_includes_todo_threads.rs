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
fn ask_ai_rag_includes_todo_thread_when_activity_matches() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");

    db::upsert_todo(
        &conn,
        &key,
        "todo:1",
        "Prepare report",
        None,
        "inbox",
        None,
        None,
        None,
        None,
    )
    .expect("todo");

    db::append_todo_note(&conn, &key, "todo:1", "Met the client at office", None).expect("note1");
    db::append_todo_note(&conn, &key, "todo:1", "Sent summary email", None).expect("note2");

    let provider = FakeProvider::default();
    rag::ask_ai_with_provider(
        &conn,
        &key,
        &conversation.id,
        "Met the client at office",
        8,
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
    assert!(prompt.contains("TODO_THREAD todo_id=todo:1"));
    assert!(prompt.contains("Prepare report"));
    assert!(prompt.contains("Sent summary email"));
}

#[test]
fn ask_ai_rag_dedups_todo_thread_when_todo_and_activity_both_match() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");

    db::upsert_todo(
        &conn,
        &key,
        "todo:1",
        "Client follow-up",
        None,
        "inbox",
        None,
        None,
        None,
        None,
    )
    .expect("todo");

    db::append_todo_note(&conn, &key, "todo:1", "Client follow-up done", None).expect("note");

    let provider = FakeProvider::default();
    rag::ask_ai_with_provider(
        &conn,
        &key,
        &conversation.id,
        "Client follow-up",
        8,
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
    assert_eq!(prompt.matches("TODO_THREAD todo_id=todo:1").count(), 1);
}
