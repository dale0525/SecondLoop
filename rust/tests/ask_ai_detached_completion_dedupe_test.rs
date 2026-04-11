use anyhow::Result;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::llm::ChatDelta;
use secondloop_rust::{auth, db, rag};

const STREAM_REQUEST_ID: &str = "req_stream_completion_is_claimed";
const PARTIAL_CLAIM_REQUEST_ID: &str = "req_partial_claim_needs_completion";
const CROSS_CONVERSATION_REQUEST_ID: &str = "req_shared_across_conversations";

struct FakeProviderWithRequestId {
    request_id: &'static str,
    answer: &'static str,
}

impl rag::AnswerProvider for FakeProviderWithRequestId {
    fn stream_answer(
        &self,
        _prompt: &str,
        on_event: &mut dyn FnMut(ChatDelta) -> Result<()>,
    ) -> Result<()> {
        on_event(ChatDelta {
            role: Some(format!("secondloop_request_id:{}", self.request_id)),
            text_delta: String::new(),
            done: false,
        })?;
        on_event(ChatDelta {
            role: Some("assistant".to_string()),
            text_delta: self.answer.to_string(),
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

    let provider = FakeProviderWithRequestId {
        request_id: STREAM_REQUEST_ID,
        answer: "Recovered answer should not be inserted twice.",
    };
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

    let provider = FakeProviderWithRequestId {
        request_id: STREAM_REQUEST_ID,
        answer: "Recovered answer should not be inserted twice.",
    };
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

    let provider = FakeProviderWithRequestId {
        request_id: STREAM_REQUEST_ID,
        answer: "Recovered answer should not be inserted twice.",
    };
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

#[test]
fn partial_detached_claim_without_message_ids_is_completed_by_stream_persistence() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");

    conn.execute(
        r#"INSERT INTO detached_ask_completion_claims(
               request_id,
               conversation_id,
               user_message_id,
               assistant_message_id,
               created_at_ms,
               updated_at_ms
           ) VALUES (?1, ?2, NULL, NULL, ?3, ?4)"#,
        (
            PARTIAL_CLAIM_REQUEST_ID,
            conversation.id.as_str(),
            1i64,
            1i64,
        ),
    )
    .expect("insert partial claim");

    let provider = FakeProviderWithRequestId {
        request_id: PARTIAL_CLAIM_REQUEST_ID,
        answer: "Partial claims should still finish persistence.",
    };
    let result = rag::ask_ai_with_provider(
        &conn,
        &key,
        &conversation.id,
        "Recover this answer",
        1,
        rag::Focus::ThisThread,
        &provider,
        &mut |_event| Ok(()),
    )
    .expect("stream ask ai after partial claim");

    assert!(
        !result.user_message_id.trim().is_empty(),
        "stream persistence should repair incomplete detached claims"
    );
    assert!(
        !result.assistant_message_id.trim().is_empty(),
        "stream persistence should persist assistant message ids for partial claims"
    );

    let messages = db::list_messages(&conn, &key, &conversation.id).expect("list messages");
    assert_eq!(
        messages.len(),
        2,
        "partial claim should end with one user/assistant pair"
    );
    assert_eq!(messages[0].content, "Recover this answer");
    assert_eq!(
        messages[1].content,
        "Partial claims should still finish persistence."
    );
    assert_eq!(result.user_message_id, messages[0].id);
    assert_eq!(result.assistant_message_id, messages[1].id);
}

#[test]
fn detached_request_id_reuse_does_not_cross_conversation_boundaries() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    let first_conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation a");
    let second_conversation =
        db::create_conversation(&conn, &key, "Inbox 2").expect("conversation b");

    let first_provider = FakeProviderWithRequestId {
        request_id: CROSS_CONVERSATION_REQUEST_ID,
        answer: "First conversation answer.",
    };
    let first_result = rag::ask_ai_with_provider(
        &conn,
        &key,
        &first_conversation.id,
        "Question for conversation A",
        1,
        rag::Focus::ThisThread,
        &first_provider,
        &mut |_event| Ok(()),
    )
    .expect("stream ask ai for first conversation");

    let second_provider = FakeProviderWithRequestId {
        request_id: CROSS_CONVERSATION_REQUEST_ID,
        answer: "Second conversation answer.",
    };
    let second_result = rag::ask_ai_with_provider(
        &conn,
        &key,
        &second_conversation.id,
        "Question for conversation B",
        1,
        rag::Focus::ThisThread,
        &second_provider,
        &mut |_event| Ok(()),
    )
    .expect("stream ask ai for second conversation");

    let first_messages =
        db::list_messages(&conn, &key, &first_conversation.id).expect("list first messages");
    let second_messages =
        db::list_messages(&conn, &key, &second_conversation.id).expect("list second messages");

    assert_eq!(
        first_messages.len(),
        2,
        "first conversation should keep its own pair"
    );
    assert_eq!(
        second_messages.len(),
        2,
        "second conversation should persist its own pair"
    );
    assert_eq!(second_messages[0].content, "Question for conversation B");
    assert_eq!(second_messages[1].content, "Second conversation answer.");
    assert_eq!(second_result.user_message_id, second_messages[0].id);
    assert_eq!(second_result.assistant_message_id, second_messages[1].id);
    assert_ne!(second_result.user_message_id, first_result.user_message_id);
    assert_ne!(
        second_result.assistant_message_id,
        first_result.assistant_message_id
    );
}
