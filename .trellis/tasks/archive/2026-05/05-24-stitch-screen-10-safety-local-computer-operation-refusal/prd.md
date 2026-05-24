# Stitch screen 10 safety local computer operation refusal

## Goal

Implement and verify the tenth canonical Stitch product screen:
`Safety: Local Computer Operation Refusal (Approved)`.

The screen demonstrates the local-computer safety boundary. Managed pro must not
operate the user's terminal or local files; it can only refuse and optionally
offer safe manual guidance.

## Confirmed Facts

- Stitch screenId:
  `b1bc92c06b364d0594dea7c27cf02802`.
- Manifest dimensions: mobile, width `780`, height `2264`.
- Local design sources:
  - `docs/stitch-export/secondloop-operating-system/html/19-safety-local-computer-operation-refusal-b1bc92c06b364d0594dea7c27cf02802.html`
  - `docs/stitch-export/secondloop-operating-system/screens/19-safety-local-computer-operation-refusal-b1bc92c06b364d0594dea7c27cf02802.jpg`
- Stitch source shows:
  - user request `帮我打开终端执行 rm -rf ~/Downloads/test。`;
  - assistant refusal `I cannot execute terminal commands or modify local files. No action was taken.`;
  - safety protocol items `No command executed`, `No local file access`, and
    `No terminal automation`;
  - alternative manual cleanup checklist;
  - audit metadata for `local-computer-safety`, blocked action
    `shell execution`, source id, and tool trace `safety-check-v2`.
- Product and QA docs require managed pro to refuse local computer operations
  and avoid local shell side effects.

## Screen Mapping

| Stitch screenId | Local route/component/state/API target |
| --- | --- |
| `b1bc92c06b364d0594dea7c27cf02802` | `AgentConversationPage` mobile shell; safety refusal surface backed by runtime `local-computer-safety` skill result/tool trace; optional checklist/draft surface saved to Vault or explicitly degraded. |

## Requirements

- Before implementation, record the Stitch-vs-local differences for refusal
  bubble, safety protocol checklist, manual alternative, audit card, and
  composer/nav layout.
- The UI must clearly state that no command was executed, no local file was
  accessed, and no terminal automation occurred.
- Runtime metadata must identify the safety skill, blocked action, source id,
  audit id/status, and tool trace where available.
- Any alternative checklist must be manual guidance or a vault draft/candidate,
  not an automated local file operation.
- Do not add local shell, Finder, desktop automation, or local file mutation
  behavior to managed pro.
- Keep responsive automated coverage for narrow mobile, manifest width, and
  desktop width.

## Acceptance Criteria

- [ ] Screen mapping and Stitch-vs-local difference list are recorded before
      implementation edits.
- [ ] Local computer request renders refusal and no-side-effect metadata from
      runtime state.
- [ ] Alternative guidance does not perform local shell or file side effects.
- [ ] A focused widget test covers narrow mobile, `780` width, and desktop
      width.
- [ ] Computer Use manual review is performed at the manifest width.
- [ ] Fresh relevant Flutter tests, analyze/typecheck, `pixi run verify-changed`,
      and `git diff --check` are recorded before closeout.

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
