# Local-First Understanding Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build SecondLoop's final local-first understanding layer by unifying temporal parsing across Ask AI and todo flows, adding a conservative local semantic parser, and demoting LLM usage to an optional enhancement path.

**Architecture:** Introduce one shared Dart temporal engine that parses once and projects results into `retrieval_window`, `todo_due`, and `todo_followup_due` modes. Layer a local-first semantic parser on top of that engine, then keep Rust/Dart LLM parsing only as a bounded enhancement contract for ambiguous cases and culturally specific edge cases when BYOK or cloud is available.

**Tech Stack:** Flutter/Dart, Rust, flutter_test, cargo test, pixi

---

## Scope

- In scope: shared temporal engine, Ask AI temporal migration, todo temporal migration, local-first semantic parser, LLM enhancement contract, follow-up due-date update plumbing.
- Out of scope: retrieval routing, hybrid rerank, embedding/index changes, old data compatibility, MemPalace-style retrieval storage changes.

## File Structure

### `SecondLoop`

- Create: `SecondLoop/lib/core/ai/temporal/temporal_resolution.dart`
  Responsibility: canonical temporal enums, metadata, and shared result types.
- Create: `SecondLoop/lib/core/ai/temporal/temporal_engine.dart`
  Responsibility: orchestration pipeline for normalization, rule resolver, locale plugin resolver, ambiguity scoring, projection, and optional enhancement eligibility.
- Create: `SecondLoop/lib/core/ai/temporal/temporal_rule_resolver.dart`
  Responsibility: fast locale-agnostic rules for absolute dates, relative dates, week/month windows, and point-in-time phrases.
- Create: `SecondLoop/lib/core/ai/temporal/temporal_locale_plugin.dart`
  Responsibility: locale plugin interface and registration helpers.
- Create: `SecondLoop/lib/core/ai/temporal/temporal_locale_plugin_zh_cn.dart`
  Responsibility: `zh-CN` cultural expressions such as `年初一`, `春节后`, and `节后第一个工作日`.
- Create: `SecondLoop/lib/core/ai/local_semantic_parse_result.dart`
  Responsibility: local-first semantic parser contract and diagnostics payload.
- Create: `SecondLoop/lib/core/ai/local_semantic_parser.dart`
  Responsibility: local intent routing, slot extraction, todo candidate linking, and confidence synthesis.
- Modify: `SecondLoop/lib/features/actions/time/time_range_resolver.dart`
  Responsibility: shrink to wrapper or adapter over the shared temporal engine for Ask AI callers.
- Modify: `SecondLoop/lib/features/actions/time/time_resolver.dart`
  Responsibility: shrink to wrapper or adapter over the shared temporal engine for todo callers.
- Modify: `SecondLoop/lib/features/chat/ask_ai_intent_resolver.dart`
  Responsibility: consume `retrieval_window` results instead of bespoke date heuristics.
- Modify: `SecondLoop/lib/features/chat/chat_page_methods_e.dart`
  Responsibility: thread temporal window into Ask AI retrieval without duplicating parsing logic.
- Modify: `SecondLoop/lib/features/actions/todo/message_action_resolver.dart`
  Responsibility: use shared temporal engine for create and follow-up due inference, and expose due-update intent.
- Modify: `SecondLoop/lib/core/ai/semantic_parse.dart`
  Responsibility: compose local parse result with optional LLM enhancement, normalize final contract, and parse enhancement payloads.
- Modify: `SecondLoop/lib/core/ai/semantic_parse_auto_actions_runner.dart`
  Responsibility: run local-first parser first and call enhancement only when policy allows.
- Modify: `SecondLoop/lib/core/ai/semantic_parse_auto_actions_runner_store.dart`
  Responsibility: preserve diagnostics and follow-up due-update signals in queued jobs.
- Modify: `SecondLoop/lib/core/backend/app_backend.dart`
  Responsibility: expose any new semantic-parse enhancement request/response surface.
