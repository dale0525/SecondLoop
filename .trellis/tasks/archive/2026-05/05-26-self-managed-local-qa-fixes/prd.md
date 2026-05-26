# Self-managed local QA fixes

## Goal

Complete the self-managed local QA pass from `docs/qa/self-managed-local-qa.md`
and fix issues found during the pass so the local self-managed runtime contract
matches the managed-pro core capability expectations.

## Requirements

- Continue the manual QA flow from the current ready self-managed Cloudflare
  runtime without leaking provider secrets or Cloudflare authorization tokens.
- Use Computer Use for App interaction during manual QA.
- When the QA doc requires Cloudflare authorization, stop and let the user
  complete the browser authorization step before continuing.
- Preserve existing user/runtime data unless a test step explicitly requires
  cleaning the relevant local authorization or QA runtime state.
- Fix self-managed local QA worker contract gaps discovered during the run,
  especially where the docs require parity with managed-pro behavior.
- Keep fixes scoped to the local QA/runtime contract and focused tests unless
  the App UI itself is proven to be the failing layer.
- Verify code fixes with focused tests, redeploy the Cloudflare worker, and
  re-run the affected manual QA case before moving on.

## Acceptance Criteria

- [ ] SM-TASK-02 remains passing: ambiguous Alex task mutation asks for
      clarification and creates no incorrect approval.
- [ ] SM-REM-01 passes: missing child birthday triggers clarification; after
      birthday is supplied, memory and recurring reminder candidates appear;
      approving both creates active memory and an approved recurring reminder
      whose next trigger is May 31.
- [ ] Remaining ready-mode QA cases are continued in order, with failures fixed
      or recorded as live/provider pending when the docs allow that outcome.
- [ ] Focused tests for changed local QA worker behavior pass.
- [ ] Updated local QA worker is deployed to the self-managed Cloudflare runtime
      before manual re-verification.
- [ ] No secrets, Cloudflare tokens, or provider keys are printed in reports or
      persisted in tracked artifacts.

## Notes

- Current endpoint under test:
  `https://secondloop-22af2c4cb940-secretary-runtime.logictan.workers.dev/`.
- Current QA vault: `CF_D1_PRIMARY_VAULT_APP_QA`.
- The self-managed local QA worker is a deterministic runtime contract used by
  the App-side manual QA flow. It must not hide managed-pro parity bugs behind
  generic fallback responses.
