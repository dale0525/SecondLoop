# Client Dart HTTP Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the main SecondLoop client to a Flutter/Dart + HTTP runtime architecture while preserving offline plain-text note editing and cloud attachment inventory, preview, and cleanup.

**Architecture:** Cloud runtime and vault services are authoritative for secretary state, notes, attachments, media processing, and semantic decisions. The App keeps only a small Dart local edit store for offline text drafts, a lightweight pending-write queue, and local attachment cache metadata. Rust may remain only in a separate self-managed deploy helper package; it must not be in the normal App chat/capture/note/attachment request path.

**Tech Stack:** Flutter/Dart, `http`, `path_provider`, Dart SQLite via `sqlite3`/`sqlite3_flutter_libs`, Cloudflare Worker HTTP APIs, pixi, Flutter tests, Node tests in SecondLoopServer.

---

## Source Specs

- `docs/architecture/cloudflare-agents-final-architecture.md`
- `docs/architecture/runtime-first-secretary-semantics.md`
- `docs/architecture/agent-state-store-secretary-memory.md`
- `docs/architecture/skill-runtime-architecture.md`
- `docs/product/personal-secretary-agent-mvp-scope.md`
- `docs/qa/managed-pro-manual-qa.md`

## Decisions

1. The main App target is pure Flutter/Dart plus HTTP clients.
2. The main App must not depend on `flutter_rust_bridge`, `secondloop_rust`, `lib/src/rust`, or `rust_builder` after this migration.
3. Self-managed deployment can keep a separate helper process. If that helper uses Rust, it must live outside the normal App runtime dependency graph.
4. Offline editing means plain-text note draft editing only. It does not include offline attachment processing, offline vector search, offline semantic parsing, or local-first vault sync.
5. Attachments remain user-visible in the App through cloud inventory, preview, deletion, and local cache cleanup.
6. Existing dirty worktree changes must be preserved. Do not revert unrelated files while executing this plan.

## Repositories

- App repository: `/Users/logictan/.t3/worktrees/SecondLoop/t3code-f5fd1b79`
- Server repository: `/Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer`

Use the required git identity before making commits:

```bash
git config user.name "Logic Tan"
git config user.email "logictan89@gmail.com"
```

## Runtime Contracts

### Notes

```text
GET    /v1/vaults/:vault_id/notes?limit=:limit&cursor=:cursor
GET    /v1/vaults/:vault_id/notes/:note_id
PUT    /v1/vaults/:vault_id/notes/:note_id
DELETE /v1/vaults/:vault_id/notes/:note_id
```

`PUT` request:

```json
{
  "title": "Meeting notes",
  "body": "Plain text or markdown body",
  "base_revision": "rev-previous"
}
```

`PUT` success:

```json
{
  "id": "note-1",
  "title": "Meeting notes",
  "body": "Plain text or markdown body",
  "revision": "rev-next",
  "updated_at_ms": 1770000000000
}
```

`PUT` conflict:

```json
{
  "error": "revision_conflict",
  "remote": {
    "id": "note-1",
    "title": "Remote title",
    "body": "Remote body",
    "revision": "rev-remote",
    "updated_at_ms": 1770000000100
  }
}
```

### Attachments

```text
GET    /v1/vaults/:vault_id/attachments?limit=:limit&cursor=:cursor&sort=:sort&type=:type
GET    /v1/vaults/:vault_id/attachments/:attachment_id/preview
GET    /v1/vaults/:vault_id/attachments/:attachment_id/delete-impact
DELETE /v1/vaults/:vault_id/attachments/:attachment_id
```

Attachment list item:

```json
{
  "id": "att-1",
  "sha256": "sha-1",
  "display_name": "receipt.pdf",
  "mime_type": "application/pdf",
  "byte_len": 102400,
  "created_at_ms": 1770000000000,
  "uploaded_at_ms": 1770000001000,
  "linked_entities": [
    { "kind": "note", "id": "note-1", "title": "Trip" }
  ],
  "preview": {
    "kind": "pdf",
    "url": "https://signed.example/preview",
    "thumbnail_url": "https://signed.example/thumb"
  },
  "processing_status": "ready",
  "can_delete": true
}
```

