import type {
  MailSendPreview,
  PendingFoundationAction,
} from "./api";
import type {
  FoundationCalendarMutationPreview,
  FoundationContactMutationPreview,
} from "../shared/sidecarApi";

export type ClassifiedFoundationAction =
  | Readonly<{ kind: "calendar"; preview: FoundationCalendarMutationPreview }>
  | Readonly<{ kind: "contacts"; preview: FoundationContactMutationPreview }>
  | Readonly<{ kind: "mail"; preview: MailSendPreview }>
  | Readonly<{ kind: "unknown"; preview: null }>;

export function classifyFoundationAction(
  item: PendingFoundationAction,
): ClassifiedFoundationAction {
  const actionName = item.approval.binding.action_name;
  if ((actionName === "mail.send" || actionName === "mail_send") && isMailPreview(item.preview)) {
    return { kind: "mail", preview: item.preview };
  }
  if (
    calendarKind(actionName) !== null
    && isCalendarPreview(item.preview)
    && item.preview.kind === calendarKind(actionName)
  ) {
    return { kind: "calendar", preview: item.preview };
  }
  if (actionName === "contacts.contact.update" && isContactPreview(item.preview)) {
    return { kind: "contacts", preview: item.preview };
  }
  return { kind: "unknown", preview: null };
}

export function foundationActionTitle(item: PendingFoundationAction): string {
  const classified = classifyFoundationAction(item);
  switch (classified.kind) {
    case "mail":
      return classified.preview.subject;
    case "calendar":
      return classified.preview.content?.title
        ?? classified.preview.eventId
        ?? item.approval.binding.resource_target;
    case "contacts":
      return classified.preview.replacement.displayName;
    case "unknown":
      return item.approval.binding.action_name;
  }
}

function calendarKind(actionName: string): "cancel" | "create" | "update" | null {
  if (actionName === "calendar.event.cancel") return "cancel";
  if (actionName === "calendar.event.create") return "create";
  if (actionName === "calendar.event.update") return "update";
  return null;
}

function isMailPreview(value: unknown): value is MailSendPreview {
  return isRecord(value)
    && typeof value.accountId === "string"
    && typeof value.subject === "string"
    && isRecord(value.from)
    && Array.isArray(value.to)
    && Array.isArray(value.cc)
    && Array.isArray(value.bcc)
    && Array.isArray(value.attachments)
    && typeof value.draftRevision === "number"
    && typeof value.previewHash === "string";
}

function isCalendarPreview(value: unknown): value is FoundationCalendarMutationPreview {
  return isRecord(value)
    && typeof value.accountId === "string"
    && ["cancel", "create", "update"].includes(String(value.kind))
    && (value.content === null || isRecord(value.content))
    && (value.eventId === null || typeof value.eventId === "string")
    && (value.expectedVersion === null || typeof value.expectedVersion === "number")
    && Array.isArray(value.conflicts)
    && typeof value.attendeeVisible === "boolean"
    && typeof value.previewHash === "string";
}

function isContactPreview(value: unknown): value is FoundationContactMutationPreview {
  return isRecord(value)
    && typeof value.accountId === "string"
    && typeof value.contactId === "string"
    && typeof value.expectedVersion === "number"
    && isRecord(value.replacement)
    && typeof value.replacement.displayName === "string"
    && Array.isArray(value.replacement.identities)
    && typeof value.previewHash === "string";
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
