# LLM Reasoning Thinking UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 assistant 等待期间展示 OpenAI-compatible 流里真实返回的 reasoning 内容，并在正式回答开始时清除临时思考 UI。

**Architecture:** Rust OpenAI-compatible parser 识别 reasoning 字段，并通过现有 `Stream<String>` 增加 `SL_REASONING` 控制帧，保持普通字符串仍代表回答 delta。Flutter `AgentConversationPage` 解析该控制帧，渲染一个临时 thinking panel；第一个回答 delta 到达后清空 reasoning 状态并展示普通 assistant 消息。SecondLoopServer 只做 discovery gate：现有 `ai-gateway` 对 ask_ai SSE 是 passthrough，只有发现 staging strip reasoning 时才在服务端主分支修改、推送和部署。

**Tech Stack:** Flutter/Dart, Rust, flutter_rust_bridge stream strings, OpenAI-compatible SSE/JSON, pixi, Flutter widget tests, Rust integration tests.

---

## File Structure

### App Repo

- Modify: `rust/src/llm/openai.rs`
  - Responsibility: extract OpenAI-compatible answer deltas and reasoning deltas from SSE/JSON.
  - Keep `ChatDelta` shape unchanged by encoding reasoning as an internal control role prefix.
- Create: `rust/src/api/ask_ai_stream_controls.rs`
  - Responsibility: convert internal Ask AI control roles into public stream control frames.
- Modify: `rust/src/api/mod.rs`
  - Responsibility: expose `ask_ai_stream_controls` as a crate-private API module.
- Modify: `rust/src/api/core.rs`
  - Responsibility: use the shared stream control helper for unscoped Ask AI streams.
- Modify: `rust/src/api/ask_scope.rs`
  - Responsibility: use the shared stream control helper for scoped Ask AI streams.
- Modify: `rust/src/api/core_parts/part_04.rs`
  - Responsibility: call the control-frame helper before writing visible answer deltas for all Ask AI stream variants.
- Modify: `rust/tests/openai_sse_parse.rs`
  - Responsibility: prove parser extracts reasoning from SSE and JSON without changing existing answer parsing.
- Modify: `lib/features/agent_ui/agent_conversation_page.dart`
  - Responsibility: own temporary reasoning state, parse `SL_REASONING`, render and clear the thinking panel.
- Modify: `test/agent_conversation_test.dart`
  - Responsibility: prove reasoning UI is temporary, non-persistent, and not confused with final answer text.

### Server Repo Discovery

- Read-only unless needed: `/Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer/workers/ai-gateway/src/openai_proxy.js`
  - Responsibility: confirm ask_ai SSE responses are passed through rather than normalized.
- Optional if discovery fails: `/Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer/workers/ai-gateway/test/gateway.test.js`
  - Responsibility: lock reasoning-field passthrough behavior before a service patch.

## Control Contract

The app stream contract after implementation:

```text
\u001eSL_REASONING\u001e{"text":"..."}
```

- Plain string chunks remain assistant answer deltas.
- `SL_REASONING` chunks are temporary reasoning deltas.
- `SL_META` chunks remain metadata.
- `SL_ERROR` chunks remain failures.
- Reasoning chunks do not count as visible answer text.

The internal Rust parser can use this role prefix to avoid broad `ChatDelta` churn:

```rust
const REASONING_DELTA_ROLE_PREFIX: &str = "secondloop_reasoning_delta:";
```

API layers translate that internal prefix into the public `SL_REASONING` control frame.

---

### Task 1: Rust Parser Emits Reasoning Control Events

**Files:**
- Modify: `rust/tests/openai_sse_parse.rs`
- Modify: `rust/src/llm/openai.rs`

- [ ] **Step 1: Write failing SSE reasoning test**

Add a test to `rust/tests/openai_sse_parse.rs`:

