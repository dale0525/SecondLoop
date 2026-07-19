import assert from "node:assert/strict";
import {
  chmodSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { join } from "node:path";
import test from "node:test";

import {
  desktopPackagePlan,
  prepareDesktopStaging,
  verifyDesktopStaging,
} from "../apps/desktop/scripts/package-macos.mjs";
import {
  computeProjectDesiredHash,
  computeRuntimeProjectionHash,
  hashPublicValue,
  projectRuntimeProjection,
} from "./agentweave-project.mjs";
import { packageAgentApp } from "./package-agent-app.mjs";
import { PROJECT_ROOT, scaffoldAgentApp } from "./scaffold-agent-app.mjs";

const ACCOUNT_ID = "0123456789abcdef0123456789abcdef";
const PRIVATE_SENTINEL = "sk-private-developer-fixture-that-must-not-ship";

test("managed App desktop staging excludes the developer control plane and secrets", () => {
  mkdirSync(join(PROJECT_ROOT, ".tool"), { recursive: true });
  const root = mkdtempSync(join(PROJECT_ROOT, ".tool", "managed-desktop-staging-"));
  try {
    const appRoot = join(root, "app");
    scaffoldAgentApp({
      name: "Managed Desktop Fixture",
      appId: "com.example.managed-desktop-fixture",
      output: appRoot,
    });
    configureManagedApp(appRoot);
    const releaseRoot = join(root, "release");
    packageAgentApp({ input: appRoot, output: releaseRoot });

    const rendererRoot = join(root, "renderer");
    const electronRoot = join(root, "electron");
    const sidecarPath = join(root, "agent-server");
    mkdirSync(rendererRoot, { recursive: true });
    mkdirSync(electronRoot, { recursive: true });
    writeFileSync(join(rendererRoot, "index.html"), "<!doctype html><title>fixture</title>\n");
    for (const file of ["main.cjs", "preload.cjs", "approval-preload.cjs"]) {
      writeFileSync(join(electronRoot, file), "module.exports = {};\n");
    }
    writeFileSync(sidecarPath, "#!/bin/sh\nexit 0\n");
    chmodSync(sidecarPath, 0o755);

    const plan = desktopPackagePlan({
      input: appRoot,
      output: join(root, "output"),
      arch: process.arch,
    });
    const staging = prepareDesktopStaging({
      plan,
      releaseRoot,
      sidecarPath,
      rendererRoot,
      electronRoot,
      stagingRoot: join(root, "staging"),
    });

    assert.equal(verifyDesktopStaging(staging), true);
    assert.equal(
      existsSync(join(staging.resourcesRoot, "agent-app", "app", "agentweave-project.json")),
      false,
    );
    assert.equal(
      existsSync(join(staging.resourcesRoot, "agent-app", "app", ".agentweave")),
      false,
    );
    const artifactText = regularFiles(join(root, "staging"))
      .map((path) => readFileSync(path, "utf8"))
      .join("\n");
    assert.doesNotMatch(artifactText, new RegExp(PRIVATE_SENTINEL));
    assert.doesNotMatch(artifactText, new RegExp(ACCOUNT_ID));
    assert.doesNotMatch(artifactText, /AGENTWEAVE_DEV_API|CLOUDFLARE_GATEWAY_ARTIFACT/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

function configureManagedApp(appRoot) {
  const manifestPath = join(appRoot, "agent-app.json");
  const projectPath = join(appRoot, "agentweave-project.json");
  const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
  const project = {
    schemaVersion: 1,
    providers: {
      identity: {
        id: "agentweave.identity.oidc",
        version: "0.1.0",
        publicConfig: {
          preset: "auth0",
          issuer: "https://identity.example.test/",
          clientId: "native-public-client",
          audience: "https://gateway.example.test",
          scopes: ["openid", "profile", "offline_access"],
          redirectUri: "com.example.managed-desktop-fixture:/oauth/callback",
          gatewayAlgorithm: "RS256",
        },
      },
      entitlement: {
        id: "agentweave.entitlements.http",
        version: "0.1.0",
        publicConfig: {
          baseUrl: "https://entitlements.example.test/",
          timeoutMilliseconds: 5000,
          maxResponseBytes: 65536,
        },
      },
      gateway: {
        id: "cloudflare-workers",
        version: "0.1.0",
        publicConfig: {
          upstreamBaseUrl: "https://api.openai.com/v1",
          upstreamAuthentication: "bearer",
        },
      },
    },
    modelAccess: {
      configurationPolicy: "app_managed",
      profile: {
        providerId: "cloudflare-gateway",
        endpointType: "responses",
        baseUrl: "https://managed-desktop-fixture.workers.dev/v1",
        modelName: "approved-model",
        authentication: "user_identity",
        headers: {},
      },
    },
    deployment: {
      provider: "cloudflare",
      cloudflare: {
        accountId: ACCOUNT_ID,
        workerName: "managed-desktop-fixture",
        environment: "production",
      },
    },
  };
  Object.assign(manifest, {
    schemaVersion: 2,
    ...projectRuntimeProjection(project),
  });
  writeFileSync(projectPath, `${JSON.stringify(project, null, 2)}\n`);
  writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
  mkdirSync(join(appRoot, ".agentweave"), { recursive: true });
  const lock = {
    schemaVersion: 1,
    desiredHash: computeProjectDesiredHash(project),
    runtimeProjectionHash: computeRuntimeProjectionHash(manifest),
    gateway: {
      id: project.providers.gateway.id,
      version: project.providers.gateway.version,
      publicConfigHash: hashPublicValue(project.providers.gateway.publicConfig),
    },
    deployment: {
      provider: "cloudflare",
      reference: {
        ...project.deployment.cloudflare,
        versionId: "version-1",
        deploymentId: "deployment-1",
        endpoint: project.modelAccess.profile.baseUrl,
      },
    },
  };
  writeFileSync(
    join(appRoot, ".agentweave", "deployment.lock"),
    `${JSON.stringify(lock, null, 2)}\n`,
  );
  writeFileSync(join(appRoot, ".agentweave", "developer-secret.txt"), PRIVATE_SENTINEL);
}

function regularFiles(root) {
  const result = [];
  for (const entry of readdirSync(root, { withFileTypes: true })) {
    const path = join(root, entry.name);
    if (entry.isDirectory()) result.push(...regularFiles(path));
    else if (entry.isFile()) result.push(path);
  }
  return result;
}
