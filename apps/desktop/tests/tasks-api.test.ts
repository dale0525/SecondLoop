import { afterEach, describe, expect, it, vi } from "vitest";

import {
  createFoundationTask,
  deleteFoundationTask,
  getFoundationTask,
  listFoundationTasks,
  setFoundationTaskStatus,
  updateFoundationTask,
  type FoundationTaskContent,
} from "../src/renderer/api";

afterEach(() => {
  delete window.agentWeave;
  vi.restoreAllMocks();
});

describe("Foundation Tasks renderer API", () => {
  it("uses only the typed trusted bridge operations", async () => {
    const request = vi.fn(async (operation: string) => operation === "tasks.list"
      ? { tasks: [], nextCursor: null }
      : task());
    installServerBridge(request);
    const content = task().content;

    await expect(listFoundationTasks({
      status: "open",
      dueAfter: "2026-07-15T00:00:00Z",
      dueBefore: "2026-07-20T00:00:00Z",
      tag: "work",
      text: "briefing",
      limit: 25,
      cursor: "next-page",
    })).resolves.toEqual({ tasks: [], nextCursor: null });
    await getFoundationTask("task-1");
    await createFoundationTask(content, "create-1");
    await updateFoundationTask("task-1", 1, content);
    await setFoundationTaskStatus("task-1", 2, "completed");
    await deleteFoundationTask("task-1", 3);

    expect(request.mock.calls).toEqual([
      ["tasks.list", {
        status: "open",
        dueAfter: "2026-07-15T00:00:00Z",
        dueBefore: "2026-07-20T00:00:00Z",
        tag: "work",
        text: "briefing",
        limit: 25,
        cursor: "next-page",
      }],
      ["tasks.get", { id: "task-1" }],
      ["tasks.create", { content, idempotencyKey: "create-1" }],
      ["tasks.update", { content, expectedVersion: 1, id: "task-1" }],
      ["tasks.setStatus", { expectedVersion: 2, id: "task-1", status: "completed" }],
      ["tasks.delete", { expectedVersion: 3, id: "task-1" }],
    ]);
  });
});

function task() {
  const content: FoundationTaskContent = {
    title: "Prepare briefing",
    notes: null,
    dueAt: "2026-07-16T09:30:00+08:00",
    timezone: "Asia/Shanghai",
    recurrence: null,
    priority: "high",
    tags: ["work"],
  };
  return {
    id: "task-1",
    content,
    status: "open" as const,
    version: 1,
    createdAt: "2026-07-15T00:00:00Z",
    updatedAt: "2026-07-15T00:00:00Z",
    completedAt: null,
  };
}

function installServerBridge(request: (operation: string, input?: unknown) => Promise<unknown>) {
  window.agentWeave = {
    server: { request },
    owner: {} as NonNullable<Window["agentWeave"]>["owner"],
    approval: { open: vi.fn() },
  };
}
