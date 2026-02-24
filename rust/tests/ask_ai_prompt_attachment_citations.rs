use anyhow::Result;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::llm::ChatDelta;
use secondloop_rust::{auth, db, rag};

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
        *self.prompt.lock().unwrap() = Some(prompt.to_string());
        on_event(ChatDelta {
            role: Some("assistant".to_string()),
            text_delta: "ok".to_string(),
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
fn ask_ai_prompt_contains_attachment_citation_contract() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    let message = db::insert_message(&conn, &key, &conversation.id, "user", "see attachment")
        .expect("message");

    let attachment =
        db::insert_attachment(&conn, &key, &app_dir, b"report", "text/plain").expect("attachment");
    db::link_attachment_to_message(&conn, &key, &message.id, &attachment.sha256).expect("link");
    db::mark_attachment_annotation_ok(
        &conn,
        &key,
        &attachment.sha256,
        "en",
        "test-model",
        &serde_json::json!({
            "readable_text_full": "project delta status: all milestones are green"
        }),
        1_700_000_123_000,
    )
    .expect("annotation");

    let provider = CaptureProvider::default();
    rag::ask_ai_with_provider(
        &conn,
        &key,
        &conversation.id,
        "what does the attachment say?",
        4,
        rag::Focus::ThisThread,
        &provider,
        &mut |_ev| Ok(()),
    )
    .expect("ask");

    let prompt = provider.prompt.lock().unwrap().clone().expect("prompt");

    assert!(prompt.contains("Attachment citation contract (strict)"));
    assert!(prompt.contains("secondloop://attachment/<sha>"));
    assert!(prompt.contains("Resources catalog (attachments):"));
    assert!(prompt.contains("?kind=<kind>&chunk=<i>"));
}
