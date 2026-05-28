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
- The root app palette is a single SecondLoop product palette. App-wide light
  and dark colors live in `AppShellPalette`, `AppTheme`, `AppThemeStyleSpec`,
  and `SlTokens`; do not add user-facing palette/style selectors or make
  `AppThemePalettePrefs` change visible app colors. Keep only the
  light/dark/system appearance mode selector wired through `AppThemeModePrefs`.
- The production app shell Settings tab is `AgentSettingsPage`; legacy
  `SettingsPage` still exists for deeper/native settings flows. Shared
  appearance controls such as light/dark/system must use
  `SettingsThemeModeRow` or another reusable settings primitive so both
  surfaces stay consistent.
- `AgentSettingsPage` owns production app-level preferences in its first
  `General` tab: appearance, language, app reminder preferences, desktop boot
  behavior, Quick Capture hotkey, About / update, welcome guide, and
  diagnostics. Account, Connection, Permissions, Memory, and Activity tabs
  should keep their domain-specific settings instead of absorbing these
  app-level rows.
- When legacy `SettingsPage` and `AgentSettingsPage` need the same behavior
  (for example language labels/dialogs or Quick Capture hotkey validation),
  extract feature-local helpers under `lib/features/settings/` and call them
  from both surfaces. Do not copy dialog or validation logic between the two
  pages.
- Treat dark mode as a first-class token mapping, not a generated inversion of
  the light theme. Shared widgets should read `Theme.of(context).colorScheme`
  or `SlTokens.of(context)` so they pick up `AppShellPalette.dark*` values
  automatically.
- The app shell itself must follow the active app brightness. Do not wrap
  `AppShell`, Settings, runtime mode, or onboarding surfaces in
  `AppTheme.light(...)` unless the surface is deliberately locked and tested as
  a light-only artifact.
- First-launch and onboarding routes must be created after UI preferences
  (`AppThemeModePrefs` and palette normalization) are initialized. Onboarding
  widgets that install a local `Theme` must still read backgrounds, panels,
  borders, dividers, and text from `Theme.of(context).colorScheme` or
  `SlTokens.of(context)`; switching to `AppTheme.dark(...)` is not enough if
  descendants keep hard-coded light `AppShellPalette` constants.
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
- Desktop workbench shell controls are product controls, not decorative
  chrome. App-tab destinations should select real `AppTab` entries; non-tab
  destinations such as Memory, Approvals, or Connectors must either open a real
  page/sheet or surface an explicit degraded state such as
  `needs_configuration` or `tool_unavailable`.
- Quick Capture is a desktop hotkey/service affordance for capturing while the
  app is out of focus, not an always-visible app-shell entry. Do not add a
  desktop workbench FAB, plus button, or other persistent in-app Quick Capture
  launcher. Keep `AppShell` listening to `QuickCaptureController` requests so
  the desktop hotkey path can return to Chat when the overlay closes with
  `openChat`.
- Desktop workbench tool traces must fail closed. Show successful labels such
  as `web-research: executed`, `skill_result_response`, or
  `CITATIONS: PRESENT` only when the runtime state provides trace metadata and
  assistant citation evidence. If trace fields or citations are absent, render
  `not reported`, `tool_unavailable`, or `CITATIONS: MISSING` rather than
  defaulting to success copy.
- Keep approval controls wired to runtime callbacks. For example,
  `memory_confirmation` and `recurring_reminder_confirmation` cards should call
  the shared approval decision path, and editable recurring reminder titles
  should use the runtime approval patch path only when `editableFields` contains
  `title`.
- Desktop approval queues must keep fail-closed runtime items visible in the
  default attention view. Treat `needs_configuration`, `tool_unavailable`,
  `refused`, purchase/payment safety refusals, and local-computer safety
  refusals as queue items even when they cannot be approved; disable approve /
  reject controls for those states and show configure, retry, or unavailable
  messaging only when backed by a real path or honest degraded behavior.
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
- Disconnected email draft-only flows must render from
  `RuntimeAgentState.workingSetRecords`, not assistant text. Use
  `kind == email_draft` / `email_draft_candidate` records for draft fields
  (`to` or `recipients`, `subject`, `body`, `source`, `audit_id` / `draft_id`)
  and `kind == external_tool_block`, `external_side_effect_blocked`,
  `email_authorization_block`, or `tool_blocked` records for fail-closed
  metadata (`reason`, `connector`, `blocked_action`, `status_label`, `risk`,
  `audit_id`, `tool`). Generic external block kinds such as
  `external_side_effect_blocked` must still be confirmed as email-specific via
  `tool` or `blocked_action` before rendering an email guardrail; purchase,
  payment, local-computer, or other safety blocks belong to their own card
  families. The UI must not render a send/approve action for this state; `Save
  Draft` and connector actions must either call a real local path or show an
  honest unavailable/configuration result. Suppress empty context strips when
  the only available runtime state is an email draft plus its guardrail record.
- Purchase/payment safety refusal cards must render from machine-readable
  runtime records, not assistant prose. Match `purchase-payment-safety` /
  `external_side_effect_blocked` records through explicit source or assistant
  turn ids, display the blocked action, no-external-action status, audit/source
  ids, and tool trace, and do not create an approval path for the transaction.
  Safe alternatives may prefill or create research, checklist, or reminder
  follow-ups, but must never initiate buying, booking, payment, transfer, or
  signing.
- Local-computer safety refusal cards are a separate safety family from
  purchase/payment. Match `local-computer-safety` records through explicit
  runtime fields such as `skill`, `skill_id`, `runtime_skill`, `tool`,
  `blocked_action`, `source_message_id`, and `assistant_turn_id`; do not infer
  them from assistant text. Generic `external_side_effect_blocked` records must
  only render as local-computer safety when the explicit skill or blocked action
  names shell, terminal, local file, Finder, desktop, or local computer
  operation. Display no-side-effect evidence (`No command executed`, `No local
  file access`, `No terminal automation`), audit/source/tool metadata, and only
  manual guidance or a safe follow-up prompt. Do not add approval, shell,
  Finder, desktop automation, or local file mutation actions.
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
- Keep repository-backed `RuntimeAgentState.approvalItems` and immediate
  send-result approval metadata distinct. The operating message list may render
  operating-system cards when `runtimeState` is present, but when approvals only
  came from the latest send result and `runtimeState == null`, preserve the
  existing `_buildRuntimeApprovalCards` acceptance-card path so memory/task
  approval flows keep their established keys, copy, and tests.
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
