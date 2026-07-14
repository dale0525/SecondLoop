use super::*;

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
