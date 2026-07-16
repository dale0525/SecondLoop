use crate::credential::{CredentialScope, CredentialVault, SecretId};
use crate::mail::*;
use crate::mail_attachments::MailAttachmentSource;
use crate::mail_fake::{FakeMailConnector, SeedAttachment, SeedBodyPart, SeedMessage};
use async_imap::{Client, Session, types::Flag};
use async_trait::async_trait;
use chrono::{TimeZone, Utc};
use futures::TryStreamExt;
use lettre::{
    AsyncSmtpTransport, AsyncTransport, Message, Tokio1Executor,
    message::{Mailbox as LettreMailbox, header::MessageId},
    transport::smtp::{
        authentication::{Credentials, Mechanism},
        client::Tls,
    },
};
use mail_parser::{MessageParser, MimeHeaders};
use serde::{Deserialize, Serialize};
use std::{
    collections::{BTreeMap, BTreeSet, HashMap},
    fmt,
    pin::Pin,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    task::{Context, Poll},
    time::Duration,
};
use tokio::{
    io::{AsyncRead, AsyncWrite, ReadBuf},
    net::TcpStream,
    time::timeout,
};

const CONNECTOR_ID: &str = "agentweave.connector.mail.imap-smtp";

#[path = "mail_imap_smtp_support.rs"]
mod support;
use support::*;
#[path = "mail_imap_smtp_outgoing.rs"]
mod outgoing;
use outgoing::build_outgoing_message;
#[path = "mail_imap_smtp_auth.rs"]
mod authentication;
pub use authentication::MailAuthentication;
use authentication::XOAuth2Authenticator;

enum ImapStream {
    Plain(TcpStream),
    Tls(tokio_native_tls::TlsStream<TcpStream>),
}

impl fmt::Debug for ImapStream {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(match self {
            Self::Plain(_) => "ImapStream::Plain",
            Self::Tls(_) => "ImapStream::Tls",
        })
    }
}

impl AsyncRead for ImapStream {
    fn poll_read(
        self: Pin<&mut Self>,
        context: &mut Context<'_>,
        buffer: &mut ReadBuf<'_>,
    ) -> Poll<std::io::Result<()>> {
        match self.get_mut() {
            Self::Plain(stream) => Pin::new(stream).poll_read(context, buffer),
            Self::Tls(stream) => Pin::new(stream).poll_read(context, buffer),
        }
    }
}

impl AsyncWrite for ImapStream {
    fn poll_write(
        self: Pin<&mut Self>,
        context: &mut Context<'_>,
        buffer: &[u8],
    ) -> Poll<std::io::Result<usize>> {
        match self.get_mut() {
            Self::Plain(stream) => Pin::new(stream).poll_write(context, buffer),
            Self::Tls(stream) => Pin::new(stream).poll_write(context, buffer),
        }
    }

    fn poll_flush(self: Pin<&mut Self>, context: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        match self.get_mut() {
            Self::Plain(stream) => Pin::new(stream).poll_flush(context),
            Self::Tls(stream) => Pin::new(stream).poll_flush(context),
        }
    }

    fn poll_shutdown(self: Pin<&mut Self>, context: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        match self.get_mut() {
            Self::Plain(stream) => Pin::new(stream).poll_shutdown(context),
            Self::Tls(stream) => Pin::new(stream).poll_shutdown(context),
        }
    }
}

type ImapSession = Session<ImapStream>;

#[derive(Clone, Copy, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum MailTlsMode {
    Implicit,
    StartTls,
    None,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ImapSmtpMailConfig {
    pub account: MailAccount,
    pub credential_scope: CredentialScope,
    pub credential_secret_id: SecretId,
    pub imap_host: String,
    pub imap_port: u16,
    pub imap_tls: MailTlsMode,
    pub smtp_host: String,
    pub smtp_port: u16,
    pub smtp_tls: MailTlsMode,
    pub username: String,
    pub archive_mailbox: Option<String>,
    pub sent_mailbox: Option<String>,
    pub drafts_mailbox: Option<String>,
    pub trash_mailbox: Option<String>,
    pub allow_insecure_localhost: bool,
    pub connect_timeout_seconds: u64,
    pub operation_timeout_seconds: u64,
}

