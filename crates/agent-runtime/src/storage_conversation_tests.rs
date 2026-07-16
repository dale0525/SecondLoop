use super::*;
use crate::session::messages_to_model_history;
use crate::tools::ToolPersistence;

#[tokio::test]
async fn conversation_scope_isolates_apps_users_and_devices() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let scope_a = ConversationScope::local("com.example.app-a");
    let mut scope_b = ConversationScope::local("com.example.app-b");
    scope_b.user_id = "other-user".into();
    scope_b.device_id = "other-device".into();
    let session = storage
        .create_scoped_session(&scope_a, "Scoped")
        .await
        .unwrap();
    storage
        .append_scoped_turn(&scope_a, &session.id, "hello", "hi")
        .await
        .unwrap();

    assert!(
        storage
            .session_exists_scoped(&scope_a, &session.id)
            .await
            .unwrap()
    );
    assert!(
        !storage
            .session_exists_scoped(&scope_b, &session.id)
            .await
            .unwrap()
    );
    assert!(
        storage
            .list_scoped_messages(&scope_b, &session.id)
            .await
            .unwrap()
            .is_empty()
    );
    assert!(
        storage
            .list_scoped_sessions(&scope_b)
            .await
            .unwrap()
            .is_empty()
    );
}

#[tokio::test]
async fn runtime_events_are_committed_with_the_turn_and_can_be_replayed() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let scope = ConversationScope::default();
    let session = storage
        .create_scoped_session(&scope, "Events")
        .await
        .unwrap();
    let events = vec![
        RuntimeEvent::TurnStarted {
            turn_id: "turn-1".into(),
        },
        RuntimeEvent::TurnFinished {
            turn_id: "turn-1".into(),
        },
    ];

    storage
        .append_scoped_turn_with_events(&scope, &session.id, "hello", "hi", &events)
        .await
        .unwrap();
    let persisted = storage
        .list_conversation_events(&scope, &session.id)
        .await
        .unwrap();

    assert_eq!(persisted.len(), 2);
    assert_eq!(persisted[0].event_index, 0);
    assert_eq!(persisted[0].kind, "turn_started");
    assert_eq!(persisted[1].kind, "turn_finished");
    assert_eq!(persisted[0].payload["turn_id"], "turn-1");
}

#[tokio::test]
async fn batch_event_persistence_projects_sensitive_tool_payloads() {
    let root = tempfile::tempdir().unwrap();
    let database = root.path().join("metadata-only-events.db");
    let url = format!("sqlite://{}?mode=rwc", database.display());
    let scope = ConversationScope::local("com.example.metadata-only-batch");
    let storage = Storage::connect(&url).await.unwrap();
    let session = storage
        .create_scoped_session(&scope, "Sensitive batch")
        .await
        .unwrap();
    let events = vec![
        RuntimeEvent::ToolCallStarted {
            call_id: "call-sensitive".into(),
            name: "connector__mail__read".into(),
            arguments: serde_json::json!({"query": "batch-argument-secret"}),
            persistence: ToolPersistence::MetadataOnly,
        },
        RuntimeEvent::ToolCallFinished {
            call_id: "call-sensitive".into(),
            result: serde_json::json!({
                "ok": true,
                "data": {"body": "batch-result-secret"},
                "error": null,
                "metadata": {"duration_ms": 7, "output_truncated": false}
            }),
            persistence: ToolPersistence::MetadataOnly,
        },
    ];

    storage
        .append_scoped_turn_with_events(&scope, &session.id, "read", "done", &events)
        .await
        .unwrap();
    storage.close().await;

    let restarted = Storage::connect(&url).await.unwrap();
    let persisted = restarted
        .list_conversation_events(&scope, &session.id)
        .await
        .unwrap();
    let encoded = serde_json::to_string(&persisted).unwrap();
    assert!(!encoded.contains("batch-argument-secret"));
    assert!(!encoded.contains("batch-result-secret"));
    assert!(persisted[0].payload.get("arguments").is_none());
    assert!(persisted[0].payload.get("arguments_metadata").is_some());
    assert!(persisted[1].payload.get("result").is_none());
    assert_eq!(persisted[1].payload["result_metadata"]["ok"], true);
}

#[tokio::test]
async fn batch_event_persistence_keeps_full_tool_payloads_when_allowed() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let scope = ConversationScope::local("com.example.full-events");
    let session = storage
        .create_scoped_session(&scope, "Full events")
        .await
        .unwrap();
    let event = RuntimeEvent::ToolCallStarted {
        call_id: "call-public".into(),
        name: "echo".into(),
        arguments: serde_json::json!({"text": "public-value"}),
        persistence: ToolPersistence::Full,
    };

    storage
        .append_scoped_turn_with_events(&scope, &session.id, "echo", "done", &[event])
        .await
        .unwrap();
    let persisted = storage
        .list_conversation_events(&scope, &session.id)
        .await
        .unwrap();

    assert_eq!(persisted[0].payload["arguments"]["text"], "public-value");
}