- Modify: `SecondLoop/lib/core/backend/native_backend_prompt_ai.dart`
  Responsibility: call the new enhancement contract instead of the current parse-only contract.
- Modify: `SecondLoop/lib/core/backend/semantic_parse_attempt_aware_backend.dart`
  Responsibility: gate retries and enhancement attempts under the new local-first policy.
- Test: `SecondLoop/test/temporal_engine_test.dart`
- Test: `SecondLoop/test/ask_ai_temporal_engine_test.dart`
- Test: `SecondLoop/test/time_resolver_test.dart`
- Test: `SecondLoop/test/message_action_resolver_test.dart`
- Test: `SecondLoop/test/local_semantic_parser_test.dart`
- Test: `SecondLoop/test/ai_semantic_parse_test.dart`
- Test: `SecondLoop/test/semantic_parse_auto_actions_runner_test.dart`
- Test: `SecondLoop/test/semantic_parse_jobs_backend_api_test.dart`

### `SecondLoop/rust`

- Modify: `SecondLoop/rust/src/semantic_parse/mod.rs`
  Responsibility: replace the old parse-everything prompt/schema with an enhancement-only contract that can fill or disambiguate local results.
- Modify: `SecondLoop/rust/src/api/core.rs`
  Responsibility: expose enhancement calls and any due-update fields needed by Dart.
- Modify: `SecondLoop/rust/src/db/parts/09a_semantic_parse_jobs.rs`
  Responsibility: persist local-first parse state, diagnostics, and enhancement attempts.
- Modify: `SecondLoop/rust/src/db/parts/09b_semantic_parse_job_mutations.rs`
  Responsibility: apply follow-up due updates and new semantic parse result fields.
- Modify: `SecondLoop/rust/src/db/semantic_parse_jobs_tests.rs`
  Responsibility: verify job persistence and follow-up due-update mutations.

### `SecondLoopServer`

- Modify: `SecondLoopServer/docs/superpowers/specs/2026-04-19-local-first-semantic-and-temporal-design.md`
  Responsibility: only if implementation reveals contract drift that must be reconciled before code lands. Prefer leaving the spec unchanged.

## Task 1: Build Shared Temporal Contracts and Local Resolver Shell

**Files:**
- Create: `SecondLoop/lib/core/ai/temporal/temporal_resolution.dart`
- Create: `SecondLoop/lib/core/ai/temporal/temporal_engine.dart`
- Create: `SecondLoop/lib/core/ai/temporal/temporal_rule_resolver.dart`
- Create: `SecondLoop/lib/core/ai/temporal/temporal_locale_plugin.dart`
- Create: `SecondLoop/lib/core/ai/temporal/temporal_locale_plugin_zh_cn.dart`
- Test: `SecondLoop/test/temporal_engine_test.dart`

- [ ] **Step 1: Write failing temporal engine tests for mode projection, ambiguity, and locale plugins**

```dart
test('retrieval_window projects 上周 into an inclusive past range', () {
  final result = TemporalEngine.resolve(
    text: '上周聊过什么',
    nowLocal: DateTime(2026, 2, 4, 10, 0),
    locale: const Locale('zh', 'CN'),
    timezone: 'Asia/Shanghai',
    firstDayOfWeek: 1,
    mode: TemporalMode.retrievalWindow,
    allowEnhancement: false,
  );

  expect(result.semantics, TemporalSemantics.rangePast);
  expect(result.startLocal, DateTime(2026, 1, 26));
  expect(result.endLocal, DateTime(2026, 2, 2));
});

test('todo_due rejects 上周 and degrades to none', () {
  final result = TemporalEngine.resolve(
    text: '上周提醒我报税',
    nowLocal: DateTime(2026, 2, 4, 10, 0),
    locale: const Locale('zh', 'CN'),
    timezone: 'Asia/Shanghai',
    firstDayOfWeek: 1,
    mode: TemporalMode.todoDue,
    allowEnhancement: false,
  );

  expect(result.resolver, TemporalResolver.none);
  expect(result.dueAtLocal, isNull);
});
```

