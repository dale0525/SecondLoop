import { useState } from "react";
import {
  Brain,
  CheckCircle2,
  ChevronRight,
  LoaderCircle,
  Wrench,
  XCircle
} from "lucide-react";

import {
  ReasoningMessage,
  ToolCallMessage,
  ToolResultMessage
} from "../types";

type ToolActivityItem = ToolCallMessage | ToolResultMessage;

type ReasoningRowProps = {
  message: ReasoningMessage;
};

type ToolActivityGroupProps = {
  items: ToolActivityItem[];
};

function isToolCall(item: ToolActivityItem): item is ToolCallMessage {
  return item.kind === "tool_call";
}

function isToolResult(item: ToolActivityItem): item is ToolResultMessage {
  return item.kind === "tool_result";
}

export function humanizeToolName(name: string): string {
  const words = name
    .replace(/^mcp__/, "")
    .replace(/[_-]+/g, " ")
    .trim()
    .split(/\s+/)
    .filter(Boolean);

  if (words.length === 0) {
    return "Tool";
  }

  return words
    .map((word, index) =>
      index === 0 ? word.charAt(0).toUpperCase() + word.slice(1) : word
    )
    .join(" ");
}

function toolGroupTitle(items: ToolActivityItem[]): string {
  const calls = items.filter(isToolCall);
  if (calls.length > 1) {
    return `${calls.length} tools`;
  }

  return humanizeToolName(items[0]?.name ?? "tool");
}

function toolGroupStatus(items: ToolActivityItem[]): string {
  if (
    items.some((item) => isToolCall(item) && item.status === "running")
  ) {
    return "Running";
  }

  if (
    items.some(
      (item) =>
        (isToolCall(item) && item.status === "failed") ||
        (isToolResult(item) && item.ok === false)
    )
  ) {
    return "Failed";
  }

  return "Completed";
}

function orderToolItems(items: ToolActivityItem[]): ToolActivityItem[] {
  const resultsByCallId = new Map<string, ToolResultMessage[]>();
  for (const item of items) {
    if (!isToolResult(item)) continue;
    const bucket = resultsByCallId.get(item.callId) ?? [];
    bucket.push(item);
    resultsByCallId.set(item.callId, bucket);
  }

  const emittedResults = new Set<ToolResultMessage>();
  const ordered: ToolActivityItem[] = [];
  for (const item of items) {
    if (!isToolCall(item)) {
      if (!emittedResults.has(item)) {
        ordered.push(item);
        emittedResults.add(item);
      }
      continue;
    }

    ordered.push(item);
    for (const result of resultsByCallId.get(item.callId) ?? []) {
      ordered.push(result);
      emittedResults.add(result);
    }
  }

  return ordered;
}

function toolItemTitle(item: ToolActivityItem): string {
  const prefix = isToolCall(item) ? "Call" : "Result";
  return `${prefix} · ${humanizeToolName(item.name)}`;
}

function statusIcon(status: string): JSX.Element {
  if (status === "Running") {
    return <LoaderCircle size={14} aria-hidden="true" className="activity-spin" />;
  }

  if (status === "Failed") {
    return <XCircle size={14} aria-hidden="true" />;
  }

  return <CheckCircle2 size={14} aria-hidden="true" />;
}

export function ReasoningRow({ message }: ReasoningRowProps): JSX.Element {
  const [open, setOpen] = useState(false);
  const running = message.status === "running";
  const title = running ? "Thinking..." : "Thought";

  return (
    <article
      aria-label={running ? "Assistant thinking" : "Assistant thought"}
      className={`activity-row reasoning-row${running ? " activity-row-running" : ""}`}
    >
      <button
        aria-expanded={open}
        className="activity-summary"
        onClick={() => setOpen((current) => !current)}
        type="button"
      >
        {running ? (
          <LoaderCircle size={14} aria-hidden="true" className="activity-spin" />
        ) : (
          <Brain size={14} aria-hidden="true" />
        )}
        <span className="activity-title">{title}</span>
        {running ? <span className="activity-status">{message.text}</span> : null}
        <ChevronRight
          size={14}
          aria-hidden="true"
          className={`activity-chevron${open ? " activity-chevron-open" : ""}`}
        />
      </button>
      {open ? <pre className="activity-detail">{message.text}</pre> : null}
    </article>
  );
}

export function ToolActivityGroup({
  items
}: ToolActivityGroupProps): JSX.Element {
  const [open, setOpen] = useState(false);
  const status = toolGroupStatus(items);
  const orderedItems = orderToolItems(items);

  return (
    <article aria-label="Assistant tool activity" className="activity-row tool-row">
      <button
        aria-expanded={open}
        className="activity-summary"
        onClick={() => setOpen((current) => !current)}
        type="button"
      >
        {items.length > 1 ? (
          <Wrench size={14} aria-hidden="true" />
        ) : (
          statusIcon(status)
        )}
        <span className="activity-title">{toolGroupTitle(items)}</span>
        <span className="activity-status">{status}</span>
        <ChevronRight
          size={14}
          aria-hidden="true"
          className={`activity-chevron${open ? " activity-chevron-open" : ""}`}
        />
      </button>
      {open ? (
        <div className="activity-tool-items">
          {orderedItems.map((item) => (
            <div className="activity-tool-item" key={item.id}>
              <div className="activity-tool-item-title">{toolItemTitle(item)}</div>
              <pre className="activity-detail">
                {isToolCall(item) ? item.args || "{}" : item.content || "(empty)"}
              </pre>
            </div>
          ))}
        </div>
      ) : null}
    </article>
  );
}
