import { ModelSettings } from "./types";
import type { RuntimeEvent } from "./runtimeEvents";
import type { AttachmentMetadata } from "../shared/attachments";
import type {
  BackupExportReceipt,
  BackupRestoreReceipt,
  DataProtectionStatus,
} from "../shared/dataProtection";
import type {
  FoundationMisfirePolicy,
  FoundationNotificationRecord,
  FoundationNotificationStatus,
  FoundationQuietHours,
  FoundationScheduleRecord,
  FoundationScheduleSpec,
  FoundationScheduleStatus,
  FoundationTaskContent,
  FoundationTaskListInput,
  FoundationTaskPage,
  FoundationTaskRecord,
  FoundationTaskStatus,
} from "../shared/sidecarApi";
import { requestDevelopmentJson, requestServer } from "./trustedServerRequest";

export type {
  FoundationMisfirePolicy,
  FoundationNotificationRecord,
  FoundationNotificationStatus,
  FoundationQuietHours,
  FoundationScheduleRecord,
  FoundationScheduleSpec,
  FoundationScheduleStatus,
  FoundationTaskContent,
  FoundationTaskListInput,
  FoundationTaskPage,
  FoundationTaskPriority,
  FoundationTaskRecord,
  FoundationTaskStatus,
} from "../shared/sidecarApi";

export type { AttachmentMetadata } from "../shared/attachments";
export type {
  BackupExportReceipt,
  BackupRestoreReceipt,
  DataProtectionStatus,
} from "../shared/dataProtection";

export type ServerSession = {
  created_at: string;
  id: string;
  title: string;
  updated_at: string;
};

export type ServerSessionPage = {
  items: ServerSession[];
  nextCursor: string | null;
};

export type ServerConversationEvent = {
  created_at: string;
  event_index: number;
  id: string;
  kind: string;
  payload: RuntimeEvent;
  session_id: string;
  turn_id?: string;
};

export type ServerTurnStatus =
  | "running"
  | "completed"
  | "failed"
  | "cancelled"
  | "interrupted";

export type ServerTurn = {
  assistant_message_id: string | null;
  failure_message: string | null;
  finished_at: string | null;
  id: string;
  request_id: string;
  session_id: string;
  started_at: string;
  status: ServerTurnStatus;
  updated_at: string;
  user_message_id: string;
};

export type ServerSessionDetail = {
  events: ServerConversationEvent[];
  messages: ServerMessage[];
  session: ServerSession;
  turns: ServerTurn[];
};

export type StartTurnResponse = {
  reused: boolean;
  turn: ServerTurn;
  userMessage: ServerMessage;
};

export type TurnEventsResponse = {
  events: ServerConversationEvent[];
  hasMore: boolean;
  nextCursor: number;
  turn: ServerTurn;
};

export type SessionEventsResponse = {
  events: ServerConversationEvent[];
  hasMore: boolean;
  nextCursor: number;
};

export type CancelTurnResponse = {
  accepted: boolean;
  turn: ServerTurn;
};

export type {
  RuntimeEvent,
  StructuredContent,
  StructuredContentAudience,
} from "./runtimeEvents";

export type ServerMessage = {
  id: string;
  session_id: string;
  role: string;
  content: string;
  created_at: string;
};

export type PostMessageResponse = {
  accepted: boolean;
  user_message?: ServerMessage;
  assistant_message?: ServerMessage;
  events?: RuntimeEvent[];
};

export type ModelConnectionTestResponse = {
  ok: boolean;
  message: string;
};

export type MemoryEvidence = {
  source: string;
  sourceId?: string | null;
  excerpt?: string | null;
  observedAt: string;
};

export type MemoryRecord = {
  schemaVersion: number;
  id: string;
  kind: string;
  value: { text: string; attributes: Record<string, string> };
  evidence: MemoryEvidence[];
  confidence: number;
  sensitivity: string;
  retention: { mode: string; expiresAt?: string; sessionId?: string };
  state: "proposed" | "committed" | "tombstoned";
  version: number;
  conflictKey?: string | null;
  supersedes?: string | null;
  supersededBy?: string | null;
  createdAt: string;
  updatedAt: string;
};

