use super::*;
use crate::tools::ToolPersistence;

#[tokio::test]
async fn durable_turn_is_idempotent_and_replays_cursor_pages() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let scope = ConversationScope::local("com.example.turns");
    let session = storage
        .create_scoped_session(&scope, "Streaming")
        .await
        .unwrap();
    let started = storage
        .begin_scoped_turn(&scope, &session.id, "request-1", "hello")
        .await
        .unwrap();
    assert!(started.created);
    let replayed = storage
        .begin_scoped_turn(&scope, &session.id, "request-1", "hello")
        .await
        .unwrap();
    assert!(!replayed.created);
    assert_eq!(replayed.turn.id, started.turn.id);
    assert_eq!(replayed.user_message.content, "hello");
    assert_eq!(
        storage
            .begin_scoped_turn(&scope, &session.id, "request-1", "different")
            .await
            .unwrap_err()
            .to_string(),
        TURN_REQUEST_CONFLICT_MESSAGE
    );

    for event in [
        RuntimeEvent::TurnStarted {
            turn_id: started.turn.id.clone(),
        },
        RuntimeEvent::AssistantTextDelta { text: "hi".into() },
    ] {
        storage
            .append_scoped_turn_event(&scope, &session.id, &started.turn.id, &event)
            .await
            .unwrap();
    }
    let first = storage
        .list_scoped_turn_events_page(&scope, &session.id, &started.turn.id, -1, 1)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(first.events.len(), 1);
    assert!(first.has_more);
    let second = storage
        .list_scoped_turn_events_page(&scope, &session.id, &started.turn.id, first.next_cursor, 10)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(second.events[0].payload["text"], "hi");

    let terminal = RuntimeEvent::TurnFinished {
        turn_id: started.turn.id.clone(),
    };
    let finished = storage
        .finish_scoped_turn(
            &scope,
            &session.id,
            &started.turn.id,
            ConversationTurnCompletion {
                status: ConversationTurnStatus::Completed,
                terminal_event: &terminal,
                assistant_content: Some("hi"),
                failure_message: None,
            },
        )
        .await
        .unwrap();
    assert_eq!(finished.status, ConversationTurnStatus::Completed);
    assert!(finished.assistant_message_id.is_some());
    assert_eq!(
        storage
            .list_scoped_messages(&scope, &session.id)
            .await
            .unwrap()
            .len(),
        2
    );
}

#[tokio::test]
async fn durable_event_persistence_projects_sensitive_tool_payloads_across_restart() {
    let root = tempfile::tempdir().unwrap();
    let database = root.path().join("metadata-only-turn.db");
    let url = format!("sqlite://{}?mode=rwc", database.display());
    let scope = ConversationScope::local("com.example.metadata-only-turn");
    let storage = Storage::connect(&url).await.unwrap();
    let session = storage
        .create_scoped_session(&scope, "Sensitive turn")
        .await
        .unwrap();
    let started = storage
        .begin_scoped_turn(&scope, &session.id, "request-sensitive", "read")
        .await
        .unwrap();
    for event in [
        RuntimeEvent::ToolCallStarted {
            call_id: "call-sensitive".into(),
            name: "connector__mail__read".into(),
            arguments: serde_json::json!({"query": "durable-argument-secret"}),
            persistence: ToolPersistence::MetadataOnly,
        },
        RuntimeEvent::ToolCallFinished {
            call_id: "call-sensitive".into(),
            result: serde_json::json!({
                "ok": false,
                "data": null,
                "error": {
                    "code": "permission_denied",
                    "message": "durable-result-secret",
                    "retryable": false
                },
                "metadata": {"duration_ms": 4, "output_truncated": false}
            }),
            persistence: ToolPersistence::MetadataOnly,
        },
    ] {
        storage
            .append_scoped_turn_event(&scope, &session.id, &started.turn.id, &event)
            .await
            .unwrap();
    }
    storage.close().await;

    let restarted = Storage::connect(&url).await.unwrap();
    let page = restarted
        .list_scoped_turn_events_page(&scope, &session.id, &started.turn.id, -1, 10)
        .await
        .unwrap()
        .unwrap();
    let encoded = serde_json::to_string(&page.events).unwrap();
    assert!(!encoded.contains("durable-argument-secret"));
    assert!(!encoded.contains("durable-result-secret"));
    assert!(page.events[0].payload.get("arguments").is_none());
    assert_eq!(
        page.events[1].payload["result_metadata"]["error_code"],
        "permission_denied"
    );
}