## File Structure

### Server

- Modify: `/Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer/workers/vault-service/src/index.js`
- Create: `/Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer/workers/vault-service/src/note_routes.js`
- Create: `/Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer/workers/vault-service/src/attachment_inventory_routes.js`
- Create: `/Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer/workers/vault-service/test/note_routes.test.js`
- Create: `/Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer/workers/vault-service/test/attachment_inventory_routes.test.js`

### App

- Modify: `pubspec.yaml`
- Create: `lib/core/offline_edit/local_edit_models.dart`
- Create: `lib/core/offline_edit/local_edit_store.dart`
- Create: `lib/core/offline_edit/local_edit_sync_service.dart`
- Create: `lib/core/cloud/runtime_note_client.dart`
- Modify: `lib/core/cloud/vault_attachments_client.dart`
- Create: `lib/features/notes/note_list_page.dart`
- Create: `lib/features/notes/note_editor_page.dart`
- Create: `lib/features/notes/note_editor_controller.dart`
- Create: `lib/features/attachments/attachment_preview_descriptor.dart`
- Create: `lib/features/attachments/attachment_storage_controller.dart`
- Modify: `lib/features/settings/vault_usage_card.dart`
- Create: `test/no_rust_dependency_for_runtime_client_test.dart`

### App Tests

- Create: `test/core/offline_edit/local_edit_store_test.dart`
- Create: `test/core/offline_edit/local_edit_sync_service_test.dart`
- Create: `test/core/cloud/runtime_note_client_test.dart`
- Modify: `test/core/cloud/vault_attachments_client_test.dart`
- Create: `test/features/notes/note_editor_controller_test.dart`
- Create: `test/features/notes/note_editor_page_test.dart`
- Create: `test/features/attachments/attachment_storage_controller_test.dart`
- Modify: `test/vault_attachment_usage_list_view_test.dart`

---

## Task 1: Server Note API

**Files:**
- Create: `workers/vault-service/src/note_routes.js`
- Modify: `workers/vault-service/src/index.js`
- Create: `workers/vault-service/test/note_routes.test.js`

- [ ] **Step 1: Write failing route tests**

Test cases:

- `PUT /v1/vaults/vault-1/notes/note-1` creates a note with `revision: rev-1`.
- `GET /v1/vaults/vault-1/notes/note-1` returns title, body, revision, and updated timestamp.
- `GET /v1/vaults/vault-1/notes?limit=50` returns the saved note.
- A stale `PUT` with `base_revision: rev-stale` returns `409` and `error: revision_conflict`.
- `DELETE /v1/vaults/vault-1/notes/note-1` returns `204` and hides the note from list/read.

Run:

```bash
cd /Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer/workers/vault-service
npm test -- test/note_routes.test.js
```

Expected: FAIL because routes do not exist.

- [ ] **Step 2: Implement `note_routes.js`**

Export:

```js
export async function handleNoteRequest(request, env, state, url) {}
```

Implementation requirements:

- Match `^/v1/vaults/([^/]+)/notes(?:/([^/]+))?$`.
- Use `state.getVault(vaultId)` and initialize `vault.notes` as a `Map`.
- Keep note records as `{ id, title, body, revision, created_at_ms, updated_at_ms, deleted_at_ms? }`.
- Generate revision strings as `rev-1`, `rev-2`, `rev-3`.
- Return `409` with the remote note when `base_revision` does not match the stored revision.
- Return JSON with `content-type: application/json`.

- [ ] **Step 3: Mount route**

Modify `workers/vault-service/src/index.js`:

- Import `handleNoteRequest`.
- Call it before existing working-set/blob routes.
- Return its response when it is non-null.

- [ ] **Step 4: Verify and commit**

```bash
cd /Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer/workers/vault-service
npm test -- test/note_routes.test.js
cd /Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer
git add workers/vault-service/src/index.js workers/vault-service/src/note_routes.js workers/vault-service/test/note_routes.test.js
git commit -m "feat: add vault note HTTP contract"
```

Expected: tests pass and commit succeeds.

## Task 2: Server Attachment Inventory API

