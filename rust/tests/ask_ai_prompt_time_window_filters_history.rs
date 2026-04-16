use anyhow::Result;
use rusqlite::params;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::embedding;
use secondloop_rust::llm::ChatDelta;
use secondloop_rust::{auth, db, rag};
use std::fs;
use std::path::{Path, PathBuf};

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

fn write_text(path: &Path, text: &str) {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).expect("create parent");
    }
    fs::write(path, text).expect("write text");
}

fn create_external_markdown_source(root: &Path) -> PathBuf {
    let source = root.join("markdown-library");
    write_text(
        &source.join("travel/old-plan.md"),
        "# Old Travel Plan\n\nThe stale budget cap was 1000.\n",
    );
    write_text(
        &source.join("travel/today-plan.md"),
        "# Today Travel Plan\n\nThe current budget cap is 600.\n",
    );
    source
}

#[test]
fn ask_ai_time_window_prompt_filters_conversation_history_by_range() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    db::set_active_embedding_model_name(&conn, embedding::DEFAULT_MODEL_NAME).expect("model");
    db::set_active_embedding_model_name(&conn, embedding::DEFAULT_MODEL_NAME).expect("model");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    let attachment = db::insert_attachment(&conn, &key, &app_dir, b"window resource", "text/plain")
        .expect("attachment");

    // Set up a time window (like "today").
    let time_start_ms: i64 = 1_000_000;
    let time_end_ms: i64 = time_start_ms + 86_400_000;

    // Seed an "old" message that should NOT be included.
    let old_user = db::insert_message(&conn, &key, &conversation.id, "user", "HISTORY_OLD_USER")
        .expect("old user");
    conn.execute(
        "UPDATE messages SET created_at = ?2, updated_at = ?2 WHERE id = ?1",
        params![old_user.id, time_start_ms - 7 * 86_400_000],
    )
    .expect("update old user ts");

    let old_assistant = db::insert_message(
        &conn,
        &key,
        &conversation.id,
        "assistant",
        "HISTORY_OLD_ASSISTANT",
    )
    .expect("old assistant");
    conn.execute(
        "UPDATE messages SET created_at = ?2, updated_at = ?2 WHERE id = ?1",
        params![old_assistant.id, time_start_ms - 7 * 86_400_000 + 1],
    )
    .expect("update old assistant ts");

    // Seed an "in range" message that SHOULD be included.
    let new_user = db::insert_message(
        &conn,
        &key,
        &conversation.id,
        "user",
        "HISTORY_IN_RANGE_USER",
    )
    .expect("new user");
    conn.execute(
        "UPDATE messages SET created_at = ?2, updated_at = ?2 WHERE id = ?1",
        params![new_user.id, time_start_ms + 1],
    )
    .expect("update new user ts");

    let provider = FakeProvider::default();
    rag::ask_ai_with_provider_using_active_embeddings_time_window(
        &conn,
        &key,
        &app_dir,
        &conversation.id,
        "今天有哪些事要做？",
        0,
        rag::Focus::ThisThread,
        time_start_ms,
        time_end_ms,
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

    assert!(
        prompt.contains("HISTORY_IN_RANGE_USER"),
        "expected in-range history missing: {prompt}"
    );
    assert!(
        !prompt.contains("HISTORY_OLD_USER"),
        "expected old history to be filtered out: {prompt}"
    );
    assert!(
        !prompt.contains("HISTORY_OLD_ASSISTANT"),
        "expected old history to be filtered out: {prompt}"
    );
    assert!(
        !prompt.contains("Resources catalog (attachments):"),
        "expected unrelated recent attachments to stay out of prompt: {prompt}"
    );
    assert!(
        !prompt.contains(&format!("secondloop://attachment/{}", attachment.sha256)),
        "expected unrelated attachment deep link to stay out of prompt: {prompt}"
    );
}

