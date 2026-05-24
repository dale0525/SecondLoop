# Stitch screen 12 connect Cloudflare security refinement

## Goal

Implement and verify the twelfth canonical Stitch product screen:
`Setup: Connect Cloudflare (Security Refinement)`.

The screen demonstrates the first self-managed setup step: securely linking the
user's Cloudflare account through OAuth or least-privilege manual credentials
without presenting high-privilege tokens as persistent app configuration.

## Confirmed Facts

- Stitch screenId:
  `7296ed1e87b9466489af5de513f0e24b`.
- Manifest dimensions: mobile, width `780`, height `1926`.
- Local design sources:
  - `docs/stitch-export/secondloop-operating-system/html/21-setup-connect-cloudflare-security-refinement-7296ed1e87b9466489af5de513f0e24b.html`
  - `docs/stitch-export/secondloop-operating-system/screens/21-setup-connect-cloudflare-security-refinement-7296ed1e87b9466489af5de513f0e24b.jpg`
- Stitch source shows:
  - transactional onboarding without app top/bottom nav;
  - `Infrastructure Connection`, step 1 of 4;
  - primary `Connect Cloudflare Account` OAuth action;
  - advanced manual configuration for account id and API token;
  - least-privilege hint `Workers: Edit`;
  - explicit safety copy that authorization is setup-helper-only and not stored
    as persistent business configuration.
- Product and QA docs require in-App Cloudflare authorization/deployment setup,
  no manual Wrangler requirement, no high-privilege token persistence, and
  owned D1/KV/R2/runtime resources.

## Screen Mapping

| Stitch screenId | Local route/component/state/API target |
| --- | --- |
| `7296ed1e87b9466489af5de513f0e24b` | Settings self-managed setup entry -> Cloudflare connection step; setup controller authorization handoff, OAuth/manual credential form state, validation, deployment helper session, and secret safety boundary. |

## Requirements

- Before implementation, record the Stitch-vs-local differences for setup shell,
  OAuth action, manual credential fields, validation, safety copy, and
  navigation/actions.
- OAuth connection must call a real authorization handoff path or show a clear
  unavailable/degraded state.
- Manual account id/token inputs must be treated as setup-helper session data,
  not persistent app business config.
- The UI must explain resource ownership and provider cost ownership without
  implying managed pro requires Cloudflare.
- Verification must cover error/validation states for missing account id/token
  when manual mode is used.
- Self-managed manual QA requiring a real Cloudflare account must be recorded as
  pending/N/A when credentials are unavailable.
- Keep responsive automated coverage for narrow mobile, manifest width, and
  desktop width.

## Acceptance Criteria

- [ ] Screen mapping and Stitch-vs-local difference list are recorded before
      implementation edits.
- [ ] Cloudflare OAuth/manual setup state is backed by setup controller data or
      explicit degraded states.
- [ ] High-privilege token data is not persisted as normal app configuration.
- [ ] A focused widget/scenario test covers narrow mobile, `780` width, and
      desktop width.
- [ ] Computer Use manual review is performed at the manifest width.
- [ ] Fresh relevant Flutter tests, analyze/typecheck, `pixi run verify-changed`,
      and `git diff --check` are recorded before closeout.

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
