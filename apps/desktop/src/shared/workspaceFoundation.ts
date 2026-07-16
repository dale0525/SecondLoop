import type {
  FoundationBusyInterval,
  FoundationCalendarAttendee,
  FoundationCalendarEvent,
  FoundationCalendarEventContent,
  FoundationContactIdentity,
  FoundationContactRecord,
  SidecarApiOperation,
} from "./sidecarApi";

const RFC3339 = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/;
const SAFE_ACCOUNT_ID = /^[A-Za-z0-9._-]+$/;

export type WorkspaceReadOperation = Extract<
  SidecarApiOperation,
  | "calendar.events.get"
  | "calendar.events.list"
  | "calendar.freeBusy"
  | "contacts.get"
  | "contacts.resolve"
>;

export function describeWorkspaceRead(
  operation: WorkspaceReadOperation,
  value: unknown,
): { method: "GET"; pathname: string } {
  switch (operation) {
    case "calendar.events.list":
    case "calendar.freeBusy": {
      const input = exactRecord(value, ["accountId", "end", "start"]);
      const accountId = accountIdentifier(input, "accountId");
      const start = timestamp(input, "start");
      const end = timestamp(input, "end");
      if (Date.parse(end) <= Date.parse(start)) throw new Error("Calendar range is invalid");
      const path = operation === "calendar.events.list"
        ? "/foundation/calendar/events"
        : "/foundation/calendar/free-busy";
      return get(`${path}?${new URLSearchParams({ accountId, start, end })}`);
    }
    case "calendar.events.get": {
      const input = exactRecord(value, ["accountId", "eventId"]);
      const accountId = accountIdentifier(input, "accountId");
      const eventId = pathIdentifier(input, "eventId");
      return get(`/foundation/calendar/events/${eventId}?${new URLSearchParams({ accountId })}`);
    }
    case "contacts.resolve": {
      const input = exactRecord(value, ["accountId", "limit", "query"]);
      const accountId = accountIdentifier(input, "accountId");
      const query = text(input, "query", 1_024);
      const limit = integer(input, "limit", 1, 50);
      return get(`/foundation/contacts?${new URLSearchParams({
        accountId,
        query,
        limit: String(limit),
      })}`);
    }
    case "contacts.get": {
      const input = exactRecord(value, ["accountId", "contactId"]);
      const accountId = accountIdentifier(input, "accountId");
      const contactId = pathIdentifier(input, "contactId");
      return get(`/foundation/contacts/${contactId}?${new URLSearchParams({ accountId })}`);
    }
  }
}

export function parseWorkspaceReadResponse(
  operation: WorkspaceReadOperation,
  value: unknown,
): unknown {
  switch (operation) {
    case "calendar.events.list":
      return array(value, 2_000, parseCalendarEvent, "Calendar events");
    case "calendar.events.get":
      return value === null ? null : parseCalendarEvent(value);
    case "calendar.freeBusy":
      return array(value, 2_000, parseBusyInterval, "Calendar free/busy");
    case "contacts.resolve":
      return array(value, 50, parseContactRecord, "Contacts");
    case "contacts.get":
      return value === null ? null : parseContactRecord(value);
  }
}

function parseCalendarEvent(value: unknown): FoundationCalendarEvent {
  const event = exactRecord(value, ["content", "id", "providerId", "status", "updatedAt", "version"]);
  const status = text(event, "status", 32);
  if (status !== "confirmed" && status !== "cancelled") {
    throw new Error("Calendar event status is invalid");
  }
  return {
    content: parseCalendarContent(event.content),
    id: text(event, "id", 512),
    providerId: nullableText(event, "providerId", 512),
    status,
    updatedAt: timestamp(event, "updatedAt"),
    version: integer(event, "version", 1, Number.MAX_SAFE_INTEGER),
  };
}

function parseCalendarContent(value: unknown): FoundationCalendarEventContent {
  const content = exactRecord(value, [
    "attendees",
    "calendarId",
    "description",
    "end",
    "location",
    "recurrence",
    "start",
    "timezone",
    "title",
  ]);
  const start = timestamp(content, "start");
  const end = timestamp(content, "end");
  if (Date.parse(end) <= Date.parse(start)) throw new Error("Calendar event range is invalid");
  return {
    attendees: array(content.attendees, 500, parseCalendarAttendee, "Calendar attendees"),
    calendarId: text(content, "calendarId", 512),
    description: nullableText(content, "description", 64 * 1_024),
    end,
    location: nullableText(content, "location", 2_048),
    recurrence: nullableText(content, "recurrence", 16 * 1_024),
    start,
    timezone: text(content, "timezone", 255),
    title: text(content, "title", 1_024),
  };
}