#[test]
fn ask_ai_time_window_prompt_includes_attachments_linked_inside_range() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    db::set_active_embedding_model_name(&conn, embedding::DEFAULT_MODEL_NAME).expect("model");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");

    let time_start_ms: i64 = 2_000_000;
    let time_end_ms: i64 = time_start_ms + 86_400_000;

    let in_range_message = db::insert_message(
        &conn,
        &key,
        &conversation.id,
        "user",
        "Please summarize the launch brief attachment.",
    )
    .expect("in range message");
    conn.execute(
        "UPDATE messages SET created_at = ?2, updated_at = ?2 WHERE id = ?1",
        params![in_range_message.id, time_start_ms + 10],
    )
    .expect("update in range message ts");

    let attachment = db::insert_attachment(&conn, &key, &app_dir, b"launch brief", "text/plain")
        .expect("attachment");
    db::link_attachment_to_message(&conn, &key, &in_range_message.id, &attachment.sha256)
        .expect("link attachment");
    db::upsert_attachment_metadata(
        &conn,
        &key,
        &attachment.sha256,
        Some("Launch brief"),
        &["launch-brief.txt".to_string()],
        &[],
    )
    .expect("metadata");

    let unrelated = db::insert_attachment(&conn, &key, &app_dir, b"unrelated", "text/plain")
        .expect("unrelated attachment");
    db::upsert_attachment_metadata(
        &conn,
        &key,
        &unrelated.sha256,
        Some("Unrelated note"),
        &["unrelated.txt".to_string()],
        &[],
    )
    .expect("unrelated metadata");

    let provider = FakeProvider::default();
    rag::ask_ai_with_provider_using_active_embeddings_time_window(
        &conn,
        &key,
        &app_dir,
        &conversation.id,
        "今天这个时间范围里的附件讲了什么？",
        4,
        rag::Focus::ThisThread,
        time_start_ms,
        time_end_ms,
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

    assert!(
        prompt.contains("Resources catalog (attachments):"),
        "expected attachment catalog in prompt: {prompt}"
    );
    assert!(
        prompt.contains(&format!("secondloop://attachment/{}", attachment.sha256)),
        "expected in-range attachment deep link in prompt: {prompt}"
    );
    assert!(
        !prompt.contains(&format!("secondloop://attachment/{}", unrelated.sha256)),
        "expected unrelated attachment to stay out of prompt: {prompt}"
    );
}

#[test]
fn ask_ai_time_window_prompt_keeps_latest_in_range_attachment_when_window_is_large() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    db::set_active_embedding_model_name(&conn, embedding::DEFAULT_MODEL_NAME).expect("model");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    let time_start_ms: i64 = 3_000_000;
    let time_end_ms: i64 = time_start_ms + 86_400_000;

    for index in 0..805 {
        let message = db::insert_message(
            &conn,
            &key,
            &conversation.id,
            "user",
            &format!("Window message {index}"),
        )
        .expect("message");
        conn.execute(
            "UPDATE messages SET created_at = ?2, updated_at = ?2 WHERE id = ?1",
            rusqlite::params![message.id, time_start_ms + index as i64],
        )
        .expect("update message ts");
    }

    let latest_message = db::insert_message(
        &conn,
        &key,
        &conversation.id,
        "user",
        "Please inspect the latest in-range attachment.",
    )
    .expect("latest message");
    conn.execute(
        "UPDATE messages SET created_at = ?2, updated_at = ?2 WHERE id = ?1",
        rusqlite::params![latest_message.id, time_end_ms - 10],
    )
    .expect("update latest message ts");

    let latest_attachment =
        db::insert_attachment(&conn, &key, &app_dir, b"latest attachment", "text/plain")
            .expect("latest attachment");
    db::link_attachment_to_message(&conn, &key, &latest_message.id, &latest_attachment.sha256)
        .expect("link latest attachment");
    db::upsert_attachment_metadata(
        &conn,
        &key,
        &latest_attachment.sha256,
        Some("Latest in-range attachment"),
        &["latest.txt".to_string()],
        &[],
    )
    .expect("latest metadata");

    let provider = FakeProvider::default();
    rag::ask_ai_with_provider_using_active_embeddings_time_window(
        &conn,
        &key,
        &app_dir,
        &conversation.id,
        "今天这个时间范围里的附件讲了什么？",
        4,
        rag::Focus::ThisThread,
        time_start_ms,
        time_end_ms,
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

    assert!(
        prompt.contains(&format!(
            "secondloop://attachment/{}",
            latest_attachment.sha256
        )),
        "latest in-range attachment should stay in prompt even with many older window messages: {prompt}"
    );
}

