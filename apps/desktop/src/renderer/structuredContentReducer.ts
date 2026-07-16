import type { RuntimeEvent, StructuredContent } from "./runtimeEvents";
import type { ChatMessage, StructuredContentMessage } from "./types";

type StructuredContentEntry = {
  content: StructuredContent | null;
  order: number | null;
  owner: string;
  revision: number;
};

export type StructuredContentState = {
  entries: ReadonlyMap<string, StructuredContentEntry>;
  nextOrder: number;
};

const ID_PATTERN = /^[A-Za-z0-9._-]{1,255}$/;
const MIME_PATTERN = /^[A-Za-z0-9.+-]+\/[A-Za-z0-9.+-]+$/;

export function createStructuredContentState(): StructuredContentState {
  return { entries: new Map(), nextOrder: 0 };
}

export function reduceStructuredContentEvents(
  state: StructuredContentState,
  events: Iterable<RuntimeEvent>,
): StructuredContentState {
  let next = state;
  for (const event of events) {
    next = reduceStructuredContentEvent(next, event);
  }
  return next;
}

export function reduceStructuredContentEvent(
  state: StructuredContentState,
  event: RuntimeEvent,
): StructuredContentState {
  if (event.type === "structured_content_published") {
    const content = parseStructuredContent(event.content);
    if (!content) return state;
    const previous = state.entries.get(content.content_id);
    if (previous?.content === null) return state;
    if (previous && (
      previous.owner !== content.owner || content.revision <= previous.revision
    )) {
      return state;
    }
    const entries = new Map(state.entries);
    const order = previous?.order ?? state.nextOrder;
    entries.set(content.content_id, {
      content,
      order,
      owner: content.owner,
      revision: content.revision,
    });
    return {
      entries,
      nextOrder: previous === undefined ? state.nextOrder + 1 : state.nextOrder,
    };
  }

  if (event.type !== "structured_content_deleted") return state;
  const deletion = parseDeletion(event);
  if (!deletion) return state;
  const previous = state.entries.get(deletion.contentId);
  if (previous && (
    previous.owner !== deletion.owner || deletion.revision < previous.revision
  )) {
    return state;
  }
  if (previous?.content === null && deletion.revision === previous.revision) {
    return state;
  }
  const entries = new Map(state.entries);
  entries.set(deletion.contentId, {
    content: null,
    order: previous?.order ?? null,
    owner: deletion.owner,
    revision: deletion.revision,
  });
  return { entries, nextOrder: state.nextOrder };
}

export function structuredContentMessages(
  state: StructuredContentState,
): StructuredContentMessage[] {
  return [...state.entries.entries()]
    .filter((entry): entry is [string, StructuredContentEntry & { content: StructuredContent }] => (
      entry[1].content !== null && entry[1].content.audience === "user"
    ))
    .sort((left, right) => (left[1].order ?? 0) - (right[1].order ?? 0))
    .map(([contentId, entry]) => ({
      content: entry.content,
      id: `structured:${contentId}`,
      kind: "structured_content",
      role: "assistant",
    }));
}

export function mergeStructuredContentMessages(
  messages: ChatMessage[],
  state: StructuredContentState,
): ChatMessage[] {
  return [
    ...messages.filter((message) => message.kind !== "structured_content"),
    ...structuredContentMessages(state),
  ];
}

function parseStructuredContent(value: unknown): StructuredContent | null {
  if (!isRecord(value) || !hasOnlyKeys(value, [
    "audience",
    "content_id",
    "fallback_text",
    "mime_type",
    "owner",
    "payload",
    "revision",
    "schema_version",
  ])) {
    return null;
  }
  if (!isId(value.content_id) || !isId(value.owner)) return null;
  if (!isPositiveRevision(value.revision)) return null;
  if (
    typeof value.mime_type !== "string"
    || value.mime_type.length > 128
    || !MIME_PATTERN.test(value.mime_type)
  ) {
    return null;
  }
  if (
    typeof value.schema_version !== "string"
    || value.schema_version.trim().length === 0
    || byteLength(value.schema_version) > 64
  ) {
    return null;
  }
  if (
    typeof value.fallback_text !== "string"
    || value.fallback_text.trim().length === 0
    || byteLength(value.fallback_text) > 32 * 1024
  ) {
    return null;
  }
  if (!isSafeJsonPayload(value.payload)) return null;
  if (!new Set(["user", "owner", "developer"]).has(String(value.audience))) {
    return null;
  }
  return value as StructuredContent;
}

function parseDeletion(event: RuntimeEvent): {
  contentId: string;
  owner: string;
  revision: number;
} | null {
  if (
    !isId(event.content_id)
    || !isId(event.owner)
    || !isPositiveRevision(event.revision)
  ) {
    return null;
  }
  return {
    contentId: event.content_id,
    owner: event.owner,
    revision: event.revision,
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasOnlyKeys(value: Record<string, unknown>, allowed: string[]): boolean {
  const keys = new Set(allowed);
  return Object.keys(value).every((key) => keys.has(key));
}

function isId(value: unknown): value is string {
  return typeof value === "string" && ID_PATTERN.test(value);
}

function isPositiveRevision(value: unknown): value is number {
  return Number.isSafeInteger(value) && Number(value) > 0;
}

function isSafeJsonPayload(value: unknown): boolean {
  try {
    const serialized = JSON.stringify(value);
    if (typeof serialized !== "string" || byteLength(serialized) > 256 * 1024) {
      return false;
    }
  } catch {
    return false;
  }

  const pending: Array<{ depth: number; value: unknown }> = [{ depth: 0, value }];
  let nodes = 0;
  while (pending.length > 0) {
    const current = pending.pop();
    if (!current || current.depth > 16 || (nodes += 1) > 4_096) return false;
    if (current.value === null || typeof current.value === "boolean") continue;
    if (typeof current.value === "number") {
      if (!Number.isFinite(current.value)) return false;
      continue;
    }
    if (typeof current.value === "string") {
      if (byteLength(current.value) > 256 * 1024) return false;
      continue;
    }
    if (Array.isArray(current.value)) {
      if (current.value.length > 512) return false;
      for (const child of current.value) {
        pending.push({ depth: current.depth + 1, value: child });
      }
      continue;
    }
    if (!isRecord(current.value) || Object.keys(current.value).length > 256) {
      return false;
    }
    for (const [key, child] of Object.entries(current.value)) {
      if (byteLength(key) > 128) return false;
      pending.push({ depth: current.depth + 1, value: child });
    }
  }
  return true;
}

function byteLength(value: string): number {
  return new TextEncoder().encode(value).byteLength;
}
