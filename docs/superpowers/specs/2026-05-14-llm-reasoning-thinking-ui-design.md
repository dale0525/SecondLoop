# LLM Reasoning Thinking UI Design

> Status: Approved by user on 2026-05-14.

## Goal

Show real LLM reasoning content while the assistant response is pending, then remove that reasoning UI as soon as the final assistant answer begins streaming.

The UI must not invent progress phases. It must not label the final response as "Final answer". The final chat transcript should contain only the user message and the assistant answer, not the temporary reasoning content.

## Current Context

`AgentConversationPage` currently has a static `_ThinkingMessage` shown while `_thinking` is true. The static body says the app is preparing a reviewable change. Once `_streamingAnswer` has visible text, `_MessageList` replaces that static state with `_AssistantTextMessage`.

The current `askAiStream` contract is a `Stream<String>`:

- Plain string chunks are visible assistant answer text.
- `SL_ERROR` control chunks report failures.
- `SL_META` control chunks are currently used for metadata such as cloud request IDs and are ignored by the conversation UI.

The Rust OpenAI-compatible parser currently extracts answer text from OpenAI-compatible chat completion SSE and JSON responses. It does not expose reasoning deltas separately.

Cloud gateway requests in the native app use the same OpenAI-compatible stream parser after the gateway response. Web bridge paths may collapse the response into a single returned string, so they cannot show live reasoning unless the bridge path is upgraded separately.

## Visual Thesis

A calm, temporary working surface appears exactly where the assistant answer will arrive. It feels transparent and alive while waiting, then disappears cleanly when the real answer begins.

## Content Plan

The conversation pane remains the primary workspace:

1. User message appears immediately after send.
2. Assistant row appears with a temporary thinking panel.
3. Real reasoning text, if provided by the server, streams inside that panel.
4. First answer delta clears the thinking panel.
5. Normal assistant answer bubble streams in place.

The right context rail and composer are unchanged.

## Interaction Thesis

Use three restrained motions:

- The thinking title has three small pulsing dots while no answer text is visible.
- Reasoning text lines fade in and drift upward as newer lines arrive.
- The whole panel collapses and fades out in about 180-240 ms when the first answer delta arrives.

## Requirements

### Reasoning Source

- Only display reasoning content explicitly emitted by the service as reasoning.
- Do not parse answer text into fake phases such as "Retrieving context", "Planning answer", or "Checking details".
- Do not synthesize reasoning text on the client.
- If no reasoning content arrives, show only a minimal waiting animation and the localized "thinking" label.
- For now, support only OpenAI-compatible provider responses.

### Thinking Panel

- Render the panel in the assistant row, after the assistant avatar and metadata.
- Use the existing agent UI palette: white panel, soft surface, blue accent, ink text, muted text, and light border.
- Keep the panel narrower than the conversation width, aligned with assistant answer cards.
- Show a title such as the existing localized `chat.agentConversation.thinking`.
- Show at most the latest 3-4 visual lines of reasoning.
- Apply a bottom fade so the panel reads as a live stream, not a transcript viewer.
- Do not provide an expand or history control.
- Do not persist reasoning in message history.

### Clearing Behavior

- The thinking panel is visible only before answer text starts.
- On the first answer delta, clear the reasoning buffer and animate the panel out.
- The assistant answer appears as a normal assistant message.
- Do not show "Final answer" or any equivalent label.
- If an error occurs before any answer delta, replace the temporary panel with the existing error message flow.

### Accessibility And Localization

- The visible title uses localized strings.
- Reasoning text is user-visible text and should use the same font family and readable contrast as assistant content.
- The loading dots should not be the only indicator; the title text remains visible.
- Animated content should remain subtle and should not shift the surrounding transcript violently.

## Stream Contract

Keep the existing plain-string answer delta behavior for compatibility. Add explicit reasoning control chunks so the UI can distinguish reasoning from answer text without guessing.

Required contract:

```text
\u001eSL_REASONING\u001e{"text":"..."}
```

Rules:

- `SL_REASONING` chunks carry reasoning deltas only.
- Plain chunks remain assistant answer deltas.
- `SL_META` remains metadata and must not be rendered as reasoning.
- `SL_ERROR` remains the error path.
- Unknown control chunks are ignored by the UI.
- Reasoning chunks do not count as visible answer text for success detection.

The OpenAI-compatible parser should recognize common reasoning fields when present, for example:

- `choices[0].delta.reasoning_content`
- `choices[0].message.reasoning_content`
- `choices[0].delta.reasoning`
- `choices[0].message.reasoning`
- top-level `reasoning`

The parser should continue extracting answer text from existing content/text fields. If a provider returns reasoning in a structure not listed above, it can be added later without changing the UI contract.

## Backend Boundary

Native BYOK and native cloud gateway paths can be handled inside the app's Rust provider/parser layer because both use OpenAI-compatible response parsing.

If the cloud gateway service strips reasoning fields before returning SSE to the app, update `/Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer` on its main branch, push, and trigger staging deployment as requested by the user.

Web bridge paths that call `sendChat` and return one complete string are out of scope for live reasoning in this design. They can continue to show the minimal waiting animation.

## Frontend Boundary

`AgentConversationPage` owns the temporary reasoning state:

- Add a `String _streamingReasoning` buffer or equivalent line model.
- Parse `SL_REASONING` chunks in `_consumeAskAiStream`.
- Update the thinking panel while no answer delta has arrived.
- Clear reasoning when the first plain answer chunk arrives.
- Continue to append plain answer chunks to `_streamingAnswer`.

The thinking panel should be a focused widget near `_ThinkingMessage`, not folded into `_AssistantTextMessage`.

## Non-Goals

- Persisting reasoning with messages.
- Showing full reasoning history after the answer completes.
- Adding an expand/collapse viewer.
- Guessing semantic phases on the frontend.
- Supporting non-OpenAI-compatible APIs.
- Redesigning the composer, right context rail, or message footer.
- Adding a "Final answer" label.

## Testing Strategy

Add focused widget and parser tests:

- Reasoning control chunks render the temporary thinking panel.
- Answer chunks clear the thinking panel and render as a normal assistant message.
- Reasoning-only chunks do not count as a completed visible answer.
- No reasoning chunks fall back to the existing minimal waiting state.
- The UI never renders the literal text "Final answer".
- OpenAI-compatible SSE parsing extracts reasoning deltas from supported reasoning fields.
- Existing answer SSE fixtures continue to produce answer text unchanged.

## Implementation Discovery Checks

Before implementation, inspect the active OpenAI-compatible providers and gateway path for the exact reasoning field variants they emit. This does not change the approved UI behavior; it only determines which parser branches are exercised first.

Before changing SecondLoopServer, verify whether it already proxies reasoning fields. If it strips them, update the service on the main branch, push, and trigger staging deployment as requested by the user.
