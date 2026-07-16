import type { StructuredContent } from "./runtimeEvents";

export const AGENTWEAVE_CARD_MIME = "application/vnd.agentweave.card+json";
export const A2UI_MIME = "application/vnd.a2ui.safe-card+json";

export type StructuredContentTone =
  | "neutral"
  | "info"
  | "success"
  | "warning"
  | "danger";

export type StructuredContentBlock =
  | { kind: "field"; label: string; value: string }
  | { kind: "list"; items: string[] }
  | { kind: "status"; label: string; tone: StructuredContentTone }
  | { kind: "text"; style: "body" | "caption" | "heading"; text: string };

export type StructuredContentAction = {
  actionId: string;
  bindingId: string | null;
  label: string;
  variant: "danger" | "primary" | "secondary";
};

export type StructuredContentViewModel = {
  actions: StructuredContentAction[];
  blocks: StructuredContentBlock[];
  source: "a2ui" | "agentweave";
};

type StructuredContentAdapter = {
  matches: (mimeType: string) => boolean;
  parse: (content: StructuredContent) => StructuredContentViewModel | null;
};

const ID_PATTERN = /^[A-Za-z0-9._-]{1,255}$/;
const FORBIDDEN_KEYS = new Set([
  "formaction",
  "href",
  "html",
  "iframe",
  "javascript",
  "apikey",
  "api_key",
  "authorization",
  "clientsecret",
  "client_secret",
  "cookie",
  "credential",
  "password",
  "refreshtoken",
  "refresh_token",
  "accesstoken",
  "access_token",
  "token",
  "verifier",
  "script",
  "src",
  "url",
]);
const TONES = new Set<StructuredContentTone>([
  "neutral",
  "info",
  "success",
  "warning",
  "danger",
]);
const adapters: StructuredContentAdapter[] = [
  {
    matches: (mimeType) => mimeType === AGENTWEAVE_CARD_MIME,
    parse: parseAgentWeaveCard,
  },
  {
    matches: (mimeType) => mimeType.startsWith("application/vnd.a2ui."),
    parse: parseA2uiCard,
  },
];

export function adaptStructuredContent(
  content: StructuredContent,
): StructuredContentViewModel | null {
  if (containsForbiddenKey(content.payload)) return null;
  const adapter = adapters.find((candidate) => candidate.matches(content.mime_type));
  return adapter?.parse(content) ?? null;
}

function parseAgentWeaveCard(
  content: StructuredContent,
): StructuredContentViewModel | null {
  if (content.schema_version !== "1" || !isRecord(content.payload)) return null;
  const payload = content.payload;
  if (!hasOnlyKeys(payload, [
    "actionBindings",
    "actions",
    "fields",
    "status",
    "summary",
    "title",
  ])) {
    return null;
  }
  const blocks: StructuredContentBlock[] = [];
  const title = requiredText(payload.title, 256);
  const summary = optionalText(payload.summary, 4_096);
  if (!title || (payload.summary !== undefined && !summary)) return null;
  blocks.push({ kind: "text", style: "heading", text: title });
  if (summary) blocks.push({ kind: "text", style: "body", text: summary });

  const fields = parseFields(payload.fields);
  if (fields === null) return null;
  blocks.push(...fields);

  const status = parseStatus(payload.status);
  if (status === null) return null;
  if (status) blocks.push(status);

  const actions = parseActions(payload.actions, payload.actionBindings);
  if (actions === null) return null;
  return { actions, blocks, source: "agentweave" };
}

function parseA2uiCard(content: StructuredContent): StructuredContentViewModel | null {
  if (!new Set(["0.8", "1"]).has(content.schema_version) || !isRecord(content.payload)) {
    return null;
  }
  if (!hasOnlyKeys(content.payload, ["actionBindings", "actions", "components"])) {
    return null;
  }
  const components = content.payload.components;
  if (!Array.isArray(components) || components.length === 0 || components.length > 64) {
    return null;
  }
  const blocks: StructuredContentBlock[] = [];
  const actions: StructuredContentAction[] = [];
  for (const component of components) {
    if (!isRecord(component) || typeof component.type !== "string") return null;
    switch (component.type) {
      case "text": {
        if (!hasOnlyKeys(component, ["style", "text", "type"])) return null;
        const text = requiredText(component.text, 4_000);
        const style = component.style ?? "body";
        if (!text || !new Set(["body", "caption", "heading"]).has(String(style))) {
          return null;
        }
        blocks.push({
          kind: "text",
          style: style as "body" | "caption" | "heading",
          text,
        });
        break;
      }
      case "field": {
        const field = parseField(component, true);
        if (!field) return null;
        blocks.push(field);
        break;
      }
      case "status": {
        const status = parseStatus(component, true);
        if (!status) return null;
        blocks.push(status);
        break;
      }
      case "list": {
        if (!hasOnlyKeys(component, ["items", "type"])) return null;
        const items = parseList(component.items);
        if (!items || items.length === 0) return null;
        blocks.push({ items, kind: "list" });
        break;
      }
      default:
        return null;
    }
  }
  const parsedActions = parseActions(
    content.payload.actions,
    content.payload.actionBindings,
  );
  if (parsedActions === null) return null;
  actions.push(...parsedActions);
  return { actions, blocks, source: "a2ui" };
}

