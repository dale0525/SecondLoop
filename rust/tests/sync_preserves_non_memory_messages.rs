use anyhow::Result;

use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::llm::ChatDelta;
use secondloop_rust::rag;
use secondloop_rust::sync;

struct OkProvider;

impl rag::AnswerProvider for OkProvider {
    fn stream_answer(
        &self,
        _prompt: &str,
        on_event: &mut dyn FnMut(ChatDelta) -> Result<()>,
    ) -> Result<()> {
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
fn sync_preserves_non_memory_messages() {
    let remote = sync::InMemoryRemoteStore::new();
    let remote_root = "SecondLoopTest";

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");
    let conversation =
        db::get_or_create_main_stream_conversation(&conn_a, &key_a).expect("main stream");

    let provider = OkProvider;
    let ask = rag::ask_ai_with_provider(
        &conn_a,
        &key_a,
        &conversation.id,
        "question",
        3,
        rag::Focus::AllMemories,
        &provider,
        &mut |_ev| Ok(()),
    )
    .expect("ask");

    sync::push(&conn_a, &key_a, &sync_key, &remote, remote_root).expect("push A");

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    sync::pull(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("pull B");

    let (user_is_memory, user_needs_embedding): (i64, i64) = conn_b
        .query_row(
            r#"SELECT COALESCE(is_memory, 1), COALESCE(needs_embedding, 1)
               FROM messages
               WHERE id = ?1"#,
            [ask.user_message_id.as_str()],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("user flags");
    assert_eq!(user_is_memory, 0);
    assert_eq!(user_needs_embedding, 0);

    let (assistant_is_memory, assistant_needs_embedding): (i64, i64) = conn_b
        .query_row(
            r#"SELECT COALESCE(is_memory, 1), COALESCE(needs_embedding, 1)
               FROM messages
               WHERE id = ?1"#,
            [ask.assistant_message_id.as_str()],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("assistant flags");
    assert_eq!(assistant_is_memory, 0);
    assert_eq!(assistant_needs_embedding, 0);

    let pending: i64 = conn_b
        .query_row(
            "SELECT COUNT(*) FROM messages WHERE COALESCE(needs_embedding, 1) = 1",
            [],
            |row| row.get(0),
        )
        .expect("pending count");
    assert_eq!(pending, 0);
}

