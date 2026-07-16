import { spawn } from "node:child_process";
import { randomBytes, randomUUID } from "node:crypto";
import { createServer } from "node:http";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  statSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HANDSHAKE_LIMIT = 4_096;
const LOG_LIMIT = 32_768;
const MODEL_REQUEST_LIMIT = 1024 * 1024;
const START_TIMEOUT_MS = 20_000;
const STOP_TIMEOUT_MS = 5_000;
const TURN_TIMEOUT_MS = 25_000;

const FOUNDATION_TOOLS = [
  "mail_draft_create",
  "mail_send_preview",
  "memory_confirm",
  "memory_propose",
];

function fail(message) {
  throw new Error(message);
}

function requireDirectory(path, label) {
  if (!existsSync(path) || !statSync(path).isDirectory()) fail(`${label} is missing`);
}

function requireFile(path, label) {
  if (!existsSync(path) || !statSync(path).isFile()) fail(`${label} is missing`);
}

function readJson(path, label) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    fail(`${label} is invalid JSON: ${error instanceof Error ? error.message : String(error)}`);
  }
}

function requireString(value, label) {
  if (typeof value !== "string" || value.length === 0) fail(`${label} is invalid`);
  return value;
}

function requireStringArray(value, label) {
  if (!Array.isArray(value) || value.some((entry) => typeof entry !== "string")) {
    fail(`${label} is invalid`);
  }
  return value;
}

export function foundationScenarioSupported(expected) {
  const capabilities = new Set(expected.capabilities);
  const tools = new Set(expected.runtimeTools);
  return capabilities.has("approval-engine")
    && capabilities.has("durable-actions")
    && capabilities.has("mail-connector")
    && capabilities.has("memory-provider")
    && expected.connectors.length > 0
    && FOUNDATION_TOOLS.every((tool) => tools.has(tool));
}

export function packagedSidecarPlan(appPath) {
  const bundleRoot = resolve(appPath);
  requireDirectory(bundleRoot, "packaged macOS App");
  if (!basename(bundleRoot).endsWith(".app")) fail("packaged macOS App must use the .app suffix");
  const resourcesRoot = join(bundleRoot, "Contents", "Resources");
  const appRoot = join(resourcesRoot, "agent-app", "app");
  const skillsRoot = join(resourcesRoot, "skills");
  const sidecarPath = join(resourcesRoot, "sidecar", "agent-server");
  requireDirectory(appRoot, "packaged Agent App");
  requireDirectory(skillsRoot, "packaged first-party skills");
  requireFile(sidecarPath, "packaged sidecar");
  if ((statSync(sidecarPath).mode & 0o111) === 0) fail("packaged sidecar is not executable");

  const manifest = readJson(join(appRoot, "agent-app.json"), "packaged Agent App manifest");
  const requirements = manifest.requires;
  if (!requirements || typeof requirements !== "object") fail("packaged requirements are invalid");
  return Object.freeze({
    appRoot,
    bundleRoot,
    expected: Object.freeze({
      appId: requireString(manifest.appId, "packaged App identifier"),
      capabilities: Object.freeze([...requireStringArray(requirements.capabilities, "packaged capabilities")]),
      connectors: Object.freeze([...requireStringArray(requirements.connectors, "packaged connectors")]),
      displayName: requireString(manifest.branding?.displayName, "packaged display name"),
      packageId: requireString(manifest.package?.id, "packaged package identifier"),
      runtimeTools: Object.freeze([...requireStringArray(requirements.runtimeTools, "packaged runtime tools")]),
      version: requireString(manifest.package?.version, "packaged App version"),
    }),
    resourcesRoot,
    sidecarPath,
    skillsRoot,
  });
}

export function assertPackagedDiscovery(discovery, expected) {
  if (!discovery || typeof discovery !== "object") fail("host bootstrap response is invalid");
  if (discovery.schemaVersion !== 1 || discovery.platform !== "desktop") {
    fail("host bootstrap platform contract is invalid");
  }
  const identity = discovery.identity;
  if (
    !identity
    || identity.appId !== expected.appId
    || identity.packageId !== expected.packageId
    || identity.version !== expected.version
    || identity.displayName !== expected.displayName
  ) {
    fail("host bootstrap identity does not match the packaged manifest");
  }
  const requirements = discovery.requirements;
  if (!requirements || typeof requirements !== "object") {
    fail("host bootstrap requirements are invalid");
  }
  assertStringSet(requirements.capabilities, expected.capabilities, "capabilities");
  assertStringSet(requirements.runtimeTools, expected.runtimeTools, "runtime tools");
  assertStringSet(requirements.connectors, expected.connectors, "connectors");
  return true;
}

