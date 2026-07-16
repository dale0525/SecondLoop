import { afterEach, describe, expect, it, vi } from "vitest";

import {
  cancelWorkspaceOAuth,
  getFoundationCalendarEvent,
  getFoundationCalendarFreeBusy,
  getFoundationContact,
  getWorkspaceOAuthStatus,
  listFoundationCalendarEvents,
  resolveFoundationContacts,
  startWorkspaceOAuth,
} from "../src/renderer/workspaceApi";
import { parseWorkspaceReadResponse } from "../src/shared/workspaceFoundation";

afterEach(() => {
  delete window.agentWeave;
  vi.restoreAllMocks();
});

describe("Workspace Renderer API", () => {
  it("maps Calendar and Contacts reads to typed trusted operations", async () => {
    const request = vi.fn(async () => []);
    installServerBridge(request);
    const start = "2026-07-16T00:00:00Z";
    const end = "2026-07-17T00:00:00Z";

    await listFoundationCalendarEvents("acct.primary", start, end);
    await getFoundationCalendarEvent("acct.primary", "event/with spaces");
    await getFoundationCalendarFreeBusy("acct.primary", start, end);
    await resolveFoundationContacts("acct.primary", "Ada", 5);
    await getFoundationContact("acct.primary", "people/ada");

    expect(request.mock.calls).toEqual([
      ["calendar.events.list", { accountId: "acct.primary", end, start }],
      ["calendar.events.get", { accountId: "acct.primary", eventId: "event/with spaces" }],
      ["calendar.freeBusy", { accountId: "acct.primary", end, start }],
      ["contacts.resolve", { accountId: "acct.primary", limit: 5, query: "Ada" }],
      ["contacts.get", { accountId: "acct.primary", contactId: "people/ada" }],
    ]);
  });

  it("wraps OAuth lifecycle without accepting token material", async () => {
    const request = vi.fn(async (operation: string) => operation === "oauth.start"
      ? oauthSummary()
      : oauthView(operation === "oauth.cancel" ? "cancelled" : "pending"));
    installServerBridge(request);
    const input = {
      connectorIds: ["agentweave-calendar", "agentweave-contacts"],
      providerId: "microsoft-graph",
      requestedCapabilities: ["calendar", "contacts"],
    };

    await expect(startWorkspaceOAuth(input)).resolves.toEqual(oauthSummary());
    await expect(getWorkspaceOAuthStatus("authorization-1")).resolves.toMatchObject({ status: "pending" });
    await expect(cancelWorkspaceOAuth("authorization-1")).resolves.toMatchObject({ status: "cancelled" });
    expect(request.mock.calls).toEqual([
      ["oauth.start", input],
      ["oauth.status", { authorizationId: "authorization-1" }],
      ["oauth.cancel", { authorizationId: "authorization-1" }],
    ]);
  });

  it("normalizes empty optional provider fields to null", () => {
    const events = parseWorkspaceReadResponse("calendar.events.list", [{
      content: {
        attendees: [{ address: "ada@example.test", displayName: "", response: "accepted" }],
        calendarId: "primary",
        description: "",
        end: "2026-07-16T11:00:00Z",
        location: "",
        recurrence: "",
        start: "2026-07-16T10:00:00Z",
        timezone: "Asia/Shanghai",
        title: "Planning",
      },
      id: "event-1",
      providerId: "",
      status: "confirmed",
      updatedAt: "2026-07-16T09:00:00Z",
      version: 1,
    }]);
    const contacts = parseWorkspaceReadResponse("contacts.resolve", [{
      displayName: "Ada Lovelace",
      id: "contact-1",
      identities: [{ kind: "email", label: "", value: "ada@example.test" }],
      organization: "",
      providerId: "",
      relationship: "",
      updatedAt: "2026-07-16T09:00:00Z",
      version: 1,
    }]);

    expect(events).toMatchObject([{
      content: {
        attendees: [{ displayName: null }],
        description: null,
        location: null,
        recurrence: null,
      },
      providerId: null,
    }]);
    expect(contacts).toMatchObject([{
      identities: [{ label: null }],
      organization: null,
      providerId: null,
      relationship: null,
    }]);
  });
});

function installServerBridge(request: (operation: string, input?: unknown) => Promise<unknown>) {
  window.agentWeave = {
    server: { request },
    owner: {} as NonNullable<Window["agentWeave"]>["owner"],
    approval: { open: vi.fn() },
  };
}

function oauthSummary() {
  return {
    authorizationId: "authorization-1",
    expiresAt: "2026-07-16T01:00:00Z",
    providerId: "microsoft-graph",
    status: "pending",
  };
}

function oauthView(status: "cancelled" | "pending") {
  return {
    ...oauthSummary(),
    bindings: [],
    connectorIds: ["agentweave-calendar", "agentweave-contacts"],
    createdAt: "2026-07-16T00:00:00Z",
    errorCode: status === "cancelled" ? "authorization_cancelled" : null,
    requestedCapabilities: ["calendar", "contacts"],
    status,
    updatedAt: "2026-07-16T00:01:00Z",
  };
}