impl ImapSmtpMailConfig {
    pub fn validate(&self) -> anyhow::Result<()> {
        for (label, value) in [
            ("account id", self.account.id.as_str()),
            ("IMAP host", self.imap_host.as_str()),
            ("SMTP host", self.smtp_host.as_str()),
            ("username", self.username.as_str()),
        ] {
            anyhow::ensure!(!value.trim().is_empty(), "{label} is required");
            anyhow::ensure!(value.len() <= 512, "{label} is too long");
        }
        anyhow::ensure!(
            self.imap_port > 0 && self.smtp_port > 0,
            "mail port is invalid"
        );
        anyhow::ensure!(
            (1..=120).contains(&self.connect_timeout_seconds),
            "mail connect timeout is invalid"
        );
        anyhow::ensure!(
            (1..=300).contains(&self.operation_timeout_seconds),
            "mail operation timeout is invalid"
        );
        self.credential_scope.validate()?;
        if self.imap_tls == MailTlsMode::None || self.smtp_tls == MailTlsMode::None {
            anyhow::ensure!(
                self.allow_insecure_localhost
                    && is_localhost(&self.imap_host)
                    && is_localhost(&self.smtp_host),
                "unencrypted mail is restricted to explicit localhost test configuration"
            );
        }
        Ok(())
    }
}

#[derive(Clone)]
pub struct ImapSmtpMailConnector {
    config: Arc<ImapSmtpMailConfig>,
    vault: Arc<CredentialVault>,
    local: FakeMailConnector,
    attachment_source: Option<Arc<dyn MailAttachmentSource>>,
    connected: Arc<AtomicBool>,
    previews: Arc<Mutex<HashMap<String, SendPreview>>>,
    messages: Arc<Mutex<HashMap<String, CachedMessage>>>,
    authentication: MailAuthentication,
    credential_connector_id: String,
    credential_scopes: Option<BTreeSet<String>>,
}

#[derive(Clone)]
struct CachedMessage {
    message: MailMessage,
    bodies: BTreeMap<String, CachedBody>,
    attachments: BTreeMap<String, Vec<u8>>,
}

#[derive(Clone)]
struct CachedBody {
    original: String,
    sanitized_plain: String,
    mime_type: String,
    trust: BodyPartTrust,
}

impl ImapSmtpMailConnector {
    pub fn new(config: ImapSmtpMailConfig, vault: Arc<CredentialVault>) -> anyhow::Result<Self> {
        config.validate()?;
        let local = FakeMailConnector::new();
        local.add_account(config.account.clone())?;
        Ok(Self {
            config: Arc::new(config),
            vault,
            local,
            attachment_source: None,
            connected: Arc::new(AtomicBool::new(true)),
            previews: Arc::new(Mutex::new(HashMap::new())),
            messages: Arc::new(Mutex::new(HashMap::new())),
            authentication: MailAuthentication::Password,
            credential_connector_id: CONNECTOR_ID.into(),
            credential_scopes: None,
        })
    }

    pub fn with_attachment_source(mut self, source: Arc<dyn MailAttachmentSource>) -> Self {
        self.attachment_source = Some(source);
        self
    }

