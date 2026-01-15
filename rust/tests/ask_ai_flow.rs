use anyhow::Result;
use secondloop_rust::{auth, db, rag};
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::llm::ChatDelta;

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

struct ErrorProvider;

impl rag::AnswerProvider for ErrorProvider {
    fn stream_answer(
        &self,
        _prompt: &str,
        _on_event: &mut dyn FnMut(ChatDelta) -> Result<()>,
    ) -> Result<()> {
        Err(anyhow::anyhow!("boom"))
    }
}

struct TwoChunkProvider;

impl rag::AnswerProvider for TwoChunkProvider {
    fn stream_answer(
        &self,
        _prompt: &str,
        on_event: &mut dyn FnMut(ChatDelta) -> Result<()>,
    ) -> Result<()> {
        on_event(ChatDelta {
            role: Some("assistant".to_string()),
            text_delta: "Hello".to_string(),
            done: false,
        })?;
        on_event(ChatDelta {
            role: None,
            text_delta: " world".to_string(),
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
fn ask_ai_stream_updates_db_and_uses_rag_context() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    db::insert_message(&conn, &key, &conversation.id, "user", "apple pie").expect("seed");
    db::process_pending_message_embeddings_default(&conn, &key, 100).expect("embed");

    let provider = FakeProvider::default();
    let mut events: Vec<ChatDelta> = Vec::new();

    let result = rag::ask_ai_with_provider(
        &conn,
        &key,
        &conversation.id,
        "apple",
        3,
        rag::Focus::AllMemories,
        &provider,
        &mut |ev| {
            events.push(ev);
            Ok(())
        },
    )
    .expect("ask");

    assert_eq!(events.len(), 2);
    assert_eq!(events[0].text_delta, "OK");
    assert!(events[1].done);

    let prompt = provider.last_prompt.lock().unwrap().clone().expect("prompt");
    assert!(prompt.contains("apple pie"));
    assert!(prompt.contains("Question: apple"));

    let messages = db::list_messages(&conn, &key, &conversation.id).expect("list");
    assert_eq!(messages.len(), 3);
    assert_eq!(messages[1].role, "user");
    assert_eq!(messages[1].content, "apple");
    assert_eq!(messages[2].role, "assistant");
    assert_eq!(messages[2].id, result.assistant_message_id);
    assert_eq!(messages[2].content, "OK");
}

#[test]
fn ask_ai_error_does_not_leave_empty_assistant_message() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    db::insert_message(&conn, &key, &conversation.id, "user", "apple pie").expect("seed");
    db::process_pending_message_embeddings_default(&conn, &key, 100).expect("embed");

    let provider = ErrorProvider;

    let err = rag::ask_ai_with_provider(
        &conn,
        &key,
        &conversation.id,
        "apple",
        3,
        rag::Focus::AllMemories,
        &provider,
        &mut |_ev| Ok(()),
    )
    .expect_err("ask should fail");
    assert!(err.to_string().contains("boom"));

    let messages = db::list_messages(&conn, &key, &conversation.id).expect("list");
    assert_eq!(messages.len(), 2);
    assert_eq!(messages[0].role, "user");
    assert_eq!(messages[0].content, "apple pie");
    assert_eq!(messages[1].role, "user");
    assert_eq!(messages[1].content, "apple");
}

#[test]
fn ask_ai_cancel_deletes_question_and_partial_answer() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    db::insert_message(&conn, &key, &conversation.id, "user", "seed").expect("seed");

    let provider = TwoChunkProvider;
    let mut seen = 0usize;

    let err = rag::ask_ai_with_provider(
        &conn,
        &key,
        &conversation.id,
        "question",
        3,
        rag::Focus::AllMemories,
        &provider,
        &mut |ev| {
            if ev.text_delta.is_empty() {
                return Ok(());
            }
            seen += 1;
            if seen == 2 {
                return Err(rag::StreamCancelled.into());
            }
            Ok(())
        },
    )
    .expect_err("ask should be cancelled");
    assert!(err.is::<rag::StreamCancelled>());

    let messages = db::list_messages(&conn, &key, &conversation.id).expect("list");
    assert_eq!(messages.len(), 1);
    assert_eq!(messages[0].content, "seed");
}
