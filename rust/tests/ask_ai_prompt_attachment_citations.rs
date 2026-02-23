use anyhow::Result;
use secondloop_rust::auth;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::llm::ChatDelta;
use secondloop_rust::{db, embedding, rag};

#[derive(Default)]
struct CaptureProvider {
    prompt: std::sync::Mutex<Option<String>>,
}

impl rag::AnswerProvider for CaptureProvider {
    fn stream_answer(
        &self,
        prompt: &str,
        on_event: &mut dyn FnMut(ChatDelta) -> Result<()>,
    ) -> Result<()> {
        *self.prompt.lock().expect("lock") = Some(prompt.to_string());
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
fn ask_ai_prompt_includes_attachment_resources_and_strict_citation_contract() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    db::set_active_embedding_model_name(&conn, embedding::DEFAULT_MODEL_NAME).expect("set model");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    let message = db::insert_message(&conn, &key, &conversation.id, "user", "status update")
        .expect("seed message");

    let attachment = db::insert_attachment(&conn, &key, &app_dir, b"pdf", "application/pdf")
        .expect("attachment");
    db::link_attachment_to_message(&conn, &key, &message.id, &attachment.sha256)
        .expect("link attachment");

    let payload = serde_json::json!({
        "mime_type": "application/pdf",
        "extracted_text_full": "Roadmap milestone Alpha has two blockers: flaky CI and missing API docs.",
    });
    db::mark_attachment_annotation_ok(
        &conn,
        &key,
        &attachment.sha256,
        "und",
        "document_extract.v1",
        &payload,
        message.created_at_ms,
    )
    .expect("mark annotation ok");

    db::process_attachment_chunk_index_default(&conn, &key, 32).expect("index chunks");
    db::process_pending_attachment_chunk_embeddings_default(&conn, &key, 64)
        .expect("index embeddings");

    let provider = CaptureProvider::default();
    rag::ask_ai_with_provider_using_active_embeddings(
        &conn,
        &key,
        &app_dir,
        &conversation.id,
        "What are the blockers in the roadmap milestone?",
        5,
        rag::Focus::AllMemories,
        &provider,
        &mut |_ev| Ok(()),
    )
    .expect("ask");

    let prompt = provider
        .prompt
        .lock()
        .expect("lock")
        .clone()
        .expect("prompt");

    let file_link = format!("secondloop://attachment/{}", attachment.sha256);
    assert!(
        prompt.contains(&file_link),
        "expected resources catalog link in prompt, got: {prompt}"
    );
    assert!(
        prompt.contains("?kind=extracted_text_full&chunk=0"),
        "expected chunk citation link in prompt, got: {prompt}"
    );
    assert!(
        prompt.contains(
            "Every paragraph that uses attachment evidence must include at least one citation"
        ),
        "expected strict citation contract in prompt, got: {prompt}"
    );
}
