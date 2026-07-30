import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import test from "node:test";

import { buildDesktopAppearance } from "./build-desktop-appearance.mjs";
import { PROJECT_ROOT, scaffoldAgentApp } from "./scaffold-agent-app.mjs";

const TEST_ROOT = join(PROJECT_ROOT, ".tool");

test("desktop appearance build includes only selected themes and auto-discovers font slots", () => {
  mkdirSync(TEST_ROOT, { recursive: true });
  const temp = mkdtempSync(join(TEST_ROOT, "desktop-appearance-"));
  try {
    const appRoot = join(temp, "app");
    scaffoldAgentApp({ name: "Themed Agent", appId: "com.example.themed-agent", output: appRoot });
    writeFileSync(
      join(appRoot, "themes", "base.json"),
      '{ "colors": { "editor.background": "#101010", "editor.foreground": "#eeeeee" } }\n',
      "utf8",
    );
    writeFileSync(
      join(appRoot, "themes", "brand.jsonc"),
      '{ "include": "./base.json", "name": "Brand Dark", "colors": { "button.background": "#1680a8", }, }\n',
      "utf8",
    );
    writeFileSync(join(appRoot, "fonts", "ui-600.woff2"), Buffer.from("font-fixture"));
    const manifestPath = join(appRoot, "agent-app.json");
    const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
    manifest.appearance = {
      defaultTheme: "com.example.brand-dark",
      themes: {
        builtins: ["vscode.light-2026"],
        custom: [{
          id: "com.example.brand-dark",
          label: "Brand Dark",
          path: "themes/brand.jsonc",
        }],
      },
    };
    manifest.schemaVersion = 2;
    manifest.modelAccess = { configurationPolicy: "user_configurable" };
    manifest.identity = {
      mode: "required",
      provider: { id: "agentweave.identity.firebase", version: "0.1.0", publicConfig: {} },
    };
    manifest.entitlements = { mode: "disabled" };
    writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");

    const bundle = buildDesktopAppearance(appRoot);

    assert.equal(bundle.defaultTheme, "com.example.brand-dark");
    assert.deepEqual(bundle.themes.map((theme) => theme.id), [
      "vscode.light-2026",
      "com.example.brand-dark",
    ]);
    assert.equal(bundle.themes[1].colors["editor.background"], "#101010");
    assert.equal(bundle.themes[1].colors["button.background"], "#1680a8");
    assert.equal(bundle.fontFaces[0].slot, "ui");
    assert.equal(bundle.fontFaces[0].weight, "600");
    assert.match(bundle.fontFaces[0].dataUrl, /^data:font\/woff2;base64,/);
  } finally {
    rmSync(temp, { recursive: true, force: true });
  }
});
