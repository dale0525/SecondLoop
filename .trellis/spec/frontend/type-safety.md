# Dart Type Safety

Use Dart models and enums to keep runtime, UI, and tests aligned. Avoid passing
untyped maps through UI layers when a local model already exists.

## Models

- Use immutable model classes for decoded runtime and UI contracts.
- Provide `fromJson` factories close to the model that owns the wire contract.
- Normalize loosely typed `Map` values with `Map<String, dynamic>.from(...)` or
  explicit entry mapping before reading fields.
- Convert numeric JSON values with `(value as num?)?.toInt()` when the wire can
  provide any numeric type.

Reference files:

- `lib/core/cloud/secretary_runtime_client.dart`
- `lib/core/cloud/runtime_agent_state_models.dart`
- `lib/web_app/web_app_service.dart`
- `test/secretary_runtime_client_test.dart`
- `test/core/cloud/runtime_agent_state_models_test.dart`

## Enums And Wire Values

Use enums with explicit wire conversion when values cross a storage or API
boundary. Keep the wire string near the enum rather than scattering literals in
widgets.

Reference files:

- `lib/core/backend/app_backend.dart`
- `lib/core/cloud/runtime_manifest.dart`
- `lib/core/cloud/runtime_profile.dart`
- `lib/core/update/update_event_log.dart`

## Callbacks

Use typed callbacks such as `VoidCallback`, `ValueChanged<T>`, and small
typedefs for injected client factories. This keeps widget tests simple and
avoids dynamic callback maps.

Reference files:

- `lib/features/agent_ui/agent_conversation_widgets.dart`
- `lib/features/settings/cloud_account_panel.dart`
- `lib/core/backend/native_backend.dart`

Avoid adding TypeScript-specific guidance to this repo; app code is Dart.
