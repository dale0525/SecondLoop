export const SIDECAR_API_REQUEST_CHANNEL = "agentweave:sidecar-api:request";

export type SidecarApiOperation =
  | "actions.list"
  | "actions.resolve"
  | "attachments.delete"
  | "attachments.get"
  | "attachments.list"
  | "calendar.events.get"
  | "calendar.events.list"
  | "calendar.freeBusy"
  | "contacts.get"
  | "contacts.resolve"
  | "devSkills.delete"
  | "devSkills.list"
  | "devSkills.reload"
  | "devSkills.validate"
  | "mail.connect"
  | "mail.configuration.delete"
  | "mail.configuration.get"
  | "mail.configuration.list"
  | "mail.configuration.put"
  | "mail.disconnect"
  | "mail.list"
  | "mail.status"
  | "memory.export"
  | "memory.forget"
  | "memory.get"
  | "memory.list"
  | "notifications.cancel"
  | "notifications.enqueue"
  | "notifications.get"
  | "notifications.list"
  | "oauth.cancel"
  | "oauth.start"
  | "oauth.status"
  | "schedules.create"
  | "schedules.get"
  | "schedules.list"
  | "schedules.setStatus"
  | "sessions.create"
  | "sessions.delete"
  | "sessions.list"
  | "sessions.load"
  | "sessions.update"
  | "tasks.create"
  | "tasks.delete"
  | "tasks.get"
  | "tasks.list"
  | "tasks.setStatus"
  | "tasks.update"
  | "turns.cancel"
  | "turns.events";

export type FoundationTaskStatus = "open" | "completed" | "cancelled";

export type FoundationMailTlsMode = "implicit" | "start_tls" | "none";

export type FoundationMailConfigurationInput = Readonly<{
  id: string;
  displayName: string;
  primaryName?: string;
  primaryAddress: string;
  username: string;
  password: string;
  imapHost: string;
  imapPort: number;
  imapTls: FoundationMailTlsMode;
  smtpHost: string;
  smtpPort: number;
  smtpTls: FoundationMailTlsMode;
  archiveMailbox?: string;
  sentMailbox?: string;
  draftsMailbox?: string;
  trashMailbox?: string;
  allowInsecureLocalhost?: boolean;
}>;

export type FoundationMailConfiguration = Readonly<
  Omit<FoundationMailConfigurationInput, "password"> & {
    credentialConfigured: boolean;
  }
>;

export type FoundationTaskPriority = "low" | "normal" | "high" | "urgent";

export type FoundationTaskContent = Readonly<{
  title: string;
  notes?: string | null;
  dueAt?: string | null;
  timezone?: string | null;
  recurrence?: string | null;
  priority: FoundationTaskPriority;
  tags: readonly string[];
}>;

export type FoundationTaskRecord = Readonly<{
  id: string;
  content: FoundationTaskContent;
  status: FoundationTaskStatus;
  version: number;
  createdAt: string;
  updatedAt: string;
  completedAt?: string | null;
}>;

export type FoundationTaskPage = Readonly<{
  tasks: FoundationTaskRecord[];
  nextCursor: string | null;
}>;

export type FoundationTaskListInput = Readonly<{
  status?: FoundationTaskStatus;
  dueAfter?: string;
  dueBefore?: string;
  tag?: string;
  text?: string;
  limit?: number;
  cursor?: string;
}>;

export type FoundationScheduleStatus = "active" | "paused" | "completed" | "cancelled";

export type FoundationScheduleSpec =
  | Readonly<{ kind: "one_shot"; at: string }>
  | Readonly<{ kind: "interval"; anchor: string; every_seconds: number }>
  | Readonly<{ kind: "cron"; expression: string; timezone: string }>
  | Readonly<{ kind: "rrule"; rule: string; timezone: string; start: string }>;

export type FoundationMisfirePolicy =
  | Readonly<{ kind: "skip"; grace_seconds: number }>
  | Readonly<{ kind: "fire_once" }>
  | Readonly<{ kind: "catch_up"; max_runs: number }>;

