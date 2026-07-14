import {
  extractAssistantText,
  PostMessageResponse,
  RuntimeEvent
} from "./api";
import {
  ChatMessage,
  ReasoningMessage,
  ToolCallMessage,
  ToolResultMessage
} from "./types";

type IdFactory = () => string;

type ToolResultEnvelope = {
  call_id?: unknown;
  data?: unknown;
  error?: unknown;
  ok?: unknown;
  tool?: unknown;
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function formatValue(value: unknown): string {
  if (value === undefined || value === null) {
    return "";
  }

  if (typeof value === "string") {
    return value;
  }

  try {
    return JSON.stringify(value, null, 2);
  } catch {
    return String(value);
  }
}

function asResultEnvelope(value: unknown): ToolResultEnvelope | null {
  return isRecord(value) ? value : null;
}

function toolResultName(
  event: RuntimeEvent,
  result: ToolResultEnvelope | null,
  call?: ToolCallMessage
): string {
  if (typeof result?.tool === "string" && result.tool.trim()) {
    return result.tool;
  }

  if (typeof event.name === "string" && event.name.trim()) {
    return event.name;
  }

  return call?.name ?? "tool";
}

function toolResultContent(result: ToolResultEnvelope | null, raw: unknown): string {
  if (result?.ok === true) {
    return formatValue(result.data ?? raw);
  }

  if (result?.ok === false && isRecord(result.error)) {
    const message = result.error.message;
    if (typeof message === "string" && message.trim()) {
      return message;
    }
  }

  return formatValue(raw);
}

function updateToolCallStatus(
  messages: ChatMessage[],
  callId: string,
  status: ToolCallMessage["status"]
): void {
  const index = messages.findIndex(
    (message) =>
      "kind" in message &&
      message.kind === "tool_call" &&
      message.callId === callId
  );
  if (index < 0) {
    return;
  }

  messages[index] = {
    ...(messages[index] as ToolCallMessage),
    status
  };
}

function appendReasoning(
  messages: ChatMessage[],
  text: string,
  createId: IdFactory
): void {
  if (!text) {
    return;
  }

  const previous = messages[messages.length - 1];
  if (previous && "kind" in previous && previous.kind === "reasoning") {
    messages[messages.length - 1] = {
      ...previous,
      text: previous.text + text
    };
    return;
  }

  messages.push({
    id: createId(),
    kind: "reasoning",
    role: "assistant",
    status: "complete",
    text
  } satisfies ReasoningMessage);
}

export function buildAssistantTurnMessages(
  response: PostMessageResponse,
  createId: IdFactory
): ChatMessage[] {
  const messages: ChatMessage[] = [];
  const callsById = new Map<string, ToolCallMessage>();
  let syntheticToolIndex = 0;
  const terminal = (response.events ?? []).some((event) =>
    ["assistant_message_finished", "turn_finished", "turn_cancelled", "turn_failed"].includes(event.type)
  );

  for (const event of response.events ?? []) {
    switch (event.type) {
      case "reasoning_delta": {
        appendReasoning(messages, event.text ?? "", createId);
        break;
      }
      case "tool_call_started": {
        syntheticToolIndex += 1;
        const callId = event.call_id ?? `tool-call-${syntheticToolIndex}`;
        const call: ToolCallMessage = {
          args: formatValue(event.arguments),
          callId,
          id: createId(),
          kind: "tool_call",
          name: event.name || "tool",
          role: "assistant",
          status: "running"
        };
        callsById.set(callId, call);
        messages.push(call);
        break;
      }
      case "tool_call_finished": {
        syntheticToolIndex += event.call_id ? 0 : 1;
        const callId = event.call_id ?? `tool-call-${syntheticToolIndex}`;
        const result = asResultEnvelope(event.result);
        const call = callsById.get(callId);
        const ok = typeof result?.ok === "boolean" ? result.ok : undefined;
        const status = ok === false ? "failed" : "completed";
        updateToolCallStatus(messages, callId, status);
        const row: ToolResultMessage = {
          callId,
          content: toolResultContent(result, event.result),
          id: createId(),
          kind: "tool_result",
          name: toolResultName(event, result, call),
          ok,
          role: "assistant"
        };
        messages.push(row);
        break;
      }
      default:
        break;
    }
  }

  const assistantText = extractAssistantText(response);
  if (assistantText) {
    messages.push({
      body: assistantText,
      id: response.assistant_message?.id ?? createId(),
      role: "assistant",
      status: terminal ? "complete" : "streaming"
    });
  }

  if (!terminal) {
    for (const message of messages) {
      if ("kind" in message && message.kind === "reasoning") {
        message.status = "running";
      }
    }
  }

  return messages;
}
