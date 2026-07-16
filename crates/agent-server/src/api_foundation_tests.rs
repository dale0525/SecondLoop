use super::*;
use agent_runtime::calendar::FakeCalendarConnector;
use agent_runtime::calendar_actions::CalendarActionService;
use agent_runtime::calendar_connector_transport::CalendarConnectorTransport;
use agent_runtime::connector::ConnectorRuntime;
use agent_runtime::connector_tools::{ConnectorToolRuntime, EphemeralConnectorContextProvider};
use agent_runtime::contacts::{
    ContactIdentity, ContactRecord, ContactScope, FakeContactsConnector,
};
use agent_runtime::contacts_actions::ContactsActionService;
use agent_runtime::contacts_connector_transport::ContactsConnectorTransport;
use agent_runtime::credential::{CredentialScope, CredentialVault, InMemorySecretStore};
use agent_runtime::credential_sqlite::SqliteCredentialMetadataStore;
use agent_runtime::foundation_actions::MailActionService;
use agent_runtime::mail::{DraftContent, MailAccount, MailAddress, OutgoingBody};
use agent_runtime::mail_connector_transport::MailConnectorTransport;
use agent_runtime::mail_fake::FakeMailConnector;
use agent_runtime::mail_imap_smtp_accounts::{
    ImapSmtpMailAccountManager, ManagedImapSmtpMailConnector, SqliteImapSmtpMailAccountStore,
};
use agent_runtime::prompt_composer::AppPromptConfig;
use agent_runtime::skill::SkillRegistry;
use agent_runtime::skill_catalog::SkillCatalog;
use agent_runtime::skill_manager::SkillManager;
use agent_runtime::tools::RuntimeConfig;
use agent_runtime::turn::{ModelClient, ModelEventStream};
use axum::body::{Body, to_bytes};
use axum::http::{Method, Request, StatusCode, header};
use futures::stream;
use model_gateway::responses::{GatewayEvent, GatewayRequest};
use serde_json::{Value, json};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Duration;
use tower::ServiceExt;

struct MailPreviewModel {
    calls: AtomicUsize,
    draft_id: String,
}

#[async_trait::async_trait]
impl ModelClient for MailPreviewModel {
    async fn stream(&self, request: GatewayRequest) -> anyhow::Result<ModelEventStream> {
        let call = self.calls.fetch_add(1, Ordering::SeqCst);
        let events = if call == 0 {
            let names: Vec<_> = request
                .tools
                .iter()
                .map(|tool| tool.advertised_name())
                .collect();
            assert!(names.contains(&"mail_send_preview"));
            assert!(!names.contains(&"mail_send"));
            assert!(!names.contains(&"connector__agentweave-mail__mail_send"));
            assert!(!names.contains(&"connector__agentweave-mail__mail_send_preview"));
            vec![
                GatewayEvent::ToolCall {
                    call_id: "call-preview".into(),
                    name: "mail_send_preview".into(),
                    legacy_alias_selected: false,
                    arguments: json!({
                        "accountId": "primary",
                        "draftId": self.draft_id,
                        "expectedRevision": 1
                    }),
                },
                GatewayEvent::Completed,
            ]
        } else {
            let result = request
                .input
                .iter()
                .find(|item| item["role"] == "tool")
                .expect("preview tool result must be sent back to the model");
            assert_eq!(result["content"]["data"]["status"], "waiting_approval");
            assert!(result["content"]["data"].get("approval").is_none());
            assert!(result["content"]["data"].get("action").is_none());
            assert!(result["content"]["data"]["preview"].is_object());
            vec![
                GatewayEvent::TextDelta {
                    text: "Waiting for approval.".into(),
                },
                GatewayEvent::Completed,
            ]
        };
        Ok(Box::pin(stream::iter(events.into_iter().map(Ok))))
    }
}

