use anyhow::Result;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::llm::ChatDelta;
use secondloop_rust::{auth, db, rag};

const STREAM_REQUEST_ID: &str = "req_stream_completion_is_claimed";

#[derive(Default)]
struct FakeProviderWithRequestId;

impl rag::AnswerProvider for FakeProviderWithRequestId {
    fn stream_answer(
        &self,
        _prompt: &str,
        on_event: &mut dyn FnMut(ChatDelta) -> Result<()>,
    ) -> Result<()> {
        on_event(ChatDelta {
            role: Some(format!("secondloop_request_id:{STREAM_REQUEST_ID}")),
            text_delta: String::new(),
            done: false,
        })?;
        on_event(ChatDelta {
            role: Some("assistant".to_string()),
            text_delta: "Recovered answer should not be inserted twice.".to_string(),
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
fn streamed_cloud_completion_blocks_detached_recovery_reinsertion() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");

    let provider = FakeProviderWithRequestId;
    rag::ask_ai_with_provider(
        &conn,
        &key,
        &conversation.id,
        "Only ask once",
        1,
        rag::Focus::ThisThread,
        &provider,
        &mut |_event| Ok(()),
    )
    .expect("stream ask ai");

    let applied = db::apply_detached_ask_completion_once(
        &conn,
        &key,
        STREAM_REQUEST_ID,
        &conversation.id,
        "Only ask once",
        "Recovered answer should not be inserted twice.",
    )
    .expect("apply detached completion");

    assert!(
        !applied,
        "detached recovery should not insert a second copy after the stream already persisted"
    );

    let messages = db::list_messages(&conn, &key, &conversation.id).expect("list messages");
    assert_eq!(
        messages.len(),
        2,
        "should keep a single user/assistant pair"
    );
    assert_eq!(messages[0].role, "user");
    assert_eq!(messages[0].content, "Only ask once");
    assert_eq!(messages[1].role, "assistant");
    assert_eq!(
        messages[1].content,
        "Recovered answer should not be inserted twice."
    );
}

#[test]
fn detached_recovery_inserted_first_blocks_stream_completion_reinsertion() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");

    let applied = db::apply_detached_ask_completion_once(
        &conn,
        &key,
        STREAM_REQUEST_ID,
        &conversation.id,
        "Only ask once",
        "Recovered answer should not be inserted twice.",
    )
    .expect("apply detached completion first");
    assert!(applied, "detached recovery should insert the first copy");

    let provider = FakeProviderWithRequestId;
    rag::ask_ai_with_provider(
        &conn,
        &key,
        &conversation.id,
        "Only ask once",
        1,
        rag::Focus::ThisThread,
        &provider,
        &mut |_event| Ok(()),
    )
    .expect("stream ask ai after detached recovery");

    let messages = db::list_messages(&conn, &key, &conversation.id).expect("list messages");
    assert_eq!(
        messages.len(),
        2,
        "stream completion should not insert a duplicate user/assistant pair after detached recovery"
    );
    assert_eq!(messages[0].role, "user");
    assert_eq!(messages[0].content, "Only ask once");
    assert_eq!(messages[1].role, "assistant");
    assert_eq!(
        messages[1].content,
        "Recovered answer should not be inserted twice."
    );
}

#[test]
fn detached_recovery_keeps_exact_message_ids_for_duplicate_content() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");

    let existing_user =
        db::insert_message_non_memory(&conn, &key, &conversation.id, "user", "Only ask once")
            .expect("seed user");
    let existing_assistant = db::insert_message_non_memory(
        &conn,
        &key,
        &conversation.id,
        "assistant",
        "Recovered answer should not be inserted twice.",
    )
    .expect("seed assistant");

    let applied = db::apply_detached_ask_completion_once(
        &conn,
        &key,
        STREAM_REQUEST_ID,
        &conversation.id,
        "Only ask once",
        "Recovered answer should not be inserted twice.",
    )
    .expect("apply detached completion first");
    assert!(
        applied,
        "detached recovery should insert the request-bound pair"
    );

    let distracting_user =
        db::insert_message_non_memory(&conn, &key, &conversation.id, "user", "Only ask once")
            .expect("distracting user");
    let distracting_assistant = db::insert_message_non_memory(
        &conn,
        &key,
        &conversation.id,
        "assistant",
        "Recovered answer should not be inserted twice.",
    )
    .expect("distracting assistant");

    let provider = FakeProviderWithRequestId;
    let result = rag::ask_ai_with_provider(
        &conn,
        &key,
        &conversation.id,
        "Only ask once",
        1,
        rag::Focus::ThisThread,
        &provider,
        &mut |_event| Ok(()),
    )
    .expect("stream ask ai after detached recovery");

    let messages = db::list_messages(&conn, &key, &conversation.id).expect("list messages");
    assert_eq!(
        messages.len(),
        6,
        "existing duplicate-content messages should remain untouched"
    );
    assert_eq!(result.user_message_id, messages[2].id);
    assert_eq!(result.assistant_message_id, messages[3].id);
    assert_ne!(result.user_message_id, existing_user.id);
    assert_ne!(result.assistant_message_id, existing_assistant.id);
    assert_ne!(result.user_message_id, distracting_user.id);
    assert_ne!(result.assistant_message_id, distracting_assistant.id);
}
