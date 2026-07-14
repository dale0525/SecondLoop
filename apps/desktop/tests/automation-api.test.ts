import { afterEach, describe, expect, it, vi } from "vitest";

import { registerSidecarApiController } from "../src/main/sidecarApiController";
import {
  cancelFoundationNotification,
  createFoundationSchedule,
  enqueueFoundationNotification,
  getFoundationNotification,
  getFoundationSchedule,
  listFoundationNotifications,
  listFoundationSchedules,
  setFoundationScheduleStatus,
} from "../src/renderer/api";

afterEach(() => {
  delete window.agentWeave;
  vi.restoreAllMocks();
});

describe("Automation Foundation renderer API", () => {
  it("uses only typed trusted bridge operations", async () => {
    const request = vi.fn(async (_operation: string, _input?: unknown) => ({}));
    window.agentWeave = {
      server: { request },
      owner: {} as NonNullable<Window["agentWeave"]>["owner"],
      approval: { open: vi.fn() },
    };
    const schedule = { kind: "one_shot" as const, at: "2026-07-16T01:00:00Z" };
    const misfire = { kind: "fire_once" as const };

    await listFoundationSchedules(20);
    await getFoundationSchedule("schedule-1");
    await createFoundationSchedule({
      name: "Morning brief",
      schedule,
      misfire,
      payload: { kind: "brief" },
      idempotencyKey: "schedule-create-1",
    });
    await setFoundationScheduleStatus("schedule-1", 1, "paused");
    await listFoundationNotifications("pending", 20);
    await getFoundationNotification("notification-1");
    await enqueueFoundationNotification({
      channel: "desktop",
      title: "Brief ready",
      body: "Your morning brief is ready.",
      dedupeKey: "brief-ready-1",
      notBefore: "2026-07-16T01:00:00Z",
      data: {},
    });
    await cancelFoundationNotification("notification-1");

    expect(request.mock.calls.map(([operation]) => operation)).toEqual([
      "schedules.list",
      "schedules.get",
      "schedules.create",
      "schedules.setStatus",
      "notifications.list",
      "notifications.get",
      "notifications.enqueue",
      "notifications.cancel",
    ]);
  });
});

describe("Automation Foundation sidecar controller", () => {
  it("maps scoped operations to fixed Foundation routes", async () => {
    const harness = ipcHarness();
    const sidecarRequest = vi.fn(async () => response({}));
    registerSidecarApiController({
      ipcMain: harness.ipcMain,
      requesterWebContents: { id: 42 },
      sidecarRequest,
    });
    const invoke = (value: unknown) => harness.invoke({ sender: { id: 42 } }, value);

    await invoke({
      operation: "schedules.create",
      input: {
        name: "Morning brief",
        schedule: { kind: "one_shot", at: "2026-07-16T01:00:00Z" },
        misfire: { kind: "fire_once" },
        payload: {},
        idempotencyKey: "schedule-1",
      },
    });
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      "/foundation/schedules",
      expect.objectContaining({ method: "POST" }),
    );

    await invoke({
      operation: "notifications.enqueue",
      input: {
        channel: "desktop",
        title: "Brief ready",
        body: "Ready",
        dedupeKey: "notification-1",
        notBefore: "2026-07-16T01:00:00Z",
        data: {},
      },
    });
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      "/foundation/notifications",
      expect.objectContaining({ method: "POST" }),
    );
  });

  it("rejects caller scope and malformed schedules before sidecar access", async () => {
    const harness = ipcHarness();
    const sidecarRequest = vi.fn();
    registerSidecarApiController({
      ipcMain: harness.ipcMain,
      requesterWebContents: { id: 42 },
      sidecarRequest,
    });

    await expect(harness.invoke(
      { sender: { id: 42 } },
      {
        operation: "schedules.create",
        input: {
          appId: "other",
          name: "Foreign",
          schedule: { kind: "one_shot", at: "2026-07-16T01:00:00Z" },
          misfire: { kind: "fire_once" },
          idempotencyKey: "schedule-1",
        },
      },
    )).rejects.toThrow(/unknown fields/);
    await expect(harness.invoke(
      { sender: { id: 42 } },
      {
        operation: "schedules.create",
        input: {
          name: "Broken",
          schedule: { kind: "interval", anchor: "not-a-time", every_seconds: 0 },
          misfire: { kind: "fire_once" },
          idempotencyKey: "schedule-1",
        },
      },
    )).rejects.toThrow(/anchor is invalid/);
    expect(sidecarRequest).not.toHaveBeenCalled();
  });
});

function ipcHarness() {
  let handler: ((event: { sender: { id: number } }, value: unknown) => unknown) | undefined;
  return {
    ipcMain: {
      handle: (_channel: string, next: typeof handler) => { handler = next; },
      removeHandler: vi.fn(),
    },
    invoke: (event: { sender: { id: number } }, value: unknown) => {
      if (!handler) throw new Error("handler missing");
      return handler(event, value);
    },
  };
}

function response(value: unknown): Response {
  return new Response(JSON.stringify(value), {
    headers: { "content-type": "application/json" },
    status: 200,
  });
}
