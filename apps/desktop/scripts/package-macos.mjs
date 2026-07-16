import { spawnSync } from "node:child_process";
import {
  chmodSync,
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { basename, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { packager } from "@electron/packager";

import {
  packageAgentApp,
  validateAgentAppRelease,
} from "../../../scripts/package-agent-app.mjs";
import {
  PROJECT_ROOT,
  resolveConfinedPath,
  validateAgentApp,
} from "../../../scripts/scaffold-agent-app.mjs";

const DESKTOP_ROOT = resolve(PROJECT_ROOT, "apps/desktop");
const LICENSE_FILES = ["LICENSE", "LICENSE-APACHE", "LICENSE-MIT", "NOTICE"];
const RUNTIME_VERSION = "0.1.0";

function fail(message) {
  throw new Error(message);
}

function readJson(path, label) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    fail(`${label} is invalid JSON: ${error instanceof Error ? error.message : String(error)}`);
  }
}

function requireDirectory(path, label) {
  if (!existsSync(path) || !statSync(path).isDirectory()) fail(`${label} is missing`);
}

function requireFile(path, label) {
  if (!existsSync(path) || !statSync(path).isFile()) fail(`${label} is missing`);
}

function copyTree(source, destination) {
  requireDirectory(source, `source directory '${source}'`);
  cpSync(source, destination, {
    dereference: false,
    errorOnExist: true,
    force: false,
    recursive: true,
    verbatimSymlinks: true,
  });
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: PROJECT_ROOT,
    encoding: "utf8",
    env: process.env,
    stdio: options.capture ? "pipe" : "inherit",
    ...options,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    const detail = options.capture ? `: ${(result.stderr || result.stdout).trim()}` : "";
    fail(`${command} failed with exit code ${result.status}${detail}`);
  }
  return result;
}

function normalizeArch(value = process.arch) {
  if (value === "arm64") return "arm64";
  if (value === "x64" || value === "x86_64") return "x64";
  fail(`unsupported macOS architecture '${value}'`);
}

function executableName(displayName) {
  const value = displayName.replaceAll(/[/:]/g, "-").trim();
  if (!value || value === "." || value === "..") fail("App display name is not packageable");
  return value;
}

function electronVersion() {
  const manifest = readJson(join(DESKTOP_ROOT, "node_modules/electron/package.json"), "Electron package");
  if (typeof manifest.version !== "string" || !/^\d+\.\d+\.\d+/.test(manifest.version)) {
    fail("Electron package version is invalid");
  }
  return manifest.version;
}

export function desktopPackagePlan({ input, output, arch = process.arch }) {
  const appRoot = resolveConfinedPath(PROJECT_ROOT, input, "Desktop Agent App input");
  const outputRoot = resolveConfinedPath(PROJECT_ROOT, output, "Desktop package output");
  const { app } = validateAgentApp(appRoot);
  if (!app.compatibility.platforms.includes("desktop")) {
    fail("Agent App does not declare Desktop compatibility");
  }
  const name = executableName(app.branding.displayName);
  return Object.freeze({
    appBundleId: app.package.id,
    appRoot,
    appVersion: app.package.version,
    arch: normalizeArch(arch),
    name,
    outputRoot,
  });
}

