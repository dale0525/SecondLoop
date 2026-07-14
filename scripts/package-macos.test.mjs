import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  chmodSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { join, relative } from "node:path";
import test from "node:test";

import {
  desktopPackagePlan,
  prepareDesktopStaging,
  verifyDesktopStaging,
} from "../apps/desktop/scripts/package-macos.mjs";
import { packageAgentApp, validateAgentAppRelease } from "./package-agent-app.mjs";
import { PROJECT_ROOT } from "./scaffold-agent-app.mjs";

const TEST_ROOT = join(PROJECT_ROOT, ".tool");
const SCRIPT = join(PROJECT_ROOT, "apps/desktop/scripts/package-macos.mjs");

function makeTempRoot() {
  mkdirSync(TEST_ROOT, { recursive: true });
  return mkdtempSync(join(TEST_ROOT, "macos-package-"));
}

function write(path, content = "fixture") {
  mkdirSync(join(path, ".."), { recursive: true });
  writeFileSync(path, content, "utf8");
}

test("macOS packaging plans preserve trusted App identity and architecture", () => {
  const plan = desktopPackagePlan({
    arch: "x86_64",
    input: "examples/minimal-agent",
    output: "dist/macos/minimal",
  });

  assert.equal(plan.appBundleId, "com.example.minimal-agent.app");
  assert.equal(plan.appVersion, "0.1.0");
  assert.equal(plan.arch, "x64");
  assert.equal(plan.name, "Minimal Agent");
  assert.equal(plan.outputRoot, join(PROJECT_ROOT, "dist/macos/minimal"));
});

test("staging carries the sidecar, locked App, first-party skills, and licenses", () => {
  const temp = makeTempRoot();
  try {
    const renderer = join(temp, "renderer");
    const electron = join(temp, "electron");
    const sidecar = join(temp, "agent-server");
    const release = join(temp, "release");
    write(join(renderer, "index.html"));
    for (const file of ["main.cjs", "preload.cjs", "approval-preload.cjs"]) {
      write(join(electron, file));
    }
    write(sidecar, "sidecar");
    chmodSync(sidecar, 0o755);
    packageAgentApp({
      input: "examples/secretary-agent",
      output: relative(PROJECT_ROOT, release),
    });
    const plan = desktopPackagePlan({
      input: "examples/secretary-agent",
      output: "dist/macos/secretary",
    });

    const staging = prepareDesktopStaging({
      electronRoot: electron,
      plan,
      releaseRoot: release,
      rendererRoot: renderer,
      sidecarPath: sidecar,
      stagingRoot: join(temp, "staging"),
    });

    assert.equal(verifyDesktopStaging(staging), true);
    assert.equal(statSync(join(staging.resourcesRoot, "sidecar/agent-server")).mode & 0o111, 0o111);
    assert.equal(validateAgentAppRelease(join(staging.resourcesRoot, "agent-app")).app.appId, "com.example.secretary-agent");
    assert.equal(existsSync(join(staging.resourcesRoot, "skills/agentweave.foundation.mail")), true);
    assert.equal(existsSync(join(staging.resourcesRoot, "skills/agentweave.foundation.memory")), true);
    assert.equal(existsSync(join(staging.resourcesRoot, "skills/com.example.secretary.routines")), false);
    const payload = readJson(join(staging.payloadRoot, "package.json"));
    assert.equal(payload.name, "com-example-secretary-agent-app");
    assert.equal(payload.productName, plan.name);
    assert.equal(payload.main, "dist-electron/main.cjs");
    for (const file of ["LICENSE", "LICENSE-APACHE", "LICENSE-MIT", "NOTICE"]) {
      assert.equal(existsSync(join(staging.resourcesRoot, "licenses", file)), true);
    }
  } finally {
    rmSync(temp, { force: true, recursive: true });
  }
});

function readJson(path) {
  return JSON.parse(readFileSync(path, "utf8"));
}

test("macOS package CLI exposes a build-free reviewable plan", () => {
  const result = spawnSync(process.execPath, [
    SCRIPT,
    "--input",
    "examples/minimal-agent",
    "--output",
    "dist/macos/minimal",
    "--arch",
    "arm64",
    "--print-plan",
  ], { cwd: PROJECT_ROOT, encoding: "utf8" });

  assert.equal(result.status, 0, result.stderr);
  const plan = JSON.parse(result.stdout);
  assert.equal(plan.appBundleId, "com.example.minimal-agent.app");
  assert.equal(plan.arch, "arm64");
  assert.equal(plan.name, "Minimal Agent");
});
