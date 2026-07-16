# Local Data Protection and Backup

[简体中文](./DATA_PROTECTION.zh-CN.md)

AgentWeave provides an optional Host capability for encrypted local backups and restart-safe database restore. An App enables it by declaring the `data-protection` capability. A Host must also supply a 32-byte data-protection key through a trusted launch channel.

## Protection boundary

The capability encrypts exported SQLite backups with AES-256-GCM. The authenticated envelope binds the App ID, creation time, and plaintext hash, so a backup cannot be silently modified or restored into a different App.

This capability does not encrypt the live SQLite database at rest. The status API reports `atRestEncryption: not_provided` instead of implying full-disk or database encryption. Apps with stronger at-rest requirements must add an audited encrypted SQLite provider or rely on operating-system volume protection.

The backup contains the AgentWeave SQLite database only. It does not contain workspace files, packaged App resources, model API keys stored by Electron, Connector secret files, or arbitrary files referenced by an attachment.

## Connector credential isolation

Connector secret bytes remain in the Host secret store. SQLite stores only scoped provider-principal metadata, opaque secret IDs, and Connector account bindings.

A provider credential is keyed by App, tenant, user, and credential ID. Each Connector account is keyed separately by App, tenant, user, Connector ID, and account ID, then references one provider credential with an allowed scope subset. Calendar and Contacts can therefore both use an account named `primary` without overwriting each other, while still sharing one Google or Microsoft principal when the user authorizes both.

Removing one Connector binding does not revoke or delete a shared credential. The Host can revoke the credential and scrub its referenced secret material only after the final binding has been removed. Every lease checks the exact Connector and account binding, the binding scope subset, the provider grant, expiry, and revocation state before reading secret material.

## Desktop key handling

Electron Main creates a random 32-byte key and stores only its operating-system-encrypted form in the App data directory. The raw key is passed to the managed Rust sidecar through the inherited launch pipe. It is not placed in the child environment, Renderer, Preload result, logs, prompts, or backup metadata.

A Desktop export wraps the operating-system-encrypted key next to the encrypted Rust backup envelope. This permits recovery after reinstall for the same operating-system user when the platform keychain can still decrypt the wrapped key. It is not a cross-user or cross-machine recovery mechanism. Losing both the platform keychain and the active App data makes these backups unrecoverable.

Custom Server Hosts can inject their own protected key through `AppState::with_data_protection`. The stock unauthenticated development server leaves the capability disabled unless a trusted managed Host supplies a key.

## Backup workflow

1. The Runtime creates a consistent SQLite snapshot with `VACUUM INTO`.
2. The snapshot is limited to 256 MiB and is never exposed to the Renderer.
3. The Runtime encrypts the snapshot in the `agentweave-backup-v1` envelope.
4. Electron Main asks the user for a destination and writes a Desktop backup bundle with private file permissions.
5. The Renderer receives only a receipt containing byte count, creation time, and bundle hash.

The authenticated API is:

- `GET /foundation/data-protection/status`
- `GET /foundation/data-protection/backup`
- `POST /foundation/data-protection/restore`

Binary backup and restore routes are intended for a trusted Host. They are not model tools and are not part of the generic Renderer sidecar request surface.

## Restore workflow

Electron Main reads the selected backup without returning its path or bytes to the Renderer. It unwraps the backup key with operating-system encryption and sends the encrypted envelope and one-time restore key over the authenticated local transport.

The sidecar authenticates and decrypts the envelope, verifies the App ID, enforces size limits, runs SQLite `quick_check`, and confirms the expected migration table. It then writes a private `restore-pending` database. No live database is modified during request handling.

After the restore is staged, Electron Main stops and restarts the managed sidecar. Startup validates the pending database again, moves the current database and its WAL/SHM files to a rollback family, and atomically promotes the pending database. A failed promotion attempts to put the previous database back before startup continues.

Only one restore can be pending. A successful later restore replaces the older rollback copy. Restore is an explicit user operation and must not be triggered by model output or external document content.

## Failure contract

- Missing capability or key: backup and restore are disabled.
- Invalid metadata, malformed key, failed authentication, or incompatible SQLite content: `400`.
- Backup for a different App or an already pending restore: `409`.
- Backup beyond the bounded size: `413`.
- Unexpected storage or filesystem failure: sanitized `500` with no path, key, or database content in the response.

Hosts should keep the active database, rollback database, encrypted backup bundle, and wrapped key out of logs, screenshots, fixtures, and bug reports.