#[tokio::test]
async fn messages_survive_restart_and_form_safe_model_history() {
    let root = tempfile::tempdir().unwrap();
    let database = root.path().join("conversation.db");
    let url = format!("sqlite://{}?mode=rwc", database.display());
    let scope = ConversationScope::local("com.example.restart");
    let storage = Storage::connect(&url).await.unwrap();
    let session = storage
        .create_scoped_session(&scope, "Restart")
        .await
        .unwrap();
    storage
        .append_scoped_turn(&scope, &session.id, "我喜欢下午开会", "记住了")
        .await
        .unwrap();
    storage.close().await;

    let restarted = Storage::connect(&url).await.unwrap();
    let messages = restarted
        .list_scoped_messages(&scope, &session.id)
        .await
        .unwrap();
    let history = messages_to_model_history(&messages).unwrap();

    assert_eq!(history.len(), 2);
    assert_eq!(history[0]["role"], "user");
    assert_eq!(history[0]["content"], "我喜欢下午开会");
    assert_eq!(history[1]["role"], "assistant");
}

#[tokio::test]
async fn conversation_search_is_scoped_and_bounded() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let scope = ConversationScope::local("com.example.search");
    let other = ConversationScope::local("com.example.other");
    let session = storage
        .create_scoped_session(&scope, "Search")
        .await
        .unwrap();
    let hidden = storage
        .create_scoped_session(&other, "Hidden")
        .await
        .unwrap();
    storage
        .append_scoped_turn(&scope, &session.id, "北京会议", "下午三点")
        .await
        .unwrap();
    storage
        .append_scoped_turn(&other, &hidden.id, "北京秘密", "hidden")
        .await
        .unwrap();

    let matches = storage
        .search_scoped_messages(&scope, "北京", 10)
        .await
        .unwrap();
    assert_eq!(matches.len(), 1);
    assert_eq!(matches[0].session_id, session.id);
    assert!(
        storage
            .search_scoped_messages(&scope, "", 10)
            .await
            .is_err()
    );
}

#[tokio::test]
async fn session_pages_use_a_stable_scoped_cursor() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let scope = ConversationScope::local("com.example.pages");
    let first = storage
        .create_scoped_session(&scope, "First")
        .await
        .unwrap();
    let second = storage
        .create_scoped_session(&scope, "Second")
        .await
        .unwrap();
    let third = storage
        .create_scoped_session(&scope, "Third")
        .await
        .unwrap();
    for (session, timestamp) in [
        (&first, "2025-01-03T00:00:00+00:00"),
        (&second, "2025-01-02T00:00:00+00:00"),
        (&third, "2025-01-01T00:00:00+00:00"),
    ] {
        sqlx::query("UPDATE sessions SET updated_at = ? WHERE id = ?")
            .bind(timestamp)
            .bind(&session.id)
            .execute(storage.pool())
            .await
            .unwrap();
    }

    let first_page = storage
        .list_scoped_sessions_page(&scope, None, 2)
        .await
        .unwrap();
    assert_eq!(
        first_page
            .items
            .iter()
            .map(|session| session.id.as_str())
            .collect::<Vec<_>>(),
        vec![first.id.as_str(), second.id.as_str()]
    );
    let cursor = first_page.next_cursor.unwrap();
    let second_page = storage
        .list_scoped_sessions_page(&scope, Some(&cursor), 2)
        .await
        .unwrap();
    assert_eq!(second_page.items.len(), 1);
    assert_eq!(second_page.items[0].id, third.id);
    assert!(second_page.next_cursor.is_none());
}

#[tokio::test]
async fn session_title_and_delete_use_optimistic_concurrency() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let scope = ConversationScope::local("com.example.mutations");
    let session = storage
        .create_scoped_session(&scope, "Original")
        .await
        .unwrap();

    let updated = storage
        .update_scoped_session_title(&scope, &session.id, "Renamed", session.updated_at)
        .await
        .unwrap();
    let SessionMutation::Applied(updated) = updated else {
        panic!("title update was not applied");
    };
    assert_eq!(updated.title, "Renamed");
    assert!(updated.updated_at > session.updated_at);

    assert!(matches!(
        storage
            .update_scoped_session_title(&scope, &session.id, "Stale", session.updated_at)
            .await
            .unwrap(),
        SessionMutation::Conflict(authoritative) if authoritative.title == "Renamed"
    ));
    assert!(matches!(
        storage
            .delete_scoped_session_if_unchanged(&scope, &session.id, session.updated_at)
            .await
            .unwrap(),
        SessionMutation::Conflict(_)
    ));
    assert!(matches!(
        storage
            .delete_scoped_session_if_unchanged(&scope, &session.id, updated.updated_at)
            .await
            .unwrap(),
        SessionMutation::Applied(_)
    ));
    assert!(
        storage
            .get_scoped_session(&scope, &session.id)
            .await
            .unwrap()
            .is_none()
    );
}
