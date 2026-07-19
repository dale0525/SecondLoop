import { describe, expect, it, vi } from "vitest";

import { registerHostBootstrapController } from "../src/main/hostBootstrapController";
import {
  HOST_BOOTSTRAP_LOAD_CHANNEL,
  parseHostDiscovery,
} from "../src/shared/hostBootstrap";
import { hostDiscoveryFixture } from "./hostBootstrapFixture";

describe("Host bootstrap controller", () => {
  it("loads and validates discovery through a fixed requester-only channel", async () => {
    const harness = ipcHarness();
    const sidecarRequest = vi.fn(async () => jsonResponse(hostDiscoveryFixture()));
    const dispose = registerHostBootstrapController({
      ipcMain: harness.ipcMain,
      requesterWebContents: { id: 41 },
      sidecarRequest,
    });

    const result = await harness.invoke({ sender: { id: 41 } });

    expect(result).toEqual(hostDiscoveryFixture());
    expect(sidecarRequest).toHaveBeenCalledWith(
      "/host/bootstrap",
      expect.objectContaining({
        cache: "no-store",
        headers: { Accept: "application/json" },
        method: "GET",
      }),
    );
    dispose();
    expect(harness.removeHandler).toHaveBeenCalledWith(HOST_BOOTSTRAP_LOAD_CHANNEL);
  });

  it("rejects other renderer windows before contacting the sidecar", async () => {
    const harness = ipcHarness();
    const sidecarRequest = vi.fn(async () => jsonResponse(hostDiscoveryFixture()));
    registerHostBootstrapController({
      ipcMain: harness.ipcMain,
      requesterWebContents: { id: 41 },
      sidecarRequest,
    });

    await expect(harness.invoke({ sender: { id: 99 } })).rejects.toThrow(
      "Host bootstrap is restricted to the requester window",
    );
    expect(sidecarRequest).not.toHaveBeenCalled();
  });

  it("rejects unknown fields and unsupported schemas from the sidecar", async () => {
    const harness = ipcHarness();
    registerHostBootstrapController({
      ipcMain: harness.ipcMain,
      requesterWebContents: { id: 41 },
      sidecarRequest: async () => jsonResponse({ ...hostDiscoveryFixture(), schemaVersion: 3 }),
    });

    await expect(harness.invoke({ sender: { id: 41 } })).rejects.toThrow(
      "Host discovery schema is unsupported",
    );

    expect(() => parseHostDiscovery({ ...hostDiscoveryFixture(), untrusted: true })).toThrow(
      "Host discovery contains unknown fields",
    );
  });

  it("rejects a valid discovery snapshot for another Host platform", async () => {
    const harness = ipcHarness();
    registerHostBootstrapController({
      ipcMain: harness.ipcMain,
      requesterWebContents: { id: 41 },
      sidecarRequest: async () => jsonResponse({ ...hostDiscoveryFixture(), platform: "server" }),
    });

    await expect(harness.invoke({ sender: { id: 41 } })).rejects.toThrow(
      "Host bootstrap platform is unsupported",
    );
  });

  it("does not forward sidecar error bodies to the renderer", async () => {
    const harness = ipcHarness();
    registerHostBootstrapController({
      ipcMain: harness.ipcMain,
      requesterWebContents: { id: 41 },
      sidecarRequest: async () =>
        new Response(JSON.stringify({ error: "secret internal path" }), { status: 500 }),
    });

    await expect(harness.invoke({ sender: { id: 41 } })).rejects.toThrow(
      "Host bootstrap is unavailable (HTTP 500)",
    );
    await expect(harness.invoke({ sender: { id: 41 } })).rejects.not.toThrow(
      "secret internal path",
    );
  });
});

function ipcHarness() {
  let handler: ((event: { sender: { id: number } }) => unknown) | null = null;
  const removeHandler = vi.fn();
  return {
    ipcMain: {
      handle: (channel: string, next: typeof handler) => {
        expect(channel).toBe(HOST_BOOTSTRAP_LOAD_CHANNEL);
        handler = next;
      },
      removeHandler,
    },
    invoke: (event: { sender: { id: number } }) => {
      if (!handler) throw new Error("IPC handler was not registered");
      return Promise.resolve(handler(event));
    },
    removeHandler,
  };
}

function jsonResponse(value: unknown): Response {
  return new Response(JSON.stringify(value), {
    headers: { "Content-Type": "application/json" },
    status: 200,
  });
}
