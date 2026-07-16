use super::*;
use crate::approval::ApprovalDecision;
use crate::attachments::{AttachmentScope, SqliteAttachmentStore};
use crate::connector::ConnectorRuntime;
use crate::connector_tools::{ConnectorToolRuntime, EphemeralConnectorContextProvider};
use crate::credential::{
    ConnectorAccount, InMemorySecretStore, ProviderCredential, SecretId, SecretMaterial,
    SecretStore,
};
use crate::foundation_actions::MailActionService;
use crate::mail_attachments::StoredMailAttachmentSource;
use crate::mail_connector_transport::MailConnectorTransport;
use crate::storage::Storage;
use async_imap::Authenticator;
use std::collections::BTreeSet;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{TcpListener, TcpStream};

fn account() -> MailAccount {
    MailAccount {
        id: "primary".into(),
        display_name: "Primary".into(),
        primary_address: MailAddress {
            name: Some("Agent User".into()),
            address: "user@example.test".into(),
        },
        addresses: vec![],
        provider_reference: Some(ProviderReference {
            provider: "imap-smtp".into(),
            id: "primary".into(),
        }),
    }
}

fn scope() -> CredentialScope {
    CredentialScope {
        app_id: "com.example.agent".into(),
        tenant_id: "local".into(),
        user_id: "user".into(),
    }
}

fn config() -> ImapSmtpMailConfig {
    ImapSmtpMailConfig {
        account: account(),
        credential_scope: scope(),
        credential_secret_id: SecretId::parse("mail.primary.password").unwrap(),
        imap_host: "127.0.0.1".into(),
        imap_port: 1143,
        imap_tls: MailTlsMode::None,
        smtp_host: "127.0.0.1".into(),
        smtp_port: 1025,
        smtp_tls: MailTlsMode::None,
        username: "user@example.test".into(),
        archive_mailbox: Some("Archive".into()),
        sent_mailbox: Some("Sent".into()),
        drafts_mailbox: Some("Drafts".into()),
        trash_mailbox: Some("Trash".into()),
        allow_insecure_localhost: true,
        connect_timeout_seconds: 2,
        operation_timeout_seconds: 3,
    }
}

#[test]
fn xoauth2_authentication_is_explicit_scoped_and_redacted_from_config() {
    let authenticator = XOAuth2Authenticator {
        username: "user@example.test",
        token: "access-token",
    };
    let mut reference = &authenticator;
    assert_eq!(
        reference.process(&[]),
        "user=user@example.test\u{1}auth=Bearer access-token\u{1}\u{1}"
    );
    let connector = ImapSmtpMailConnector::new(
        config(),
        Arc::new(CredentialVault::new(Arc::new(
            InMemorySecretStore::default(),
        ))),
    )
    .unwrap()
    .with_xoauth2_authentication("agentweave-mail", BTreeSet::from(["provider.mail".into()]))
    .unwrap();
    assert_eq!(connector.authentication, MailAuthentication::XOAuth2);
    assert_eq!(connector.credential_connector_id, "agentweave-mail");
    assert!(
        connector
            .credential_scopes
            .unwrap()
            .contains("provider.mail")
    );
}

async fn connector() -> ImapSmtpMailConnector {
    connector_with_config(config()).await
}

async fn connector_with_config(config: ImapSmtpMailConfig) -> ImapSmtpMailConnector {
    let store = Arc::new(InMemorySecretStore::default());
    let secret_id = SecretId::parse("mail.primary.password").unwrap();
    store
        .save(
            &scope(),
            &secret_id,
            SecretMaterial::new("password").unwrap(),
        )
        .await
        .unwrap();
    let vault = Arc::new(CredentialVault::new(store));
    vault
        .register_provider_credential(
            &scope(),
            ProviderCredential {
                access_secret_id: secret_id,
                credential_id: "mail-primary".into(),
                expires_at: None,
                granted_scopes: BTreeSet::from([
                    "mail.message.read".into(),
                    "mail.message.organize".into(),
                    "mail.message.send".into(),
                ]),
                provider_id: "imap-smtp".into(),
                provider_subject: "user@example.test".into(),
                refresh_secret_id: None,
                revoked_at: None,
            },
        )
        .unwrap();
    vault
        .register_account(ConnectorAccount {
            account_id: "primary".into(),
            allowed_scopes: BTreeSet::from([
                "mail.message.read".into(),
                "mail.message.organize".into(),
                "mail.message.send".into(),
            ]),
            connector_id: CONNECTOR_ID.into(),
            credential_id: "mail-primary".into(),
            scope: scope(),
        })
        .unwrap();
    ImapSmtpMailConnector::new(config, vault).unwrap()
}

