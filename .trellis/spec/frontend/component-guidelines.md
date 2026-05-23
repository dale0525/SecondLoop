# Component Guidelines

Use Flutter widgets that are small enough to test and review. Prefer explicit
constructor dependencies over hidden globals, and keep orchestration in the
owning page.

## Widget Shape

- Public pages are usually `StatefulWidget` when they own controllers,
  async state, or listeners.
- Private leaf widgets are often `StatelessWidget` or private stateful dialogs.
- Split repeated sections into private widgets in the same file first. Move them
  to a sibling file when the owning file is growing or the widget is reused.

Reference files:

- `lib/features/settings/cloud_account_panel.dart`
- `lib/features/settings/cloud_account_auth_section.dart`
- `lib/features/agent_ui/agent_conversation_widgets.dart`
- `lib/features/notes/note_editor_page.dart`

## Design Tokens And Shared Controls

- Use existing tokens and primitives before adding new styling systems:
  `AppShellPalette`, `AgentDesignTokens`, `SlButton`, `SettingsSection`,
  `SettingsActionBar`, and `SettingsInlineMessage`.
- Use Material icons and `IconButton`/`FilledButton.icon` where the existing UI
  already uses them.
- Keep settings pages composed from settings sections and action bars rather
  than one-off layout primitives.

Reference files:

- `lib/app/app_shell_style.dart`
- `lib/features/settings/settings_ui.dart`
- `lib/features/settings/self_managed_setup_page.dart`
- `lib/features/agent_ui/agent_conversation_widgets.dart`

## Stable Test Handles

Add `ValueKey` values for controls, cards, dialogs, and list items that tests or
manual QA need to locate. Use stable semantic names rather than visual copy.

Reference files:

- `lib/features/agent_ui/agent_conversation_widgets.dart`
- `lib/features/settings/self_managed_setup_page.dart`
- `lib/features/notes/note_editor_page.dart`
- `test/agent_conversation_runtime_approval_test.dart`
- `test/agent_ui/agent_ui_acceptance_driver_test.dart`

## User-Facing Copy

Prefer generated i18n access through `context.t` for user-facing copy in app
surfaces. Some legacy strings remain, but new reusable UI should not hard-code
localizable text without a reason.

Reference files:

- `lib/i18n/strings.g.dart`
- `lib/features/settings/cloud_account_panel.dart`
- `lib/features/notes/note_editor_page.dart`
- `lib/features/agent_ui/agent_conversation_widgets.dart`
