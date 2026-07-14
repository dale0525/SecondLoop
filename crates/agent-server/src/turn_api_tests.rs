use super::*;
use crate::api;
use agent_runtime::{
    session::ConversationScope, storage::Storage, turn::AgentRunner, turn_request::TurnRequest,
};
use async_trait::async_trait;
use axum::{
    body::{Body, to_bytes},
    http::Request,
};
use serde_json::{Value, json};
use tower::ServiceExt;

struct CompletingAgent;

#[async_trait]
impl AgentRunner for CompletingAgent {
    async fn run(&self, user_text: &str) -> anyhow::Result<Vec<RuntimeEvent>> {
        Ok(completed_events("generated-turn", user_text))
    }

    async fn run_request_observed(
        &self,
        request: TurnRequest,
        observer: RuntimeEventObserver,
    ) -> anyhow::Result<Vec<RuntimeEvent>> {
        let turn_id = request.turn_id.unwrap();
        let events = completed_events(&turn_id, "streamed reply");
        for event in &events {
            observer(event.clone());
            tokio::task::yield_now().await;
        }
        Ok(events)
    }
}

struct WaitingAgent;

#[async_trait]
impl AgentRunner for WaitingAgent {
    async fn run(&self, _user_text: &str) -> anyhow::Result<Vec<RuntimeEvent>> {
        unreachable!()
    }

    async fn run_request_observed(
        &self,
        request: TurnRequest,
        observer: RuntimeEventObserver,
    ) -> anyhow::Result<Vec<RuntimeEvent>> {
        let turn_id = request.turn_id.unwrap();
        observer(RuntimeEvent::TurnStarted {
            turn_id: turn_id.clone(),
        });
        observer(RuntimeEvent::AssistantTextDelta {
            text: "partial".into(),
        });
        std::future::pending::<()>().await;
        Ok(vec![])
    }
}

#[tokio::test]
async fn streamed_turn_replays_events_and_commits_assistant_atomically() {
    let (app, storage, scope, session_id) = test_app(Arc::new(CompletingAgent)).await;
    let accepted = app
        .clone()
        .oneshot(json_request(
            "POST",
            &format!("/sessions/{session_id}/turns"),
            json!({ "requestId": "request-1", "content": "hello" }),
        ))
        .await
        .unwrap();
    assert_eq!(accepted.status(), StatusCode::ACCEPTED);
    let accepted = read_json(accepted).await;
    let turn_id = accepted["turn"]["id"].as_str().unwrap();
    let (page, events) = read_until(&app, &session_id, turn_id, -1, |page, _| {
        page["turn"]["status"] == "completed"
    })
    .await;
    assert_eq!(page["turn"]["status"], "completed");
    assert_eq!(events[0]["payload"]["type"], "turn_started");
    assert_eq!(events.last().unwrap()["kind"], "turn_finished");
    let messages = storage
        .list_scoped_messages(&scope, &session_id)
        .await
        .unwrap();
    assert_eq!(messages.len(), 2);
    assert_eq!(messages[1].content, "streamed reply");
    let conflict = app
        .oneshot(json_request(
            "POST",
            &format!("/sessions/{session_id}/turns"),
            json!({ "requestId": "request-1", "content": "different" }),
        ))
        .await
        .unwrap();
    assert_eq!(conflict.status(), StatusCode::CONFLICT);
}

#[tokio::test]
async fn cancellation_stops_execution_and_persists_one_terminal_event() {
    let (app, storage, scope, session_id) = test_app(Arc::new(WaitingAgent)).await;
    let accepted = read_json(
        app.clone()
            .oneshot(json_request(
                "POST",
                &format!("/sessions/{session_id}/turns"),
                json!({ "requestId": "request-cancel", "content": "wait" }),
            ))
            .await
            .unwrap(),
    )
    .await;
    let turn_id = accepted["turn"]["id"].as_str().unwrap();
    let (first, events) = read_until(&app, &session_id, turn_id, -1, |_page, events| {
        events
            .iter()
            .any(|event| event["kind"] == "assistant_text_delta")
    })
    .await;
    assert!(
        events
            .iter()
            .any(|event| event["payload"]["text"] == "partial")
    );
    let cursor = first["nextCursor"].as_i64().unwrap();
    let cancelled = read_json(
        app.clone()
            .oneshot(empty_request(
                "POST",
                &format!("/sessions/{session_id}/turns/{turn_id}/cancel"),
            ))
            .await
            .unwrap(),
    )
    .await;
    assert_eq!(cancelled["accepted"], true);
    let (terminal, terminal_events) = read_until(&app, &session_id, turn_id, cursor, |page, _| {
        page["turn"]["status"] == "cancelled"
    })
    .await;
    assert_eq!(terminal["turn"]["status"], "cancelled");
    assert_eq!(terminal_events[0]["kind"], "turn_cancelled");
    assert_eq!(
        storage
            .list_scoped_messages(&scope, &session_id)
            .await
            .unwrap()
            .len(),
        1
    );
}

async fn test_app(
    agent: Arc<dyn AgentRunner>,
) -> (axum::Router, Storage, ConversationScope, String) {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let scope = ConversationScope::default();
    let session = storage
        .create_scoped_session(&scope, "Streaming")
        .await
        .unwrap();
    let app = api::router(Arc::new(AppState::new_with_agent(storage.clone(), agent)));
    (app, storage, scope, session.id)
}

fn completed_events(turn_id: &str, text: &str) -> Vec<RuntimeEvent> {
    vec![
        RuntimeEvent::TurnStarted {
            turn_id: turn_id.into(),
        },
        RuntimeEvent::AssistantTextDelta { text: text.into() },
        RuntimeEvent::AssistantMessageFinished { text: text.into() },
        RuntimeEvent::TurnFinished {
            turn_id: turn_id.into(),
        },
    ]
}

fn json_request(method: &str, uri: &str, body: Value) -> Request<Body> {
    Request::builder()
        .method(method)
        .uri(uri)
        .header("content-type", "application/json")
        .body(Body::from(body.to_string()))
        .unwrap()
}

fn empty_request(method: &str, uri: &str) -> Request<Body> {
    Request::builder()
        .method(method)
        .uri(uri)
        .body(Body::empty())
        .unwrap()
}

async fn read_json(response: axum::response::Response) -> Value {
    let bytes = to_bytes(response.into_body(), 1024 * 1024).await.unwrap();
    serde_json::from_slice(&bytes).unwrap()
}

async fn read_until(
    app: &axum::Router,
    session_id: &str,
    turn_id: &str,
    mut cursor: i64,
    stop: impl Fn(&Value, &[Value]) -> bool,
) -> (Value, Vec<Value>) {
    let mut events = Vec::new();
    for _ in 0..10 {
        let page = read_json(
            app.clone()
                .oneshot(empty_request(
                    "GET",
                    &format!(
                        "/sessions/{session_id}/turns/{turn_id}/events?after={cursor}&waitMs=1000"
                    ),
                ))
                .await
                .unwrap(),
        )
        .await;
        events.extend(page["events"].as_array().unwrap().iter().cloned());
        cursor = page["nextCursor"].as_i64().unwrap();
        if stop(&page, &events) {
            return (page, events);
        }
    }
    panic!("turn did not reach the expected state");
}
