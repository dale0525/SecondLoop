use secondloop_rust::api::core;

#[test]
fn api_core_smoke_happy_path() {
    let temp_dir = tempfile::tempdir().expect("tempdir");
    let app_dir = temp_dir.path().join("secondloop");
    let app_dir = app_dir.to_string_lossy().to_string();

    assert!(!core::auth_is_initialized(app_dir.clone()));

    let key = core::auth_init_master_password(app_dir.clone(), "pw".to_string())
        .expect("init master password");
    assert_eq!(key.len(), 32);

    let key2 = core::auth_unlock_with_password(app_dir.clone(), "pw".to_string())
        .expect("unlock");
    assert_eq!(key, key2);

    let conversation = core::db_create_conversation(app_dir.clone(), key.clone(), "Inbox".to_string())
        .expect("create conversation");
    let _message = core::db_insert_message(
        app_dir.clone(),
        key.clone(),
        conversation.id.clone(),
        "user".to_string(),
        "hello".to_string(),
    )
    .expect("insert message");

    let processed = core::db_process_pending_message_embeddings(app_dir.clone(), key.clone(), 100)
        .expect("process embeddings");
    assert_eq!(processed, 1);

    let similar =
        core::db_search_similar_messages(app_dir.clone(), key.clone(), "hello".to_string(), 3)
            .expect("search");
    assert_eq!(similar.len(), 1);
    assert_eq!(similar[0].message.content, "hello");

    let rebuilt = core::db_rebuild_message_embeddings(app_dir.clone(), key.clone(), 100)
        .expect("rebuild");
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
