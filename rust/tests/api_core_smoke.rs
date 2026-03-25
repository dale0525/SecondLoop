use secondloop_rust::api::core;
use secondloop_rust::{db, embedding};

#[test]
fn api_core_smoke_happy_path() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    let app_dir = app_dir.to_string_lossy().to_string();

    assert!(!core::auth_is_initialized(app_dir.clone()));

    let key = core::auth_init_master_password(app_dir.clone(), "pw".to_string())
        .expect("init master password");
    assert_eq!(key.len(), 32);

    let key2 = core::auth_unlock_with_password(app_dir.clone(), "pw".to_string()).expect("unlock");
    assert_eq!(key, key2);

    let conversation =
        core::db_create_conversation(app_dir.clone(), key.clone(), "Inbox".to_string())
            .expect("create conversation");
    let _message = core::db_insert_message(
        app_dir.clone(),
        key.clone(),
        conversation.id.clone(),
        "user".to_string(),
        "hello".to_string(),
    )
    .expect("insert message");

    let conn = db::open(std::path::Path::new(&app_dir)).expect("open db");
    db::set_active_embedding_model_name(&conn, embedding::DEFAULT_MODEL_NAME)
        .expect("set embedding model");

    let processed = core::db_process_pending_message_embeddings(app_dir.clone(), key.clone(), 100)
        .expect("process embeddings");
    assert_eq!(processed, 1);

    let similar =
        core::db_search_similar_messages(app_dir.clone(), key.clone(), "hello".to_string(), 3)
            .expect("search");
    assert_eq!(similar.len(), 1);
    assert_eq!(similar[0].message.content, "hello");

    let rebuilt =
        core::db_rebuild_message_embeddings(app_dir.clone(), key.clone(), 100).expect("rebuild");
    assert_eq!(rebuilt, 1);

    let similar_after =
        core::db_search_similar_messages(app_dir.clone(), key.clone(), "hello".to_string(), 3)
            .expect("search");
    assert_eq!(similar_after.len(), 1);
    assert_eq!(similar_after[0].message.content, "hello");

    let messages = core::db_list_messages(app_dir.clone(), key.clone(), conversation.id)
        .expect("list messages");
    assert_eq!(messages.len(), 1);
    assert_eq!(messages[0].content, "hello");
}

#[test]
fn api_core_llm_profiles_smoke() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    let app_dir = app_dir.to_string_lossy().to_string();

    let key = core::auth_init_master_password(app_dir.clone(), "pw".to_string())
        .expect("init master password");

    let p1 = core::db_create_llm_profile(
        app_dir.clone(),
        key.clone(),
        "P1".to_string(),
        "openai-compatible".to_string(),
        Some("https://example.com/v1".to_string()),
        Some("sk-p1".to_string()),
        "gpt-4o-mini".to_string(),
        true,
    )
    .expect("create p1");
    assert!(p1.is_active);

    let p2 = core::db_create_llm_profile(
        app_dir.clone(),
        key.clone(),
        "P2".to_string(),
        "openai-compatible".to_string(),
        Some("https://example.com/v1".to_string()),
        Some("sk-p2".to_string()),
        "gpt-4o-mini".to_string(),
        false,
    )
    .expect("create p2");
    assert!(!p2.is_active);

    let profiles = core::db_list_llm_profiles(app_dir.clone(), key.clone()).expect("list");
    assert_eq!(profiles.len(), 2);

    core::db_set_active_llm_profile(app_dir.clone(), key.clone(), p2.id.clone()).expect("activate");

    let profiles2 = core::db_list_llm_profiles(app_dir.clone(), key.clone()).expect("list2");
    assert!(profiles2.iter().any(|p| p.id == p1.id && !p.is_active));
    assert!(profiles2.iter().any(|p| p.id == p2.id && p.is_active));
}

#[test]
fn api_core_dismiss_followup_suggestions_requires_todo_access() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    let app_dir = app_dir.to_string_lossy().to_string();

    let key = core::auth_init_master_password(app_dir.clone(), "pw".to_string())
        .expect("init master password");
    let wrong_key = vec![9u8; 32];

    let conn = db::open(std::path::Path::new(&app_dir)).expect("open db");
    db::upsert_todo(
        &conn,
        &key.clone().try_into().expect("key bytes"),
        "todo_1",
        "Research LLM models",
        None,
        "open",
        None,
        None,
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    let generated = db::upsert_generated_todo_followup_suggestions(
        &conn,
        &key.clone().try_into().expect("key bytes"),
        "todo_1",
        &[db::TodoFollowupSuggestionDraftInput {
            content: "## Summary\nClaude / GPT / Gemini are still the main hosted options."
                .to_string(),
            generation_mode: "model_knowledge".to_string(),
            citations_json: None,
        }],
        "cloud",
        Some("gen_1"),
    )
    .expect("generate followup suggestion");

    core::db_dismiss_todo_followup_suggestions(
        app_dir.clone(),
        wrong_key,
        "todo_1".to_string(),
        vec![generated[0].id.clone()],
    )
    .expect_err("wrong key should not dismiss followup suggestion");

    let suggestions = core::db_list_todo_followup_suggestions(app_dir, key, "todo_1".to_string())
        .expect("list followup suggestions");
    assert_eq!(suggestions.len(), 1);
    assert_eq!(suggestions[0].state, "pending");
}

