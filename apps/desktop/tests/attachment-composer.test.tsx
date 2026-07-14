import { cleanup, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";

import { Chat } from "../src/renderer/screens/Chat";

describe("trusted attachment composer", () => {
  afterEach(() => {
    cleanup();
    delete window.agentWeave;
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it("imports an attachment and sends only its stable reference", async () => {
    const user = userEvent.setup();
    const attachment = {
      createdAt: "2026-07-14T10:00:00Z",
      fileName: "brief.pdf",
      id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      mimeType: "application/pdf",
      sha256: "b".repeat(64),
      sizeBytes: 2048,
    };
    window.agentWeave = {
      approval: { open: async () => { throw new Error("unavailable"); } },
      attachments: { pickAndImport: async () => attachment },
      owner: {} as NonNullable<Window["agentWeave"]>["owner"],
    };
    const fetchMock = installFetch([
      jsonResponse({ id: "session-1", title: "Inspect attachment" }),
      jsonResponse(turnAccepted()),
      jsonResponse(turnPage()),
    ]);

    render(<Chat attachmentsEnabled />);
    await user.click(screen.getByRole("button", { name: "composer.addAttachment" }));
    expect(screen.getByText("brief.pdf")).toBeVisible();
    await user.type(screen.getByLabelText("Message AgentWeave"), "Summarize this file");
    await user.click(screen.getByRole("button", { name: "Send message" }));

    expect(await screen.findByText("Attachment inspected")).toBeVisible();
    const turnBody = JSON.parse(fetchMock.mock.calls[1][1].body as string);
    expect(turnBody.content).toContain("<secondloop_attachment_refs>");
    expect(turnBody.content).toContain(attachment.id);
    expect(turnBody.content).toContain("brief.pdf");
    expect(turnBody.content).not.toContain("/Users/");
  });
});

function installFetch(responses: Response[]) {
  const fetchMock = vi.fn();
  for (const response of responses) fetchMock.mockResolvedValueOnce(response);
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}

function jsonResponse(body: unknown): Response {
  return new Response(JSON.stringify(body), {
    headers: { "Content-Type": "application/json" },
    status: 200,
  });
}

function turnAccepted() {
  return {
    reused: false,
    turn: turnRecord("running"),
    userMessage: {
      content: "request",
      created_at: "2026-07-14T10:00:00Z",
      id: "user-1",
      role: "user",
      session_id: "session-1",
    },
  };
}

function turnPage() {
  const payloads = [
    { type: "assistant_message_finished", text: "Attachment inspected" },
    { type: "turn_finished", turn_id: "turn-1" },
  ];
  return {
    events: payloads.map((payload, index) => ({
      created_at: "2026-07-14T10:00:00Z",
      event_index: index,
      id: `event-${index}`,
      kind: payload.type,
      payload,
      session_id: "session-1",
      turn_id: "turn-1",
    })),
    hasMore: false,
    nextCursor: 1,
    turn: turnRecord("completed"),
  };
}

function turnRecord(status: "completed" | "running") {
  return {
    assistant_message_id: status === "completed" ? "assistant-1" : null,
    failure_message: null,
    finished_at: status === "completed" ? "2026-07-14T10:00:01Z" : null,
    id: "turn-1",
    request_id: "request-1",
    session_id: "session-1",
    started_at: "2026-07-14T10:00:00Z",
    status,
    updated_at: "2026-07-14T10:00:01Z",
    user_message_id: "user-1",
  };
}
