import {
  spawn as spawnChild,
  type ChildProcess,
  type SpawnOptions,
} from "node:child_process";
import { randomBytes, randomUUID } from "node:crypto";
import type { Readable, Writable } from "node:stream";

import {
  SIDECAR_STATUS_SCHEMA_VERSION,
  type SidecarStatus,
  type SidecarState,
} from "../shared/sidecarStatus";

type SidecarChild = ChildProcess & {
  stderr: Readable;
  stdin: null;
  stdio: [null, Readable, Readable, Writable, Readable];
  stdout: Readable;
};

type SidecarSpawnOptions = SpawnOptions & {
  stdio: ["ignore", "pipe", "pipe", "pipe", "pipe"];
};

export type SidecarSpawn = (
  command: string,
  args: string[],
  options: SidecarSpawnOptions,
) => SidecarChild;

export type SidecarSupervisorOptions = {
  args?: string[];
  backupKey?: Buffer;
  command: string;
  credentialVaultKey?: Buffer;
  cwd: string;
  env: NodeJS.ProcessEnv;
  fetchImpl?: typeof fetch;
  healthPollMs?: number;
  healthTimeoutMs?: number;
  log?: (stream: "stderr" | "stdout", message: string) => void;
  maxUnexpectedExits?: number;
  now?: () => number;
  restartBackoffMs?: number;
  restartWindowMs?: number;
  shutdownTimeoutMs?: number;
  spawnImpl?: SidecarSpawn;
  startupTimeoutMs?: number;
  storageProtectionKey?: Buffer;
  wait?: (milliseconds: number) => Promise<void>;
};

export type SidecarRequest = (
  pathname: string,
  init?: RequestInit,
) => Promise<Response>;

const DEFAULT_STARTUP_TIMEOUT_MS = 15_000;
const DEFAULT_HEALTH_POLL_MS = 100;
const DEFAULT_HEALTH_TIMEOUT_MS = 1_000;
const DEFAULT_SHUTDOWN_TIMEOUT_MS = 5_000;
const DEFAULT_RESTART_WINDOW_MS = 60_000;
const DEFAULT_RESTART_BACKOFF_MS = 250;
const DEFAULT_MAX_UNEXPECTED_EXITS = 3;
const LAUNCH_CONFIG_FD = 3;
const LAUNCH_RESULT_FD = 4;
const MAX_HANDSHAKE_BYTES = 4_096;
const TRANSPORT_HEADER = "X-AgentWeave-Transport";

type ActiveTransport = {
  generation: number;
  origin: string;
  token: Buffer;
};

export class DesktopSidecarSupervisor {
  private readonly options: Required<Omit<SidecarSupervisorOptions, "args" | "backupKey" | "credentialVaultKey" | "fetchImpl" | "log" | "now" | "spawnImpl" | "storageProtectionKey" | "wait">> & Pick<SidecarSupervisorOptions, "log"> & {
    args: string[];
    backupKey: Buffer | null;
    credentialVaultKey: Buffer | null;
    fetchImpl: typeof fetch;
    now: () => number;
    spawnImpl: SidecarSpawn;
    storageProtectionKey: Buffer | null;
    wait: (milliseconds: number) => Promise<void>;
  };
  private state: SidecarState = "idle";
  private attempt = 0;
  private child: SidecarChild | null = null;
  private generation = 0;
  private lastExit: SidecarStatus["lastExit"] = null;
  private launchOperation: Promise<SidecarStatus> | null = null;
  private stopOperation: Promise<SidecarStatus> | null = null;
  private readonly childExitOperations = new WeakMap<SidecarChild, Promise<void>>();
  private readonly childExitResolvers = new WeakMap<SidecarChild, () => void>();
  private readonly intentionalChildren = new WeakSet<SidecarChild>();
  private readonly handledChildren = new WeakSet<SidecarChild>();
  private readonly readyChildren = new WeakSet<SidecarChild>();
  private shutdownRequested = false;
  private unexpectedExitTimes: number[] = [];
  private transport: ActiveTransport | null = null;

