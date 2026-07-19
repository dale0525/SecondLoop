import { createHash } from "node:crypto";
import { mkdir, open, readFile, realpath, rename, rm, stat } from "node:fs/promises";
import path from "node:path";

import {
  computeProviderPublicConfigHash,
  computeProjectDesiredHash,
  computeRuntimeProjectionHash,
  projectRuntimeProjection,
  validateAgentWeaveProjectData,
  validateDeploymentLockData,
  validateProjectMatchesRuntime,
} from "../../../../scripts/agentweave-project.mjs";
import type {
  DeveloperGatewayDeploymentReceipt,
  DeveloperGatewayTestReceipt,
} from "../shared/developerAccess";
import {
  DEVELOPER_PROJECT_LOAD_CHANNEL,
  DEVELOPER_PROJECT_PACKAGE_CHANNEL,
  DEVELOPER_PROJECT_SAVE_CHANNEL,
  DEVELOPER_PROJECT_SHOW_OUTPUT_CHANNEL,
  type DeveloperPackageReceipt,
  type DeveloperProjectSaveRequest,
  type DeveloperProjectSnapshot,
  type DeveloperVerifiedDeployment,
} from "../shared/developerProject";

const MAX_DOCUMENT_BYTES = 256 * 1024;
const REVISION_PATTERN = /^[a-f0-9]{64}$/;
const projectMutations = new Map<string, Promise<void>>();

type IpcEvent = { sender: { id: number } };
type IpcMainLike = {
  handle(channel: string, handler: (event: IpcEvent, value: unknown) => unknown): void;
  removeHandler(channel: string): void;
};

type Journal = {
  schemaVersion: 1;
  manifest: Record<string, unknown>;
  project: Record<string, unknown>;
};

export function registerDeveloperProjectController(options: {
  appRoot: string | null;
  ipcMain: IpcMainLike;
  packageApp: (appRoot: string) => Promise<DeveloperPackageReceipt>;
  refreshRuntime?: () => Promise<void>;
  requesterWebContents: { id: number };
  showItemInFolder: (outputPath: string) => void;
}): () => void {
  let lastOutputPath: string | null = null;
  const trusted = (event: IpcEvent) => {
    if (event.sender.id !== options.requesterWebContents.id) {
      throw new Error("Developer project access is restricted to the requester window");
    }
  };
  const serialize = <T>(operation: (root: string) => Promise<T>): Promise<T> =>
    serializeProjectMutation(options.appRoot, operation);

  options.ipcMain.handle(DEVELOPER_PROJECT_LOAD_CHANNEL, async (event) => {
    trusted(event);
    return serialize(loadSnapshot);
  });
  options.ipcMain.handle(DEVELOPER_PROJECT_SAVE_CHANNEL, async (event, value) => {
    trusted(event);
    const request = parseSaveRequest(value);
    return serialize(async (root) => {
      const snapshot = await saveProject(root, request);
      await options.refreshRuntime?.();
      return snapshot;
    });
  });
  options.ipcMain.handle(DEVELOPER_PROJECT_PACKAGE_CHANNEL, async (event) => {
    trusted(event);
    return serialize(async (root) => {
      const snapshot = await loadSnapshot(root);
      if (snapshot.deploymentStatus === "missing" || snapshot.deploymentStatus === "stale") {
        throw new Error("The model gateway must be deployed and verified before packaging");
      }
      const receipt = await options.packageApp(root);
      lastOutputPath = await validateOutputPath(root, receipt.outputPath);
      return { ...receipt, outputPath: lastOutputPath };
    });
  });
  options.ipcMain.handle(DEVELOPER_PROJECT_SHOW_OUTPUT_CHANNEL, async (event) => {
    trusted(event);
    if (!lastOutputPath) throw new Error("No packaged output is available");
    options.showItemInFolder(lastOutputPath);
  });

  return () => {
    for (const channel of [
      DEVELOPER_PROJECT_LOAD_CHANNEL,
      DEVELOPER_PROJECT_SAVE_CHANNEL,
      DEVELOPER_PROJECT_PACKAGE_CHANNEL,
      DEVELOPER_PROJECT_SHOW_OUTPUT_CHANNEL,
    ]) options.ipcMain.removeHandler(channel);
  };
}