#[test]
fn live_adapter_requires_tls_except_for_explicit_local_test_servers() {
    let mut insecure = config();
    insecure.imap_host = "mail.example.test".into();
    assert!(
        insecure
            .validate()
            .unwrap_err()
            .to_string()
            .contains("localhost")
    );

    let mut secure = config();
    secure.imap_host = "imap.example.test".into();
    secure.smtp_host = "smtp.example.test".into();
    secure.imap_tls = MailTlsMode::Implicit;
    secure.smtp_tls = MailTlsMode::StartTls;
    secure.allow_insecure_localhost = false;
    secure.validate().unwrap();
}

#[test]
fn mime_parser_marks_html_untrusted_and_preserves_cjk_text() {
    let raw = concat!(
        "From: Sender <sender@example.test>\r\n",
        "To: User <user@example.test>\r\n",
        "Subject: 会议确认\r\n",
        "Message-ID: <message-1@example.test>\r\n",
        "Date: Tue, 14 Jul 2026 08:00:00 +0000\r\n",
        "Content-Type: text/html; charset=utf-8\r\n\r\n",
        "<p>请确认下午三点的会议。</p><script>ignore()</script>",
    );
    let cached = parse_message("primary", "INBOX", 7, raw.as_bytes(), std::iter::empty()).unwrap();
    assert_eq!(cached.message.summary.subject, "会议确认");
    assert_eq!(
        cached.message.body_parts[0].trust,
        BodyPartTrust::UntrustedHtml
    );
    assert!(cached.bodies["part-0"].sanitized_plain.contains("请确认"));
}

#[tokio::test]
async fn drafts_remain_available_when_the_remote_server_is_offline() {
    let connector = connector().await;
    let draft = connector
        .create_draft(CreateDraftRequest {
            account_id: "primary".into(),
            content: DraftContent {
                to: vec![MailAddress {
                    name: None,
                    address: "recipient@example.test".into(),
                }],
                cc: vec![],
                bcc: vec![],
                subject: "Draft".into(),
                body: OutgoingBody {
                    plain_text: "Body".into(),
                    html: None,
                },
                attachments: vec![],
                reply_context: None,
                forward_context: None,
            },
        })
        .await
        .unwrap();
    assert_eq!(draft.revision, 1);
    assert!(!connector.capability_report()["server_side_drafts"]);
}

