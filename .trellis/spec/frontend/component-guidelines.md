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

## Agent Operating Shell Runtime Cards

- Render operating-shell action cards from machine-readable runtime state:
  `RuntimeAgentState.workingSetRecords` for state records and
  `SecretaryRuntimeApprovalItem.kind` for approval candidates. Do not parse
  assistant message text to decide whether to create pending intents, reminders,
  memories, tasks, or approvals.
- Keep approval controls wired to runtime callbacks. For example,
  `memory_confirmation` and `recurring_reminder_confirmation` cards should call
  the shared approval decision path, and editable recurring reminder titles
  should use the runtime approval patch path only when `editableFields` contains
  `title`.
- Candidate-only flows should not render empty chrome. Suppress processing
  strips and context strips when the only available state is pending approvals
  and every context value would be `none`, `none yet`, or `0 files`.
- Put larger operating-shell domain cards in a sibling `part` file when
  `agent_conversation_layouts.dart`, `agent_operating_system_cards.dart`, or
  `agent_conversation_widgets.dart` is close to the 1000-line source limit.

Reference files:

- `lib/features/agent_ui/agent_conversation_layouts.dart`
- `lib/features/agent_ui/agent_operating_system_cards.dart`
- `lib/features/agent_ui/agent_operating_reminder_cards.dart`
- `test/agent_conversation_stitch_third_screen_test.dart`

## User-Facing Copy

Prefer generated i18n access through `context.t` for user-facing copy in app
surfaces. Some legacy strings remain, but new reusable UI should not hard-code
localizable text without a reason.

Reference files:

- `lib/i18n/strings.g.dart`
- `lib/features/settings/cloud_account_panel.dart`
- `lib/features/notes/note_editor_page.dart`
- `lib/features/agent_ui/agent_conversation_widgets.dart`