function assertStringSet(actual, expected, label) {
  if (!Array.isArray(actual) || actual.some((entry) => typeof entry !== "string")) {
    fail(`host bootstrap ${label} are invalid`);
  }
  const left = [...actual].sort();
  const right = [...expected].sort();
  if (left.length !== right.length || left.some((entry, index) => entry !== right[index])) {
    fail(`host bootstrap ${label} do not match the packaged manifest`);
  }
}

export async function checkPackagedSidecar(appPath) {
  const plan = packagedSidecarPlan(appPath);
  const temporaryRoot = mkdtempSync(join(tmpdir(), "agentweave-packaged-sidecar-"));
  let child;
  let model;
  try {
    for (const directory of ["cache", "data", "workspace"]) {
      mkdirSync(join(temporaryRoot, directory), { recursive: true });
    }
    const foundationScenario = foundationScenarioSupported(plan.expected);
    model = foundationScenario ? await startScriptedModelServer() : undefined;
    const launch = launchSidecar(plan, temporaryRoot, model?.baseUrl);
    child = launch.child;
    const handshake = await launch.handshake;
    await expectResponse(handshake.origin, null, "/health", 401);
    await expectResponse(handshake.origin, handshake.token, "/health", 200, "ok");
    const discovery = await expectJson(handshake.origin, handshake.token, "/host/bootstrap");
    assertPackagedDiscovery(discovery, plan.expected);
    if (foundationScenario) {
      try {
        await createPackagedFoundationState(handshake.origin, handshake.token);
      } catch (error) {
        const reason = error instanceof Error ? error.message : String(error);
        const modelError = model.diagnostics.lastError ? `; model error: ${model.diagnostics.lastError}` : "";
        const sidecarError = launch.stderr() ? `; sidecar: ${launch.stderr()}` : "";
        fail(
          `${reason}; scripted model requests: ${model.diagnostics.requests}`
          + `; last reply: ${model.diagnostics.lastReply}${modelError}${sidecarError}`,
        );
      }
      await assertPackagedFoundationState(handshake.origin, handshake.token);
    }
    await stopChild(child);
    child = undefined;
    if (foundationScenario) {
      const restarted = launchSidecar(plan, temporaryRoot, model.baseUrl);
      child = restarted.child;
      const restartedHandshake = await restarted.handshake;
      await assertPackagedFoundationState(restartedHandshake.origin, restartedHandshake.token);
      await stopChild(child);
      child = undefined;
    }
    return plan;
  } finally {
    if (child) await stopChild(child);
    if (model) await model.close();
    rmSync(temporaryRoot, { force: true, recursive: true });
  }
}

function launchSidecar(plan, temporaryRoot, modelBaseUrl) {
  const launchId = randomUUID();
  const token = randomBytes(32).toString("base64url");
  let stderr = "";
  const child = spawn(plan.sidecarPath, [], {
    cwd: dirname(plan.bundleRoot),
    env: childEnvironment(plan, temporaryRoot, modelBaseUrl),
    stdio: ["ignore", "ignore", "pipe", "pipe", "pipe"],
    windowsHide: true,
  });
  child.stdio[2].on("data", (chunk) => {
    if (stderr.length < LOG_LIMIT) stderr += chunk.toString().slice(0, LOG_LIMIT - stderr.length);
  });
  child.stdio[3].end(JSON.stringify({
    schemaVersion: 1,
    launchId,
    transportToken: token,
  }));
  return {
    child,
    handshake: readHandshake(child, launchId, token, () => stderr.trim()),
    stderr: () => stderr.trim(),
  };
}