export type MemoryExport = {
  schemaVersion: number;
  exportedAt: string;
  records: MemoryRecord[];
};

export type MailAddress = {
  name?: string | null;
  address: string;
};

export type MailAccount = {
  id: string;
  displayName: string;
  primaryAddress: MailAddress;
  addresses: MailAddress[];
};

export type MailAccountStatus = {
  account: MailAccount;
  state: "connected" | "authentication_required" | "unavailable";
  detail?: string | null;
};

export type FoundationApproval = {
  approval_id: string;
  binding: {
    action_name: string;
    arguments_sha256: string;
    expires_at: string;
    resource_target: string;
    risk: string;
    risk_summary: string;
  };
  status: "pending" | "approved" | "rejected" | "cancelled" | "expired" | "consumed";
};

export type FoundationAction = {
  action_id: string;
  action_name: string;
  arguments_sha256: string;
  idempotency_key: string;
  last_error?: string | null;
  resource_target: string;
  result?: unknown;
  status: "pending" | "waiting_approval" | "ready" | "executing" | "succeeded" | "failed" | "cancelled" | "uncertain";
};

export type MailSendPreview = {
  id: string;
  accountId: string;
  draftId: string;
  draftRevision: number;
  from: MailAddress;
  to: MailAddress[];
  cc: MailAddress[];
  bcc: MailAddress[];
  subject: string;
  bodySha256: string;
  attachments: Array<{ fileName: string; mimeType: string; sizeBytes: number }>;
  previewHash: string;
};

export type PendingFoundationAction = {
  approval: FoundationApproval;
  action: FoundationAction;
  preview?: MailSendPreview | null;
};

export type FoundationActionResolution = {
  approval: FoundationApproval;
  action: FoundationAction;
  connectorResult?: unknown;
};

export type OwnerSkillValidation = {
  ok: boolean;
  errors: string[];
  warnings: string[];
  requiredTools?: string[];
  requiredConnectors?: string[];
  dependencies?: string[];
  requiredCapabilities?: string[];
  permissionDiff?: unknown;
  revisionId?: string;
  snapshotGeneration?: number;
};

export type OwnerSkillRequirements = {
  runtime_tools: string[];
  capabilities: string[];
  connectors: string[];
  packages: string[];
};

export type OwnerSkillRevision = {
  revision_id: string;
  version: string;
  status: string;
  editable: boolean;
  created_by: string;
  created_at: string;
  kind: string;
  instructions: string;
  validation: OwnerSkillValidation;
  requirements: OwnerSkillRequirements;
  permission_diff?: unknown;
};

export type OwnerSkillPackageSummary = {
  package_id: string;
  display_name: string;
  version: string;
  source_layer: string;
  status: string;
  reason: string;
  active_revision_id: string | null;
  available: boolean;
  content_hash: string | null;
  manageable: boolean;
};

export type OwnerSkillActionFacts = {
  can_edit_draft: boolean;
  can_validate_draft: boolean;
  can_request_activation: boolean;
  can_disable: boolean;
  can_request_removal: boolean;
  can_rollback: boolean;
};

export type OwnerLayeredSkill = {
  package_id: string;
  effective: OwnerSkillPackageSummary | null;
  managed: OwnerSkillPackageSummary | null;
  built_in_collision: boolean;
  actions: OwnerSkillActionFacts;
};

export type OwnerSkillPackage = Omit<
  OwnerSkillPackageSummary,
  "available" | "content_hash" | "manageable"
> & {
  display_name: string;
  effective: OwnerSkillPackageSummary | null;
  managed: OwnerSkillPackageSummary | null;
  built_in_collision: boolean;
  actions: OwnerSkillActionFacts;
  revisions: OwnerSkillRevision[];
  editable_draft: OwnerSkillRevision | null;
};

export type OwnerSkillInventory = {
  effective: OwnerSkillPackageSummary[];
  managed: OwnerSkillPackageSummary[];
  packages: OwnerLayeredSkill[];
};

export type OwnerSkillDraftSummary = {
  package_id: string;
  revision_id: string;
  version: string;
  kind: string;
  validation: unknown;
  status: string;
};

