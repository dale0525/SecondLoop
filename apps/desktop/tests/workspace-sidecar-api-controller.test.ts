// @vitest-environment node

import { describe, expect, it, vi } from "vitest";

import { registerSidecarApiController } from "../src/main/sidecarApiController";

describe("trusted Workspace sidecar operations", () => {
  it("maps fixed Calendar and Contacts paths and returns validated records", async () => {
    const harness = ipcHarness();
    const sidecarRequest = vi.fn(async (path: string) => new Response(JSON.stringify(
      path.includes("/calendar/") ? [calendarEvent()] : [contact()],
    )));
    register(harness, sidecarRequest);

    await expect(harness.invoke({
      input: {
        accountId: "acct.primary",
        end: "2026-07-17T00:00:00Z",
        start: "2026-07-16T00:00:00Z",
      },
      operation: "calendar.events.list",
    })).resolves.toEqual([calendarEvent()]);
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      "/foundation/calendar/events?accountId=acct.primary&start=2026-07-16T00%3A00%3A00Z&end=2026-07-17T00%3A00%3A00Z",
      expect.objectContaining({ method: "GET" }),
    );

    await expect(harness.invoke({
      input: { accountId: "acct.primary", limit: 5, query: "Ada Lovelace" },
      operation: "contacts.resolve",
    })).resolves.toEqual([contact()]);
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      "/foundation/contacts?accountId=acct.primary&query=Ada+Lovelace&limit=5",
      expect.objectContaining({ method: "GET" }),
    );
  });

  it("encodes opaque provider identifiers only into fixed path slots", async () => {
    const harness = ipcHarness();
    const sidecarRequest = vi.fn(async (path: string) => new Response(JSON.stringify(
      path.includes("/calendar/") ? calendarEvent() : contact(),
    )));
    register(harness, sidecarRequest);

    await harness.invoke({
      input: { accountId: "acct.primary", eventId: "provider/event = 1" },
      operation: "calendar.events.get",
    });
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      "/foundation/calendar/events/provider%2Fevent%20%3D%201?accountId=acct.primary",
      expect.objectContaining({ method: "GET" }),
    );

    await harness.invoke({
      input: { accountId: "acct.primary", contactId: "people/ada" },
      operation: "contacts.get",
    });
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      "/foundation/contacts/people%2Fada?accountId=acct.primary",
      expect.objectContaining({ method: "GET" }),
    );
  });

  it.each([
    ["unknown account field", { accountId: "acct.primary", end: "2026-07-17T00:00:00Z", secret: "x", start: "2026-07-16T00:00:00Z" }, "calendar.events.list"],
    ["reversed Calendar range", { accountId: "acct.primary", end: "2026-07-15T00:00:00Z", start: "2026-07-16T00:00:00Z" }, "calendar.events.list"],
    ["unsafe account ID", { accountId: "../vault", limit: 5, query: "Ada" }, "contacts.resolve"],
    ["blank contact query", { accountId: "acct.primary", limit: 5, query: "  " }, "contacts.resolve"],
  ])("rejects %s before sidecar access", async (_name, input, operation) => {
    const harness = ipcHarness();
    const sidecarRequest = vi.fn();
    register(harness, sidecarRequest);
    await expect(harness.invoke({ input, operation })).rejects.toThrow();
    expect(sidecarRequest).not.toHaveBeenCalled();
  });

  it("rejects provider responses with undeclared or malformed fields", async () => {
    const harness = ipcHarness();
    const sidecarRequest = vi.fn(async () => new Response(JSON.stringify([{
      ...calendarEvent(),
      accessToken: "must-not-cross-ipc",
    }])));
    register(harness, sidecarRequest);

    await expect(harness.invoke({
      input: {
        accountId: "acct.primary",
        end: "2026-07-17T00:00:00Z",
        start: "2026-07-16T00:00:00Z",
      },
      operation: "calendar.events.list",
    })).rejects.toThrow(/fields are invalid/);
  });
});

function register(harness: ReturnType<typeof ipcHarness>, sidecarRequest: ReturnType<typeof vi.fn>) {
  registerSidecarApiController({
    ipcMain: harness.ipcMain,
    openExternal: vi.fn(),
    requesterWebContents: { id: 42 },
    sidecarRequest,
  });
}

function ipcHarness() {
  let handler: ((event: { sender: { id: number } }, value: unknown) => unknown) | undefined;
  return {
    ipcMain: {
      handle: (_channel: string, next: typeof handler) => { handler = next; },
      removeHandler: () => { handler = undefined; },
    },
    invoke: (value: unknown) => {
      if (!handler) throw new Error("handler is not registered");
      return handler({ sender: { id: 42 } }, value);
    },
  };
}

function calendarEvent() {
  return {
    content: {
      attendees: [{ address: "ada@example.test", displayName: "Ada", response: "accepted" }],
      calendarId: "primary",
      description: null,
      end: "2026-07-16T03:00:00Z",
      location: "Studio",
      recurrence: null,
      start: "2026-07-16T02:00:00Z",
      timezone: "Asia/Shanghai",
      title: "Board review",
    },
    id: "event-1",
    providerId: "provider-event-1",
    status: "confirmed",
    updatedAt: "2026-07-16T00:00:00Z",
    version: 2,
  };
}

function contact() {
  return {
    displayName: "Ada Lovelace",
    id: "contact-1",
    identities: [{ kind: "email", label: "work", value: "ada@example.test" }],
    organization: "Analytical Engine",
    providerId: "people/ada",
    relationship: "Collaborator",
    updatedAt: "2026-07-16T00:00:00Z",
    version: 3,
  };
}