    pub fn capability_report(&self) -> BTreeMap<&'static str, bool> {
        BTreeMap::from([
            ("imap.mailboxes", true),
            ("imap.search", true),
            ("imap.move", true),
            ("smtp.send", true),
            ("server_side_threads", false),
            ("server_side_drafts", false),
            ("outgoing_attachments", self.attachment_source.is_some()),
        ])
    }

    async fn imap_session(&self, scopes: &[&str]) -> MailResult<ImapSession> {
        if !self.connected.load(Ordering::SeqCst) {
            return Err(MailError::Connector("account is disconnected".into()));
        }
        let credential = self.credential(scopes).await?;
        let connect_timeout = Duration::from_secs(self.config.connect_timeout_seconds);
        let address = (self.config.imap_host.as_str(), self.config.imap_port);
        let tcp = timeout(connect_timeout, TcpStream::connect(address))
            .await
            .map_err(|_| MailError::Connector("IMAP connection timed out".into()))?
            .map_err(|_| MailError::Connector("IMAP connection failed".into()))?;
        let stream = match self.config.imap_tls {
            MailTlsMode::Implicit => {
                let connector = native_tls::TlsConnector::builder()
                    .build()
                    .map_err(|_| MailError::Connector("IMAP TLS configuration failed".into()))?;
                let tls = tokio_native_tls::TlsConnector::from(connector);
                ImapStream::Tls(
                    timeout(connect_timeout, tls.connect(&self.config.imap_host, tcp))
                        .await
                        .map_err(|_| MailError::Connector("IMAP TLS handshake timed out".into()))?
                        .map_err(|_| MailError::Connector("IMAP TLS validation failed".into()))?,
                )
            }
            MailTlsMode::StartTls => {
                return Err(MailError::Unsupported(
                    "IMAP STARTTLS is not enabled in the first adapter release; use implicit TLS"
                        .into(),
                ));
            }
            MailTlsMode::None => ImapStream::Plain(tcp),
        };
        let mut client = Client::new(stream);
        timeout(connect_timeout, client.read_response())
            .await
            .map_err(|_| MailError::Connector("IMAP greeting timed out".into()))?
            .map_err(|_| MailError::Connector("IMAP greeting failed".into()))?
            .ok_or_else(|| MailError::Connector("IMAP server closed before greeting".into()))?;
        match self.authentication {
            MailAuthentication::Password => timeout(
                connect_timeout,
                client.login(&self.config.username, &credential),
            )
            .await
            .map_err(|_| MailError::Connector("IMAP login timed out".into()))?
            .map_err(|_| MailError::Connector("IMAP authentication failed".into())),
            MailAuthentication::XOAuth2 => {
                let authenticator = XOAuth2Authenticator {
                    username: &self.config.username,
                    token: &credential,
                };
                timeout(
                    connect_timeout,
                    client.authenticate("XOAUTH2", &authenticator),
                )
                .await
                .map_err(|_| MailError::Connector("IMAP XOAUTH2 timed out".into()))?
                .map_err(|_| MailError::Connector("IMAP XOAUTH2 failed".into()))
            }
        }
    }

    async fn fetch_messages(
        &self,
        mailbox: &str,
        query: &str,
        page: &PageRequest,
    ) -> MailResult<Page<MailMessageSummary>> {
        page.validate()?;
        let mut session = self.imap_session(&["mail.message.read"]).await?;
        let operation = async {
            session.select(mailbox).await.map_err(imap_error)?;
            let mut uids = session
                .uid_search(query)
                .await
                .map_err(imap_error)?
                .into_iter()
                .collect::<Vec<_>>();
            uids.sort_unstable_by(|left, right| right.cmp(left));
            let total = uids.len();
            let offset = decode_cursor(page.cursor.as_deref())?;
            let selected = uids
                .into_iter()
                .skip(offset)
                .take(page.limit as usize)
                .collect::<Vec<_>>();
            let mut items = Vec::new();
            if !selected.is_empty() {
                let sequence = selected
                    .iter()
                    .map(u32::to_string)
                    .collect::<Vec<_>>()
                    .join(",");
                let fetched = session
                    .uid_fetch(sequence, "UID FLAGS BODY.PEEK[]")
                    .await
                    .map_err(imap_error)?;
                let rows = fetched.try_collect::<Vec<_>>().await.map_err(imap_error)?;
                for row in rows {
                    let uid = row
                        .uid
                        .ok_or_else(|| MailError::Connector("IMAP response omitted UID".into()))?;
                    let raw = row.body().ok_or_else(|| {
                        MailError::Connector("IMAP response omitted message body".into())
                    })?;
                    let cached =
                        parse_message(&self.config.account.id, mailbox, uid, raw, row.flags())?;
                    self.seed_local_message(&cached)?;
                    items.push(cached.message.summary.clone());
                    self.messages
                        .lock()
                        .expect("mail cache poisoned")
                        .insert(cached.message.summary.id.clone(), cached);
                }
                items.sort_by(|left, right| right.sent_at.cmp(&left.sent_at));
            }
            let next = (offset + items.len() < total).then(|| encode_cursor(offset + items.len()));
            let _ = session.logout().await;
            Ok(Page {
                items,
                next_cursor: next,
            })
        };
        timeout(
            Duration::from_secs(self.config.operation_timeout_seconds),
            operation,
        )
        .await
        .map_err(|_| MailError::Connector("IMAP operation timed out".into()))?
    }

    async fn ensure_cached(&self, message_id: &str) -> MailResult<CachedMessage> {
        if let Some(cached) = self
            .messages
            .lock()
            .expect("mail cache poisoned")
            .get(message_id)
            .cloned()
        {
            return Ok(cached);
        }
        let (mailbox, uid) = decode_message_id(message_id)?;
        let mut session = self.imap_session(&["mail.message.read"]).await?;
        session.select(&mailbox).await.map_err(imap_error)?;
        let fetched = session
            .uid_fetch(uid.to_string(), "UID FLAGS BODY.PEEK[]")
            .await
            .map_err(imap_error)?;
        let rows = fetched.try_collect::<Vec<_>>().await.map_err(imap_error)?;
        let row = rows
            .first()
            .ok_or_else(|| MailError::NotFound(message_id.into()))?;
        let raw = row
            .body()
            .ok_or_else(|| MailError::Connector("IMAP response omitted message body".into()))?;
        let cached = parse_message(&self.config.account.id, &mailbox, uid, raw, row.flags())?;
        self.seed_local_message(&cached)?;
        self.messages
            .lock()
            .expect("mail cache poisoned")
            .insert(message_id.into(), cached.clone());
        let _ = session.logout().await;
        Ok(cached)
    }

    fn seed_local_message(&self, cached: &CachedMessage) -> MailResult<()> {
        let bodies = cached
            .message
            .body_parts
            .iter()
            .filter_map(|metadata| {
                cached.bodies.get(&metadata.id).map(|body| SeedBodyPart {
                    metadata: metadata.clone(),
                    original: body.original.clone(),
                    sanitized_plain_fallback: (body.trust == BodyPartTrust::UntrustedHtml)
                        .then(|| body.sanitized_plain.clone()),
                })
            })
            .collect();
        let attachments = cached
            .message
            .attachments
            .iter()
            .filter_map(|metadata| {
                cached
                    .attachments
                    .get(&metadata.id)
                    .map(|data| SeedAttachment {
                        metadata: metadata.clone(),
                        data: data.clone(),
                    })
            })
            .collect();
        self.local.seed_message(SeedMessage {
            message: cached.message.clone(),
            bodies,
            attachments,
        })
    }

    async fn smtp_send(&self, preview: &SendPreview, draft: &MailDraft) -> MailResult<()> {
        let mut attachments = Vec::with_capacity(draft.content.attachments.len());
        for attachment in &draft.content.attachments {
            let source = self.attachment_source.as_ref().ok_or_else(|| {
                MailError::Unsupported(
                    "IMAP/SMTP outgoing attachments require a Host attachment source".into(),
                )
            })?;
            attachments.push(source.resolve(&draft.account_id, attachment).await?);
        }
        let credential = self.credential(&["mail.message.send"]).await?;
        let mut builder = Message::builder()
            .from(to_lettre_mailbox(&preview.from)?)
            .subject(&preview.subject)
            .header(MessageId::from(preview.internet_message_id.clone()));
        for address in &preview.to {
            builder = builder.to(to_lettre_mailbox(address)?);
        }
        for address in &preview.cc {
            builder = builder.cc(to_lettre_mailbox(address)?);
        }
        for address in &preview.bcc {
            builder = builder.bcc(to_lettre_mailbox(address)?);
        }
        let message = build_outgoing_message(builder, draft, attachments)?;
        let credentials = Credentials::new(self.config.username.clone(), credential);
        let mut transport = match self.config.smtp_tls {
            MailTlsMode::Implicit => {
                AsyncSmtpTransport::<Tokio1Executor>::relay(&self.config.smtp_host)
                    .map_err(|_| MailError::Connector("SMTP TLS configuration failed".into()))?
            }
            MailTlsMode::StartTls => {
                AsyncSmtpTransport::<Tokio1Executor>::starttls_relay(&self.config.smtp_host)
                    .map_err(|_| {
                        MailError::Connector("SMTP STARTTLS configuration failed".into())
                    })?
            }
            MailTlsMode::None => {
                AsyncSmtpTransport::<Tokio1Executor>::builder_dangerous(&self.config.smtp_host)
                    .tls(Tls::None)
            }
        };
        transport = transport
            .port(self.config.smtp_port)
            .credentials(credentials);
        if self.authentication == MailAuthentication::XOAuth2 {
            transport = transport.authentication(vec![Mechanism::Xoauth2]);
        }
        timeout(
            Duration::from_secs(self.config.operation_timeout_seconds),
            transport.build().send(message),
        )
        .await
        .map_err(|_| MailError::ReconciliationRequired {
            outbox_id: preview.outbox_id.clone(),
        })?
        .map_err(|error| {
            if error.is_timeout() || error.is_client() {
                MailError::ReconciliationRequired {
                    outbox_id: preview.outbox_id.clone(),
                }
            } else {
                MailError::Connector("SMTP server rejected the message".into())
            }
        })?;
        Ok(())
    }
}

