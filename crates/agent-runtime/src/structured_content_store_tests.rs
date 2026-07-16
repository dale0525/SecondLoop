use super::*;
use crate::structured_content::StructuredActionConstraints;
use chrono::Duration;

async fn fixture(label: &str) -> (Storage, ConversationScope, String, StructuredContentService) {
    let path = std::env::temp_dir().join(format!(
        "agentweave-structured-content-{label}-{}.db",
        Uuid::new_v4()
    ));
    let storage = Storage::connect(&format!("sqlite://{}?mode=rwc", path.display()))
        .await
        .unwrap();
    let scope = ConversationScope::local("com.example.secretary");
    let session = storage
        .create_scoped_session(&scope, "Structured content")
        .await
        .unwrap();
    let service = StructuredContentService::new(storage.clone(), scope.clone(), "default").unwrap();
    (storage, scope, session.id, service)
}

fn card_request(
    expected_revision: Option<u64>,
    bindings: Vec<StructuredActionBindingRequest>,
) -> PublishStructuredContentRequest {
    PublishStructuredContentRequest {
        content_id: Some("briefing-card".into()),
        expected_revision,
        mime_type: AGENTWEAVE_CARD_MIME.into(),
        schema_version: "1".into(),
        payload: serde_json::json!({
            "title": "Daily briefing",
            "summary": "Three items need attention.",
            "status": {"label": "Ready", "tone": "success"},
            "fields": [{"label": "Timezone", "value": "Asia/Shanghai"}],
            "actions": bindings.iter().map(|binding| serde_json::json!({
                "id": binding.action_id,
                "label": "Connect",
                "style": "primary"
            })).collect::<Vec<_>>()
        }),
        fallback_text: "Daily briefing: three items need attention.".into(),
        audience: StructuredContentAudience::User,
        bindings,
    }
}

fn oauth_binding(now: DateTime<Utc>) -> StructuredActionBindingRequest {
    oauth_binding_named(now, "connect-google", "connect-google-1")
}

fn oauth_binding_named(
    now: DateTime<Utc>,
    action_id: &str,
    idempotency_key: &str,
) -> StructuredActionBindingRequest {
    StructuredActionBindingRequest {
        action_id: action_id.into(),
        intent: StructuredActionIntent::OauthStart,
        idempotency_key: idempotency_key.into(),
        expires_at: now + Duration::minutes(10),
        parameters: serde_json::json!({
            "providerId": "google-workspace",
            "connectorIds": ["google-mail"],
            "requestedCapabilities": ["mail.read"]
        }),
        input_schema: serde_json::json!({
            "type": "object",
            "properties": {},
            "required": [],
            "additionalProperties": false
        }),
        constraints: StructuredActionConstraints {
            provider_ids: vec!["google-workspace".into()],
            connector_ids: vec!["google-mail".into()],
            capabilities: vec!["mail.read".into()],
        },
    }
}

#[tokio::test]
async fn schema_upgrade_adds_persisted_claim_fencing_columns() {
    let (storage, _scope, _session_id, _service) = fixture("claim-migration").await;
    sqlx::query("DROP INDEX structured_action_content_execution_idx")
        .execute(storage.pool())
        .await
        .unwrap();
    sqlx::query("ALTER TABLE structured_action_bindings DROP COLUMN claim_token")
        .execute(storage.pool())
        .await
        .unwrap();
    sqlx::query("ALTER TABLE structured_action_bindings DROP COLUMN claim_epoch")
        .execute(storage.pool())
        .await
        .unwrap();
    sqlx::query(
        "DELETE FROM runtime_schema_migrations WHERE component = 'conversation' AND version = 4",
    )
    .execute(storage.pool())
    .await
    .unwrap();
    sqlx::query(
        "INSERT OR IGNORE INTO runtime_schema_migrations(component, version, applied_at) VALUES ('conversation', 3, ?)",
    )
    .bind(Utc::now().to_rfc3339())
    .execute(storage.pool())
    .await
    .unwrap();

    storage.run_migrations().await.unwrap();

    let columns = sqlx::query("PRAGMA table_info(structured_action_bindings)")
        .fetch_all(storage.pool())
        .await
        .unwrap()
        .into_iter()
        .map(|row| row.try_get::<String, _>("name").unwrap())
        .collect::<std::collections::BTreeSet<_>>();
    assert!(columns.contains("claim_token"));
    assert!(columns.contains("claim_epoch"));
    let version: i64 = sqlx::query_scalar(
        "SELECT MAX(version) FROM runtime_schema_migrations WHERE component = 'conversation'",
    )
    .fetch_one(storage.pool())
    .await
    .unwrap();
    assert_eq!(version, 4);
}