export type OwnerSkillApproval = {
  approval_id: string;
  operation?: "activation" | "removal" | "rollback";
  package_id: string;
  permission_diff: unknown;
  requested_by: string;
  revision_id: string;
  status: string;
};

export type OwnerSkillMutationReport = {
  status?: string;
  active_generation?: number;
  active_revision_id?: string;
  generation?: number;
};

export type {
  DevSkillInventory,
  DevSkillMutationResponse,
  DevSkillPackage,
  DevSkillPackageKind,
  DevSkillReloadResponse,
  DevSkillSource,
  DevSkillValidation,
} from "./devSkillsApi";

export async function createServerSession(title: string): Promise<ServerSession> {
  return requestServer<ServerSession>("sessions.create", { title }, "/sessions", {
    body: JSON.stringify({ title }),
    method: "POST"
  });
}

export async function listServerSessions(
  cursor?: string,
  limit = 50,
): Promise<ServerSessionPage> {
  const params = new URLSearchParams({ limit: String(limit) });
  if (cursor) params.set("cursor", cursor);
  return requestServer<ServerSessionPage>(
    "sessions.list",
    { cursor, limit },
    `/sessions?${params}`,
    { method: "GET" },
  );
}

export async function loadServerSession(id: string): Promise<ServerSessionDetail> {
  return requestServer<ServerSessionDetail>(
    "sessions.load",
    { id },
    `/sessions/${encodeURIComponent(id)}`,
    { method: "GET" },
  );
}

export async function updateServerSession(
  session: ServerSession,
  title: string,
): Promise<ServerSession> {
  return requestServer<ServerSession>(
    "sessions.update",
    { expectedUpdatedAt: session.updated_at, id: session.id, title },
    `/sessions/${encodeURIComponent(session.id)}`,
    {
      body: JSON.stringify({ expectedUpdatedAt: session.updated_at, title }),
      method: "PATCH",
    },
  );
}

export async function deleteServerSession(session: ServerSession): Promise<unknown> {
  const params = new URLSearchParams({ expectedUpdatedAt: session.updated_at });
  return requestServer(
    "sessions.delete",
    { expectedUpdatedAt: session.updated_at, id: session.id },
    `/sessions/${encodeURIComponent(session.id)}?${params}`,
    { method: "DELETE" },
  );
}

export async function postSessionMessage(
  sessionId: string,
  content: string,
  modelSettings?: ModelSettings | null
): Promise<PostMessageResponse> {
  const secureBridge = window.agentWeave?.modelSettings;
  if (secureBridge) {
    return secureBridge.postSessionMessage(sessionId, content) as Promise<PostMessageResponse>;
  }
  return requestDevelopmentJson<PostMessageResponse>(`/sessions/${sessionId}/messages`, {
    body: JSON.stringify({
      content,
      ...(modelSettings ? { modelSettings } : {})
    }),
    method: "POST"
  });
}

export async function startSessionTurn(
  sessionId: string,
  requestId: string,
  content: string,
  modelSettings?: ModelSettings | null,
): Promise<StartTurnResponse> {
  const secureBridge = window.agentWeave?.modelSettings;
  if (secureBridge?.startSessionTurn) {
    return secureBridge.startSessionTurn(
      sessionId,
      requestId,
      content,
    ) as Promise<StartTurnResponse>;
  }
  return requestDevelopmentJson<StartTurnResponse>(
    `/sessions/${encodeURIComponent(sessionId)}/turns`,
    {
      body: JSON.stringify({
        content,
        requestId,
        ...(modelSettings ? { modelSettings } : {}),
      }),
      method: "POST",
    },
  );
}

export async function listServerTurnEvents(
  sessionId: string,
  turnId: string,
  after = -1,
  waitMs = 20_000,
): Promise<TurnEventsResponse> {
  const params = new URLSearchParams({
    after: String(after),
    limit: "100",
    waitMs: String(waitMs),
  });
  return requestServer<TurnEventsResponse>(
    "turns.events",
    { after, limit: 100, sessionId, turnId, waitMs },
    `/sessions/${encodeURIComponent(sessionId)}/turns/${encodeURIComponent(turnId)}/events?${params}`,
    { method: "GET" },
  );
}