**Files:**
- Create: `workers/vault-service/src/attachment_inventory_routes.js`
- Modify: `workers/vault-service/src/index.js`
- Create: `workers/vault-service/test/attachment_inventory_routes.test.js`

- [ ] **Step 1: Write failing route tests**

Test cases:

- Runtime test fixtures can seed one attachment with `id`, `sha256`, `display_name`, `mime_type`, `byte_len`, and `linked_entities`.
- `GET /v1/vaults/vault-1/attachments?limit=50` returns `items`, `total_count`, `total_bytes_used`, preview descriptor, processing status, and `can_delete`.
- `GET /v1/vaults/vault-1/attachments/att-1/preview` returns preview kind and URL.
- `GET /v1/vaults/vault-1/attachments/att-1/delete-impact` returns linked entities and `requires_confirmation: true`.
- `DELETE /v1/vaults/vault-1/attachments/att-1` returns `204` and hides the item from list.

Run:

```bash
cd /Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer/workers/vault-service
npm test -- test/attachment_inventory_routes.test.js
```

Expected: FAIL because routes do not exist.

- [ ] **Step 2: Implement `attachment_inventory_routes.js`**

Export:

```js
export async function handleAttachmentInventoryRequest(request, env, state, url) {}
```

Implementation requirements:

- Match `^/v1/vaults/([^/]+)/attachments(?:/([^/]+)(?:/(preview|delete-impact))?)?$`.
- Read and mutate `state.getVault(vaultId).attachments`.
- Normalize old fixture fields such as `mimeType` and `byteLen` into snake_case response fields.
- Build preview kind from MIME type: `image`, `pdf`, `audio`, `video`, or `download`.
- Do not run OCR, ASR, embedding, or media annotation in this route.

- [ ] **Step 3: Mount route**

Modify `workers/vault-service/src/index.js`:

- Import `handleAttachmentInventoryRequest`.
- Call it before blob routes.
- Return its response when it is non-null.

- [ ] **Step 4: Verify and commit**

```bash
cd /Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer/workers/vault-service
npm test -- test/attachment_inventory_routes.test.js
cd /Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer
git add workers/vault-service/src/index.js workers/vault-service/src/attachment_inventory_routes.js workers/vault-service/test/attachment_inventory_routes.test.js
git commit -m "feat: add vault attachment inventory API"
```

Expected: tests pass and commit succeeds.