function childEnvironment(plan, temporaryRoot, modelBaseUrl) {
  const env = {};
  for (const key of [
    "DYLD_FALLBACK_LIBRARY_PATH",
    "DYLD_LIBRARY_PATH",
    "HOME",
    "HTTPS_PROXY",
    "HTTP_PROXY",
    "LANG",
    "NO_PROXY",
    "PATH",
    "RUST_BACKTRACE",
    "RUST_LOG",
    "SSL_CERT_DIR",
    "SSL_CERT_FILE",
    "TMPDIR",
    "TZ",
  ]) {
    if (process.env[key]) env[key] = process.env[key];
  }
  return {
    ...env,
    AGENTWEAVE_APP_DATA_ROOT: join(temporaryRoot, "data"),
    AGENTWEAVE_APP_ROOT: plan.appRoot,
    AGENTWEAVE_BUILTIN_SKILLS_MODE: "directory",
    AGENTWEAVE_CACHE_ROOT: join(temporaryRoot, "cache"),
    AGENTWEAVE_DATABASE_URL: `sqlite://${join(temporaryRoot, "data", "agentweave.db")}?mode=rwc`,
    AGENTWEAVE_FAKE_MAIL: "enabled",
    AGENTWEAVE_LAUNCH_CONFIG_FD: "3",
    AGENTWEAVE_LAUNCH_RESULT_FD: "4",
    AGENTWEAVE_MANAGED_SKILLS: "1",
    ...(modelBaseUrl ? {
      AGENTWEAVE_MODEL_BASE_URL: modelBaseUrl,
      AGENTWEAVE_MODEL_ENDPOINT_TYPE: "chat_completions",
      AGENTWEAVE_MODEL_NAME: "packaged-foundation-check",
    } : {}),
    AGENTWEAVE_SKILLS_ROOT: plan.skillsRoot,
    AGENTWEAVE_WORKSPACE_ROOT: join(temporaryRoot, "workspace"),
  };
}

async function startScriptedModelServer() {
  const diagnostics = { lastError: null, lastReply: "none", requests: 0 };
  const server = createServer((request, response) => {
    if (request.method !== "POST" || request.url !== "/v1/chat/completions") {
      response.writeHead(404).end();
      return;
    }
    let body = "";
    request.setEncoding("utf8");
    request.on("data", (chunk) => {
      body += chunk;
      if (body.length > MODEL_REQUEST_LIMIT) request.destroy();
    });
    request.on("end", () => {
      try {
        diagnostics.requests += 1;
        const reply = scriptedModelReply(JSON.parse(body));
        diagnostics.lastReply = reply.choices?.[0]?.message?.tool_calls?.[0]?.id ?? "text";
        response.writeHead(200, { "content-type": "application/json" });
        response.end(JSON.stringify(reply));
      } catch (error) {
        diagnostics.lastError = error instanceof Error ? error.message : String(error);
        response.writeHead(500, { "content-type": "application/json" });
        response.end(JSON.stringify({ error: "scripted model request is invalid" }));
      }
    });
  });
  await new Promise((resolveListen, rejectListen) => {
    server.once("error", rejectListen);
    server.listen(0, "127.0.0.1", () => {
      server.off("error", rejectListen);
      resolveListen();
    });
  });
  const address = server.address();
  if (!address || typeof address === "string") fail("scripted model address is invalid");
  return {
    baseUrl: `http://127.0.0.1:${address.port}/v1`,
    diagnostics,
    close: () => new Promise((resolveClose, rejectClose) => {
      server.close((error) => error ? rejectClose(error) : resolveClose());
    }),
  };
}

