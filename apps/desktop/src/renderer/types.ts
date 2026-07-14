export type MessageAttachmentKind = "file" | "image" | "text-file";

export type MessageAttachment = {
  dataUrl?: string;
  id: string;
  kind: MessageAttachmentKind;
  mime: string;
  name: string;
  path?: string;
  size: number;
  text?: string;
  url?: string;
};

export type ChatBubbleMessage = {
  attachments?: MessageAttachment[];
  body: string;
  id: string;
  kind?: "assistant" | "user";
  role: "assistant" | "user";
  status?: "complete" | "streaming";
};

export type ReasoningMessage = {
  id: string;
  kind: "reasoning";
  role: "assistant";
  status?: "complete" | "running";
  text: string;
};

export type ToolCallMessage = {
  args: string;
  callId: string;
  id: string;
  kind: "tool_call";
  name: string;
  role: "assistant";
  status?: "completed" | "failed" | "running";
};

export type ToolResultMessage = {
  callId: string;
  content: string;
  id: string;
  kind: "tool_result";
  name: string;
  ok?: boolean;
  role: "assistant";
};

export type ChatMessage =
  | ChatBubbleMessage
  | ReasoningMessage
  | ToolCallMessage
  | ToolResultMessage;

export type EndpointType = "responses" | "chat_completions" | "completion";

export type ModelSettings = {
  apiKey: string;
  baseUrl: string;
  endpointType: EndpointType;
  modelName: string;
};
