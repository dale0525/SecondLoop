use super::*;
use crate::api;
use agent_runtime::automation::{
    DeclarativeScheduledRunExecutor, NotificationStore, SchedulerRunner,
};
use agent_runtime::automation_tools::{AutomationScope, AutomationToolRuntime};
use agent_runtime::scheduler::SchedulerStore;
use agent_runtime::storage::Storage;
use agent_runtime::structured_content::{
    StructuredActionBindingRequest, StructuredContentAudience,
};
use agent_runtime::structured_content_store::{
    PublishStructuredContentRequest, StructuredActionClaim,
};
use axum::{
    body::{Body, to_bytes},
    http::{Request, StatusCode, header},
};
use chrono::Duration;
use serde_json::{Value, json};
use tower::ServiceExt;

#[test]
fn structured_error_mapping_requires_an_explicit_runtime_classification() {
    assert!(matches!(
        map_structured_error(anyhow::anyhow!(
            "database resource not found while decoding an invalid row"
        )),
        ApiError::Internal(_)
    ));
    assert!(matches!(
        map_structured_error(StructuredContentError::not_found("missing binding").into()),
        ApiError::NotFound(_)
    ));
    assert!(matches!(
        map_structured_error(StructuredContentError::conflict("stale binding").into()),
        ApiError::Conflict(_)
    ));
}

#[tokio::test]
async fn schedule_action_is_scoped_idempotent_and_advances_the_card() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let automation = AutomationToolRuntime::from_storage(
        &storage,
        AutomationScope::new("dev.agentweave.default", "local", "local-user").unwrap(),
    )
    .await
    .unwrap();
    let state = Arc::new(AppState::new(storage.clone()).with_automation_foundation(automation));
    let session = storage
        .create_scoped_session(state.conversation_scope(), "Reminder")
        .await
        .unwrap();
    let now = Utc::now();
    let published = state
        .structured_content()
        .publish(
            &session.id,
            Some("turn-1"),
            card_request(
                "reminder-card",
                None,
                vec![schedule_binding("confirm", "daily-reminder-1", now)],
            ),
            now,
        )
        .await
        .unwrap();
    let binding_id = &published.bindings[0].binding_id;
    let app = api::router(state.clone());
    let path = format!(
        "/sessions/{}/structured-actions/{binding_id}/accept",
        session.id
    );

    let first = app
        .clone()
        .oneshot(json_request(&path, json!({"input":{}})))
        .await
        .unwrap();
    assert_eq!(first.status(), StatusCode::OK);
    assert_eq!(first.headers()[header::CACHE_CONTROL], "no-store");
    let first = read_json(first).await;
    assert_eq!(first["receipt"]["replayed"], false);
    assert_eq!(first["receipt"]["payload"]["status"], "active");
    assert!(first["receipt"]["payload"]["id"].is_string());
    assert!(first["receipt"]["payload"].get("request").is_none());
    assert!(first["receipt"]["payload"].get("payload").is_none());

    let repeated = app
        .clone()
        .oneshot(json_request(&path, json!({"input":{}})))
        .await
        .unwrap();
    assert_eq!(repeated.status(), StatusCode::OK);
    assert_eq!(read_json(repeated).await["receipt"]["replayed"], true);

    let schedules = app
        .clone()
        .oneshot(empty_request("/foundation/schedules?limit=10"))
        .await
        .unwrap();
    assert_eq!(schedules.status(), StatusCode::OK);
    assert_eq!(read_json(schedules).await.as_array().unwrap().len(), 1);

    let content = app
        .oneshot(empty_request(&format!(
            "/sessions/{}/structured-content",
            session.id
        )))
        .await
        .unwrap();
    let content = read_json(content).await;
    assert_eq!(content[0]["revision"], 2);
    assert_eq!(content[0]["payload"]["status"]["label"], "Active");
    assert!(
        content[0]["payload"]["actions"]
            .as_array()
            .unwrap()
            .is_empty()
    );
    assert_eq!(content[0]["payload"]["fields"][2]["label"], "Timezone");
    assert_eq!(content[0]["payload"]["fields"][2]["value"], "Asia/Shanghai");
}

