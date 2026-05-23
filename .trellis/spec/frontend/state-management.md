# State Management And Forms

The app uses Flutter-native state patterns: inherited scopes, `ChangeNotifier`
controllers, `TextEditingController`, local `setState`, `AnimatedBuilder`, and
`ValueListenableBuilder`. There is no global Redux/Riverpod-style state library
in the current code.

## App-Level Scopes

Use inherited scopes for cross-cutting dependencies:

- `AppBackendScope` for backend access.
- `SessionScope` for unlocked session key and lock callback.
- `CloudAuthScope` for auth controller and gateway config.
- `SubscriptionScope` for subscription status.
- `AppPlatformCapabilityScope` for platform capability switches.

Reference files:

- `lib/app/app.dart`
- `lib/core/session/session_scope.dart`
- `lib/core/cloud/cloud_auth_scope.dart`
- `lib/core/subscription/subscription_scope.dart`
- `lib/core/platform/app_platform_capability_scope.dart`
- `lib/core/navigation/inherited_scope_page_wrapper.dart`

## Controller-Owned State

- Store form controllers and focus nodes in the owning `State` object.
- Initialize controllers in `initState` or field initializers, dispose them in
  `dispose`, and resubscribe in `didUpdateWidget` when the injected controller
  changes.
- Use `AnimatedBuilder` when a `ChangeNotifier` controller owns the source of
  truth and the widget only renders it.

Reference files:

- `lib/features/settings/cloud_account_panel.dart`
- `lib/features/settings/self_managed_setup_page.dart`
- `lib/features/settings/self_managed_setup_sections.dart`
- `lib/features/notes/note_editor_page.dart`

## Form Fields

- Current forms mostly use `TextField` with `TextEditingController`, not
  `Form`/`GlobalKey<FormState>`.
- Disable inputs and submit buttons with local busy flags while async work is
  running.
- Trim user input at action boundaries before sending it to controllers or
  clients.
- Use `ValueListenableBuilder<TextEditingValue>` when button enabled state
  depends on live text input.
- Use `DropdownButtonFormField`, `SwitchListTile`, or existing settings rows
  when they match the current control type.

Reference files:

- `lib/features/settings/cloud_account_auth_section.dart`
- `lib/features/settings/self_managed_setup_sections.dart`
- `lib/features/agent_ui/agent_conversation_widgets.dart`
- `lib/features/actions/time/date_time_picker_dialog.dart`
- `lib/features/settings/media_annotation_settings_page_embedded.dart`

## Async UI Rules

- Guard duplicate submissions with `_busy` or equivalent per-action state.
- Check `mounted` after awaited calls before `setState`, snackbar display, or
  navigation.
- Keep transient errors in local state when the owning widget displays them.

Reference files:

- `lib/features/settings/cloud_account_panel.dart`
- `lib/features/agent_ui/agent_conversation_page.dart`