- [ ] **Step 2: Run the targeted temporal tests to verify the new coverage fails**

Run: `cd SecondLoop && pixi run flutter test test/temporal_engine_test.dart`
Expected: FAIL because the temporal engine files do not exist yet.

- [ ] **Step 3: Implement the temporal contracts, rule resolver, plugin interface, and engine shell**

```dart
enum TemporalMode { retrievalWindow, todoDue, todoFollowupDue }
enum TemporalResolver { rule, localePlugin, llm, none }

final class TemporalResolution {
  const TemporalResolution({
    required this.mode,
    required this.confidence,
    required this.resolver,
    required this.semantics,
    this.dueAtLocal,
    this.startLocal,
    this.endLocal,
    this.metadata = const TemporalMetadata(),
  });
}
```

Implementation notes:

- Normalize text before matching so full-width digits and punctuation do not fork behavior.
- Keep parsing independent from projection; projection decides how one parse maps into each mode.
- Locale plugins may return a candidate, but the engine owns the final confidence and safe fallback logic.
- Return `none` for low-confidence or multi-parse results instead of picking one candidate.

- [ ] **Step 4: Run the temporal tests to verify the engine passes**

Run: `cd SecondLoop && pixi run flutter test test/temporal_engine_test.dart`
Expected: PASS for the new temporal engine tests.

- [ ] **Step 5: Commit the shared temporal foundation**

```bash
git -C SecondLoop add \
  lib/core/ai/temporal/temporal_resolution.dart \
  lib/core/ai/temporal/temporal_engine.dart \
  lib/core/ai/temporal/temporal_rule_resolver.dart \
  lib/core/ai/temporal/temporal_locale_plugin.dart \
  lib/core/ai/temporal/temporal_locale_plugin_zh_cn.dart \
  test/temporal_engine_test.dart
git -C SecondLoop commit -m "✨ feat(ai): add shared temporal engine foundation"
```

## Task 2: Migrate Ask AI Time Understanding to the Shared Temporal Engine

**Files:**
- Modify: `SecondLoop/lib/features/actions/time/time_range_resolver.dart`
- Modify: `SecondLoop/lib/features/chat/ask_ai_intent_resolver.dart`
- Modify: `SecondLoop/lib/features/chat/chat_page_methods_e.dart`
- Create: `SecondLoop/test/ask_ai_temporal_engine_test.dart`
- Modify: `SecondLoop/test/time_range_resolver_today_test.dart`

- [ ] **Step 1: Write failing Ask AI tests for shared retrieval-window behavior**

```dart
test('Ask AI uses temporal engine for 本周 retrieval scope', () {
  final result = resolveAskAiIntent(
    text: '本周我答应了谁什么事？',
    nowLocal: DateTime(2026, 2, 4, 10, 0),
    locale: const Locale('zh', 'CN'),
    firstDayOfWeekIndex: 1,
  );

  expect(result.timeRange?.startLocal, DateTime(2026, 2, 2));
  expect(result.timeRange?.endLocal, DateTime(2026, 2, 9));
});
```

- [ ] **Step 2: Run the Ask AI tests to verify they fail against the old bespoke resolver**

Run: `cd SecondLoop && pixi run flutter test test/ask_ai_temporal_engine_test.dart test/time_range_resolver_today_test.dart`
Expected: FAIL because Ask AI is still wired to the old local-only range resolver path.

- [ ] **Step 3: Replace bespoke Ask AI range inference with temporal engine consumption**

```dart
final resolution = TemporalEngine.resolve(
  text: messageText,
  nowLocal: nowLocal,
  locale: locale,
  timezone: timezone,
  firstDayOfWeek: firstDayOfWeekIndex,
  mode: TemporalMode.retrievalWindow,
  allowEnhancement: allowEnhancement,
);
```

Implementation notes:

