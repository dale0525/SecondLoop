import { cleanup, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";

import { MessageList } from "../src/renderer/components/MessageList";
import { Chat } from "../src/renderer/screens/Chat";
import {
  A2UI_MIME,
  AGENTWEAVE_CARD_MIME,
} from "../src/renderer/structuredContentAdapters";
import {
  createStructuredContentState,
  reduceStructuredContentEvents,
  structuredContentMessages,
} from "../src/renderer/structuredContentReducer";
import type { RuntimeEvent, StructuredContent } from "../src/renderer/runtimeEvents";
import type { ChatMessage } from "../src/renderer/types";

describe("structured content reducer", () => {
  it("folds publications and deletions by owner and monotonic revision", () => {
    const first = published(cardContent({ revision: 1, title: "First" }));
    const newest = published(cardContent({ revision: 3, title: "Newest" }));
    const stale = published(cardContent({ revision: 2, title: "Stale" }));
    const wrongOwner = published(cardContent({
      owner: "other-agent",
      revision: 4,
      title: "Wrong owner",
    }));
    const state = reduceStructuredContentEvents(createStructuredContentState(), [
      first,
      newest,
      stale,
      wrongOwner,
      deleted(2),
    ]);

    expect(structuredContentMessages(state)).toMatchObject([
      { content: { payload: { title: "Newest" }, revision: 3 } },
    ]);

    const deletedState = reduceStructuredContentEvents(state, [
      deleted(3),
      first,
    ]);
    expect(structuredContentMessages(deletedState)).toEqual([]);

    const attemptedReuse = reduceStructuredContentEvents(deletedState, [
      published(cardContent({ revision: 4, title: "Restored" })),
    ]);
    expect(structuredContentMessages(attemptedReuse)).toEqual([]);
  });

  it("produces identical active content for incremental and history replay", () => {
    const events = [
      published(cardContent({ contentId: "one", revision: 1, title: "One" })),
      published(cardContent({ contentId: "two", revision: 1, title: "Two" })),
      published(cardContent({ contentId: "one", revision: 2, title: "One updated" })),
      deleted(1, "two"),
    ];
    const incremental = reduceStructuredContentEvents(
      reduceStructuredContentEvents(createStructuredContentState(), events.slice(0, 2)),
      events.slice(2),
    );
    const history = reduceStructuredContentEvents(createStructuredContentState(), events);

    expect(structuredContentMessages(incremental)).toEqual(
      structuredContentMessages(history),
    );
    expect(structuredContentMessages(history)).toMatchObject([
      { content: { content_id: "one", revision: 2 } },
    ]);
  });

  it("fails closed on malformed envelopes and hides non-user audiences", () => {
    const ownerContent = cardContent({ audience: "owner", revision: 1, title: "Private" });
    const malformed = {
      ...published(cardContent({ revision: 2, title: "Malformed" })),
      content: {
        ...cardContent({ revision: 2, title: "Malformed" }),
        unexpected: true,
      },
    } as RuntimeEvent;
    const state = reduceStructuredContentEvents(createStructuredContentState(), [
      published(ownerContent),
      malformed,
    ]);

    expect(structuredContentMessages(state)).toEqual([]);
  });
});

describe("structured content adapters", () => {
  afterEach(() => cleanup());

  it("renders the strict AgentWeave card schema as native chat content", () => {
    renderStructured(cardContent({
      payload: {
        actionBindings: { confirm: "binding-1" },
        actions: [{
          id: "confirm",
          label: "Confirm",
          style: "primary",
        }],
        fields: [
          { label: "Time", value: "09:00" },
          { label: "Timezone", value: "Asia/Shanghai" },
        ],
        status: { label: "Ready to schedule", tone: "info" },
        summary: "This reminder will run every weekday.",
        title: "Morning briefing",
      },
    }));

    expect(screen.getByRole("heading", { name: "Morning briefing" })).toBeVisible();
    expect(screen.getByText("Asia/Shanghai")).toBeVisible();
    expect(screen.getByText("Ready to schedule")).toBeVisible();
    expect(screen.getByRole("button", { name: "Confirm" })).toBeDisabled();
  });

  it("shows only plain fallback text for unknown MIME and active content", () => {
    const { rerender } = renderStructured(cardContent({
      fallbackText: "[Safe fallback](https://example.com)",
      mimeType: "application/vnd.unknown+json",
      payload: { title: "Unknown renderer" },
    }));

    expect(screen.getByText("[Safe fallback](https://example.com)")).toBeVisible();
    expect(screen.queryByRole("link")).not.toBeInTheDocument();

    rerender(
      <MessageList messages={[structuredMessage(cardContent({
        fallbackText: "Blocked active content",
        payload: {
          html: "<script>window.evil()</script>",
          title: "Must not render",
        },
      }))]} />,
    );

    expect(screen.getByText("Blocked active content")).toBeVisible();
    expect(screen.queryByText("Must not render")).not.toBeInTheDocument();
    expect(document.querySelector("script, iframe")).toBeNull();
  });

  it("accepts only the safe A2UI component profile and opaque actions", async () => {
    const user = userEvent.setup();
    const onAction = vi.fn();
    const safe = cardContent({
      fallbackText: "A2UI fallback",
      mimeType: A2UI_MIME,
      payload: {
        actionBindings: { authorize: "opaque-binding-7" },
        actions: [{ id: "authorize", label: "Continue", style: "primary" }],
        components: [
          { style: "heading", text: "Connect calendar", type: "text" },
          { label: "Status", type: "field", value: "Not connected" },
          { label: "Authorization required", tone: "warning", type: "status" },
        ],
      },
      schemaVersion: "0.8",
    });
    const { rerender } = render(
      <MessageList messages={[structuredMessage(safe)]} />,
    );
    expect(screen.getByRole("button", { name: "Continue" })).toBeDisabled();

    rerender(
      <MessageList
        messages={[structuredMessage(safe)]}
        onStructuredContentAction={onAction}
      />,
    );
    await user.click(screen.getByRole("button", { name: "Continue" }));
    expect(onAction).toHaveBeenCalledWith({
      actionId: "authorize",
      bindingId: "opaque-binding-7",
    });
    expect(Object.keys(onAction.mock.calls[0][0]).sort()).toEqual([
      "actionId",
      "bindingId",
    ]);

    const unbound = cardContent({
      fallbackText: "Unbound A2UI action",
      mimeType: A2UI_MIME,
      payload: {
        actions: [{ id: "authorize", label: "Continue", style: "primary" }],
        components: [{ text: "Connect calendar", type: "text" }],
      },
      schemaVersion: "0.8",
    });
    rerender(
      <MessageList
        messages={[structuredMessage(unbound)]}
        onStructuredContentAction={onAction}
      />,
    );
    expect(screen.getByRole("button", { name: "Continue" })).toBeDisabled();
  });

  it("falls back for unsupported A2UI components or URL-bearing buttons", () => {
    const { rerender } = renderStructured(cardContent({
      fallbackText: "Unsupported image",
      mimeType: A2UI_MIME,
      payload: {
        components: [{ src: "https://example.com/image.png", type: "image" }],
      },
      schemaVersion: "0.8",
    }));
    expect(screen.getByText("Unsupported image")).toBeVisible();
    expect(document.querySelector("img")).toBeNull();

    rerender(
      <MessageList messages={[structuredMessage(cardContent({
        fallbackText: "Blocked navigation",
        mimeType: A2UI_MIME,
        payload: {
          actionBindings: { open: "binding-open" },
          actions: [{ id: "open", label: "Open", url: "https://example.com" }],
          components: [{ text: "Unsafe navigation", type: "text" }],
        },
        schemaVersion: "0.8",
      }))]} />,
    );
    expect(screen.getByText("Blocked navigation")).toBeVisible();
    expect(screen.queryByRole("button", { name: "Open" })).not.toBeInTheDocument();
  });

  it("disables card actions while pending and exposes a retryable error", async () => {
    const user = userEvent.setup();
    let rejectAction: (error: Error) => void = () => undefined;
    const onAction = vi.fn(() => new Promise<void>((_resolve, reject) => {
      rejectAction = reject;
    }));
    render(
      <MessageList
        messages={[structuredMessage(cardContent({
          payload: {
            actionBindings: { confirm: "binding-1" },
            actions: [{ id: "confirm", label: "Confirm", style: "primary" }],
            title: "Reminder preview",
          },
        }))]}
        onStructuredContentAction={onAction}
      />,
    );
    const button = screen.getByRole("button", { name: "Confirm" });
    await user.click(button);
    expect(button).toBeDisabled();
    expect(button).toHaveAttribute("aria-busy", "true");
    rejectAction(new Error("Host rejected action"));
    expect(await screen.findByRole("alert")).toBeVisible();
    await waitFor(() => expect(button).toBeEnabled());
  });
});

describe("structured content chat integration", () => {
  afterEach(() => {
    cleanup();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
    window.localStorage.clear();
    delete window.agentWeave;
  });

  it("renders the same structured revision from live polling and session history", async () => {
    const user = userEvent.setup();
    const content = cardContent({
      payload: {
        fields: [{ label: "Next run", value: "Tomorrow at 09:00" }],
        status: { label: "Scheduled", tone: "success" },
        title: "Daily reminder",
      },
      revision: 2,
    });
    const eventPayloads: RuntimeEvent[] = [
      published(cardContent({ ...contentOptions(content), revision: 1 })),
      published(content),
      { text: "The reminder is ready.", type: "assistant_message_finished" },
      { turn_id: "turn-1", type: "turn_finished" },
    ];
    vi.stubGlobal("fetch", vi.fn(async (input: string | URL | Request, init?: RequestInit) => {
      const url = String(input);
      if (url.endsWith("/sessions") && init?.method === "POST") {
        return jsonResponse(sessionRecord());
      }
      if (url.endsWith("/sessions/session-1/turns") && init?.method === "POST") {
        return jsonResponse(turnAccepted());
      }
      if (url.includes("/sessions/session-1/turns/turn-1/events")) {
        return jsonResponse(turnPage(eventPayloads));
      }
      if (url.includes("/sessions/session-1/events")) {
        return new Promise<Response>(() => undefined);
      }
      throw new Error(`Unexpected request: ${url}`);
    }));

    render(<Chat />);
    await user.type(screen.getByLabelText("Message AgentWeave"), "Create a reminder");
    await user.click(screen.getByRole("button", { name: "Send message" }));
    expect(await screen.findByText("Tomorrow at 09:00")).toBeVisible();
    expect(screen.getByText("Scheduled")).toBeVisible();

    cleanup();
    vi.unstubAllGlobals();
    installHistoryBridge(eventPayloads);
    render(<Chat />);

    expect(await screen.findByText("Tomorrow at 09:00")).toBeVisible();
    expect(screen.getByText("Scheduled")).toBeVisible();
    await waitFor(() => {
      expect(screen.getAllByText("Daily reminder")).toHaveLength(1);
    });
  });

  it("applies a structured revision that arrives after the terminal turn", async () => {
    const initial = cardContent({
      payload: {
        status: { label: "Waiting for authorization", tone: "info" },
        title: "Connect calendar",
      },
      revision: 2,
    });
    const completed = cardContent({
      payload: {
        fields: [{ label: "Account", value: "user@example.test" }],
        status: { label: "Completed", tone: "success" },
        title: "Connect calendar",
      },
      revision: 3,
    });
    installHistoryBridge([published(initial)], [published(completed)]);
    render(<Chat />);

    expect(await screen.findByText("user@example.test")).toBeVisible();
    expect(screen.getByText("Completed")).toBeVisible();
    expect(screen.queryByText("Waiting for authorization")).not.toBeInTheDocument();
  });
});

type CardOptions = {
  audience?: StructuredContent["audience"];
  contentId?: string;
  fallbackText?: string;
  mimeType?: string;
  owner?: string;
  payload?: unknown;
  revision?: number;
  schemaVersion?: string;
  title?: string;
};

function cardContent(options: CardOptions = {}): StructuredContent {
  return {
    audience: options.audience ?? "user",
    content_id: options.contentId ?? "card-1",
    fallback_text: options.fallbackText ?? options.title ?? "Structured content fallback",
    mime_type: options.mimeType ?? AGENTWEAVE_CARD_MIME,
    owner: options.owner ?? "assistant-agent",
    payload: options.payload ?? { title: options.title ?? "Structured card" },
    revision: options.revision ?? 1,
    schema_version: options.schemaVersion ?? "1",
  };
}

function contentOptions(content: StructuredContent): CardOptions {
  return {
    audience: content.audience,
    contentId: content.content_id,
    fallbackText: content.fallback_text,
    mimeType: content.mime_type,
    owner: content.owner,
    payload: content.payload,
    schemaVersion: content.schema_version,
  };
}

function published(content: StructuredContent): RuntimeEvent {
  return { content, type: "structured_content_published" };
}

function deleted(revision: number, contentId = "card-1"): RuntimeEvent {
  return {
    content_id: contentId,
    owner: "assistant-agent",
    revision,
    type: "structured_content_deleted",
  };
}

function structuredMessage(content: StructuredContent): ChatMessage {
  return {
    content,
    id: `structured:${content.content_id}`,
    kind: "structured_content",
    role: "assistant",
  };
}

function renderStructured(content: StructuredContent) {
  return render(<MessageList messages={[structuredMessage(content)]} />);
}

function jsonResponse(body: unknown): Response {
  return new Response(JSON.stringify(body), {
    headers: { "Content-Type": "application/json" },
    status: 200,
  });
}

function sessionRecord() {
  return {
    created_at: "2026-07-17T08:00:00Z",
    id: "session-1",
    title: "Reminder",
    updated_at: "2026-07-17T08:00:01Z",
  };
}

function turnRecord(status: "completed" | "running") {
  return {
    assistant_message_id: status === "completed" ? "assistant-1" : null,
    failure_message: null,
    finished_at: status === "completed" ? "2026-07-17T08:00:01Z" : null,
    id: "turn-1",
    request_id: "request-1",
    session_id: "session-1",
    started_at: "2026-07-17T08:00:00Z",
    status,
    updated_at: "2026-07-17T08:00:01Z",
    user_message_id: "user-1",
  };
}

function turnAccepted() {
  return {
    reused: false,
    turn: turnRecord("running"),
    userMessage: {
      content: "Create a reminder",
      created_at: "2026-07-17T08:00:00Z",
      id: "user-1",
      role: "user",
      session_id: "session-1",
    },
  };
}

function turnPage(payloads: RuntimeEvent[]) {
  return {
    events: conversationEvents(payloads),
    hasMore: false,
    nextCursor: payloads.length - 1,
    turn: turnRecord("completed"),
  };
}

function conversationEvents(payloads: RuntimeEvent[]) {
  return payloads.map((payload, index) => ({
    created_at: "2026-07-17T08:00:01Z",
    event_index: index,
    id: `event-${index}`,
    kind: payload.type,
    payload,
    session_id: "session-1",
    turn_id: "turn-1",
  }));
}

function installHistoryBridge(
  payloads: RuntimeEvent[],
  backgroundPayloads: RuntimeEvent[] = [],
): void {
  const session = sessionRecord();
  let backgroundDelivered = false;
  window.agentWeave = {
    approval: { open: async () => { throw new Error("unavailable"); } },
    owner: {} as NonNullable<Window["agentWeave"]>["owner"],
    server: {
      request: vi.fn(async (operation: string) => {
        if (operation === "sessions.list") return { items: [session], nextCursor: null };
        if (operation === "sessions.load") {
          return {
            events: conversationEvents(payloads),
            messages: [
              {
                content: "Create a reminder",
                created_at: "2026-07-17T08:00:00Z",
                id: "user-1",
                role: "user",
                session_id: "session-1",
              },
              {
                content: "The reminder is ready.",
                created_at: "2026-07-17T08:00:01Z",
                id: "assistant-1",
                role: "assistant",
                session_id: "session-1",
              },
            ],
            session,
            turns: [turnRecord("completed")],
          };
        }
        if (operation === "sessions.events") {
          if (!backgroundDelivered && backgroundPayloads.length > 0) {
            backgroundDelivered = true;
            const events = conversationEvents(backgroundPayloads).map((event, index) => ({
              ...event,
              event_index: payloads.length + index,
              id: `background-event-${index}`,
              turn_id: undefined,
            }));
            return {
              events,
              hasMore: false,
              nextCursor: events.at(-1)?.event_index ?? payloads.length - 1,
            };
          }
          return new Promise(() => undefined);
        }
        throw new Error(`Unexpected operation: ${operation}`);
      }),
    },
  };
}