```rust
#[test]
fn openai_sse_parses_reasoning_content_as_control_role() {
    let sse = r#"
data: {"choices":[{"delta":{"reasoning_content":"I should inspect the local context."}}]}

data: {"choices":[{"delta":{"content":"Here is the answer."}}]}

data: [DONE]
"#;

    let events = openai::parse_chat_completions_sse(sse.as_bytes()).expect("parse sse");
    assert_eq!(
        events,
        vec![
            ChatDelta {
                role: Some(
                    "secondloop_reasoning_delta:I should inspect the local context.".to_string(),
                ),
                text_delta: "".to_string(),
                done: false,
            },
            ChatDelta {
                role: None,
                text_delta: "Here is the answer.".to_string(),
                done: false,
            },
            ChatDelta {
                role: None,
                text_delta: "".to_string(),
                done: true,
            },
        ]
    );
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
pixi run cargo test "--test openai_sse_parse openai_sse_parses_reasoning_content_as_control_role"
```

Expected: FAIL because the parser currently ignores `reasoning_content`.

- [ ] **Step 3: Write failing JSON reasoning test**

Add a second test to `rust/tests/openai_sse_parse.rs`:

```rust
#[test]
fn openai_json_parses_message_reasoning_before_answer() {
    let body = r#"{
  "choices": [
    {
      "message": {
        "role": "assistant",
        "reasoning_content": "I checked the relevant memory.",
        "content": "The next step is to book the appointment."
      }
    }
  ]
}"#;

    let events = openai::parse_chat_completions_json(body.as_bytes()).expect("parse json");
    assert_eq!(
        events,
        vec![
            ChatDelta {
                role: Some("secondloop_reasoning_delta:I checked the relevant memory.".to_string()),
                text_delta: "".to_string(),
                done: false,
            },
            ChatDelta {
                role: Some("assistant".to_string()),
                text_delta: "The next step is to book the appointment.".to_string(),
                done: false,
            },
            ChatDelta {
                role: None,
                text_delta: "".to_string(),
                done: true,
            },
        ]
    );
}
```

- [ ] **Step 4: Run test to verify it fails**

Run:

```bash
pixi run cargo test "--test openai_sse_parse openai_json_parses_message_reasoning_before_answer"
```

Expected: FAIL because JSON parsing does not emit a reasoning event.

- [ ] **Step 5: Add failing coverage for another reasoning field variant**

Add a test that proves at least one non-`reasoning_content` variant from the spec works:

```rust
#[test]
fn openai_sse_parses_delta_reasoning_field_as_control_role() {
    let sse = r#"
data: {"choices":[{"delta":{"reasoning":"A shorter reasoning field."}}]}

data: [DONE]
"#;

    let events = openai::parse_chat_completions_sse(sse.as_bytes()).expect("parse sse");
    assert_eq!(
        events,
        vec![
            ChatDelta {
                role: Some("secondloop_reasoning_delta:A shorter reasoning field.".to_string()),
                text_delta: "".to_string(),
                done: false,
            },
            ChatDelta {
                role: None,
                text_delta: "".to_string(),
                done: true,
            },
        ]
    );
}
```

- [ ] **Step 6: Run variant test to verify it fails**

Run:

```bash
pixi run cargo test "--test openai_sse_parse openai_sse_parses_delta_reasoning_field_as_control_role"
```

Expected: FAIL because the parser does not extract `delta.reasoning`.

- [ ] **Step 7: Implement minimal parser support**

In `rust/src/llm/openai.rs`:

- Add `const REASONING_DELTA_ROLE_PREFIX: &str = "secondloop_reasoning_delta:";`.
- Add `fn reasoning_role(reasoning_delta: String) -> Option<String>` that returns the prefixed role only for non-empty trimmed text.
- Add `fn extract_reasoning_delta(value: &Value) -> String` checking:
  - `/choices/0/delta/reasoning_content`
  - `/choices/0/message/reasoning_content`
  - `/choices/0/delta/reasoning`
  - `/choices/0/message/reasoning`
  - `/reasoning`
- In `parse_sse_payload`, keep existing answer text extraction and set `role` to `reasoning_role(reasoning_delta).or_else(|| extract_role(&parsed_value))`.
- In `read_chat_completions_json`, emit a reasoning `ChatDelta` before the answer `ChatDelta` when `extract_reasoning_delta(&root)` is non-empty.