## Task 3: Dart Local Edit Store

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/core/offline_edit/local_edit_models.dart`
- Create: `lib/core/offline_edit/local_edit_store.dart`
- Create: `test/core/offline_edit/local_edit_store_test.dart`

- [ ] **Step 1: Add dependencies**

```bash
cd /Users/logictan/.t3/worktrees/SecondLoop/t3code-f5fd1b79
pixi run flutter pub add sqlite3 sqlite3_flutter_libs
```

Expected: `pubspec.yaml` and `pubspec.lock` include both packages.

- [ ] **Step 2: Write failing store tests**

Required test cases in `test/core/offline_edit/local_edit_store_test.dart`:

- `saveDraft(...)` stores `remoteId`, title, body, `baseRevision`, `dirty: true`, and `syncState: pending`.
- `listPendingEdits()` returns pending edits in updated-time order.
- `markSynced(...)` stores remote revision, clears dirty state, and moves to `clean`.
- `markConflict(...)` preserves local body while storing remote title/body/revision and moves to `conflict`.

Run:

```bash
pixi run flutter test test/core/offline_edit/local_edit_store_test.dart
```

Expected: FAIL until the store exists.

- [ ] **Step 3: Implement models**

Create `lib/core/offline_edit/local_edit_models.dart` with:

- `enum LocalEditSyncState { clean, pending, syncing, conflict, failed }`
- `class LocalTextEdit`
- fields: `localId`, `remoteId`, `title`, `body`, `baseRevision`, `dirty`, `syncState`, `updatedAtMs`, `lastSyncedAtMs`, `conflictRemoteRevision`, `conflictRemoteTitle`, `conflictRemoteBody`.

- [ ] **Step 4: Implement store**

Create `lib/core/offline_edit/local_edit_store.dart`.

Required API:

```dart
factory LocalEditStore.inMemory();
Future<LocalTextEdit> saveDraft({String? remoteId, required String title, required String body, required String? baseRevision, required int nowMs});
Future<List<LocalTextEdit>> listPendingEdits();
Future<LocalTextEdit?> readByRemoteId(String remoteId);
Future<LocalTextEdit?> readByLocalId(String localId);
Future<void> markSynced({required String localId, required String remoteId, required String revision, required int nowMs});
Future<void> markConflict({required String localId, required String remoteRevision, required String remoteTitle, required String remoteBody, required int nowMs});
Future<void> close();
```

Required SQLite table:

```sql
CREATE TABLE IF NOT EXISTS local_text_edits (
  local_id TEXT PRIMARY KEY,
  remote_id TEXT,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  base_revision TEXT,
  dirty INTEGER NOT NULL,
  sync_state TEXT NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  last_synced_at_ms INTEGER,
  conflict_remote_revision TEXT,
  conflict_remote_title TEXT,
  conflict_remote_body TEXT
);
```

- [ ] **Step 5: Verify and commit**

```bash
pixi run flutter test test/core/offline_edit/local_edit_store_test.dart
git add pubspec.yaml pubspec.lock lib/core/offline_edit/local_edit_models.dart lib/core/offline_edit/local_edit_store.dart test/core/offline_edit/local_edit_store_test.dart
git commit -m "feat: add Dart local note edit store"
```

Expected: tests pass and commit succeeds.

## Task 4: Runtime Note Client and Offline Sync

**Files:**
- Create: `lib/core/cloud/runtime_note_client.dart`
- Create: `test/core/cloud/runtime_note_client_test.dart`
- Create: `lib/core/offline_edit/local_edit_sync_service.dart`
- Create: `test/core/offline_edit/local_edit_sync_service_test.dart`

- [ ] **Step 1: Write failing client tests**

Required test cases:

- `RuntimeNoteClient.saveNote(...)` sends `PUT`, bearer auth, title, body, and `base_revision`.
- A `200` response parses id, title, body, revision, and timestamp.
- A `409` response throws `RuntimeNoteConflictException` containing remote note data.

Run:

```bash
pixi run flutter test test/core/cloud/runtime_note_client_test.dart
```

Expected: FAIL until client exists.

- [ ] **Step 2: Implement `RuntimeNoteClient`**

Required public types:

```dart
class RuntimeNote {}
class RuntimeNoteConflictException implements Exception {}
class RuntimeNoteClient {}
```

Required API:

```dart
Future<RuntimeNote> saveNote({
  required String vaultId,
  required String noteId,
  required String title,
  required String body,
  required String? baseRevision,
});
```

- [ ] **Step 3: Write failing sync service tests**

Required test cases:

- `flushPending()` saves pending edits and calls `markSynced`.
- `flushPending()` catches `RuntimeNoteConflictException` and calls `markConflict`.
- Non-conflict failures leave the edit retryable as `failed`.

- [ ] **Step 4: Implement `LocalEditSyncService`**

Required constructor dependencies:

- `LocalEditStore store`
- note save callback or `RuntimeNoteClient`
- `int Function() nowMs`

No dependency on `SyncEngine`, `NativeAppBackend`, `SecretaryBackend`, or Rust APIs.

- [ ] **Step 5: Verify and commit**

```bash
pixi run flutter test test/core/cloud/runtime_note_client_test.dart test/core/offline_edit/local_edit_sync_service_test.dart
git add lib/core/cloud/runtime_note_client.dart test/core/cloud/runtime_note_client_test.dart lib/core/offline_edit/local_edit_sync_service.dart test/core/offline_edit/local_edit_sync_service_test.dart
git commit -m "feat: sync offline note edits through runtime API"
```

Expected: tests pass and commit succeeds.

## Task 5: Offline Text Note UI

**Files:**
- Create: `lib/features/notes/note_editor_controller.dart`
- Create: `lib/features/notes/note_editor_page.dart`
- Create: `lib/features/notes/note_list_page.dart`
- Create: `test/features/notes/note_editor_controller_test.dart`
- Create: `test/features/notes/note_editor_page_test.dart`

- [ ] **Step 1: Write failing controller tests**

Required test cases:

- Editing while offline saves into `LocalEditStore`.
- Online save flushes through `LocalEditSyncService`.
- Conflict state exposes local text and remote text.
- Controller imports do not reference `lib/src/rust`, `NativeAppBackend`, or `SyncEngine`.

- [ ] **Step 2: Implement `NoteEditorController`**

Required responsibilities:

- Load existing note from `RuntimeNoteClient` when online.
- Save every explicit user save into `LocalEditStore` first.
- Flush when online.
- Expose states: `clean`, `pending`, `saving`, `conflict`, `failed`.

- [ ] **Step 3: Write failing widget tests**

Required test cases:

- Title and body fields render.
- Offline save shows pending state.
- Conflict panel shows local and remote content.
- Body field handles at least 10,000 characters without overflow.

- [ ] **Step 4: Implement note pages**

Create:

- `NoteListPage`: search, sort, dirty/conflict badges.
- `NoteEditorPage`: title field, plain text/markdown body field, save state, conflict panel.

Do not include AI semantic controls in the note editor.

- [ ] **Step 5: Verify and commit**

```bash
pixi run flutter test test/features/notes/note_editor_controller_test.dart test/features/notes/note_editor_page_test.dart
git add lib/features/notes test/features/notes
git commit -m "feat: add offline note editor"
```

Expected: tests pass and commit succeeds.

## Task 6: Attachment Inventory, Preview, and Cleanup

**Files:**
- Modify: `lib/core/cloud/vault_attachments_client.dart`
- Modify: `test/core/cloud/vault_attachments_client_test.dart`
- Create: `lib/features/attachments/attachment_preview_descriptor.dart`
- Create: `lib/features/attachments/attachment_storage_controller.dart`
- Create: `test/features/attachments/attachment_storage_controller_test.dart`
- Modify: `lib/features/settings/vault_usage_card.dart`
- Modify: `test/vault_attachment_usage_list_view_test.dart`

- [ ] **Step 1: Extend HTTP client tests**

Required test cases:

- Parse `id`, `display_name`, `linked_entities`, `preview.url`, `preview.thumbnail_url`, `processing_status`, and `can_delete`.
- `fetchAttachmentPreview(...)` calls `/preview`.
- `fetchDeleteImpact(...)` calls `/delete-impact`.
- `deleteVaultAttachment(...)` accepts attachment id and keeps sha fallback compatibility.

- [ ] **Step 2: Extend `VaultAttachmentsClient`**

Add value types:

- `VaultAttachmentPreview`
- `VaultAttachmentLinkedEntity`
- `VaultAttachmentDeleteImpact`

Keep existing fields and tests working for grouped video and sha-only responses.

- [ ] **Step 3: Write failing controller tests**

Required test cases:

- List refresh sorts by size descending.
- Preview returns signed URL descriptor and records local cache access.
- Delete loads impact before invoking delete.
- Local cache cleanup deletes cache metadata only and does not call cloud delete.

- [ ] **Step 4: Implement `AttachmentStorageController`**

Dependencies:

- `VaultAttachmentsClient`
- local cache metadata store

Forbidden dependencies:

- `NativeAppBackend`
- `SyncEngine`
- Rust attachment APIs

- [ ] **Step 5: Update storage UI**

Modify `VaultUsageCard` and `VaultAttachmentUsageListView`:

- Display name before MIME type.
- Show size, upload time, linked entities, and processing status.
- Add type/sort filters.
- Add preview action.
- Add delete impact confirmation before cloud delete.
- Add separate local cache cleanup action.

- [ ] **Step 6: Verify and commit**

```bash
pixi run flutter test test/core/cloud/vault_attachments_client_test.dart test/features/attachments/attachment_storage_controller_test.dart test/vault_attachment_usage_list_view_test.dart
git add lib/core/cloud/vault_attachments_client.dart test/core/cloud/vault_attachments_client_test.dart lib/features/attachments/attachment_preview_descriptor.dart lib/features/attachments/attachment_storage_controller.dart test/features/attachments/attachment_storage_controller_test.dart lib/features/settings/vault_usage_card.dart test/vault_attachment_usage_list_view_test.dart
git commit -m "feat: manage attachment storage through cloud inventory"
```

Expected: tests pass and commit succeeds.

## Task 7: Remove Local-First Sync From Product Path

**Files:**
- Modify: `lib/features/settings/sync_settings_page.dart`
- Modify: `lib/features/settings/cloud_runtime_mode_page.dart`
- Modify: `lib/core/sync/sync_engine_gate.dart`
- Create: `test/runtime_first_removes_local_sync_modes_test.dart`

- [ ] **Step 1: Write product-path guard test**

Required assertions:

- Runtime Mode exposes only `managed pro` and `self-managed/open-source`.
- WebDAV and local directory sync are not reachable from runtime-first settings.
- Chat, notes, and attachment storage pages do not instantiate `SyncEngine`.

- [ ] **Step 2: Remove old sync settings from visible product path**

Keep reset/dev helpers available for test scripts where still needed, but remove WebDAV/localDir/managed-vault sync as user-facing product modes.

- [ ] **Step 3: Verify and commit**

```bash
pixi run flutter test test/runtime_first_removes_local_sync_modes_test.dart test/features/settings/runtime_mode_page_test_ids_test.dart test/cloud_runtime_mode_page_test.dart
git add lib/features/settings lib/core/sync test/runtime_first_removes_local_sync_modes_test.dart test/features/settings/runtime_mode_page_test_ids_test.dart test/cloud_runtime_mode_page_test.dart
git commit -m "refactor: remove local sync from runtime-first product path"
```

Expected: tests pass and commit succeeds.

## Task 8: Main App Rust Dependency Guard and Removal

2026-05-17 execution note: only the runtime-client guard subset is in scope for this pass. Full physical Rust deletion is deferred because the current main backend, chat/settings/legacy attachment paths, `pubspec.yaml`, platform plugin registration, and web build tasks still depend on FRB/Rust. The next deletion plan must first replace those paths with Dart/runtime interfaces, then remove Rust from the main App dependency graph while keeping any self-managed helper Rust in an isolated helper scope.

**Files:**
- Create: `test/no_rust_dependency_for_runtime_client_test.dart`
- Modify: `pubspec.yaml`
- Delete after replacements pass: `lib/src/rust/`
- Delete after replacements pass: `rust/`
- Delete after replacements pass: `rust_builder/`
- Delete after replacements pass: `third_party/flutter-rust-bridge-patched/`

- [ ] **Step 1: Write Rust dependency guard test**

The test must scan:

- `lib/core/cloud`
- `lib/core/offline_edit`
- `lib/features/notes`
- `lib/features/attachments`
- `lib/features/chat`
- `lib/features/settings`

It must fail on:

- `src/rust`
- `flutter_rust_bridge`
- `rust_core.`
- `rust_attachments.`
- `NativeAppBackend`

- [ ] **Step 2: Remove Rust imports from runtime-first paths**

Replace failing imports with Dart HTTP clients, `LocalEditStore`, and attachment storage controller APIs from earlier tasks.

For this pass, scan only the migrated runtime-client surfaces: `lib/core/cloud`, `lib/core/offline_edit`, `lib/features/notes`, the new cloud attachment preview/storage controller files, runtime mode settings page, and vault usage card. Do not include legacy `chat`, old attachment DB flows, or self-managed helper internals until their runtime interfaces exist.

- [ ] **Step 3: Remove main App Rust packages**

Remove from `pubspec.yaml`:

```yaml
flutter_rust_bridge:
secondloop_rust:
```

Remove platform build references to `rust_builder` and generated FRB bindings.

- [ ] **Step 4: Delete Rust main App source**

```bash
rm -rf lib/src/rust rust rust_builder third_party/flutter-rust-bridge-patched
```

If the self-managed helper still needs Rust, create or keep it in a separate helper package outside these App runtime dependencies before deleting shared Rust code.

- [ ] **Step 5: Verify and commit**

```bash
pixi run flutter test test/no_rust_dependency_for_runtime_client_test.dart
pixi run flutter test
git add pubspec.yaml pubspec.lock lib test
git add -u
git commit -m "refactor: remove Rust from main client runtime"
```

Expected: tests pass and commit succeeds.

## Task 9: QA and Acceptance Updates

**Files:**
- Modify: `docs/qa/managed-pro-manual-qa.md`
- Modify: `docs/qa/cloudflare-agents-automation-testing-runbook.md`
- Modify: `docs/superpowers/plans/README.md`

- [x] **Step 1: Update managed pro QA**

Add managed pro checks for:

- Create/edit a note online.
- Edit the same note offline and see pending state.
- Reconnect and confirm the note syncs.
- Force a revision conflict and confirm local and remote text are visible.
- Open attachment storage list.
- Sort attachments by size.
- Preview image/PDF/audio/video items.
- Delete an attachment after impact confirmation.
- Clear local attachment cache without deleting cloud attachment records.

- [x] **Step 2: Update automation runbook**

Add automation mapping for:

- `LocalEditStore` tests.
- `RuntimeNoteClient` tests.
- Note editor widget tests.
- Attachment inventory client/controller tests.
- Rust dependency guard test.

- [x] **Step 3: Verify docs references and commit**

```bash
rg -n "Rust|local runtime|WebDAV|localDir|offline|attachment|note" docs/qa docs/superpowers/plans
git add -f docs/qa/managed-pro-manual-qa.md docs/qa/cloudflare-agents-automation-testing-runbook.md docs/superpowers/plans/README.md docs/superpowers/plans/2026-05-17-client-dart-http-runtime-implementation-plan.md
git commit -m "docs: add runtime-first client QA coverage"
```

Expected: Mentions of Rust/local runtime are historical, self-managed-helper specific, or removal-oriented. QA must not instruct managed pro testers to exercise local-first sync.

---

## Full Verification Gate

Run App checks:

```bash
cd /Users/logictan/.t3/worktrees/SecondLoop/t3code-f5fd1b79
pixi run flutter test test/core/offline_edit/local_edit_store_test.dart
pixi run flutter test test/core/cloud/runtime_note_client_test.dart test/core/cloud/vault_attachments_client_test.dart
pixi run flutter test test/features/notes/note_editor_controller_test.dart test/features/notes/note_editor_page_test.dart
pixi run flutter test test/features/attachments/attachment_storage_controller_test.dart test/vault_attachment_usage_list_view_test.dart
pixi run flutter test test/no_rust_dependency_for_runtime_client_test.dart
pixi run flutter test
```

Run Server checks:

```bash
cd /Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer/workers/vault-service
npm test -- test/note_routes.test.js test/attachment_inventory_routes.test.js
```

Run managed pro acceptance after staging has both Server and App changes:

```bash
cd /Users/logictan/.t3/worktrees/SecondLoop/t3code-f5fd1b79
pixi run managed-pro-acceptance-dry-run
pixi run managed-pro-acceptance
```

## Migration Safety Notes

- Do not delete Rust before the Dart note store, note HTTP client, attachment inventory client, and UI tests pass.
- Do not port old WebDAV/localDir/managed-vault sync to Dart. Replace it with runtime profile plus note edit outbox.
- Do not move OCR, ASR, embedding, semantic parse, or attachment chunk search into Dart. Those belong in runtime or skill Workers.
- Do not make attachment preview depend on local file availability. Preview should use signed cloud URLs and local cache only as an optimization.
- Do not let conflict resolution silently overwrite remote text. Store both local and remote versions and show a user-visible conflict state.

## Success Criteria

- Managed pro App runs without Rust or local runtime dependency.
- Self-managed helper remains isolated from normal App request flow.
- Chat/capture semantics stay runtime-first.
- Offline plain-text note editing works without network and syncs through HTTP when online.
- Revision conflicts are explicit and recoverable.
- Users can view cloud attachment list, storage usage, previews, linked entities, and delete impact.
- Users can clear local attachment cache separately from deleting cloud attachments.
- Main App tests include a guard that prevents runtime-first client paths from importing generated Rust bindings.