#[tokio::test]
async fn content_revisions_survive_restart_and_tombstones_are_monotonic() {
    let (storage, scope, session_id, service) = fixture("lifecycle").await;
    let now = Utc::now();
    let first = service
        .publish(&session_id, Some("turn-1"), card_request(None, vec![]), now)
        .await
        .unwrap();
    assert_eq!(first.content.revision, 1);

    let restarted =
        StructuredContentService::new(storage.clone(), scope.clone(), "default").unwrap();
    assert_eq!(
        restarted
            .get(&session_id, "briefing-card")
            .await
            .unwrap()
            .unwrap()
            .revision,
        1
    );
    let second = restarted
        .publish(
            &session_id,
            Some("turn-2"),
            card_request(Some(1), vec![]),
            now + Duration::seconds(1),
        )
        .await
        .unwrap();
    assert_eq!(second.content.revision, 2);
    assert!(
        restarted
            .publish(
                &session_id,
                None,
                card_request(Some(1), vec![]),
                now + Duration::seconds(2),
            )
            .await
            .unwrap_err()
            .to_string()
            .contains("revision conflict")
    );
    assert!(
        restarted
            .delete(
                &session_id,
                None,
                "briefing-card",
                2,
                now + Duration::seconds(3),
            )
            .await
            .unwrap()
    );
    assert!(
        restarted
            .get(&session_id, "briefing-card")
            .await
            .unwrap()
            .is_none()
    );
    assert!(
        restarted
            .publish(
                &session_id,
                None,
                card_request(Some(3), vec![]),
                now + Duration::seconds(4),
            )
            .await
            .unwrap_err()
            .to_string()
            .contains("cannot be reused")
    );

    let events = storage
        .list_conversation_events(&scope, &session_id)
        .await
        .unwrap();
    assert_eq!(events.len(), 3);
    assert_eq!(events[2].kind, "structured_content_deleted");
    assert_eq!(events[2].payload["revision"], 3);
    assert_eq!(events[2].payload["audience"], "user");
}

#[tokio::test]
async fn action_bindings_are_scoped_expiring_and_idempotent_across_restart() {
    let (storage, scope, session_id, service) = fixture("actions").await;
    let now = Utc::now();
    let published = service
        .publish(
            &session_id,
            Some("turn-1"),
            card_request(None, vec![oauth_binding(now)]),
            now,
        )
        .await
        .unwrap();
    let binding_id = published.bindings[0].binding_id.clone();
    assert_eq!(
        published.content.payload["actionBindings"]["connect-google"],
        binding_id
    );
    let execution = match service
        .claim_action(&session_id, &binding_id, serde_json::json!({}), now)
        .await
        .unwrap()
    {
        StructuredActionClaim::Execute(execution) => execution,
        StructuredActionClaim::Replay(_) => panic!("new action unexpectedly replayed"),
    };
    assert_eq!(execution.intent, StructuredActionIntent::OauthStart);
    let receipt = service
        .complete_action(
            &execution,
            serde_json::json!({
                "authorizationId": "authorization-1",
                "providerId": "google-workspace",
                "status": "pending"
            }),
            now + Duration::seconds(1),
        )
        .await
        .unwrap();
    assert!(!receipt.replayed);

    let restarted =
        StructuredContentService::new(storage.clone(), scope.clone(), "default").unwrap();
    let replay = restarted
        .claim_action(
            &session_id,
            &binding_id,
            serde_json::json!({}),
            now + Duration::seconds(2),
        )
        .await
        .unwrap();
    assert!(matches!(replay, StructuredActionClaim::Replay(receipt) if receipt.replayed));

    let same_scope_session = storage
        .create_scoped_session(&scope, "Other same-scope session")
        .await
        .unwrap();
    assert!(
        restarted
            .claim_action(
                &same_scope_session.id,
                &binding_id,
                serde_json::json!({}),
                now + Duration::seconds(2),
            )
            .await
            .unwrap_err()
            .to_string()
            .contains("unavailable")
    );

    let other_scope = ConversationScope {
        app_id: scope.app_id.clone(),
        agent_id: "other-agent".into(),
        tenant_id: "other-tenant".into(),
        user_id: "other-user".into(),
        device_id: "other-device".into(),
    };
    let other_scope_session = storage
        .create_scoped_session(&other_scope, "Other scoped session")
        .await
        .unwrap();
    let other = StructuredContentService::new(storage, other_scope.clone(), "default").unwrap();
    assert!(
        other
            .claim_action(
                &other_scope_session.id,
                &binding_id,
                serde_json::json!({}),
                now + Duration::seconds(2),
            )
            .await
            .is_err()
    );
}