Do not add frontend `SL_REASONING` strings here; this layer only emits internal `ChatDelta`.

- [ ] **Step 8: Run parser tests**

Run:

```bash
pixi run cargo test "--test openai_sse_parse"
pixi run cargo test "--test openai_non_stream_json"
```

Expected: PASS. Existing answer parsing fixtures remain unchanged.

- [ ] **Step 9: Commit parser work**

```bash
git add rust/src/llm/openai.rs rust/tests/openai_sse_parse.rs
git commit -m "feat: parse openai reasoning deltas"
```

---

### Task 2: Rust Ask AI Streams Emit `SL_REASONING`

**Files:**
- Create: `rust/src/api/ask_ai_stream_controls.rs`
- Modify: `rust/src/api/mod.rs`
- Modify: `rust/src/api/core.rs`
- Modify: `rust/src/api/ask_scope.rs`
- Modify: `rust/src/api/core_parts/part_04.rs`

- [ ] **Step 1: Write failing pure helper tests**

Add this module line to `rust/src/api/mod.rs`:

```rust
pub(crate) mod ask_ai_stream_controls;
```

Create `rust/src/api/ask_ai_stream_controls.rs` with only tests first:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn control_frame_for_reasoning_role_emits_reasoning_json() {
        let frame = control_frame_for_role(Some(
            "secondloop_reasoning_delta:I should inspect \"local\" context.",
        ));

        assert_eq!(
            frame.as_deref(),
            Some("\u{001e}SL_REASONING\u{001e}{\"text\":\"I should inspect \\\"local\\\" context.\"}"),
        );
    }

    #[test]
    fn control_frame_for_request_id_role_keeps_existing_meta_contract() {
        let frame = control_frame_for_role(Some("secondloop_request_id:req_123"));

        assert_eq!(
            frame.as_deref(),
            Some("\u{001e}SL_META\u{001e}{\"type\":\"cloud_request_id\",\"request_id\":\"req_123\"}"),
        );
    }

    #[test]
    fn control_frame_for_normal_assistant_role_is_none() {
        assert_eq!(control_frame_for_role(Some("assistant")), None);
    }
}
```

- [ ] **Step 2: Run helper tests to verify they fail**

Run:

```bash
pixi run cargo test "api::ask_ai_stream_controls"
```

Expected: FAIL because `control_frame_for_role` is not implemented.

- [ ] **Step 3: Implement shared stream-control helper**

In `rust/src/api/ask_ai_stream_controls.rs`, implement:

```rust
use anyhow::Result;

use crate::frb_generated::StreamSink;
use crate::rag;

const ASK_AI_META_PREFIX: &str = "\u{001e}SL_META\u{001e}";
const ASK_AI_REASONING_PREFIX: &str = "\u{001e}SL_REASONING\u{001e}";
const ASK_AI_META_REQUEST_ID_ROLE_PREFIX: &str = "secondloop_request_id:";
const ASK_AI_REASONING_DELTA_ROLE_PREFIX: &str = "secondloop_reasoning_delta:";

pub(crate) fn meta_frame_for_role(role: Option<&str>) -> Option<String> {
    let Some(role) = role else {
        return None;
    };
    if let Some(request_id) = role.strip_prefix(ASK_AI_META_REQUEST_ID_ROLE_PREFIX) {
        let request_id = request_id.trim();
        if request_id.is_empty() {
            return None;
        }
        return Some(format!(
            "{ASK_AI_META_PREFIX}{{\"type\":\"cloud_request_id\",\"request_id\":\"{request_id}\"}}"
        ));
    }
    None
}

pub(crate) fn reasoning_frame_for_role(role: Option<&str>) -> Option<String> {
    let Some(role) = role else {
        return None;
    };
    if let Some(reasoning_delta) = role.strip_prefix(ASK_AI_REASONING_DELTA_ROLE_PREFIX) {
        if reasoning_delta.is_empty() {
            return None;
        }
        let payload = serde_json::json!({ "text": reasoning_delta }).to_string();
        return Some(format!("{ASK_AI_REASONING_PREFIX}{payload}"));
    }

    None
}

