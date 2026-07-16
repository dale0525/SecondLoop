import type {
  FoundationBusyInterval,
  FoundationCalendarEvent,
  FoundationContactRecord,
  OAuthAuthorizationSummary,
  OAuthAuthorizationView,
} from "../shared/sidecarApi";
import { requestServer } from "./trustedServerRequest";

export type {
  FoundationBusyInterval,
  FoundationCalendarAttendee,
  FoundationCalendarEvent,
  FoundationCalendarEventContent,
  FoundationContactIdentity,
  FoundationContactRecord,
  OAuthAuthorizationBinding,
  OAuthAuthorizationStatus,
  OAuthAuthorizationSummary,
  OAuthAuthorizationView,
} from "../shared/sidecarApi";

export async function listFoundationCalendarEvents(
  accountId: string,
  start: string,
  end: string,
): Promise<FoundationCalendarEvent[]> {
  const input = { accountId, end, start };
  return requestServer(
    "calendar.events.list",
    input,
    `/foundation/calendar/events?${new URLSearchParams(input)}`,
    { method: "GET" },
  );
}

export async function getFoundationCalendarEvent(
  accountId: string,
  eventId: string,
): Promise<FoundationCalendarEvent | null> {
  return requestServer(
    "calendar.events.get",
    { accountId, eventId },
    `/foundation/calendar/events/${encodeURIComponent(eventId)}?${new URLSearchParams({ accountId })}`,
    { method: "GET" },
  );
}

export async function getFoundationCalendarFreeBusy(
  accountId: string,
  start: string,
  end: string,
): Promise<FoundationBusyInterval[]> {
  const input = { accountId, end, start };
  return requestServer(
    "calendar.freeBusy",
    input,
    `/foundation/calendar/free-busy?${new URLSearchParams(input)}`,
    { method: "GET" },
  );
}

export async function resolveFoundationContacts(
  accountId: string,
  query: string,
  limit = 10,
): Promise<FoundationContactRecord[]> {
  const input = { accountId, limit, query };
  return requestServer(
    "contacts.resolve",
    input,
    `/foundation/contacts?${new URLSearchParams({
      accountId,
      query,
      limit: String(limit),
    })}`,
    { method: "GET" },
  );
}

export async function getFoundationContact(
  accountId: string,
  contactId: string,
): Promise<FoundationContactRecord | null> {
  return requestServer(
    "contacts.get",
    { accountId, contactId },
    `/foundation/contacts/${encodeURIComponent(contactId)}?${new URLSearchParams({ accountId })}`,
    { method: "GET" },
  );
}

export async function startWorkspaceOAuth(input: {
  connectorIds: readonly string[];
  providerId: string;
  requestedCapabilities: readonly string[];
}): Promise<OAuthAuthorizationSummary> {
  return requestServer("oauth.start", input, "/host/oauth/authorizations", {
    body: JSON.stringify(input),
    method: "POST",
  });
}

export async function getWorkspaceOAuthStatus(
  authorizationId: string,
): Promise<OAuthAuthorizationView> {
  return requestServer(
    "oauth.status",
    { authorizationId },
    `/host/oauth/authorizations/${encodeURIComponent(authorizationId)}`,
    { method: "GET" },
  );
}

export async function cancelWorkspaceOAuth(
  authorizationId: string,
): Promise<OAuthAuthorizationView> {
  return requestServer(
    "oauth.cancel",
    { authorizationId },
    `/host/oauth/authorizations/${encodeURIComponent(authorizationId)}`,
    { method: "DELETE" },
  );
}