#[tokio::test]
async fn agent_mail_preview_persists_a_session_bound_action_through_server_turns() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let mail = Arc::new(FakeMailConnector::new());
    mail.add_account(test_mail_account()).unwrap();
    let runtime = Arc::new(ConnectorRuntime::new(None, 256 * 1024).unwrap());
    runtime
        .register(
            MailConnectorTransport::descriptor("Fake Mail", true),
            Arc::new(MailConnectorTransport::new(mail.clone())),
        )
        .await
        .unwrap();
    let scope = CredentialScope {
        app_id: "agentweave.default".into(),
        tenant_id: "local".into(),
        user_id: "local-user".into(),
    };
    let context = Arc::new(
        EphemeralConnectorContextProvider::fail_closed(scope.clone(), Duration::from_secs(2))
            .unwrap(),
    );
    let tools = ConnectorToolRuntime::load(runtime, context.clone()).unwrap();
    let draft_id = create_test_draft(&tools, "server-agent-draft").await;
    let actions = MailActionService::new(
        &storage,
        tools.clone(),
        context,
        scope,
        "server-agent-test-v1",
    )
    .await
    .unwrap();
    let skill_manager =
        SkillManager::from_registry_and_catalog(SkillRegistry::empty(), SkillCatalog::empty());
    let root = std::env::temp_dir();
    let state = AppState::new_with_model_app_foundations_and_skill_manager(
        storage,
        MailPreviewModel {
            calls: AtomicUsize::new(0),
            draft_id,
        },
        skill_manager,
        RuntimeConfig::workspace_write(root.clone(), root).without_builtin_tools(),
        AppPromptConfig::default(),
        AppFoundationRuntimes::new(None, None, Some(tools))
            .with_mail_actions(Some(actions.clone())),
    );
    let app = router(Arc::new(state));
    let created = app
        .clone()
        .oneshot(json_request("/sessions", json!({"title": "Mail approval"})))
        .await
        .unwrap();
    let session_id = read_json(created).await["id"].as_str().unwrap().to_string();

    let response = app
        .oneshot(json_request(
            &format!("/sessions/{session_id}/messages"),
            json!({"content": "Send the reviewed draft"}),
        ))
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
    let body = read_json(response).await;
    assert_eq!(
        body["assistant_message"]["content"],
        "Waiting for approval."
    );
    let pending = actions.list_actions().await.unwrap();
    assert_eq!(pending.len(), 1);
    assert_eq!(
        pending[0].approval.binding.session_id.as_deref(),
        Some(session_id.as_str())
    );
    assert_eq!(mail.provider_submission_count(), 0);
}

#[tokio::test]
async fn foundation_mail_approval_api_resumes_exactly_once() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let mail = Arc::new(FakeMailConnector::new());
    mail.add_account(test_mail_account()).unwrap();
    let runtime = Arc::new(ConnectorRuntime::new(None, 256 * 1024).unwrap());
    runtime
        .register(
            MailConnectorTransport::descriptor("Fake Mail", true),
            Arc::new(MailConnectorTransport::new(mail.clone())),
        )
        .await
        .unwrap();
    let scope = CredentialScope {
        app_id: "agentweave.default".into(),
        tenant_id: "local".into(),
        user_id: "local-user".into(),
    };
    let context = Arc::new(
        EphemeralConnectorContextProvider::fail_closed(scope.clone(), Duration::from_secs(2))
            .unwrap(),
    );
    let tools = ConnectorToolRuntime::load(runtime, context.clone()).unwrap();
    let draft_id = create_test_draft(&tools, "api-draft").await;
    let actions = MailActionService::new(&storage, tools.clone(), context, scope, "api-test-v1")
        .await
        .unwrap();
    let app = router(Arc::new(
        AppState::new(storage).with_mail_foundation(tools, actions),
    ));

    let requested = app
        .clone()
        .oneshot(json_request(
            "/foundation/mail/send-approvals",
            json!({
                "accountId": "primary",
                "draftId": draft_id,
                "expectedRevision": 1,
                "idempotencyKey": "api-send-1",
                "sessionId": null
            }),
        ))
        .await
        .unwrap();
    assert_eq!(requested.status(), StatusCode::OK);
    let requested = read_json(requested).await;
    let approval_id = requested["approval"]["approval_id"].as_str().unwrap();

    let listed = app
        .clone()
        .oneshot(
            Request::builder()
                .uri("/foundation/actions")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(listed.status(), StatusCode::OK);
    assert_eq!(read_json(listed).await.as_array().unwrap().len(), 1);

    for _ in 0..2 {
        let resolved = app
            .clone()
            .oneshot(json_request(
                &format!("/foundation/actions/{approval_id}"),
                json!({"decision": "approve_once"}),
            ))
            .await
            .unwrap();
        assert_eq!(resolved.status(), StatusCode::OK);
        assert_eq!(read_json(resolved).await["action"]["status"], "succeeded");
    }
    assert_eq!(mail.provider_submission_count(), 1);
    assert_eq!(mail.logical_delivery_count(), 1);
}