  constructor(options: SidecarSupervisorOptions) {
    this.options = {
      command: options.command,
      args: [...(options.args ?? [])],
      backupKey: options.backupKey
        ? Buffer.from(options.backupKey)
        : null,
      credentialVaultKey: options.credentialVaultKey
        ? Buffer.from(options.credentialVaultKey)
        : null,
      storageProtectionKey: options.storageProtectionKey
        ? Buffer.from(options.storageProtectionKey)
        : null,
      cwd: options.cwd,
      env: { ...options.env },
      startupTimeoutMs: options.startupTimeoutMs ?? DEFAULT_STARTUP_TIMEOUT_MS,
      healthPollMs: options.healthPollMs ?? DEFAULT_HEALTH_POLL_MS,
      healthTimeoutMs: options.healthTimeoutMs ?? DEFAULT_HEALTH_TIMEOUT_MS,
      shutdownTimeoutMs: options.shutdownTimeoutMs ?? DEFAULT_SHUTDOWN_TIMEOUT_MS,
      restartWindowMs: options.restartWindowMs ?? DEFAULT_RESTART_WINDOW_MS,
      restartBackoffMs: options.restartBackoffMs ?? DEFAULT_RESTART_BACKOFF_MS,
      maxUnexpectedExits: options.maxUnexpectedExits ?? DEFAULT_MAX_UNEXPECTED_EXITS,
      fetchImpl: options.fetchImpl ?? fetch,
      spawnImpl: options.spawnImpl ?? defaultSpawn,
      now: options.now ?? Date.now,
      wait: options.wait ?? wait,
      log: options.log,
    };
    validateOptions(this.options);
  }

  status(): SidecarStatus {
    return Object.freeze({
      schemaVersion: SIDECAR_STATUS_SCHEMA_VERSION,
      mode: "managed",
      state: this.state,
      attempt: this.attempt,
      canEnsureRunning: !new Set<SidecarState>(["ready", "starting", "stopping"]).has(this.state),
      lastExit: this.lastExit,
    });
  }

  request(pathname: string, init: RequestInit = {}): Promise<Response> {
    const transport = this.transport;
    if (this.state !== "ready" || !transport || transport.generation !== this.generation) {
      return Promise.reject(new Error("Managed sidecar is not ready"));
    }
    return requestTransport(this.options.fetchImpl, transport, pathname, init);
  }

  start(): Promise<SidecarStatus> {
    if (this.shutdownRequested) return Promise.resolve(this.status());
    if (this.state === "ready") return Promise.resolve(this.status());
    if (this.state === "circuit_open") return Promise.resolve(this.status());
    if (this.state === "stopping") {
      return this.stopOperation ?? Promise.resolve(this.status());
    }
    if (this.launchOperation) return this.launchOperation;
    const operation = this.launchOnce();
    this.launchOperation = operation;
    const clear = () => {
      if (this.launchOperation === operation) this.launchOperation = null;
    };
    void operation.then(clear, clear);
    return operation;
  }

  ensureRunning(): Promise<SidecarStatus> {
    if (this.state === "ready" || this.state === "starting") {
      return this.launchOperation ?? Promise.resolve(this.status());
    }
    if (this.state === "stopping") {
      return this.stopOperation ?? Promise.resolve(this.status());
    }
    return this.recoverAndStart();
  }

  private async recoverAndStart(): Promise<SidecarStatus> {
    this.unexpectedExitTimes = [];
    this.generation += 1;
    const previousLaunch = this.launchOperation;
    if (previousLaunch) await previousLaunch.catch(() => undefined);
    if (this.state === "circuit_open" || this.state === "crashed") {
      this.state = "idle";
    }
    return this.start();
  }

  shutdown(): Promise<SidecarStatus> {
    this.shutdownRequested = true;
    return this.stop().finally(() => {
      this.options.backupKey?.fill(0);
      this.options.credentialVaultKey?.fill(0);
      this.options.storageProtectionKey?.fill(0);
    });
  }

  stop(): Promise<SidecarStatus> {
    if (this.stopOperation) return this.stopOperation;
    const operation = this.stopOnce();
    this.stopOperation = operation;
    const clear = () => {
      if (this.stopOperation === operation) this.stopOperation = null;
    };
    void operation.then(clear, clear);
    return operation;
  }

