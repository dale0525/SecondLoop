# Persistence Guidelines

The app does not use a general ORM pattern. Persistence is split by use case:
runtime connection metadata, preferences, secure blobs, local edit queues, and
feature-specific caches.

## Local Preferences And Secure Blobs

- Use `SharedPreferences` for non-secret preferences, lightweight JSON state,
  and runtime connection metadata.
- Use `SecureBlobStore` for secret or sensitive grouped values. It serializes
  updates through an internal tail future and stores a JSON map under a scoped
  secure-storage key.
- Tests that touch preferences should call
  `SharedPreferences.setMockInitialValues(...)`.

Reference files:

- `lib/core/cloud/runtime_connection_store.dart`
- `lib/core/cloud/cloud_auth_store.dart`
- `lib/core/storage/secure_blob_store.dart`
- `test/runtime_api_client_test.dart`
- `test/app_theme_mode_prefs_test.dart`

## Local Structured Stores

SQLite is used for explicit local edit storage, not as a blanket app database
rule. Keep local stores behind a small domain class with an in-memory factory
for tests and a platform-backed factory for production.

Reference files:

- `lib/core/offline_edit/local_edit_store_io.dart`
- `lib/core/offline_edit/local_edit_store_web.dart`
- `test/core/offline_edit/local_edit_store_test.dart`

## Runtime-First Data

For agent/runtime features, prefer app-visible runtime/vault client models over
writing authoritative business state into local stores. Existing runtime state
models preserve wire concepts such as tasks, memory records, approvals,
conversation turns, context snapshots, and audit refs.

Reference files:

- `lib/core/cloud/runtime_agent_state_models.dart`
- `lib/core/cloud/runtime_agent_state_repository.dart`
- `lib/core/cloud/secretary_runtime_client.dart`
- `test/core/cloud/runtime_agent_state_models_test.dart`

Avoid using local fallback state as the source of truth for new runtime-first
feature work.