export async function loadDeveloperProjectSnapshot(
  appRoot: string | null,
): Promise<DeveloperProjectSnapshot> {
  return serializeProjectMutation(appRoot, loadSnapshot);
}

export async function recordDeveloperGatewayDeployment(options: {
  appRoot: string | null;
  expectedRevision: string;
  receipt: DeveloperGatewayDeploymentReceipt;
}): Promise<DeveloperProjectSnapshot> {
  if (!REVISION_PATTERN.test(options.expectedRevision)) {
    throw new Error("Developer project revision is invalid");
  }
  return serializeProjectMutation(options.appRoot, async (root) => {
    const current = await loadSnapshot(root);
    if (current.revision !== options.expectedRevision) {
      throw new Error("Developer project changed after the deployment plan was created");
    }
    const project = projectWithDeploymentEndpoint(current.project, options.receipt);
    const manifest = {
      ...current.manifest,
      schemaVersion: 2,
      ...projectRuntimeProjection(project),
    };
    validateProjectMatchesRuntime(project, manifest);
    await writePairWithJournal(root, manifest, project);
    await rm(path.join(root, ".agentweave", "deployment.lock"), { force: true });
    return loadSnapshot(root);
  });
}

export async function verifyDeveloperGatewayDeployment(options: {
  appRoot: string | null;
  deployment: DeveloperGatewayDeploymentReceipt;
  expectedRevision: string;
  test: DeveloperGatewayTestReceipt;
}): Promise<DeveloperProjectSnapshot> {
  if (!REVISION_PATTERN.test(options.expectedRevision)) {
    throw new Error("Developer project revision is invalid");
  }
  return serializeProjectMutation(options.appRoot, async (root) => {
    const current = await loadSnapshot(root);
    if (current.revision !== options.expectedRevision) {
      throw new Error("Developer project changed before gateway verification completed");
    }
    const project = projectWithDeploymentEndpoint(current.project, options.deployment);
    const manifest = current.manifest;
    validateProjectMatchesRuntime(project, manifest);
    validateGatewayTestReceipt(options.deployment, options.test);
    const gateway = providerGateway(project);
    const lock = {
      schemaVersion: 1,
      desiredHash: computeProjectDesiredHash(project),
      runtimeProjectionHash: computeRuntimeProjectionHash(manifest),
      gateway: {
        id: gateway.id,
        version: gateway.version,
        publicConfigHash: computeProviderPublicConfigHash(gateway),
      },
      deployment: {
        provider: "cloudflare",
        reference: {
          accountId: options.deployment.target.accountId,
          workerName: options.deployment.target.workerName,
          ...(options.deployment.target.environment === undefined
            ? {}
            : { environment: options.deployment.target.environment }),
          versionId: options.deployment.versionId,
          deploymentId: options.deployment.target.deploymentId,
          endpoint: runtimeGatewayBaseUrl(options.deployment.endpoint),
        },
      },
    };
    validateDeploymentLockData(lock, { app: manifest, project });
    await writeJsonAtomic(path.join(root, ".agentweave", "deployment.lock"), lock, 0o600);
    return loadSnapshot(root);
  });
}

export async function invalidateDeveloperGatewayDeployment(options: {
  appRoot: string | null;
  expectedRevision?: string;
}): Promise<DeveloperProjectSnapshot> {
  if (options.expectedRevision !== undefined && !REVISION_PATTERN.test(options.expectedRevision)) {
    throw new Error("Developer project revision is invalid");
  }
  return serializeProjectMutation(options.appRoot, async (root) => {
    const current = await loadSnapshot(root);
    if (options.expectedRevision !== undefined && current.revision !== options.expectedRevision) {
      throw new Error("Developer project changed before deployment state was invalidated");
    }
    await rm(path.join(root, ".agentweave", "deployment.lock"), { force: true });
    return loadSnapshot(root);
  });
}

