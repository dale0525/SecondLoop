import { EventEmitter } from "node:events";
import { PassThrough } from "node:stream";

import { describe, expect, it, vi } from "vitest";

import {
  DesktopSidecarSupervisor,
  sanitizeSidecarLog,
  type SidecarSpawn,
} from "../src/main/sidecarSupervisor";

describe("Desktop sidecar supervisor", () => {
  it("deduplicates concurrent starts and waits for health readiness", async () => {
    const child = new MockChild();
    const spawnImpl = spawnSequence(child);
    const fetchImpl = vi.fn()
      .mockRejectedValueOnce(new Error("not bound"))
      .mockResolvedValueOnce(new Response("ok", { status: 200 }));
    const supervisor = createSupervisor({ fetchImpl, spawnImpl });

    const [first, second] = await Promise.all([supervisor.start(), supervisor.start()]);

    expect(spawnImpl).toHaveBeenCalledTimes(1);
    expect(fetchImpl).toHaveBeenCalledTimes(2);
    expect(first.state).toBe("ready");
    expect(second).toEqual(first);
    expect(first.attempt).toBe(1);
    const healthHeaders = new Headers(fetchImpl.mock.calls[1][1]?.headers);
    expect(healthHeaders.get("X-AgentWeave-Transport")).toBe(child.launch?.transportToken);
    expect(String(fetchImpl.mock.calls[1][0])).toMatch(/^http:\/\/127\.0\.0\.1:\d+\/health$/);
    expect(JSON.stringify(first)).not.toContain(child.launch?.transportToken);
    expect(JSON.stringify(spawnImpl.mock.calls[0])).not.toContain(child.launch?.transportToken);
  });

  it("passes the data protection key only through the inherited launch pipe", async () => {
    const child = new MockChild();
    const key = Buffer.alloc(32, 7);
    const spawnImpl = spawnSequence(child);
    const supervisor = createSupervisor({ dataProtectionKey: key, spawnImpl });

    await supervisor.start();

    expect(child.launch?.dataProtectionKeyHex).toBe(key.toString("hex"));
    expect(JSON.stringify(spawnImpl.mock.calls[0]?.[2]?.env)).not.toContain(key.toString("hex"));
  });

  it("fails a timed-out startup and terminates that child", async () => {
    const child = new MockChild({ exitOnSignal: true });
    const spawnImpl = spawnSequence(child);
    let now = 0;
    const supervisor = createSupervisor({
      fetchImpl: vi.fn(async () => {
        throw new Error("not ready");
      }),
      now: () => now,
      spawnImpl,
      startupTimeoutMs: 200,
      wait: async (milliseconds) => {
        now += milliseconds;
      },
    });

    const status = await supervisor.start();

    expect(status.state).toBe("failed");
    expect(child.signals).toEqual(["SIGTERM"]);
    expect(spawnImpl).toHaveBeenCalledTimes(1);
  });

  it("fails without restarting when a child exits before readiness", async () => {
    const child = new MockChild();
    let releaseHealth!: () => void;
    const supervisor = createSupervisor({
      fetchImpl: vi.fn(() => new Promise<Response>((resolve) => {
        releaseHealth = () => resolve(new Response("ok", { status: 200 }));
      })),
      spawnImpl: spawnSequence(child),
    });

    const starting = supervisor.start();
    await waitForCallback(() => releaseHealth);
    child.emitExit(1, null);
    releaseHealth();

    await expect(starting).resolves.toMatchObject({
      attempt: 1,
      state: "failed",
    });
    await flushMicrotasks();
    expect(supervisor.status().state).toBe("failed");
  });

  it("stops explicitly without scheduling a restart", async () => {
    const child = new MockChild({ exitOnSignal: true });
    const spawnImpl = spawnSequence(child);
    const supervisor = createSupervisor({ spawnImpl });
    await supervisor.start();

    const status = await supervisor.stop();
    await flushMicrotasks();

    expect(status.state).toBe("stopped");
    expect(child.signals).toEqual(["SIGTERM"]);
    expect(spawnImpl).toHaveBeenCalledTimes(1);
  });

  it("forces shutdown when the child ignores graceful termination", async () => {
    const child = new MockChild();
    const waits: Array<() => void> = [];
    const supervisor = createSupervisor({
      shutdownTimeoutMs: 10,
      spawnImpl: spawnSequence(child),
      wait: () => new Promise((resolve) => waits.push(resolve)),
    });
    await supervisor.start();

    const stopping = supervisor.stop();
    expect(child.signals).toEqual(["SIGTERM"]);
    waits.shift()?.();
    await flushMicrotasks();
    expect(child.signals).toEqual(["SIGTERM", "SIGKILL"]);
    child.emitExit(null, "SIGKILL");
    await expect(stopping).resolves.toMatchObject({ state: "stopped" });
  });

  it("restarts crashes, opens the circuit, and allows explicit recovery", async () => {
    const children = [new MockChild(), new MockChild(), new MockChild(), new MockChild()];
    const spawnImpl = spawnSequence(...children);
    const supervisor = createSupervisor({
      maxUnexpectedExits: 3,
      restartBackoffMs: 1,
      spawnImpl,
    });
    await supervisor.start();

    children[0].emitExit(1, null);
    await waitForStatus(supervisor, "ready");
    children[1].emitExit(1, null);
    await waitForStatus(supervisor, "ready");
    children[2].emitExit(1, null);
    await waitForStatus(supervisor, "circuit_open");

    expect(spawnImpl).toHaveBeenCalledTimes(3);
    expect(supervisor.status()).toMatchObject({
      attempt: 3,
      canEnsureRunning: true,
      lastExit: { code: 1, signal: null },
      state: "circuit_open",
    });

    await expect(supervisor.ensureRunning()).resolves.toMatchObject({ state: "ready" });
    expect(spawnImpl).toHaveBeenCalledTimes(4);
  });

  it("counts a process error and its following exit event only once", async () => {
    const first = new MockChild();
    const second = new MockChild();
    const spawnImpl = spawnSequence(first, second);
    const supervisor = createSupervisor({ spawnImpl });
    await supervisor.start();

    first.emit("error", new Error("spawn channel failed"));
    first.emitExit(1, null);
    await waitForStatus(supervisor, "ready");

    expect(spawnImpl).toHaveBeenCalledTimes(2);
    expect(supervisor.status()).toMatchObject({
      attempt: 2,
      lastExit: { code: null, signal: null },
      state: "ready",
    });
  });

  it("rotates the private endpoint credential after a crash", async () => {
    const first = new MockChild();
    const second = new MockChild();
    const fetchImpl = vi.fn(async (
      _url: RequestInfo | URL,
      _init: RequestInit = {},
    ) => new Response("ok"));
    const supervisor = createSupervisor({
      fetchImpl,
      spawnImpl: spawnSequence(first, second),
    });
    await supervisor.start();
    await supervisor.request("/sessions");
    const firstToken = new Headers(fetchImpl.mock.calls.at(-1)?.[1]?.headers)
      .get("X-AgentWeave-Transport");

    first.emitExit(1, null);
    await waitForStatus(supervisor, "ready");
    await supervisor.request("/sessions");
    const secondToken = new Headers(fetchImpl.mock.calls.at(-1)?.[1]?.headers)
      .get("X-AgentWeave-Transport");

    expect(firstToken).toBe(first.launch?.transportToken);
    expect(secondToken).toBe(second.launch?.transportToken);
    expect(secondToken).not.toBe(firstToken);
  });

  it("bounds and redacts child diagnostics", () => {
    const longToken = "a".repeat(80);
    const sanitized = sanitizeSidecarLog(
      `Authorization=Bearer secret-token api_key=top-secret user@example.com ${longToken}`,
    );

    expect(sanitized).toContain("Authorization=Bearer [REDACTED]");
    expect(sanitized).toContain("api_key=[REDACTED]");
    expect(sanitized).toContain("[REDACTED_EMAIL]");
    expect(sanitized).toContain("[REDACTED_TOKEN]");
    expect(sanitized).not.toContain("secret-token");
    expect(sanitized).not.toContain("top-secret");
    expect(sanitized).not.toContain("user@example.com");
  });

  it("sanitizes split log lines and flushes a bounded trailing line", async () => {
    const child = new MockChild();
    const log = vi.fn();
    const supervisor = createSupervisor({
      log,
      spawnImpl: spawnSequence(child),
    });
    await supervisor.start();

    child.stdout.write("user@example.com Bear");
    child.stdout.write("er secret-token\n");
    const stderrEnded = new Promise<void>((resolve) => child.stderr.once("end", resolve));
    child.stderr.end(`token=${"z".repeat(80)}`);
    await stderrEnded;

    expect(log).toHaveBeenCalledWith(
      "stdout",
      "[REDACTED_EMAIL] Bearer [REDACTED]",
    );
    expect(log).toHaveBeenCalledWith("stderr", "token=[REDACTED]");
    expect(log.mock.calls.flat().join(" ")).not.toContain("secret-token");
    expect(log.mock.calls.flat().join(" ")).not.toContain("z".repeat(80));
  });
});

