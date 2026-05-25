# Stitch screen 2-8 functional alignment implementation plan

## Preparation

- [ ] Load frontend/backend specs with `trellis-before-dev` before editing.
- [ ] Reconfirm git status in both App and Server repos.
- [ ] Build the fresh screen 2-8 diff checklist from Stitch HTML/screenshots,
      product docs, QA docs, existing Flutter tests, and Server contract tests.

## Screen 2: Web Research Continuity

- [ ] Verify real runtime send/fetch path carries `web_research_drafts`,
      `citations_json`, `tool_trace`, context snapshot, and recent-turn
      continuity.
- [ ] Add or update frontend functional test so the UI is exercised through
      send -> runtime state refresh, not only injected final state.
- [ ] Add Server test only if citation/follow-up state is missing.
- [ ] Run focused Flutter and Server tests, then Computer Use review at width
      780.

## Screen 3: Recurring Reminder Clarification

- [ ] Expose pending intents in Server `agent-state` or add an App model field
      that consumes an existing Server pending-intent payload.
- [ ] Ensure missing birthday produces pending intent/clarification and no
      active recurring reminder.
- [ ] Ensure supplied birthday produces separate memory and recurring-reminder
      approvals with editable title and approval decision wiring.
- [ ] Add functional frontend and Server tests.
- [ ] Run focused tests and Computer Use review at width 780.

## Screen 4: Task Mutation Approval

- [ ] Update Server task mutation approval contract for title changes:
      editable title, current/proposed title diff, target id, resolver,
      context/audit/tool metadata.
- [ ] Ensure approval patch updates pending task mutation without applying the
      formal task change.
- [ ] Ensure approval applies only after decision.
- [ ] Add functional frontend and Server tests.
- [ ] Run focused tests and Computer Use review at width 780.

## Screen 5: Calendar Approval From Email Extraction

- [ ] Support combined memory candidate plus calendar event candidate in one
      runtime result.
- [ ] Keep calendar event creation approval-gated and edit honestly unavailable
      unless runtime patch exists.
- [ ] Add functional frontend and Server tests.
- [ ] Run focused tests and Computer Use review at width 780.

## Screen 6: File OCR Attachment

- [ ] Preserve rich media result fields through Server result metadata and
      agent-state: OCR text, summary, source id, confidence, saved-to-vault,
      attachment id, citations, status.
- [ ] Keep attachment tile tappable and image preview backed by bytes when
      available.
- [ ] Support optional runtime-backed reminder candidate if emitted.
- [ ] Add functional frontend and Server tests.
- [ ] Run focused tests and Computer Use review at width 780.

## Screen 7: Meeting Audio Action Candidates

- [ ] Preserve audio media fields: meeting id, transcript, minutes, duration,
      high-fidelity confirmation, decisions, action items, saved-to-vault.
- [ ] Convert runtime action candidates to approval items.
- [ ] Make Create/Dismiss approval decisions mutate runtime state honestly.
- [ ] Add functional frontend and Server tests.
- [ ] Run focused tests and Computer Use review at width 780.

## Screen 8: Email Unauthorized Draft Only

- [ ] Add Server handling for email `needs_configuration` /
      `tool_unavailable` with draft-only and blocked-tool projection records.
- [ ] Ensure no `email_send_confirmation` approval is created for the
      unauthorized path.
- [ ] Keep frontend Save Draft / Connect Email degraded actions honest.
- [ ] Add functional frontend and Server tests.
- [ ] Run focused tests and Computer Use review at width 780.

## Shared Validation

- [ ] Focused Flutter tests for modified screens.
- [ ] `pixi run flutter analyze` for modified App files/tests.
- [ ] `pixi run verify-changed` in App.
- [ ] Focused Server tests for modified runtime files.
- [ ] Broader Server test command if runtime contract changes are shared.
- [ ] `git diff --check` in both repos.
- [ ] File line-count check for modified files, especially Server runtime
      files near 1000 lines.

## Closeout

- [ ] Update task PRD acceptance boxes with evidence.
- [ ] Use `trellis-check` for final verification.
- [ ] Record per-screen completion output requested by the user.
- [ ] If Server changed, prepare/push Server changes only after tests pass and
      confirm no tracked file contains sensitive Server information.
