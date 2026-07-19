import { createHash } from "node:crypto";
import {
  copyFileSync,
  existsSync,
  lstatSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { basename, dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

import {
  PROJECT_ROOT,
  resolveConfinedPath,
  validateAgentApp,
} from "./scaffold-agent-app.mjs";
import {
  AGENTWEAVE_PROJECT_FILE,
  hashPublicValue,
  runtimeProviderProjection,
  validateAgentWeaveProjectWorkspace,
} from "./agentweave-project.mjs";

export const AGENT_APP_LOCK_SCHEMA_VERSION = 1;
const DEFAULT_RUNTIME_VERSION = "0.1.0";
const LOCK_FILE = "agent-app.lock.json";
const FORBIDDEN_RELEASE_FILE = /(^|\/)(\.env(?:\..*)?|.*\.(?:key|p12|pem|pfx)|credentials?\.json|secrets?\.json)$/i;
const DEVELOPER_ONLY_DIRECTORIES = new Set([".agentweave", ".git", ".github", ".idea", ".vscode"]);
const DEVELOPER_ONLY_FILES = new Set([
  AGENTWEAVE_PROJECT_FILE,
  "AGENTS.md",
  ".editorconfig",
  ".gitattributes",
  ".gitignore",
]);
const ARTIFACT_SECRET_PATTERNS = [
  ["private key", /-----BEGIN (?:EC |OPENSSH |RSA )?PRIVATE KEY-----/],
  ["bearer authorization", /\bAuthorization\s*[:=]\s*Bearer\s+[A-Za-z0-9._~+/-]{12,}={0,2}\b/i],
  ["OpenAI-style key", /\bsk[-_][A-Za-z0-9_-]{16,}\b/],
  ["GitHub token", /\bgh[pousr]_[A-Za-z0-9]{20,}\b/],
  ["Slack token", /\bxox[baprs]-[A-Za-z0-9-]{16,}\b/],
  ["AWS access key", /\bAKIA[0-9A-Z]{16}\b/],
];
const CREDENTIAL_ASSIGNMENT_PATTERN = /(?:^|[\r\n,{]\s*)["']?([A-Za-z0-9_.-]*(?:api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|password|credential|secret)[A-Za-z0-9_.-]*)["']?\s*[:=]\s*(?:"([^"\r\n]+)"|'([^'\r\n]+)'|([^\s,}\]#]+))/gim;

function fail(message) {
  throw new Error(message);
}

function normalized(path) {
  return path.split(sep).join("/");
}

function isDeveloperOnlyReleasePath(path) {
  const segments = normalized(path).split("/");
  return segments.some((segment) => DEVELOPER_ONLY_DIRECTORIES.has(segment))
    || DEVELOPER_ONLY_FILES.has(segments.at(-1));
}

function isCredentialPlaceholder(value) {
  const normalizedValue = value.trim().replaceAll(/^["']|["';]$/g, "").toLowerCase();
  return normalizedValue === ""
    || ["null", "none", "undefined", "string", "redacted", "masked", "placeholder"].includes(normalizedValue)
    || normalizedValue.startsWith("${")
    || normalizedValue.startsWith("{{")
    || normalizedValue.startsWith("<")
    || normalizedValue.startsWith("your-")
    || normalizedValue.startsWith("your_")
    || normalizedValue.startsWith("replace-")
    || normalizedValue.startsWith("replace_");
}

function isCredentialValueField(value) {
  const normalizedValue = value.toLowerCase().replaceAll(/[^a-z0-9]/g, "");
  if (["id", "name", "reference", "scope", "slot", "type"].some((suffix) => normalizedValue.endsWith(suffix))) {
    return false;
  }
  return normalizedValue.includes("apikey")
    || normalizedValue.includes("accesstoken")
    || normalizedValue.includes("refreshtoken")
    || normalizedValue.includes("clientsecret")
    || normalizedValue.includes("password")
    || ["credential", "credentials", "credentialdata", "credentialvalue", "secret", "secrets", "secretvalue"].includes(normalizedValue);
}

function scanCredentialMarkers(bytes, path) {
  const content = Buffer.isBuffer(bytes) ? bytes.toString("utf8") : String(bytes);
  for (const [label, pattern] of ARTIFACT_SECRET_PATTERNS) {
    if (pattern.test(content)) fail(`release artifact contains ${label} credential marker in '${path}'`);
  }
  CREDENTIAL_ASSIGNMENT_PATTERN.lastIndex = 0;
  for (const match of content.matchAll(CREDENTIAL_ASSIGNMENT_PATTERN)) {
    const value = match[2] ?? match[3] ?? match[4] ?? "";
    if (isCredentialValueField(match[1]) && !isCredentialPlaceholder(value)) {
      fail(`release artifact contains credential assignment marker '${match[1]}' in '${path}'`);
    }
  }
}

function requireSemver(value, label) {
  if (typeof value !== "string" || !/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(value)) {
    fail(`${label} must be a semantic version`);
  }
}

function listRegularFiles(root, prefix = "") {
  const directory = prefix ? join(root, prefix) : root;
  const files = [];
  for (const entry of readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    const path = prefix ? join(prefix, entry.name) : entry.name;
    const absolute = join(root, path);
    if (entry.isSymbolicLink() || lstatSync(absolute).isSymbolicLink()) {
      fail(`release input contains symbolic link '${normalized(path)}'`);
    }
    if (entry.isDirectory()) files.push(...listRegularFiles(root, path));
    else if (entry.isFile()) files.push(path);
    else fail(`release input contains unsupported entry '${normalized(path)}'`);
  }
  return files.sort((left, right) => normalized(left).localeCompare(normalized(right)));
}

function inspectTree(
  root,
  { excluded = new Set(), excludeDeveloperFiles = false, overrides = new Map() } = {},
) {
  const files = listRegularFiles(root).filter((path) => {
    const portable = normalized(path);
    return !excluded.has(portable) && !(excludeDeveloperFiles && isDeveloperOnlyReleasePath(portable));
  });
  if (files.length === 0) fail(`release input '${root}' is empty`);
  const digest = createHash("sha256");
  for (const path of files) {
    const portable = normalized(path);
    if (FORBIDDEN_RELEASE_FILE.test(portable)) {
      fail(`release input contains forbidden credential file '${portable}'`);
    }
    const bytes = overrides.get(portable) ?? readFileSync(join(root, path));
    scanCredentialMarkers(bytes, portable);
    digest.update(portable, "utf8");
    digest.update("\0", "utf8");
    digest.update(String(bytes.length), "ascii");
    digest.update("\0", "utf8");
    digest.update(bytes);
  }
  return { contentHash: digest.digest("hex"), files, overrides };
}

function copyInspectedTree(root, inspection, destination) {
  mkdirSync(destination, { recursive: true });
  for (const path of inspection.files) {
    const target = join(destination, path);
    mkdirSync(dirname(target), { recursive: true });
    const replacement = inspection.overrides?.get(normalized(path));
    if (replacement) writeFileSync(target, replacement);
    else copyFileSync(join(root, path), target);
  }
}

function readJson(path, label) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    fail(`${label} is invalid JSON: ${error instanceof Error ? error.message : String(error)}`);
  }
}

function localPackageSources(appRoot) {
  const packagesRoot = join(appRoot, "packages");
  const result = new Map();
  if (!existsSync(packagesRoot)) return result;
  for (const entry of readdirSync(packagesRoot, { withFileTypes: true })) {
    if (!entry.isDirectory() || entry.isSymbolicLink()) continue;
    const root = join(packagesRoot, entry.name);
    const manifestPath = join(root, "agentweave.json");
    if (!existsSync(manifestPath)) continue;
    const manifest = readJson(manifestPath, `${entry.name} package manifest`);
    if (result.has(manifest.id)) fail(`Agent App contains duplicate package '${manifest.id}'`);
    result.set(manifest.id, { root, source: "app" });
  }
  return result;
}

function selectedPackageSources(appRoot, app, catalog) {
  const appPackages = localPackageSources(appRoot);
  const catalogById = new Map(catalog.skills.map((skill) => [skill.id, skill]));
  return app.requires.packages.map((requirement) => {
    const local = appPackages.get(requirement.id);
    if (local) return { ...local, id: requirement.id };
    const catalogEntry = catalogById.get(requirement.id);
    if (!catalogEntry?.localPackage?.path) {
      fail(`selected package '${requirement.id}' has no distributable source`);
    }
    return {
      id: requirement.id,
      root: resolveConfinedPath(PROJECT_ROOT, catalogEntry.localPackage.path, `${requirement.id} source`),
      source: "first_party",
    };
  });
}

function prepareOutput(output) {
  const root = resolveConfinedPath(PROJECT_ROOT, output, "release output");
  if (existsSync(root)) {
    if (!statSync(root).isDirectory()) fail("release output exists and is not a directory");
    if (readdirSync(root).length > 0) fail("release output directory must be empty");
  }
  return root;
}

function requestedLocales(value) {
  if (value === undefined || value === null || value === "") return null;
  const items = (Array.isArray(value) ? value : String(value).split(","))
    .map((item) => String(item).trim())
    .filter(Boolean);
  if (items.length === 0) fail("locale selection must not be empty");
  if (new Set(items).size !== items.length) fail("locale selection contains duplicates");
  return items;
}

function localizedAppInspection(appRoot, app, locales, defaultLocale) {
  const selectedIds = requestedLocales(locales);
  if (!selectedIds && !defaultLocale) {
    return { app, inspection: inspectTree(appRoot, { excludeDeveloperFiles: true }) };
  }
  if (!app.localization) fail("Agent App does not declare localization resources");
  const byId = new Map(app.localization.locales.map((entry) => [entry.id, entry]));
  const ids = selectedIds ?? app.localization.locales.map((entry) => entry.id);
  for (const id of ids) {
    if (!byId.has(id)) fail(`selected locale '${id}' is not declared by the Agent App`);
  }
  const packagedDefault = defaultLocale
    ?? (ids.includes(app.localization.defaultLocale) ? app.localization.defaultLocale : ids[0]);
  if (!ids.includes(packagedDefault)) {
    fail(`default locale '${packagedDefault}' must be included in the locale selection`);
  }
  const packagedApp = structuredClone(app);
  packagedApp.localization = {
    defaultLocale: packagedDefault,
    locales: ids.map((id) => byId.get(id)),
  };
  const selected = new Set(ids);
  const excluded = new Set(
    app.localization.locales
      .filter((entry) => !selected.has(entry.id))
      .map((entry) => entry.resource),
  );
  const manifestBytes = Buffer.from(`${JSON.stringify(packagedApp, null, 2)}\n`, "utf8");
  const overrides = new Map([["agent-app.json", manifestBytes]]);
  return {
    app: packagedApp,
    inspection: inspectTree(appRoot, { excluded, excludeDeveloperFiles: true, overrides }),
  };
}

export function packageAgentApp({
  input,
  output,
  runtimeVersion = DEFAULT_RUNTIME_VERSION,
  locales,
  defaultLocale,
}) {
  requireSemver(runtimeVersion, "runtime version");
  const appRoot = resolveConfinedPath(PROJECT_ROOT, input, "Agent App input");
  const { app: sourceApp, catalog } = validateAgentApp(appRoot);
  validateAgentWeaveProjectWorkspace(appRoot, {
    app: sourceApp,
    requireDeploymentLock: sourceApp.modelAccess?.configurationPolicy === "app_managed",
  });
  const localized = localizedAppInspection(appRoot, sourceApp, locales, defaultLocale);
  const app = localized.app;
  const appInspection = localized.inspection;
  const packages = selectedPackageSources(appRoot, app, catalog)
    .map((source) => {
      const inspection = inspectTree(source.root, { excludeDeveloperFiles: true });
      const manifest = readJson(join(source.root, "agentweave.json"), `${source.id} package manifest`);
      if (manifest.id !== source.id) fail(`${source.id} package source has mismatched identity`);
      return {
        ...source,
        inspection,
        version: manifest.version,
      };
    })
    .sort((left, right) => left.id.localeCompare(right.id));
  const outputRoot = prepareOutput(output);
  const lock = {
    schemaVersion: AGENT_APP_LOCK_SCHEMA_VERSION,
    app: {
      appId: app.appId,
      packageId: app.package.id,
      version: app.package.version,
      contentHash: appInspection.contentHash,
      path: "app",
    },
    runtime: {
      compatibility: app.compatibility.runtime,
      packagedWithVersion: runtimeVersion,
    },
    platforms: [...app.compatibility.platforms].sort(),
    packages: packages.map((entry) => ({
      id: entry.id,
      version: entry.version,
      contentHash: entry.inspection.contentHash,
      path: `packages/${entry.id}`,
      source: entry.source,
    })),
    hostRequirements: {
      capabilities: [...app.requires.capabilities].sort(),
      runtimeTools: [...app.requires.runtimeTools].sort(),
      connectors: [...app.requires.connectors].sort().map((id) => ({ id, runtimeVersion })),
      providers: [...app.requires.capabilities]
        .filter((id) => id.includes("provider"))
        .sort()
        .map((id) => ({ id, runtimeVersion })),
    },
    localization: app.localization ? {
      defaultLocale: app.localization.defaultLocale,
      locales: app.localization.locales.map((entry) => entry.id),
    } : null,
    publicProviderProjection: {
      manifestSchemaVersion: app.schemaVersion,
      value: runtimeProviderProjection(app),
      contentHash: hashPublicValue(runtimeProviderProjection(app)),
    },
  };
  mkdirSync(outputRoot, { recursive: true });
  copyInspectedTree(appRoot, appInspection, join(outputRoot, "app"));
  mkdirSync(join(outputRoot, "packages"), { recursive: true });
  for (const entry of packages) {
    copyInspectedTree(entry.root, entry.inspection, join(outputRoot, "packages", entry.id));
  }
  writeFileSync(join(outputRoot, LOCK_FILE), `${JSON.stringify(lock, null, 2)}\n`, "utf8");
  validateAgentAppRelease(outputRoot);
  return { lock, outputRoot };
}

function requireReleasePath(root, value, label) {
  if (typeof value !== "string" || value === "" || value.includes("\\")) {
    fail(`${label} is invalid`);
  }
  return resolveConfinedPath(root, value, label);
}

function validateArtifactInventory(root) {
  for (const path of listRegularFiles(root)) {
    const portable = normalized(path);
    if (isDeveloperOnlyReleasePath(portable)) {
      fail(`release artifact contains developer-only file '${portable}'`);
    }
    scanCredentialMarkers(readFileSync(join(root, path)), portable);
  }
}

function validatePublicProviderProjectionLock(value, app) {
  if (value === undefined) {
    if (app.schemaVersion === 1) return;
    fail("Agent App lock is missing the public provider projection");
  }
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    fail("locked public provider projection must be an object");
  }
  for (const key of Object.keys(value)) {
    if (!["manifestSchemaVersion", "value", "contentHash"].includes(key)) {
      fail(`locked public provider projection contains unknown field '${key}'`);
    }
  }
  if (value.manifestSchemaVersion !== app.schemaVersion) {
    fail("locked public provider projection schema does not match packaged manifest");
  }
  const expected = runtimeProviderProjection(app);
  if (
    value.contentHash !== hashPublicValue(value.value)
    || value.contentHash !== hashPublicValue(expected)
  ) {
    fail("locked public provider projection does not match packaged manifest");
  }
}

export function validateAgentAppRelease(input) {
  const releaseRoot = resolveConfinedPath(PROJECT_ROOT, input, "release artifact");
  if (!existsSync(releaseRoot) || !statSync(releaseRoot).isDirectory()) {
    fail("release artifact is not a directory");
  }
  const topLevel = readdirSync(releaseRoot).sort();
  if (JSON.stringify(topLevel) !== JSON.stringify([LOCK_FILE, "app", "packages"])) {
    fail("release artifact contains an unexpected top-level entry");
  }
  validateArtifactInventory(releaseRoot);
  const lock = readJson(join(releaseRoot, LOCK_FILE), "Agent App lock");
  if (lock.schemaVersion !== AGENT_APP_LOCK_SCHEMA_VERSION) {
    fail(`unsupported Agent App lock schema version '${lock.schemaVersion}'`);
  }
  requireSemver(lock.runtime?.packagedWithVersion, "locked runtime version");
  const appRoot = requireReleasePath(releaseRoot, lock.app?.path, "locked App path");
  const { app } = validateAgentApp(appRoot, { validateProject: false });
  if (app.appId !== lock.app.appId || app.package.id !== lock.app.packageId || app.package.version !== lock.app.version) {
    fail("locked App identity does not match packaged manifest");
  }
  const lockedLocalization = app.localization ? {
    defaultLocale: app.localization.defaultLocale,
    locales: app.localization.locales.map((entry) => entry.id),
  } : null;
  if (JSON.stringify(lockedLocalization) !== JSON.stringify(lock.localization ?? null)) {
    fail("locked App localization does not match packaged manifest");
  }
  validatePublicProviderProjectionLock(lock.publicProviderProjection, app);
  if (inspectTree(appRoot).contentHash !== lock.app.contentHash) fail("packaged App content hash mismatch");
  const expectedIds = app.requires.packages.map((entry) => entry.id).sort();
  const lockedIds = lock.packages.map((entry) => entry.id).sort();
  if (JSON.stringify(expectedIds) !== JSON.stringify(lockedIds)) fail("locked package inventory mismatch");
  for (const entry of lock.packages) {
    const packageRoot = requireReleasePath(releaseRoot, entry.path, `${entry.id} locked path`);
    const manifest = readJson(join(packageRoot, "agentweave.json"), `${entry.id} package manifest`);
    if (manifest.id !== entry.id || manifest.version !== entry.version) {
      fail(`${entry.id} locked package identity mismatch`);
    }
    if (inspectTree(packageRoot).contentHash !== entry.contentHash) {
      fail(`${entry.id} packaged content hash mismatch`);
    }
  }
  return lock;
}

function usage() {
  return [
    "Usage:",
    "  node scripts/package-agent-app.mjs --input <app-path> --output <release-path> [--runtime-version <version>] [--locales <id,id>] [--default-locale <id>]",
    "  node scripts/package-agent-app.mjs --verify <release-path>",
  ].join("\n");
}

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 1) {
    const option = argv[index];
    if (option === "--help" || option === "-h") return { help: true };
    if (!["--input", "--output", "--runtime-version", "--locales", "--default-locale", "--verify"].includes(option)) {
      fail(`unknown argument '${option}'`);
    }
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) fail(`${option} requires a value`);
    const field = option.slice(2)
      .replace("runtime-version", "runtimeVersion")
      .replace("default-locale", "defaultLocale");
    args[field] = value;
    index += 1;
  }
  return args;
}

export function runCli(argv = process.argv.slice(2)) {
  const args = parseArgs(argv);
  if (args.help) return console.log(usage());
  if (args.verify) {
    if (args.input || args.output || args.runtimeVersion || args.locales || args.defaultLocale) {
      fail("--verify cannot be combined with packaging options");
    }
    validateAgentAppRelease(args.verify);
    console.log(`Verified Agent App release at ${relative(PROJECT_ROOT, resolve(PROJECT_ROOT, args.verify))}`);
    return;
  }
  if (!args.input || !args.output) fail(`--input and --output are required\n${usage()}`);
  const result = packageAgentApp(args);
  console.log(`Packaged Agent App release at ${relative(PROJECT_ROOT, result.outputRoot)}`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    runCli();
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  }
}
