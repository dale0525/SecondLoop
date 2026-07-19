import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { join, relative } from "node:path";
import test from "node:test";

import { PROJECT_ROOT, scaffoldAgentApp } from "./scaffold-agent-app.mjs";
import {
  computeProjectDesiredHash,
  hashPublicValue,
  runtimeProviderProjection,
} from "./agentweave-project.mjs";
import {
  packageAgentApp,
  validateAgentAppRelease,
} from "./package-agent-app.mjs";

const TEST_ROOT = join(PROJECT_ROOT, ".tool");
const SCRIPT_PATH = join(PROJECT_ROOT, "scripts", "package-agent-app.mjs");
const CLOUDFLARE_ACCOUNT_ID = "0123456789abcdef0123456789abcdef";
const MANAGED_ENDPOINT = "https://gateway.example.com/v1";

function makeTempRoot() {
  mkdirSync(TEST_ROOT, { recursive: true });
  return mkdtempSync(join(TEST_ROOT, "agent-app-release-"));
}

function fileMap(root, prefix = "") {
  const result = {};
  const directory = prefix ? join(root, prefix) : root;
  for (const entry of readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    const path = prefix ? `${prefix}/${entry.name}` : entry.name;
    if (entry.isDirectory()) Object.assign(result, fileMap(root, path));
    else result[path] = readFileSync(join(root, path));
  }
  return result;
}

function configureManagedGateway(appRoot, { writeLock = true } = {}) {
  const manifestPath = join(appRoot, "agent-app.json");
  const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
  const identity = {
    id: "agentweave.identity.oidc",
    version: "1.0.0",
    publicConfig: {
      issuer: "https://identity.example.com",
      clientId: "public-desktop-client",
      audience: "com.example.release.gateway",
    },
  };
  const entitlement = {
    id: "agentweave.entitlement.remote",
    version: "1.0.0",
    publicConfig: { policyId: "standard" },
  };
  const gateway = {
    id: "agentweave.gateway.cloudflare",
    version: "1.0.0",
    publicConfig: { requestLimit: 60 },
  };
  const modelAccess = {
    configurationPolicy: "app_managed",
    profile: {
      providerId: "agentweave.gateway.cloudflare",
      endpointType: "responses",
      baseUrl: MANAGED_ENDPOINT,
      modelName: "approved-model",
      authentication: "user_identity",
    },
  };
  Object.assign(manifest, {
    modelAccess,
    identity: { mode: "required", provider: identity },
    entitlements: { mode: "required", provider: entitlement },
  });
  writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");

  const project = {
    schemaVersion: 1,
    providers: { identity, entitlement, gateway },
    modelAccess,
    deployment: {
      provider: "cloudflare",
      cloudflare: {
        accountId: CLOUDFLARE_ACCOUNT_ID,
        workerName: "deployment-ref-worker",
        environment: "production",
      },
    },
  };
  writeFileSync(
    join(appRoot, "agentweave-project.json"),
    `${JSON.stringify(project, null, 2)}\n`,
    "utf8",
  );
  if (writeLock) {
    mkdirSync(join(appRoot, ".agentweave"), { recursive: true });
    const lock = {
      schemaVersion: 1,
      desiredHash: computeProjectDesiredHash(project),
      runtimeProjectionHash: hashPublicValue(runtimeProviderProjection(manifest)),
      gateway: {
        id: gateway.id,
        version: gateway.version,
        publicConfigHash: hashPublicValue(gateway.publicConfig),
      },
      deployment: {
        provider: "cloudflare",
        reference: {
          ...project.deployment.cloudflare,
          versionId: "f165ce16-42aa-4b95-b544-4d0bc39f49a2",
          deploymentId: "12ee6020-b9b1-4d11-bcc4-176f3d890d52",
          endpoint: MANAGED_ENDPOINT,
        },
      },
    };
    writeFileSync(
      join(appRoot, ".agentweave", "deployment.lock"),
      `${JSON.stringify(lock, null, 2)}\n`,
      "utf8",
    );
  }
  return { manifest, project };
}

