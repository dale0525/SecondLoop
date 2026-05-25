# Stitch Screen 12 Design

## Screen Mapping

| Stitch screenId | Stitch title | Local route/component | Local state/API |
| --- | --- | --- | --- |
| `7296ed1e87b9466489af5de513f0e24b` | Setup: Connect Cloudflare (Security Refinement) | Settings self-managed setup entry -> `SelfManagedSetupPage` / `SelfManagedSetupSections` | `SelfManagedSetupController`, `SelfManagedSetupRequest`, `LocalRuntimeHelperProcess`, setup-helper Cloudflare authorization handoff, manual account/token validation, runtime manifest save only after verification |

## Stitch Inputs

- Manifest role: canonical, area `Cloudflare connection`.
- Dimensions: mobile, width `780`, height `1926`.
- HTML: `docs/stitch-export/secondloop-operating-system/html/21-setup-connect-cloudflare-security-refinement-7296ed1e87b9466489af5de513f0e24b.html`.
- Screenshot: `docs/stitch-export/secondloop-operating-system/screens/21-setup-connect-cloudflare-security-refinement-7296ed1e87b9466489af5de513f0e24b.jpg`.

## Stitch vs Local Differences

### UI

- Stitch is a transactional onboarding card centered on the page with no app top
  bar, tab rail, or bottom navigation. The current local page still has a
  settings shell top bar and bottom action bar from screen 11.
- Stitch header copy is `Infrastructure Connection`, `Step 1 of 4`, with a
  four-segment progress indicator where only the first segment is active. The
  local page starts later in the flow with provider secrets, capability checks,
  and runtime manifest sections.
- Stitch primary visible action is `Connect Cloudflare Account`, followed by an
  advanced manual section. The local page currently exposes Cloudflare account
  as a plain label inside the provider secrets card and does not present OAuth
  as the first-class step.
- Stitch manual fields are `Cloudflare Account ID` and `API Token`, with the
  `Workers: Edit` least-privilege hint and a visibility control. The local page
  asks for provider secrets first and lacks account-token validation UI.
- Stitch footer repeats the safety boundary: setup-helper-only Cloudflare
  authorization, no persistent business config, BYOK secrets written to the
  user's own Cloudflare runtime secrets. Local safety content exists but is
  separated into screen 11 cards and is not the screen 12 first viewport.

### Functionality

- OAuth action must trigger a real controller state transition. Since the local
  helper cannot complete browser OAuth in this repo today, it should surface an
  honest degraded `tool_unavailable` / helper-unavailable state instead of a
  fake connected result.
- Manual configuration must be real form state. Empty account id or API token
  should block verification and show inline validation without invoking the
  helper.
- Manual API token must be treated as setup-helper session input. It must not be
  written to `RuntimeConnectionStore` or displayed in manifest/profile state.
- `Verify Connection` should invoke the setup controller only after manual
  validation passes, and the controller remains responsible for saving runtime
  metadata only after deployment, health check, required model verification, and
  required runtime capabilities pass.

### State Flow

- Current local flow: fill provider secrets -> run setup -> helper authorizes
  Cloudflare -> deploys -> verifies -> saves runtime connection.
- Required screen 12 flow: start with Cloudflare connection -> OAuth degraded
  handoff or manual account/token session data -> verify connection -> later
  provider secrets and deployment checks.
- Error states must include missing account id, missing API token, helper
  unavailable, deploy failure, model capability failure, and ready state.

### Data/API Wiring

- `SelfManagedSetupRequest` needs a setup authorization shape that can represent
  OAuth, manual account id, and manual setup token without conflating Cloudflare
  token with persistent runtime auth token.
- `SelfManagedRuntimeDeployRunner` / `SelfManagedCloudflareAuth` should consume
  the setup authorization input for deployment automation, but the returned
  `CloudRuntimeConnection` should only persist runtime profile metadata and the
  runtime auth token.
- Tests should assert manual token material is captured by helper input and not
  present in saved runtime profile/manifest.

## Product Boundary Decisions

- Keep this screen self-managed-only. Managed pro must not imply Cloudflare is
  required.
- Do not add direct Cloudflare management APIs in the app. The app initiates
  setup-helper handoff or passes session-scoped manual credentials to the helper.
- Do not store high-privilege Cloudflare management tokens as business config.
- Manual live deployment with a real Cloudflare account remains `live QA
  pending` unless real credentials are available.