- Keep `time_range_resolver.dart` only as an adapter if existing call sites still depend on its type.
- Ask AI must accept `none` and continue retrieval without a time filter.
- Do not duplicate culture-specific parsing rules in `ask_ai_intent_resolver.dart`.

- [ ] **Step 4: Run the Ask AI tests to verify the migration passes**

Run: `cd SecondLoop && pixi run flutter test test/ask_ai_temporal_engine_test.dart test/time_range_resolver_today_test.dart`
Expected: PASS for the Ask AI temporal coverage.

- [ ] **Step 5: Commit the Ask AI temporal migration**

```bash
git -C SecondLoop add \
  lib/features/actions/time/time_range_resolver.dart \
  lib/features/chat/ask_ai_intent_resolver.dart \
  lib/features/chat/chat_page_methods_e.dart \
  test/ask_ai_temporal_engine_test.dart \
  test/time_range_resolver_today_test.dart
git -C SecondLoop commit -m "✨ feat(ai): route ask-ai temporal scope through shared engine"
```

## Task 3: Migrate Todo Time Understanding and Add Follow-Up Due Intent

**Files:**
- Modify: `SecondLoop/lib/features/actions/time/time_resolver.dart`
- Modify: `SecondLoop/lib/features/actions/todo/message_action_resolver.dart`
- Modify: `SecondLoop/test/time_resolver_test.dart`
- Modify: `SecondLoop/test/message_action_resolver_test.dart`

- [ ] **Step 1: Write failing tests for create-due and follow-up-due paths**

```dart
test('followup can extract due update without forcing a status change', () {
  final decision = MessageActionResolver.resolve(
    '把报销改到年初一之后第一个工作日',
    locale: const Locale('zh', 'CN'),
    nowLocal: DateTime(2026, 2, 4, 10, 0),
    openTodoTargets: const [
      TodoLinkTarget(id: 'todo:1', title: '报销', status: 'open'),
    ],
  );

  final follow = decision as MessageActionFollowUpDecision;
  expect(follow.todoId, 'todo:1');
  expect(follow.newStatus, isNull);
  expect(follow.dueAtLocal, isNotNull);
});
```

- [ ] **Step 2: Run the todo temporal tests to verify they fail before migration**

Run: `cd SecondLoop && pixi run flutter test test/time_resolver_test.dart test/message_action_resolver_test.dart`
Expected: FAIL because create and follow-up flows still rely on separate time parsing paths and follow-up due updates are not modeled.

- [ ] **Step 3: Replace todo-specific time parsing with temporal engine projections**

```dart
final dueResolution = TemporalEngine.resolve(
  text: messageText,
  nowLocal: nowLocal,
  locale: locale,
  timezone: timezone,
  firstDayOfWeek: firstDayOfWeekIndex,
  mode: isFollowup ? TemporalMode.todoFollowupDue : TemporalMode.todoDue,
  allowEnhancement: false,
);
```

Implementation notes:

- `todo_due` should convert valid day-level phrases into a due point using current day-end or morning defaults.
- `todo_followup_due` should allow due mutation without inventing a status transition.
- If a phrase is only valid as a retrieval window, do not coerce it into a todo due date.

- [ ] **Step 4: Run the todo temporal tests to verify the shared engine behavior passes**

Run: `cd SecondLoop && pixi run flutter test test/time_resolver_test.dart test/message_action_resolver_test.dart`
Expected: PASS for both create and follow-up due cases.

- [ ] **Step 5: Commit the todo temporal migration**

```bash
git -C SecondLoop add \
  lib/features/actions/time/time_resolver.dart \
  lib/features/actions/todo/message_action_resolver.dart \
  test/time_resolver_test.dart \
  test/message_action_resolver_test.dart
git -C SecondLoop commit -m "✨ feat(todo): unify due-date parsing with temporal engine"
```

## Task 4: Add the Local-First Semantic Parser