#[tokio::test]
async fn content_allows_only_one_binding_claim_at_a_time() {
    let (_storage, _scope, session_id, service) = fixture("content-claim").await;
    let now = Utc::now();
    let published = service
        .publish(
            &session_id,
            None,
            card_request(
                None,
                vec![
                    oauth_binding_named(now, "connect-google", "connect-google-1"),
                    oauth_binding_named(now, "connect-outlook", "connect-outlook-1"),
                ],
            ),
            now,
        )
        .await
        .unwrap();
    let first_id = published.bindings[0].binding_id.clone();
    let second_id = published.bindings[1].binding_id.clone();
    let barrier = std::sync::Arc::new(tokio::sync::Barrier::new(3));
    let first_service = service.clone();
    let first_session = session_id.clone();
    let first_barrier = barrier.clone();
    let first = tokio::spawn(async move {
        first_barrier.wait().await;
        first_service
            .claim_action(&first_session, &first_id, serde_json::json!({}), now)
            .await
    });
    let second_service = service.clone();
    let second_session = session_id.clone();
    let second_barrier = barrier.clone();
    let second = tokio::spawn(async move {
        second_barrier.wait().await;
        second_service
            .claim_action(&second_session, &second_id, serde_json::json!({}), now)
            .await
    });
    barrier.wait().await;
    let results = [first.await.unwrap(), second.await.unwrap()];
    assert_eq!(results.iter().filter(|result| result.is_ok()).count(), 1);
    assert_eq!(results.iter().filter(|result| result.is_err()).count(), 1);
    assert!(
        results
            .iter()
            .filter_map(|result| result.as_ref().err())
            .all(|error| error.to_string().contains("claim conflict"))
    );
}

#[tokio::test]
async fn expired_lease_reclaim_fences_the_old_worker() {
    let (storage, scope, session_id, service) = fixture("lease-fencing").await;
    let now = Utc::now();
    let published = service
        .publish(
            &session_id,
            None,
            card_request(None, vec![oauth_binding(now)]),
            now,
        )
        .await
        .unwrap();
    let binding_id = &published.bindings[0].binding_id;
    let old_execution = match service
        .claim_action(&session_id, binding_id, serde_json::json!({}), now)
        .await
        .unwrap()
    {
        StructuredActionClaim::Execute(execution) => execution,
        StructuredActionClaim::Replay(_) => panic!("new action unexpectedly replayed"),
    };

    let restarted = StructuredContentService::new(storage, scope, "default").unwrap();
    let new_execution = match restarted
        .claim_action(
            &session_id,
            binding_id,
            serde_json::json!({}),
            now + Duration::seconds(ACTION_LEASE_SECONDS + 1),
        )
        .await
        .unwrap()
    {
        StructuredActionClaim::Execute(execution) => execution,
        StructuredActionClaim::Replay(_) => panic!("expired action unexpectedly replayed"),
    };
    assert_ne!(old_execution.claim_token, new_execution.claim_token);
    assert_eq!(new_execution.claim_epoch, old_execution.claim_epoch + 1);

    let stale_time = now + Duration::seconds(ACTION_LEASE_SECONDS + 2);
    assert!(
        restarted
            .complete_action(
                &old_execution,
                serde_json::json!({"status":"stale"}),
                stale_time,
            )
            .await
            .unwrap_err()
            .to_string()
            .contains("claim conflict")
    );
    assert!(
        restarted
            .release_action(&old_execution, stale_time)
            .await
            .unwrap_err()
            .to_string()
            .contains("release conflict")
    );

    let receipt = restarted
        .complete_action(
            &new_execution,
            serde_json::json!({"status":"completed"}),
            stale_time,
        )
        .await
        .unwrap();
    assert!(!receipt.replayed);
}

