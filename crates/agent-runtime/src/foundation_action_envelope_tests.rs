use super::*;
use crate::approval::{ApprovalStatus, immutable_arguments_hash};
use crate::durable_run::ActionStatus;
use chrono::Duration;
use std::collections::BTreeSet;

fn scope() -> RunScope {
    RunScope {
        app_id: "com.example.agent".into(),
        agent_id: "assistant".into(),
        tenant_id: "local".into(),
        user_id: "user-1".into(),
        session_id: Some("session-1".into()),
    }
}

fn envelope(key: &str, subject: &str) -> FoundationActionEnvelope {
    FoundationActionEnvelope::new(
        "mail.send",
        "mail",
        "mail_send",
        "primary@example.com",
        FoundationActionResource::new("draft", "draft-1", Some("7".into())).unwrap(),
        FoundationActionEffect::ExternalWrite,
        key,
        json!({"draftId": "draft-1", "subject": subject}),
        FoundationActionPreview::new(
            format!("Send one message with subject {subject}"),
            json!({"to": ["recipient@example.com"]}),
        )
        .unwrap(),
    )
    .unwrap()
}

fn request(key: &str, subject: &str, now: DateTime<Utc>) -> FoundationActionRequest {
    FoundationActionRequest {
        scope: scope(),
        envelope: envelope(key, subject),
        policy_version: "policy-v1".into(),
        expires_at: now + Duration::minutes(15),
    }
}

#[test]
fn envelope_hash_is_canonical_and_unknown_or_drifted_fields_fail_closed() {
    let left = envelope("send-1", "Hello");
    let mut right = left.clone();
    right.payload = json!({"subject": "Hello", "draftId": "draft-1"});
    assert_eq!(
        left.envelope_sha256().unwrap(),
        right.envelope_sha256().unwrap()
    );

    right.payload = json!({"draftId": "draft-1", "subject": "Changed"});
    assert!(right.validate().is_err());
    let mut value = serde_json::to_value(left).unwrap();
    value
        .as_object_mut()
        .unwrap()
        .insert("approvalId".into(), json!("model-controlled"));
    assert!(serde_json::from_value::<FoundationActionEnvelope>(value).is_err());
}

#[tokio::test]
async fn request_is_atomic_durable_and_replays_the_exact_envelope() {
    let root = tempfile::tempdir().unwrap();
    let database = root.path().join("actions.db");
    let url = format!("sqlite://{}?mode=rwc", database.display());
    let storage = Storage::connect(&url).await.unwrap();
    let store = DurableFoundationActionStore::from_storage(&storage)
        .await
        .unwrap();
    let now = Utc::now();
    let first = store
        .request(request("send-1", "Hello", now), now)
        .await
        .unwrap();
    assert!(!first.replayed);
    assert_eq!(first.action.status, ActionStatus::WaitingApproval);
    assert_eq!(first.approval.status, ApprovalStatus::Pending);
    assert_eq!(
        first.approval.binding.arguments_sha256,
        first.envelope.envelope_sha256().unwrap()
    );
    assert_eq!(
        first.approval.binding.resource_target,
        first.envelope.resource_target()
    );
    storage.close().await;

    let restarted_storage = Storage::connect(&url).await.unwrap();
    let restarted = DurableFoundationActionStore::from_storage(&restarted_storage)
        .await
        .unwrap();
    let replay = restarted
        .request(request("send-1", "Hello", now), now)
        .await
        .unwrap();
    assert!(replay.replayed);
    assert!(replay.action.replayed);
    assert_eq!(replay.action.action_id, first.action.action_id);
    assert_eq!(replay.approval.approval_id, first.approval.approval_id);
}

#[tokio::test]
async fn idempotency_conflict_and_scope_isolation_are_explicit() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let store = DurableFoundationActionStore::from_storage(&storage)
        .await
        .unwrap();
    let now = Utc::now();
    let first = store
        .request(request("send-1", "Hello", now), now)
        .await
        .unwrap();
    assert!(
        store
            .request(request("send-1", "Changed", now), now)
            .await
            .is_err()
    );
    let mut policy_drift = request("send-1", "Hello", now);
    policy_drift.policy_version = "policy-v2".into();
    assert!(store.request(policy_drift, now).await.is_err());

    let mut isolated = request("send-1", "Changed", now);
    isolated.scope.session_id = Some("session-2".into());
    let second = store.request(isolated, now).await.unwrap();
    assert_ne!(first.action.action_id, second.action.action_id);
}

#[tokio::test]
async fn concurrent_requests_create_one_run_action_and_approval() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let store = DurableFoundationActionStore::from_storage(&storage)
        .await
        .unwrap();
    let now = Utc::now();
    let (left, right) = tokio::join!(
        store.request(request("send-race", "Hello", now), now),
        store.request(request("send-race", "Hello", now), now)
    );
    let left = left.unwrap();
    let right = right.unwrap();
    assert_eq!(left.action.action_id, right.action.action_id);
    assert_eq!(
        BTreeSet::from([left.replayed, right.replayed]),
        BTreeSet::from([false, true])
    );

    for table in [
        "durable_runs",
        "run_steps",
        "durable_actions",
        "run_approvals",
    ] {
        let count: i64 = sqlx::query_scalar(&format!("SELECT COUNT(*) FROM {table}"))
            .fetch_one(store.store.pool())
            .await
            .unwrap();
        assert_eq!(count, 1, "unexpected row count in {table}");
    }
}

#[tokio::test]
async fn persisted_envelope_drift_is_rejected_on_replay() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let store = DurableFoundationActionStore::from_storage(&storage)
        .await
        .unwrap();
    let now = Utc::now();
    let first = store
        .request(request("send-tamper", "Hello", now), now)
        .await
        .unwrap();
    let tampered = json!({"unexpected": true});
    sqlx::query("UPDATE durable_actions SET arguments_json = ? WHERE action_id = ?")
        .bind(serde_json::to_string(&tampered).unwrap())
        .bind(&first.action.action_id)
        .execute(store.store.pool())
        .await
        .unwrap();

    assert!(
        store
            .request(request("send-tamper", "Hello", now), now)
            .await
            .is_err()
    );
}

#[tokio::test]
async fn persistence_failure_rolls_back_registry_run_action_and_approval() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let store = DurableFoundationActionStore::from_storage(&storage)
        .await
        .unwrap();
    sqlx::query(
        r#"CREATE TRIGGER reject_foundation_approval
        BEFORE INSERT ON run_approvals
        BEGIN SELECT RAISE(ABORT, 'injected approval persistence failure'); END"#,
    )
    .execute(store.store.pool())
    .await
    .unwrap();
    let now = Utc::now();
    assert!(
        store
            .request(request("send-rollback", "Hello", now), now)
            .await
            .is_err()
    );

    for table in [
        "foundation_action_requests",
        "durable_runs",
        "run_steps",
        "durable_actions",
        "run_approvals",
    ] {
        let count: i64 = sqlx::query_scalar(&format!("SELECT COUNT(*) FROM {table}"))
            .fetch_one(store.store.pool())
            .await
            .unwrap();
        assert_eq!(count, 0, "partial state remained in {table}");
    }
}

#[test]
fn deserialized_payload_hash_must_match_exact_payload() {
    let mut value = serde_json::to_value(envelope("send-hash", "Hello")).unwrap();
    value["payloadSha256"] = json!(immutable_arguments_hash(&json!({"other": true})).unwrap());
    let decoded: FoundationActionEnvelope = serde_json::from_value(value).unwrap();
    assert!(decoded.validate().is_err());
}