pub(crate) fn control_frame_for_role(role: Option<&str>) -> Option<String> {
    meta_frame_for_role(role).or_else(|| reasoning_frame_for_role(role))
}

pub(crate) fn emit_control_if_any(sink: &StreamSink<String>, role: Option<&str>) -> Result<()> {
    let Some(frame) = control_frame_for_role(role) else {
        return Ok(());
    };
    if sink.add(frame).is_err() {
        return Err(rag::StreamCancelled.into());
    }
    Ok(())
}

pub(crate) fn emit_request_meta_if_any(sink: &StreamSink<String>, role: Option<&str>) -> Result<()> {
    let Some(frame) = meta_frame_for_role(role) else {
        return Ok(());
    };
    if sink.add(frame).is_err() {
        return Err(rag::StreamCancelled.into());
    }
    Ok(())
}

pub(crate) fn emit_reasoning_if_any(sink: &StreamSink<String>, role: Option<&str>) -> Result<()> {
    let Some(frame) = reasoning_frame_for_role(role) else {
        return Ok(());
    };
    if sink.add(frame).is_err() {
        return Err(rag::StreamCancelled.into());
    }
    Ok(())
}
```

- [ ] **Step 4: Run helper tests**

Run:

```bash
pixi run cargo test "api::ask_ai_stream_controls"
```

Expected: PASS.

- [ ] **Step 5: Wire all Ask AI stream closures**

In `rust/src/api/core_parts/part_04.rs`, replace each call to:

```rust
emit_ask_ai_meta_if_any(&sink, ev.role.as_deref())?;
```

with:

```rust
crate::api::ask_ai_stream_controls::emit_control_if_any(&sink, ev.role.as_deref())?;
```

Do this for all Ask AI variants in the file:

- `rag_ask_ai_stream`
- `rag_ask_ai_stream_time_window`
- `rag_ask_ai_stream_with_brok_embeddings`
- `rag_ask_ai_stream_with_brok_embeddings_time_window`
- `rag_ask_ai_stream_cloud_gateway`
- `rag_ask_ai_stream_cloud_gateway_time_window`
- `rag_ask_ai_stream_cloud_gateway_with_embeddings`
- `rag_ask_ai_stream_cloud_gateway_with_embeddings_time_window`

In `rust/src/api/ask_scope.rs`, update `stream_scoped_ask_with_provider` carefully. It currently gates metadata on `emit_meta`; reasoning must not be gated there.

Use this shape:

```rust
if emit_meta {
    crate::api::ask_ai_stream_controls::emit_request_meta_if_any(&sink, ev.role.as_deref())?;
}
crate::api::ask_ai_stream_controls::emit_reasoning_if_any(&sink, ev.role.as_deref())?;
```

To support that, split the helper in `ask_ai_stream_controls.rs` into:

- `control_frame_for_role(role)` for generic tests and unscoped streams.
- `meta_frame_for_role(role)`.
- `reasoning_frame_for_role(role)`.
- `emit_control_if_any(sink, role)`.
- `emit_request_meta_if_any(sink, role)`.
- `emit_reasoning_if_any(sink, role)`.

Unscoped streams can keep `emit_control_if_any`; scoped streams should preserve the existing behavior where request-id metadata only emits for cloud gateway scoped streams, while reasoning emits for both BYOK and cloud scoped streams.

Then remove now-unused local `ASK_AI_META_PREFIX`, `ASK_AI_META_REQUEST_ID_ROLE_PREFIX`, and `emit_ask_ai_meta_if_any` definitions from `rust/src/api/core.rs` and `rust/src/api/ask_scope.rs` if they are no longer referenced.

- [ ] **Step 6: Run Rust checks**

Run:

```bash
pixi run cargo test "api::ask_ai_stream_controls"
pixi run cargo test "--test openai_sse_parse"
pixi run cargo test "--test ask_ai_flow"
pixi run cargo test "--test llm_gateway_provider_smoke"
```

Expected: PASS. If compile fails because helper names remain stale, update all references.

- [ ] **Step 7: Commit stream bridge**

```bash
git add rust/src/api/mod.rs rust/src/api/ask_ai_stream_controls.rs rust/src/api/core.rs rust/src/api/ask_scope.rs rust/src/api/core_parts/part_04.rs
git commit -m "feat: emit reasoning stream control frames"
```

---

### Task 3: Flutter Thinking Panel Consumes Real Reasoning

**Files:**
- Modify: `test/agent_conversation_test.dart`
- Modify: `lib/features/agent_ui/agent_conversation_page.dart`

- [ ] **Step 1: Write failing widget test for live reasoning panel**

In `test/agent_conversation_test.dart`:

- Add `const _askAiReasoningPrefix = '\u001eSL_REASONING\u001e';`.
- Add `_ControlledReasoningBackend` that returns a `StreamController<String>` stream.
- Add a test named `agent conversation shows reasoning temporarily until answer starts`.

Test flow:

```dart
backend.stream.add('$_askAiReasoningPrefix{"text":"I should inspect the local context."}');
await tester.pump();
expect(find.byKey(const ValueKey('agent_thinking_panel')), findsOneWidget);
expect(find.textContaining('I should inspect the local context.'), findsOneWidget);