export function scriptedModelReply(body) {
  if (!body || typeof body !== "object" || !Array.isArray(body.messages)) {
    fail("scripted model request body is invalid");
  }
  const completed = new Set(body.messages
    .filter((message) => message?.role === "tool" && typeof message.tool_call_id === "string")
    .map((message) => message.tool_call_id));
  if (!completed.has("foundation-memory-propose")) {
    return modelToolCall(body, "memory_propose", "foundation-memory-propose", {
      draft: {
        kind: "user.preference",
        value: { text: "Packaged Foundation state survives restart", attributes: {} },
        evidence: [{
          source: "explicit_user_action",
          sourceId: "packaged-foundation-check",
          excerpt: "Persist this deterministic package-check preference.",
          observedAt: "2026-01-01T00:00:00Z",
        }],
        confidence: 10_000,
        sensitivity: "internal",
        retention: { mode: "persistent" },
        conflictKey: "packaged-foundation-check",
        supersedes: null,
      },
    });
  }
  if (!completed.has("foundation-memory-confirm")) {
    const proposal = successfulToolOutput(body, "foundation-memory-propose");
    return modelToolCall(body, "memory_confirm", "foundation-memory-confirm", {
      id: requireString(proposal.record?.id, "proposed memory identifier"),
      expectedVersion: requirePositiveInteger(
        proposal.record?.version,
        "proposed memory version",
      ),
    });
  }
  if (!completed.has("foundation-mail-draft")) {
    successfulToolOutput(body, "foundation-memory-confirm");
    return modelToolCall(body, "mail_draft_create", "foundation-mail-draft", {
      accountId: "primary",
      content: {
        to: [{ name: "Package Check", address: "recipient@example.test" }],
        cc: [],
        bcc: [],
        subject: "Packaged Foundation persistence check",
        body: { plainText: "This draft remains behind an approval boundary.", html: null },
        attachments: [],
        replyContext: null,
        forwardContext: null,
      },
    });
  }
  if (!completed.has("foundation-mail-preview")) {
    const draft = successfulToolOutput(body, "foundation-mail-draft");
    return modelToolCall(body, "mail_send_preview", "foundation-mail-preview", {
      accountId: "primary",
      draftId: requireString(draft.id, "Mail draft identifier"),
      expectedRevision: requirePositiveInteger(draft.revision, "Mail draft revision"),
    });
  }
  successfulToolOutput(body, "foundation-mail-preview");
  return {
    choices: [{
      finish_reason: "stop",
      message: { content: "Packaged Foundation scenario completed." },
    }],
  };
}

function modelToolCall(body, canonicalName, callId, argumentsValue) {
  const suffix = `_${canonicalName}`;
  const tool = Array.isArray(body.tools)
    ? body.tools.find((candidate) => (
      candidate?.function?.name === canonicalName
      || candidate?.function?.name?.endsWith(suffix)
    ))
    : undefined;
  if (!tool) fail(`scripted model is missing '${canonicalName}'`);
  return {
    choices: [{
      finish_reason: "tool_calls",
      message: {
        content: null,
        tool_calls: [{
          id: callId,
          type: "function",
          function: {
            name: tool.function.name,
            arguments: JSON.stringify(argumentsValue),
          },
        }],
      },
    }],
  };
}

function successfulToolOutput(body, callId) {
  const message = body.messages.find((candidate) => (
    candidate?.role === "tool" && candidate.tool_call_id === callId
  ));
  if (!message) fail(`scripted model is missing tool result '${callId}'`);
  let result;
  try {
    result = typeof message.content === "string" ? JSON.parse(message.content) : message.content;
  } catch {
    fail(`scripted model tool result '${callId}' is invalid`);
  }
  return successfulToolResultData(result, `scripted model tool result '${callId}'`);
}

function successfulToolResultData(result, label) {
  if (!result || result.ok !== true || !result.data || typeof result.data !== "object") {
    const code = typeof result?.error?.code === "string" ? result.error.code : "unknown";
    const message = typeof result?.error?.message === "string" ? result.error.message : "unknown";
    fail(`${label} failed (${code}: ${message})`);
  }
  if (result.data.ok === false) {
    const code = typeof result.data?.error?.code === "string" ? result.data.error.code : "unknown";
    fail(`${label} failed (${code})`);
  }
  if (typeof result.data.connector_id === "string"
    && result.data.output
    && typeof result.data.output === "object") {
    return result.data.output;
  }
  return result.data.ok === true && result.data.output && typeof result.data.output === "object"
    ? result.data.output
    : result.data;
}

function requirePositiveInteger(value, label) {
  if (!Number.isSafeInteger(value) || value < 1) fail(`${label} is invalid`);
  return value;
}