test("Agent App release packaging is deterministic and locks selected packages", () => {
  const temp = makeTempRoot();
  try {
    const first = join(temp, "first");
    const second = join(temp, "second");
    const input = join(PROJECT_ROOT, "examples", "secretary-agent");
    packageAgentApp({ input, output: first, runtimeVersion: "0.1.0" });
    packageAgentApp({ input, output: second, runtimeVersion: "0.1.0" });
    assert.deepEqual(fileMap(first), fileMap(second));

    const lock = validateAgentAppRelease(first);
    assert.equal(lock.app.appId, "com.example.secretary-agent");
    assert.deepEqual(lock.packages.map((entry) => entry.id), [
      "agentweave.foundation.mail",
      "agentweave.foundation.memory",
      "com.example.secretary.routines",
    ]);
    assert.deepEqual(lock.hostRequirements.connectors, [
      { id: "agentweave-mail", runtimeVersion: "0.1.0" },
    ]);
    assert.deepEqual(lock.hostRequirements.providers, [
      { id: "memory-provider", runtimeVersion: "0.1.0" },
    ]);
    assert.deepEqual(lock.publicProviderProjection.value, {});
    assert.equal(lock.publicProviderProjection.manifestSchemaVersion, 1);
    assert.match(lock.publicProviderProjection.contentHash, /^sha256:[0-9a-f]{64}$/);
    assert.doesNotMatch(JSON.stringify(lock), new RegExp(PROJECT_ROOT.replaceAll("/", "\\/")));
  } finally {
    rmSync(temp, { recursive: true, force: true });
  }
});

test("release packaging selects App locales without mutating source", () => {
  const temp = makeTempRoot();
  try {
    const input = join(PROJECT_ROOT, "examples", "minimal-agent");
    const sourceManifest = readFileSync(join(input, "agent-app.json"), "utf8");
    const release = join(temp, "zh-release");

    const result = packageAgentApp({
      input,
      output: release,
      locales: ["zh-CN"],
    });

    assert.deepEqual(result.lock.localization, {
      defaultLocale: "zh-CN",
      locales: ["zh-CN"],
    });
    const packagedManifest = JSON.parse(readFileSync(join(release, "app", "agent-app.json"), "utf8"));
    assert.equal(packagedManifest.localization.defaultLocale, "zh-CN");
    assert.deepEqual(packagedManifest.localization.locales.map((locale) => locale.id), ["zh-CN"]);
    assert.equal(existsSync(join(release, "app", "locales", "en.json")), false);
    assert.equal(existsSync(join(release, "app", "locales", "zh-CN.json")), true);
    assert.equal(readFileSync(join(input, "agent-app.json"), "utf8"), sourceManifest);
    validateAgentAppRelease(release);
  } finally {
    rmSync(temp, { recursive: true, force: true });
  }
});

test("release packaging CLI accepts locale selection", () => {
  const temp = makeTempRoot();
  try {
    const release = join(temp, "cli-release");
    const result = spawnSync(
      process.execPath,
      [
        SCRIPT_PATH,
        "--input",
        "examples/minimal-agent",
        "--output",
        relative(PROJECT_ROOT, release),
        "--locales",
        "zh-CN",
        "--default-locale",
        "zh-CN",
      ],
      { cwd: PROJECT_ROOT, encoding: "utf8" },
    );

    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(validateAgentAppRelease(release).localization, {
      defaultLocale: "zh-CN",
      locales: ["zh-CN"],
    });
  } finally {
    rmSync(temp, { recursive: true, force: true });
  }
});

test("release verification rejects tampering and future lock schemas", () => {
  const temp = makeTempRoot();
  try {
    const release = join(temp, "release");
    packageAgentApp({
      input: join(PROJECT_ROOT, "examples", "minimal-agent"),
      output: release,
    });
    const prompt = join(release, "app", "prompts", "system.md");
    writeFileSync(prompt, `${readFileSync(prompt, "utf8")}tampered\n`, "utf8");
    assert.throws(() => validateAgentAppRelease(release), /content hash mismatch/);

    rmSync(release, { recursive: true, force: true });
    packageAgentApp({
      input: join(PROJECT_ROOT, "examples", "minimal-agent"),
      output: release,
    });
    const lockPath = join(release, "agent-app.lock.json");
    const lock = JSON.parse(readFileSync(lockPath, "utf8"));
    lock.publicProviderProjection.contentHash = `sha256:${"0".repeat(64)}`;
    writeFileSync(lockPath, `${JSON.stringify(lock, null, 2)}\n`, "utf8");
    assert.throws(() => validateAgentAppRelease(release), /public provider projection/);

    rmSync(release, { recursive: true, force: true });
    packageAgentApp({
      input: join(PROJECT_ROOT, "examples", "minimal-agent"),
      output: release,
    });
    const futureLock = JSON.parse(readFileSync(lockPath, "utf8"));
    futureLock.schemaVersion = 2;
    writeFileSync(lockPath, `${JSON.stringify(futureLock, null, 2)}\n`, "utf8");
    assert.throws(() => validateAgentAppRelease(release), /unsupported Agent App lock schema/);
  } finally {
    rmSync(temp, { recursive: true, force: true });
  }
});

