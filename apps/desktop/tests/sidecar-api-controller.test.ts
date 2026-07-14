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