**Files:**
- Create: `SecondLoop/lib/core/ai/local_semantic_parse_result.dart`
- Create: `SecondLoop/lib/core/ai/local_semantic_parser.dart`
- Modify: `SecondLoop/lib/core/ai/semantic_parse.dart`
- Create: `SecondLoop/test/local_semantic_parser_test.dart`
- Modify: `SecondLoop/test/ai_semantic_parse_test.dart`

- [ ] **Step 1: Write failing semantic parser tests for intent routing, candidate linking, and conservative fallback**

```dart
test('local parser creates obvious todo without LLM', () {
  final result = LocalSemanticParser.parse(
    text: '明天下午 3 点提交材料',
    nowLocal: DateTime(2026, 2, 4, 10, 0),
    locale: const Locale('zh', 'CN'),
    openTodoTargets: const [],
  );

  expect(result.kind, LocalSemanticParseKind.create);
  expect(result.resolver, SemanticResolver.local);
  expect(result.dueAtLocal, DateTime(2026, 2, 5, 15, 0));
});

test('local parser returns none when followup target is ambiguous', () {
  final result = LocalSemanticParser.parse(
    text: '把这个改到下周',
    nowLocal: DateTime(2026, 2, 4, 10, 0),
    locale: const Locale('zh', 'CN'),
    openTodoTargets: const [
      TodoLinkTarget(id: 'todo:1', title: '报销', status: 'open'),
      TodoLinkTarget(id: 'todo:2', title: '报销', status: 'open'),
    ],
  );

  expect(result.kind, LocalSemanticParseKind.none);
});
```

- [ ] **Step 2: Run local semantic parser tests to verify they fail**

Run: `cd SecondLoop && pixi run flutter test test/local_semantic_parser_test.dart test/ai_semantic_parse_test.dart`
Expected: FAIL because the local-first parser contract does not exist yet.

- [ ] **Step 3: Implement local routing, slot extraction, linking, and contract normalization**

```dart
final class LocalSemanticParseResult {
  const LocalSemanticParseResult({
    required this.kind,
    required this.confidence,
    required this.resolver,
    this.title,
    this.status,
    this.todoId,
    this.dueAtLocal,
    this.recurrenceRule,
    this.taskType,
    this.suggestedTags = const <String>[],
    this.tagConfidence = 0,
    this.diagnostics = const LocalSemanticParseDiagnostics(),
  });
}
```

Implementation notes:

- Use the shared temporal engine instead of embedding time parsing rules inside the local parser.
- Distinguish `ambiguous` from `none` internally if that improves diagnostics, but collapse to conservative output for automation.
- Candidate linking should use explicit title mention, fuzzy similarity, and recency/state weighting before allowing follow-up execution.

- [ ] **Step 4: Run local semantic parser tests to verify the local-first path passes**

Run: `cd SecondLoop && pixi run flutter test test/local_semantic_parser_test.dart test/ai_semantic_parse_test.dart`
Expected: PASS for local routing and parser contract tests.

- [ ] **Step 5: Commit the local-first parser layer**

```bash
git -C SecondLoop add \
  lib/core/ai/local_semantic_parse_result.dart \
  lib/core/ai/local_semantic_parser.dart \
  lib/core/ai/semantic_parse.dart \
  test/local_semantic_parser_test.dart \
  test/ai_semantic_parse_test.dart
git -C SecondLoop commit -m "✨ feat(ai): add local-first semantic parser"
```

## Task 5: Convert LLM Parsing Into Optional Enhancement and Plumb Follow-Up Due Updates

