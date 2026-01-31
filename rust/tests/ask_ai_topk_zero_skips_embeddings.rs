use std::fs;

use secondloop_rust::crypto::KdfParams;
use secondloop_rust::embedding::PRODUCTION_MODEL_NAME;
use secondloop_rust::llm::ChatDelta;
use secondloop_rust::{auth, db, rag};

struct StubProvider;

impl rag::AnswerProvider for StubProvider {
    fn stream_answer(
        &self,
        _prompt: &str,
        on_event: &mut dyn FnMut(ChatDelta) -> anyhow::Result<()>,
    ) -> anyhow::Result<()> {
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

#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
#[test]
fn ask_ai_topk_zero_skips_embeddings_on_fastembed_failure() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    db::insert_message(&conn, &key, &conversation.id, "user", "hello").expect("insert message");

    db::set_active_embedding_model_name(&conn, PRODUCTION_MODEL_NAME).expect("set model");

    let dylib_name = if cfg!(target_os = "windows") {
        "onnxruntime.dll"
    } else if cfg!(target_os = "macos") {
        "libonnxruntime.dylib"
    } else if cfg!(target_os = "linux") {
        "libonnxruntime.so"
    } else {
        unreachable!("test only runs on desktop platforms");
    };

    let runtime_dir = app_dir.join("onnxruntime");
    fs::create_dir_all(&runtime_dir).expect("create runtime dir");
    fs::write(runtime_dir.join(dylib_name), b"not a real dylib").expect("write fake dylib");

    let provider = StubProvider;
    let mut on_event = |_ev: ChatDelta| Ok(());

    let result_with_rag = rag::ask_ai_with_provider_using_active_embeddings(
        &conn,
        &key,
        &app_dir,
        &conversation.id,
        "hello?",
        1,
        rag::Focus::AllMemories,
        &provider,
        &mut on_event,
    );
    assert!(
        result_with_rag.is_err(),
        "expected embeddings to fail; got {result_with_rag:?}"
    );

    let result_without_rag = rag::ask_ai_with_provider_using_active_embeddings(
        &conn,
        &key,
        &app_dir,
        &conversation.id,
        "hello?",
        0,
        rag::Focus::AllMemories,
        &provider,
        &mut on_event,
    );
    assert!(
        result_without_rag.is_ok(),
        "expected top_k=0 to skip embeddings; got {result_without_rag:?}"
    );
}