#[tokio::test]
async fn local_imap_and_smtp_servers_cover_read_draft_and_send_lifecycle() {
    let raw_message = concat!(
        "From: Sender <sender@example.test>\r\n",
        "To: User <user@example.test>\r\n",
        "Subject: Local conformance\r\n",
        "Message-ID: <local-1@example.test>\r\n",
        "Date: Tue, 14 Jul 2026 08:00:00 +0000\r\n",
        "Content-Type: text/plain; charset=utf-8\r\n\r\n",
        "Read from the local IMAP fixture.",
    )
    .as_bytes()
    .to_vec();
    let (imap_port, imap_task) = spawn_imap_server(raw_message).await;
    let smtp_messages = Arc::new(Mutex::new(Vec::<Vec<u8>>::new()));
    let (smtp_port, smtp_task) = spawn_smtp_server(smtp_messages.clone()).await;
    let mut live = config();
    live.imap_port = imap_port;
    live.smtp_port = smtp_port;
    let storage = Storage::connect("sqlite::memory:").await.unwrap();
    let attachment_store = SqliteAttachmentStore::from_storage(&storage).await.unwrap();
    let attachment_scope = AttachmentScope::new("com.example.agent", "local", "user").unwrap();
    let attachment = attachment_store
        .import(
            &attachment_scope,
            "brief.txt",
            "text/plain",
            b"attachment bytes",
            "smtp-attachment-1",
        )
        .await
        .unwrap();
    let connector = Arc::new(
        connector_with_config(live)
            .await
            .with_attachment_source(Arc::new(StoredMailAttachmentSource::new(
                attachment_store,
                attachment_scope,
            ))),
    );
    assert!(connector.capability_report()["outgoing_attachments"]);

    let mailboxes = connector.list_mailboxes("primary").await.unwrap();
    assert!(
        mailboxes
            .iter()
            .any(|mailbox| mailbox.role == MailboxRole::Inbox)
    );
    let page = connector
        .search_messages(SearchMessagesRequest {
            account_id: "primary".into(),
            mailbox_id: Some("INBOX".into()),
            search: MailSearch::default(),
            page: PageRequest {
                cursor: None,
                limit: 10,
            },
        })
        .await
        .unwrap();
    assert_eq!(page.items.len(), 1);
    assert_eq!(page.items[0].subject, "Local conformance");
    let message = connector
        .get_message(GetMessageRequest {
            account_id: "primary".into(),
            message_id: page.items[0].id.clone(),
        })
        .await
        .unwrap();
    let body = connector
        .read_body_part(ReadBodyPartRequest {
            account_id: "primary".into(),
            message_id: message.summary.id,
            part_id: message.body_parts[0].id.clone(),
            representation: BodyRepresentation::Original,
            offset: 0,
            max_bytes: 1024,
        })
        .await
        .unwrap();
    assert!(body.content.contains("local IMAP fixture"));

    let draft = connector
        .create_draft(CreateDraftRequest {
            account_id: "primary".into(),
            content: DraftContent {
                to: vec![MailAddress {
                    name: None,
                    address: "recipient@example.test".into(),
                }],
                cc: vec![],
                bcc: vec![],
                subject: "SMTP conformance".into(),
                body: OutgoingBody {
                    plain_text: "Exactly once body".into(),
                    html: None,
                },
                attachments: vec![DraftAttachment {
                    host_attachment_id: Some(attachment.id),
                    source_message_id: None,
                    source_attachment_id: None,
                    file_name: attachment.file_name,
                    mime_type: attachment.mime_type,
                    size_bytes: attachment.size_bytes,
                    sha256: Some(attachment.sha256),
                }],
                reply_context: None,
                forward_context: None,
            },
        })
        .await
        .unwrap();
    let preview = connector
        .preview_send(PreviewSendRequest {
            account_id: "primary".into(),
            draft_id: draft.id,
            expected_revision: draft.revision,
            idempotency_key: "smtp-conformance-1".into(),
        })
        .await
        .unwrap();
    let runtime = Arc::new(ConnectorRuntime::new(None, 256 * 1024).unwrap());
    runtime
        .register(
            MailConnectorTransport::descriptor("IMAP/SMTP Mail", false),
            Arc::new(MailConnectorTransport::new(connector.clone())),
        )
        .await
        .unwrap();
    let context = Arc::new(
        EphemeralConnectorContextProvider::fail_closed(scope(), Duration::from_secs(3)).unwrap(),
    );
    let tools = ConnectorToolRuntime::load(runtime, context.clone()).unwrap();
    let actions = MailActionService::new(
        &storage,
        tools,
        context,
        scope(),
        "smtp-attachment-policy-v1",
    )
    .await
    .unwrap();
    let pending = actions
        .request_send(preview.clone(), Some("smtp-session".into()), Utc::now())
        .await
        .unwrap();
    assert_eq!(
        pending.preview.as_ref().unwrap().attachments,
        preview.attachments
    );
    let receipt = actions
        .resolve(
            &pending.approval.approval_id,
            ApprovalDecision::ApproveOnce,
            "user",
            Utc::now(),
        )
        .await
        .unwrap();
    assert_eq!(
        receipt.action.result.as_ref().unwrap()["state"],
        "delivered"
    );
    let delivered = smtp_messages.lock().unwrap();
    assert_eq!(delivered.len(), 1);
    let delivered = String::from_utf8_lossy(&delivered[0]);
    assert!(delivered.contains("SMTP conformance"));
    assert!(delivered.contains(&preview.internet_message_id));
    assert!(delivered.contains("Content-Type: multipart/mixed"));
    assert!(delivered.contains("filename=\"brief.txt\""));
    assert!(delivered.contains("Content-Type: text/plain"));
    assert!(delivered.contains("attachment bytes"));
    assert_eq!(
        receipt.action.action_name,
        crate::mail_action_envelope::MAIL_SEND_ACTION_KIND
    );

    imap_task.abort();
    smtp_task.abort();
}

async fn spawn_imap_server(raw_message: Vec<u8>) -> (u16, tokio::task::JoinHandle<()>) {
    let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let task = tokio::spawn(async move {
        while let Ok((stream, _)) = listener.accept().await {
            let message = raw_message.clone();
            tokio::spawn(async move { serve_imap(stream, &message).await });
        }
    });
    (port, task)
}