#[tokio::test]
async fn action_endpoint_rejects_scope_expiry_staleness_constraints_and_extra_parameters() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let state = Arc::new(AppState::new(storage.clone()));
    let session = storage
        .create_scoped_session(state.conversation_scope(), "Validation")
        .await
        .unwrap();
    let other = storage
        .create_scoped_session(state.conversation_scope(), "Other")
        .await
        .unwrap();
    let now = Utc::now();

    let scoped = state
        .structured_content()
        .publish(
            &session.id,
            None,
            card_request(
                "scope-card",
                None,
                vec![schedule_binding("confirm", "scope-1", now)],
            ),
            now,
        )
        .await
        .unwrap();
    let scoped_binding = &scoped.bindings[0].binding_id;
    let app = api::router(state.clone());
    let wrong_scope = app
        .clone()
        .oneshot(json_request(
            &format!(
                "/sessions/{}/structured-actions/{scoped_binding}/accept",
                other.id
            ),
            json!({"input":{}}),
        ))
        .await
        .unwrap();
    assert_eq!(wrong_scope.status(), StatusCode::NOT_FOUND);

    let extra = app
        .clone()
        .oneshot(json_request(
            &format!(
                "/sessions/{}/structured-actions/{scoped_binding}/accept",
                session.id
            ),
            json!({"input":{},"providerId":"attacker","schedule":{}}),
        ))
        .await
        .unwrap();
    assert_eq!(extra.status(), StatusCode::UNPROCESSABLE_ENTITY);

    let old = state
        .structured_content()
        .publish(
            &session.id,
            None,
            card_request(
                "stale-card",
                None,
                vec![schedule_binding("confirm", "stale-1", now)],
            ),
            now,
        )
        .await
        .unwrap();
    state
        .structured_content()
        .publish(
            &session.id,
            None,
            card_request("stale-card", Some(1), Vec::new()),
            now + Duration::seconds(1),
        )
        .await
        .unwrap();
    let stale = app
        .clone()
        .oneshot(json_request(
            &format!(
                "/sessions/{}/structured-actions/{}/accept",
                session.id, old.bindings[0].binding_id
            ),
            json!({"input":{}}),
        ))
        .await
        .unwrap();
    assert_eq!(stale.status(), StatusCode::CONFLICT);

    let publication_time = now - Duration::minutes(2);
    let expired = state
        .structured_content()
        .publish(
            &session.id,
            None,
            card_request(
                "expired-card",
                None,
                vec![schedule_binding_with_expiry(
                    "confirm",
                    "expired-1",
                    publication_time + Duration::minutes(1),
                )],
            ),
            publication_time,
        )
        .await
        .unwrap();
    let expired = app
        .clone()
        .oneshot(json_request(
            &format!(
                "/sessions/{}/structured-actions/{}/accept",
                session.id, expired.bindings[0].binding_id
            ),
            json!({"input":{}}),
        ))
        .await
        .unwrap();
    assert_eq!(expired.status(), StatusCode::CONFLICT);

    let oauth_mismatch = state
        .structured_content()
        .publish(
            &session.id,
            None,
            card_request(
                "oauth-card",
                None,
                vec![oauth_binding_with_mismatched_constraints(now)],
            ),
            now,
        )
        .await
        .unwrap_err();
    assert!(
        oauth_mismatch
            .to_string()
            .contains("constraints do not match")
    );
}

#[tokio::test]
async fn confirmed_reminder_survives_restart_and_enqueues_one_notification_per_run() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let automation = AutomationToolRuntime::from_storage(
        &storage,
        AutomationScope::new("dev.agentweave.default", "local", "local-user").unwrap(),
    )
    .await
    .unwrap();
    let state = Arc::new(AppState::new(storage.clone()).with_automation_foundation(automation));
    let session = storage
        .create_scoped_session(state.conversation_scope(), "One-shot reminder")
        .await
        .unwrap();
    let now = Utc::now();
    let binding = one_shot_schedule_binding(now);
    let published = state
        .structured_content()
        .publish(
            &session.id,
            None,
            card_request("one-shot-card", None, vec![binding]),
            now,
        )
        .await
        .unwrap();
    let app = api::router(state);
    let accepted = app
        .oneshot(json_request(
            &format!(
                "/sessions/{}/structured-actions/{}/accept",
                session.id, published.bindings[0].binding_id
            ),
            json!({"input":{}}),
        ))
        .await
        .unwrap();
    assert_eq!(accepted.status(), StatusCode::OK);

    let run_at = now + Duration::seconds(3);
    let first_runner = SchedulerRunner::new(
        SchedulerStore::from_storage(&storage).await.unwrap(),
        NotificationStore::from_storage(&storage).await.unwrap(),
        DeclarativeScheduledRunExecutor,
        "scheduler-before-restart",
        Duration::seconds(30),
    )
    .unwrap();
    assert_eq!(first_runner.tick(run_at, 10).await.unwrap(), 1);

    let restarted_runner = SchedulerRunner::new(
        SchedulerStore::from_storage(&storage).await.unwrap(),
        NotificationStore::from_storage(&storage).await.unwrap(),
        DeclarativeScheduledRunExecutor,
        "scheduler-after-restart",
        Duration::seconds(30),
    )
    .unwrap();
    assert_eq!(
        restarted_runner
            .tick(run_at + Duration::seconds(1), 10)
            .await
            .unwrap(),
        0
    );
    let notifications = NotificationStore::from_storage(&storage).await.unwrap();
    let claimed = notifications
        .claim_due(
            "desktop-host",
            run_at + Duration::seconds(1),
            Duration::seconds(30),
            10,
        )
        .await
        .unwrap();
    assert_eq!(claimed.len(), 1);
    assert_eq!(claimed[0].request.title, "One-shot reminder");
    assert_eq!(claimed[0].request.body, "Review today's priorities.");
}