async function createPackagedFoundationState(origin, token) {
  const session = await requestJson(origin, token, "/sessions", {
    body: { title: "Packaged Foundation check" },
    method: "POST",
    status: 200,
  });
  const sessionId = requireString(session.id, "Foundation check session identifier");
  const started = await requestJson(origin, token, `/sessions/${encodeURIComponent(sessionId)}/turns`, {
    body: {
      requestId: randomUUID(),
      content: "Persist the deterministic check state and prepare the approval-bound Mail action.",
    },
    method: "POST",
    status: 202,
  });
  const turnId = requireString(started.turn?.id, "Foundation check turn identifier");
  const turn = await waitForTurn(origin, token, sessionId, turnId);
  if (turn.turn?.status !== "completed") fail("packaged Foundation turn did not complete");
  const previewEvent = turn.events.find((event) => (
    event?.payload?.type === "tool_call_finished"
    && event.payload.call_id === "foundation-mail-preview"
  ));
  assertPackagedMailPreviewEvent(previewEvent);
}

export function assertPackagedMailPreviewEvent(event) {
  const payload = event?.payload;
  if (
    payload?.type !== "tool_call_finished"
    || payload.call_id !== "foundation-mail-preview"
    || payload.persistence !== "metadata_only"
    || Object.hasOwn(payload, "result")
    || payload.result_metadata?.ok !== true
  ) {
    fail("packaged Mail preview persistence policy is invalid");
  }
  return true;
}

async function waitForTurn(origin, token, sessionId, turnId) {
  const deadline = Date.now() + TURN_TIMEOUT_MS;
  const path = `/sessions/${encodeURIComponent(sessionId)}/turns/${encodeURIComponent(turnId)}`;
  const events = [];
  let cursor = -1;
  let lastStatus = "unknown";
  while (Date.now() < deadline) {
    const page = await requestJson(
      origin,
      token,
      `${path}/events?after=${cursor}&limit=100&waitMs=2500`,
      { method: "GET", status: 200 },
    );
    if (!Array.isArray(page.events) || !Number.isSafeInteger(page.nextCursor)) {
      fail("packaged Foundation turn event page is invalid");
    }
    events.push(...page.events);
    cursor = page.nextCursor;
    lastStatus = page.turn?.status ?? "missing";
    if (page.turn?.status !== "running") return { ...page, events };
  }
  const eventTypes = events.map((event) => event?.payload?.type ?? "invalid").join(",");
  fail(`packaged Foundation turn timed out (${lastStatus}; events: ${eventTypes})`);
}

async function assertPackagedFoundationState(origin, token) {
  const memories = await requestJson(
    origin,
    token,
    "/foundation/memory?query=Packaged%20Foundation&limit=20",
    { method: "GET", status: 200 },
  );
  if (!Array.isArray(memories) || !memories.some((memory) => (
    memory?.state === "committed"
    && memory?.value?.text === "Packaged Foundation state survives restart"
  ))) {
    fail("packaged committed Memory state is missing");
  }
  const actions = await requestJson(origin, token, "/foundation/actions", {
    method: "GET",
    status: 200,
  });
  if (!Array.isArray(actions) || !actions.some((item) => (
    item?.action?.status === "waiting_approval"
    && item?.approval?.status === "pending"
    && item?.preview?.accountId === "primary"
    && typeof item?.preview?.idempotencyKey === "string"
    && item.preview.idempotencyKey.length > 0
  ))) {
    fail("packaged approval-bound Action state is missing");
  }
}

