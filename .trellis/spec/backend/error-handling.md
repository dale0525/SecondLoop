# Error Handling

Use narrow, app-visible exceptions at client boundaries and keep UI error
formatting close to the widget that displays the error.

## HTTP Clients

- `RuntimeApiClient` throws `StateError('missing_cloud_runtime_connection')`
  when no runtime profile is available.
- `RuntimeApiClient` throws `CloudRuntimeApiException` for non-2xx responses and
  includes the `uri`, `statusCode`, and response body.
- `RuntimeApiClient` throws `FormatException` when a successful response is not
  the expected JSON object.
- `HttpJsonClient` is a lower-level helper; it returns status/body and lets the
  caller decide which statuses are errors.
- `WebAppServiceHttp` decodes error payloads into `WebAppHttpException` with
  status, body, and optional error code.

Reference files:

- `lib/core/cloud/runtime_api_client.dart`
- `lib/core/cloud/http_json_client.dart`
- `lib/web_app/web_app_service.dart`
- `test/runtime_api_client_test.dart`
- `test/web_app/web_app_service_http_test.dart`

## Conflict And Domain Errors

Use domain-specific exception classes when the caller can recover with structured
data. For example, note conflicts expose the remote note instead of forcing the
UI to parse text.

Reference files:

- `lib/core/cloud/runtime_note_client.dart`
- `test/core/cloud/runtime_note_client_test.dart`

## UI Error Surfacing

- Convert raw exceptions into localized, user-facing copy in the feature widget
  or helper that owns the user flow.
- Use `ScaffoldMessenger` for transient success/failure notices and inline
  message widgets for persistent setup or settings errors.
- Check `mounted` after awaits before calling `setState` or showing UI.

Reference files:

- `lib/features/settings/cloud_account_panel.dart`
- `lib/features/settings/self_managed_setup_sections.dart`
- `lib/features/settings/settings_ui.dart`

Do not parse assistant prose to infer whether a mutation succeeded. Use
structured runtime metadata or client responses.
