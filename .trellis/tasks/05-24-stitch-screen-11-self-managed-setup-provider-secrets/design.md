# Stitch screen 11 self-managed setup design

## Source Mapping

| Stitch screenId | Local route | Local component | State owner | Runtime/API owner |
| --- | --- | --- | --- | --- |
| `113754579c364c3b994e7bfbaa6f99d6` | Settings -> Runtime mode -> self-managed setup | `SelfManagedSetupPage` with `SelfManagedSetupSections` | `SelfManagedSetupController` / `SelfManagedSetupState` | `LocalRuntimeHelperProcess.runSetup`, `RuntimeConnectionStore.saveConnection`, `CloudRuntimeManifest`, `ModelCapabilityVerificationResult` |

Manifest baseline: mobile, `780 x 3900`.

Design source:

- `docs/stitch-export/secondloop-operating-system/html/20-self-managed-setup-provider-secrets-113754579c364c3b994e7bfbaa6f99d6.html`
- `docs/stitch-export/secondloop-operating-system/screens/20-self-managed-setup-provider-secrets-113754579c364c3b994e7bfbaa6f99d6.jpg`

## Stitch-vs-local differences

### UI

- Stitch has a compact top bar with `SecondLoop`, `self-managed`, and `verification required` chips; local page currently uses the default settings shell app bar.
- Stitch starts with a horizontal setup progress rail: Cloudflare Authorized, Provider Secrets, Capability Checks, Runtime Manifest. Local page has no progress rail.
- Stitch provider entry is a dense card with OpenAI / Anthropic / Custom segmented selection, an obscured API key field, explicit runtime-secret copy, and a `Write secrets` action. Local page uses plain stacked text fields for provider, API key, embedding key, and multimodal key.
- Stitch includes Cloudflare authorization safety cards explaining setup-helper-only usage, no business-config persistence, revocation, and user-owned resources. Local page has no equivalent.
- Stitch displays a capability verification table with per-check status rows and a failed/pending `Side-effect Discipline` row. Local page only shows a status text and optional error code.
- Stitch displays a runtime manifest card with endpoint URL, vault binding, skill availability, and provider cost owner. Local page only prints the endpoint URL when a manifest exists.
- Stitch bottom actions are fixed: Back, Run checks, Continue disabled until verification passes. Local page has a normal settings action bar with authorize, deploy, retry, reset.

### Functionality

- Local controller already has a real setup path through `LocalRuntimeHelperProcess.runSetup`, but the default helper is currently unavailable and must be surfaced honestly as `self_managed_helper_unavailable`.
- Local controller blocks ready state when `ModelCapabilityVerificationResult.ok == false` or required runtime capabilities are missing; screen 11 needs that gate visible in the fixed Continue button.
- Local setup saves runtime profile/manifest through `RuntimeConnectionStore`, and tests already assert provider API keys are not persisted. The UI needs to make this secret boundary explicit.
- The page needs provider selection controls that write the provider request value instead of a free text provider field.
- The page needs real actions for `Write secrets` and `Run checks`; both should call the existing setup helper path rather than rendering inert buttons.

### State flow

- Stitch screen represents the post-Cloudflare provider-secret step. Current local page starts from idle and has a separate authorize action. For this screen, the UI will render the canonical progress rail while still letting the existing helper emit authorizing/deploying/verifying/ready/failed states.
- Capability rows will be projected from `ModelCapabilityVerificationResult.checks`, with missing/not-yet-run checks rendered as honest pending state. Failed required checks keep Continue disabled.
- Helper-unavailable, missing provider config, verification failure, and missing runtime capability must remain explicit degraded/error states.

### Data/API wiring

- Provider, API key, embedding key, and multimodal key remain inputs to `SelfManagedSetupRequest`; secret values are only passed to the setup helper and are not displayed after entry.
- Runtime manifest values come from `CloudRuntimeManifest`, not hardcoded production state. If missing, the UI renders `pending`.
- Skill availability count comes from `CloudRuntimeManifest.skills`; if missing, the UI renders `pending`.
- Vault binding is not yet part of `CloudRuntimeManifest`. The screen may derive a degraded/pending display from available capabilities without adding a fake persisted field.

## Technical approach

- Keep the implementation in the existing settings feature. Use `SelfManagedSetupPage` for shell/bottom actions and `SelfManagedSetupSections` for screen sections.
- Extend `SelfManagedSetupSections` into focused private widgets for progress, provider secrets, Cloudflare safety, verification rows, and manifest fields. Do not paste exported HTML.
- Preserve existing stable keys used by tests where possible, and add keys for the new screen actions and verification/manifest sections.
- Keep fields obscured for provider secrets. Do not show entered key values outside the password field.
- Continue is enabled only when `controller.state.isReady == true`; Back calls `Navigator.maybePop`; Run checks and Write secrets both call the real `_deployCurrentRequest` path.
- Keep response sizing bounded by `maxWidth: 800`, mobile padding `16`, and a fixed bottom action bar to match the manifest width.

## Compatibility and rollback

- Existing callers keep using `SelfManagedSetupPage(controller: ...)`; no route migration is required.
- Existing `SelfManagedSetupRequest` and controller runner tests stay valid, with new assertions added for gate and UI projection.
- If the new layout regresses, rollback is limited to `self_managed_setup_page.dart`, `self_managed_setup_sections.dart`, and focused tests.
