import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import test from "node:test";

import { buildDesktopLocalization } from "./build-desktop-localization.mjs";
import { PROJECT_ROOT, scaffoldAgentApp } from "./scaffold-agent-app.mjs";

const TEST_ROOT = join(PROJECT_ROOT, ".tool");

test("host localization catalogs keep keys and placeholders aligned", () => {
  const bundle = buildDesktopLocalization();
  const english = bundle.locales.find((entry) => entry.id === "en").messages;
  const chinese = bundle.locales.find((entry) => entry.id === "zh-CN").messages;
  assert.deepEqual(Object.keys(chinese).sort(), Object.keys(english).sort());
  for (const key of Object.keys(english)) {
    const placeholders = (value) => [...value.matchAll(/\{([A-Za-z][A-Za-z0-9_]*)\}/g)]
      .map((match) => match[1])
      .sort();
    assert.deepEqual(placeholders(chinese[key]), placeholders(english[key]), key);
  }
});

test("desktop localization merges packaged App messages over host catalogs", () => {
  mkdirSync(TEST_ROOT, { recursive: true });
  const temp = mkdtempSync(join(TEST_ROOT, "desktop-localization-"));
  try {
    const appRoot = join(temp, "app");
    scaffoldAgentApp({ name: "Localized Agent", appId: "com.example.localized-agent", output: appRoot });
    const chinesePath = join(appRoot, "locales", "zh-CN.json");
    const chinese = JSON.parse(readFileSync(chinesePath, "utf8"));
    chinese["app.name"] = "本地化智能体";
    writeFileSync(chinesePath, `${JSON.stringify(chinese, null, 2)}\n`, "utf8");
    const manifestPath = join(appRoot, "agent-app.json");
    const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
    manifest.schemaVersion = 2;
    manifest.modelAccess = { configurationPolicy: "user_configurable" };
    manifest.identity = {
      mode: "required",
      provider: { id: "agentweave.identity.firebase", version: "0.1.0", publicConfig: {} },
    };
    manifest.entitlements = { mode: "disabled" };
    writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");

    const bundle = buildDesktopLocalization(appRoot);

    assert.equal(bundle.defaultLocale, "en");
    assert.deepEqual(bundle.locales.map((entry) => entry.id), ["en", "zh-CN"]);
    const zh = bundle.locales.find((entry) => entry.id === "zh-CN");
    assert.equal(zh.messages["app.name"], "本地化智能体");
    assert.equal(zh.messages["settings.title"], "设置");
  } finally {
    rmSync(temp, { recursive: true, force: true });
  }
});