backend.stream.add('The next step is to book the appointment.');
await tester.pump();
expect(find.textContaining('I should inspect the local context.'), findsNothing);
expect(find.textContaining('The next step is to book the appointment.'), findsOneWidget);
expect(find.textContaining('Final answer'), findsNothing);
```

Expected failure before implementation: `agent_thinking_panel` is not found and `SL_REASONING` may be ignored or treated incorrectly.

- [ ] **Step 2: Run failing widget test**

Run:

```bash
pixi run flutter test "test/agent_conversation_test.dart --plain-name 'agent conversation shows reasoning temporarily until answer starts'"
```

Expected: FAIL for missing thinking panel/reasoning behavior.

- [ ] **Step 3: Write failing widget test for reasoning-only failure path**

Add a test named `agent conversation does not treat reasoning-only stream as answer`.

Test flow:

```dart
backend.stream.add('$_askAiReasoningPrefix{"text":"Only temporary reasoning."}');
await tester.pump();
expect(find.textContaining('Only temporary reasoning.'), findsOneWidget);

await backend.stream.close();
await tester.pumpAndSettle();
expect(find.textContaining('Only temporary reasoning.'), findsNothing);
expect(find.text('Ask AI failed. Please try again.'), findsOneWidget);
expect(find.textContaining('Final answer'), findsNothing);
```

Expected failure before implementation: reasoning-only chunks are not represented as temporary state.

- [ ] **Step 4: Run failing widget test**

Run:

```bash
pixi run flutter test "test/agent_conversation_test.dart --plain-name 'agent conversation does not treat reasoning-only stream as answer'"
```

Expected: FAIL before implementation.

- [ ] **Step 5: Write failing widget test for unknown control chunks**

Add a test named `agent conversation ignores unknown stream control chunks`.

Test flow:

```dart
backend.stream.add('$_askAiReasoningPrefix{"text":"Temporary reasoning."}');
await tester.pump();
expect(find.textContaining('Temporary reasoning.'), findsOneWidget);

backend.stream.add('\u001eSL_UNKNOWN\u001e{"text":"do not render"}');
await tester.pump();
expect(find.textContaining('SL_UNKNOWN'), findsNothing);
expect(find.textContaining('do not render'), findsNothing);
expect(find.textContaining('Temporary reasoning.'), findsOneWidget);