export async function listServerSessionEvents(
  sessionId: string,
  after = -1,
  waitMs = 20_000,
): Promise<SessionEventsResponse> {
  const params = new URLSearchParams({
    after: String(after),
    limit: "100",
    waitMs: String(waitMs),
  });
  return requestServer<SessionEventsResponse>(
    "sessions.events",
    { after, limit: 100, sessionId, waitMs },
    `/sessions/${encodeURIComponent(sessionId)}/events?${params}`,
    { method: "GET" },
  );
}

export async function cancelServerTurn(
  sessionId: string,
  turnId: string,
): Promise<CancelTurnResponse> {
  return requestServer<CancelTurnResponse>(
    "turns.cancel",
    { sessionId, turnId },
    `/sessions/${encodeURIComponent(sessionId)}/turns/${encodeURIComponent(turnId)}/cancel`,
    { method: "POST" },
  );
}

export async function testModelConnection(
  settings: ModelSettings
): Promise<ModelConnectionTestResponse> {
  const secureBridge = window.agentWeave?.modelSettings;
  if (secureBridge) {
    return secureBridge.testConnection() as Promise<ModelConnectionTestResponse>;
  }
  return requestDevelopmentJson<ModelConnectionTestResponse>("/model/test", {
    body: JSON.stringify(settings),
    method: "POST"
  });
}

export async function listMemories(query = "", limit = 50): Promise<MemoryRecord[]> {
  const params = new URLSearchParams({ query, limit: String(limit) });
  return requestServer<MemoryRecord[]>(
    "memory.list",
    { limit, query },
    `/foundation/memory?${params}`,
    { method: "GET" },
  );
}

export async function getMemory(id: string): Promise<MemoryRecord> {
  return requestServer<MemoryRecord>("memory.get", { id }, `/foundation/memory/${encodeURIComponent(id)}`, {
    method: "GET"
  });
}

export async function forgetMemory(id: string, expectedVersion: number): Promise<unknown> {
  return requestServer("memory.forget", { expectedVersion, id }, `/foundation/memory/${encodeURIComponent(id)}`, {
    body: JSON.stringify({ expectedVersion }),
    method: "DELETE"
  });
}

export async function exportMemories(): Promise<MemoryExport> {
  return requestServer<MemoryExport>("memory.export", undefined, "/foundation/memory/export", { method: "GET" });
}

export async function listAttachments(limit = 25): Promise<AttachmentMetadata[]> {
  return requestServer<AttachmentMetadata[]>(
    "attachments.list",
    { limit },
    `/foundation/attachments?${new URLSearchParams({ limit: String(limit) })}`,
    { method: "GET" },
  );
}

export async function getAttachment(id: string): Promise<AttachmentMetadata> {
  return requestServer<AttachmentMetadata>(
    "attachments.get",
    { id },
    `/foundation/attachments/${encodeURIComponent(id)}`,
    { method: "GET" },
  );
}

export async function deleteAttachment(id: string): Promise<unknown> {
  return requestServer(
    "attachments.delete",
    { id },
    `/foundation/attachments/${encodeURIComponent(id)}`,
    { method: "DELETE" },
  );
}

export async function pickAndImportAttachment(): Promise<AttachmentMetadata | null> {
  const bridge = window.agentWeave?.attachments;
  if (!bridge) throw new Error("Trusted attachment import is unavailable");
  return bridge.pickAndImport();
}

export async function getDataProtectionStatus(): Promise<DataProtectionStatus> {
  const bridge = window.agentWeave?.dataProtection;
  if (!bridge) throw new Error("Trusted data protection is unavailable");
  return bridge.status();
}

export async function exportEncryptedBackup(): Promise<BackupExportReceipt | null> {
  const bridge = window.agentWeave?.dataProtection;
  if (!bridge) throw new Error("Trusted data protection is unavailable");
  return bridge.exportBackup();
}

export async function restoreEncryptedBackup(): Promise<BackupRestoreReceipt | null> {
  const bridge = window.agentWeave?.dataProtection;
  if (!bridge) throw new Error("Trusted data protection is unavailable");
  return bridge.restoreBackup();
}

