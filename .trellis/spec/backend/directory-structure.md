# Core Directory Structure

This repository is a Flutter/Dart app. It does not contain server route
handlers. Treat "backend" specs as app-side core, runtime-client, persistence,
and adapter guidance.

## Ownership

- `lib/core/backend/` owns the local app backend abstraction. `AppBackend` is the
  interface, and `NativeAppBackend` is split with Dart `part` files for local
  implementation slices.
- `lib/core/cloud/` owns HTTP clients, auth/session helpers, runtime connection
  profiles, runtime/vault models, and service clients.
- `lib/core/<domain>/` owns cross-feature services such as sync, update,
  notifications, desktop, AI routing, storage, and platform capabilities.
- `lib/web_app/` owns browser-shell service adapters and web-only app entry
  wiring.
- `lib/features/<feature>/` owns user-facing pages, cards, dialogs, and
  feature-specific controller glue.
- `lib/ui/` owns reusable UI primitives used across multiple features.

Reference files:

- `lib/core/backend/app_backend.dart`
- `lib/core/backend/native_backend.dart`
- `lib/core/cloud/runtime_api_client.dart`
- `lib/web_app/web_app_service.dart`
- `lib/features/settings/cloud_account_panel.dart`
- `lib/ui/sl_button.dart`

## Platform Split

Use conditional imports for platform behavior when an implementation has IO,
web, or stub variants. Keep the shared interface in the unsuffixed file and put
platform specifics in `_io.dart`, `_web.dart`, or `_stub.dart`.

Reference files:

- `lib/app/router.dart`
- `lib/core/cloud/http_client_factory_io.dart`
- `lib/core/cloud/http_client_factory_stub.dart`
- `lib/core/offline_edit/local_edit_store_io.dart`
- `lib/core/offline_edit/local_edit_store_web.dart`

## Boundary Rules

- Do not add product UI state to `lib/core/cloud/`; keep UI state in feature
  widgets/controllers and keep cloud clients transport-focused.
- Do not document private backend repositories, infrastructure, deployment
  internals, secrets, or private logs in Trellis specs.
- If a feature needs a new external contract, document only the app-visible
  request/response shape and the local tests that prove it.
