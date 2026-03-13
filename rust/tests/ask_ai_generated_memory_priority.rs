use anyhow::Result;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::llm::ChatDelta;
use secondloop_rust::{auth, db, knowledge, rag};

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
        *self.last_prompt.lock().expect("lock prompt") = Some(prompt.to_string());
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
fn ask_ai_prefers_generated_preference_memory_for_style_questions() {
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
        "Please answer in Chinese and keep responses short and practical.",
    )
    .expect("preference");
    db::insert_message(
        &conn,
        &key,
        &conversation.id,
        "user",
        "Budget freeze decision: freeze-signal budget decision. Follow up with Alice on Monday.",
    )
    .expect("evidence");

    knowledge::ensure_knowledge_rebuild_requested(&conn).expect("request rebuild");
    knowledge::process_pending_knowledge_index_jobs_active(&conn, &key, 256).expect("process jobs");

    let provider = FakeProvider::default();
    rag::ask_ai_with_provider_using_active_embeddings(
        &conn,
        &key,
        &app_dir,
        &conversation.id,
        "Plan my week in my usual style around the budget freeze.",
        6,
        rag::Focus::ThisThread,
        &provider,
        &mut |_event| Ok(()),
    )
    .expect("ask ai");

    let prompt = provider
        .last_prompt
        .lock()
        .expect("lock prompt")
        .clone()
        .expect("prompt");
    let memories = prompt_memories_section(&prompt);
    let digest_index = memories
        .to_lowercase()
        .find("session digest")
        .expect("session digest in prompt");
    let evidence_index = memories
        .find("source=raw_text role=body")
        .expect("raw source block in prompt");

    assert!(memories.contains("User prefers responses in Chinese"));
    assert!(evidence_index > digest_index);
}