#[tokio::test]
async fn untrusted_payloads_and_action_inputs_fail_closed() {
    let (_storage, _scope, session_id, service) = fixture("validation").await;
    let now = Utc::now();
    for payload in [
        serde_json::json!({"title": "Unsafe", "html": "<script>bad()</script>"}),
        serde_json::json!({"title": "Unsafe", "url": "https://attacker.invalid"}),
        serde_json::json!({"title": "Unsafe", "access_token": "secret"}),
        serde_json::json!({"title": "Unsafe", "unknown": true}),
    ] {
        let mut request = card_request(None, vec![]);
        request.content_id = Some(format!("unsafe-{}", Uuid::new_v4()));
        request.payload = payload;
        assert!(
            service
                .publish(&session_id, None, request, now)
                .await
                .is_err()
        );
    }

    let published = service
        .publish(
            &session_id,
            None,
            card_request(None, vec![oauth_binding(now)]),
            now,
        )
        .await
        .unwrap();
    assert!(
        service
            .claim_action(
                &session_id,
                &published.bindings[0].binding_id,
                serde_json::json!({"providerId": "attacker"}),
                now,
            )
            .await
            .unwrap_err()
            .to_string()
            .contains("unknown fields")
    );
}

#[tokio::test]
async fn a2ui_payloads_are_structurally_validated_before_persistence() {
    let (_storage, _scope, session_id, service) = fixture("a2ui-validation").await;
    let now = Utc::now();
    let mut valid = card_request(None, Vec::new());
    valid.content_id = Some("a2ui-valid".into());
    valid.mime_type = "application/vnd.a2ui.safe-card+json".into();
    valid.schema_version = "0.8".into();
    valid.payload = serde_json::json!({
        "components": [
            {"type":"text","style":"heading","text":"Connect workspace"},
            {"type":"status","label":"Not connected","tone":"warning"},
            {"type":"field","label":"Provider","value":"Workspace"},
            {"type":"list","items":["Mail","Calendar"]}
        ]
    });
    service
        .publish(&session_id, None, valid.clone(), now)
        .await
        .unwrap();

    for (content_id, schema_version, payload) in [
        (
            "a2ui-unknown-component",
            "0.8",
            serde_json::json!({"components":[{"type":"button","label":"Unsafe"}]}),
        ),
        (
            "a2ui-unknown-field",
            "0.8",
            serde_json::json!({"components":[{"type":"text","text":"Hi","extra":true}]}),
        ),
        (
            "a2ui-unsupported-schema",
            "2",
            serde_json::json!({"components":[{"type":"text","text":"Hi"}]}),
        ),
    ] {
        let mut invalid = valid.clone();
        invalid.content_id = Some(content_id.into());
        invalid.schema_version = schema_version.into();
        invalid.payload = payload;
        assert!(
            service
                .publish(&session_id, None, invalid, now)
                .await
                .is_err()
        );
        assert!(
            service
                .get(&session_id, content_id)
                .await
                .unwrap()
                .is_none()
        );
    }
}

#[tokio::test]
async fn executing_actions_fence_content_updates_and_deletion() {
    let (_storage, _scope, session_id, service) = fixture("execution-fence").await;
    let now = Utc::now();
    let published = service
        .publish(
            &session_id,
            None,
            card_request(None, vec![oauth_binding(now)]),
            now,
        )
        .await
        .unwrap();
    let execution = match service
        .claim_action(
            &session_id,
            &published.bindings[0].binding_id,
            serde_json::json!({}),
            now,
        )
        .await
        .unwrap()
    {
        StructuredActionClaim::Execute(execution) => execution,
        StructuredActionClaim::Replay(_) => panic!("new action unexpectedly replayed"),
    };

    assert!(
        service
            .publish(
                &session_id,
                None,
                card_request(Some(1), Vec::new()),
                now + Duration::seconds(1),
            )
            .await
            .unwrap_err()
            .to_string()
            .contains("action is executing")
    );
    assert!(
        service
            .delete(
                &session_id,
                None,
                "briefing-card",
                1,
                now + Duration::seconds(1),
            )
            .await
            .unwrap_err()
            .to_string()
            .contains("action is executing")
    );

    service
        .complete_action(
            &execution,
            serde_json::json!({"status":"completed"}),
            now + Duration::seconds(2),
        )
        .await
        .unwrap();
    assert_eq!(
        service
            .get(&session_id, "briefing-card")
            .await
            .unwrap()
            .unwrap()
            .revision,
        2
    );
}