function validateGatewayTestReceipt(
  deployment: DeveloperGatewayDeploymentReceipt,
  test: DeveloperGatewayTestReceipt,
): void {
  if (
    test.remoteVersion !== deployment.versionId
    || test.protocolVersion.length === 0
    || test.protocolVersion.length > 64
    || !Number.isSafeInteger(test.testedAtUnixMs)
    || test.testedAtUnixMs <= 0
    || test.target.accountId !== deployment.target.accountId
    || test.target.deploymentId !== deployment.target.deploymentId
    || test.target.workerName !== deployment.target.workerName
    || test.target.environment !== deployment.target.environment
  ) {
    throw new Error("Gateway verification receipt does not match the deployment");
  }
}

async function serializeProjectMutation<T>(
  appRoot: string | null,
  operation: (root: string) => Promise<T>,
): Promise<T> {
  const root = await configuredRoot(appRoot);
  const previous = projectMutations.get(root) ?? Promise.resolve();
  const result = previous.then(() => operation(root), () => operation(root));
  const settled = result.then(() => undefined, () => undefined);
  projectMutations.set(root, settled);
  try {
    return await result;
  } finally {
    if (projectMutations.get(root) === settled) projectMutations.delete(root);
  }
}

async function configuredRoot(value: string | null): Promise<string> {
  if (!value || !path.isAbsolute(value)) {
    throw new Error("Developer project root is not configured");
  }
  const root = await realpath(value);
  const metadata = await stat(root);
  if (!metadata.isDirectory()) throw new Error("Developer project root is invalid");
  return root;
}

async function loadSnapshot(root: string): Promise<DeveloperProjectSnapshot> {
  await recoverJournal(root);
  const manifest = await readJsonObject(path.join(root, "agent-app.json"), "Agent App manifest");
  const project = await readJsonObject(
    path.join(root, "agentweave-project.json"),
    "AgentWeave project configuration",
  );
  validateAgentWeaveProjectData(project);
  validateProjectMatchesRuntime(project, manifest);
  const lockPath = path.join(root, ".agentweave", "deployment.lock");
  let deploymentStatus: DeveloperProjectSnapshot["deploymentStatus"] = "not_required";
  let deploymentMessage: string | null = null;
  let verifiedDeployment: DeveloperVerifiedDeployment | null = null;
  if (modelPolicy(project) === "app_managed") {
    try {
      const lock = await readOptionalJsonObject(lockPath, "Deployment lock");
      if (lock === null) {
        deploymentStatus = "missing";
        deploymentMessage = "Deploy and verify the configured gateway before packaging.";
      } else {
        validateDeploymentLockData(lock, { app: manifest, project });
        deploymentStatus = "ready";
        verifiedDeployment = verifiedDeploymentFromLock(lock);
      }
    } catch (error) {
      deploymentStatus = "stale";
      deploymentMessage = safeMessage(error, "Deployment state no longer matches this project.");
    }
  }
  return {
    appRoot: root,
    revision: revisionFor(manifest, project),
    desiredHash: computeProjectDesiredHash(project),
    manifest,
    project,
    deploymentStatus,
    deploymentMessage,
    verifiedDeployment,
  };
}

function verifiedDeploymentFromLock(lock: Record<string, unknown>): DeveloperVerifiedDeployment {
  const deployment = lock.deployment as Record<string, unknown>;
  const reference = deployment.reference as Record<string, unknown>;
  return Object.freeze({
    target: Object.freeze({
      accountId: String(reference.accountId),
      deploymentId: String(reference.deploymentId),
      workerName: String(reference.workerName),
      ...(reference.environment === undefined ? {} : { environment: String(reference.environment) }),
    }),
    versionId: String(reference.versionId),
    endpoint: String(reference.endpoint),
  });
}

