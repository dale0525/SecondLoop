use agent_runtime::{
    credential::{
        ConnectorAccount, CredentialScope, CredentialVault, InMemorySecretStore,
        ProviderCredential, SecretId, SecretMaterial, SecretStore,
    },
    mail::{
        ApprovedSendRequest, CreateDraftRequest, DeliveryState, DraftContent, MailAccount,
        MailAccountActionRequest, MailAccountState, MailAddress, MailConnector, MailSearch,
        OutgoingBody, PageRequest, PreviewSendRequest, ProviderReference, SearchMessagesRequest,
    },
    mail_imap_smtp::{ImapSmtpMailConfig, ImapSmtpMailConnector, MailTlsMode},
};
use chrono::{Duration as ChronoDuration, Utc};
use std::{collections::BTreeSet, env, sync::Arc, time::Duration};
use tokio::time::sleep;
use uuid::Uuid;

const CONNECTOR_ID: &str = "agentweave.connector.mail.imap-smtp";
const ACCOUNT_ID: &str = "live-primary";

struct LiveMailSettings {
    from_address: String,
    imap_host: String,
    imap_port: u16,
    inbox: String,
    password: String,
    smtp_host: String,
    smtp_port: u16,
    smtp_tls: MailTlsMode,
    username: String,
}

impl LiveMailSettings {
    fn from_environment() -> Result<Self, String> {
        if required("AGENTWEAVE_LIVE_MAIL_ENABLED")? != "1" {
            return Err("AGENTWEAVE_LIVE_MAIL_ENABLED must equal 1".into());
        }
        let from_address = required("AGENTWEAVE_LIVE_MAIL_FROM_ADDRESS")?;
        let to_address = required("AGENTWEAVE_LIVE_MAIL_TO_ADDRESS")?;
        if !from_address.eq_ignore_ascii_case(&to_address) {
            return Err(
                "live Mail smoke requires the sender and recipient to be the same account".into(),
            );
        }
        Ok(Self {
            from_address,
            imap_host: required("AGENTWEAVE_LIVE_MAIL_IMAP_HOST")?,
            imap_port: port("AGENTWEAVE_LIVE_MAIL_IMAP_PORT")?,
            inbox: optional("AGENTWEAVE_LIVE_MAIL_INBOX", "INBOX"),
            password: required("AGENTWEAVE_LIVE_MAIL_PASSWORD")?,
            smtp_host: required("AGENTWEAVE_LIVE_MAIL_SMTP_HOST")?,
            smtp_port: port("AGENTWEAVE_LIVE_MAIL_SMTP_PORT")?,
            smtp_tls: smtp_tls_mode()?,
            username: required("AGENTWEAVE_LIVE_MAIL_USERNAME")?,
        })
    }
}

fn required(name: &str) -> Result<String, String> {
    env::var(name)
        .ok()
        .filter(|value| !value.trim().is_empty())
        .ok_or_else(|| format!("{name} is required"))
}

fn optional(name: &str, fallback: &str) -> String {
    env::var(name)
        .ok()
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| fallback.to_string())
}

fn port(name: &str) -> Result<u16, String> {
    required(name)?
        .parse::<u16>()
        .ok()
        .filter(|value| *value > 0)
        .ok_or_else(|| format!("{name} must be a valid non-zero port"))
}

fn smtp_tls_mode() -> Result<MailTlsMode, String> {
    match optional("AGENTWEAVE_LIVE_MAIL_SMTP_TLS", "start_tls").as_str() {
        "implicit" => Ok(MailTlsMode::Implicit),
        "start_tls" => Ok(MailTlsMode::StartTls),
        _ => Err("AGENTWEAVE_LIVE_MAIL_SMTP_TLS must be implicit or start_tls".into()),
    }
}

fn scope() -> CredentialScope {
    CredentialScope {
        app_id: "org.agentweave.live-mail-smoke".into(),
        tenant_id: "dedicated-test".into(),
        user_id: "test-account".into(),
    }
}

