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
  "ensureRunning" | "request" | "shutdown" | "start" | "status" | "stop"
>;

export type DesktopSidecarController = Readonly<{
  ensureRunning(): Promise<SidecarStatus>;
  provisionLaunchKeys(keys: DesktopSidecarLaunchKeys): Promise<SidecarStatus>;
  request: SidecarRequest;
  shutdown(): Promise<SidecarStatus>;
  start(): Promise<SidecarStatus>;
  status(): SidecarStatus;
  stop(): Promise<SidecarStatus>;
}>;

export type DesktopSidecarLaunchKeys = Readonly<{
  backupKey?: Buffer;
  credentialVaultKey?: Buffer;
  storageProtectionKey?: Buffer;
}>;

export type DesktopSidecarControllerDependencies = Readonly<{
  backupKey?: Buffer;
  credentialVaultKey?: Buffer;
  log?: SidecarSupervisorOptions["log"];
  prepareDirectory?: (directory: string) => void;
  storageProtectionKey?: Buffer;
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
    const launchKeys: {
      backupKey: Buffer | null;
      credentialVaultKey: Buffer | null;
      storageProtectionKey: Buffer | null;
    } = {
      backupKey: copyLaunchKey(dependencies.backupKey, "backup"),
      credentialVaultKey: copyLaunchKey(dependencies.credentialVaultKey, "credential Vault"),
      storageProtectionKey: copyLaunchKey(dependencies.storageProtectionKey, "storage protection"),
    };
    const create = () => createSupervisor({
      args: [...resolution.args],
      command: resolution.command,
      cwd: resolution.cwd,
      env: resolution.env,
      log: dependencies.log,
      ...(launchKeys.backupKey ? { backupKey: launchKeys.backupKey } : {}),
      ...(launchKeys.credentialVaultKey
        ? { credentialVaultKey: launchKeys.credentialVaultKey }
        : {}),
      ...(launchKeys.storageProtectionKey
        ? { storageProtectionKey: launchKeys.storageProtectionKey }
        : {}),
    });
    let supervisor = create();
    let transition = Promise.resolve();
    let activeRequests = 0;
    const idleWaiters = new Set<() => void>();
    const waitForRequests = () => activeRequests === 0
      ? Promise.resolve()
      : new Promise<void>((resolve) => idleWaiters.add(resolve));
    const exclusive = <T>(operation: () => Promise<T>): Promise<T> => {
      const result = transition.then(operation);
      transition = result.then(() => undefined, () => undefined);
      return result;
    };
    const request: SidecarRequest = (pathname, init) => {
      const gate = transition;
      return gate.then(async () => {
        activeRequests += 1;
        const active = supervisor;
        try {
          return await active.request(pathname, init);
        } finally {
          activeRequests -= 1;
          if (activeRequests === 0) {
            for (const resolve of idleWaiters) resolve();
            idleWaiters.clear();
          }
        }
      });
    };
    return Object.freeze({
      ensureRunning: () => exclusive(() => supervisor.ensureRunning()),
      provisionLaunchKeys: (keys) => exclusive(async () => {
        const updates = validatedLaunchKeyUpdates(keys, launchKeys);
        if (Object.keys(updates).length === 0) {
          const status = await supervisor.ensureRunning();
          if (status.state !== "ready") throw new Error("Sidecar security provisioning failed");
          return status;
        }
        let retained = false;
        try {
          await waitForRequests();
          await supervisor.stop();
          for (const [name, key] of Object.entries(updates) as Array<
            [keyof typeof launchKeys, Buffer]
          >) {
            launchKeys[name] = key;
          }
          retained = true;
          supervisor = create();
          const status = await supervisor.start();
          if (status.state !== "ready") throw new Error("Sidecar security provisioning failed");
          return status;
        } finally {
          if (!retained) {
            for (const key of Object.values(updates)) key?.fill(0);
          }
        }
      }),
      request,
      shutdown: () => exclusive(async () => {
        await waitForRequests();
        try {
          return await supervisor.shutdown();
        } finally {
          launchKeys.backupKey?.fill(0);
          launchKeys.credentialVaultKey?.fill(0);
          launchKeys.storageProtectionKey?.fill(0);
        }
      }),
      start: () => exclusive(() => supervisor.start()),
      status: () => supervisor.status(),
      stop: () => exclusive(async () => {
        await waitForRequests();
        return supervisor.stop();
      }),
    });
  } catch {
    return staticController({ mode: "unavailable", reason: "missing-executable" });
  }
}

export function registerSidecarController(options: {
  controller: Pick<DesktopSidecarController, "ensureRunning" | "status">;
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
  controller: Pick<DesktopSidecarController, "shutdown">;
  onError?: (error: unknown) => void;
}): () => void {
  let stopped = false;
  let stopping: Promise<void> | null = null;
  const beforeQuit = (event: { preventDefault(): void }) => {
    if (stopped) return;
    event.preventDefault();
    if (stopping) return;
    stopping = Promise.resolve()
      .then(() => options.controller.shutdown())
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
    provisionLaunchKeys: async () => {
      throw new Error("Managed sidecar is required for local security provisioning");
    },
    request: mode === "external"
      ? externalRequest(resolution.baseUrl, resolution.transportToken)
      : async () => Promise.reject(new Error("Desktop sidecar is unavailable")),
    shutdown: async () => status,
    start: async () => status,
    status: () => status,
    stop: async () => status,
  });
}

function copyLaunchKey(value: Buffer | undefined, label: string): Buffer | null {
  if (!value) return null;
  if (value.byteLength !== 32) throw new Error(`Sidecar ${label} key must be 32 bytes`);
  return Buffer.from(value);
}

function validatedLaunchKeyUpdates(
  input: DesktopSidecarLaunchKeys,
  current: {
    backupKey: Buffer | null;
    credentialVaultKey: Buffer | null;
    storageProtectionKey: Buffer | null;
  },
): Partial<Record<keyof typeof current, Buffer>> {
  for (const [name, label] of [
    ["backupKey", "backup"],
    ["credentialVaultKey", "credential Vault"],
    ["storageProtectionKey", "storage protection"],
  ] as const) {
    const supplied = input[name];
    if (!supplied) continue;
    if (supplied.byteLength !== 32) throw new Error(`Sidecar ${label} key must be 32 bytes`);
    if (current[name]) {
      if (!current[name].equals(supplied)) {
        throw new Error(`Sidecar ${label} key cannot change during the host lifetime`);
      }
      continue;
    }
  }
  const updates: Partial<Record<keyof typeof current, Buffer>> = {};
  for (const name of ["backupKey", "credentialVaultKey", "storageProtectionKey"] as const) {
    const supplied = input[name];
    if (supplied && !current[name]) updates[name] = Buffer.from(supplied);
  }
  return updates;
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