export function prepareDesktopStaging({
  plan,
  releaseRoot,
  sidecarPath,
  rendererRoot = join(DESKTOP_ROOT, "dist"),
  electronRoot = join(DESKTOP_ROOT, "dist-electron"),
  stagingRoot,
}) {
  requireDirectory(rendererRoot, "Desktop Renderer build");
  requireDirectory(electronRoot, "Desktop Electron build");
  requireFile(sidecarPath, "agent-server sidecar");
  const lock = validateAgentAppRelease(releaseRoot);
  const payloadRoot = join(stagingRoot, "app");
  const resourcesRoot = join(stagingRoot, "resources");
  mkdirSync(payloadRoot, { recursive: true });
  mkdirSync(resourcesRoot, { recursive: true });
  copyTree(rendererRoot, join(payloadRoot, "dist"));
  copyTree(electronRoot, join(payloadRoot, "dist-electron"));
  writeFileSync(join(payloadRoot, "package.json"), `${JSON.stringify({
    name: plan.appBundleId.toLowerCase().replaceAll(".", "-"),
    productName: plan.name,
    version: plan.appVersion,
    private: true,
    main: "dist-electron/main.cjs",
  }, null, 2)}\n`, "utf8");

  const sidecarRoot = join(resourcesRoot, "sidecar");
  mkdirSync(sidecarRoot, { recursive: true });
  cpSync(sidecarPath, join(sidecarRoot, "agent-server"), { errorOnExist: true, force: false });
  chmodSync(join(sidecarRoot, "agent-server"), 0o755);
  copyTree(releaseRoot, join(resourcesRoot, "agent-app"));

  const skillsRoot = join(resourcesRoot, "skills");
  mkdirSync(skillsRoot, { recursive: true });
  for (const entry of lock.packages.filter((item) => item.source === "first_party")) {
    copyTree(join(releaseRoot, entry.path), join(skillsRoot, entry.id));
  }

  const licensesRoot = join(resourcesRoot, "licenses");
  mkdirSync(licensesRoot, { recursive: true });
  for (const file of LICENSE_FILES) {
    cpSync(join(PROJECT_ROOT, file), join(licensesRoot, file), { errorOnExist: true, force: false });
  }
  verifyDesktopStaging({ payloadRoot, resourcesRoot });
  return { payloadRoot, resourcesRoot };
}

export function verifyDesktopStaging({ payloadRoot, resourcesRoot }) {
  requireFile(join(payloadRoot, "package.json"), "packaged Desktop manifest");
  requireFile(join(payloadRoot, "dist/index.html"), "packaged Desktop Renderer");
  for (const file of ["main.cjs", "preload.cjs", "approval-preload.cjs"]) {
    requireFile(join(payloadRoot, "dist-electron", file), `packaged ${file}`);
  }
  const sidecar = join(resourcesRoot, "sidecar/agent-server");
  requireFile(sidecar, "packaged sidecar");
  if ((statSync(sidecar).mode & 0o111) === 0) fail("packaged sidecar is not executable");
  validateAgentAppRelease(join(resourcesRoot, "agent-app"));
  for (const file of LICENSE_FILES) requireFile(join(resourcesRoot, "licenses", file), file);
  return true;
}

export function verifyPackagedMacApp(appPath) {
  requireDirectory(appPath, "packaged macOS App");
  requireFile(join(appPath, "Contents/MacOS", basename(appPath, ".app")), "App executable");
  verifyFinalResources(appPath);
  return true;
}

function verifyFinalResources(appPath) {
  const resources = join(appPath, "Contents/Resources");
  requireFile(join(resources, "app.asar"), "Desktop app.asar");
  const sidecar = join(resources, "sidecar/agent-server");
  requireFile(sidecar, "packaged sidecar");
  if ((statSync(sidecar).mode & 0o111) === 0) fail("packaged sidecar is not executable");
  validateAgentAppRelease(join(resources, "agent-app"));
  for (const file of LICENSE_FILES) requireFile(join(resources, "licenses", file), file);
}

function assertSidecarArchitecture(sidecarPath, arch) {
  if (process.platform !== "darwin") return;
  const result = run("/usr/bin/lipo", ["-archs", sidecarPath], { capture: true });
  const expected = arch === "x64" ? "x86_64" : "arm64";
  if (!result.stdout.trim().split(/\s+/).includes(expected)) {
    fail(`agent-server does not contain the requested ${arch} architecture`);
  }
}

function buildInputs(plan) {
  run("cargo", ["build", "--release", "-p", "agent-server", "--bin", "agent-server"]);
  run("npm", ["--prefix", "apps/desktop", "run", "build"], {
    env: { ...process.env, AGENTWEAVE_APP_ROOT: plan.appRoot },
  });
}