function parseFields(value: unknown): StructuredContentBlock[] | null {
  if (value === undefined) return [];
  if (!Array.isArray(value) || value.length > 32) return null;
  const fields: StructuredContentBlock[] = [];
  for (const candidate of value) {
    const field = parseField(candidate, false);
    if (!field) return null;
    fields.push(field);
  }
  return fields;
}

function parseField(value: unknown, includeType: boolean): StructuredContentBlock | null {
  if (!isRecord(value)) return null;
  if (!hasOnlyKeys(value, includeType ? ["label", "type", "value"] : ["label", "value"])) {
    return null;
  }
  const label = requiredText(value.label, 4_096);
  const fieldValue = requiredText(value.value, 4_096);
  return label && fieldValue ? { kind: "field", label, value: fieldValue } : null;
}

function parseStatus(
  value: unknown,
  includeType = false,
): Extract<StructuredContentBlock, { kind: "status" }> | null | undefined {
  if (value === undefined) return undefined;
  if (!isRecord(value)) return null;
  if (!hasOnlyKeys(value, includeType ? ["label", "tone", "type"] : ["label", "tone"])) {
    return null;
  }
  const label = requiredText(value.label, 128);
  const tone = value.tone ?? "neutral";
  if (!label || !TONES.has(tone as StructuredContentTone)) return null;
  return { kind: "status", label, tone: tone as StructuredContentTone };
}

function parseList(value: unknown): string[] | null {
  if (value === undefined) return [];
  if (!Array.isArray(value) || value.length > 24) return null;
  const items = value.map((item) => requiredText(item, 500));
  return items.every((item): item is string => Boolean(item)) ? items : null;
}

function parseActions(
  value: unknown,
  bindingsValue: unknown,
): StructuredContentAction[] | null {
  const bindings = parseBindings(bindingsValue);
  if (bindings === null) return null;
  if (value === undefined) return bindings.size === 0 ? [] : null;
  if (!Array.isArray(value) || value.length > 8) return null;
  const actions: StructuredContentAction[] = [];
  for (const candidate of value) {
    const action = parseAction(candidate, bindings);
    if (!action) return null;
    actions.push(action);
  }
  const actionIds = new Set(actions.map((action) => action.actionId));
  if (actionIds.size !== actions.length) return null;
  if (bindings.size > 0 && (
    bindings.size !== actionIds.size
    || [...bindings.keys()].some((actionId) => !actionIds.has(actionId))
  )) {
    return null;
  }
  return actions;
}

function parseAction(
  value: unknown,
  bindings: ReadonlyMap<string, string>,
): StructuredContentAction | null {
  if (!isRecord(value)) return null;
  if (!hasOnlyKeys(value, ["id", "label", "style"])) return null;
  const actionId = requiredId(value.id);
  const label = requiredText(value.label, 128);
  const variant = value.style ?? "secondary";
  if (!actionId || !label || !new Set(["danger", "primary", "secondary"]).has(String(variant))) {
    return null;
  }
  return {
    actionId,
    bindingId: bindings.get(actionId) ?? null,
    label,
    variant: variant as "danger" | "primary" | "secondary",
  };
}

function parseBindings(value: unknown): ReadonlyMap<string, string> | null {
  if (value === undefined) return new Map();
  if (!isRecord(value) || Object.keys(value).length > 8) return null;
  const bindings = new Map<string, string>();
  for (const [actionId, bindingValue] of Object.entries(value)) {
    const validActionId = requiredId(actionId);
    const bindingId = requiredId(bindingValue);
    if (!validActionId || !bindingId) return null;
    bindings.set(validActionId, bindingId);
  }
  return bindings;
}

function containsForbiddenKey(value: unknown): boolean {
  const pending: Array<{ depth: number; value: unknown }> = [{ depth: 0, value }];
  let nodes = 0;
  while (pending.length > 0) {
    const current = pending.pop();
    if (!current || current.depth > 16 || (nodes += 1) > 4_096) return true;
    if (Array.isArray(current.value)) {
      for (const child of current.value) {
        pending.push({ depth: current.depth + 1, value: child });
      }
      continue;
    }
    if (!isRecord(current.value)) continue;
    for (const [key, child] of Object.entries(current.value)) {
      if (FORBIDDEN_KEYS.has(key.toLowerCase())) return true;
      pending.push({ depth: current.depth + 1, value: child });
    }
  }
  return false;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasOnlyKeys(value: Record<string, unknown>, allowed: string[]): boolean {
  const keys = new Set(allowed);
  return Object.keys(value).every((key) => keys.has(key));
}

function optionalText(value: unknown, maximum: number): string | null | undefined {
  return value === undefined ? undefined : requiredText(value, maximum);
}

function requiredText(value: unknown, maximum: number): string | null {
  if (typeof value !== "string") return null;
  const text = value.trim();
  return text.length > 0 && text.length <= maximum ? text : null;
}

function requiredId(value: unknown): string | null {
  return typeof value === "string" && ID_PATTERN.test(value) ? value : null;
}