export type FoundationScheduleRecord = Readonly<{
  id: string;
  request: {
    app_id: string;
    tenant_id: string;
    user_id: string;
    name: string;
    schedule: FoundationScheduleSpec;
    misfire: FoundationMisfirePolicy;
    payload: unknown;
  };
  status: FoundationScheduleStatus;
  next_run_at: string | null;
  version: number;
}>;

export type FoundationNotificationStatus =
  | "pending"
  | "delivering"
  | "delivered"
  | "failed"
  | "uncertain"
  | "cancelled";

export type FoundationQuietHours = Readonly<{
  timezone: string;
  startMinute: number;
  endMinute: number;
}>;

export type FoundationNotificationRecord = Readonly<{
  notification_id: string;
  request: {
    appId: string;
    tenantId: string;
    userId: string;
    channel: string;
    title: string;
    body: string;
    dedupeKey: string;
    notBefore: string;
    quietHours?: FoundationQuietHours | null;
    data: unknown;
  };
  status: FoundationNotificationStatus;
  attempt_count: number;
  delivery_id?: string | null;
  last_error?: string | null;
}>;

export type SidecarApiRequest = Readonly<{
  input?: unknown;
  operation: SidecarApiOperation;
}>;

export type OAuthAuthorizationStatus =
  | "cancelled"
  | "completed"
  | "denied"
  | "exchanging"
  | "expired"
  | "failed"
  | "preparing"
  | "pending";

export type OAuthAuthorizationSummary = Readonly<{
  authorizationId: string;
  expiresAt: string;
  providerId: string;
  status: OAuthAuthorizationStatus;
}>;

export type OAuthAuthorizationBinding = Readonly<{
  accountId: string;
  connectorId: string;
}>;

export type OAuthAuthorizationView = OAuthAuthorizationSummary & Readonly<{
  bindings: readonly OAuthAuthorizationBinding[];
  connectorIds: readonly string[];
  createdAt: string;
  errorCode: string | null;
  requestedCapabilities: readonly string[];
  updatedAt: string;
}>;

export type FoundationCalendarAttendee = Readonly<{
  address: string;
  displayName: string | null;
  response: string;
}>;

export type FoundationCalendarEventContent = Readonly<{
  attendees: readonly FoundationCalendarAttendee[];
  calendarId: string;
  description: string | null;
  end: string;
  location: string | null;
  recurrence: string | null;
  start: string;
  timezone: string;
  title: string;
}>;

export type FoundationCalendarEvent = Readonly<{
  content: FoundationCalendarEventContent;
  id: string;
  providerId: string | null;
  status: "cancelled" | "confirmed";
  updatedAt: string;
  version: number;
}>;

export type FoundationBusyInterval = Readonly<{
  end: string;
  eventId: string | null;
  start: string;
}>;

export type FoundationContactIdentity = Readonly<{
  kind: string;
  label: string | null;
  value: string;
}>;

export type FoundationContactRecord = Readonly<{
  displayName: string;
  id: string;
  identities: readonly FoundationContactIdentity[];
  organization: string | null;
  providerId: string | null;
  relationship: string | null;
  updatedAt: string;
  version: number;
}>;

export type FoundationCalendarMutationPreview = Readonly<{
  accountId: string;
  attendeeVisible: boolean;
  conflicts: readonly FoundationBusyInterval[];
  content: FoundationCalendarEventContent | null;
  eventId: string | null;
  expectedVersion: number | null;
  idempotencyKey: string;
  kind: "cancel" | "create" | "update";
  previewHash: string;
  previewId: string;
}>;

export type FoundationContactMutationPreview = Readonly<{
  accountId: string;
  contactId: string;
  expectedVersion: number;
  idempotencyKey: string;
  previewHash: string;
  previewId: string;
  replacement: FoundationContactRecord;
}>;
