// @vitest-environment node

import { describe, expect, it, vi } from "vitest";

import { registerOwnerController } from "../src/main/ownerController";
import { OWNER_REQUEST_CHANNEL } from "../src/shared/ownerRequest";

describe("Owner Main-process controller", () => {
  it("keeps the bearer credential in Main and delegates through sidecar transport", async () => {
    const harness = ipcHarness();
    const sidecarRequest = vi.fn(async (_path: string, _init: RequestInit = {}) =>
      new Response(JSON.stringify({ packages: [] })));
    registerOwnerController({
      ipcMain: harness.ipcMain,
      requesterToken: "owner-main-secret",
      requesterWebContents: { id: 11 },
      sidecarRequest,
    });

    await expect(harness.invoke(
      { sender: { id: 11 } },
      { operation: "listSkills" },
    )).resolves.toEqual({ packages: [] });
    const [path, init] = sidecarRequest.mock.calls[0];
    expect(path).toBe("/owner/skills");
    expect(new Headers(init!.headers).get("Authorization")).toBe("Bearer owner-main-secret");
  });

  it("rejects untrusted windows and invalid identifiers before sidecar access", async () => {
    const harness = ipcHarness();
    const sidecarRequest = vi.fn();
    registerOwnerController({
      ipcMain: harness.ipcMain,
      requesterToken: "owner-main-secret",
      requesterWebContents: { id: 11 },
      sidecarRequest,
    });

    await expect(harness.invoke(
      { sender: { id: 9 } },
      { operation: "listSkills" },
    )).rejects.toThrow(/requester window/);
    await expect(harness.invoke(
      { sender: { id: 11 } },
      { operation: "skillDetail", input: { packageId: "../../sessions" } },
    )).rejects.toThrow(/package id/);
    expect(sidecarRequest).not.toHaveBeenCalled();
  });
});

function ipcHarness() {
  let handler: ((event: { sender: { id: number } }, value: unknown) => unknown) | null = null;
  return {
    ipcMain: {
      handle: (channel: string, next: typeof handler) => {
        expect(channel).toBe(OWNER_REQUEST_CHANNEL);
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