export async function packageMacDesktop({
  input,
  output,
  arch = process.arch,
  sidecar = join(PROJECT_ROOT, "target/release/agent-server"),
  skipBuild = false,
  overwrite = false,
  signIdentity,
}) {
  if (process.platform !== "darwin") fail("macOS Desktop packaging requires a macOS host");
  const plan = desktopPackagePlan({ input, output, arch });
  const sidecarPath = resolveConfinedPath(PROJECT_ROOT, sidecar, "Desktop sidecar input");
  if (existsSync(plan.outputRoot)) {
    if (!overwrite) fail("Desktop package output already exists; pass --overwrite to replace it");
    rmSync(plan.outputRoot, { force: true, recursive: true });
  }
  if (!skipBuild) buildInputs(plan);
  assertSidecarArchitecture(sidecarPath, plan.arch);
  mkdirSync(join(PROJECT_ROOT, ".tool"), { recursive: true });
  const stagingRoot = mkdtempSync(join(PROJECT_ROOT, ".tool/macos-desktop-"));
  try {
    const releaseRoot = join(stagingRoot, "release");
    packageAgentApp({ input: plan.appRoot, output: releaseRoot, runtimeVersion: RUNTIME_VERSION });
    const staging = prepareDesktopStaging({
      plan,
      releaseRoot,
      sidecarPath,
      stagingRoot: join(stagingRoot, "package"),
    });
    mkdirSync(plan.outputRoot, { recursive: true });
    const paths = await packager({
      appBundleId: plan.appBundleId,
      appCategoryType: "public.app-category.productivity",
      appVersion: plan.appVersion,
      arch: plan.arch,
      asar: true,
      dir: staging.payloadRoot,
      electronVersion: electronVersion(),
      executableName: plan.name,
      extraResource: readdirSync(staging.resourcesRoot).map((entry) => join(staging.resourcesRoot, entry)),
      name: plan.name,
      osxSign: signIdentity ? { hardenedRuntime: true, identity: signIdentity } : undefined,
      out: plan.outputRoot,
      overwrite: false,
      platform: "darwin",
      prune: false,
      quiet: false,
    });
    if (paths.length !== 1) fail("Desktop packager returned an unexpected artifact set");
    const appEntries = readdirSync(paths[0], { withFileTypes: true })
      .filter((entry) => entry.isDirectory() && entry.name.endsWith(".app"));
    if (appEntries.length !== 1) fail("Desktop package does not contain exactly one App bundle");
    const appPath = join(paths[0], appEntries[0].name);
    if (!signIdentity) {
      run("/usr/bin/codesign", ["--deep", "--force", "--sign", "-", appPath]);
    }
    run("/usr/bin/codesign", ["--deep", "--strict", "--verify", appPath]);
    verifyPackagedMacApp(appPath);
    return { appPath, plan };
  } finally {
    rmSync(stagingRoot, { force: true, recursive: true });
  }
}

function usage() {
  return [
    "Usage:",
    "  node apps/desktop/scripts/package-macos.mjs --input <app-path> --output <directory> [--arch arm64|x64] [--sidecar <path>] [--sign-identity <identity>] [--skip-build] [--overwrite]",
    "  node apps/desktop/scripts/package-macos.mjs --input <app-path> --output <directory> --print-plan",
  ].join("\n");
}

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 1) {
    const option = argv[index];
    if (option === "--help" || option === "-h") return { help: true };
    if (["--skip-build", "--overwrite", "--print-plan"].includes(option)) {
      args[option.slice(2).replaceAll(/-([a-z])/g, (_, letter) => letter.toUpperCase())] = true;
      continue;
    }
    if (!["--input", "--output", "--arch", "--sidecar", "--sign-identity"].includes(option)) {
      fail(`unknown argument '${option}'`);
    }
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) fail(`${option} requires a value`);
    const field = option.slice(2).replace("sign-identity", "signIdentity");
    args[field] = value;
    index += 1;
  }
  return args;
}

export async function runCli(argv = process.argv.slice(2)) {
  const args = parseArgs(argv);
  if (args.help) return console.log(usage());
  if (!args.input || !args.output) fail(`--input and --output are required\n${usage()}`);
  if (args.printPlan) {
    console.log(JSON.stringify(desktopPackagePlan(args), null, 2));
    return;
  }
  const result = await packageMacDesktop(args);
  console.log(`Packaged macOS Desktop App at ${relative(PROJECT_ROOT, result.appPath)}`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  runCli().catch((error) => {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  });
}
