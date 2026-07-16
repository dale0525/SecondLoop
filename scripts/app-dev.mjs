import { spawn, spawnSync } from "node:child_process";
import { mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { join } from "node:path";

import { resolveAppProject } from "./app-project.mjs";

const DESKTOP_URL = "http://127.0.0.1:5173";

export function createAppDevPlan(options = {}) {
  const app = resolveAppProject(options);
  const environment = Object.freeze({
    AGENTWEAVE_APP_ROOT: app.appRoot,
    AGENTWEAVE_DEV_API: "1",
    AGENTWEAVE_DEV_SKILLS_ROOT: app.packagesRoot,
    AGENTWEAVE_DESKTOP_URL: DESKTOP_URL,
    AGENTWEAVE_DEV_USER_DATA_ROOT: join(app.projectRoot, ".tool", "app-dev", app.outputName),
  });
  return Object.freeze({
    app,
    environment,
    setup: Object.freeze([
      Object.freeze({ command: "cargo", args: ["build", "-p", "agent-server", "--bin", "agent-server"] }),
      Object.freeze({ command: "npm", args: ["--prefix", "apps/desktop", "run", "build:electron"] }),
    ]),
    vite: Object.freeze({
      command: "npm",
      args: ["--prefix", "apps/desktop", "run", "dev", "--", "--host", "127.0.0.1", "--port", "5173", "--strictPort"],
    }),
    electron: Object.freeze({ command: "npm", args: ["--prefix", "apps/desktop", "run", "start"] }),
  });
}

function runSetup(plan) {
  for (const step of plan.setup) {
    const result = spawnSync(step.command, step.args, {
      cwd: plan.app.projectRoot,
      env: { ...process.env, ...plan.environment },
      stdio: "inherit",
    });
    if (result.error) throw result.error;
    if (result.status !== 0) throw new Error(`${step.command} exited with code ${result.status}`);
  }
}

function spawnProcess(plan, processPlan, name) {
  const child = spawn(processPlan.command, processPlan.args, {
    cwd: plan.app.projectRoot,
    env: { ...process.env, ...plan.environment },
    stdio: ["ignore", "pipe", "pipe"],
  });
  child.stdout?.on("data", (chunk) => writePrefixed(name, chunk));
  child.stderr?.on("data", (chunk) => writePrefixed(name, chunk));
  return child;
}

async function waitForVite(child, timeoutMs = 30_000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (child.exitCode !== null) throw new Error("Desktop Vite server stopped before becoming ready");
    try {
      const response = await fetch(DESKTOP_URL, { signal: AbortSignal.timeout(1_000) });
      if (response.ok) {
        await new Promise((resolve) => setTimeout(resolve, 100));
        if (child.exitCode !== null) {
          throw new Error("Desktop Vite server stopped before becoming ready");
        }
        return;
      }
    } catch {
      // The development server is still starting.
    }
    await new Promise((resolve) => setTimeout(resolve, 150));
  }
  throw new Error("Desktop Vite server did not become ready in time");
}

async function runAppDev() {
  const plan = createAppDevPlan();
  mkdirSync(plan.environment.AGENTWEAVE_DEV_USER_DATA_ROOT, { recursive: true });
  mkdirSync(plan.app.packagesRoot, { recursive: true });
  console.log(`Preparing ${plan.app.displayName} from ${plan.app.appRootRelative}...`);
  runSetup(plan);
  const vite = spawnProcess(plan, plan.vite, "vite");
  let electron;
  let stopping = false;
  let resolveStopped;
  const stopped = new Promise((resolve) => {
    resolveStopped = resolve;
  });
  const stop = () => {
    if (stopping) return;
    stopping = true;
    if (electron && !electron.killed) electron.kill("SIGTERM");
    if (!vite.killed) vite.kill("SIGTERM");
    resolveStopped();
  };
  for (const signal of ["SIGINT", "SIGTERM"]) process.on(signal, stop);
  try {
    const ready = await Promise.race([
      waitForVite(vite).then(() => true),
      stopped.then(() => false),
    ]);
    if (!ready) return;
    electron = spawnProcess(plan, plan.electron, "electron");
    console.log(`Opened ${plan.app.displayName} in the AgentWeave Electron development host.`);
    await Promise.race([
      stopped,
      new Promise((resolve, reject) => {
        electron.once("error", (error) => stopping ? resolve() : reject(error));
        electron.once("exit", (code, signal) => {
          const error = unexpectedProcessExit("Electron", code, signal, stopping);
          error ? reject(error) : resolve();
        });
        vite.once("exit", (code, signal) => {
          const error = unexpectedProcessExit("Desktop Vite server", code, signal, stopping);
          if (error) reject(error);
          else if (!stopping) reject(new Error("Desktop Vite server stopped unexpectedly"));
        });
      }),
    ]);
  } finally {
    stop();
    for (const signal of ["SIGINT", "SIGTERM"]) process.removeListener(signal, stop);
  }
}

export function unexpectedProcessExit(name, code, signal, stopping = false) {
  if (stopping || code === 0) return null;
  const outcome = code === null ? `from signal ${signal ?? "unknown"}` : `with code ${code}`;
  return new Error(`${name} exited ${outcome}`);
}

function writePrefixed(name, chunk) {
  for (const line of chunk.toString().split(/\r?\n/)) {
    if (line) console.log(`[${name}] ${line}`);
  }
}

if (process.argv.includes("--print-plan")) {
  console.log(JSON.stringify(createAppDevPlan(), null, 2));
} else if (process.argv[1] === fileURLToPath(import.meta.url)) {
  runAppDev().catch((error) => {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  });
}
