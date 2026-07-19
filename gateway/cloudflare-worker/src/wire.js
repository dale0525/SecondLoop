import { fail } from "./errors.js";

const MESSAGE_ROLES = new Set(["system", "developer", "user", "assistant"]);
const CHAT_MESSAGE_ROLES = new Set(["system", "user", "assistant"]);
const MAX_ITEMS = 4096;

function invalid() {
  fail(400, "wire_shape_not_allowed", "The model request does not match the enabled runtime protocol.");
}

function plainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function onlyKeys(value, allowed) {
  if (!plainObject(value) || Object.keys(value).some((key) => !allowed.includes(key))) invalid();
}

function boundedArray(value) {
  if (!Array.isArray(value) || value.length > MAX_ITEMS) invalid();
  return value;
}

function text(value) {
  if (typeof value !== "string") invalid();
  return value;
}

function toolName(value) {
  if (typeof value !== "string" || value.length < 1 || value.length > 128
    || !/^[A-Za-z0-9_-]+$/.test(value)) invalid();
  return value;
}

function opaqueCallId(value) {
  if (typeof value !== "string" || value.length < 1
    || new TextEncoder().encode(value).byteLength > 512 || /[\u0000-\u001f\u007f]/.test(value)) invalid();
  return value;
}

function schema(value) {
  if (!plainObject(value)) invalid();
  return value;
}

function validateResponsesInput(input) {
  for (const item of boundedArray(input)) {
    if (!plainObject(item)) invalid();
    if (item.type === "function_call") {
      onlyKeys(item, ["type", "call_id", "name", "arguments", "status"]);
      opaqueCallId(item.call_id);
      toolName(item.name);
      text(item.arguments);
      if (item.status !== "completed") invalid();
      continue;
    }
    if (item.type === "function_call_output") {
      onlyKeys(item, ["type", "call_id", "output"]);
      opaqueCallId(item.call_id);
      text(item.output);
      continue;
    }
    onlyKeys(item, ["role", "content"]);
    if (!MESSAGE_ROLES.has(item.role)) invalid();
    text(item.content);
  }
}

function validateResponsesTools(tools) {
  for (const tool of boundedArray(tools)) {
    onlyKeys(tool, ["type", "name", "description", "parameters"]);
    if (tool.type !== "function") invalid();
    toolName(tool.name);
    text(tool.description);
    schema(tool.parameters);
  }
}

function validateResponses(body, tokenField) {
  onlyKeys(body, ["model", "input", "tools", "stream", tokenField]);
  if (body.stream !== true) invalid();
  validateResponsesInput(body.input);
  validateResponsesTools(body.tools);
}

function validateChatToolCall(call) {
  onlyKeys(call, ["id", "type", "function"]);
  opaqueCallId(call.id);
  if (call.type !== "function") invalid();
  onlyKeys(call.function, ["name", "arguments"]);
  toolName(call.function.name);
  text(call.function.arguments);
}

function validateChatMessages(messages) {
  for (const message of boundedArray(messages)) {
    if (!plainObject(message) || !CHAT_MESSAGE_ROLES.has(message.role) && message.role !== "tool") invalid();
    if (message.role === "tool") {
      onlyKeys(message, ["role", "content", "tool_call_id"]);
      text(message.content);
      opaqueCallId(message.tool_call_id);
      continue;
    }
    if (message.role === "assistant" && Object.hasOwn(message, "tool_calls")) {
      onlyKeys(message, ["role", "content", "tool_calls"]);
      text(message.content);
      for (const call of boundedArray(message.tool_calls)) validateChatToolCall(call);
      continue;
    }
    onlyKeys(message, ["role", "content"]);
    text(message.content);
  }
}

function validateChatTools(tools) {
  for (const tool of boundedArray(tools)) {
    onlyKeys(tool, ["type", "function"]);
    if (tool.type !== "function") invalid();
    onlyKeys(tool.function, ["name", "description", "parameters"]);
    toolName(tool.function.name);
    text(tool.function.description);
    schema(tool.function.parameters);
  }
}

function validateChatCompletions(body, tokenField) {
  onlyKeys(body, ["model", "messages", "tools", "stream", tokenField]);
  if (body.stream !== true) invalid();
  validateChatMessages(body.messages);
  validateChatTools(body.tools);
}

function validateCompletion(body, tokenField) {
  onlyKeys(body, ["model", "prompt", "stream", tokenField]);
  text(body.prompt);
  if (body.stream !== false) invalid();
}

export function enforceWireProtocol(route, body) {
  if (route.wireProtocol === "agentweave_responses_v1") {
    validateResponses(body, route.tokenField);
    return;
  }
  if (route.wireProtocol === "agentweave_chat_completions_v1") {
    validateChatCompletions(body, route.tokenField);
    return;
  }
  if (route.wireProtocol === "agentweave_completion_v1") {
    validateCompletion(body, route.tokenField);
    return;
  }
  invalid();
}