async function requestJson(origin, token, path, { body, method, status }) {
  const response = await fetch(new URL(path, origin), {
    method,
    headers: {
      "X-AgentWeave-Transport": token,
      ...(body === undefined ? {} : { "content-type": "application/json" }),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    signal: AbortSignal.timeout(5_000),
  });
  if (response.status !== status) {
    fail(`expected ${method} ${path} HTTP ${status}, received ${response.status}`);
  }
  try {
    return await response.json();
  } catch {
    fail(`${method} ${path} response body is invalid JSON`);
  }
}

function readHandshake(child, launchId, token, readStderr) {
  return new Promise((resolveHandshake, rejectHandshake) => {
    let settled = false;
    let data = "";
    const timer = setTimeout(() => finish(new Error("packaged sidecar launch handshake timed out")), START_TIMEOUT_MS);
    const finish = (error, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (error) rejectHandshake(withLogs(error, readStderr()));
      else resolveHandshake(value);
    };
    child.once("error", () => finish(new Error("packaged sidecar failed to spawn")));
    child.once("exit", (code, signal) => {
      finish(new Error(`packaged sidecar exited before launch handshake (${signal ?? code ?? "unknown"})`));
    });
    child.stdio[4].on("data", (chunk) => {
      data += chunk.toString();
      if (data.length > HANDSHAKE_LIMIT) return finish(new Error("packaged sidecar launch handshake is too large"));
      const newline = data.indexOf("\n");
      if (newline < 0) return;
      let result;
      try {
        result = JSON.parse(data.slice(0, newline));
      } catch {
        return finish(new Error("packaged sidecar launch handshake is invalid"));
      }
      if (
        result.schemaVersion !== 1
        || result.launchId !== launchId
        || result.pid !== child.pid
        || typeof result.origin !== "string"
        || Object.hasOwn(result, "transportToken")
      ) {
        return finish(new Error("packaged sidecar returned an invalid launch handshake"));
      }
      let origin;
      try {
        origin = new URL(result.origin);
      } catch {
        return finish(new Error("packaged sidecar returned an invalid dynamic origin"));
      }
      if (origin.protocol !== "http:" || origin.hostname !== "127.0.0.1" || origin.pathname !== "/") {
        return finish(new Error("packaged sidecar returned an unsafe dynamic origin"));
      }
      return finish(null, { origin: origin.href, token });
    });
  });
}

function withLogs(error, logs) {
  return logs ? new Error(`${error.message}\n${logs}`) : error;
}

async function expectResponse(origin, token, path, expectedStatus, expectedBody) {
  const headers = token ? { "X-AgentWeave-Transport": token } : {};
  const response = await fetch(new URL(path, origin), {
    headers,
    signal: AbortSignal.timeout(5_000),
  });
  if (response.status !== expectedStatus) {
    fail(`expected ${path} HTTP ${expectedStatus}, received ${response.status}`);
  }
  if (expectedBody !== undefined && await response.text() !== expectedBody) {
    fail(`${path} response body is invalid`);
  }
}

async function expectJson(origin, token, path) {
  const response = await fetch(new URL(path, origin), {
    headers: { "X-AgentWeave-Transport": token },
    signal: AbortSignal.timeout(5_000),
  });
  if (response.status !== 200) fail(`expected ${path} HTTP 200, received ${response.status}`);
  try {
    return await response.json();
  } catch {
    fail(`${path} response body is invalid JSON`);
  }
}

async function stopChild(child) {
  if (child.exitCode !== null || child.signalCode !== null) return;
  const exited = new Promise((resolveExit) => child.once("exit", resolveExit));
  child.kill("SIGTERM");
  const stopped = await Promise.race([
    exited.then(() => true),
    new Promise((resolveWait) => setTimeout(() => resolveWait(false), STOP_TIMEOUT_MS)),
  ]);
  if (!stopped && child.exitCode === null && child.signalCode === null) {
    child.kill("SIGKILL");
    await exited;
    fail("packaged sidecar did not stop after SIGTERM");
  }
}

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 1) {
    const option = argv[index];
    if (option === "--help" || option === "-h") return { help: true };
    if (option === "--print-plan") {
      args.printPlan = true;
      continue;
    }
    if (option !== "--app") fail(`unknown argument '${option}'`);
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) fail("--app requires a value");
    args.app = value;
    index += 1;
  }
  return args;
}

function usage() {
  return "Usage: node scripts/check-packaged-sidecar.mjs --app <path-to-app> [--print-plan]";
}

export async function runCli(argv = process.argv.slice(2)) {
  const args = parseArgs(argv);
  if (args.help) return console.log(usage());
  if (!args.app) fail(`--app is required\n${usage()}`);
  if (args.printPlan) {
    const plan = packagedSidecarPlan(args.app);
    console.log(JSON.stringify({
      bundleRoot: plan.bundleRoot,
      expected: plan.expected,
      sidecarPath: plan.sidecarPath,
    }, null, 2));
    return;
  }
  const plan = await checkPackagedSidecar(args.app);
  console.log(`Packaged sidecar check passed for ${plan.expected.displayName}`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  runCli().catch((error) => {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  });
}