test("release packaging excludes credential-shaped files", () => {
  const temp = makeTempRoot();
  try {
    const app = join(temp, "app");
    mkdirSync(app, { recursive: true });
    for (const [path, bytes] of Object.entries(fileMap(join(PROJECT_ROOT, "examples", "minimal-agent")))) {
      const destination = join(app, path);
      mkdirSync(join(destination, ".."), { recursive: true });
      writeFileSync(destination, bytes);
    }
    writeFileSync(join(app, ".env"), "API_KEY=must-not-ship\n", "utf8");
    assert.throws(
      () => packageAgentApp({ input: app, output: join(temp, "release") }),
      /forbidden credential file/,
    );
  } finally {
    rmSync(temp, { recursive: true, force: true });
  }
});

test("release packaging scans included content for credential assignment markers", () => {
  const temp = makeTempRoot();
  try {
    const app = join(temp, "app");
    scaffoldAgentApp({ name: "Credential Scan", appId: "com.example.credential-scan", output: app });
    writeFileSync(
      join(app, "leak.txt"),
      "OPENAI_API_KEY=sk-production-value-that-must-not-ship\n",
      "utf8",
    );
    assert.throws(
      () => packageAgentApp({ input: app, output: join(temp, "release") }),
      /credential marker|credential assignment marker/,
    );
  } finally {
    rmSync(temp, { recursive: true, force: true });
  }
});

test("app-managed packaging requires deployment lock and excludes all developer control-plane files", () => {
  const temp = makeTempRoot();
  try {
    const app = join(temp, "app");
    scaffoldAgentApp({ name: "Managed Gateway", appId: "com.example.managed-gateway", output: app });
    configureManagedGateway(app, { writeLock: false });
    assert.throws(
      () => packageAgentApp({ input: app, output: join(temp, "missing-lock-release") }),
      /deployment\.lock is required before packaging/,
    );

    const { manifest } = configureManagedGateway(app);
    mkdirSync(join(app, ".github", "workflows"), { recursive: true });
    mkdirSync(join(app, ".vscode"), { recursive: true });
    writeFileSync(join(app, ".github", "workflows", "release.yml"), "name: developer-only\n", "utf8");
    writeFileSync(join(app, ".vscode", "settings.json"), "{}\n", "utf8");
    writeFileSync(join(app, ".gitignore"), ".agentweave/\n", "utf8");

    const release = join(temp, "release");
    const result = packageAgentApp({ input: app, output: release });
    assert.equal(existsSync(join(release, "app", "agentweave-project.json")), false);
    assert.equal(existsSync(join(release, "app", ".agentweave")), false);
    assert.equal(existsSync(join(release, "app", ".github")), false);
    assert.equal(existsSync(join(release, "app", ".vscode")), false);
    assert.equal(existsSync(join(release, "app", ".gitignore")), false);
    assert.deepEqual(result.lock.publicProviderProjection.value, runtimeProviderProjection(manifest));
    const serializedLock = JSON.stringify(result.lock);
    assert.doesNotMatch(serializedLock, new RegExp(CLOUDFLARE_ACCOUNT_ID));
    assert.doesNotMatch(serializedLock, /deployment-ref-worker/);
    validateAgentAppRelease(release);
  } finally {
    rmSync(temp, { recursive: true, force: true });
  }
});

test("release packaging carries declared custom themes and auto-discovered fonts", () => {
  const temp = makeTempRoot();
  try {
    const app = join(temp, "themed-app");
    scaffoldAgentApp({ name: "Release Theme", appId: "com.example.release-theme", output: app });
    writeFileSync(
      join(app, "themes", "brand.jsonc"),
      '{ "name": "Brand", "colors": { "editor.background": "#101010", }, }\n',
      "utf8",
    );
    writeFileSync(join(app, "fonts", "ui.woff2"), Buffer.from("font-fixture"));
    const manifestPath = join(app, "agent-app.json");
    const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
    manifest.appearance.defaultTheme = "com.example.brand";
    manifest.appearance.themes.builtins = ["vscode.light-2026"];
    manifest.appearance.themes.custom = [{
      id: "com.example.brand",
      path: "themes/brand.jsonc",
    }];
    writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");

    const release = join(temp, "release");
    packageAgentApp({ input: app, output: release });

    assert.equal(existsSync(join(release, "app", "themes", "brand.jsonc")), true);
    assert.equal(existsSync(join(release, "app", "fonts", "ui.woff2")), true);
    assert.equal(validateAgentAppRelease(release).app.appId, "com.example.release-theme");
  } finally {
    rmSync(temp, { recursive: true, force: true });
  }
});