  private async launchOnce(): Promise<SidecarStatus> {
    const generation = this.generation + 1;
    this.generation = generation;
    this.clearTransport();
    this.state = "starting";
    this.attempt += 1;
    const launchId = randomUUID();
    const token = randomBytes(32);
    let child: SidecarChild;
    try {
      child = this.options.spawnImpl(
        this.options.command,
        [...this.options.args],
        {
          cwd: this.options.cwd,
          detached: false,
          env: {
            ...this.options.env,
            AGENTWEAVE_LAUNCH_CONFIG_FD: String(LAUNCH_CONFIG_FD),
            AGENTWEAVE_LAUNCH_RESULT_FD: String(LAUNCH_RESULT_FD),
          },
          stdio: ["ignore", "pipe", "pipe", "pipe", "pipe"],
          windowsHide: true,
        },
      );
    } catch {
      token.fill(0);
      this.state = "failed";
      return this.status();
    }
    this.child = child;
    const childExit = new Promise<void>((resolve) => {
      this.childExitResolvers.set(child, resolve);
    });
    this.childExitOperations.set(child, childExit);
    child.once("error", () => this.handleUnexpectedTermination(child, generation, null, null));
    child.once("exit", (code, signal) => {
      this.handleUnexpectedTermination(child, generation, code, signal);
    });
    this.attachLogs(child);

    let ready = false;
    try {
      await writeLaunchConfig(
        child.stdio[LAUNCH_CONFIG_FD],
        launchId,
        token,
        this.options.backupKey,
        this.options.credentialVaultKey,
        this.options.storageProtectionKey,
      );
      const origin = await readLaunchResult(
        child,
        child.stdio[LAUNCH_RESULT_FD],
        launchId,
        this.options.startupTimeoutMs,
      );
      if (this.child === child && this.generation === generation) {
        this.transport = { generation, origin, token };
        ready = await this.waitForHealth(child, generation);
      }
    } catch {
      token.fill(0);
    }
    if (this.transport?.token !== token) token.fill(0);
    if (ready && this.child === child && this.generation === generation) {
      this.readyChildren.add(child);
      this.state = "ready";
      return this.status();
    }
    if (this.child === child && this.generation === generation) {
      this.intentionalChildren.add(child);
      this.state = "failed";
      this.clearTransport(generation);
      await this.terminateChild(child);
      if (this.child === child) this.child = null;
    }
    return this.status();
  }

  private async waitForHealth(
    child: SidecarChild,
    generation: number,
  ): Promise<boolean> {
    const deadline = this.options.now() + this.options.startupTimeoutMs;
    while (
      this.child === child
      && this.generation === generation
      && this.options.now() < deadline
    ) {
      try {
        const transport = this.transport;
        if (!transport || transport.generation !== generation) return false;
        const response = await requestTransport(
          this.options.fetchImpl,
          transport,
          "/health",
          {
            cache: "no-store",
            method: "GET",
            signal: AbortSignal.timeout(this.options.healthTimeoutMs),
          },
        );
        if (response.ok) return true;
      } catch {
        // A starting sidecar is expected to refuse connections until it binds.
      }
      await this.options.wait(this.options.healthPollMs);
    }
    return false;
  }

  private handleUnexpectedTermination(
    child: SidecarChild,
    generation: number,
    code: number | null,
    signal: NodeJS.Signals | null,
  ): void {
    if (this.handledChildren.has(child)) return;
    this.handledChildren.add(child);
    this.childExitResolvers.get(child)?.();
    this.childExitResolvers.delete(child);
    if (this.child === child) {
      this.child = null;
    }
    this.clearTransport(generation);
    this.lastExit = Object.freeze({ code, signal });
    if (this.intentionalChildren.has(child) || this.generation !== generation) return;

    if (!this.readyChildren.has(child)) {
      this.state = "failed";
      return;
    }

    const now = this.options.now();
    this.unexpectedExitTimes = this.unexpectedExitTimes
      .filter((timestamp) => now - timestamp <= this.options.restartWindowMs);
    this.unexpectedExitTimes.push(now);
    if (this.unexpectedExitTimes.length >= this.options.maxUnexpectedExits) {
      this.state = "circuit_open";
      return;
    }
    this.state = "crashed";
    const restartGeneration = this.generation;
    void this.restartAfterCrash(restartGeneration);
  }

  private async restartAfterCrash(generation: number): Promise<void> {
    const multiplier = Math.max(1, this.unexpectedExitTimes.length);
    await this.options.wait(this.options.restartBackoffMs * multiplier);
    const activeLaunch = this.launchOperation;
    if (activeLaunch) await activeLaunch.catch(() => undefined);
    await Promise.resolve();
    if (this.state !== "crashed" || this.generation !== generation || this.child) return;
    await this.start();
  }

  private async stopOnce(): Promise<SidecarStatus> {
    this.generation += 1;
    this.clearTransport();
    const child = this.child;
    if (!child) {
      this.state = "stopped";
      return this.status();
    }
    this.state = "stopping";
    this.intentionalChildren.add(child);
    await this.terminateChild(child);
    if (this.child === child) this.child = null;
    this.state = "stopped";
    return this.status();
  }

