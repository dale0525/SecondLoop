export type DesktopLifecycleEvent =
  | "activate"
  | "before-quit"
  | "will-quit"
  | "window-all-closed";

export type DesktopWindowScope = Readonly<{
  dispose(): void;
  focus(): void;
  isDestroyed(): boolean;
  onClosed(listener: () => void): void;
}>;

export type DesktopLifecycle = Readonly<{
  dispose(): void;
  ensureWindow(): Promise<void>;
}>;

export type DesktopLifecycleOptions = Readonly<{
  createWindowScope(): DesktopWindowScope | Promise<DesktopWindowScope>;
  disposeHostScope(): void;
  on(event: DesktopLifecycleEvent, listener: () => void): void;
  onError?(error: unknown): void;
  platform: NodeJS.Platform;
  quit(): void;
  removeListener(event: DesktopLifecycleEvent, listener: () => void): void;
}>;

export function installDesktopLifecycle(
  options: DesktopLifecycleOptions,
): DesktopLifecycle {
  let activeWindow: DesktopWindowScope | null = null;
  let creatingWindow: Promise<void> | null = null;
  let disposed = false;
  let hostDisposed = false;
  let quitting = false;

  const disposeHost = () => {
    if (hostDisposed) return;
    hostDisposed = true;
    options.disposeHostScope();
  };
  const releaseWindow = (scope: DesktopWindowScope) => {
    if (activeWindow !== scope) return;
    activeWindow = null;
    scope.dispose();
  };
  const ensureWindow = async () => {
    if (disposed || quitting) return;
    if (activeWindow) {
      if (!activeWindow.isDestroyed()) {
        activeWindow.focus();
        return;
      }
      releaseWindow(activeWindow);
    }
    if (creatingWindow) return creatingWindow;

    const creation = Promise.resolve()
      .then(() => options.createWindowScope())
      .then((scope) => {
        if (disposed || quitting || scope.isDestroyed()) {
          scope.dispose();
          return;
        }
        activeWindow = scope;
        scope.onClosed(() => releaseWindow(scope));
      })
      .finally(() => {
        if (creatingWindow === creation) creatingWindow = null;
      });
    creatingWindow = creation;
    return creation;
  };
  const activate = () => {
    void ensureWindow().catch((error) => options.onError?.(error));
  };
  const beforeQuit = () => {
    quitting = true;
  };
  const willQuit = () => {
    quitting = true;
    if (activeWindow) releaseWindow(activeWindow);
    disposeHost();
  };
  const windowAllClosed = () => {
    if (options.platform !== "darwin") options.quit();
  };

  options.on("activate", activate);
  options.on("before-quit", beforeQuit);
  options.on("will-quit", willQuit);
  options.on("window-all-closed", windowAllClosed);

  return Object.freeze({
    dispose: () => {
      if (disposed) return;
      disposed = true;
      quitting = true;
      options.removeListener("activate", activate);
      options.removeListener("before-quit", beforeQuit);
      options.removeListener("will-quit", willQuit);
      options.removeListener("window-all-closed", windowAllClosed);
      if (activeWindow) releaseWindow(activeWindow);
      disposeHost();
    },
    ensureWindow,
  });
}