backend.stream.add('Visible answer.');
await tester.pump();
expect(find.textContaining('Temporary reasoning.'), findsNothing);
expect(find.textContaining('Visible answer.'), findsOneWidget);
```

Expected: FAIL before implementation if unknown control chunks are treated as answer text.

- [ ] **Step 6: Run unknown-control widget test**

Run:

```bash
pixi run flutter test "test/agent_conversation_test.dart --plain-name 'agent conversation ignores unknown stream control chunks'"
```

Expected: FAIL before implementation.

- [ ] **Step 7: Implement Dart stream parsing and state**

In `lib/features/agent_ui/agent_conversation_page.dart`:

- Add `import 'dart:convert';`.
- Add `_askAiReasoningPrefix = '\u001eSL_REASONING\u001e';`.
- Add `String _streamingReasoning = '';`.
- Reset `_streamingReasoning` in `_send()` and `_showAskFailure()`.
- Extend `_consumeAskAiStream`:
  - Ignore `SL_META` as today.
  - Parse `SL_REASONING` JSON using a helper like `_extractReasoningDeltaText`.
  - Append reasoning text to `_streamingReasoning`.
  - Do not set `sawVisibleDelta` for reasoning chunks.
  - Ignore any chunk that starts with the record-separator control prefix `\u001eSL_` and is not `SL_ERROR`, `SL_META`, or `SL_REASONING`.
  - On the first plain answer delta, clear `_streamingReasoning` and append to `_streamingAnswer`.
- Pass `streamingReasoning` into `_MessageList`.

Parsing helper shape:

```dart
String _extractReasoningDeltaText(String rawPayload) {
  try {
    final decoded = jsonDecode(rawPayload);
    if (decoded is Map) {
      return '${decoded['text'] ?? ''}';
    }
  } catch (_) {
    return '';
  }
  return '';
}
```

- [ ] **Step 8: Implement focused thinking panel widget**

Replace the static `_ThinkingMessage` body with a widget that accepts reasoning:

```dart
const _ThinkingMessage(reasoning: streamingReasoning)
```

Panel requirements:

- Root key: `ValueKey('agent_thinking_panel')`.
- Reasoning text key: `ValueKey('agent_thinking_reasoning_text')`.
- Show `t.thinking` in the title.
- If reasoning is empty, show only title plus subtle dots/shimmer.
- If reasoning is non-empty, show latest 3-4 visual lines or last 420-600 chars.
- Do not render "Final answer".
- Use `AnimatedSwitcher` or `AnimatedSize` for the panel transition.

- [ ] **Step 9: Run focused widget tests**

Run:

```bash
pixi run flutter test "test/agent_conversation_test.dart --plain-name 'agent conversation shows reasoning temporarily until answer starts'"
pixi run flutter test "test/agent_conversation_test.dart --plain-name 'agent conversation does not treat reasoning-only stream as answer'"
pixi run flutter test "test/agent_conversation_test.dart --plain-name 'agent conversation ignores unknown stream control chunks'"
```

Expected: PASS.

- [ ] **Step 10: Run full conversation tests**

Run:

```bash
pixi run flutter test test/agent_conversation_test.dart
```

Expected: PASS. Existing metadata and error sentinel tests still pass.

- [ ] **Step 11: Commit Flutter UI**

```bash
git add lib/features/agent_ui/agent_conversation_page.dart test/agent_conversation_test.dart
git commit -m "feat: show temporary llm reasoning in chat"
```

---

### Task 4: SecondLoopServer Discovery Gate

**Files:**
- Read-only by default: `/Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer/workers/ai-gateway/src/openai_proxy.js`
- Optional modify if needed: `/Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer/workers/ai-gateway/test/gateway.test.js`
- Optional modify if needed: `/Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer/workers/ai-gateway/src/openai_proxy.js`

- [ ] **Step 1: Confirm server repository state**

Run:

```bash
git -C /Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer status --short --branch
```

Expected: branch is `main`. Do not touch untracked `paseo.json`.

- [ ] **Step 2: Verify ask_ai SSE passthrough**

Inspect `workers/ai-gateway/src/openai_proxy.js` around the streaming branch. Expected behavior:

- For `/v1/chat/completions` with `effectivePurpose === 'ask_ai'`, `wantsJson` is false.
- The streaming branch uses `sseTransformForUsageTokenMetering`, which enqueues original chunks and only reads usage fields.
- Therefore reasoning fields inside upstream SSE data should pass through unchanged to the app.

- [ ] **Step 3: If passthrough is already preserved, do not modify server**

Record this in the implementation summary. No server commit, push, or staging deploy is needed.

- [ ] **Step 4: If passthrough is not preserved, add a failing server test**

Only if Step 2 fails, add a test in `workers/ai-gateway/test/gateway.test.js`:

```js
test('POST /v1/chat/completions passes reasoning_content SSE fields through for ask_ai', async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (input) => {
    const url = typeof input === 'string' ? input : input.url;
    if (url === 'https://upstream.test/v1/chat/completions') {
      return new Response(
        'data: {"choices":[{"delta":{"reasoning_content":"server reasoning"}}]}\n\n' +
          'data: {"choices":[{"delta":{"content":"answer"}}]}\n\n' +
          'data: [DONE]\n\n',
        { status: 200, headers: { 'content-type': 'text/event-stream' } },
      );
    }
    throw new Error(`unexpected fetch url: ${url}`);
  };

  try {
    const req = new Request('https://gateway.test/v1/chat/completions', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        authorization: 'Bearer test_uid',
        'x-secondloop-purpose': 'ask_ai',
      },
      body: JSON.stringify({ model: 'gpt-test', stream: true, messages: [] }),
    });

    const resp = await worker.fetch(req, {
      AUTH_MODE: 'dev',
      ENTITLEMENTS: kvFromEntries({
        test_uid: JSON.stringify({ entitlements: { cloud_ai: { active: true } } }),
      }),
      USAGE: kvFromEntries({}),
      USAGE_PURPOSE_ALLOWLIST: 'ask_ai',
      UPSTREAM_BASE_URL: 'https://upstream.test',
      UPSTREAM_API_KEY: 'sk-upstream',
    });

    assert.equal(resp.status, 200);
    assert.match(await resp.text(), /reasoning_content/);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