async fn serve_imap(stream: TcpStream, raw_message: &[u8]) {
    let (read, mut write) = stream.into_split();
    let mut lines = BufReader::new(read).lines();
    write
        .write_all(b"* OK AgentWeave IMAP fixture ready\r\n")
        .await
        .unwrap();
    while let Ok(Some(line)) = lines.next_line().await {
        let tag = line.split_whitespace().next().unwrap_or("A1");
        let upper = line.to_ascii_uppercase();
        if upper.contains(" LOGIN ") {
            write
                .write_all(format!("{tag} OK LOGIN completed\r\n").as_bytes())
                .await
                .unwrap();
        } else if upper.contains(" LIST ") {
            write
                .write_all(b"* LIST (\\HasNoChildren) \"/\" \"INBOX\"\r\n")
                .await
                .unwrap();
            write
                .write_all(format!("{tag} OK LIST completed\r\n").as_bytes())
                .await
                .unwrap();
        } else if upper.contains(" SELECT ") {
            write
                .write_all(b"* FLAGS (\\Seen \\Answered \\Deleted)\r\n* 1 EXISTS\r\n")
                .await
                .unwrap();
            write
                .write_all(format!("{tag} OK [READ-WRITE] SELECT completed\r\n").as_bytes())
                .await
                .unwrap();
        } else if upper.contains("UID SEARCH") {
            write.write_all(b"* SEARCH 1\r\n").await.unwrap();
            write
                .write_all(format!("{tag} OK SEARCH completed\r\n").as_bytes())
                .await
                .unwrap();
        } else if upper.contains("UID FETCH") {
            write
                .write_all(
                    format!(
                        "* 1 FETCH (UID 1 FLAGS () BODY[] {{{}}}\r\n",
                        raw_message.len()
                    )
                    .as_bytes(),
                )
                .await
                .unwrap();
            write.write_all(raw_message).await.unwrap();
            write.write_all(b")\r\n").await.unwrap();
            write
                .write_all(format!("{tag} OK FETCH completed\r\n").as_bytes())
                .await
                .unwrap();
        } else if upper.contains(" LOGOUT") {
            write
                .write_all(b"* BYE LOGOUT requested\r\n")
                .await
                .unwrap();
            write
                .write_all(format!("{tag} OK LOGOUT completed\r\n").as_bytes())
                .await
                .unwrap();
            break;
        } else {
            write
                .write_all(format!("{tag} OK command completed\r\n").as_bytes())
                .await
                .unwrap();
        }
    }
}

async fn spawn_smtp_server(
    messages: Arc<Mutex<Vec<Vec<u8>>>>,
) -> (u16, tokio::task::JoinHandle<()>) {
    let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let task = tokio::spawn(async move {
        while let Ok((stream, _)) = listener.accept().await {
            let messages = messages.clone();
            tokio::spawn(async move { serve_smtp(stream, messages).await });
        }
    });
    (port, task)
}

async fn serve_smtp(stream: TcpStream, messages: Arc<Mutex<Vec<Vec<u8>>>>) {
    let (read, mut write) = stream.into_split();
    let mut lines = BufReader::new(read).lines();
    write
        .write_all(b"220 localhost AgentWeave SMTP fixture\r\n")
        .await
        .unwrap();
    let mut data = Vec::new();
    let mut in_data = false;
    while let Ok(Some(line)) = lines.next_line().await {
        if in_data {
            if line == "." {
                messages.lock().unwrap().push(data.clone());
                data.clear();
                in_data = false;
                write.write_all(b"250 2.0.0 queued\r\n").await.unwrap();
            } else {
                data.extend_from_slice(line.as_bytes());
                data.extend_from_slice(b"\r\n");
            }
        } else if line.starts_with("EHLO") {
            write
                .write_all(b"250-localhost\r\n250-AUTH PLAIN LOGIN\r\n250 SIZE 10485760\r\n")
                .await
                .unwrap();
        } else if line.starts_with("AUTH PLAIN") {
            write
                .write_all(b"235 2.7.0 authenticated\r\n")
                .await
                .unwrap();
        } else if line.starts_with("MAIL FROM") || line.starts_with("RCPT TO") {
            write.write_all(b"250 2.1.0 accepted\r\n").await.unwrap();
        } else if line == "DATA" {
            in_data = true;
            write
                .write_all(b"354 End data with <CR><LF>.<CR><LF>\r\n")
                .await
                .unwrap();
        } else if line == "QUIT" {
            write.write_all(b"221 2.0.0 bye\r\n").await.unwrap();
            break;
        } else {
            write.write_all(b"250 2.0.0 ok\r\n").await.unwrap();
        }
    }
}