function parseCalendarAttendee(value: unknown): FoundationCalendarAttendee {
  const attendee = exactRecord(value, ["address", "displayName", "response"]);
  return {
    address: text(attendee, "address", 512),
    displayName: nullableText(attendee, "displayName", 1_024),
    response: text(attendee, "response", 64),
  };
}

function parseBusyInterval(value: unknown): FoundationBusyInterval {
  const interval = exactRecord(value, ["end", "eventId", "start"]);
  const start = timestamp(interval, "start");
  const end = timestamp(interval, "end");
  if (Date.parse(end) <= Date.parse(start)) throw new Error("Busy interval is invalid");
  return { end, eventId: nullableText(interval, "eventId", 512), start };
}

function parseContactRecord(value: unknown): FoundationContactRecord {
  const contact = exactRecord(value, [
    "displayName",
    "id",
    "identities",
    "organization",
    "providerId",
    "relationship",
    "updatedAt",
    "version",
  ]);
  const identities = array(contact.identities, 100, parseContactIdentity, "Contact identities");
  if (identities.length === 0) throw new Error("Contact identities are invalid");
  return {
    displayName: text(contact, "displayName", 1_024),
    id: text(contact, "id", 512),
    identities,
    organization: nullableText(contact, "organization", 2_048),
    providerId: nullableText(contact, "providerId", 512),
    relationship: nullableText(contact, "relationship", 2_048),
    updatedAt: timestamp(contact, "updatedAt"),
    version: integer(contact, "version", 1, Number.MAX_SAFE_INTEGER),
  };
}

function parseContactIdentity(value: unknown): FoundationContactIdentity {
  const identity = exactRecord(value, ["kind", "label", "value"]);
  return {
    kind: text(identity, "kind", 64),
    label: nullableText(identity, "label", 255),
    value: text(identity, "value", 2_048),
  };
}

function exactRecord(value: unknown, keys: readonly string[]): Record<string, unknown> {
  if (!isRecord(value)) throw new Error("Workspace response is invalid");
  const actual = Object.keys(value);
  if (actual.some((key) => !keys.includes(key)) || keys.some((key) => !Object.hasOwn(value, key))) {
    throw new Error("Workspace response fields are invalid");
  }
  return value;
}

function array<T>(
  value: unknown,
  maximum: number,
  parse: (item: unknown) => T,
  name: string,
): T[] {
  if (!Array.isArray(value) || value.length > maximum) throw new Error(`${name} are invalid`);
  return value.map(parse);
}

function accountIdentifier(value: Record<string, unknown>, name: string): string {
  const result = text(value, name, 128);
  if (!SAFE_ACCOUNT_ID.test(result) || result === "." || result === "..") {
    throw new Error(`${name} is invalid`);
  }
  return result;
}

function pathIdentifier(value: Record<string, unknown>, name: string): string {
  return encodeURIComponent(text(value, name, 512));
}

function timestamp(value: Record<string, unknown>, name: string): string {
  const result = text(value, name, 64);
  if (!RFC3339.test(result) || !Number.isFinite(Date.parse(result))) {
    throw new Error(`${name} is invalid`);
  }
  return result;
}

function nullableText(value: Record<string, unknown>, name: string, maximum: number): string | null {
  const result = value[name];
  if (result === null || (
    typeof result === "string"
    && result.length <= maximum
    && result.trim().length === 0
  )) return null;
  return text(value, name, maximum);
}

function text(value: Record<string, unknown>, name: string, maximum: number): string {
  const result = value[name];
  if (
    typeof result !== "string"
    || result.trim().length === 0
    || result.length > maximum
    || [...result].some((character) => character < " " && character !== "\n" && character !== "\t")
  ) {
    throw new Error(`${name} is invalid`);
  }
  return result;
}

function integer(
  value: Record<string, unknown>,
  name: string,
  minimum: number,
  maximum: number,
): number {
  const result = value[name];
  if (!Number.isSafeInteger(result) || (result as number) < minimum || (result as number) > maximum) {
    throw new Error(`${name} is invalid`);
  }
  return result as number;
}

function get(pathname: string): { method: "GET"; pathname: string } {
  return { method: "GET", pathname };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
