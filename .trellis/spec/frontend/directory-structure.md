# Frontend Directory Structure

SecondLoop's frontend is Flutter. Keep UI code close to the feature it serves
and move only repeated primitives into shared UI modules.

## App Shell

- `lib/app/` owns app startup, scopes, theme, shell navigation, and default tab
  wiring.
- `AppShell` is tab-based rather than route-table based. It uses `AppTab`
  values, lazy tab loading, responsive rail/bottom-nav layout, and injected tab
  builders for tests.
- Platform-specific default page builders use conditional imports.

Reference files:

- `lib/app/app.dart`
- `lib/app/router.dart`
- `lib/app/app_shell_default_pages_shared.dart`
- `lib/app/app_shell_default_pages_io.dart`
- `lib/app/app_shell_default_pages_web.dart`
- `test/app_shell_agent_tabs_test.dart`

## Feature Folders

- Put pages, cards, dialogs, feature controllers, and feature-specific helpers
  under `lib/features/<feature>/`.
- Keep agent UI split into focused files: page orchestration, layout helpers,
  runtime helpers, send logic, cards, tokens, and acceptance driver.
- Keep settings UI sections under `lib/features/settings/` and share local
  settings primitives through `settings_ui.dart`.

Reference files:

- `lib/features/agent_ui/agent_conversation_page.dart`
- `lib/features/agent_ui/agent_conversation_widgets.dart`
- `lib/features/agent_ui/agent_conversation_send.dart`
- `lib/features/settings/settings_ui.dart`
- `lib/features/settings/cloud_account_panel.dart`

## Shared UI

- Use `lib/ui/` for cross-feature primitives such as buttons, surfaces,
  background, focus rings, markdown styling, and shared dialogs.
- Use feature-local tokens only when they are clearly tied to one feature family.

Reference files:

- `lib/ui/sl_button.dart`
- `lib/ui/sl_surface.dart`
- `lib/features/agent_ui/agent_design_tokens.dart`
- `lib/features/agent_ui/agent_operating_system_tokens.dart`

Do not create framework-style directories that do not match the current Flutter
codebase, such as React hooks, pages/routes folders, or frontend API route
handlers.