type SupervisorOverrides = Partial<ConstructorParameters<typeof DesktopSidecarSupervisor>[0]>;

function createSupervisor(overrides: SupervisorOverrides = {}): DesktopSidecarSupervisor {
  return new DesktopSidecarSupervisor({
    command: "/app/agent-server",
    cwd: "/app",
    env: { PATH: "/usr/bin" },
    fetchImpl: vi.fn(async () => new Response("ok", { status: 200 })),
    restartBackoffMs: 1,
    shutdownTimeoutMs: 10,
    startupTimeoutMs: 100,
    wait: async () => undefined,
    ...overrides,
  });
}

function spawnSequence(...children: MockChild[]): ReturnType<typeof vi.fn<SidecarSpawn>> {
  const spawn = vi.fn<SidecarSpawn>();
  for (const child of children) {
    spawn.mockImplementationOnce((_command, _args, options) => {
      child.acceptLaunch(options.env ?? {});
      return child as unknown as ReturnType<SidecarSpawn>;
    });
  }
  return spawn;
}

class MockChild extends EventEmitter {
  private static nextPid = 1;
  readonly stdout = new PassThrough();
  readonly stderr = new PassThrough();
  readonly launchConfig = new PassThrough();
  readonly launchResult = new PassThrough();
  readonly stdin = null;
  readonly stdio = [
    null,
    this.stdout,
    this.stderr,
    this.launchConfig,
    this.launchResult,
  ] as const;
  readonly signals: string[] = [];
  readonly pid = 20_000 + MockChild.nextPid++;
  launch: {
    dataProtectionKeyHex?: string;
    launchId: string;
    transportToken: string;
  } | null = null;
  exitCode: number | null = null;
  signalCode: NodeJS.Signals | null = null;
  readonly exitOnSignal: boolean;

