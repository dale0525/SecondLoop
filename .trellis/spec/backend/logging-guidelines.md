# Logging Guidelines

Logging is intentionally limited in the app. Prefer persisted event records for
user-visible diagnostics and `debugPrint` only for best-effort local diagnostics.

## Persisted Event Logs

Use typed records when users or support flows need recent diagnostic history.
The update flow stores bounded, pruned `UpdateEventRecord` entries in
`SharedPreferences`.

Reference files:

- `lib/core/update/update_event_log.dart`
- `lib/core/update/app_update_service.dart`
- `test/update_event_log_test.dart`
- `test/support/app_update_service_test_support.dart`

## Debug Diagnostics

- Use `debugPrint` for best-effort cleanup or platform diagnostic messages that
  should not affect behavior.
- Include a short stable prefix so logs can be searched, such as
  `sync replace-local:` or `cloud sync switch:`.
- Do not log bearer tokens, refresh tokens, API keys, secure blob payloads,
  vault contents, private runtime internals, or private service paths.

Reference files:

- `lib/core/sync/cloud_sync_switch_prompt_gate.dart`
- `lib/core/sync/vault_replace_local_guard.dart`
- `lib/core/update/auto_upgrade_gate.dart`

## Tests

When logging behavior matters, inject an in-memory logger rather than scraping
console output.

Reference files:

- `test/app_update_service_test.dart`
- `test/app_update_service_check_test.dart`
- `test/support/app_update_service_test_support.dart`