#[async_trait]
impl MailConnector for ImapSmtpMailConnector {
    async fn list_accounts(&self) -> MailResult<Vec<MailAccount>> {
        Ok(vec![self.config.account.clone()])
    }

    async fn account_status(&self, account_id: &str) -> MailResult<MailAccountStatus> {
        ensure_account_id(&self.config.account.id, account_id)?;
        let state = if self.connected.load(Ordering::SeqCst) {
            MailAccountState::Connected
        } else {
            MailAccountState::AuthenticationRequired
        };
        Ok(MailAccountStatus {
            account: self.config.account.clone(),
            state,
            detail: None,
        })
    }

    async fn request_connect(
        &self,
        request: MailAccountActionRequest,
    ) -> MailResult<MailAccountStatus> {
        ensure_account_id(&self.config.account.id, &request.account_id)?;
        self.connected.store(true, Ordering::SeqCst);
        match self.imap_session(&["mail.message.read"]).await {
            Ok(mut session) => {
                let _ = session.logout().await;
                self.account_status(&request.account_id).await
            }
            Err(error) => {
                self.connected.store(false, Ordering::SeqCst);
                Err(error)
            }
        }
    }

    async fn disconnect(&self, request: MailAccountActionRequest) -> MailResult<MailAccountStatus> {
        ensure_account_id(&self.config.account.id, &request.account_id)?;
        self.connected.store(false, Ordering::SeqCst);
        self.account_status(&request.account_id).await
    }