  private async terminateChild(child: SidecarChild): Promise<void> {
    if (child.exitCode !== null || child.signalCode !== null) return;
    const childExit = this.childExitOperations.get(child) ?? Promise.resolve();
    signalChild(child, "SIGTERM");
    const exited = await Promise.race([
      childExit.then(() => true),
      this.options.wait(this.options.shutdownTimeoutMs).then(() => false),
    ]);
    if (exited || child.exitCode !== null || child.signalCode !== null) return;
    signalChild(child, "SIGKILL");
    await Promise.race([
      childExit,
      this.options.wait(this.options.shutdownTimeoutMs),
    ]);
  }

  private attachLogs(child: SidecarChild): void {
    if (!this.options.log) return;
    attachSanitizedLines(child.stdout, "stdout", this.options.log);
    attachSanitizedLines(child.stderr, "stderr", this.options.log);
  }

  private clearTransport(generation?: number): void {
    if (!this.transport || (generation !== undefined && this.transport.generation !== generation)) {
      return;
    }
    this.transport.token.fill(0);
    this.transport = null;
  }
}

export function sanitizeSidecarLog(value: string): string {
  return value
    .slice(0, 4_096)
    .replace(
      /(\bauthorization\s*["']?\s*[:=]\s*)["']?(?:(Bearer|Basic)\s+)?[^\s,"'}]+/gi,
      (_match, prefix: string, scheme: string | undefined) => (
        `${prefix}${scheme ? `${scheme} ` : ""}[REDACTED]`
      ),
    )
    .replace(/Bearer\s+\S+/gi, "Bearer [REDACTED]")
    .replace(
      /((?:api[_-]?key|password|secret|token)\s*["']?\s*[:=]\s*)["']?[^\s,"'}]+/gi,
      "$1[REDACTED]",
    )
    .replace(/[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}/g, "[REDACTED_EMAIL]")
    .replace(/\b[A-Za-z0-9_+/=-]{40,}\b/g, "[REDACTED_TOKEN]");
}

function attachSanitizedLines(
  stream: NodeJS.ReadableStream,
  source: "stderr" | "stdout",
  log: (stream: "stderr" | "stdout", message: string) => void,
): void {
  let pending = "";
  stream.on("data", (chunk: Buffer | string) => {
    pending = `${pending}${chunk.toString()}`.slice(-8_192);
    const lines = pending.split(/\r?\n/);
    pending = lines.pop() ?? "";
    for (const line of lines) {
      if (line.length > 0) log(source, sanitizeSidecarLog(line));
    }
  });
  stream.once("end", () => {
    if (pending.length > 0) log(source, sanitizeSidecarLog(pending));
    pending = "";
  });
}

function signalChild(child: SidecarChild, signal: NodeJS.Signals): void {
  try {
    child.kill(signal);
  } catch {
    // Exit observation and the bounded shutdown timeout remain authoritative.
  }
}

function defaultSpawn(
  command: string,
  args: string[],
  options: SidecarSpawnOptions,
): SidecarChild {
  return spawnChild(command, args, options) as unknown as SidecarChild;
}

function writeLaunchConfig(
  stream: Writable,
  launchId: string,
  token: Buffer,
  backupKey: Buffer | null,
  credentialVaultKey: Buffer | null,
  storageProtectionKey: Buffer | null,
): Promise<void> {
  if (!stream || stream.destroyed) throw new Error("Sidecar launch pipe is unavailable");
  const document = JSON.stringify({
    schemaVersion: 1,
    launchId,
    transportToken: token.toString("base64url"),
    ...(backupKey
      ? { backupKeyHex: backupKey.toString("hex") }
      : {}),
    ...(credentialVaultKey
      ? { credentialVaultKeyHex: credentialVaultKey.toString("hex") }
      : {}),
    ...(storageProtectionKey
      ? { storageProtectionKeyHex: storageProtectionKey.toString("hex") }
      : {}),
  });
  return new Promise((resolve, reject) => {
    let settled = false;
    const finish = (error?: Error) => {
      if (settled) return;
      settled = true;
      stream.removeListener("error", onError);
      if (error) reject(error);
      else resolve();
    };
    const onError = () => finish(new Error("Sidecar launch pipe failed"));
    stream.once("error", onError);
    stream.end(document, () => finish());
  });
}