#[test]
fn ask_ai_time_window_persists_attachment_evidence_for_catalog_resources() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    let time_start_ms: i64 = 4_000_000;
    let time_end_ms: i64 = time_start_ms + 86_400_000;

    let in_range_message = db::insert_message(
        &conn,
        &key,
        &conversation.id,
        "user",
        "Please inspect the launch brief attachment.",
    )
    .expect("in range message");
    conn.execute(
        "UPDATE messages SET created_at = ?2, updated_at = ?2 WHERE id = ?1",
        params![in_range_message.id, time_start_ms + 10],
    )
    .expect("update in range message ts");

    let attachment = db::insert_attachment(&conn, &key, &app_dir, b"launch brief", "text/plain")
        .expect("attachment");
    db::link_attachment_to_message(&conn, &key, &in_range_message.id, &attachment.sha256)
        .expect("link attachment");
    db::upsert_attachment_metadata(
        &conn,
        &key,
        &attachment.sha256,
        Some("Launch brief"),
        &["launch-brief.txt".to_string()],
        &[],
    )
    .expect("metadata");

    let provider = FakeProvider::default();
    rag::ask_ai_with_provider_using_active_embeddings_time_window(
        &conn,
        &key,
        &app_dir,
        &conversation.id,
        "今天这个时间范围里的附件讲了什么？",
        0,
        rag::Focus::ThisThread,
        time_start_ms,
        time_end_ms,
        &provider,
        &mut |_ev| Ok(()),
    )
    .expect("ask");

    let messages = db::list_messages(&conn, &key, &conversation.id).expect("list messages");
    let assistant = messages.last().expect("assistant message");
    let raw = assistant
        .citations_json
        .as_deref()
        .expect("citations json should be stored");
    let value: serde_json::Value = serde_json::from_str(raw).expect("valid json");
    let direct_sources = value["direct_sources"]
        .as_array()
        .expect("direct_sources array");
    assert!(
        direct_sources.iter().any(|source| {
            source["href"].as_str()
                == Some(&format!("secondloop://attachment/{}", attachment.sha256))
        }),
        "expected time-window attachment catalog resource in citations json: {value}"
    );
}

#[test]
fn ask_ai_time_window_prompt_filters_external_documents_by_range() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    let source = create_external_markdown_source(temp_dir.path());

    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    db::set_active_embedding_model_name(&conn, embedding::DEFAULT_MODEL_NAME).expect("model");

    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("conversation");
    db::run_external_import_with_callbacks(&app_dir, &key, &source, &mut |_| {}, &|| false)
        .expect("import external docs");

    let external = db::open_external_readonly_db(&app_dir).expect("open external db");
    external
        .execute(
            "UPDATE external_documents SET created_at_ms = ?2 WHERE source_rel_path = ?1",
            params!["travel/old-plan.md", 1_000_i64],
        )
        .expect("update old document ts");
    external
        .execute(
            "UPDATE external_documents SET created_at_ms = ?2 WHERE source_rel_path = ?1",
            params!["travel/today-plan.md", 2_000_010_i64],
        )
        .expect("update in-range document ts");

    let time_start_ms: i64 = 2_000_000;
    let time_end_ms: i64 = time_start_ms + 86_400_000;

    let provider = FakeProvider::default();
    rag::ask_ai_with_provider_using_active_embeddings_time_window(
        &conn,
        &key,
        &app_dir,
        &conversation.id,
        "Where is the current budget cap documented?",
        4,
        rag::Focus::AllMemories,
        time_start_ms,
        time_end_ms,
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

    assert!(
        prompt.contains("current budget cap is 600"),
        "expected in-range external document in prompt: {prompt}"
    );
    assert!(
        !prompt.contains("stale budget cap was 1000"),
        "expected out-of-range external document to stay out of prompt: {prompt}"
    );
}