fn test_mail_account() -> MailAccount {
    MailAccount {
        id: "primary".into(),
        display_name: "Work Mail".into(),
        primary_address: MailAddress {
            name: Some("Local User".into()),
            address: "local@example.test".into(),
        },
        addresses: Vec::new(),
        provider_reference: None,
    }
}

async fn create_test_draft(tools: &ConnectorToolRuntime, call_id: &str) -> String {
    let draft = tools
        .execute_trusted_host_action(
            "mail_draft_create",
            call_id,
            serde_json::to_value(agent_runtime::mail::CreateDraftRequest {
                account_id: "primary".into(),
                content: DraftContent {
                    to: vec![MailAddress {
                        name: Some("Recipient".into()),
                        address: "recipient@example.test".into(),
                    }],
                    cc: Vec::new(),
                    bcc: Vec::new(),
                    subject: "Approval API".into(),
                    body: OutgoingBody {
                        plain_text: "Please review".into(),
                        html: None,
                    },
                    attachments: Vec::new(),
                    reply_context: None,
                    forward_context: None,
                },
            })
            .unwrap(),
        )
        .await
        .unwrap();
    draft["output"]["id"].as_str().unwrap().to_string()
}

#[tokio::test]
async fn foundation_calendar_approval_api_resumes_exactly_once() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let scope = CredentialScope {
        app_id: "agentweave.default".into(),
        tenant_id: "local".into(),
        user_id: "local-user".into(),
    };
    let runtime = Arc::new(ConnectorRuntime::new(None, 256 * 1024).unwrap());
    runtime
        .register(
            CalendarConnectorTransport::descriptor("Fake Calendar", true),
            Arc::new(
                CalendarConnectorTransport::new(
                    Arc::new(FakeCalendarConnector::default()),
                    scope.clone(),
                )
                .unwrap(),
            ),
        )
        .await
        .unwrap();
    let context = Arc::new(
        EphemeralConnectorContextProvider::fail_closed(scope.clone(), Duration::from_secs(2))
            .unwrap(),
    );
    let tools = ConnectorToolRuntime::load(runtime, context.clone()).unwrap();
    let actions =
        CalendarActionService::new(&storage, tools.clone(), context, scope, "api-test-v1")
            .await
            .unwrap();
    let app = router(Arc::new(
        AppState::new(storage).with_calendar_foundation(tools, actions),
    ));
    let start = chrono::Utc::now() + chrono::Duration::hours(1);
    let requested = app
        .clone()
        .oneshot(json_request(
            "/foundation/calendar/create-approvals",
            json!({
                "accountId": "primary",
                "content": {
                    "calendarId": "primary",
                    "title": "Planning",
                    "description": null,
                    "start": start,
                    "end": start + chrono::Duration::hours(1),
                    "timezone": "Asia/Shanghai",
                    "location": null,
                    "attendees": [],
                    "recurrence": null
                },
                "idempotencyKey": "api-calendar-create-1",
                "sessionId": null
            }),
        ))
        .await
        .unwrap();
    assert_eq!(requested.status(), StatusCode::OK);
    let requested = read_json(requested).await;
    let approval_id = requested["approval"]["approval_id"].as_str().unwrap();

    for _ in 0..2 {
        let resolved = app
            .clone()
            .oneshot(json_request(
                &format!("/foundation/actions/{approval_id}"),
                json!({"decision": "approve_once"}),
            ))
            .await
            .unwrap();
        assert_eq!(resolved.status(), StatusCode::OK);
        assert_eq!(read_json(resolved).await["action"]["status"], "succeeded");
    }

    let listed = app
        .oneshot(
            Request::builder()
                .uri("/foundation/actions")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(listed.status(), StatusCode::OK);
    assert_eq!(read_json(listed).await.as_array().unwrap().len(), 1);
}

