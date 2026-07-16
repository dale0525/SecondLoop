# Workspace provider adapters

`agent-provider-adapters` keeps provider-specific OAuth and wire formats outside the provider-neutral AgentWeave connector contracts. The server currently wires Google Workspace and Microsoft 365 into the canonical Mail, Calendar, and Contacts connectors.

The adapters never receive raw credentials from model tool arguments. OAuth access and refresh material remains in the persistent Credential Vault, connector account bindings select the credential, and each request leases only the scopes required by that connector.

## Shared host configuration

Real workspace providers require the persistent Credential Vault and an OAuth callback registered by the provider application:

```bash
export AGENTWEAVE_SECRET_ROOT=/absolute/path/to/credential-vault
export AGENTWEAVE_SECRET_MASTER_KEY_HEX=<64-lowercase-hex-characters>
export AGENTWEAVE_OAUTH_CALLBACK_URL=http://127.0.0.1:43121/oauth/callback
```

The callback URL may remain loopback HTTP. Provider API and token traffic is HTTPS-only, redirect-disabled, origin-confined, bounded, and redacted from model-visible state.

## Google Workspace

```bash
export AGENTWEAVE_WORKSPACE_PROVIDER=google
export AGENTWEAVE_GOOGLE_CLIENT_ID=<oauth-client-id>
export AGENTWEAVE_GOOGLE_CLIENT_SECRET=<oauth-client-secret>
export AGENTWEAVE_GOOGLE_ACCOUNT_ID=<account-id-returned-by-oauth-completion>
export AGENTWEAVE_GOOGLE_EMAIL=person@example.com
```

The client secret is optional for a provider application registered as a public client. Gmail uses the existing Mail v1 IMAP/SMTP implementation with XOAUTH2; Calendar and Contacts use their Google JSON APIs.

## Microsoft 365

```bash
export AGENTWEAVE_WORKSPACE_PROVIDER=microsoft
export AGENTWEAVE_MICROSOFT_CLIENT_ID=<application-client-id>
export AGENTWEAVE_MICROSOFT_CLIENT_SECRET=<application-client-secret>
export AGENTWEAVE_MICROSOFT_ACCOUNT_ID=<account-id-returned-by-oauth-completion>
export AGENTWEAVE_MICROSOFT_EMAIL=person@example.com
```

The Microsoft application must allow the configured loopback redirect and delegated permissions for the enabled connectors:

- Mail: `openid`, `profile`, `email`, `offline_access`, `https://outlook.office.com/IMAP.AccessAsUser.All`, and `https://outlook.office.com/SMTP.Send`.
- Calendar: the identity scopes above plus `Calendars.ReadWrite`.
- Contacts: the identity scopes above plus `Contacts.ReadWrite`.

Microsoft's v2 endpoint issues one resource audience per access token. Authorize Mail in one OAuth session and authorize Calendar plus Contacts in a separate session; the provider rejects a mixed Outlook-and-Graph authorization plan before opening a browser.

Outlook Mail reuses Mail v1 through XOAUTH2 against `outlook.office365.com:993` and `smtp.office365.com:587`. Calendar and Contacts use Microsoft Graph with `@odata.etag` or `changeKey` optimistic versions, immutable approval previews, and provider IDs protected from model substitution.

Calendar values are normalized to UTC instants plus an IANA timezone. Ambiguous or nonexistent local times and non-IANA provider timezone identifiers fail closed instead of being flattened. Graph recurrence objects remain complete JSON in the provider-neutral recurrence field.

## Connector identifiers

OAuth authorization requests use the canonical connector IDs returned by the host:

```text
agentweave-mail
agentweave-calendar
agentweave-contacts
```

Account IDs are opaque bindings returned by OAuth completion. Do not replace them with an email address or provider subject, and do not persist access tokens in application configuration.
