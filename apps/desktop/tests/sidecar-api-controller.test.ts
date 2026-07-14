// @vitest-environment node

import { describe, expect, it, vi } from "vitest";

import { registerSidecarApiController } from "../src/main/sidecarApiController";
import { SIDECAR_API_REQUEST_CHANNEL } from "../src/shared/sidecarApi";

describe("trusted sidecar API controller", () => {
  it("maps typed operations to fixed sidecar requests", async () => {
    const harness = ipcHarness();
    const sidecarRequest = vi.fn(async () => new Response(JSON.stringify([{ id: "memory-1" }])));
    registerSidecarApiController({
      ipcMain: harness.ipcMain,
      requesterWebContents: { id: 42 },
      sidecarRequest,
    });

    await expect(harness.invoke(
      { sender: { id: 42 } },
      { input: { limit: 25, query: "flight" }, operation: "memory.list" },
    )).resolves.toEqual([{ id: "memory-1" }]);
    expect(sidecarRequest).toHaveBeenCalledWith(
      "/foundation/memory?query=flight&limit=25",
      expect.objectContaining({ method: "GET" }),
    );

    await harness.invoke(
      { sender: { id: 42 } },
      {
        input: {
          expectedUpdatedAt: "2026-07-14T10:00:00Z",
          id: "session-1",
          title: "Renamed",
        },
        operation: "sessions.update",
      },
    );
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      "/sessions/session-1",
      expect.objectContaining({
        body: JSON.stringify({
          title: "Renamed",
          expectedUpdatedAt: "2026-07-14T10:00:00Z",
        }),
        method: "PATCH",
      }),
    );

    await harness.invoke(
      { sender: { id: 42 } },
      {
        input: { after: 7, limit: 50, sessionId: "session-1", turnId: "turn-1", waitMs: 5000 },
        operation: "turns.events",
      },
    );
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      "/sessions/session-1/turns/turn-1/events?after=7&limit=50&waitMs=5000",
      expect.objectContaining({ method: "GET" }),
    );

    await harness.invoke(
      { sender: { id: 42 } },
      {
        input: { sessionId: "session-1", turnId: "turn-1" },
        operation: "turns.cancel",
      },
    );
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      "/sessions/session-1/turns/turn-1/cancel",
      expect.objectContaining({ method: "POST" }),
    );
  });

  it("maps every task operation to the fixed Foundation Tasks API", async () => {
    const harness = ipcHarness();
    const sidecarRequest = vi.fn(async () => new Response(JSON.stringify({ id: "task-1" })));
    registerSidecarApiController({
      ipcMain: harness.ipcMain,
      requesterWebContents: { id: 42 },
      sidecarRequest,
    });
    const content = {
      title: "Prepare briefing",
      notes: "Use the latest figures",
      dueAt: "2026-07-16T09:30:00+08:00",
      timezone: "Asia/Shanghai",
      recurrence: null,
      priority: "high",
      tags: ["work"],
    };

    await harness.invoke(
      { sender: { id: 42 } },
      {
        input: {
          cursor: "next-page",
          dueAfter: "2026-07-15T00:00:00Z",
          dueBefore: "2026-07-20T00:00:00Z",
          limit: 25,
          status: "open",
          tag: "work",
          text: "briefing",
        },
        operation: "tasks.list",
      },
    );
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      "/foundation/tasks?status=open&dueAfter=2026-07-15T00%3A00%3A00Z&dueBefore=2026-07-20T00%3A00%3A00Z&tag=work&text=briefing&limit=25&cursor=next-page",
      expect.objectContaining({ method: "GET" }),
    );

    await harness.invoke(
      { sender: { id: 42 } },
      { input: { id: "task-1" }, operation: "tasks.get" },
    );
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      "/foundation/tasks/task-1",
      expect.objectContaining({ method: "GET" }),
    );

    await harness.invoke(
      { sender: { id: 42 } },
      { input: { content, idempotencyKey: "create-1" }, operation: "tasks.create" },
    );
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      "/foundation/tasks",
      expect.objectContaining({
        body: JSON.stringify({ content, idempotencyKey: "create-1" }),
        method: "POST",
      }),
    );

    await harness.invoke(
      { sender: { id: 42 } },
      { input: { content, expectedVersion: 2, id: "task-1" }, operation: "tasks.update" },
    );
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      "/foundation/tasks/task-1",
      expect.objectContaining({
        body: JSON.stringify({ content, expectedVersion: 2 }),
        method: "PATCH",
      }),
    );

    await harness.invoke(
      { sender: { id: 42 } },
      {
        input: { expectedVersion: 3, id: "task-1", status: "completed" },
        operation: "tasks.setStatus",
      },
    );
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      "/foundation/tasks/task-1/status",
      expect.objectContaining({
        body: JSON.stringify({ expectedVersion: 3, status: "completed" }),
        method: "POST",
      }),
    );

    await harness.invoke(
      { sender: { id: 42 } },
      { input: { expectedVersion: 4, id: "task-1" }, operation: "tasks.delete" },
    );
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      "/foundation/tasks/task-1",
      expect.objectContaining({ body: JSON.stringify({ expectedVersion: 4 }), method: "DELETE" }),
    );
  });

  it("maps attachment metadata operations without exposing attachment bytes", async () => {
    const harness = ipcHarness();
    const sidecarRequest = vi.fn(async () => new Response(JSON.stringify([])));
    registerSidecarApiController({
      ipcMain: harness.ipcMain,
      requesterWebContents: { id: 42 },
      sidecarRequest,
    });
    const id = "123e4567-e89b-12d3-a456-426614174000";

    await harness.invoke(
      { sender: { id: 42 } },
      { input: { limit: 10 }, operation: "attachments.list" },
    );
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      "/foundation/attachments?limit=10",
      expect.objectContaining({ method: "GET" }),
    );

    await harness.invoke(
      { sender: { id: 42 } },
      { input: { id }, operation: "attachments.get" },
    );
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      `/foundation/attachments/${id}`,
      expect.objectContaining({ method: "GET" }),
    );

    await harness.invoke(
      { sender: { id: 42 } },
      { input: { id }, operation: "attachments.delete" },
    );
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      `/foundation/attachments/${id}`,
      expect.objectContaining({ method: "DELETE" }),
    );
  });

  it.each([
    ["invalid task identifier", { input: { id: "../secret" }, operation: "tasks.get" }, /id is invalid/],
    ["oversized title", taskCreate({ title: "x".repeat(1_025) }, "create-1"), /title is invalid/],
    ["oversized notes", taskCreate({ notes: "x".repeat(65_537) }, "create-1"), /notes is invalid/],
    ["oversized idempotency key", taskCreate({}, "x".repeat(513)), /idempotencyKey is invalid/],
    ["blank idempotency key", taskCreate({}, "   "), /idempotencyKey is invalid/],
    ["invalid version", {
      input: { expectedVersion: 0, id: "task-1", status: "completed" },
      operation: "tasks.setStatus",
    }, /expectedVersion is invalid/],
    ["invalid status", {
      input: { expectedVersion: 1, id: "task-1", status: "archived" },
      operation: "tasks.setStatus",
    }, /status is invalid/],
    ["unknown input field", {
      input: { id: "task-1", path: "/etc/passwd" },
      operation: "tasks.get",
    }, /unknown fields/],
    ["unknown content field", taskCreate({ path: "/etc/passwd" }, "create-1"), /unknown fields/],
  ])("rejects %s before task sidecar access", async (_name, request, error) => {
    const harness = ipcHarness();
    const sidecarRequest = vi.fn();
    registerSidecarApiController({
      ipcMain: harness.ipcMain,
      requesterWebContents: { id: 42 },
      sidecarRequest,
    });

    await expect(harness.invoke({ sender: { id: 42 } }, request)).rejects.toThrow(error as RegExp);
    expect(sidecarRequest).not.toHaveBeenCalled();
  });

  it("rejects other renderers and arbitrary operations before sidecar access", async () => {
    const harness = ipcHarness();
    const sidecarRequest = vi.fn();
    registerSidecarApiController({
      ipcMain: harness.ipcMain,
      requesterWebContents: { id: 42 },
      sidecarRequest,
    });

    await expect(harness.invoke(
      { sender: { id: 7 } },
      { operation: "memory.list" },
    )).rejects.toThrow(/requester window/);
    await expect(harness.invoke(
      { sender: { id: 42 } },
      { input: { path: "http://attacker.invalid" }, operation: "raw.fetch" },
    )).rejects.toThrow(/operation is not allowed/);
    await expect(harness.invoke(
      { sender: { id: 42 } },
      { input: { id: ".." }, operation: "memory.get" },
    )).rejects.toThrow(/id is invalid/);
    expect(sidecarRequest).not.toHaveBeenCalled();
  });
});

function taskCreate(overrides: Record<string, unknown>, idempotencyKey: string) {
  return {
    input: {
      content: {
        title: "Prepare briefing",
        priority: "normal",
        tags: [],
        ...overrides,
      },
      idempotencyKey,
    },
    operation: "tasks.create",
  };
}

function ipcHarness() {
  let handler: ((event: { sender: { id: number } }, value: unknown) => unknown) | null = null;
  return {
    ipcMain: {
      handle: (channel: string, next: typeof handler) => {
        expect(channel).toBe(SIDECAR_API_REQUEST_CHANNEL);
        handler = next;
      },
      removeHandler: () => undefined,
    },
    invoke: (event: { sender: { id: number } }, value: unknown) => {
      if (!handler) throw new Error("IPC handler was not registered");
      return Promise.resolve(handler(event, value));
    },
  };
}
