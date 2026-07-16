import assert from "node:assert/strict";
import { mkdirSync, rmSync, writeFileSync } from "node:fs";
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

function writeApp(root, path, appId = "com.example.test-app") {
  const appRoot = join(root, path);
  mkdirSync(join(appRoot, "packages"), { recursive: true });
  writeFileSync(join(appRoot, "agent-app.json"), JSON.stringify({
    appId,
    branding: { displayName: "Test App" },
  }));
  return appRoot;
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
    assert.equal(packaged.input, appRoot);
    assert.equal(packaged.output, join(root, "dist", "macos", "com-example-test-app"));
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
