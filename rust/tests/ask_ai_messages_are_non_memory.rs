use anyhow::Result;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::llm::ChatDelta;
use secondloop_rust::rag::{self, AnswerProvider, Focus};
use secondloop_rust::{auth, db};

struct FakeProvider;

impl AnswerProvider for FakeProvider {
    fn stream_answer(
        &self,
        _prompt: &str,
        on_event: &mut dyn FnMut(ChatDelta) -> Result<()>,
    ) -> Result<()> {
        on_event(ChatDelta {
            role: Some("assistant".to_string()),
            text_delta: "hello".to_string(),
            done: false,
        })?;
        on_event(ChatDelta {
            role: Some("assistant".to_string()),
            text_delta: "".to_string(),
            done: true,
        })?;
        Ok(())
    }
}

#[test]
fn ask_ai_inserts_non_memory_messages() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    db::insert_message(
        &conn,
        &key,
        &conversation.id,
        "user",
        "老婆 3 月 1 号回台湾",
    )
    .expect("memory message");

    let provider = FakeProvider;
    let mut on_event = |_ev: ChatDelta| Ok(());
    let result = rag::ask_ai_with_provider(
        &conn,
        &key,
        &conversation.id,
        "老婆什么时候回台湾？",
        3,
        Focus::AllMemories,
        &provider,
        &mut on_event,
    )
    .expect("ask ai");

    let (user_is_memory, user_needs_embedding): (i64, i64) = conn
        .query_row(
            r#"SELECT COALESCE(is_memory, 1), COALESCE(needs_embedding, 1)
               FROM messages
               WHERE id = ?1"#,
            [result.user_message_id.as_str()],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("user flags");
    assert_eq!(user_is_memory, 0);
    assert_eq!(user_needs_embedding, 0);

    let (assistant_is_memory, assistant_needs_embedding): (i64, i64) = conn
        .query_row(
            r#"SELECT COALESCE(is_memory, 1), COALESCE(needs_embedding, 1)
               FROM messages
               WHERE id = ?1"#,
            [result.assistant_message_id.as_str()],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("assistant flags");
    assert_eq!(assistant_is_memory, 0);
    assert_eq!(assistant_needs_embedding, 0);

    let pending: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM messages WHERE COALESCE(needs_embedding, 1) = 1",
            [],
            |row| row.get(0),
        )
        .expect("pending count");
    assert_eq!(pending, 0);
}