    async fn list_mailboxes(&self, account_id: &str) -> MailResult<Vec<Mailbox>> {
        ensure_account_id(&self.config.account.id, account_id)?;
        let mut session = self.imap_session(&["mail.message.read"]).await?;
        let names = session.list(None, Some("*")).await.map_err(imap_error)?;
        let names = names.try_collect::<Vec<_>>().await.map_err(imap_error)?;
        let mut mailboxes = names
            .into_iter()
            .map(|name| {
                let value = name.name().to_string();
                Mailbox {
                    id: value.clone(),
                    account_id: account_id.to_string(),
                    name: value.clone(),
                    role: mailbox_role(&value, &self.config),
                    provider_reference: Some(ProviderReference {
                        provider: "imap".into(),
                        id: value,
                    }),
                }
            })
            .collect::<Vec<_>>();
        mailboxes.sort_by(|left, right| left.name.cmp(&right.name));
        let _ = session.logout().await;
        Ok(mailboxes)
    }

    async fn list_threads(&self, request: ListThreadsRequest) -> MailResult<Page<MailThread>> {
        let messages = self
            .search_messages(SearchMessagesRequest {
                account_id: request.account_id.clone(),
                mailbox_id: request.mailbox_id,
                search: MailSearch::default(),
                page: request.page,
            })
            .await?;
        Ok(Page {
            next_cursor: messages.next_cursor,
            items: messages
                .items
                .into_iter()
                .map(|message| MailThread {
                    id: message
                        .thread_id
                        .clone()
                        .unwrap_or_else(|| message.id.clone()),
                    account_id: message.account_id.clone(),
                    subject: message.subject.clone(),
                    message_ids: vec![message.id.clone()],
                    participants: vec![message.from.clone()],
                    last_message_at: message.sent_at,
                    unread_count: u32::from(!message.is_read),
                    provider_reference: message.provider_reference.clone(),
                })
                .collect(),
        })
    }

    async fn get_thread(&self, request: GetThreadRequest) -> MailResult<MailThreadDetail> {
        let message = self
            .get_message(GetMessageRequest {
                account_id: request.account_id.clone(),
                message_id: request.thread_id.clone(),
            })
            .await?;
        let summary = &message.summary;
        Ok(MailThreadDetail {
            thread: MailThread {
                id: request.thread_id,
                account_id: request.account_id,
                subject: summary.subject.clone(),
                message_ids: vec![summary.id.clone()],
                participants: vec![summary.from.clone()],
                last_message_at: summary.sent_at,
                unread_count: u32::from(!summary.is_read),
                provider_reference: summary.provider_reference.clone(),
            },
            messages: vec![message],
        })
    }

