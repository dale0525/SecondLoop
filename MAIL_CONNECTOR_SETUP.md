# IMAP/SMTP Mail Connector Setup

English | [简体中文](./MAIL_CONNECTOR_SETUP.zh-CN.md)

AgentWeave exposes an unconfigured Mail state by default and does not invent a connected account. Set `AGENTWEAVE_FAKE_MAIL=enabled` only for deterministic development or test data. When IMAP/SMTP is enabled, the account configuration file still stores only an opaque secret ID. The mailbox password is never written to the Agent App Manifest, model input, Renderer state, or ordinary logs.

## 1. Security prerequisites

Production configurations require:

- IMAP over implicit TLS. The initial implementation does not enable IMAP STARTTLS.
- SMTP over implicit TLS or STARTTLS.
- Certificate validation through the system trust store.
- Plaintext connections only for explicitly configured `localhost` test services.
- Passwords stored in the encrypted Credential Vault and read through short-lived leases jointly authorized by App, tenant, user, Connector, account, and scope.
- No blind retry when an SMTP result is `uncertain`; reconcile it manually or against provider state first.

## 2. Create an account configuration

Copy [mail-account.example.json](./examples/secretary-agent/mail-account.example.json), then change the mail address, servers, ports, and folder names. `credentialSecretId` is a reference, not a password.

The scope in the configuration must match the running App. The Secretary example uses:

```json
{
  "appId": "com.example.secretary-agent",
  "tenantId": "local",
  "userId": "local-user"
}
```

Common ports are `993` for IMAP implicit TLS, `465` for SMTP implicit TLS, and `587` for SMTP STARTTLS. Folder names, app passwords, and authentication policies vary between Gmail, Microsoft, and other services; follow your provider's settings.

## 3. Configure the Credential Vault

Generate a 32-byte master key and provide it through the deployment environment's secret manager. Do not commit it to Git:

```bash
export AGENTWEAVE_SECRET_ROOT="$HOME/.agentweave/secrets"
export AGENTWEAVE_SECRET_MASTER_KEY_HEX="$(openssl rand -hex 32)"
```

Write the mailbox password or app password to the Vault through standard input. The command below does not put the secret value in arguments or output:

```bash
password-manager read agentweave/mail-primary | \
  pixi run store-server-secret -- \
    --app-id com.example.secretary-agent \
    --secret-id mail.primary.password
```

To rotate an existing secret:

```bash
password-manager read agentweave/mail-primary-new | \
  pixi run store-server-secret -- \
    --app-id com.example.secretary-agent \
    --secret-id mail.primary.password \
    --rotate
```

`password-manager read ...` is a placeholder. Replace it with the command for your actual password manager. Avoid putting a plaintext password directly on the shell command line.

## 4. Start the Server

```bash
export AGENTWEAVE_APP_ROOT="examples/secretary-agent"
export AGENTWEAVE_MAIL_CONNECTOR="imap-smtp"
export AGENTWEAVE_MAIL_ACCOUNT_CONFIG="examples/secretary-agent/mail-account.json"
export AGENTWEAVE_SECRET_ROOT="$HOME/.agentweave/secrets"
export AGENTWEAVE_SECRET_MASTER_KEY_HEX="<inject from deployment secret manager>"

pixi run server
```

At startup, the Runtime validates the configuration, App scope, secret ID, and Connector account authorization. The Server fails closed if the Vault is missing, the scope does not match, the TLS policy is unsafe, or the configuration file is a symbolic link.

## 5. Run the dedicated live smoke

The default pull request gate only compiles the ignored live test. It never reads repository secrets and never connects to an external mailbox. A maintainer can run `.github/workflows/live-mail-smoke.yml` manually after configuring the protected `live-mail-smoke` environment.

The environment requires these secrets:

- `LIVE_MAIL_IMAP_HOST`
- `LIVE_MAIL_IMAP_PORT`
- `LIVE_MAIL_SMTP_HOST`
- `LIVE_MAIL_SMTP_PORT`
- `LIVE_MAIL_USERNAME`
- `LIVE_MAIL_PASSWORD`
- `LIVE_MAIL_FROM_ADDRESS`
- `LIVE_MAIL_TO_ADDRESS`

`LIVE_MAIL_INBOX` is optional and defaults to `INBOX`. `LIVE_MAIL_SMTP_TLS` is optional and defaults to `start_tls`; its other supported value is `implicit`. IMAP always uses implicit TLS.

The sender and recipient must be the same dedicated account. The smoke lists the real IMAP mailboxes, creates a uniquely identified local draft, binds an exact send preview and approval, submits it through SMTP, and waits for the same Message-ID to appear through IMAP. Configuration values, credentials, and message content are not printed. A missing secret, an external recipient, a TLS failure, an uncertain SMTP result, or an unobserved delivery fails the workflow.

## 6. Known compatibility boundaries

- IMAP supports mailbox listing, search, read, mark-as-read, and move operations. When the server does not provide thread IDs, thread semantics conservatively treat each message as a separate thread.
- Drafts are stored in a local deterministic draft store by default because IMAP providers vary widely in their Drafts folder behavior.
- SMTP supports plain-text and HTML bodies. The initial live adapter does not read outbound attachments from arbitrary local paths.
- HTML mail is treated as untrusted content. Active content is not executed, and prompt-like text in external mail cannot alter Runtime instructions or approval policy.
- OAuth, the Gmail API, and Microsoft Graph should be integrated as separate adapters instead of adding vendor behavior to the Mail Foundation Skill.

The repository's default conformance gate uses a local Fake IMAP/SMTP server and requires no real account. The protected live smoke is an additional, explicitly triggered provider check.
