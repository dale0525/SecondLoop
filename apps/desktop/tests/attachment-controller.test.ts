// @vitest-environment node

import { describe, expect, it, vi } from "vitest";

import { registerAttachmentController } from "../src/main/attachmentController";
import { ATTACHMENT_PICK_IMPORT_CHANNEL } from "../src/shared/attachments";

const metadata = {
  id: "123e4567-e89b-12d3-a456-426614174000",
  fileName: "brief.pdf",
  mimeType: "application/pdf",
  sizeBytes: 4,
  sha256: "a".repeat(64),
  createdAt: "2026-07-14T10:00:00Z",
};

describe("trusted attachment controller", () => {
  it("reads a selected file in Main and returns metadata without its path", async () => {
    const harness = ipcHarness();
    const readFile = vi.fn(async () => new Uint8Array([1, 2, 3, 4]));
    const sidecarRequest = vi.fn(async () => new Response(JSON.stringify(metadata)));
    registerAttachmentController({
      ipcMain: harness.ipcMain,
      pickFile: async () => "/Users/local/Documents/brief.pdf",
      readFile,
      requesterWebContents: { id: 42 },
      sidecarRequest,
      uuid: () => "import-1",
    });

    await expect(harness.invoke({ sender: { id: 42 } })).resolves.toEqual(metadata);
    expect(readFile).toHaveBeenCalledWith("/Users/local/Documents/brief.pdf");
    expect(sidecarRequest).toHaveBeenCalledWith(
      "/foundation/attachments?fileName=brief.pdf",
      expect.objectContaining({
        headers: {
          "Content-Type": "application/pdf",
          "Idempotency-Key": "desktop-import-import-1",
        },
        method: "POST",
      }),
    );
    expect(JSON.stringify(await harness.invoke({ sender: { id: 42 } }))).not.toContain("/Users/");
  });

  it("returns null when selection is cancelled", async () => {
    const harness = ipcHarness();
    const readFile = vi.fn();
    const sidecarRequest = vi.fn();
    registerAttachmentController({
      ipcMain: harness.ipcMain,
      pickFile: async () => null,
      readFile,
      requesterWebContents: { id: 42 },
      sidecarRequest,
    });

    await expect(harness.invoke({ sender: { id: 42 } })).resolves.toBeNull();
    expect(readFile).not.toHaveBeenCalled();
    expect(sidecarRequest).not.toHaveBeenCalled();
  });

  it("rejects oversized bytes and calls from other renderer windows", async () => {
    const harness = ipcHarness();
    const sidecarRequest = vi.fn();
    registerAttachmentController({
      ipcMain: harness.ipcMain,
      pickFile: async () => "/private/large.bin",
      readFile: async () => new Uint8Array(16 * 1024 * 1024 + 1),
      requesterWebContents: { id: 42 },
      sidecarRequest,
    });

    await expect(harness.invoke({ sender: { id: 7 } })).rejects.toThrow(/requester window/);
    await expect(harness.invoke({ sender: { id: 42 } })).rejects.toThrow(/16 MiB/);
    expect(sidecarRequest).not.toHaveBeenCalled();
  });
});

function ipcHarness() {
  let handler: ((event: { sender: { id: number } }) => unknown) | null = null;
  return {
    ipcMain: {
      handle: (channel: string, next: typeof handler) => {
        expect(channel).toBe(ATTACHMENT_PICK_IMPORT_CHANNEL);
        handler = next;
      },
      removeHandler: () => undefined,
    },
    invoke: (event: { sender: { id: number } }) => {
      if (!handler) throw new Error("IPC handler was not registered");
      return Promise.resolve(handler(event));
    },
  };
}