**Files:**
- Modify: `SecondLoop/lib/core/ai/semantic_parse.dart`
- Modify: `SecondLoop/lib/core/ai/semantic_parse_auto_actions_runner.dart`
- Modify: `SecondLoop/lib/core/ai/semantic_parse_auto_actions_runner_store.dart`
- Modify: `SecondLoop/lib/core/backend/app_backend.dart`
- Modify: `SecondLoop/lib/core/backend/native_backend_prompt_ai.dart`
- Modify: `SecondLoop/lib/core/backend/semantic_parse_attempt_aware_backend.dart`
- Modify: `SecondLoop/rust/src/semantic_parse/mod.rs`
- Modify: `SecondLoop/rust/src/api/core.rs`
- Modify: `SecondLoop/rust/src/db/parts/09a_semantic_parse_jobs.rs`
- Modify: `SecondLoop/rust/src/db/parts/09b_semantic_parse_job_mutations.rs`
- Modify: `SecondLoop/rust/src/db/semantic_parse_jobs_tests.rs`
- Modify: `SecondLoop/test/semantic_parse_auto_actions_runner_test.dart`
- Modify: `SecondLoop/test/semantic_parse_jobs_backend_api_test.dart`

- [ ] **Step 1: Write failing orchestration tests for enhancement gating and follow-up due persistence**

```dart
test('runner skips enhancement when local parse is high confidence', () async {
  final result = await runner.parseMessage(
    text: '明天下午 3 点提交材料',
    locale: const Locale('zh', 'CN'),
  );

  expect(fakeBackend.enhancementRequests, isEmpty);
  expect(result.decision, isA<MessageActionCreateDecision>());
});

test('runner requests enhancement when local parse is ambiguous and cloud is enabled', () async {
  final result = await runner.parseMessage(
    text: '把报销改到节后第一个工作日',
    locale: const Locale('zh', 'CN'),
  );

  expect(fakeBackend.enhancementRequests.single.kind, 'semantic_parse_enhancement');
  expect(result.decision, isA<MessageActionFollowUpDecision>());
});
```

- [ ] **Step 2: Run Dart and Rust tests to verify the old parse-only contract fails**

Run: `cd SecondLoop && pixi run flutter test test/semantic_parse_auto_actions_runner_test.dart test/semantic_parse_jobs_backend_api_test.dart && pixi run cargo test semantic_parse_jobs`
Expected: FAIL because the current backend contract still assumes LLM is the primary parser and follow-up due updates are not persisted.

- [ ] **Step 3: Replace the parse-only backend contract with enhancement payloads and due-update mutation support**

```rust
#[derive(Serialize, Deserialize)]
pub struct SemanticParseEnhancementRequest {
    pub local_result: LocalSemanticParseResult,
    pub unresolved_fields: Vec<String>,
    pub allow_temporal_enhancement: bool,
}
```

Implementation notes:

- LLM should receive the local result, unresolved fields, and candidate todo context rather than the raw "decide everything" prompt.
- The enhancement response may refine confidence, fill missing fields, or return `none`; it must not force execution when ambiguity remains.
- Reuse existing todo due mutation helpers where possible instead of adding a parallel write path.

- [ ] **Step 4: Run the orchestration tests to verify local-first plus enhancement behavior passes**

Run: `cd SecondLoop && pixi run flutter test test/semantic_parse_auto_actions_runner_test.dart test/semantic_parse_jobs_backend_api_test.dart && pixi run cargo test semantic_parse_jobs`
Expected: PASS for the new runner gating tests and Rust semantic parse job tests.

- [ ] **Step 5: Commit the enhancement-path integration**

```bash
git -C SecondLoop add \
  lib/core/ai/semantic_parse.dart \
  lib/core/ai/semantic_parse_auto_actions_runner.dart \
  lib/core/ai/semantic_parse_auto_actions_runner_store.dart \
  lib/core/backend/app_backend.dart \
  lib/core/backend/native_backend_prompt_ai.dart \
  lib/core/backend/semantic_parse_attempt_aware_backend.dart \
  rust/src/semantic_parse/mod.rs \
  rust/src/api/core.rs \
  rust/src/db/parts/09a_semantic_parse_jobs.rs \
  rust/src/db/parts/09b_semantic_parse_job_mutations.rs \
  rust/src/db/semantic_parse_jobs_tests.rs \
  test/semantic_parse_auto_actions_runner_test.dart \
  test/semantic_parse_jobs_backend_api_test.dart
git -C SecondLoop commit -m "✨ feat(ai): make semantic parse enhancement local-first"
```

