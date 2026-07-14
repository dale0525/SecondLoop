import { afterEach, describe, expect, it, vi } from "vitest";

import {
  createDesktopSidecarController,
  installSidecarShutdownGate,
  registerSidecarController,
} from "../src/main/sidecarController";
import type { ManagedSidecarResolution } from "../src/main/sidecarRuntime";
import {
  SIDECAR_ENSURE_RUNNING_CHANNEL,
  SIDECAR_STATUS_CHANNEL,
  SIDECAR_STATUS_SCHEMA_VERSION,
  type SidecarStatus,
} from "../src/shared/sidecarStatus";

const readyStatus = Object.freeze<SidecarStatus>({
  schemaVersion: SIDECAR_STATUS_SCHEMA_VERSION,
  mode: "managed",
  state: "ready",
  attempt: 1,
  canEnsureRunning: false,
  lastExit: null,
});

afterEach(() => vi.unstubAllGlobals());

describe("desktop sidecar controller", () => {
  it("prepares managed directories and delegates lifecycle operations", async () => {
    const prepareDirectory = vi.fn();
    const supervisor = {
      ensureRunning: vi.fn(async () => readyStatus),
      request: vi.fn(async () => new Response("ok")),
      start: vi.fn(async () => readyStatus),
      status: vi.fn(() => readyStatus),
      stop: vi.fn(async () => readyStatus),
    };
    const supervisorFactory = vi.fn(() => supervisor);
    const controller = createDesktopSidecarController(managedResolution(), {
      prepareDirectory,
      supervisorFactory,
    });

    expect(prepareDirectory.mock.calls.map(([directory]) => directory)).toEqual([
      "/user/sidecar/data",
      "/user/sidecar/cache",
      "/user/sidecar/workspace",
    ]);
    expect(supervisorFactory).toHaveBeenCalledWith(expect.objectContaining({
      command: "/app/agent-server",
      cwd: "/app",
    }));
    await expect(controller.start()).resolves.toBe(readyStatus);
    await expect(controller.ensureRunning()).resolves.toBe(readyStatus);
    await expect(controller.stop()).resolves.toBe(readyStatus);
  });

  it("never creates or stops an owned process in external mode", async () => {
    const supervisorFactory = vi.fn();
    const controller = createDesktopSidecarController({
      baseUrl: "https://sidecar.example.test/",
      mode: "external",
      transportToken: null,
    }, { supervisorFactory });

    await expect(controller.start()).resolves.toMatchObject({
      mode: "external",
      state: "external",
    });
    await expect(controller.stop()).resolves.toMatchObject({ state: "external" });
    expect(supervisorFactory).not.toHaveBeenCalled();
  });

  it("requires Main-owned transport authentication for a trusted external server", async () => {
    const fetchMock = vi.fn(async (_url: URL, _init: RequestInit = {}) => new Response("ok"));
    vi.stubGlobal("fetch", fetchMock);
    const controller = createDesktopSidecarController({
      baseUrl: "https://sidecar.example.test/",
      mode: "external",
      transportToken: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ",
    });

    await controller.request("/health");

    const [url, init] = fetchMock.mock.calls[0];
    expect(String(url)).toBe("https://sidecar.example.test/health");
    expect(new Headers(init!.headers).get("X-AgentWeave-Transport"))
      .toBe("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ");
  });

  it("restricts status and recovery IPC to the requester web contents", async () => {
    const handlers = new Map<string, (event: { sender: { id: number } }) => unknown>();
    const ipcMain = {
      handle: vi.fn((channel: string, handler: (event: { sender: { id: number } }) => unknown) => {
        handlers.set(channel, handler);
      }),
      removeHandler: vi.fn((channel: string) => handlers.delete(channel)),
    };
    const controller = {
      ensureRunning: vi.fn(async () => readyStatus),
      request: vi.fn(async () => new Response("ok")),
      start: vi.fn(async () => readyStatus),
      status: vi.fn(() => readyStatus),
      stop: vi.fn(async () => readyStatus),
    };
    const dispose = registerSidecarController({
      controller,
      ipcMain,
      requesterWebContents: { id: 42 },
    });

    expect(handlers.get(SIDECAR_STATUS_CHANNEL)?.({ sender: { id: 42 } })).toBe(readyStatus);
    await expect(handlers.get(SIDECAR_ENSURE_RUNNING_CHANNEL)?.({
      sender: { id: 42 },
    })).resolves.toBe(readyStatus);
    expect(() => handlers.get(SIDECAR_STATUS_CHANNEL)?.({ sender: { id: 7 } }))
      .toThrow("Sidecar control is restricted to the requester window");
    dispose();
    expect(handlers).toHaveProperty("size", 0);
  });

  it("gates app quit on one bounded controller stop operation", async () => {
    const harness: {
      beforeQuit?: (event: { preventDefault(): void }) => void;
      finishStop?: () => void;
    } = {};
    const stop = vi.fn(() => new Promise<SidecarStatus>((resolve) => {
      harness.finishStop = () => resolve(readyStatus);
    }));
    const app = {
      on: vi.fn((_event: "before-quit", listener: NonNullable<typeof harness.beforeQuit>) => {
        harness.beforeQuit = listener;
      }),
      quit: vi.fn(),
      removeListener: vi.fn(),
    };
    installSidecarShutdownGate({ app, controller: { stop } });
    const firstEvent = { preventDefault: vi.fn() };
    const secondEvent = { preventDefault: vi.fn() };

    harness.beforeQuit?.(firstEvent);
    harness.beforeQuit?.(secondEvent);
    await flushMicrotasks();
    expect(firstEvent.preventDefault).toHaveBeenCalledOnce();
    expect(secondEvent.preventDefault).toHaveBeenCalledOnce();
    expect(stop).toHaveBeenCalledOnce();
    expect(app.quit).not.toHaveBeenCalled();

    harness.finishStop?.();
    await flushMicrotasks();
    expect(app.quit).toHaveBeenCalledOnce();

    const finalEvent = { preventDefault: vi.fn() };
    harness.beforeQuit?.(finalEvent);
    expect(finalEvent.preventDefault).not.toHaveBeenCalled();
  });
});

function managedResolution(): ManagedSidecarResolution {
  return {
    args: [],
    cacheRoot: "/user/sidecar/cache",
    command: "/app/agent-server",
    cwd: "/app",
    dataRoot: "/user/sidecar/data",
    env: { PATH: "/usr/bin" },
    mode: "managed",
    workspaceRoot: "/user/sidecar/workspace",
  };
}

async function flushMicrotasks(): Promise<void> {
  for (let index = 0; index < 8; index += 1) await Promise.resolve();
}
