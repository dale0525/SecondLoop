import { ipcRenderer } from "electron";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { desktopPreloadApi } from "../src/preload";
import { ATTACHMENT_PICK_IMPORT_CHANNEL } from "../src/shared/attachments";
import {
  DATA_PROTECTION_EXPORT_CHANNEL,
  DATA_PROTECTION_RESTORE_CHANNEL,
  DATA_PROTECTION_STATUS_CHANNEL,
} from "../src/shared/dataProtection";
import { SIDECAR_API_REQUEST_CHANNEL } from "../src/shared/sidecarApi";
import {
  SIDECAR_ENSURE_RUNNING_CHANNEL,
  SIDECAR_STATUS_CHANNEL,
} from "../src/shared/sidecarStatus";

vi.mock("electron", () => ({
  contextBridge: { exposeInMainWorld: vi.fn() },
  ipcRenderer: { invoke: vi.fn() },
}));

describe("sidecar preload capability", () => {
  beforeEach(() => vi.mocked(ipcRenderer.invoke).mockReset());

  it("exposes only no-argument status and recovery calls with parsed results", async () => {
    vi.mocked(ipcRenderer.invoke).mockResolvedValue({
      schemaVersion: 1,
      mode: "managed",
      state: "ready",
      attempt: 1,
      canEnsureRunning: false,
      lastExit: null,
    });

    await expect(desktopPreloadApi.sidecar.status()).resolves.toMatchObject({ state: "ready" });
    await expect(desktopPreloadApi.sidecar.ensureRunning()).resolves.toMatchObject({ state: "ready" });
    expect(ipcRenderer.invoke).toHaveBeenNthCalledWith(1, SIDECAR_STATUS_CHANNEL);
    expect(ipcRenderer.invoke).toHaveBeenNthCalledWith(2, SIDECAR_ENSURE_RUNNING_CHANNEL);
    expect(Object.keys(desktopPreloadApi.sidecar).sort()).toEqual(["ensureRunning", "status"]);
  });

  it("rejects malformed Main-process status values", async () => {
    vi.mocked(ipcRenderer.invoke).mockResolvedValue({
      schemaVersion: 1,
      mode: "managed",
      state: "ready",
      attempt: 1,
      canEnsureRunning: false,
      lastExit: null,
      executable: "/secret/path",
    });

    await expect(desktopPreloadApi.sidecar.status()).rejects.toThrow(
      "Sidecar status contains unknown fields",
    );

    vi.mocked(ipcRenderer.invoke).mockResolvedValue({
      schemaVersion: 1,
      mode: "external",
      state: "ready",
      attempt: 0,
      canEnsureRunning: false,
      lastExit: null,
    });
    await expect(desktopPreloadApi.sidecar.status()).rejects.toThrow(
      "Sidecar mode and state are inconsistent",
    );
  });

  it("forwards typed task operations without exposing an arbitrary path", async () => {
    vi.mocked(ipcRenderer.invoke).mockResolvedValue({ tasks: [], nextCursor: null });

    await expect(desktopPreloadApi.server.request("tasks.list", {
      status: "open",
      limit: 25,
    })).resolves.toEqual({ tasks: [], nextCursor: null });
    expect(ipcRenderer.invoke).toHaveBeenCalledWith(SIDECAR_API_REQUEST_CHANNEL, {
      operation: "tasks.list",
      input: { status: "open", limit: 25 },
    });
    expect(Object.keys(desktopPreloadApi.server)).toEqual(["request"]);
  });

  it("exposes trusted attachment selection as metadata only", async () => {
    const metadata = {
      id: "123e4567-e89b-12d3-a456-426614174000",
      fileName: "brief.pdf",
      mimeType: "application/pdf",
      sizeBytes: 4,
      sha256: "a".repeat(64),
      createdAt: "2026-07-14T10:00:00Z",
    };
    vi.mocked(ipcRenderer.invoke).mockResolvedValue(metadata);

    await expect(desktopPreloadApi.attachments.pickAndImport()).resolves.toEqual(metadata);
    expect(ipcRenderer.invoke).toHaveBeenCalledWith(ATTACHMENT_PICK_IMPORT_CHANNEL);
    expect(Object.keys(desktopPreloadApi.attachments)).toEqual(["pickAndImport"]);
  });

  it("exposes data protection operations without paths or raw bytes", async () => {
    const status = {
      enabled: true,
      atRestEncryption: "configured",
      backupEncryption: "aes-256-gcm",
      backupFormat: "agentweave-backup-v1",
      pendingRestart: false,
      restoreRollbackAvailable: false,
    };
    vi.mocked(ipcRenderer.invoke)
      .mockResolvedValueOnce(status)
      .mockResolvedValueOnce(null)
      .mockResolvedValueOnce(null);

    await expect(desktopPreloadApi.dataProtection.status()).resolves.toEqual(status);
    await expect(desktopPreloadApi.dataProtection.exportBackup()).resolves.toBeNull();
    await expect(desktopPreloadApi.dataProtection.restoreBackup()).resolves.toBeNull();
    expect(ipcRenderer.invoke).toHaveBeenNthCalledWith(1, DATA_PROTECTION_STATUS_CHANNEL);
    expect(ipcRenderer.invoke).toHaveBeenNthCalledWith(2, DATA_PROTECTION_EXPORT_CHANNEL);
    expect(ipcRenderer.invoke).toHaveBeenNthCalledWith(3, DATA_PROTECTION_RESTORE_CHANNEL);
    expect(Object.keys(desktopPreloadApi.dataProtection).sort()).toEqual([
      "exportBackup",
      "restoreBackup",
      "status",
    ]);

    vi.mocked(ipcRenderer.invoke).mockResolvedValue({
      ...status,
      atRestEncryption: "encrypted",
    });
    await expect(desktopPreloadApi.dataProtection.status()).rejects.toThrow(
      "Data protection status is invalid",
    );
  });
});