#[tokio::test]
async fn oauth_resource_actions_are_bound_to_the_originating_content_and_session() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let state = Arc::new(AppState::new(storage.clone()));
    let original = storage
        .create_scoped_session(state.conversation_scope(), "Original OAuth")
        .await
        .unwrap();
    let other = storage
        .create_scoped_session(state.conversation_scope(), "Other OAuth")
        .await
        .unwrap();
    let now = Utc::now();
    let published = state
        .structured_content()
        .publish(
            &original.id,
            None,
            card_request(
                "owned-oauth-card",
                None,
                vec![oauth_start_binding(now, "owned-oauth-start")],
            ),
            now,
        )
        .await
        .unwrap();
    let execution = match state
        .structured_content()
        .claim_action(
            &original.id,
            &published.bindings[0].binding_id,
            json!({}),
            now,
        )
        .await
        .unwrap()
    {
        StructuredActionClaim::Execute(execution) => execution,
        StructuredActionClaim::Replay(_) => panic!("unexpected replay"),
    };
    state
        .structured_content()
        .complete_action(
            &execution,
            json!({
                "authorizationId":"authorization-1",
                "providerId":"workspace",
                "connectorIds":["calendar"],
                "requestedCapabilities":["read"],
                "status":"pending",
                "expiresAt":(now + Duration::minutes(10))
            }),
            now,
        )
        .await
        .unwrap();

    ensure_owned_oauth_authorization(&state, &execution, "authorization-1")
        .await
        .unwrap();
    let mut foreign_content_execution = execution.clone();
    foreign_content_execution.content_id = "other-oauth-card".into();
    let error =
        ensure_owned_oauth_authorization(&state, &foreign_content_execution, "authorization-1")
            .await
            .unwrap_err();
    assert!(matches!(error, ApiError::NotFound(_)));
    let mut foreign_execution = execution.clone();
    foreign_execution.session_id = other.id;
    let error = ensure_owned_oauth_authorization(&state, &foreign_execution, "authorization-1")
        .await
        .unwrap_err();
    assert!(matches!(error, ApiError::NotFound(_)));
}

fn card_request(
    content_id: &str,
    expected_revision: Option<u64>,
    bindings: Vec<StructuredActionBindingRequest>,
) -> PublishStructuredContentRequest {
    PublishStructuredContentRequest {
        content_id: Some(content_id.into()),
        expected_revision,
        mime_type: "application/vnd.agentweave.card+json".into(),
        schema_version: "1".into(),
        payload: json!({
            "title":"Reminder preview",
            "status":{"label":"Ready","tone":"info"},
            "actions":bindings.iter().map(|binding| json!({
                "id":binding.action_id,
                "label":"Confirm",
                "style":"primary"
            })).collect::<Vec<_>>()
        }),
        fallback_text: "Reminder preview".into(),
        audience: StructuredContentAudience::User,
        bindings,
    }
}

fn schedule_binding(
    action_id: &str,
    idempotency_key: &str,
    now: chrono::DateTime<Utc>,
) -> StructuredActionBindingRequest {
    let mut binding =
        schedule_binding_with_expiry(action_id, idempotency_key, now + Duration::minutes(10));
    binding.parameters = json!({
        "name":"Daily reminder",
        "schedule":{
            "kind":"cron",
            "expression":"0 0 9 * * *",
            "timezone":"Asia/Shanghai"
        },
        "misfire":{"kind":"fire_once"},
        "payload":{
            "notifications":[{
                "channel":"desktop",
                "title":"Daily reminder",
                "body":"Review today's priorities.",
                "dedupeKey":"daily-reminder-notification",
                "notBefore":now.to_rfc3339(),
                "quietHours":null,
                "data":{}
            }]
        },
        "idempotencyKey":idempotency_key
    });
    binding
}

