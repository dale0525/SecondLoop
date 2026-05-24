# Stitch screen 08 email unauthorized draft only

## Goal

Implement and verify the eighth canonical Stitch product screen:
`Email Unauthorized: Draft Only (Approved)`.

The screen demonstrates the fail-closed email boundary: when email is not
connected, the app may prepare a draft or configuration prompt, but must not
claim that an email was sent or produce an external side effect.

## Confirmed Facts

- Stitch screenId:
  `a8435575721c43b9a5398a242abc28d0`.
- Manifest dimensions: mobile, width `780`, height `2112`.
- Local design sources:
  - `docs/stitch-export/secondloop-operating-system/html/17-email-unauthorized-draft-only-a8435575721c43b9a5398a242abc28d0.html`
  - `docs/stitch-export/secondloop-operating-system/screens/17-email-unauthorized-draft-only-a8435575721c43b9a5398a242abc28d0.jpg`
- Stitch source shows:
  - managed-pro chat shell with `Email Not Connected`;
  - user request `直接把周报邮件发给 Alice。`;
  - assistant response stating email cannot be sent because Email is not
    connected;
  - draft card `Draft: Weekly Report` with recipient, subject, body, source,
    and audit metadata;
  - guardrail card `Email Blocked: Authorization Required` with connector,
    blocked action, fail-closed status, risk, audit id, and `tool: email.send`.
- Product and QA docs require unauthorized email/calendar to degrade to draft,
  `needs_configuration`, or `tool_unavailable`, with no external side effect.

## Screen Mapping

| Stitch screenId | Local route/component/state/API target |
| --- | --- |
| `a8435575721c43b9a5398a242abc28d0` | `AgentConversationPage` mobile shell; email degraded/draft surfaces in shared agent operating cards or calendar/email card patterns; state from runtime email skill result metadata, draft records, connector availability, audit/tool trace metadata, and no send approval execution. |

## Requirements

- Before implementation, record the Stitch-vs-local differences for draft
  rendering, connector unavailable state, guardrail metadata, and action
  affordances.
- The UI must not show or imply successful send when email is disconnected.
- A generated draft may be shown only as draft/local candidate state, with
  recipient, subject, body, source, and audit metadata.
- Connector unavailable state must be explicit: `needs_configuration`,
  `tool_unavailable`, or equivalent runtime status.
- The `Connect Email` affordance must route to a real connector/setup flow or
  an honest unavailable state.
- Save Draft must use a real draft path when available or clearly degrade.
- No send side effect may happen in this screen.
- Keep responsive automated coverage for narrow mobile, manifest width, and
  desktop width.

## Stitch-vs-Local Difference Record

- Stitch renders a dedicated mobile managed-pro chat shell for the unauthorized
  email flow, with a top status pill `Email Not Connected`; the local shell
  already has the managed-pro chat frame but does not yet surface connector
  availability in the operating header for this runtime state.
- Stitch shows the user request `直接把周报邮件发给 Alice。` followed by an
  assistant refusal that explicitly says email cannot be sent because Email is
  not connected; local runtime chat bubbles can show this text, but no
  screen-specific safety card exists yet to reinforce that no send occurred.
- Stitch has a standalone `Draft: Weekly Report` card with To, Subject, Body,
  Source, Audit, `Save Draft`, and `Connect Email`; local code has a
  `CalendarEmailCard` demo/acceptance card with an email draft section, but it
  is bundled with calendar availability/invite sections and is not mapped from
  runtime email-skill metadata.
- Stitch has a `Email Blocked: Authorization Required` guardrail card with
  reason, connector, blocked action, fail-closed status, risk, audit id, and
  `tool: email.send`; local runtime approval cards cover task/calendar/memory
  and meeting action candidates, but there is no runtime-backed external-tool
  block / email authorization card.
- Stitch's `Save Draft` and `Connect Email` are safe affordances: they must
  either call a real local path or render as honest unavailable/configuration
  actions; local implementation must avoid adding a `Send` or approval action
  for the disconnected email state.