    async fn search_messages(
        &self,
        request: SearchMessagesRequest,
    ) -> MailResult<Page<MailMessageSummary>> {
        ensure_account_id(&self.config.account.id, &request.account_id)?;
        request.search.validate()?;
        let mailbox = request.mailbox_id.as_deref().unwrap_or("INBOX");
        self.fetch_messages(mailbox, &imap_search_query(&request.search), &request.page)
            .await
    }

    async fn get_message(&self, request: GetMessageRequest) -> MailResult<MailMessage> {
        ensure_account_id(&self.config.account.id, &request.account_id)?;
        Ok(self.ensure_cached(&request.message_id).await?.message)
    }

    async fn read_body_part(&self, request: ReadBodyPartRequest) -> MailResult<BodyPartContent> {
        request.validate()?;
        let cached = self.ensure_cached(&request.message_id).await?;
        let body = cached
            .bodies
            .get(&request.part_id)
            .ok_or_else(|| MailError::NotFound(request.part_id.clone()))?;
        let (content, representation, trust, mime_type) = match request.representation {
            BodyRepresentation::Original => (
                &body.original,
                BodyRepresentation::Original,
                body.trust,
                body.mime_type.clone(),
            ),
            BodyRepresentation::SanitizedPlainFallback => (
                &body.sanitized_plain,
                BodyRepresentation::SanitizedPlainFallback,
                BodyPartTrust::PlainText,
                "text/plain".into(),
            ),
        };
        let (chunk, next_offset, truncated) =
            text_chunk(content, request.offset, request.max_bytes)?;
        Ok(BodyPartContent {
            part_id: request.part_id,
            representation,
            mime_type,
            trust,
            content: chunk,
            offset: request.offset,
            next_offset,
            truncated,
        })
    }

    async fn read_attachment(&self, request: ReadAttachmentRequest) -> MailResult<AttachmentChunk> {
        request.validate()?;
        let cached = self.ensure_cached(&request.message_id).await?;
        let data = cached
            .attachments
            .get(&request.attachment_id)
            .ok_or_else(|| MailError::NotFound(request.attachment_id.clone()))?;
        let start = usize::try_from(request.offset)
            .map_err(|_| MailError::InvalidRequest("attachment offset is invalid".into()))?;
        if start > data.len() {
            return Err(MailError::InvalidRequest(
                "attachment offset exceeds content".into(),
            ));
        }
        let end = (start + request.max_bytes as usize).min(data.len());
        Ok(AttachmentChunk {
            attachment_id: request.attachment_id,
            data: data[start..end].to_vec(),
            offset: request.offset,
            next_offset: (end < data.len()).then_some(end as u64),
            truncated: end < data.len(),
        })
    }

    async fn set_read_state(&self, request: SetReadStateRequest) -> MailResult<MailMessageSummary> {
        ensure_account_id(&self.config.account.id, &request.account_id)?;
        let (mailbox, uid) = decode_message_id(&request.message_id)?;
        let mut session = self.imap_session(&["mail.message.organize"]).await?;
        session.select(&mailbox).await.map_err(imap_error)?;
        let query = if request.is_read {
            "+FLAGS.SILENT (\\Seen)"
        } else {
            "-FLAGS.SILENT (\\Seen)"
        };
        let updates = session
            .uid_store(uid.to_string(), query)
            .await
            .map_err(imap_error)?;
        let _ = updates.try_collect::<Vec<_>>().await.map_err(imap_error)?;
        let _ = session.logout().await;
        self.messages
            .lock()
            .expect("mail cache poisoned")
            .remove(&request.message_id);
        Ok(self
            .ensure_cached(&request.message_id)
            .await?
            .message
            .summary)
    }

    async fn archive_message(
        &self,
        request: ArchiveMessageRequest,
    ) -> MailResult<MailMessageSummary> {
        let destination =
            self.config.archive_mailbox.clone().ok_or_else(|| {
                MailError::Unsupported("archive mailbox is not configured".into())
            })?;
        self.move_message(MoveMessageRequest {
            account_id: request.account_id,
            message_id: request.message_id,
            from_mailbox_id: None,
            to_mailbox_id: destination,
        })
        .await
    }