export async function listFoundationTasks(
  input: FoundationTaskListInput = {},
): Promise<FoundationTaskPage> {
  const params = new URLSearchParams({ limit: String(input.limit ?? 50) });
  if (input.status) params.set("status", input.status);
  if (input.dueAfter) params.set("dueAfter", input.dueAfter);
  if (input.dueBefore) params.set("dueBefore", input.dueBefore);
  if (input.tag) params.set("tag", input.tag);
  if (input.text) params.set("text", input.text);
  if (input.cursor) params.set("cursor", input.cursor);
  return requestServer<FoundationTaskPage>(
    "tasks.list",
    input,
    `/foundation/tasks?${params}`,
    { method: "GET" },
  );
}

export async function getFoundationTask(id: string): Promise<FoundationTaskRecord> {
  return requestServer<FoundationTaskRecord>(
    "tasks.get",
    { id },
    `/foundation/tasks/${encodeURIComponent(id)}`,
    { method: "GET" },
  );
}

export async function createFoundationTask(
  content: FoundationTaskContent,
  idempotencyKey: string,
): Promise<FoundationTaskRecord> {
  const input = { content, idempotencyKey };
  return requestServer<FoundationTaskRecord>("tasks.create", input, "/foundation/tasks", {
    body: JSON.stringify(input),
    method: "POST",
  });
}

export async function updateFoundationTask(
  id: string,
  expectedVersion: number,
  content: FoundationTaskContent,
): Promise<FoundationTaskRecord> {
  const input = { content, expectedVersion, id };
  return requestServer<FoundationTaskRecord>(
    "tasks.update",
    input,
    `/foundation/tasks/${encodeURIComponent(id)}`,
    {
      body: JSON.stringify({ content, expectedVersion }),
      method: "PATCH",
    },
  );
}

export async function setFoundationTaskStatus(
  id: string,
  expectedVersion: number,
  status: FoundationTaskStatus,
): Promise<FoundationTaskRecord> {
  const input = { expectedVersion, id, status };
  return requestServer<FoundationTaskRecord>(
    "tasks.setStatus",
    input,
    `/foundation/tasks/${encodeURIComponent(id)}/status`,
    {
      body: JSON.stringify({ expectedVersion, status }),
      method: "POST",
    },
  );
}

export async function deleteFoundationTask(
  id: string,
  expectedVersion: number,
): Promise<unknown> {
  return requestServer(
    "tasks.delete",
    { expectedVersion, id },
    `/foundation/tasks/${encodeURIComponent(id)}`,
    {
      body: JSON.stringify({ expectedVersion }),
      method: "DELETE",
    },
  );
}

export async function listFoundationSchedules(limit = 25): Promise<FoundationScheduleRecord[]> {
  return requestServer<FoundationScheduleRecord[]>(
    "schedules.list",
    { limit },
    `/foundation/schedules?${new URLSearchParams({ limit: String(limit) })}`,
    { method: "GET" },
  );
}

export async function getFoundationSchedule(id: string): Promise<FoundationScheduleRecord> {
  return requestServer<FoundationScheduleRecord>(
    "schedules.get",
    { id },
    `/foundation/schedules/${encodeURIComponent(id)}`,
    { method: "GET" },
  );
}

export async function createFoundationSchedule(input: {
  name: string;
  schedule: FoundationScheduleSpec;
  misfire: FoundationMisfirePolicy;
  payload?: unknown;
  idempotencyKey: string;
}): Promise<FoundationScheduleRecord> {
  return requestServer<FoundationScheduleRecord>("schedules.create", input, "/foundation/schedules", {
    body: JSON.stringify(input),
    method: "POST",
  });
}

export async function setFoundationScheduleStatus(
  id: string,
  expectedVersion: number,
  status: FoundationScheduleStatus,
): Promise<FoundationScheduleRecord> {
  const input = { expectedVersion, id, status };
  return requestServer<FoundationScheduleRecord>(
    "schedules.setStatus",
    input,
    `/foundation/schedules/${encodeURIComponent(id)}`,
    { body: JSON.stringify({ expectedVersion, status }), method: "POST" },
  );
}