#[tokio::test]
async fn turn_writes_wait_for_a_competing_immediate_transaction() {
    let root = tempfile::tempdir().unwrap();
    let database = root.path().join("turn-write-contention.db");
    let url = format!("sqlite://{}?mode=rwc", database.display());
    let scope = ConversationScope::local("com.example.turn-write-contention");
    let storage = Storage::connect(&url).await.unwrap();
    let session = storage
        .create_scoped_session(&scope, "Write contention")
        .await
        .unwrap();
    let started = storage
        .begin_scoped_turn(&scope, &session.id, "request-contention", "hello")
        .await
        .unwrap();
    let blocker = Storage::connect_without_migrations(&url).await.unwrap();

    let blocking_tx = blocker.pool().begin_with("BEGIN IMMEDIATE").await.unwrap();
    let append_storage = storage.clone();
    let append_scope = scope.clone();
    let append_session_id = session.id.clone();
    let append_turn_id = started.turn.id.clone();
    let append = tokio::spawn(async move {
        append_storage
            .append_scoped_turn_event(
                &append_scope,
                &append_session_id,
                &append_turn_id,
                &RuntimeEvent::AssistantTextDelta { text: "hi".into() },
            )
            .await
    });
    tokio::time::sleep(std::time::Duration::from_millis(50)).await;
    assert!(!append.is_finished());
    blocking_tx.commit().await.unwrap();
    tokio::time::timeout(std::time::Duration::from_secs(2), append)
        .await
        .unwrap()
        .unwrap()
        .unwrap();

    let blocking_tx = blocker.pool().begin_with("BEGIN IMMEDIATE").await.unwrap();
    let finish_storage = storage.clone();
    let finish_scope = scope.clone();
    let finish_session_id = session.id.clone();
    let finish_turn_id = started.turn.id.clone();
    let finish = tokio::spawn(async move {
        let terminal = RuntimeEvent::TurnFinished {
            turn_id: finish_turn_id.clone(),
        };
        finish_storage
            .finish_scoped_turn(
                &finish_scope,
                &finish_session_id,
                &finish_turn_id,
                ConversationTurnCompletion {
                    status: ConversationTurnStatus::Completed,
                    terminal_event: &terminal,
                    assistant_content: Some("hi"),
                    failure_message: None,
                },
            )
            .await
    });
    tokio::time::sleep(std::time::Duration::from_millis(50)).await;
    assert!(!finish.is_finished());
    blocking_tx.commit().await.unwrap();
    let finished = tokio::time::timeout(std::time::Duration::from_secs(2), finish)
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    assert_eq!(finished.status, ConversationTurnStatus::Completed);
}

#[tokio::test]
async fn restart_marks_running_turn_interrupted_with_terminal_event() {
    let root = tempfile::tempdir().unwrap();
    let database = root.path().join("turns.db");
    let url = format!("sqlite://{}?mode=rwc", database.display());
    let scope = ConversationScope::local("com.example.recovery");
    let storage = Storage::connect(&url).await.unwrap();
    let session = storage
        .create_scoped_session(&scope, "Recovery")
        .await
        .unwrap();
    let started = storage
        .begin_scoped_turn(&scope, &session.id, "request-1", "hello")
        .await
        .unwrap();
    storage
        .append_scoped_turn_event(
            &scope,
            &session.id,
            &started.turn.id,
            &RuntimeEvent::AssistantTextDelta {
                text: "partial".into(),
            },
        )
        .await
        .unwrap();
    storage.close().await;

    let restarted = Storage::connect(&url).await.unwrap();
    let recovered = restarted
        .get_scoped_turn(&scope, &session.id, &started.turn.id)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(recovered.status, ConversationTurnStatus::Interrupted);
    assert_eq!(recovered.failure_message.as_deref(), Some(RECOVERY_MESSAGE));
    let page = restarted
        .list_scoped_turn_events_page(&scope, &session.id, &started.turn.id, -1, 10)
        .await
        .unwrap()
        .unwrap();
    assert_eq!(page.events.last().unwrap().kind, "turn_failed");
}
