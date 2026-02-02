use anyhow::Result;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::llm::ChatDelta;
use secondloop_rust::{auth, db, embedding, rag};

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

fn prompt_memories_section(prompt: &str) -> &str {
    let start = prompt
        .find("Relevant memories (quoted):")
        .expect("memories section start");
    let rest = &prompt[start..];
    let end = rest
        .find("\nAnswer the user's question.")
        .unwrap_or(rest.len());
    &rest[..end]
}

#[test]
fn rag_v2_compress_excludes_low_score_sentence() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    db::set_active_embedding_model_name(&conn, embedding::DEFAULT_MODEL_NAME).expect("model");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");

    let text = concat!(
        "Phoenix meeting notes: shipped v2.\n",
        "Phoenix action items: follow up with Alice.\n",
        "UNIQUE_TOKEN_SHOULD_NOT_APPEAR.\n"
    );
    db::insert_message(&conn, &key, &conversation.id, "user", text).expect("seed");

    let provider = FakeProvider::default();
    rag::ask_ai_with_provider_using_active_embeddings(
        &conn,
        &key,
        &app_dir,
        &conversation.id,
        "phoenix",
        3,
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
    let memories = prompt_memories_section(&prompt);
    assert!(memories.contains("Phoenix meeting notes"));
    assert!(!memories.contains("UNIQUE_TOKEN_SHOULD_NOT_APPEAR"));
}

#[test]
fn rag_v2_mmr_promotes_diverse_contexts() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    db::set_active_embedding_model_name(&conn, embedding::DEFAULT_MODEL_NAME).expect("model");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");

    for i in 0..8 {
        db::insert_message(
            &conn,
            &key,
            &conversation.id,
            "user",
            &format!("alpha beta CLUSTER_A_{i}"),
        )
        .expect("seed a");
    }
    for i in 0..3 {
        db::insert_message(
            &conn,
            &key,
            &conversation.id,
            "user",
            &format!("beta gamma CLUSTER_B_{i}"),
        )
        .expect("seed b");
    }

    let provider = FakeProvider::default();
    rag::ask_ai_with_provider_using_active_embeddings(
        &conn,
        &key,
        &app_dir,
        &conversation.id,
        "alpha beta",
        3,
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
    let memories = prompt_memories_section(&prompt);
    assert!(memories.contains("CLUSTER_B_"));
}

#[test]
fn rag_v2_respects_context_char_budget() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    db::set_active_embedding_model_name(&conn, embedding::DEFAULT_MODEL_NAME).expect("model");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");

    let long = "x".repeat(3500);
    db::insert_message(
        &conn,
        &key,
        &conversation.id,
        "user",
        &format!("CTX1_UNIQUE {long} alpha beta"),
    )
    .expect("seed 1");
    db::insert_message(
        &conn,
        &key,
        &conversation.id,
        "user",
        &format!("CTX2_UNIQUE {long} alpha"),
    )
    .expect("seed 2");

    let provider = FakeProvider::default();
    rag::ask_ai_with_provider_using_active_embeddings(
        &conn,
        &key,
        &app_dir,
        &conversation.id,
        "alpha beta",
        2,
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
    let memories = prompt_memories_section(&prompt);
    assert!(memories.contains("CTX1_UNIQUE"));
    assert!(!memories.contains("CTX2_UNIQUE"));
}
