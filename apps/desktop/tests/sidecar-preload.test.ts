import { ipcRenderer } from "electron";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { desktopPreloadApi } from "../src/preload";
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
});
