# Stitch screen 11 self-managed setup provider secrets

## Goal

Implement and verify the eleventh canonical Stitch product screen:
`Self-managed Setup: Provider Secrets and Capability Verification (Approved)`.

The screen demonstrates the self-managed setup stage after Cloudflare
authorization, where provider secrets are written to the user's Cloudflare
runtime, capability checks gate progress, and the runtime manifest reports
availability without storing high-privilege secrets as app business config.

## Confirmed Facts

- Stitch screenId:
  `113754579c364c3b994e7bfbaa6f99d6`.
- Manifest dimensions: mobile, width `780`, height `3900`.
- Local design sources:
  - `docs/stitch-export/secondloop-operating-system/html/20-self-managed-setup-provider-secrets-113754579c364c3b994e7bfbaa6f99d6.html`
  - `docs/stitch-export/secondloop-operating-system/screens/20-self-managed-setup-provider-secrets-113754579c364c3b994e7bfbaa6f99d6.jpg`
- Stitch source shows:
  - setup progress rail: Cloudflare Authorized, Provider Secrets, Capability
    Checks, Runtime Manifest;
  - OpenAI/Anthropic/Custom provider secret selector;
  - secret copy stating keys are stored as Cloudflare runtime secrets, not app
    storage;
  - Cloudflare authorization safety cards;
  - capability verification rows for structured output, secretary metadata,
    tool discipline, multimodal understanding, Chinese intent, context/latency,
    clarification, and side-effect discipline;
  - runtime manifest with endpoint, vault binding, skill availability report,
    and provider cost owner.
- Product and QA docs require self-managed setup to be App-driven, write BYOK
  secrets to the user's runtime, run capability verification, and block ready
  state when required checks fail.

## Screen Mapping

| Stitch screenId | Local route/component/state/API target |
| --- | --- |
| `113754579c364c3b994e7bfbaa6f99d6` | Settings runtime mode -> self-managed setup flow (`SelfManagedSetupPage` / setup controller); provider secret form, setup helper handoff, capability verification state, runtime manifest persistence, skill availability report, and profile config. |

## Requirements

- Before implementation, record the Stitch-vs-local differences for setup
  progress, provider secret entry, safety copy, capability checks, manifest,
  and bottom actions.
- Provider secrets must not be persisted as ordinary app business config or
  displayed in plain text after entry.
- Secret write actions must call a real setup helper/runtime-secret path or
  show an honest degraded/unavailable state.
- Capability verification must gate continuation: side-effect discipline or any
  required check failure prevents ready/continue state.
- Runtime manifest display must come from setup/controller state, not hardcoded
  static values in production code.
- Self-managed manual QA requiring real Cloudflare/provider accounts must be
  recorded as `live QA pending` or `N/A - self-managed was not manually tested`
  when credentials are unavailable.
- Keep responsive automated coverage for narrow mobile, manifest width, and
  desktop width.

## Acceptance Criteria

- [ ] Screen mapping and Stitch-vs-local difference list are recorded before
      implementation edits.
- [ ] Provider secret, capability verification, and runtime manifest states are
      backed by setup controller/runtime data or explicit degraded states.
- [ ] Continue/ready state is blocked when required capability checks fail.
- [ ] A focused widget/scenario test covers narrow mobile, `780` width, and
      desktop width.
- [ ] Computer Use manual review is performed at the manifest width.
- [ ] Fresh relevant Flutter tests, analyze/typecheck, `pixi run verify-changed`,
      and `git diff --check` are recorded before closeout.

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
