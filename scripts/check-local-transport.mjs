import { spawn } from "node:child_process";
import { randomBytes, randomUUID } from "node:crypto";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const executable = resolve(process.argv[2] ?? join(projectRoot, "target/debug/agent-server"));
const temporaryRoot = await mkdtemp(join(tmpdir(), "agentweave-local-transport-"));
const children = [];

try {
  const [first, second] = await Promise.all([
    launchSidecar("first"),
    launchSidecar("second"),
  ]);
  if (first.origin === second.origin || first.token === second.token) {
    throw new Error("Concurrent sidecars did not receive independent transports");
  }
  await expectStatus(first.origin, null, 401);
  await expectStatus(first.origin, "wrong-transport-token", 401);
  await expectStatus(first.origin, second.token, 401);
  await expectStatus(first.origin, first.token, 200, "ok");
  await expectStatus(second.origin, first.token, 401);
  await expectStatus(second.origin, second.token, 200, "ok");
  console.log("Local sidecar transport check passed");
} finally {
  await Promise.all(children.map(stopChild));
  await rm(temporaryRoot, { force: true, recursive: true });
}

async function launchSidecar(name) {
  const launchId = randomUUID();
  const token = randomBytes(32).toString("base64url");
  const child = spawn(executable, [], {
    cwd: projectRoot,
    env: childEnvironment(name),
    stdio: ["ignore", "ignore", "pipe", "pipe", "pipe"],
    windowsHide: true,
  });
  children.push(child);
  child.stdio[3].end(JSON.stringify({
    schemaVersion: 1,
    launchId,
    transportToken: token,
  }));
  const result = await readHandshake(child);
  if (
    result.schemaVersion !== 1
    || result.launchId !== launchId
    || result.pid !== child.pid
    || typeof result.origin !== "string"
    || Object.hasOwn(result, "transportToken")
  ) {
    throw new Error("Sidecar returned an invalid launch handshake");
  }
  const origin = new URL(result.origin);
  if (
    origin.protocol !== "http:"
    || origin.hostname !== "127.0.0.1"
    || origin.port === "49321"
    || origin.pathname !== "/"
  ) {
    throw new Error("Sidecar returned an unsafe dynamic origin");
  }
  return { child, origin: origin.href, token };
}

function childEnvironment(name) {
  const env = {};
  for (const key of ["HOME", "LANG", "PATH", "RUST_BACKTRACE", "RUST_LOG", "TMPDIR"]) {
    if (process.env[key]) env[key] = process.env[key];
  }
  return {
    ...env,
    AGENTWEAVE_APP_ROOT: join(projectRoot, "examples/minimal-agent"),
    AGENTWEAVE_DATABASE_URL: `sqlite://${join(temporaryRoot, `${name}.db`)}?mode=rwc`,
    AGENTWEAVE_LAUNCH_CONFIG_FD: "3",
    AGENTWEAVE_LAUNCH_RESULT_FD: "4",
    AGENTWEAVE_SKILLS_ROOT: join(projectRoot, "skills"),
    AGENTWEAVE_WORKSPACE_ROOT: join(temporaryRoot, `${name}-workspace`),
  };
}

function readHandshake(child) {
  return new Promise((resolveHandshake, rejectHandshake) => {
    let settled = false;
    let data = "";
    const timer = setTimeout(() => finish(new Error("Sidecar launch handshake timed out")), 15_000);
    const finish = (error, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (error) rejectHandshake(error);
      else resolveHandshake(value);
    };
    child.once("error", () => finish(new Error("Sidecar failed to spawn")));
    child.once("exit", () => finish(new Error("Sidecar exited before launch handshake")));
    child.stdio[4].on("data", (chunk) => {
      data += chunk.toString();
      if (data.length > 4_096) return finish(new Error("Sidecar launch handshake is too large"));
      const newline = data.indexOf("\n");
      if (newline < 0) return;
      try {
        finish(null, JSON.parse(data.slice(0, newline)));
      } catch {
        finish(new Error("Sidecar launch handshake is invalid"));
      }
    });
  });
}

async function expectStatus(origin, token, expected, body) {
  const headers = token ? { "X-AgentWeave-Transport": token } : {};
  const response = await fetch(new URL("/health", origin), { headers });
  if (response.status !== expected) {
    throw new Error(`Expected local transport HTTP ${expected}, received ${response.status}`);
  }
  if (body !== undefined && await response.text() !== body) {
    throw new Error("Authenticated health response was invalid");
  }
}

async function stopChild(child) {
  if (child.exitCode !== null || child.signalCode !== null) return;
  const exited = new Promise((resolveExit) => child.once("exit", resolveExit));
  child.kill("SIGTERM");
  const completed = await Promise.race([
    exited.then(() => true),
    new Promise((resolveWait) => setTimeout(() => resolveWait(false), 5_000)),
  ]);
  if (!completed && child.exitCode === null && child.signalCode === null) {
    child.kill("SIGKILL");
    await exited;
  }
}
