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