async function saveProject(
  root: string,
  request: DeveloperProjectSaveRequest,
): Promise<DeveloperProjectSnapshot> {
  const current = await loadSnapshot(root);
  if (current.revision !== request.expectedRevision) {
    throw new Error("Developer project changed on disk; reload before saving");
  }
  const project = cloneRecord(validateAgentWeaveProjectData(request.project));
  const projection = projectRuntimeProjection(project);
  const manifest = {
    ...current.manifest,
    schemaVersion: 2,
    ...projection,
  };
  validateProjectMatchesRuntime(project, manifest);
  await writePairWithJournal(root, manifest, project);
  return loadSnapshot(root);
}

async function writePairWithJournal(
  root: string,
  manifest: Record<string, unknown>,
  project: Record<string, unknown>,
): Promise<void> {
  const stateRoot = path.join(root, ".agentweave");
  await ensureRealDirectory(stateRoot);
  const journal: Journal = { schemaVersion: 1, manifest, project };
  const journalPath = path.join(stateRoot, "project-save.journal");
  await writeJsonAtomic(journalPath, journal, 0o600);
  await writeJsonAtomic(path.join(root, "agentweave-project.json"), project, 0o600);
  await writeJsonAtomic(path.join(root, "agent-app.json"), manifest, 0o600);
  await rm(journalPath, { force: true });
}

async function recoverJournal(root: string): Promise<void> {
  const journalPath = path.join(root, ".agentweave", "project-save.journal");
  const journal = await readOptionalJsonObject(journalPath, "Project save journal");
  if (!journal) return;
  if (journal.schemaVersion !== 1 || !isRecord(journal.manifest) || !isRecord(journal.project)) {
    throw new Error("Project save journal is invalid");
  }
  validateAgentWeaveProjectData(journal.project);
  validateProjectMatchesRuntime(journal.project, journal.manifest);
  await writeJsonAtomic(path.join(root, "agentweave-project.json"), journal.project, 0o600);
  await writeJsonAtomic(path.join(root, "agent-app.json"), journal.manifest, 0o600);
  await rm(journalPath, { force: true });
}

async function readJsonObject(filePath: string, label: string): Promise<Record<string, unknown>> {
  const value = await readOptionalJsonObject(filePath, label);
  if (!value) throw new Error(`${label} is missing`);
  return value;
}

async function readOptionalJsonObject(
  filePath: string,
  label: string,
): Promise<Record<string, unknown> | null> {
  let handle;
  try {
    handle = await open(filePath, "r");
  } catch (error) {
    if (isNodeError(error, "ENOENT")) return null;
    throw error;
  }
  try {
    const metadata = await handle.stat();
    if (!metadata.isFile() || metadata.size > MAX_DOCUMENT_BYTES) {
      throw new Error(`${label} is not an allowed file`);
    }
    const text = await handle.readFile("utf8");
    const value: unknown = JSON.parse(text);
    if (!isRecord(value)) throw new Error(`${label} must be a JSON object`);
    return value;
  } catch (error) {
    throw new Error(safeMessage(error, `${label} is invalid`));
  } finally {
    await handle.close();
  }
}

async function writeJsonAtomic(filePath: string, value: unknown, mode: number): Promise<void> {
  const parent = path.dirname(filePath);
  await ensureRealDirectory(parent);
  const temporary = path.join(parent, `.${path.basename(filePath)}.${process.pid}.${Date.now()}.tmp`);
  const handle = await open(temporary, "wx", mode);
  try {
    await handle.writeFile(`${JSON.stringify(value, null, 2)}\n`, "utf8");
    await handle.sync();
  } finally {
    await handle.close();
  }
  try {
    await rename(temporary, filePath);
  } finally {
    await rm(temporary, { force: true });
  }
}

async function ensureRealDirectory(directory: string): Promise<void> {
  await mkdir(directory, { recursive: true, mode: 0o700 });
  const metadata = await stat(directory);
  if (!metadata.isDirectory()) throw new Error("Developer project state directory is invalid");
  const canonical = await realpath(directory);
  if (canonical !== path.resolve(directory)) {
    throw new Error("Developer project state directory must not use symlinks");
  }
}

