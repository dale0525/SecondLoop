use super::*;
use std::sync::{
    Mutex as StdMutex,
    atomic::{AtomicUsize, Ordering},
};
use tokio::sync::Notify;

struct HistoryCapturingAgent {
    histories: Arc<StdMutex<Vec<Vec<serde_json::Value>>>>,
}

#[async_trait::async_trait]
impl AgentRunner for HistoryCapturingAgent {
    async fn run(&self, user_text: &str) -> anyhow::Result<Vec<RuntimeEvent>> {
        Ok(finished_events(user_text))
    }

    async fn run_request(&self, request: TurnRequest) -> anyhow::Result<Vec<RuntimeEvent>> {
        self.histories
            .lock()
            .unwrap()
            .push(request.conversation_history);
        Ok(finished_events(&request.user_text))
    }
}

fn finished_events(user_text: &str) -> Vec<RuntimeEvent> {
    let turn_id = uuid::Uuid::new_v4().to_string();
    let text = format!("answer:{user_text}");
    vec![
        RuntimeEvent::TurnStarted {
            turn_id: turn_id.clone(),
        },
        RuntimeEvent::AssistantMessageFinished { text },
        RuntimeEvent::TurnFinished { turn_id },
    ]
}

#[tokio::test]
async fn second_server_turn_receives_first_turn_history_and_persists_events() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let histories = Arc::new(StdMutex::new(Vec::new()));
    let state = Arc::new(AppState::new_with_agent(
        storage.clone(),
        Arc::new(HistoryCapturingAgent {
            histories: histories.clone(),
        }),
    ));
    let session = storage
        .create_scoped_session(state.conversation_scope(), "History")
        .await
        .unwrap();

    for content in ["first", "second"] {
        let _ = post_message_for_actor(
            session.id.clone(),
            state.clone(),
            UserMessageRequest {
                content: content.into(),
                model_settings: None,
            },
            ActorContext::anonymous(),
        )
        .await
        .unwrap();
    }

    let captured = histories.lock().unwrap().clone();
    assert!(captured[0].is_empty());
    assert_eq!(captured[1].len(), 2);
    assert_eq!(captured[1][0]["role"], "user");
    assert_eq!(captured[1][0]["content"], "first");
    assert_eq!(captured[1][1]["role"], "assistant");
    assert_eq!(captured[1][1]["content"], "answer:first");
    let events = storage
        .list_conversation_events(state.conversation_scope(), &session.id)
        .await
        .unwrap();
    assert_eq!(events.len(), 6);
    assert_eq!(events[0].kind, "turn_started");
    assert_eq!(events[5].kind, "turn_finished");
}

struct BlockingHistoryAgent {
    calls: AtomicUsize,
    first_started: Notify,
    histories: Arc<StdMutex<Vec<Vec<serde_json::Value>>>>,
    release_first: Notify,
}

#[async_trait::async_trait]
impl AgentRunner for BlockingHistoryAgent {
    async fn run(&self, user_text: &str) -> anyhow::Result<Vec<RuntimeEvent>> {
        Ok(finished_events(user_text))
    }

    async fn run_request(&self, request: TurnRequest) -> anyhow::Result<Vec<RuntimeEvent>> {
        let call = self.calls.fetch_add(1, Ordering::SeqCst);
        self.histories
            .lock()
            .unwrap()
            .push(request.conversation_history);
        if call == 0 {
            self.first_started.notify_one();
            self.release_first.notified().await;
        }
        Ok(finished_events(&request.user_text))
    }
}

#[tokio::test]
async fn concurrent_turns_for_one_session_are_serialized_before_history_load() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let histories = Arc::new(StdMutex::new(Vec::new()));
    let agent = Arc::new(BlockingHistoryAgent {
        calls: AtomicUsize::new(0),
        first_started: Notify::new(),
        histories: histories.clone(),
        release_first: Notify::new(),
    });
    let state = Arc::new(AppState::new_with_agent(storage.clone(), agent.clone()));
    let session = storage
        .create_scoped_session(state.conversation_scope(), "Concurrent")
        .await
        .unwrap();

    let first = tokio::spawn(post_message_for_actor(
        session.id.clone(),
        state.clone(),
        UserMessageRequest {
            content: "first".into(),
            model_settings: None,
        },
        ActorContext::anonymous(),
    ));
    agent.first_started.notified().await;
    let second = tokio::spawn(post_message_for_actor(
        session.id,
        state,
        UserMessageRequest {
            content: "second".into(),
            model_settings: None,
        },
        ActorContext::anonymous(),
    ));
    tokio::task::yield_now().await;
    assert_eq!(histories.lock().unwrap().len(), 1);

    agent.release_first.notify_one();
    let _ = first.await.unwrap().unwrap();
    let _ = second.await.unwrap().unwrap();
    let captured = histories.lock().unwrap();
    assert!(captured[0].is_empty());
    assert_eq!(captured[1].len(), 2);
    assert_eq!(captured[1][0]["content"], "first");
    assert_eq!(captured[1][1]["content"], "answer:first");
}