    async fn move_message(&self, request: MoveMessageRequest) -> MailResult<MailMessageSummary> {
        ensure_account_id(&self.config.account.id, &request.account_id)?;
        let summary = self
            .ensure_cached(&request.message_id)
            .await?
            .message
            .summary;
        let (mailbox, uid) = decode_message_id(&request.message_id)?;
        if let Some(expected) = request.from_mailbox_id.as_deref()
            && expected != mailbox
        {
            return Err(MailError::InvalidRequest(
                "source mailbox does not match message".into(),
            ));
        }
        let mut session = self.imap_session(&["mail.message.organize"]).await?;
        session.select(&mailbox).await.map_err(imap_error)?;
        session
            .uid_mv(uid.to_string(), &request.to_mailbox_id)
            .await
            .map_err(imap_error)?;
        let _ = session.logout().await;
        self.messages
            .lock()
            .expect("mail cache poisoned")
            .remove(&request.message_id);
        Ok(summary)
    }

    async fn create_draft(&self, request: CreateDraftRequest) -> MailResult<MailDraft> {
        self.local.create_draft(request).await
    }
    async fn create_reply_draft(&self, request: CreateReplyDraftRequest) -> MailResult<MailDraft> {
        self.local.create_reply_draft(request).await
    }
    async fn create_forward_draft(
        &self,
        request: CreateForwardDraftRequest,
    ) -> MailResult<MailDraft> {
        self.local.create_forward_draft(request).await
    }
    async fn get_draft(&self, request: GetDraftRequest) -> MailResult<MailDraft> {
        self.local.get_draft(request).await
    }
    async fn update_draft(&self, request: UpdateDraftRequest) -> MailResult<MailDraft> {
        self.local.update_draft(request).await
    }
    async fn delete_draft(&self, request: DeleteDraftRequest) -> MailResult<()> {
        self.local.delete_draft(request).await
    }

    async fn preview_send(&self, request: PreviewSendRequest) -> MailResult<SendPreview> {
        let preview = self.local.preview_send(request).await?;
        self.previews
            .lock()
            .expect("mail preview cache poisoned")
            .insert(preview.id.clone(), preview.clone());
        Ok(preview)
    }

    async fn send_approved(&self, request: ApprovedSendRequest) -> MailResult<DeliveryReceipt> {
        let preview = self
            .previews
            .lock()
            .expect("mail preview cache poisoned")
            .get(&request.preview_id)
            .cloned()
            .ok_or_else(|| MailError::NotFound(request.preview_id.clone()))?;
        if request.approval.operation != MailApprovalOperation::SendDraft
            || request.approval.resource_id != preview.draft_id
            || request.approval.revision != preview.draft_revision
            || request.approval.preview_hash.as_deref() != Some(&preview.preview_hash)
        {
            return Err(MailError::ApprovalMismatch);
        }
        let draft = self
            .local
            .get_draft(GetDraftRequest {
                account_id: preview.account_id.clone(),
                draft_id: preview.draft_id.clone(),
            })
            .await?;
        match self.smtp_send(&preview, &draft).await {
            Ok(()) => self.local.send_approved(request).await,
            Err(MailError::ReconciliationRequired { .. }) => {
                self.local.queue_delivery_outcome(DeliveryState::Uncertain);
                self.local.send_approved(request).await
            }
            Err(error) => Err(error),
        }
    }

    async fn delivery_status(&self, request: DeliveryStatusRequest) -> MailResult<DeliveryReceipt> {
        self.local.delivery_status(request).await
    }
}

