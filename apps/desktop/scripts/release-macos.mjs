import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import {
  closeSync,
  existsSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  openSync,
  readSync,
  rmSync,
  statSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { basename, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

import {
  PROJECT_ROOT,
  resolveConfinedPath,
} from "../../../scripts/scaffold-agent-app.mjs";

function fail(message) {
  throw new Error(message);
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

function requireDirectory(path, label) {
  if (!existsSync(path) || !statSync(path).isDirectory()) fail(`${label} is missing`);
}

function requireFile(path, label) {
  if (!existsSync(path) || !statSync(path).isFile()) fail(`${label} is missing`);
}

function normalizeHttpsBaseUrl(value) {
  let url;
  try {
    url = new URL(value);
  } catch {
    fail("download base URL is invalid");
  }
  if (url.protocol !== "https:") fail("download base URL must use HTTPS");
  if (url.username || url.password || url.search || url.hash) {
    fail("download base URL must not contain credentials, a query, or a fragment");
  }
  return url.toString().replace(/\/$/, "");
}

export function releaseFileSlug(value) {
  const slug = value
    .normalize("NFKD")
    .replaceAll(/[^A-Za-z0-9._-]+/g, "-")
    .replaceAll(/-{2,}/g, "-")
    .replaceAll(/^[._-]+|[._-]+$/g, "")
    .toLowerCase();
  if (!slug || slug === "." || slug === "..") fail("release name is not file-safe");
  return slug;
}

export function normalizeMacArchitectures(value) {
  const result = [...new Set(value.trim().split(/\s+/).filter(Boolean).map((arch) => {
    if (arch === "x86_64" || arch === "x64") return "x64";
    if (arch === "arm64") return "arm64";
    fail(`unsupported macOS architecture '${arch}'`);
  }))].sort();
  if (result.length === 0) fail("macOS executable architecture is missing");
  return result.length === 1 ? result[0] : "universal";
}

export function releaseArtifactNames({ appName, version, architecture }) {
  const stem = `${releaseFileSlug(appName)}-${releaseFileSlug(version)}-macos-${architecture}`;
  return Object.freeze({
    appArchive: `${stem}.zip`,
    diskImage: `${stem}.dmg`,
    metadata: `${stem}.json`,
  });
}

function readPlistString(infoPlist, key, { optional = false } = {}) {
  const result = spawnSync("/usr/bin/plutil", ["-extract", key, "raw", "-o", "-", infoPlist], {
    cwd: PROJECT_ROOT,
    encoding: "utf8",
    stdio: "pipe",
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    if (optional) return null;
    fail(`Info.plist does not contain a valid ${key}`);
  }
  const value = result.stdout.trim();
  if (!value && !optional) fail(`Info.plist ${key} is empty`);
  return value || null;
}

function inspectApp(appPath) {
  requireDirectory(appPath, "signed macOS App");
  if (!appPath.endsWith(".app")) fail("signed macOS App must have an .app extension");
  const infoPlist = join(appPath, "Contents/Info.plist");
  requireFile(infoPlist, "signed App Info.plist");
  const executable = readPlistString(infoPlist, "CFBundleExecutable");
  const executablePath = join(appPath, "Contents/MacOS", executable);
  requireFile(executablePath, "signed App executable");
  const archs = run("/usr/bin/lipo", ["-archs", executablePath], { capture: true }).stdout;
  return Object.freeze({
    appName: basename(appPath, ".app"),
    architecture: normalizeMacArchitectures(archs),
    buildVersion: readPlistString(infoPlist, "CFBundleVersion"),
    bundleId: readPlistString(infoPlist, "CFBundleIdentifier"),
    minimumSystemVersion: readPlistString(infoPlist, "LSMinimumSystemVersion", { optional: true }),
    version: readPlistString(infoPlist, "CFBundleShortVersionString"),
  });
}

export function parseDeveloperIdSignature(output) {
  const identity = output.match(/^Authority=(Developer ID Application:.+)$/m)?.[1]?.trim();
  if (!identity) {
    fail("macOS release requires a Developer ID Application signature");
  }
  const teamId = output.match(/^TeamIdentifier=(.+)$/m)?.[1]?.trim();
  if (!teamId || teamId === "not set") fail("Developer ID signature does not contain a TeamIdentifier");
  if (!/^[A-Z0-9]{10}$/.test(teamId)) fail("Developer ID signature contains an invalid TeamIdentifier");
  return Object.freeze({ identity, teamId });
}

function verifyDeveloperIdApp(appPath) {
  run("/usr/bin/codesign", ["--deep", "--strict", "--verify", appPath]);
  const detail = run("/usr/bin/codesign", ["--display", "--verbose=4", appPath], { capture: true });
  return parseDeveloperIdSignature(`${detail.stdout}\n${detail.stderr}`);
}

function sha256File(path) {
  const hash = createHash("sha256");
  const buffer = Buffer.allocUnsafe(1024 * 1024);
  const descriptor = openSync(path, "r");
  try {
    let bytesRead;
    do {
      bytesRead = readSync(descriptor, buffer, 0, buffer.length, null);
      if (bytesRead > 0) hash.update(buffer.subarray(0, bytesRead));
    } while (bytesRead > 0);
  } finally {
    closeSync(descriptor);
  }
  return hash.digest("hex");
}

export function describeReleaseArtifact({ path, kind, downloadBaseUrl, notarized }) {
  requireFile(path, `release ${kind}`);
  const fileName = basename(path);
  return Object.freeze({
    downloadUrl: `${normalizeHttpsBaseUrl(downloadBaseUrl)}/${encodeURIComponent(fileName)}`,
    fileName,
    kind,
    notarized,
    sha256: sha256File(path),
    sizeBytes: statSync(path).size,
  });
}

export function createMacUpdateMetadata({
  app,
  artifacts,
  publishedAt,
  teamId,
}) {
  if (!app || typeof app !== "object") fail("release App metadata is required");
  if (!Array.isArray(artifacts) || artifacts.length === 0) fail("at least one release artifact is required");
  const timestamp = new Date(publishedAt);
  if (!Number.isFinite(timestamp.valueOf())) fail("publishedAt must be an ISO-8601 timestamp");
  if (typeof teamId !== "string" || !/^[A-Z0-9]{10}$/.test(teamId)) {
    fail("Developer Team ID must contain 10 uppercase letters or digits");
  }
  return Object.freeze({
    app: {
      buildVersion: app.buildVersion,
      bundleId: app.bundleId,
      name: app.appName,
      version: app.version,
    },
    architecture: app.architecture,
    artifacts,
    minimumSystemVersion: app.minimumSystemVersion,
    platform: "macos",
    publishedAt: timestamp.toISOString(),
    schemaVersion: 1,
    signature: {
      teamId,
      type: "developer_id_application",
    },
  });
}

export function macReleasePlan({ app, output, downloadBaseUrl }) {
  if (process.platform !== "darwin") fail("macOS release preparation requires a macOS host");
  const appPath = resolveConfinedPath(PROJECT_ROOT, app, "signed macOS App input");
  const outputRoot = resolveConfinedPath(PROJECT_ROOT, output, "macOS release output");
  const inspected = inspectApp(appPath);
  return Object.freeze({
    ...inspected,
    appPath,
    downloadBaseUrl: normalizeHttpsBaseUrl(downloadBaseUrl),
    names: releaseArtifactNames(inspected),
    outputRoot,
  });
}

function archiveApp(appPath, destination) {
  rmSync(destination, { force: true });
  run("/usr/bin/ditto", ["-c", "-k", "--keepParent", appPath, destination]);
  requireFile(destination, "archived macOS App");
}

function createDiskImage({ appPath, destination, volumeName }) {
  mkdirSync(join(PROJECT_ROOT, ".tool"), { recursive: true });
  const stagingRoot = mkdtempSync(join(PROJECT_ROOT, ".tool/macos-release-dmg-"));
  try {
    run("/usr/bin/ditto", [appPath, join(stagingRoot, basename(appPath))]);
    const applicationsLink = join(stagingRoot, "Applications");
    symlinkSync("/Applications", applicationsLink);
    if (!lstatSync(applicationsLink).isSymbolicLink()) fail("Applications alias was not created");
    rmSync(destination, { force: true });
    run("/usr/bin/hdiutil", [
      "create",
      "-format",
      "UDZO",
      "-fs",
      "HFS+",
      "-ov",
      "-srcfolder",
      stagingRoot,
      "-volname",
      volumeName,
      destination,
    ]);
    requireFile(destination, "macOS disk image");
  } finally {
    rmSync(stagingRoot, { force: true, recursive: true });
  }
}

function signDiskImage(path, { identity, keychain }) {
  const args = ["--force", "--sign", identity, "--timestamp"];
  if (keychain) args.push("--keychain", keychain);
  args.push(path);
  run("/usr/bin/codesign", args);
  run("/usr/bin/codesign", ["--strict", "--verify", path]);
}

function notarize(path, { keychain, profile }) {
  const args = ["notarytool", "submit", path, "--keychain-profile", profile];
  if (keychain) args.push("--keychain", keychain);
  args.push("--wait", "--timeout", "30m", "--output-format", "json");
  run("/usr/bin/xcrun", args);
}

function staple(path) {
  run("/usr/bin/xcrun", ["stapler", "staple", path]);
  run("/usr/bin/xcrun", ["stapler", "validate", path]);
}

export function releaseMacDesktop({
  app,
  output,
  downloadBaseUrl,
  keychain,
  notaryProfile,
  overwrite = false,
  publishedAt = new Date().toISOString(),
  skipNotarization = false,
}) {
  const plan = macReleasePlan({ app, output, downloadBaseUrl });
  if (!skipNotarization && !notaryProfile) fail("--notary-profile is required for a notarized release");
  if (existsSync(plan.outputRoot)) {
    if (!overwrite) fail("macOS release output already exists; pass --overwrite to replace it");
    rmSync(plan.outputRoot, { force: true, recursive: true });
  }
  mkdirSync(plan.outputRoot, { recursive: true });
  let completed = false;
  try {
    const signature = verifyDeveloperIdApp(plan.appPath);
    const appArchive = join(plan.outputRoot, plan.names.appArchive);
    const diskImage = join(plan.outputRoot, plan.names.diskImage);
    if (!skipNotarization) {
      mkdirSync(join(PROJECT_ROOT, ".tool"), { recursive: true });
      const submissionRoot = mkdtempSync(join(PROJECT_ROOT, ".tool/macos-notary-"));
      try {
        const submissionArchive = join(submissionRoot, "app.zip");
        archiveApp(plan.appPath, submissionArchive);
        notarize(submissionArchive, { keychain, profile: notaryProfile });
        staple(plan.appPath);
        run("/usr/sbin/spctl", ["--assess", "--type", "execute", "--verbose=2", plan.appPath]);
      } finally {
        rmSync(submissionRoot, { force: true, recursive: true });
      }
    }
    archiveApp(plan.appPath, appArchive);
    createDiskImage({ appPath: plan.appPath, destination: diskImage, volumeName: plan.appName });
    signDiskImage(diskImage, { identity: signature.identity, keychain });
    if (!skipNotarization) {
      notarize(diskImage, { keychain, profile: notaryProfile });
      staple(diskImage);
      run("/usr/sbin/spctl", ["--assess", "--type", "open", "--context", "context:primary-signature", "--verbose=2", diskImage]);
    }
    const notarized = !skipNotarization;
    const artifacts = [
      describeReleaseArtifact({
        downloadBaseUrl: plan.downloadBaseUrl,
        kind: "application_archive",
        notarized,
        path: appArchive,
      }),
      describeReleaseArtifact({
        downloadBaseUrl: plan.downloadBaseUrl,
        kind: "disk_image",
        notarized,
        path: diskImage,
      }),
    ];
    const metadata = createMacUpdateMetadata({
      app: plan,
      artifacts,
      publishedAt,
      teamId: signature.teamId,
    });
    const metadataPath = join(plan.outputRoot, plan.names.metadata);
    writeFileSync(metadataPath, `${JSON.stringify(metadata, null, 2)}\n`, "utf8");
    completed = true;
    return Object.freeze({ appArchive, diskImage, metadataPath, plan });
  } finally {
    if (!completed) rmSync(plan.outputRoot, { force: true, recursive: true });
  }
}

function usage() {
  return [
    "Usage:",
    "  node apps/desktop/scripts/release-macos.mjs --app <path.app> --output <directory> --download-base-url <https-url> --notary-profile <profile> [--keychain <path>] [--overwrite]",
    "  node apps/desktop/scripts/release-macos.mjs --app <path.app> --output <directory> --download-base-url <https-url> --skip-notarization [--overwrite]",
    "  node apps/desktop/scripts/release-macos.mjs --app <path.app> --output <directory> --download-base-url <https-url> --print-plan",
  ].join("\n");
}

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 1) {
    const option = argv[index];
    if (option === "--help" || option === "-h") return { help: true };
    if (["--overwrite", "--print-plan", "--skip-notarization"].includes(option)) {
      args[option.slice(2).replaceAll(/-([a-z])/g, (_, letter) => letter.toUpperCase())] = true;
      continue;
    }
    if (!["--app", "--output", "--download-base-url", "--keychain", "--notary-profile", "--published-at"].includes(option)) {
      fail(`unknown argument '${option}'`);
    }
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) fail(`${option} requires a value`);
    const field = option.slice(2).replaceAll(/-([a-z])/g, (_, letter) => letter.toUpperCase());
    args[field] = value;
    index += 1;
  }
  return args;
}

export function runCli(argv = process.argv.slice(2)) {
  const args = parseArgs(argv);
  if (args.help) return console.log(usage());
  if (!args.app || !args.output || !args.downloadBaseUrl) {
    fail(`--app, --output, and --download-base-url are required\n${usage()}`);
  }
  if (args.printPlan) {
    console.log(JSON.stringify(macReleasePlan(args), null, 2));
    return;
  }
  const result = releaseMacDesktop(args);
  console.log(`Prepared macOS release artifacts at ${relative(PROJECT_ROOT, result.plan.outputRoot)}`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    runCli();
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  }
}