function parseSaveRequest(value: unknown): DeveloperProjectSaveRequest {
  if (!isRecord(value)
    || Object.keys(value).some((key) => key !== "expectedRevision" && key !== "project")
    || typeof value.expectedRevision !== "string"
    || !REVISION_PATTERN.test(value.expectedRevision)
    || !Object.hasOwn(value, "project")) {
    throw new Error("Developer project save request is invalid");
  }
  return { expectedRevision: value.expectedRevision, project: value.project };
}

function revisionFor(manifest: unknown, project: unknown): string {
  return createHash("sha256")
    .update(JSON.stringify([manifest, project]), "utf8")
    .digest("hex");
}

function modelPolicy(project: Record<string, unknown>): string | null {
  const access = isRecord(project.modelAccess) ? project.modelAccess : null;
  return typeof access?.configurationPolicy === "string" ? access.configurationPolicy : null;
}

function projectWithDeploymentEndpoint(
  source: Record<string, unknown>,
  receipt: DeveloperGatewayDeploymentReceipt,
): Record<string, unknown> {
  const project = cloneRecord(source);
  const gateway = providerGateway(project);
  if (receipt.providerId !== gateway.id || receipt.providerVersion !== gateway.version) {
    throw new Error("Deployment receipt does not match the selected gateway plugin");
  }
  const deployment = isRecord(project.deployment) && isRecord(project.deployment.cloudflare)
    ? project.deployment.cloudflare
    : null;
  if (
    !deployment
    || deployment.accountId !== receipt.target.accountId
    || deployment.workerName !== receipt.target.workerName
    || deployment.environment !== receipt.target.environment
  ) {
    throw new Error("Deployment receipt does not match the developer project target");
  }
  const modelAccess = isRecord(project.modelAccess) ? project.modelAccess : null;
  const profile = modelAccess && isRecord(modelAccess.profile) ? modelAccess.profile : null;
  if (modelAccess?.configurationPolicy !== "app_managed" || !profile) {
    throw new Error("Deployment receipt requires app-managed model access");
  }
  if (
    typeof receipt.endpoint !== "string"
    || receipt.endpoint.length > 2_048
    || typeof receipt.versionId !== "string"
    || receipt.versionId.length === 0
    || receipt.versionId.length > 128
    || typeof receipt.target.deploymentId !== "string"
    || receipt.target.deploymentId.length === 0
    || receipt.target.deploymentId.length > 128
  ) {
    throw new Error("Deployment receipt is invalid");
  }
  project.modelAccess = {
    ...modelAccess,
    profile: { ...profile, baseUrl: runtimeGatewayBaseUrl(receipt.endpoint) },
  };
  validateAgentWeaveProjectData(project);
  return project;
}

function runtimeGatewayBaseUrl(endpoint: string): string {
  return `${endpoint.replace(/\/$/, "")}/v1`;
}

function providerGateway(project: Record<string, unknown>): Record<string, unknown> {
  const providers = isRecord(project.providers) ? project.providers : null;
  const gateway = providers && isRecord(providers.gateway) ? providers.gateway : null;
  if (!gateway) throw new Error("Developer project gateway plugin is unavailable");
  return gateway;
}

async function validateOutputPath(root: string, outputPath: string): Promise<string> {
  const output = await realpath(outputPath);
  const allowedRoot = path.resolve(root, "..");
  const relative = path.relative(allowedRoot, output);
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative)) {
    throw new Error("Packaged output path is outside the developer project");
  }
  return output;
}

function cloneRecord(value: unknown): Record<string, unknown> {
  if (!isRecord(value)) throw new Error("Developer project configuration is invalid");
  return JSON.parse(JSON.stringify(value)) as Record<string, unknown>;
}

function safeMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message && !/[\r\n]/.test(error.message)
    ? error.message.slice(0, 500)
    : fallback;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isNodeError(error: unknown, code: string): boolean {
  return error instanceof Error && "code" in error && error.code === code;
}
