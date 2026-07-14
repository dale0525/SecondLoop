export const SIDECAR_API_REQUEST_CHANNEL = "agentweave:sidecar-api:request";

export type SidecarApiOperation =
  | "actions.list"
  | "actions.resolve"
  | "devSkills.delete"
  | "devSkills.list"
  | "devSkills.reload"
  | "devSkills.validate"
  | "mail.connect"
  | "mail.disconnect"
  | "mail.list"
  | "mail.status"
  | "memory.export"
  | "memory.forget"
  | "memory.get"
  | "memory.list"
  | "sessions.create"
  | "sessions.delete"
  | "sessions.list"
  | "sessions.load"
  | "sessions.update"
  | "turns.cancel"
  | "turns.events";

export type SidecarApiRequest = Readonly<{
  input?: unknown;
  operation: SidecarApiOperation;
}>;
