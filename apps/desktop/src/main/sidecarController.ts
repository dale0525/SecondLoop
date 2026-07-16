import { chmodSync, mkdirSync } from "node:fs";

import {
  SIDECAR_ENSURE_RUNNING_CHANNEL,
  SIDECAR_STATUS_CHANNEL,
  SIDECAR_STATUS_SCHEMA_VERSION,
  type SidecarStatus,
} from "../shared/sidecarStatus";
import type { DesktopSidecarResolution } from "./sidecarRuntime";
import {
  DesktopSidecarSupervisor,
  normalizeSidecarRequestUrl,
  type SidecarRequest,
  type SidecarSupervisorOptions,
} from "./sidecarSupervisor";

type IpcEvent = { sender: { id: number } };

type IpcMainLike = {
  handle(channel: string, handler: (event: IpcEvent) => unknown): void;
  removeHandler(channel: string): void;
};

type SupervisorLike = Pick<
  DesktopSidecarSupervisor,
  "ensureRunning" | "request" | "start" | "status" | "stop"
>;

export type DesktopSidecarController = Readonly<{
  ensureRunning(): Promise<SidecarStatus>;
  request: SidecarRequest;
  start(): Promise<SidecarStatus>;
  status(): SidecarStatus;
  stop(): Promise<SidecarStatus>;
}>;

export type DesktopSidecarControllerDependencies = Readonly<{
  credentialVaultKey?: Buffer;
  dataProtectionKey?: Buffer;
  log?: SidecarSupervisorOptions["log"];
  prepareDirectory?: (directory: string) => void;
  supervisorFactory?: (options: SidecarSupervisorOptions) => SupervisorLike;
}>;

export function createDesktopSidecarController(
  resolution: DesktopSidecarResolution,
  dependencies: DesktopSidecarControllerDependencies = {},
): DesktopSidecarController {
  if (resolution.mode !== "managed") {
    return staticController(resolution);
  }

  try {
    const prepareDirectory = dependencies.prepareDirectory ?? preparePrivateDirectory;
    for (const directory of [
      resolution.dataRoot,
      resolution.cacheRoot,
      resolution.workspaceRoot,
    ]) {
      prepareDirectory(directory);
    }
    const createSupervisor = dependencies.supervisorFactory
      ?? ((options: SidecarSupervisorOptions) => new DesktopSidecarSupervisor(options));
    const supervisor = createSupervisor({
      args: [...resolution.args],
      command: resolution.command,
      cwd: resolution.cwd,
      env: resolution.env,
      log: dependencies.log,
      ...(dependencies.dataProtectionKey
        ? { dataProtectionKey: dependencies.dataProtectionKey }
        : {}),
      ...(dependencies.credentialVaultKey
        ? { credentialVaultKey: dependencies.credentialVaultKey }
        : {}),
    });
    return Object.freeze({
      ensureRunning: () => supervisor.ensureRunning(),
      request: (pathname, init) => supervisor.request(pathname, init),
      start: () => supervisor.start(),
      status: () => supervisor.status(),
      stop: () => supervisor.stop(),
    });
  } catch {
    return staticController({ mode: "unavailable", reason: "missing-executable" });
  }
}

export function registerSidecarController(options: {
  controller: DesktopSidecarController;
  ipcMain: IpcMainLike;
  requesterWebContents: { id: number };
}): () => void {
  const assertRequester = (event: IpcEvent) => {
    if (event.sender.id !== options.requesterWebContents.id) {
      throw new Error("Sidecar control is restricted to the requester window");
    }
  };
  options.ipcMain.handle(SIDECAR_STATUS_CHANNEL, (event) => {
    assertRequester(event);
    return options.controller.status();
  });
  options.ipcMain.handle(SIDECAR_ENSURE_RUNNING_CHANNEL, (event) => {
    assertRequester(event);
    return options.controller.ensureRunning();
  });
  return () => {
    options.ipcMain.removeHandler(SIDECAR_STATUS_CHANNEL);
    options.ipcMain.removeHandler(SIDECAR_ENSURE_RUNNING_CHANNEL);
  };
}

export function installSidecarShutdownGate(options: {
  app: {
    on(event: "before-quit", listener: (event: { preventDefault(): void }) => void): void;
    quit(): void;
    removeListener(event: "before-quit", listener: (event: { preventDefault(): void }) => void): void;
  };
  controller: Pick<DesktopSidecarController, "stop">;
  onError?: (error: unknown) => void;
}): () => void {
  let stopped = false;
  let stopping: Promise<void> | null = null;
  const beforeQuit = (event: { preventDefault(): void }) => {
    if (stopped) return;
    event.preventDefault();
    if (stopping) return;
    stopping = Promise.resolve()
      .then(() => options.controller.stop())
      .catch((error) => options.onError?.(error))
      .then(() => {
        stopped = true;
        options.app.quit();
      });
  };
  options.app.on("before-quit", beforeQuit);
  return () => options.app.removeListener("before-quit", beforeQuit);
}

function staticController(
  resolution: Extract<DesktopSidecarResolution, { mode: "external" | "unavailable" }>,
): DesktopSidecarController {
  const mode = resolution.mode;
  const status = Object.freeze<SidecarStatus>({
    schemaVersion: SIDECAR_STATUS_SCHEMA_VERSION,
    mode,
    state: mode,
    attempt: 0,
    canEnsureRunning: false,
    lastExit: null,
  });
  return Object.freeze({
    ensureRunning: async () => status,
    request: mode === "external"
      ? externalRequest(resolution.baseUrl, resolution.transportToken)
      : async () => Promise.reject(new Error("Desktop sidecar is unavailable")),
    start: async () => status,
    status: () => status,
    stop: async () => status,
  });
}

function externalRequest(baseUrl: string, transportToken: string | null): SidecarRequest {
  return (pathname, init = {}) => {
    let url: URL;
    try {
      url = normalizeSidecarRequestUrl(new URL(baseUrl).origin, pathname);
    } catch {
      return Promise.reject(new Error("Sidecar request path is not allowed"));
    }
    const headers = new Headers(init.headers);
    headers.delete("cookie");
    if (transportToken) headers.set("X-AgentWeave-Transport", transportToken);
    return fetch(url, {
      ...init,
      credentials: "omit",
      headers,
      redirect: "error",
    });
  };
}

function preparePrivateDirectory(directory: string): void {
  mkdirSync(directory, { mode: 0o700, recursive: true });
  if (process.platform !== "win32") chmodSync(directory, 0o700);
}
