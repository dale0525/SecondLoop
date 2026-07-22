// @vitest-environment node

import { describe, expect, it, vi } from "vitest";

import { registerCommerceController } from "../src/main/commerceController";
import {
  COMMERCE_PORTAL_CHANNEL,
  COMMERCE_STATUS_CHANNEL,
} from "../src/shared/commerce";

describe("trusted Commerce Host controller", () => {
  it("acknowledges portal verification only after the system browser opens", async () => {
    const harness = ipcHarness();
    const calls: Array<{ pathname: string; body: unknown }> = [];
    const openExternal = vi.fn(async () => undefined);
    registerCommerceController({
      ipcMain: harness.ipcMain,
      openExternal,
      requesterWebContents: { id: 7 },
      sidecarRequest: async (pathname, init) => {
        calls.push({
          pathname,
          body: init?.body ? JSON.parse(String(init.body)) : null,
        });
        if (pathname === "/commerce/customer-portal") {
          return jsonResponse({
            portalUrl: "https://app.creem.io/customer/token",
            verificationNonce: "nonce_0000000000000002",
          });
        }
        if (pathname === "/commerce/customer-portal/verified") {
          return jsonResponse({ verified: true });
        }
        throw new Error(`Unexpected request: ${pathname}`);
      },
    });

    await expect(harness.invoke(COMMERCE_PORTAL_CHANNEL)).resolves.toEqual({ opened: true });
    expect(openExternal).toHaveBeenCalledWith("https://app.creem.io/customer/token");
    expect(calls).toEqual([{
      pathname: "/commerce/customer-portal",
      body: null,
    }, {
      pathname: "/commerce/customer-portal/verified",
      body: { verificationNonce: "nonce_0000000000000002" },
    }]);
  });

  it("does not mark the portal verified when the system browser fails", async () => {
    const harness = ipcHarness();
    const sidecarRequest = vi.fn(async () => jsonResponse({
      portalUrl: "https://app.creem.io/customer/token",
      verificationNonce: "nonce_0000000000000002",
    }));
    registerCommerceController({
      ipcMain: harness.ipcMain,
      openExternal: async () => { throw new Error("open failed"); },
      requesterWebContents: { id: 7 },
      sidecarRequest,
    });

    await expect(harness.invoke(COMMERCE_PORTAL_CHANNEL)).rejects.toThrow("commerce_browser_open_failed");
    expect(sidecarRequest).toHaveBeenCalledTimes(1);
  });

  it("rejects portal Provider parameters and another Renderer", async () => {
    const harness = ipcHarness();
    const sidecarRequest = vi.fn();
    registerCommerceController({
      ipcMain: harness.ipcMain,
      openExternal: vi.fn(),
      requesterWebContents: { id: 7 },
      sidecarRequest,
    });

    await expect(harness.invoke(COMMERCE_PORTAL_CHANNEL, { customerId: "cust_attacker" }))
      .rejects.toThrow("does not accept Provider parameters");
    await expect(harness.invoke(COMMERCE_STATUS_CHANNEL, undefined, 8))
      .rejects.toThrow("restricted");
    expect(sidecarRequest).not.toHaveBeenCalled();
  });
});

function ipcHarness() {
  const handlers = new Map<
    string,
    (event: { sender: { id: number } }, value?: unknown) => unknown
  >();
  return {
    ipcMain: {
      handle: (
        channel: string,
        handler: (event: { sender: { id: number } }, value?: unknown) => unknown,
      ) => { handlers.set(channel, handler); },
      removeHandler: (channel: string) => { handlers.delete(channel); },
    },
    invoke: async (channel: string, value?: unknown, sender = 7) => {
      const handler = handlers.get(channel);
      if (!handler) throw new Error(`Missing IPC handler: ${channel}`);
      return handler({ sender: { id: sender } }, value);
    },
  };
}

function jsonResponse(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "content-type": "application/json" },
  });
}