  constructor(options: { exitOnSignal?: boolean } = {}) {
    super();
    this.exitOnSignal = options.exitOnSignal ?? false;
  }

  acceptLaunch(env: NodeJS.ProcessEnv): void {
    if (env.AGENTWEAVE_LAUNCH_CONFIG_FD !== "3" || env.AGENTWEAVE_LAUNCH_RESULT_FD !== "4") {
      throw new Error("Launch descriptors were not configured");
    }
    let config = "";
    this.launchConfig.on("data", (chunk) => {
      config += chunk.toString();
    });
    this.launchConfig.once("finish", () => {
      const launch = JSON.parse(config) as { launchId: string; transportToken: string };
      this.launch = launch;
      this.launchResult.end(`${JSON.stringify({
        schemaVersion: 1,
        launchId: launch.launchId,
        pid: this.pid,
        origin: `http://127.0.0.1:${40_000 + this.pid % 10_000}`,
      })}\n`);
    });
  }

  kill(signal: NodeJS.Signals = "SIGTERM"): boolean {
    this.signals.push(signal);
    if (this.exitOnSignal) this.emitExit(null, signal);
    return true;
  }

  emitExit(code: number | null, signal: NodeJS.Signals | null): void {
    this.exitCode = code;
    this.signalCode = signal;
    this.emit("exit", code, signal);
  }

}

async function flushMicrotasks(): Promise<void> {
  for (let index = 0; index < 8; index += 1) await Promise.resolve();
}

async function waitForStatus(
  supervisor: DesktopSidecarSupervisor,
  expected: ReturnType<DesktopSidecarSupervisor["status"]>["state"],
): Promise<void> {
  for (let index = 0; index < 40; index += 1) {
    if (supervisor.status().state === expected) return;
    await flushMicrotasks();
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
  throw new Error(`Sidecar did not reach ${expected}; current=${supervisor.status().state}`);
}

async function waitForCallback(read: () => (() => void) | undefined): Promise<void> {
  for (let index = 0; index < 40; index += 1) {
    if (read()) return;
    await flushMicrotasks();
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
  throw new Error("Expected callback was not installed");
}
