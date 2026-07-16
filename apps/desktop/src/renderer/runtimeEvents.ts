export type StructuredContentAudience = "user" | "owner" | "developer";

export type StructuredContent = {
  audience: StructuredContentAudience;
  content_id: string;
  fallback_text: string;
  mime_type: string;
  owner: string;
  payload: unknown;
  revision: number;
  schema_version: string;
};

export type RuntimeEvent = {
  arguments?: unknown;
  call_id?: string;
  content?: StructuredContent;
  content_id?: string;
  message?: string;
  name?: string;
  owner?: string;
  receipt?: unknown;
  result?: unknown;
  result_metadata?: unknown;
  revision?: number;
  text?: string;
  turn_id?: string;
  type: string;
};
