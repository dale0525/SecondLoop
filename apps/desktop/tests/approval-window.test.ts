// @vitest-environment node

import { describe, expect, it, vi } from "vitest";

import { registerApprovalWindowController } from "../src/main/approvalWindow";
import { getElectronBuildConfig } from "../vite.electron.config";
import rendererConfig from "../vite.config";

const APPROVAL_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";

describe("independent approval window", () => {
  it("preserves runtime credentials and file-safe renderer assets in production bundles", () => {
    expect(getElectronBuildConfig("electron-main")).toMatchObject({
      define: { "process.env": "process.env" },
      build: {
        emptyOutDir: true,
        rollupOptions: { output: { entryFileNames: "main.cjs" } },
      },
    });
    expect(getElectronBuildConfig("electron-preload")).toMatchObject({
      build: {
        emptyOutDir: false,
        rollupOptions: {
          output: {
            entryFileNames: "preload.cjs",
            inlineDynamicImports: true,
          },
        },
      },
    });
    expect(rendererConfig).toMatchObject({ base: "./" });
  });

  it("binds open and completion IPC to separate web contents", async () => {
    const requester = fakeWebContents(11);
    const attacker = fakeWebContents(12);
    const approval = new FakeWindow(21);
    const handlers = new Map<string, (event: { sender: FakeWebContents }, value: unknown) => unknown>();
    const ipcMain = {
      handle: vi.fn((channel: string, handler: (event: { sender: FakeWebContents }, value: unknown) => unknown) => {
        handlers.set(channel, handler);
      }),
      removeHandler: vi.fn()
    };
    const createWindow = vi.fn(() => approval);

    registerApprovalWindowController({
      approvalPreload: "/app/dist-electron/approval-preload.cjs",
      approvalUrl: "http://127.0.0.1:4173/approval.html",
      createWindow,
      ipcMain,
      requesterWebContents: requester
    });

    const open = handlers.get("agentweave:approval:open")!;
    const complete = handlers.get("agentweave:approval:complete")!;
    await expect(open({ sender: attacker }, APPROVAL_ID)).rejects.toThrow(/requester window/);

    const observed = open({ sender: requester }, APPROVAL_ID) as Promise<unknown>;
    expect(createWindow).toHaveBeenCalledWith(expect.objectContaining({
      modal: true,
      webPreferences: {
        contextIsolation: true,
        nodeIntegration: false,
        preload: "/app/dist-electron/approval-preload.cjs",
        sandbox: true
      }
    }));
    expect(approval.loadedUrl).toBe(
      `http://127.0.0.1:4173/approval.html?approvalId=${APPROVAL_ID}`
    );
    expect(approval.webContents.openHandler).toBeTypeOf("function");
    expect(approval.webContents.openHandler!()).toEqual({ action: "deny" });

    expect(() => complete(
      { sender: requester },
      { approvalId: APPROVAL_ID, decision: "approve" }
    )).toThrow(/approval window/);
    await complete(
      { sender: approval.webContents },
      { approvalId: APPROVAL_ID, decision: "approve" }
    );
    await expect(observed).resolves.toEqual({
      approvalId: APPROVAL_ID,
      decision: "approve",
      status: "completed"
    });
    expect(approval.closed).toBe(true);
  });

  it("treats closing the isolated window as observation-only cancellation", async () => {
    const requester = fakeWebContents(31);
    const approval = new FakeWindow(41);
    const handlers = new Map<string, (event: { sender: FakeWebContents }, value: unknown) => unknown>();
    registerApprovalWindowController({
      approvalPreload: "/approval-preload.cjs",
      approvalUrl: "file:///app/approval.html",
      createWindow: () => approval,
      ipcMain: {
        handle: (channel, handler) => handlers.set(channel, handler),
        removeHandler: () => undefined
      },
      requesterWebContents: requester
    });

    const observed = handlers.get("agentweave:approval:open")!(
      { sender: requester },
      APPROVAL_ID
    ) as Promise<unknown>;
    const close = handlers.get("agentweave:approval:close")!;
    await expect(close({ sender: requester }, APPROVAL_ID)).rejects.toThrow(/approval window/);
    await expect(close({ sender: approval.webContents }, APPROVAL_ID)).resolves.toEqual({
      accepted: true
    });

    await expect(observed).resolves.toEqual({
      approvalId: APPROVAL_ID,
      status: "closed"
    });
    expect(approval.closed).toBe(true);
    expect(approval.destroyed).toBe(true);
  });

  it("returns a load_failed observation instead of completing the approval", async () => {
    const requester = fakeWebContents(51);
    const approval = new FakeWindow(61);
    approval.loadError = new Error("renderer failed to load");
    const handlers = new Map<string, (event: { sender: FakeWebContents }, value: unknown) => unknown>();
    registerApprovalWindowController({
      approvalPreload: "/approval-preload.cjs",
      approvalUrl: "file:///app/approval.html",
      createWindow: () => approval,
      ipcMain: {
        handle: (channel, handler) => handlers.set(channel, handler),
        removeHandler: () => undefined
      },
      requesterWebContents: requester
    });

    const observed = handlers.get("agentweave:approval:open")!(
      { sender: requester },
      APPROVAL_ID
    ) as Promise<unknown>;

    await expect(observed).resolves.toEqual({
      approvalId: APPROVAL_ID,
      status: "load_failed"
    });
  });
});

type FakeWebContents = {
  id: number;
  openHandler?: () => { action: "deny" };
  on: ReturnType<typeof vi.fn>;
  setWindowOpenHandler(handler: () => { action: "deny" }): void;
};

function fakeWebContents(id: number): FakeWebContents {
  return {
    id,
    on: vi.fn(),
    setWindowOpenHandler(handler) {
      this.openHandler = handler;
    }
  };
}

class FakeWindow {
  private readonly contents: FakeWebContents;
  readonly listeners = new Map<string, () => void>();
  closed = false;
  destroyed = false;
  loadError: Error | null = null;
  loadedUrl = "";

  constructor(id: number) {
    this.contents = fakeWebContents(id);
  }

  get webContents(): FakeWebContents {
    if (this.destroyed) throw new TypeError("Object has been destroyed");
    return this.contents;
  }

  close(): void {
    this.closed = true;
    this.emit("closed");
  }

  destroy(): void {
    this.destroyed = true;
    this.closed = true;
    this.emit("closed");
  }

  isDestroyed(): boolean {
    return this.closed;
  }

  loadURL(url: string): Promise<void> {
    this.loadedUrl = url;
    return this.loadError ? Promise.reject(this.loadError) : Promise.resolve();
  }

  on(event: string, listener: () => void): void {
    this.listeners.set(event, listener);
  }

  emit(event: string): void {
    this.listeners.get(event)?.();
  }
}