export async function listFoundationNotifications(
  status?: FoundationNotificationStatus,
  limit = 25,
): Promise<FoundationNotificationRecord[]> {
  const params = new URLSearchParams({ limit: String(limit) });
  if (status) params.set("status", status);
  return requestServer<FoundationNotificationRecord[]>(
    "notifications.list",
    { limit, ...(status ? { status } : {}) },
    `/foundation/notifications?${params}`,
    { method: "GET" },
  );
}

export async function getFoundationNotification(id: string): Promise<FoundationNotificationRecord> {
  return requestServer<FoundationNotificationRecord>(
    "notifications.get",
    { id },
    `/foundation/notifications/${encodeURIComponent(id)}`,
    { method: "GET" },
  );
}

export async function enqueueFoundationNotification(input: {
  channel: string;
  title: string;
  body: string;
  dedupeKey: string;
  notBefore: string;
  quietHours?: FoundationQuietHours | null;
  data?: unknown;
}): Promise<FoundationNotificationRecord> {
  return requestServer<FoundationNotificationRecord>(
    "notifications.enqueue",
    input,
    "/foundation/notifications",
    { body: JSON.stringify(input), method: "POST" },
  );
}

export async function cancelFoundationNotification(
  id: string,
): Promise<FoundationNotificationRecord> {
  return requestServer<FoundationNotificationRecord>(
    "notifications.cancel",
    { id },
    `/foundation/notifications/${encodeURIComponent(id)}/cancel`,
    { body: "{}", method: "POST" },
  );
}

export async function listMailAccounts(): Promise<MailAccount[]> {
  return requestServer<MailAccount[]>("mail.list", undefined, "/foundation/mail/accounts", { method: "GET" });
}

export async function getMailAccountStatus(id: string): Promise<MailAccountStatus> {
  return requestServer<MailAccountStatus>(
    "mail.status",
    { id },
    `/foundation/mail/accounts/${encodeURIComponent(id)}`,
    { method: "GET" }
  );
}

export async function connectMailAccount(id: string): Promise<MailAccountStatus> {
  return requestServer<MailAccountStatus>(
    "mail.connect",
    { id },
    `/foundation/mail/accounts/${encodeURIComponent(id)}`,
    { method: "POST" }
  );
}

export async function disconnectMailAccount(id: string): Promise<MailAccountStatus> {
  return requestServer<MailAccountStatus>(
    "mail.disconnect",
    { id },
    `/foundation/mail/accounts/${encodeURIComponent(id)}`,
    { method: "DELETE" }
  );
}

export async function listFoundationActions(): Promise<PendingFoundationAction[]> {
  return requestServer<PendingFoundationAction[]>(
    "actions.list",
    undefined,
    "/foundation/actions",
    { method: "GET" },
  );
}

export async function resolveFoundationAction(
  approvalId: string,
  decision: "approve_once" | "reject"
): Promise<FoundationActionResolution> {
  return requestServer<FoundationActionResolution>(
    "actions.resolve",
    { approvalId, decision },
    `/foundation/actions/${encodeURIComponent(approvalId)}`,
    {
      body: JSON.stringify({ decision }),
      method: "POST"
    }
  );
}

export {
  createDevSkill,
  deleteDevSkill,
  listDevSkills,
  readDevSkill,
  reloadDevSkills,
  updateDevSkill,
  validateDevSkills,
} from "./devSkillsApi";

export async function acceptStructuredAction(
  sessionId: string,
  bindingId: string,
  input: Record<string, unknown> = {},
): Promise<unknown> {
  return requestServer(
    "structuredActions.accept",
    { bindingId, input, sessionId },
    `/sessions/${encodeURIComponent(sessionId)}/structured-actions/${encodeURIComponent(bindingId)}/accept`,
    { body: JSON.stringify({ input }), method: "POST" },
  );
}

export function extractAssistantText(response: PostMessageResponse): string {
  const finished = response.events?.find(
    (event) =>
      event.type === "assistant_message_finished" && typeof event.text === "string"
  );
  if (finished?.text) {
    return finished.text;
  }

  const deltaText = response.events
    ?.filter(
      (event) => event.type === "assistant_text_delta" && typeof event.text === "string"
    )
    .map((event) => event.text)
    .join("");
  if (deltaText) {
    return deltaText;
  }

  return response.assistant_message?.content ?? "";
}