function readLaunchResult(
  child: SidecarChild,
  stream: Readable,
  launchId: string,
  timeoutMs: number,
): Promise<string> {
  return new Promise((resolve, reject) => {
    let data = Buffer.alloc(0);
    let settled = false;
    const finish = (error: Error | null, origin?: string) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      stream.removeListener("data", onData);
      child.removeListener("error", onTermination);
      child.removeListener("exit", onTermination);
      if (error) reject(error);
      else resolve(origin!);
    };
    const onTermination = () => finish(new Error("Sidecar exited before launch handshake"));
    const onData = (chunk: Buffer | string) => {
      data = Buffer.concat([data, Buffer.from(chunk)]);
      if (data.byteLength > MAX_HANDSHAKE_BYTES) {
        finish(new Error("Sidecar launch handshake is too large"));
        return;
      }
      const newline = data.indexOf(0x0a);
      if (newline < 0) return;
      try {
        const trailing = data.subarray(newline + 1).toString("utf8").trim();
        if (trailing) throw new Error("trailing launch data");
        finish(null, validateLaunchResult(
          JSON.parse(data.subarray(0, newline).toString("utf8")),
          launchId,
          child.pid,
        ));
      } catch {
        finish(new Error("Sidecar launch handshake is invalid"));
      }
    };
    const timer = setTimeout(
      () => finish(new Error("Sidecar launch handshake timed out")),
      timeoutMs,
    );
    child.once("error", onTermination);
    child.once("exit", onTermination);
    stream.on("data", onData);
  });
}

function validateLaunchResult(value: unknown, launchId: string, pid: number | undefined): string {
  if (!isRecord(value) || Object.keys(value).sort().join(",") !== "launchId,origin,pid,schemaVersion") {
    throw new Error("invalid launch result shape");
  }
  if (value.schemaVersion !== 1 || value.launchId !== launchId || value.pid !== pid) {
    throw new Error("mismatched launch result");
  }
  if (typeof value.origin !== "string") throw new Error("invalid launch origin");
  const url = new URL(value.origin);
  if (
    url.protocol !== "http:"
    || url.hostname !== "127.0.0.1"
    || !url.port
    || url.username
    || url.password
    || url.pathname !== "/"
    || url.search
    || url.hash
  ) {
    throw new Error("unsafe launch origin");
  }
  return url.origin;
}

function requestTransport(
  fetchImpl: typeof fetch,
  transport: ActiveTransport,
  pathname: string,
  init: RequestInit,
): Promise<Response> {
  const url = normalizeSidecarRequestUrl(transport.origin, pathname);
  const headers = new Headers(init.headers);
  headers.delete("cookie");
  headers.set(TRANSPORT_HEADER, transport.token.toString("base64url"));
  return fetchImpl(url, {
    ...init,
    credentials: "omit",
    headers,
    redirect: "error",
  });
}

export function normalizeSidecarRequestUrl(origin: string, pathname: string): URL {
  if (!pathname.startsWith("/") || pathname.startsWith("//") || pathname.includes("\\")) {
    throw new Error("Sidecar request path is not allowed");
  }
  const rawPath = pathname.split(/[?#]/, 1)[0];
  try {
    if (rawPath.split("/").some((segment) => {
      const decoded = decodeURIComponent(segment);
      return decoded === "." || decoded === "..";
    })) {
      throw new Error("dot segment");
    }
  } catch {
    throw new Error("Sidecar request path is not allowed");
  }
  const url = new URL(pathname, origin);
  if (url.origin !== origin || url.username || url.password || url.hash) {
    throw new Error("Sidecar request path is not allowed");
  }
  return url;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function wait(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function validateOptions(options: DesktopSidecarSupervisor["options"]): void {
  if (!options.command || !options.cwd) throw new Error("Sidecar launch paths are required");
  if (options.backupKey && options.backupKey.byteLength !== 32) {
    throw new Error("Sidecar backup key must be 32 bytes");
  }
  if (options.credentialVaultKey && options.credentialVaultKey.byteLength !== 32) {
    throw new Error("Sidecar credential Vault key must be 32 bytes");
  }
  if (options.storageProtectionKey && options.storageProtectionKey.byteLength !== 32) {
    throw new Error("Sidecar storage protection key must be 32 bytes");
  }
  for (const [label, value] of [
    ["startup timeout", options.startupTimeoutMs],
    ["health poll", options.healthPollMs],
    ["health timeout", options.healthTimeoutMs],
    ["shutdown timeout", options.shutdownTimeoutMs],
    ["restart window", options.restartWindowMs],
    ["restart backoff", options.restartBackoffMs],
    ["unexpected exit limit", options.maxUnexpectedExits],
  ] as const) {
    if (!Number.isSafeInteger(value) || value <= 0) {
      throw new Error(`Sidecar ${label} must be a positive integer`);
    }
  }
}