fn schedule_binding_with_expiry(
    action_id: &str,
    idempotency_key: &str,
    expires_at: chrono::DateTime<Utc>,
) -> StructuredActionBindingRequest {
    StructuredActionBindingRequest {
        action_id: action_id.into(),
        intent: StructuredActionIntent::ScheduleCreate,
        idempotency_key: idempotency_key.into(),
        expires_at,
        parameters: json!({
            "name":"Reminder",
            "schedule":{
                "kind":"cron",
                "expression":"0 0 9 * * *",
                "timezone":"UTC"
            },
            "misfire":{"kind":"fire_once"},
            "payload":{
                "notifications":[{
                    "channel":"desktop",
                    "title":"Reminder",
                    "body":"Review today's priorities.",
                    "dedupeKey":idempotency_key,
                    "notBefore":expires_at.to_rfc3339(),
                    "quietHours":null,
                    "data":{}
                }]
            },
            "idempotencyKey":idempotency_key
        }),
        input_schema: empty_input_schema(),
        constraints: StructuredActionConstraints::default(),
    }
}

fn one_shot_schedule_binding(now: chrono::DateTime<Utc>) -> StructuredActionBindingRequest {
    StructuredActionBindingRequest {
        action_id: "confirm".into(),
        intent: StructuredActionIntent::ScheduleCreate,
        idempotency_key: "one-shot-reminder-binding".into(),
        expires_at: now + Duration::minutes(10),
        parameters: json!({
            "name":"One-shot reminder",
            "schedule":{
                "kind":"one_shot",
                "at":(now + Duration::seconds(2)).to_rfc3339()
            },
            "misfire":{"kind":"fire_once"},
            "payload":{
                "notifications":[{
                    "channel":"desktop",
                    "title":"One-shot reminder",
                    "body":"Review today's priorities.",
                    "dedupeKey":"one-shot-reminder",
                    "notBefore":(now + Duration::seconds(2)).to_rfc3339(),
                    "quietHours":null,
                    "data":{}
                }]
            },
            "idempotencyKey":"one-shot-reminder-job"
        }),
        input_schema: empty_input_schema(),
        constraints: StructuredActionConstraints::default(),
    }
}

fn oauth_binding_with_mismatched_constraints(
    now: chrono::DateTime<Utc>,
) -> StructuredActionBindingRequest {
    StructuredActionBindingRequest {
        action_id: "authorize".into(),
        intent: StructuredActionIntent::OauthStart,
        idempotency_key: "oauth-mismatch-1".into(),
        expires_at: now + Duration::minutes(10),
        parameters: json!({
            "providerId":"workspace",
            "connectorIds":["calendar"],
            "requestedCapabilities":["read"]
        }),
        input_schema: empty_input_schema(),
        constraints: StructuredActionConstraints {
            provider_ids: vec!["other-provider".into()],
            connector_ids: vec!["calendar".into()],
            capabilities: vec!["read".into()],
        },
    }
}

fn oauth_start_binding(
    now: chrono::DateTime<Utc>,
    idempotency_key: &str,
) -> StructuredActionBindingRequest {
    StructuredActionBindingRequest {
        action_id: "authorize".into(),
        intent: StructuredActionIntent::OauthStart,
        idempotency_key: idempotency_key.into(),
        expires_at: now + Duration::minutes(10),
        parameters: json!({
            "providerId":"workspace",
            "connectorIds":["calendar"],
            "requestedCapabilities":["read"]
        }),
        input_schema: empty_input_schema(),
        constraints: StructuredActionConstraints {
            provider_ids: vec!["workspace".into()],
            connector_ids: vec!["calendar".into()],
            capabilities: vec!["read".into()],
        },
    }
}

fn empty_input_schema() -> Value {
    json!({
        "type":"object",
        "properties":{},
        "required":[],
        "additionalProperties":false
    })
}

fn json_request(uri: &str, body: Value) -> Request<Body> {
    Request::builder()
        .method("POST")
        .uri(uri)
        .header(header::CONTENT_TYPE, "application/json")
        .body(Body::from(body.to_string()))
        .unwrap()
}

fn empty_request(uri: &str) -> Request<Body> {
    Request::builder().uri(uri).body(Body::empty()).unwrap()
}

async fn read_json(response: axum::response::Response) -> Value {
    let bytes = to_bytes(response.into_body(), 1024 * 1024).await.unwrap();
    serde_json::from_slice(&bytes).unwrap()
}