```

Run:

```bash
cd /Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer
pixi run test
```

Expected: FAIL only if current code strips reasoning.

- [ ] **Step 5: If server code is needed, patch, test, push, deploy staging**

Only if Step 4 proves a server bug:

```bash
cd /Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer
git config user.name "Logic Tan"
git config user.email "logictan89@gmail.com"
pixi run test
git add workers/ai-gateway/src/openai_proxy.js workers/ai-gateway/test/gateway.test.js
git commit -m "fix: preserve reasoning deltas in ai gateway"
git push origin main
pixi run deploy-staging
```

Expected: tests pass, push succeeds, staging deployment succeeds.

---

### Task 5: Final Verification And Formatting

**Files:**
- Modify as needed from Tasks 1-4.

- [ ] **Step 1: Format changed app files**

Run:

```bash
pixi run dart format "lib/features/agent_ui/agent_conversation_page.dart test/agent_conversation_test.dart"
pixi run cargo fmt
```

Expected: formatters complete without errors.

- [ ] **Step 2: Run focused app verification**

Run:

```bash
pixi run flutter test test/agent_conversation_test.dart
pixi run cargo test "--test openai_sse_parse"
pixi run cargo test "--test openai_non_stream_json"
pixi run cargo test "--test ask_ai_flow"
pixi run cargo test "--test llm_gateway_provider_smoke"
```

Expected: all pass.

- [ ] **Step 3: Run analyzer on touched Dart surface**

Run:

```bash
pixi run flutter analyze "lib/features/agent_ui/agent_conversation_page.dart test/agent_conversation_test.dart"
```

Expected: no analyzer errors.

- [ ] **Step 4: Check git status**

Run:

```bash
git status --short
```

Expected: only intended files are modified or staged. No generated image files, `.tool`, `.tmp`, or unrelated docs are included.

- [ ] **Step 5: Commit final verification fixes if needed**

If formatting or minor verification fixes changed files:

```bash
git add rust/src/llm/openai.rs rust/src/api/core.rs rust/src/api/ask_scope.rs rust/src/api/core_parts/part_04.rs rust/tests/openai_sse_parse.rs lib/features/agent_ui/agent_conversation_page.dart test/agent_conversation_test.dart
git commit -m "test: verify llm reasoning thinking flow"
```

If no files changed after verification, do not create an empty commit.
