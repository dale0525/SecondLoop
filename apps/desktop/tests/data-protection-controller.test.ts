// @vitest-environment node

import { createHash } from "node:crypto";
import { describe, expect, it, vi } from "vitest";

import { registerDataProtectionController } from "../src/main/dataProtectionController";
import {
  DATA_PROTECTION_EXPORT_CHANNEL,
  DATA_PROTECTION_RESTORE_CHANNEL,
  DATA_PROTECTION_STATUS_CHANNEL,
} from "../src/shared/dataProtection";

const status = {
  enabled: true,
  atRestEncryption: "not_provided",
  backupEncryption: "aes-256-gcm",
  backupFormat: "agentweave-backup-v1",
  pendingRestart: false,
  restoreRollbackAvailable: false,
};

const backup = {
  appId: "agentweave.default",
  createdAt: "2026-07-14T10:00:00Z",
  plaintextBytes: 4,
  plaintextSha256: "a".repeat(64),
  envelopeSha256: "b".repeat(64),
};

describe("trusted data protection controller", () => {
  it("returns status and exports encrypted bytes without returning a path", async () => {
    const harness = ipcHarness();
    const writeFile = vi.fn(async () => undefined);
    const sidecar = sidecarFixture(async (pathname) => pathname.endsWith("/status")
      ? jsonResponse(status)
      : new Response(new Uint8Array([1, 2, 3, 4]), {
          headers: {
            "content-length": "4",
            "x-agentweave-backup-created-at": "2026-07-14T10:00:00Z",
            "x-agentweave-backup-sha256": createHash("sha256")
              .update(new Uint8Array([1, 2, 3, 4]))
              .digest("hex"),
          },
        }));
    registerDataProtectionController({
      chooseBackupDestination: async () => "/Users/local/backup.agentweave-backup",
      chooseBackupSource: async () => null,
      ipcMain: harness.ipcMain,
      readFile: vi.fn(),
      requesterWebContents: { id: 42 },
      sidecar,
      wrappedKey: "wrapped-key",
      writeFile,
    });

    await expect(harness.invoke(DATA_PROTECTION_STATUS_CHANNEL, 42)).resolves.toEqual(status);
    const receipt = await harness.invoke(DATA_PROTECTION_EXPORT_CHANNEL, 42);
    expect(receipt).toMatchObject({
      exported: true,
      createdAt: "2026-07-14T10:00:00Z",
    });
    expect(receipt).toEqual(expect.objectContaining({
      bytes: expect.any(Number),
      sha256: expect.stringMatching(/^[0-9a-f]{64}$/),
    }));
    expect(JSON.stringify(receipt)).not.toContain("/Users/");
    expect(writeFile).toHaveBeenCalledWith(
      "/Users/local/backup.agentweave-backup",
      expect.objectContaining({ byteLength: expect.any(Number) }),
    );
  });

  it("imports in Main and restarts only after a validated restore is staged", async () => {
    const harness = ipcHarness();
    const sidecar = sidecarFixture(async () => jsonResponse({
      accepted: true,
      restartRequired: true,
      backup,
    }));
    registerDataProtectionController({
      chooseBackupDestination: async () => null,
      chooseBackupSource: async () => "/private/backup.agentweave-backup",
      ipcMain: harness.ipcMain,
      readFile: async () => desktopBundle("wrapped-key", new Uint8Array([1, 2, 3, 4])),
      requesterWebContents: { id: 42 },
      sidecar,
      unwrapKey: (wrappedKey) => {
        expect(wrappedKey).toBe("wrapped-key");
        return Buffer.alloc(32, 7);
      },
      writeFile: vi.fn(),
    });

    const receipt = await harness.invoke(DATA_PROTECTION_RESTORE_CHANNEL, 42);
    expect(receipt).toEqual({ accepted: true, backup, restarted: true });
    expect(JSON.stringify(receipt)).not.toContain("/private/");
    expect(sidecar.stop).toHaveBeenCalledOnce();
    expect(sidecar.start).toHaveBeenCalledOnce();
  });

  it("rejects other windows and treats picker cancellation as no mutation", async () => {
    const harness = ipcHarness();
    const sidecar = sidecarFixture(vi.fn());
    registerDataProtectionController({
      chooseBackupDestination: async () => null,
      chooseBackupSource: async () => null,
      ipcMain: harness.ipcMain,
      readFile: vi.fn(),
      requesterWebContents: { id: 42 },
      sidecar,
      writeFile: vi.fn(),
    });

    await expect(harness.invoke(DATA_PROTECTION_EXPORT_CHANNEL, 7)).rejects.toThrow(/requester/);
    await expect(harness.invoke(DATA_PROTECTION_EXPORT_CHANNEL, 42)).resolves.toBeNull();
    await expect(harness.invoke(DATA_PROTECTION_RESTORE_CHANNEL, 42)).resolves.toBeNull();
    expect(sidecar.request).not.toHaveBeenCalled();
  });
});

function sidecarFixture(request: (pathname: string) => Promise<Response>) {
  return {
    request: vi.fn(request),
    start: vi.fn(async () => sidecarStatus("ready")),
    stop: vi.fn(async () => sidecarStatus("stopped")),
  };
}

function sidecarStatus(state: "ready" | "stopped") {
  return {
    attempt: 1,
    canEnsureRunning: false,
    lastExit: null,
    mode: "managed" as const,
    schemaVersion: 1 as const,
    state,
  };
}

function jsonResponse(value: unknown): Response {
  return new Response(JSON.stringify(value), {
    headers: { "content-type": "application/json" },
  });
}

function desktopBundle(wrappedKey: string, envelope: Uint8Array): Uint8Array {
  const wrapped = Buffer.from(wrappedKey);
  const output = Buffer.alloc(8 + 4 + wrapped.byteLength + envelope.byteLength);
  output.write("AWDBK001", 0, "ascii");
  output.writeUInt32BE(wrapped.byteLength, 8);
  wrapped.copy(output, 12);
  Buffer.from(envelope).copy(output, 12 + wrapped.byteLength);
  return output;
}

function ipcHarness() {
  const handlers = new Map<string, (event: { sender: { id: number } }) => unknown>();
  return {
    ipcMain: {
      handle: (channel: string, handler: (event: { sender: { id: number } }) => unknown) => {
        handlers.set(channel, handler);
      },
      removeHandler: (channel: string) => handlers.delete(channel),
    },
    invoke: (channel: string, senderId: number) => {
      const handler = handlers.get(channel);
      if (!handler) throw new Error("IPC handler was not registered");
      return Promise.resolve(handler({ sender: { id: senderId } }));
    },
  };
}
