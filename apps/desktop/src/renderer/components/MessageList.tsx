import {
  ChatBubbleMessage,
  ChatMessage,
  ReasoningMessage,
  StructuredContentActionHandler,
  StructuredContentMessage,
  ToolCallMessage,
  ToolResultMessage
} from "../types";
import { ReasoningRow, ToolActivityGroup } from "./ActivityRows";
import { MessageContent } from "./messageContent/MessageContent";

type MessageListProps = {
  messages: ChatMessage[];
  onStructuredContentAction?: StructuredContentActionHandler;
};

function isBubble(message: ChatMessage): message is ChatBubbleMessage {
  return (
    !("kind" in message) ||
    message.kind === undefined ||
    message.kind === "assistant" ||
    message.kind === "user"
  );
}

function isReasoning(message: ChatMessage): message is ReasoningMessage {
  return "kind" in message && message.kind === "reasoning";
}

function isToolRow(
  message: ChatMessage
): message is ToolCallMessage | ToolResultMessage {
  return (
    "kind" in message &&
    (message.kind === "tool_call" || message.kind === "tool_result")
  );
}

function isStructuredContent(
  message: ChatMessage
): message is StructuredContentMessage {
  return "kind" in message && message.kind === "structured_content";
}

export function MessageList({
  messages,
  onStructuredContentAction,
}: MessageListProps): JSX.Element {
  const rows: JSX.Element[] = [];

  for (let index = 0; index < messages.length; index += 1) {
    const message = messages[index];

    if (isReasoning(message)) {
      rows.push(<ReasoningRow key={message.id} message={message} />);
      continue;
    }

    if (isToolRow(message)) {
      const group: Array<ToolCallMessage | ToolResultMessage> = [];
      const start = index;
      while (index < messages.length) {
        const current = messages[index];
        if (!isToolRow(current)) {
          break;
        }
        group.push(current);
        index += 1;
      }
      index -= 1;
      rows.push(
        <ToolActivityGroup
          items={group}
          key={`tool-activity-${group[0]?.id ?? start}`}
        />
      );
      continue;
    }

    if (isStructuredContent(message)) {
      rows.push(
        <article
          aria-label="Assistant message"
          className="message-bubble message-bubble-assistant message-bubble-structured"
          key={message.id}
        >
          <MessageContent
            body={message.content.fallback_text}
            onStructuredContentAction={onStructuredContentAction}
            role="assistant"
            structuredContent={message.content}
          />
        </article>
      );
      continue;
    }

    if (!isBubble(message)) {
      continue;
    }

    rows.push(
      <article
        aria-label={message.role === "assistant" ? "Assistant message" : "User message"}
        className={`message-bubble message-bubble-${message.role}`}
        key={message.id}
      >
        <MessageContent
          attachments={message.attachments}
          body={message.body}
          isStreaming={message.status === "streaming"}
          role={message.role}
        />
      </article>
    );
  }

  return (
    <section className="message-list" aria-live="polite" aria-label="Conversation">
      {rows}
    </section>
  );
}