## Task 6: Verify End-to-End Behavior and Remove Obsolete Duplication

**Files:**
- Modify: `SecondLoop/lib/features/actions/time/time_range_resolver.dart`
- Modify: `SecondLoop/lib/features/actions/time/time_resolver.dart`
- Modify: `SecondLoop/lib/core/ai/semantic_parse.dart`
- Modify: `SecondLoopServer/docs/superpowers/specs/2026-04-19-local-first-semantic-and-temporal-design.md`

- [ ] **Step 1: Write one final regression checklist in code by extending existing tests instead of using a manual QA note**

```dart
test('no-key user still gets baseline understanding end to end', () async {
  expect(await parseMessageWithoutCloud('明天下午3点提交材料'), isNotNull);
  expect(await resolveAskAiWindowWithoutCloud('今天有哪些事'), isNotNull);
  expect(await parseMessageWithoutCloud('把报销改到年初一之后第一个工作日'), isA<MessageActionNoneDecision>());
});
```

- [ ] **Step 2: Run the focused verification suite and capture any drift**

Run: `cd SecondLoop && pixi run flutter test test/temporal_engine_test.dart test/ask_ai_temporal_engine_test.dart test/time_resolver_test.dart test/message_action_resolver_test.dart test/local_semantic_parser_test.dart test/ai_semantic_parse_test.dart test/semantic_parse_auto_actions_runner_test.dart test/semantic_parse_jobs_backend_api_test.dart && pixi run cargo test semantic_parse_jobs`
Expected: PASS for all targeted understanding-layer tests.

- [ ] **Step 3: Delete or reduce dead wrappers and update the spec only if contract names changed**

```dart
@Deprecated('Use TemporalEngine.resolve instead')
typedef LocalTimeRangeResolver = TemporalEngineRangeAdapter;
```

Implementation notes:

- Prefer removing dead duplicated logic instead of keeping two active parsers.
- If the implementation keeps adapters for compatibility, make them thin and clearly deprecated.
- Update the spec only when the committed code intentionally changes public terms or contracts.

- [ ] **Step 4: Run formatting and the verification suite again**

Run: `cd SecondLoop && pixi run dart format lib test rust_builder integration_test test_driver && pixi run cargo fmt "--all" && pixi run flutter test test/temporal_engine_test.dart test/ask_ai_temporal_engine_test.dart test/time_resolver_test.dart test/message_action_resolver_test.dart test/local_semantic_parser_test.dart test/ai_semantic_parse_test.dart test/semantic_parse_auto_actions_runner_test.dart test/semantic_parse_jobs_backend_api_test.dart && pixi run cargo test semantic_parse_jobs`
Expected: PASS with no formatting diffs and no understanding-layer regressions.

- [ ] **Step 5: Commit the cleanup and verification pass**

```bash
git -C SecondLoop add \
  lib/features/actions/time/time_range_resolver.dart \
  lib/features/actions/time/time_resolver.dart \
  lib/core/ai/semantic_parse.dart \
  test/temporal_engine_test.dart \
  test/ask_ai_temporal_engine_test.dart \
  test/time_resolver_test.dart \
  test/message_action_resolver_test.dart \
  test/local_semantic_parser_test.dart \
  test/ai_semantic_parse_test.dart \
  test/semantic_parse_auto_actions_runner_test.dart \
  test/semantic_parse_jobs_backend_api_test.dart
git -C SecondLoop commit -m "✅ test(ai): verify local-first understanding layer"
```

If Step 3 changes the spec, stage and commit that change separately in `SecondLoopServer`.

## Execution Notes

- Users without BYOK or cloud are a first-class baseline. Any step that regresses no-key behavior is a plan bug and should be corrected before implementation continues.
- Wrong time windows and wrong due dates are worse than missing structure. If a case is ambiguous, keep the output conservative and let retrieval or automation proceed without fabricated structure.
- Retrieval/rerank work starts only after this plan lands and its contracts stabilize.