#[test]
fn api_core_dismiss_all_followup_suggestions_requires_todo_access() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    let app_dir = app_dir.to_string_lossy().to_string();

    let key = core::auth_init_master_password(app_dir.clone(), "pw".to_string())
        .expect("init master password");
    let wrong_key = vec![9u8; 32];

    let conn = db::open(std::path::Path::new(&app_dir)).expect("open db");
    db::upsert_todo(
        &conn,
        &key.clone().try_into().expect("key bytes"),
        "todo_1",
        "Research LLM models",
        None,
        "open",
        None,
        None,
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    db::upsert_generated_todo_followup_suggestions(
        &conn,
        &key.clone().try_into().expect("key bytes"),
        "todo_1",
        &[db::TodoFollowupSuggestionDraftInput {
            content: "## Summary\nClaude / GPT / Gemini are still the main hosted options."
                .to_string(),
            generation_mode: "model_knowledge".to_string(),
            citations_json: None,
        }],
        "cloud",
        Some("gen_1"),
    )
    .expect("generate followup suggestion");

    core::db_dismiss_all_todo_followup_suggestions(
        app_dir.clone(),
        wrong_key,
        "todo_1".to_string(),
    )
    .expect_err("wrong key should not dismiss all followup suggestions");

    let suggestions = core::db_list_todo_followup_suggestions(app_dir, key, "todo_1".to_string())
        .expect("list followup suggestions");
    assert_eq!(suggestions.len(), 1);
    assert_eq!(suggestions[0].state, "pending");
}

#[test]
fn api_core_list_followup_suggestions_requires_todo_access() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    let app_dir = app_dir.to_string_lossy().to_string();

    let key = core::auth_init_master_password(app_dir.clone(), "pw".to_string())
        .expect("init master password");
    let wrong_key = vec![9u8; 32];

    let conn = db::open(std::path::Path::new(&app_dir)).expect("open db");
    db::upsert_todo(
        &conn,
        &key.clone().try_into().expect("key bytes"),
        "todo_1",
        "Research LLM models",
        None,
        "open",
        None,
        None,
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    core::db_list_todo_followup_suggestions(app_dir, wrong_key, "todo_1".to_string())
        .expect_err("wrong key should not list followup suggestions");
}

#[test]
fn api_core_upsert_generated_followup_suggestions_requires_todo_access() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    let app_dir = app_dir.to_string_lossy().to_string();

    let key = core::auth_init_master_password(app_dir.clone(), "pw".to_string())
        .expect("init master password");
    let wrong_key = vec![9u8; 32];

    let conn = db::open(std::path::Path::new(&app_dir)).expect("open db");
    db::upsert_todo(
        &conn,
        &key.clone().try_into().expect("key bytes"),
        "todo_1",
        "Research LLM models",
        None,
        "open",
        None,
        None,
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    core::db_upsert_generated_todo_followup_suggestions(
        app_dir.clone(),
        wrong_key,
        "todo_1".to_string(),
        vec![db::TodoFollowupSuggestionDraftInput {
            content: "## Summary\nClaude / GPT / Gemini are still the main hosted options."
                .to_string(),
            generation_mode: "model_knowledge".to_string(),
            citations_json: None,
        }],
        "cloud".to_string(),
        Some("gen_1".to_string()),
    )
    .expect_err("wrong key should not upsert followup suggestions");

    let suggestions = core::db_list_todo_followup_suggestions(app_dir, key, "todo_1".to_string())
        .expect("list followup suggestions");
    assert!(suggestions.is_empty());
}

#[test]
fn api_core_apply_followup_suggestions_requires_todo_access() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    let app_dir = app_dir.to_string_lossy().to_string();

    let key = core::auth_init_master_password(app_dir.clone(), "pw".to_string())
        .expect("init master password");
    let wrong_key = vec![9u8; 32];

    let conn = db::open(std::path::Path::new(&app_dir)).expect("open db");
    db::upsert_todo(
        &conn,
        &key.clone().try_into().expect("key bytes"),
        "todo_1",
        "Research LLM models",
        None,
        "open",
        None,
        None,
        None,
        None,
        None,
        None,
    )
    .expect("upsert todo");

    let generated = db::upsert_generated_todo_followup_suggestions(
        &conn,
        &key.clone().try_into().expect("key bytes"),
        "todo_1",
        &[db::TodoFollowupSuggestionDraftInput {
            content: "## Summary\nClaude / GPT / Gemini are still the main hosted options."
                .to_string(),
            generation_mode: "model_knowledge".to_string(),
            citations_json: None,
        }],
        "cloud",
        Some("gen_1"),
    )
    .expect("generate followup suggestion");

    core::db_apply_todo_followup_suggestions(
        app_dir.clone(),
        wrong_key,
        "todo_1".to_string(),
        vec![generated[0].id.clone()],
    )
    .expect_err("wrong key should not apply followup suggestion");

    let suggestions = core::db_list_todo_followup_suggestions(app_dir, key, "todo_1".to_string())
        .expect("list followup suggestions");
    assert_eq!(suggestions.len(), 1);
    assert_eq!(suggestions[0].state, "pending");
}