#[tokio::test]
async fn foundation_contacts_approval_api_resumes_exactly_once() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let scope = CredentialScope {
        app_id: "agentweave.default".into(),
        tenant_id: "local".into(),
        user_id: "local-user".into(),
    };
    let contact = ContactRecord {
        id: "contact-1".into(),
        display_name: "Alex Chen".into(),
        identities: vec![ContactIdentity {
            kind: "email".into(),
            value: "alex@example.test".into(),
            label: None,
        }],
        organization: None,
        relationship: None,
        version: 1,
        provider_id: Some("provider-1".into()),
        updated_at: chrono::Utc::now(),
    };
    let contacts = Arc::new(FakeContactsConnector::default());
    contacts
        .seed(
            ContactScope {
                app_id: scope.app_id.clone(),
                tenant_id: scope.tenant_id.clone(),
                user_id: scope.user_id.clone(),
                account_id: "primary".into(),
            },
            contact.clone(),
        )
        .unwrap();
    let runtime = Arc::new(ConnectorRuntime::new(None, 256 * 1024).unwrap());
    runtime
        .register(
            ContactsConnectorTransport::descriptor("Fake Contacts", true),
            Arc::new(ContactsConnectorTransport::new(contacts, scope.clone()).unwrap()),
        )
        .await
        .unwrap();
    let context = Arc::new(
        EphemeralConnectorContextProvider::fail_closed(scope.clone(), Duration::from_secs(2))
            .unwrap(),
    );
    let tools = ConnectorToolRuntime::load(runtime, context.clone()).unwrap();
    let actions =
        ContactsActionService::new(&storage, tools.clone(), context, scope, "api-test-v1")
            .await
            .unwrap();
    let app = router(Arc::new(
        AppState::new(storage).with_contacts_foundation(tools, actions),
    ));
    let requested = app
        .clone()
        .oneshot(json_request(
            "/foundation/contacts/update-approvals",
            json!({
                "accountId": "primary",
                "contactId": "contact-1",
                "expectedVersion": 1,
                "replacement": {
                    "id": "ignored",
                    "displayName": "Alex Chen",
                    "identities": [{
                        "kind": "email",
                        "value": "new@example.test",
                        "label": "work"
                    }],
                    "organization": null,
                    "relationship": null,
                    "version": 1,
                    "providerId": null,
                    "updatedAt": contact.updated_at
                },
                "idempotencyKey": "api-contact-update-1",
                "sessionId": null
            }),
        ))
        .await
        .unwrap();
    assert_eq!(requested.status(), StatusCode::OK);
    let requested = read_json(requested).await;
    let approval_id = requested["approval"]["approval_id"].as_str().unwrap();

    for _ in 0..2 {
        let resolved = app
            .clone()
            .oneshot(json_request(
                &format!("/foundation/actions/{approval_id}"),
                json!({"decision": "approve_once"}),
            ))
            .await
            .unwrap();
        assert_eq!(resolved.status(), StatusCode::OK);
        let resolved = read_json(resolved).await;
        assert_eq!(resolved["action"]["status"], "succeeded");
        if let Some(output) = resolved["connectorResult"]["output"].as_object() {
            assert_eq!(output["providerId"], "provider-1");
        }
    }
}

