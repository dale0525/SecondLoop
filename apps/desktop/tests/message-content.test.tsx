import { cleanup, render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it } from "vitest";

import { MessageList } from "../src/renderer/components/MessageList";
import { ChatMessage } from "../src/renderer/types";

describe("rich message content", () => {
  afterEach(() => {
    cleanup();
  });

  it("renders reasoning rows as collapsible assistant activity", async () => {
    const user = userEvent.setup();
    render(
      <MessageList
        messages={
          [
            {
              body: "",
              id: "reasoning-complete",
              kind: "reasoning",
              role: "assistant",
              status: "complete",
              text: "I should inspect the renderer first."
            },
            {
              body: "",
              id: "reasoning-running",
              kind: "reasoning",
              role: "assistant",
              status: "running",
              text: "Reading the current message list."
            }
          ] as unknown as ChatMessage[]
        }
      />
    );

    expect(screen.getByRole("button", { name: /Thought/i })).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: /Thinking/i })
    ).toBeInTheDocument();
    expect(
      screen.queryByText("I should inspect the renderer first.")
    ).not.toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: /Thought/i }));

    expect(
      screen.getByText("I should inspect the renderer first.")
    ).toBeInTheDocument();
  });

  it("groups tool calls and results into a collapsible activity row", async () => {
    const user = userEvent.setup();
    render(
      <MessageList
        messages={
          [
            {
              args: '{"query":"MessageList"}',
              body: "",
              callId: "call-search",
              id: "tool-call-search",
              kind: "tool_call",
              name: "search_files",
              role: "assistant",
              status: "completed"
            },
            {
              body: "",
              callId: "call-search",
              content: "2 matches",
              id: "tool-result-search",
              kind: "tool_result",
              name: "search_files",
              ok: true,
              role: "assistant"
            }
          ] as unknown as ChatMessage[]
        }
      />
    );

    expect(
      screen.getByRole("button", { name: /Search files/i })
    ).toBeInTheDocument();
    expect(screen.queryByText('{"query":"MessageList"}')).not.toBeInTheDocument();
    expect(screen.queryByText("2 matches")).not.toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: /Search files/i }));

    expect(screen.getByText('{"query":"MessageList"}')).toBeInTheDocument();
    expect(screen.getByText("2 matches")).toBeInTheDocument();
  });

  it("marks metadata-only tool results complete after the finished event", () => {
    render(
      <MessageList
        messages={[
          {
            args: "{}",
            callId: "call-publish",
            id: "tool-call-publish",
            kind: "tool_call",
            name: "structured_content_publish",
            role: "assistant",
            status: "completed"
          },
          {
            callId: "call-publish",
            content: "",
            id: "tool-result-publish",
            kind: "tool_result",
            name: "structured_content_publish",
            ok: undefined,
            role: "assistant"
          }
        ] as ChatMessage[]}
      />
    );

    expect(
      screen.getByRole("button", { name: /Structured content publish Completed/i })
    ).toBeInTheDocument();
  });

  it("renders assistant markdown, math, and code as structured content", () => {
    render(
      <MessageList
        messages={[
          {
            body: [
              "### Project Synthesis",
              "",
              "The result is **strong** and includes $E = mc^2$.",
              "",
              "- Retention improved",
              "- Latency needs review",
              "",
              "| Metric | Value |",
              "| --- | --- |",
              "| Retention | 74.2% |",
              "",
              "$$\\sigma = \\sqrt{\\frac{1}{N}\\sum_i(x_i-\\mu)^2}$$",
              "",
              "```ts",
              "const score = 74.2;",
              "```"
            ].join("\n"),
            id: "assistant-rich",
            role: "assistant"
          }
        ]}
      />
    );

    expect(
      screen.getByRole("heading", { name: "Project Synthesis" })
    ).toBeInTheDocument();
    expect(screen.getByText("strong")).toBeInTheDocument();
    expect(screen.getByRole("list")).toBeInTheDocument();
    expect(screen.getByRole("table")).toBeInTheDocument();
    expect(document.querySelector(".chat-table-scroll > table")).not.toBeNull();
    expect(screen.getByText("Retention")).toBeInTheDocument();
    expect(document.querySelector(".katex")).not.toBeNull();
    expect(screen.getByText("ts")).toBeInTheDocument();
    expect(screen.getByText("const score = 74.2;")).toBeInTheDocument();
    expect(document.querySelector("pre > .chat-code-block")).toBeNull();
  });

  it("renders attachments and assistant-delivered file outputs", () => {
    const messages = [
      {
        body: [
          "Generated outputs:",
          "",
          "MEDIA:https://example.com/chart.png",
          "Saved to: `/tmp/report.pdf`"
        ].join("\n"),
        id: "assistant-files",
        role: "assistant",
        attachments: [
          {
            id: "att-image",
            kind: "image",
            name: "chart.png",
            mime: "image/png",
            size: 2048,
            dataUrl:
              "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/lW7cQwAAAABJRU5ErkJggg=="
          },
          {
            id: "att-text",
            kind: "text-file",
            name: "notes.md",
            mime: "text/markdown",
            size: 512
          }
        ]
      }
    ] as unknown as ChatMessage[];

    render(<MessageList messages={messages} />);

    const bubble = screen.getByLabelText("Assistant message");
    expect(within(bubble).getAllByText("chart.png").length).toBeGreaterThan(0);
    expect(within(bubble).getByText("notes.md")).toBeInTheDocument();
    expect(within(bubble).getByAltText("chart.png")).toBeInTheDocument();
    expect(within(bubble).getByText("report.pdf")).toBeInTheDocument();
  });

  it("uses a friendly label for assistant-delivered data image previews", () => {
    render(
      <MessageList
        messages={[
          {
            body: [
              "Generated preview:",
              "",
              "MEDIA:data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ"
            ].join("\n"),
            id: "assistant-data-image",
            role: "assistant"
          }
        ]}
      />
    );

    const bubble = screen.getByLabelText("Assistant message");
    expect(within(bubble).getByAltText("Image preview")).toBeInTheDocument();
    expect(within(bubble).getByText("Image preview")).toBeInTheDocument();
    expect(within(bubble).queryByText(/base64/)).not.toBeInTheDocument();
  });
});
