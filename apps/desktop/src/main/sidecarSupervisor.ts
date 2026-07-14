import {
  spawn as spawnChild,
  type ChildProcessByStdio,
  type SpawnOptions,
} from "node:child_process";
import type { Readable } from "node:stream";

import {
  SIDECAR_STATUS_SCHEMA_VERSION,
  type SidecarStatus,
  type SidecarState,
} from "../shared/sidecarStatus";

type SidecarChild = ChildProcessByStdio<null, Readable, Readable>;

type SidecarSpawnOptions = SpawnOptions & {
  stdio: ["ignore", "pipe", "pipe"];
};

export type SidecarSpawn = (
  command: string,
  args: string[],
  options: SidecarSpawnOptions,
) => SidecarChild;

export type SidecarSupervisorOptions = {
  args?: string[];
  baseUrl: string;
  command: string;
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
  wait?: (milliseconds: number) => Promise<void>;
};

const DEFAULT_STARTUP_TIMEOUT_MS = 15_000;
const DEFAULT_HEALTH_POLL_MS = 100;
const DEFAULT_HEALTH_TIMEOUT_MS = 1_000;
const DEFAULT_SHUTDOWN_TIMEOUT_MS = 5_000;
const DEFAULT_RESTART_WINDOW_MS = 60_000;
const DEFAULT_RESTART_BACKOFF_MS = 250;
const DEFAULT_MAX_UNEXPECTED_EXITS = 3;

export class DesktopSidecarSupervisor {
  private readonly options: Required<Omit<SidecarSupervisorOptions, "args" | "fetchImpl" | "log" | "now" | "spawnImpl" | "wait">> & Pick<SidecarSupervisorOptions, "log"> & {
    args: string[];
    fetchImpl: typeof fetch;
    now: () => number;
    spawnImpl: SidecarSpawn;
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
  private unexpectedExitTimes: number[] = [];

  constructor(options: SidecarSupervisorOptions) {
    this.options = {
      command: options.command,
      args: [...(options.args ?? [])],
      cwd: options.cwd,
      env: { ...options.env },
      baseUrl: options.baseUrl,
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

  start(): Promise<SidecarStatus> {
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
    this.state = "starting";
    this.attempt += 1;
    let child: SidecarChild;
    try {
      child = this.options.spawnImpl(
        this.options.command,
        [...this.options.args],
        {
          cwd: this.options.cwd,
          detached: false,
          env: { ...this.options.env },
          stdio: ["ignore", "pipe", "pipe"],
          windowsHide: true,
        },
      );
    } catch {
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

    const ready = await this.waitForHealth(child, generation);
    if (ready && this.child === child && this.generation === generation) {
      this.readyChildren.add(child);
      this.state = "ready";
      return this.status();
    }
    if (this.child === child && this.generation === generation) {
      this.intentionalChildren.add(child);
      this.state = "failed";
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
        const response = await this.options.fetchImpl(
          new URL("/health", this.options.baseUrl),
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
  return spawnChild(command, args, options);
}

function wait(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function validateOptions(options: DesktopSidecarSupervisor["options"]): void {
  if (!options.command || !options.cwd) throw new Error("Sidecar launch paths are required");
  new URL(options.baseUrl);
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