#[tokio::test]
async fn trusted_mail_configuration_api_cruds_without_returning_secrets() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let manager = mail_account_manager(&storage).await;
    let app = router(Arc::new(
        AppState::new(storage).with_mail_account_manager(manager),
    ));
    let first_password = "first-credential-marker";
    let created = app
        .clone()
        .oneshot(json_request_with_method(
            Method::PUT,
            "/foundation/mail/account-configurations/primary",
            mail_configuration(first_password, "first@example.test"),
        ))
        .await
        .unwrap();
    assert_eq!(created.status(), StatusCode::OK);
    let created = read_text(created).await;
    assert!(!created.contains(first_password));
    assert!(!created.contains("password"));
    assert_eq!(
        serde_json::from_str::<Value>(&created).unwrap()["credentialConfigured"],
        true
    );

    let second_password = "rotated-credential-marker";
    let updated = app
        .clone()
        .oneshot(json_request_with_method(
            Method::PUT,
            "/foundation/mail/account-configurations/primary",
            mail_configuration(second_password, "updated@example.test"),
        ))
        .await
        .unwrap();
    assert_eq!(updated.status(), StatusCode::OK);
    let updated = read_text(updated).await;
    assert!(!updated.contains(second_password));
    assert_eq!(
        serde_json::from_str::<Value>(&updated).unwrap()["username"],
        "updated@example.test"
    );

    let deleted = app
        .clone()
        .oneshot(
            Request::builder()
                .method(Method::DELETE)
                .uri("/foundation/mail/account-configurations/primary")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(deleted.status(), StatusCode::OK);
    assert_eq!(read_json(deleted).await["deleted"], true);
    let missing = app
        .oneshot(
            Request::builder()
                .uri("/foundation/mail/account-configurations/primary")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(missing.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn mail_configuration_api_rejects_insecure_remote_hosts_without_echoing_password() {
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let app = router(Arc::new(
        AppState::new(storage.clone())
            .with_mail_account_manager(mail_account_manager(&storage).await),
    ));
    let password = "rejected-credential-marker";
    let mut body = mail_configuration(password, "user@example.test");
    body["imapTls"] = json!("none");
    let response = app
        .oneshot(json_request_with_method(
            Method::PUT,
            "/foundation/mail/account-configurations/primary",
            body,
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    assert!(!read_text(response).await.contains(password));
}

async fn mail_account_manager(storage: &Storage) -> Arc<ImapSmtpMailAccountManager> {
    let metadata = SqliteCredentialMetadataStore::from_storage(storage)
        .await
        .unwrap();
    Arc::new(ImapSmtpMailAccountManager::new(
        SqliteImapSmtpMailAccountStore::from_storage(storage)
            .await
            .unwrap(),
        Arc::new(CredentialVault::new_persistent(
            Arc::new(InMemorySecretStore::default()),
            metadata,
        )),
        Arc::new(ManagedImapSmtpMailConnector::new()),
    ))
}

fn mail_configuration(password: &str, username: &str) -> Value {
    json!({
        "displayName": "Primary Mail",
        "primaryName": "Local User",
        "primaryAddress": "user@example.test",
        "username": username,
        "password": password,
        "imapHost": "imap.example.test",
        "imapPort": 993,
        "imapTls": "implicit",
        "smtpHost": "smtp.example.test",
        "smtpPort": 587,
        "smtpTls": "start_tls",
        "archiveMailbox": "Archive",
        "sentMailbox": "Sent",
        "draftsMailbox": "Drafts",
        "trashMailbox": "Trash",
        "allowInsecureLocalhost": false
    })
}

fn json_request(uri: &str, body: Value) -> Request<Body> {
    json_request_with_method(Method::POST, uri, body)
}

fn json_request_with_method(method: Method, uri: &str, body: Value) -> Request<Body> {
    Request::builder()
        .method(method)
        .uri(uri)
        .header(header::CONTENT_TYPE, "application/json")
        .body(Body::from(body.to_string()))
        .unwrap()
}

async fn read_json(response: axum::response::Response) -> Value {
    serde_json::from_str(&read_text(response).await).unwrap()
}

async fn read_text(response: axum::response::Response) -> String {
    let bytes = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    String::from_utf8(bytes.to_vec()).unwrap()
}
