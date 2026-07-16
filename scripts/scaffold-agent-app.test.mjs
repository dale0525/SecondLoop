import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { join, relative } from "node:path";
import test from "node:test";

import {
  FOUNDATION_CATALOG_PATH,
  PROJECT_ROOT,
  resolveConfinedPath,
  scaffoldAgentApp,
  validateAgentApp,
  validateAgentAppTemplate,
  validateCatalogData,
  validateCatalogFile,
} from "./scaffold-agent-app.mjs";

const SCRIPT_PATH = join(PROJECT_ROOT, "scripts", "scaffold-agent-app.mjs");
const TEST_ROOT = join(PROJECT_ROOT, ".tool");

function makeTempRoot() {
  mkdirSync(TEST_ROOT, { recursive: true });
  return mkdtempSync(join(TEST_ROOT, "agent-app-scaffold-"));
}

function readJson(path) {
  return JSON.parse(readFileSync(path, "utf8"));
}

function writeJson(path, value) {
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function fileMap(root, prefix = "") {
  const result = {};
  const directory = prefix ? join(root, prefix) : root;
  for (const entry of readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    const path = prefix ? join(prefix, entry.name) : entry.name;
    if (entry.isDirectory()) Object.assign(result, fileMap(root, path));
    else result[path] = readFileSync(join(root, path), "utf8");
  }
  return result;
}

test("foundation catalog validates local packages and declares staged candidates", () => {
  const catalog = validateCatalogFile();
  const byId = new Map(catalog.skills.map((skill) => [skill.id, skill]));

  assert.equal(byId.get("agentweave.core.filesystem").consumerDefault, true);
  assert.deepEqual(byId.get("agentweave.core.skill-creator").audience, ["developer"]);
  assert.equal(byId.get("agentweave.core.skill-creator").consumerDefault, false);
  assert.equal(byId.get("agentweave.foundation.memory").wave, "available");
  assert.equal(byId.get("agentweave.foundation.mail").wave, "available");
  assert.deepEqual(byId.get("agentweave.foundation.calendar").dependencies.connectors, [
    "agentweave-calendar",
  ]);
  assert.deepEqual(byId.get("agentweave.foundation.contacts").dependencies.connectors, [
    "agentweave-contacts",
  ]);
  for (const id of [
    "agentweave.foundation.calendar",
    "agentweave.foundation.tasks",
    "agentweave.foundation.web-research",
    "agentweave.foundation.documents",
    "agentweave.foundation.contacts",
    "agentweave.foundation.scheduler",
    "agentweave.foundation.notifications",
    "agentweave.foundation.notes",
    "agentweave.foundation.messaging",
  ]) {
    assert.equal(byId.get(id).wave, "available");
    assert.equal(byId.get(id).stability, "preview");
    assert.ok(byId.get(id).localPackage.path.startsWith("skills/foundation-"));
  }
  for (const skill of catalog.skills) {
    assert.ok(skill.platforms.length > 0);
    assert.ok(skill.permissions.required);
    assert.ok(skill.permissions.conditional);
    assert.ok(skill.dataSensitivity.level);
    assert.ok(skill.replacementContract.id);
  }
});

test("checked-in template and minimal example validate", () => {
  const template = validateAgentAppTemplate();
  assert.deepEqual(template.files, [
    "README.md",
    "agent-app.json",
    "fonts/README.md",
    "locales/README.md",
    "locales/en.json",
    "locales/zh-CN.json",
    "packages/README.md",
    "prompts/developer.md",
    "prompts/system.md",
    "themes/README.md",
  ]);
  const { app } = validateAgentApp(join(PROJECT_ROOT, "examples", "minimal-agent"));
  assert.deepEqual(app.requires.packages.map((skill) => skill.id), ["agentweave.core.filesystem"]);
});

test("scaffold output is deterministic and excludes developer-only defaults", () => {
  const temp = makeTempRoot();
  try {
    const first = join(temp, "first");
    const second = join(temp, "second");
    scaffoldAgentApp({ name: "Research Agent", appId: "com.example.research-agent", output: first });
    scaffoldAgentApp({ name: "Research Agent", appId: "com.example.research-agent", output: second });
    assert.deepEqual(fileMap(first), fileMap(second));

    const manifest = readJson(join(first, "agent-app.json"));
    assert.equal(manifest.appId, "com.example.research-agent");
    assert.equal(manifest.package.id, "com.example.research-agent.app");
    assert.equal(manifest.branding.displayName, "Research Agent");
    assert.equal(manifest.policy.externalSideEffects, "require_approval");
    assert.equal(manifest.policy.network, "deny");
    assert.equal(manifest.policy.backgroundExecution, "disabled");
    assert.equal(manifest.policy.memoryPersistence, "disabled");
    assert.equal(manifest.policy.skillManagement, "disabled");
    assert.equal(manifest.appearance.defaultTheme, "vscode.dark-2026");
    assert.equal(manifest.localization.defaultLocale, "en");
    assert.deepEqual(manifest.localization.locales.map((locale) => locale.id), ["en", "zh-CN"]);
    assert.equal(manifest.appearance.themes.builtins.length, 19);
    assert.deepEqual(manifest.appearance.themes.custom, []);
    assert.deepEqual(manifest.requires.packages.map((skill) => skill.id), [
      "agentweave.core.filesystem",
    ]);
    assert.doesNotMatch(JSON.stringify(manifest), /skill-creator|api.?key|password/i);
  } finally {
    rmSync(temp, { recursive: true, force: true });
  }
});

test("Agent App localization validation checks locale parity and placeholders", () => {
  const temp = makeTempRoot();
  try {
    const output = join(temp, "localized-app");
    scaffoldAgentApp({ name: "Localized Agent", appId: "com.example.localized-agent", output });
    const chinesePath = join(output, "locales", "zh-CN.json");
    const chinese = readJson(chinesePath);
    delete chinese["app.tagline"];
    writeJson(chinesePath, chinese);
    assert.throws(() => validateAgentApp(output), /same message keys/);

    chinese["app.tagline"] = "你好，{name}";
    writeJson(chinesePath, chinese);
    assert.throws(() => validateAgentApp(output), /preserve placeholders/);
  } finally {
    rmSync(temp, { recursive: true, force: true });
  }
});

test("Agent App validation accepts selected VS Code JSONC themes and packaged font slots", () => {
  const temp = makeTempRoot();
  try {
    const output = join(temp, "appearance-app");
    scaffoldAgentApp({ name: "Appearance Agent", appId: "com.example.appearance-agent", output });
    writeFileSync(
      join(output, "themes", "base.json"),
      '{ "colors": { "editor.background": "#101010" } }\n',
      "utf8",
    );
    writeFileSync(
      join(output, "themes", "brand.jsonc"),
      '{\n  // VS Code JSONC is supported.\n  "include": "./base.json",\n  "name": "Brand Dark",\n  "colors": { "button.background": "#1677aa", },\n}\n',
      "utf8",
    );
    writeFileSync(join(output, "fonts", "ui-600.woff2"), Buffer.from("font-fixture"));
    const manifestPath = join(output, "agent-app.json");
    const manifest = readJson(manifestPath);
    manifest.appearance.defaultTheme = "com.example.brand-dark";
    manifest.appearance.themes.builtins = ["vscode.light-2026"];
    manifest.appearance.themes.custom = [{
      id: "com.example.brand-dark",
      label: "Brand Dark",
      path: "themes/brand.jsonc",
    }];
    writeJson(manifestPath, manifest);

    const { app } = validateAgentApp(output);

    assert.equal(app.appearance.defaultTheme, "com.example.brand-dark");
  } finally {
    rmSync(temp, { recursive: true, force: true });
  }
});

test("Agent App appearance validation rejects unavailable themes and invalid font names", () => {
  const temp = makeTempRoot();
  try {
    const output = join(temp, "invalid-appearance-app");
    scaffoldAgentApp({ name: "Invalid Appearance", appId: "com.example.invalid-appearance", output });
    const manifestPath = join(output, "agent-app.json");
    const manifest = readJson(manifestPath);
    manifest.appearance.defaultTheme = "vscode.missing";
    writeJson(manifestPath, manifest);
    assert.throws(() => validateAgentApp(output), /packaged theme/);

    manifest.appearance.defaultTheme = "vscode.dark-2026";
    writeJson(manifestPath, manifest);
    writeFileSync(join(output, "fonts", "brand-font.ttf"), Buffer.from("font-fixture"));
    assert.throws(() => validateAgentApp(output), /font slot convention/);
  } finally {
    rmSync(temp, { recursive: true, force: true });
  }
});

test("validation rejects path escape and future schemas", () => {
  assert.throws(
    () => resolveConfinedPath(PROJECT_ROOT, "../outside", "test output"),
    /escapes/,
  );

  const futureCatalog = structuredClone(readJson(FOUNDATION_CATALOG_PATH));
  futureCatalog.schemaVersion = 2;
  assert.throws(() => validateCatalogData(futureCatalog), /newer than supported/);

  const temp = makeTempRoot();
  try {
    const realDirectory = join(temp, "real-directory");
    const linkedDirectory = join(temp, "linked-directory");
    mkdirSync(realDirectory);
    symlinkSync(realDirectory, linkedDirectory);
    assert.throws(
      () => resolveConfinedPath(PROJECT_ROOT, join(linkedDirectory, "child"), "test output"),
      /crosses symbolic link/,
    );

    const output = join(temp, "future-app");
    scaffoldAgentApp({ name: "Future Agent", appId: "com.example.future-agent", output });
    const manifestPath = join(output, "agent-app.json");
    const manifest = readJson(manifestPath);
    manifest.schemaVersion = 2;
    writeJson(manifestPath, manifest);
    assert.throws(() => validateAgentApp(output), /newer than supported/);
  } finally {
    rmSync(temp, { recursive: true, force: true });
  }
});

test("catalog validation detects local package incompatibility", () => {
  const catalog = structuredClone(readJson(FOUNDATION_CATALOG_PATH));
  const filesystem = catalog.skills.find((skill) => skill.id === "agentweave.core.filesystem");
  filesystem.version = "9.0.0";
  assert.throws(
    () => validateCatalogData(catalog),
    /does not match local package/,
  );
});

test("Agent App validation rejects permissive policy and embedded secrets", () => {
  const temp = makeTempRoot();
  try {
    const output = join(temp, "unsafe-app");
    scaffoldAgentApp({ name: "Safe Agent", appId: "com.example.safe-agent", output });
    const manifestPath = join(output, "agent-app.json");
    const manifest = readJson(manifestPath);

    manifest.policy.externalSideEffects = "allow_by_policy";
    writeJson(manifestPath, manifest);
    assert.throws(() => validateAgentApp(output), /must deny or require approval/);

    manifest.policy.externalSideEffects = "require_approval";
    manifest.apiKey = "not-allowed";
    writeJson(manifestPath, manifest);
    assert.throws(() => validateAgentApp(output), /must not contain secret material/);
  } finally {
    rmSync(temp, { recursive: true, force: true });
  }
});

test("CLI creates and validates an Agent App", () => {
  const temp = makeTempRoot();
  try {
    const output = join(temp, "cli-agent");
    const create = spawnSync(
      process.execPath,
      [
        SCRIPT_PATH,
        "--name",
        "CLI Agent",
        "--app-id",
        "com.example.cli-agent",
        "--output",
        relative(PROJECT_ROOT, output),
      ],
      { cwd: PROJECT_ROOT, encoding: "utf8" },
    );
    assert.equal(create.status, 0, create.stderr);
    assert.match(create.stdout, /Created and validated Agent App/);

    const validate = spawnSync(
      process.execPath,
      [SCRIPT_PATH, "--validate", relative(PROJECT_ROOT, output)],
      { cwd: PROJECT_ROOT, encoding: "utf8" },
    );
    assert.equal(validate.status, 0, validate.stderr);
    assert.match(validate.stdout, /Validated/);
  } finally {
    rmSync(temp, { recursive: true, force: true });
  }
});
