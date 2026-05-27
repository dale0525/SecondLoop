# Frontend Quality Guidelines

Write focused Flutter tests around the behavior being changed. Do not rely on
manual inspection when existing test seams can verify the flow.

## Widget Tests

- Use `testWidgets` for pages, dialogs, cards, and shell behavior.
- Wrap UI with the same scopes the production widget expects:
  `AppBackendScope`, `SessionScope`, `CloudAuthScope`, `SubscriptionScope`, and
  `AppPlatformCapabilityScope`.
- Use `wrapWithI18n(...)` when testing text that depends on generated
  translations.
- Set a fixed surface size for responsive shell or workbench tests and reset it
  in `addTearDown`.
- Interact through stable `ValueKey` values where available.
- When testing horizontally scrollable tab bars such as `AgentTabBar`, call
  `tester.ensureVisible(find.text(label))` before tapping tabs that may sit
  outside the default 800px widget-test viewport. This keeps the test aligned
  with the real scrollable UI instead of depending on a wider artificial
  surface.

## Runtime Stitch Screen Functional Tests

### 1. Scope / Trigger

- Trigger: a canonical Stitch screen renders runtime-owned state, approval
  cards, media results, drafts, or tool evidence in `AgentConversationPage`.
- Do not stop at a final-state fixture test when the screen represents a user
  workflow. Add a functional widget test that exercises at least one real UI
  action boundary such as send, approve, reject, edit, or refresh.

### 2. Signatures

- Runtime send seam:
  `ChatRuntimeConversationSender.send({vaultId, conversationId, message})`.
- Runtime state seam:
  `RuntimeAgentStateRepository.fetchAgentState({vaultId, conversationId,
  turnLimit, turnBefore, turnOrder})`.
- Approval seam when relevant:
  `ChatRuntimeApprovalSender.submitApprovalDecision(...)` and
  `patchApprovalItem(...)`.

### 3. Contracts

- The sender may return immediate metadata, but the widget should refresh
  `RuntimeAgentStateRepository` after user actions and render from the refreshed
  runtime state when available.
- Current-fact answers must surface citation/tool evidence from runtime fields
  such as `webResearchDrafts`, `citationsJson`, context snapshots, or tool
  trace metadata.
- Approval, draft-only, media, and safety cards must come from
  machine-readable runtime records or approval items, not parsed assistant text.

### 4. Validation & Error Matrix

- Missing refreshed runtime state -> assert the honest empty/degraded UI, not a
  fabricated success card.
- Missing citations for current facts -> assert `CITATIONS: MISSING` or no
  verified-source success copy.
- Unsupported approval patch field -> assert the edit affordance is absent or
  unavailable.

### 5. Good/Base/Bad Cases

- Good: start with `RuntimeAgentState.empty(...)`, enter text through
  `chat_input`, tap `chat_send`, have the fake sender update a mutable
  repository, then assert refreshed runtime evidence is visible.
- Base: keep a final-state fixture test for pixel/structure regression at the
  Stitch manifest width.
- Bad: inject only the final fixture and claim the send/approval workflow is
  covered.

### 6. Tests Required

- Assert the outbound user message or approval decision was captured by the
  fake sender.
- Assert the repository was fetched again after the action.
- Assert the key runtime-backed labels, citations, draft/degraded states, or
  approval metadata appear after refresh.

### 7. Wrong vs Correct

#### Wrong

```dart
await tester.pumpWidget(screenWithFinalRuntimeState());
expect(find.text('VERIFIED SOURCES'), findsOneWidget);
```

#### Correct

```dart
await tester.pumpWidget(screenWithMutableRuntimeRepository());
await tester.enterText(find.byKey(const ValueKey('chat_input')), prompt);
await tester.tap(find.byKey(const ValueKey('chat_send')));
await tester.pumpAndSettle();

expect(sender.sentMessages, [prompt]);
expect(repository.requests.length, greaterThanOrEqualTo(2));
expect(find.text('VERIFIED SOURCES'), findsOneWidget);
```

Reference files:

- `test/agent_conversation_test_support.dart`
- `test/agent_conversation_runtime_approval_test.dart`
- `test/app_shell_agent_tabs_test.dart`
- `test/web_app/web_app_gate_test.dart`

## Client And Service Tests

Use `MockClient` to verify HTTP method, path, headers, body, and response
handling. Avoid live network calls in unit/widget tests.

Reference files:

- `test/runtime_api_client_test.dart`
- `test/secretary_runtime_client_test.dart`
- `test/web_app/web_app_service_http_test.dart`
- `test/core/cloud/http_json_client_test.dart`

## Verification

- Run `pixi run verify-changed` before committing changed app code.
- Run targeted `pixi run flutter test <paths>` for the feature under change.
- Run `pixi run ci` before sharing broad UI or runtime-client changes.
- If a test touches preferences, initialize `SharedPreferences` with mock values.

Reference files:

- `pixi.toml`
- `scripts/verify_changed.sh`
- `scripts/run_full_ci_parallel.sh`

## Accessibility And QA Handles

Keys are not a substitute for accessible labels, but the current test strategy
depends on stable keys for repeatable QA and widget tests. Add keys to new
important actions and rendered runtime cards.
