import { describe, expect, it } from "vitest";

import { buildAssistantTurnMessages } from "../src/renderer/chatEventMessages";

describe("persisted chat activity", () => {
  it("uses result metadata to finish metadata-only tool activity", () => {
    let index = 0;
    const messages = buildAssistantTurnMessages(
      {
        accepted: true,
        events: [
          {
            type: "tool_call_started",
            call_id: "call-publish",
            name: "structured_content_publish",
            arguments: {}
          },
          {
            type: "tool_call_finished",
            call_id: "call-publish",
            result_metadata: {
              error_code: "structured_content_error",
              ok: false
            }
          },
          { type: "turn_failed", turn_id: "turn-1" }
        ]
      },
      () => `activity-${index += 1}`
    );

    expect(messages).toMatchObject([
      { callId: "call-publish", kind: "tool_call", status: "failed" },
      {
        callId: "call-publish",
        content: "structured_content_error",
        kind: "tool_result",
        ok: false
      }
    ]);
  });
});