## Acceptance Criteria

- [x] Screen mapping and Stitch-vs-local difference list are recorded before
      implementation edits.
- [x] Unauthorized email request renders draft-only and fail-closed guardrail
      state from runtime metadata.
- [x] No UI text or state claims that an email was sent.
- [x] A focused widget test covers narrow mobile, `780` width, and desktop
      width.
- [x] Computer Use manual review is performed at the manifest width.
- [x] Fresh relevant Flutter tests, analyze/typecheck, `pixi run verify-changed`,
      and `git diff --check` are recorded before closeout.

## Closeout Evidence

- Stitch screenId:
  `a8435575721c43b9a5398a242abc28d0`.
- Local route/component mapping:
  `AgentConversationPage` mobile operating shell. Runtime records are projected
  from `RuntimeAgentState.workingSetRecords`: `email_draft` for the draft-only
  card and `external_tool_block` / related blocked-tool kinds for the
  fail-closed email guardrail. The top app bar derives `Email Not Connected`
  from the same runtime state.
- Functionality filled:
  unauthorized email now renders as draft-only with recipient, subject, body,
  source, and audit metadata; the blocked `email.send` action renders reason,
  connector, blocked action, fail-closed status, risk, audit id, and tool id.
  `Save Draft` and `Connect Email` are safe degraded local affordances that
  show honest snackbars and do not send email, create approval items, or invoke
  external side effects.
- Modified files:
  - `lib/features/agent_ui/agent_conversation_page.dart`
  - `lib/features/agent_ui/agent_conversation_layouts.dart`
  - `lib/features/agent_ui/agent_operating_email_cards.dart`
  - `test/agent_conversation_stitch_eighth_screen_test.dart`
  - `tools/stitch_screen_08_manual_app.dart`
  - `.trellis/spec/frontend/component-guidelines.md`
  - this task PRD
- Computer Use manual review:
  launched `tools/stitch_screen_08_manual_app.dart` in the macOS Flutter debug
  app at manifest width `780`. Verified the managed-pro header, `Email Not
  Connected` status, Chinese user request, assistant refusal, `Draft: Weekly
  Report` fields, draft/source/audit chips, fail-closed guardrail metadata, and
  absence of an empty context strip. Clicked `SAVE DRAFT` and `CONNECT EMAIL`;
  both produced local explanatory snackbars and no send/approval side effect.
- Manual screenshot evidence:
  `build/manual-qa/stitch-screen-08-email-unauthorized-draft-only.png`.
- Known non-1:1 differences:
  the local operating card style uses uppercase footer button labels and a
  Material security icon instead of Stitch's remote illustrative envelope/lock
  image. This keeps the implementation inside existing Flutter primitives and
  avoids adding a decorative remote asset to a safety-critical card.
- Fresh commands run:
  - `pixi run flutter test test/agent_conversation_stitch_eighth_screen_test.dart`
    -> passed, 2 tests.
  - `pixi run flutter test test/agent_conversation_stitch_first_screen_test.dart test/agent_conversation_stitch_second_screen_test.dart test/agent_conversation_stitch_third_screen_test.dart test/agent_conversation_stitch_fourth_screen_test.dart test/agent_conversation_stitch_fifth_screen_test.dart test/agent_conversation_stitch_sixth_screen_test.dart test/agent_conversation_stitch_seventh_screen_test.dart test/agent_conversation_stitch_eighth_screen_test.dart`
    -> passed, 18 tests.
  - `pixi run flutter analyze lib/features/agent_ui/agent_conversation_page.dart lib/features/agent_ui/agent_conversation_layouts.dart lib/features/agent_ui/agent_operating_email_cards.dart test/agent_conversation_stitch_eighth_screen_test.dart tools/stitch_screen_08_manual_app.dart`
    -> passed with no issues.
  - `pixi run flutter analyze tools/stitch_screen_08_manual_app.dart`
    -> passed with no issues.
  - `pixi run verify-changed`
    -> passed, including formatting and full Flutter analyze.
  - `git diff --check`
    -> passed.

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
