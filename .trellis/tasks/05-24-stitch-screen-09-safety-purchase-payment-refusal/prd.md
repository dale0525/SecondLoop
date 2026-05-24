# Stitch screen 09 safety purchase payment refusal

## Goal

Implement and verify the ninth canonical Stitch product screen:
`Safety: Purchase Payment Refusal (Approved)`.

The screen demonstrates the purchase/payment safety boundary. The agent must
refuse or safely downgrade transaction requests and must not claim to buy,
book, pay, or call external transaction tools.

## Confirmed Facts

- Stitch screenId:
  `8c87969f58254457bfb9dd85718fdd49`.
- Manifest dimensions: mobile, width `780`, height `2182`.
- Local design sources:
  - `docs/stitch-export/secondloop-operating-system/html/18-safety-purchase-payment-refusal-8c87969f58254457bfb9dd85718fdd49.html`
  - `docs/stitch-export/secondloop-operating-system/screens/18-safety-purchase-payment-refusal-8c87969f58254457bfb9dd85718fdd49.jpg`
- Stitch source shows:
  - user request `帮我直接买两张明天去上海的高铁票并付款。`;
  - `Blocked External Transaction`;
  - assistant refusal stating no transaction was initiated;
  - safe alternatives for research, checklist creation, and reminder;
  - safety metadata for `purchase-payment-safety`, blocked action
    `ticket purchase + payment`, `Refused / No external action`, audit id,
    source id, and tool trace `safe-check-v2`.
- Product and QA docs require purchase/payment/booking/transfer/signing style
  actions to be refused or downgraded, with no external side effect.

## Screen Mapping

| Stitch screenId | Local route/component/state/API target |
| --- | --- |
| `8c87969f58254457bfb9dd85718fdd49` | `AgentConversationPage` mobile shell; safety refusal surface backed by runtime `purchase-payment-safety` skill result/tool trace; optional safe alternatives represented as real follow-up intents, draft/candidate actions, or disabled/degraded actions. |

## Requirements

- Before implementation, record the Stitch-vs-local differences for refusal
  bubble, safe alternatives, safety protocol metadata, and composer/nav layout.
- The UI must clearly state that the purchase/payment was refused and no
  external action was taken.
- Runtime metadata must identify the safety skill, blocked action, source id,
  audit id, and tool trace where available.
- Safe alternatives may include research, checklist, or reminder preparation,
  but each control must be real or explicitly degraded.
- Do not add a purchase, payment, ticket-booking, or hidden external-action
  tool path.
- Keep responsive automated coverage for narrow mobile, manifest width, and
  desktop width.

## Acceptance Criteria

- [ ] Screen mapping and Stitch-vs-local difference list are recorded before
      implementation edits.
- [ ] Purchase/payment request renders refusal and no-side-effect metadata from
      runtime state.
- [ ] Safe alternatives do not perform blocked external actions.
- [ ] A focused widget test covers narrow mobile, `780` width, and desktop
      width.
- [ ] Computer Use manual review is performed at the manifest width.
- [ ] Fresh relevant Flutter tests, analyze/typecheck, `pixi run verify-changed`,
      and `git diff --check` are recorded before closeout.

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
