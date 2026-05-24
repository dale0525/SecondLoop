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
- Treat `task_mutation_confirmation` as a family of mutation approvals, not as
  a single title-change shape. Render the title-diff approval card only when
  the runtime item explicitly advertises title editing (`editableFields`
  contains `title`) or provides title-specific fields such as `current_title`,
  `proposed_title`, `new_title`, or `target_title`. Due-time/status mutations
  must keep a due/status approval preview instead of showing a false title diff.
- When adding a new runtime approval kind, keep
  `agent_conversation_layouts.dart` as a dispatcher only. Put the typed payload
  projection next to the card, for example
  `CalendarEventApprovalDetails.fromRuntime(...)`, and centralize repeated raw
  `record` field reads in a helper such as
  `runtime_approval_record_helpers.dart`. The card may format derived display
  labels, but it must not claim external side effects happened before the
  runtime approval state says so.
- Calendar/email approval cards must render from runtime approval items such as
  `calendar_event_confirmation`, using `calendar_event_id` plus `record` fields
  (`title`, time labels or `starts_at_ms` / `ends_at_ms`, participants,
  source/tool metadata, audit/context refs, and approval status). Edit controls
  should be visibly unavailable unless a real approval patch path is wired for
  the advertised editable field.
- Runtime media result cards must project `kind == media_result` records from
  `RuntimeAgentState.workingSetRecords` or the context snapshot working set,
  then associate them to assistant turns with explicit assistant/source ids
  before falling back to attachment matching. Keep the typed projection in
  `agent_runtime_media_results.dart`, not inline in the page dispatcher.
- OCR/image media results must keep extracted text separate from summaries.
  Read OCR text from fields such as `ocr_text` / `ocrText` / `text`, read
  summary from fields such as `summary` / `llm_summary`, and label the display
  as `OCR TEXT`. Do not reuse transcript or meeting-minutes labels for image
  OCR.
- Media metadata such as `source_id`, `confidence_percent`, and
  `saved_to_vault` must come from runtime fields or render as honest degraded
  values. The UI must not claim Vault save/sync just because an attachment or
  media card exists.
- When adding image/OCR attachment fixtures, use decodable image bytes and test
  both the chat tile and attachment detail surface. A tile navigation test
  should fail if the viewer renders a codec error instead of the image preview.
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
- `test/agent_conversation_stitch_sixth_screen_test.dart`

## User-Facing Copy

Prefer generated i18n access through `context.t` for user-facing copy in app
surfaces. Some legacy strings remain, but new reusable UI should not hard-code
localizable text without a reason.

Reference files:

- `lib/i18n/strings.g.dart`
- `lib/features/settings/cloud_account_panel.dart`
- `lib/features/notes/note_editor_page.dart`
- `lib/features/agent_ui/agent_conversation_widgets.dart`