fn parse_message<'a, I>(
    account_id: &str,
    mailbox: &str,
    uid: u32,
    raw: &[u8],
    flags: I,
) -> MailResult<CachedMessage>
where
    I: Iterator<Item = Flag<'a>>,
{
    let parsed = MessageParser::default()
        .parse(raw)
        .ok_or_else(|| MailError::Connector("MIME message could not be parsed".into()))?;
    let id = encode_message_id(mailbox, uid);
    let from = parsed
        .from()
        .and_then(|addresses| addresses.first())
        .map(mail_address)
        .unwrap_or(MailAddress {
            name: None,
            address: "unknown@invalid".into(),
        });
    let to = parsed.to().map(mail_addresses).unwrap_or_default();
    let sent_at = parsed
        .date()
        .and_then(|date| Utc.timestamp_opt(date.to_timestamp(), 0).single())
        .unwrap_or_else(Utc::now);
    let internet_message_id = parsed.message_id().unwrap_or(&id).to_string();
    let mut bodies = BTreeMap::new();
    let mut body_parts = Vec::new();
    let mut seen_body_parts = BTreeSet::new();
    for part_id in parsed.text_body.iter().chain(parsed.html_body.iter()) {
        if !seen_body_parts.insert(*part_id) {
            continue;
        }
        let part = &parsed.parts[*part_id as usize];
        let part_key = format!("part-{part_id}");
        let original = part.text_contents().unwrap_or_default().to_string();
        let is_html = part.is_text_html();
        let sanitized_plain = if is_html {
            parsed.body_text(0).unwrap_or_default().to_string()
        } else {
            original.clone()
        };
        let mime_type = if is_html { "text/html" } else { "text/plain" }.to_string();
        body_parts.push(MailBodyPart {
            id: part_key.clone(),
            mime_type: mime_type.clone(),
            charset: Some("utf-8".into()),
            size_bytes: original.len() as u64,
            disposition: None,
            content_id: part.content_id().map(str::to_owned),
            trust: if is_html {
                BodyPartTrust::UntrustedHtml
            } else {
                BodyPartTrust::PlainText
            },
            has_sanitized_plain_fallback: is_html,
        });
        bodies.insert(
            part_key,
            CachedBody {
                original,
                sanitized_plain,
                mime_type,
                trust: if is_html {
                    BodyPartTrust::UntrustedHtml
                } else {
                    BodyPartTrust::PlainText
                },
            },
        );
    }
    let mut attachments = Vec::new();
    let mut attachment_data = BTreeMap::new();
    for part_id in &parsed.attachments {
        let part = &parsed.parts[*part_id as usize];
        let attachment_id = format!("attachment-{part_id}");
        let mime_type = part
            .content_type()
            .map(|value| {
                format!(
                    "{}/{}",
                    value.c_type,
                    value.c_subtype.as_deref().unwrap_or("octet-stream")
                )
            })
            .unwrap_or_else(|| "application/octet-stream".into());
        attachments.push(AttachmentMetadata {
            id: attachment_id.clone(),
            file_name: part.attachment_name().unwrap_or("attachment").to_string(),
            mime_type,
            size_bytes: part.len() as u64,
            disposition: ContentDisposition::Attachment,
            content_id: part.content_id().map(str::to_owned),
            provider_reference: Some(ProviderReference {
                provider: "imap".into(),
                id: format!("{uid}:{part_id}"),
            }),
        });
        attachment_data.insert(attachment_id, part.contents().to_vec());
    }
    let is_read = flags.into_iter().any(|flag| flag == Flag::Seen);
    let thread_id = parsed
        .in_reply_to()
        .as_text()
        .map(|value| value.to_string())
        .unwrap_or_else(|| id.clone());
    let summary = MailMessageSummary {
        id: id.clone(),
        account_id: account_id.into(),
        thread_id: Some(thread_id),
        internet_message_id,
        from,
        to,
        subject: parsed.subject().unwrap_or("(no subject)").to_string(),
        sent_at,
        is_read,
        has_attachments: !attachments.is_empty(),
        mailbox_ids: vec![mailbox.into()],
        provider_reference: Some(ProviderReference {
            provider: "imap".into(),
            id: uid.to_string(),
        }),
    };
    Ok(CachedMessage {
        message: MailMessage {
            summary,
            reply_to: parsed.reply_to().map(mail_addresses).unwrap_or_default(),
            cc: parsed.cc().map(mail_addresses).unwrap_or_default(),
            bcc: parsed.bcc().map(mail_addresses).unwrap_or_default(),
            in_reply_to: parsed.in_reply_to().as_text().map(str::to_owned),
            references: parsed
                .references()
                .as_text_list()
                .map(|values| values.iter().map(ToString::to_string).collect())
                .unwrap_or_default(),
            body_parts,
            attachments,
        },
        bodies,
        attachments: attachment_data,
    })
}

#[cfg(test)]
#[path = "mail_imap_smtp_tests.rs"]
mod tests;
