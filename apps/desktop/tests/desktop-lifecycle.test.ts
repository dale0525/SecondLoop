import { describe, expect, it, vi } from "vitest";

import {
  installDesktopLifecycle,
  type DesktopLifecycleEvent,
  type DesktopWindowScope,
} from "../src/main/desktopLifecycle";

describe("desktop host lifecycle", () => {
  it("recreates only the window scope on macOS activation", async () => {
    const harness = lifecycleHarness("darwin");
    const first = windowScope();
    const second = windowScope();
    harness.createWindowScope
      .mockResolvedValueOnce(first.scope)
      .mockResolvedValueOnce(second.scope);
    const lifecycle = harness.install();

    await lifecycle.ensureWindow();
    first.close();
    harness.emit("window-all-closed");

    expect(first.dispose).toHaveBeenCalledOnce();
    expect(harness.disposeHostScope).not.toHaveBeenCalled();
    expect(harness.quit).not.toHaveBeenCalled();

    harness.emit("activate");
    await flushMicrotasks();

    expect(harness.createWindowScope).toHaveBeenCalledTimes(2);
    expect(harness.disposeHostScope).not.toHaveBeenCalled();
    expect(second.dispose).not.toHaveBeenCalled();
  });

  it("focuses an existing window and coalesces concurrent creation", async () => {
    const harness = lifecycleHarness("darwin");
    let finishCreation: ((scope: DesktopWindowScope) => void) | undefined;
    harness.createWindowScope.mockImplementation(() => new Promise((resolve) => {
      finishCreation = resolve;
    }));
    const lifecycle = harness.install();

    const first = lifecycle.ensureWindow();
    harness.emit("activate");
    await flushMicrotasks();
    expect(harness.createWindowScope).toHaveBeenCalledOnce();

    const created = windowScope();
    finishCreation?.(created.scope);
    await first;
    harness.emit("activate");
    await flushMicrotasks();

    expect(harness.createWindowScope).toHaveBeenCalledOnce();
    expect(created.focus).toHaveBeenCalledOnce();
  });

  it("quits non-macOS hosts but disposes Host scope only at real exit", async () => {
    const harness = lifecycleHarness("win32");
    const created = windowScope();
    harness.createWindowScope.mockResolvedValue(created.scope);
    const lifecycle = harness.install();
    await lifecycle.ensureWindow();

    created.close();
    harness.emit("window-all-closed");
    expect(harness.quit).toHaveBeenCalledOnce();
    expect(harness.disposeHostScope).not.toHaveBeenCalled();

    harness.emit("before-quit");
    harness.emit("activate");
    await flushMicrotasks();
    expect(harness.createWindowScope).toHaveBeenCalledOnce();
    expect(harness.disposeHostScope).not.toHaveBeenCalled();

    harness.emit("will-quit");
    harness.emit("will-quit");
    expect(harness.disposeHostScope).toHaveBeenCalledOnce();
  });

  it("cleans a late window and reports retryable activation failures", async () => {
    const harness = lifecycleHarness("darwin");
    harness.createWindowScope.mockRejectedValueOnce(new Error("window failed"));
    const lifecycle = harness.install();

    harness.emit("activate");
    await flushMicrotasks();
    expect(harness.onError).toHaveBeenCalledWith(expect.objectContaining({
      message: "window failed",
    }));

    let finishCreation: ((scope: DesktopWindowScope) => void) | undefined;
    harness.createWindowScope.mockImplementationOnce(() => new Promise((resolve) => {
      finishCreation = resolve;
    }));
    harness.emit("activate");
    await flushMicrotasks();
    harness.emit("before-quit");
    const late = windowScope();
    finishCreation?.(late.scope);
    await flushMicrotasks();

    expect(late.dispose).toHaveBeenCalledOnce();
    expect(harness.disposeHostScope).not.toHaveBeenCalled();
  });
});

function lifecycleHarness(platform: NodeJS.Platform) {
  const listeners = new Map<DesktopLifecycleEvent, () => void>();
  const createWindowScope = vi.fn<() => Promise<DesktopWindowScope>>();
  const disposeHostScope = vi.fn();
  const onError = vi.fn();
  const quit = vi.fn();
  return {
    createWindowScope,
    disposeHostScope,
    emit: (event: DesktopLifecycleEvent) => listeners.get(event)?.(),
    install: () => installDesktopLifecycle({
      createWindowScope,
      disposeHostScope,
      on: (event, listener) => listeners.set(event, listener),
      onError,
      platform,
      quit,
      removeListener: (event, listener) => {
        if (listeners.get(event) === listener) listeners.delete(event);
      },
    }),
    onError,
    quit,
  };
}

function windowScope() {
  let closed: (() => void) | undefined;
  const dispose = vi.fn();
  const focus = vi.fn();
  const scope: DesktopWindowScope = {
    dispose,
    focus,
    isDestroyed: () => false,
    onClosed: (listener) => {
      closed = listener;
    },
  };
  return {
    close: () => closed?.(),
    dispose,
    focus,
    scope,
  };
}

async function flushMicrotasks(): Promise<void> {
  for (let index = 0; index < 8; index += 1) await Promise.resolve();
}
