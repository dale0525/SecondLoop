import assert from "node:assert/strict";
import { cpSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import test from "node:test";

import { createAppDevPlan, unexpectedProcessExit } from "./app-dev.mjs";
import { createAppPackagePlan } from "./app-package.mjs";
import { resolveAppProject } from "./app-project.mjs";

function fixture(name) {
  const root = join(process.cwd(), ".tool", `app-project-${name}-${process.pid}`);
  rmSync(root, { recursive: true, force: true });
  mkdirSync(root, { recursive: true });
  return root;
}

function writeApp(root, path, appId = "com.example.testapp") {
  const appRoot = join(root, path);
  cpSync(join(process.cwd(), "templates", "agent-app"), appRoot, { recursive: true });
  const manifestPath = join(appRoot, "agent-app.json");
  const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
  manifest.appId = appId;
  manifest.package.id = appId;
  manifest.branding.displayName = "Test App";
  writeFileSync(manifestPath, JSON.stringify(manifest));
  return appRoot;
}

function writeIncompleteFirebase(appRoot, publicConfig) {
  const manifestPath = join(appRoot, "agent-app.json");
  const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
  manifest.identity = {
    mode: "required",
    provider: { id: "agentweave.identity.firebase", version: "0.1.0", publicConfig },
  };
  writeFileSync(manifestPath, JSON.stringify(manifest));
  const projectPath = join(appRoot, "agentweave-project.json");
  const project = JSON.parse(readFileSync(projectPath, "utf8"));
  project.providers.identity = manifest.identity.provider;
  writeFileSync(projectPath, JSON.stringify(project));
}

test("project resolver prefers the standard app directory", () => {
  const root = fixture("standard");
  try {
    const appRoot = writeApp(root, "app");
    assert.equal(resolveAppProject({ projectRoot: root }).appRoot, appRoot);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("project resolver accepts one generic product during migration", () => {
  const root = fixture("product");
  try {
    const appRoot = writeApp(root, "products/example");
    assert.equal(resolveAppProject({ projectRoot: root }).appRoot, appRoot);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("project resolver fails closed for ambiguous products", () => {
  const root = fixture("ambiguous");
  try {
    writeApp(root, "products/one", "com.example.one");
    writeApp(root, "products/two", "com.example.two");
    assert.throws(() => resolveAppProject({ projectRoot: root }), /Multiple Agent Apps/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("app dev and package plans use the same selected App", () => {
  const root = fixture("plans");
  try {
    const appRoot = writeApp(root, "app");
    const dev = createAppDevPlan({ projectRoot: root });
    const packaged = createAppPackagePlan({ projectRoot: root });
    assert.equal(dev.app.appRoot, appRoot);
    assert.equal(dev.environment.AGENTWEAVE_DEV_SKILLS_ROOT, join(appRoot, "packages"));
    assert.equal(dev.environment.AGENTWEAVE_DEV_RECOVERY_REVISION, undefined);
    assert.equal(dev.recovery, null);
    assert.equal(packaged.input, appRoot);
    assert.equal(packaged.output, join(root, "dist", "macos", "com-example-testapp"));
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("app dev recovery revision changes when the editable project changes", () => {
  const root = fixture("recovery-revision");
  try {
    const appRoot = writeApp(root, "app");
    writeIncompleteFirebase(appRoot, {});
    const first = createAppDevPlan({ projectRoot: root });
    assert.match(first.recovery.reason, /projectId is required/);
    writeIncompleteFirebase(appRoot, { projectId: "example-project" });
    const second = createAppDevPlan({ projectRoot: root });
    assert.notEqual(
      first.environment.AGENTWEAVE_DEV_RECOVERY_REVISION,
      second.environment.AGENTWEAVE_DEV_RECOVERY_REVISION,
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("app dev rejects structurally invalid projects instead of broadening recovery", () => {
  const root = fixture("invalid-recovery-project");
  try {
    const appRoot = writeApp(root, "app");
    writeFileSync(join(appRoot, "agentweave-project.json"), "{}\n");
    assert.throws(() => createAppDevPlan({ projectRoot: root }), /schemaVersion is required/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("app dev treats requested and clean process exits as successful", () => {
  assert.equal(unexpectedProcessExit("Electron", 0, null), null);
  assert.equal(unexpectedProcessExit("Electron", null, "SIGTERM", true), null);
  assert.match(
    unexpectedProcessExit("Electron", null, "SIGKILL")?.message ?? "",
    /signal SIGKILL/,
  );
});
