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
fn ask_ai_resources_catalog_is_capped_to_twenty_items() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");

    for idx in 0..26 {
        let body = format!("attachment-{idx}");
        let attachment =
            db::insert_attachment(&conn, &key, &app_dir, body.as_bytes(), "text/plain")
                .expect("insert attachment");

        db::mark_attachment_annotation_ok(
            &conn,
            &key,
            &attachment.sha256,
            "en",
            "test-model",
            &serde_json::json!({
                "readable_text_full": format!("evidence text for attachment {idx}")
            }),
            1_700_000_000_000 + i64::from(idx),
        )
        .expect("annotation");
    }

    let provider = CaptureProvider::default();
    rag::ask_ai_with_provider(
        &conn,
        &key,
        &conversation.id,
        "show attachment resources",
        6,
        rag::Focus::AllMemories,
        &provider,
        &mut |_ev| Ok(()),
    )
    .expect("ask");

    let prompt = provider.prompt.lock().unwrap().clone().expect("prompt");

    let resource_lines = prompt
        .lines()
        .filter(|line| {
            line.trim().starts_with("- [")
                && line.contains("secondloop://attachment/")
                && !line.contains("?kind=")
        })
        .count();

    assert!(resource_lines > 0);
    assert!(resource_lines <= 20);
}
