import { existsSync, readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { basename, join, relative, resolve } from "node:path";

export const PROJECT_ROOT = resolve(fileURLToPath(new URL("..", import.meta.url)));

function fail(message) {
  throw new Error(message);
}

function manifestAt(root) {
  return existsSync(join(root, "agent-app.json"));
}

function candidateProductRoots(projectRoot) {
  const productsRoot = join(projectRoot, "products");
  if (!existsSync(productsRoot)) return [];
  return readdirSync(productsRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && manifestAt(join(productsRoot, entry.name)))
    .map((entry) => join(productsRoot, entry.name))
    .sort();
}

function readManifest(appRoot) {
  try {
    return JSON.parse(readFileSync(join(appRoot, "agent-app.json"), "utf8"));
  } catch (error) {
    fail(`Agent App manifest is invalid: ${error instanceof Error ? error.message : String(error)}`);
  }
}

function safeSegment(value, fallback) {
  const segment = String(value ?? "")
    .trim()
    .toLowerCase()
    .replaceAll(/[^a-z0-9]+/g, "-")
    .replaceAll(/^-+|-+$/g, "");
  return segment || fallback;
}

export function resolveAppProject({
  projectRoot = PROJECT_ROOT,
  appRoot = process.env.AGENTWEAVE_APP_ROOT,
} = {}) {
  let selected;
  if (appRoot) {
    selected = resolve(projectRoot, appRoot);
  } else if (manifestAt(join(projectRoot, "app"))) {
    selected = join(projectRoot, "app");
  } else {
    const products = candidateProductRoots(projectRoot);
    if (products.length !== 1) {
      fail(products.length === 0
        ? "No Agent App was found. Create app/agent-app.json or set AGENTWEAVE_APP_ROOT."
        : "Multiple Agent Apps were found under products/. Set AGENTWEAVE_APP_ROOT to choose one.");
    }
    [selected] = products;
  }
  if (!manifestAt(selected)) fail(`Agent App root does not contain agent-app.json: ${selected}`);
  const manifest = readManifest(selected);
  if (typeof manifest.appId !== "string" || !manifest.appId.trim()) {
    fail("Agent App manifest appId is required");
  }
  if (typeof manifest.branding?.displayName !== "string" || !manifest.branding.displayName.trim()) {
    fail("Agent App manifest branding.displayName is required");
  }
  const outputName = safeSegment(manifest.appId, safeSegment(basename(selected), "agent-app"));
  return Object.freeze({
    appId: manifest.appId,
    appRoot: selected,
    appRootRelative: relative(projectRoot, selected) || ".",
    displayName: manifest.branding.displayName,
    outputName,
    packagesRoot: join(selected, "packages"),
    projectRoot,
  });
}