async fn connector(settings: LiveMailSettings) -> Result<ImapSmtpMailConnector, String> {
    let account_scope = scope();
    let secret_id = SecretId::parse("live.mail.password").map_err(|_| "secret ID is invalid")?;
    let store = Arc::new(InMemorySecretStore::default());
    store
        .save(
            &account_scope,
            &secret_id,
            SecretMaterial::new(settings.password).map_err(|_| "live Mail password is invalid")?,
        )
        .await
        .map_err(|_| "live Mail credential could not be stored")?;
    let vault = Arc::new(CredentialVault::new(store));
    let credential_id = "live-mail-primary";
    let allowed_scopes = BTreeSet::from(["mail.message.read".into(), "mail.message.send".into()]);
    vault
        .register_provider_credential(
            &account_scope,
            ProviderCredential {
                access_secret_id: secret_id.clone(),
                credential_id: credential_id.into(),
                expires_at: None,
                granted_scopes: allowed_scopes.clone(),
                provider_id: "imap-smtp".into(),
                provider_subject: settings.username.clone(),
                refresh_secret_id: None,
                revoked_at: None,
            },
        )
        .map_err(|_| "live Mail credential could not be registered")?;
    vault
        .register_account(ConnectorAccount {
            account_id: ACCOUNT_ID.into(),
            allowed_scopes,
            connector_id: CONNECTOR_ID.into(),
            credential_id: credential_id.into(),
            scope: account_scope.clone(),
        })
        .map_err(|_| "live Mail account could not be registered")?;
    let account = MailAccount {
        addresses: vec![],
        display_name: "AgentWeave Live Mail Smoke".into(),
        id: ACCOUNT_ID.into(),
        primary_address: MailAddress {
            address: settings.from_address,
            name: None,
        },
        provider_reference: Some(ProviderReference {
            id: ACCOUNT_ID.into(),
            provider: "imap-smtp".into(),
        }),
    };
    ImapSmtpMailConnector::new(
        ImapSmtpMailConfig {
            account,
            allow_insecure_localhost: false,
            archive_mailbox: None,
            connect_timeout_seconds: 30,
            credential_scope: account_scope,
            credential_secret_id: secret_id,
            drafts_mailbox: None,
            imap_host: settings.imap_host,
            imap_port: settings.imap_port,
            imap_tls: MailTlsMode::Implicit,
            operation_timeout_seconds: 60,
            sent_mailbox: None,
            smtp_host: settings.smtp_host,
            smtp_port: settings.smtp_port,
            smtp_tls: settings.smtp_tls,
            trash_mailbox: None,
            username: settings.username,
        },
        vault,
    )
    .map_err(|_| "live Mail connector configuration is invalid".into())
}

#[tokio::test]
#[ignore = "requires dedicated live IMAP/SMTP credentials"]
async fn live_imap_smtp_round_trip() {
    let settings = LiveMailSettings::from_environment()
        .unwrap_or_else(|message| panic!("live Mail smoke configuration failed: {message}"));
    let inbox = settings.inbox.clone();
    let sender = settings.from_address.clone();
    let connector = connector(settings)
        .await
        .expect("live Mail connector initialization failed");

    let status = connector
        .request_connect(MailAccountActionRequest {
            account_id: ACCOUNT_ID.into(),
        })
        .await
        .expect("live IMAP authentication failed");
    assert_eq!(status.state, MailAccountState::Connected);
    let mailboxes = connector
        .list_mailboxes(ACCOUNT_ID)
        .await
        .expect("live IMAP mailbox listing failed");
    assert!(
        mailboxes
            .iter()
            .any(|mailbox| mailbox.name.eq_ignore_ascii_case(&inbox)),
        "configured live IMAP inbox was not found"
    );

    let run_id = Uuid::new_v4();
    let subject = format!("AgentWeave live connector smoke {run_id}");
    let draft = connector
        .create_draft(CreateDraftRequest {
            account_id: ACCOUNT_ID.into(),
            content: DraftContent {
                attachments: vec![],
                bcc: vec![],
                body: OutgoingBody {
                    html: None,
                    plain_text: format!("Dedicated AgentWeave connector smoke {run_id}"),
                },
                cc: vec![],
                forward_context: None,
                reply_context: None,
                subject: subject.clone(),
                to: vec![MailAddress {
                    address: sender,
                    name: None,
                }],
            },
        })
        .await
        .expect("live Mail draft creation failed");
    let preview = connector
        .preview_send(PreviewSendRequest {
            account_id: ACCOUNT_ID.into(),
            draft_id: draft.id,
            expected_revision: draft.revision,
            idempotency_key: format!("live-smoke-{run_id}"),
        })
        .await
        .expect("live Mail send preview failed");
    let receipt = connector
        .send_approved(ApprovedSendRequest {
            approval: preview.approval_grant(format!("live-smoke-approval-{run_id}")),
            preview_id: preview.id.clone(),
        })
        .await
        .expect("live SMTP submission failed");
    assert_eq!(receipt.state, DeliveryState::Delivered);

    let after = Utc::now() - ChronoDuration::minutes(10);
    for attempt in 0..12 {
        let messages = connector
            .search_messages(SearchMessagesRequest {
                account_id: ACCOUNT_ID.into(),
                mailbox_id: Some(inbox.clone()),
                page: PageRequest {
                    cursor: None,
                    limit: 20,
                },
                search: MailSearch {
                    after: Some(after),
                    subject: Some(subject.clone()),
                    ..MailSearch::default()
                },
            })
            .await
            .expect("live IMAP delivery lookup failed");
        if messages
            .items
            .iter()
            .any(|message| message.internet_message_id == preview.internet_message_id)
        {
            return;
        }
        if attempt < 11 {
            sleep(Duration::from_secs(5)).await;
        }
    }
    panic!("live Mail message was not observed through IMAP before the smoke timeout");
}
