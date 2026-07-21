import assert from "node:assert/strict";
import {
  mkdirSync,
  mkdtempSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { join } from "node:path";
import test from "node:test";

import {
  computeProjectDesiredHash,
  hashPublicValue,
  projectRuntimeProjection,
  runtimeProviderProjection,
  validateAgentWeaveProjectData,
  validateAgentWeaveProjectWorkspace,
  validateDeploymentLockData,
  validateProjectMatchesRuntime,
  validateRuntimeProviderProjection,
} from "./agentweave-project.mjs";
import { PROJECT_ROOT } from "./scaffold-agent-app.mjs";

const ACCOUNT_ID = "0123456789abcdef0123456789abcdef";
const ENDPOINT = "https://example-agent-gateway.workers.dev/v1";

function provider(id, publicConfig = {}) {
  return { id, version: "1.0.0", publicConfig };
}

function managedProject() {
  return {
    schemaVersion: 1,
    providers: {
      identity: provider("agentweave.identity.oidc", {
        audience: "com.example.agent.gateway",
        clientId: "desktop-public-client",
        issuer: "https://identity.example.com",
      }),
      entitlement: provider("agentweave.entitlement.remote", {
        policyId: "standard",
      }),
      gateway: provider("agentweave.gateway.cloudflare", {
        requestLimit: 60,
      }),
    },
    modelAccess: {
      configurationPolicy: "app_managed",
      profile: {
        providerId: "agentweave.gateway.cloudflare",
        endpointType: "responses",
        baseUrl: ENDPOINT,
        modelName: "approved-model",
        authentication: "user_identity",
        headers: { "X-AgentWeave-Protocol": "1" },
      },
    },
    deployment: {
      provider: "cloudflare",
      cloudflare: {
        accountId: ACCOUNT_ID,
        workerName: "example-agent-gateway",
        environment: "production",
      },
    },
  };
}

function managedApp(project = managedProject()) {
  return {
    schemaVersion: 2,
    ...projectRuntimeProjection(project),
  };
}

function deploymentLock(project = managedProject(), app = managedApp(project)) {
  return {
    schemaVersion: 1,
    desiredHash: computeProjectDesiredHash(project),
    runtimeProjectionHash: hashPublicValue(runtimeProviderProjection(app)),
    gateway: {
      id: project.providers.gateway.id,
      version: project.providers.gateway.version,
      publicConfigHash: hashPublicValue(project.providers.gateway.publicConfig),
    },
    deployment: {
      provider: "cloudflare",
      reference: {
        ...project.deployment.cloudflare,
        versionId: "f165ce16-42aa-4b95-b544-4d0bc39f49a2",
        deploymentId: "12ee6020-b9b1-4d11-bcc4-176f3d890d52",
        endpoint: ENDPOINT,
      },
    },
  };
}

function writeJson(path, value) {
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

test("project desired state validates providers and hashes canonical public configuration", () => {
  const project = managedProject();
  assert.equal(validateAgentWeaveProjectData(project), project);

  const reordered = {
    deployment: project.deployment,
    modelAccess: project.modelAccess,
    providers: project.providers,
    schemaVersion: 1,
  };
  assert.equal(computeProjectDesiredHash(project), computeProjectDesiredHash(reordered));

  const projection = projectRuntimeProjection(project);
  assert.deepEqual(projection.identity, {
    mode: "required",
    provider: project.providers.identity,
  });
  assert.deepEqual(projection.entitlements, {
    mode: "required",
    provider: project.providers.entitlement,
  });
  assert.equal(validateProjectMatchesRuntime(project, managedApp(project)), true);
});

test("project desired state rejects unknown fields and recursively rejects credential material", () => {
  const unknown = managedProject();
  unknown.extra = true;
  assert.throws(() => validateAgentWeaveProjectData(unknown), /unknown field 'extra'/);

  const namedSecret = managedProject();
  namedSecret.providers.identity.publicConfig.nested = {
    apiKey: "must-never-be-written",
  };
  assert.throws(() => validateAgentWeaveProjectData(namedSecret), /apiKey.*secret material/);

  const publicTokenMetadata = managedProject();
  publicTokenMetadata.providers.identity.publicConfig.tokenEndpoint = "https://identity.example.com/token";
  publicTokenMetadata.providers.gateway.publicConfig.maxOutputTokens = 4096;
  assert.equal(validateAgentWeaveProjectData(publicTokenMetadata), publicTokenMetadata);

  const firebaseWebConfiguration = managedProject();
  firebaseWebConfiguration.providers.identity = provider("agentweave.identity.firebase", {
    projectId: "sample-project-123",
    firebaseWebKey: "public-firebase-browser-identifier",
    webApplicationId: "1:123:web:abc",
    authDomain: "sample-project-123.firebaseapp.com",
  });
  assert.equal(
    validateAgentWeaveProjectData(firebaseWebConfiguration),
    firebaseWebConfiguration,
  );

  const accessToken = managedProject();
  accessToken.providers.identity.publicConfig.accessToken = "must-never-be-written";
  assert.throws(() => validateAgentWeaveProjectData(accessToken), /accessToken.*secret material/);

  const disguisedSecret = managedProject();
  disguisedSecret.providers.gateway.publicConfig.value = "sk-this-is-a-real-looking-secret-value";
  assert.throws(() => validateAgentWeaveProjectData(disguisedSecret), /must not contain secret material/);

  const credentialHeader = managedProject();
  credentialHeader.modelAccess.profile.headers.Authorization = "Bearer hidden-value";
  assert.throws(() => validateAgentWeaveProjectData(credentialHeader), /must not contain secret material/);
});

test("runtime provider projection preserves v1 and enforces complete fail-closed v2 policy", () => {
  assert.deepEqual(validateRuntimeProviderProjection({ schemaVersion: 1 }), {});
  assert.throws(
    () => validateRuntimeProviderProjection({
      schemaVersion: 1,
      identity: { mode: "local_single_user" },
    }),
    /requires schemaVersion 2/,
  );
  assert.throws(
    () => validateRuntimeProviderProjection({
      schemaVersion: 2,
      modelAccess: { configurationPolicy: "user_configurable" },
      identity: { mode: "local_single_user" },
    }),
    /entitlements is required/,
  );

  const anonymousRemote = managedApp();
  anonymousRemote.modelAccess.profile.authentication = "none";
  assert.throws(
    () => validateRuntimeProviderProjection(anonymousRemote),
    /must use user_identity/,
  );

  const missingEntitlement = managedApp();
  missingEntitlement.entitlements = { mode: "disabled" };
  assert.throws(
    () => validateRuntimeProviderProjection(missingEntitlement),
    /must require identity and entitlements/,
  );

  const loopback = {
    schemaVersion: 2,
    modelAccess: {
      configurationPolicy: "app_managed",
      profile: {
        providerId: "agentweave.gateway.local",
        endpointType: "responses",
        baseUrl: "http://127.0.0.1:11434/v1",
        modelName: "local-model",
        authentication: "none",
      },
    },
    identity: { mode: "local_single_user" },
    entitlements: { mode: "disabled" },
  };
  assert.deepEqual(runtimeProviderProjection(loopback).modelAccess, loopback.modelAccess);
});

test("deployment lock strictly binds Cloudflare references to desired and runtime hashes", () => {
  const project = managedProject();
  const app = managedApp(project);
  const lock = deploymentLock(project, app);
  assert.equal(validateDeploymentLockData(lock, { project, app }), lock);

  const staleDesired = structuredClone(lock);
  staleDesired.desiredHash = `sha256:${"0".repeat(64)}`;
  assert.throws(
    () => validateDeploymentLockData(staleDesired, { project, app }),
    /desiredHash is stale/,
  );

  const movedDeployment = structuredClone(lock);
  movedDeployment.deployment.reference.workerName = "different-worker";
  assert.throws(
    () => validateDeploymentLockData(movedDeployment, { project, app }),
    /workerName.*does not match desired state/,
  );

  const unknown = structuredClone(lock);
  unknown.deployment.reference.zoneId = "not-allowed";
  assert.throws(
    () => validateDeploymentLockData(unknown, { project, app }),
    /unknown field 'zoneId'/,
  );
});

test("workspace validation requires a matching deployment lock only for production packaging", () => {
  mkdirSync(join(PROJECT_ROOT, ".tool"), { recursive: true });
  const root = mkdtempSync(join(PROJECT_ROOT, ".tool", "agentweave-project-"));
  try {
    const project = managedProject();
    const app = managedApp(project);
    writeJson(join(root, "agentweave-project.json"), project);

    const configured = validateAgentWeaveProjectWorkspace(root, { app });
    assert.equal(configured.lock, null);
    assert.throws(
      () => validateAgentWeaveProjectWorkspace(root, { app, requireDeploymentLock: true }),
      /deployment\.lock is required before packaging/,
    );

    mkdirSync(join(root, ".agentweave"));
    writeJson(join(root, ".agentweave", "deployment.lock"), deploymentLock(project, app));
    assert.equal(
      validateAgentWeaveProjectWorkspace(root, { app, requireDeploymentLock: true }).lock.deployment.provider,
      "cloudflare",
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("schemaVersion 1 Apps remain valid only with an unconfigured legacy project", () => {
  const legacyProject = {
    schemaVersion: 1,
    providers: { identity: null, entitlement: null, gateway: null },
    modelAccess: { configurationPolicy: "user_configurable" },
    deployment: null,
  };
  assert.equal(validateProjectMatchesRuntime(legacyProject, { schemaVersion: 1 }), true);

  const configured = managedProject();
  assert.throws(
    () => validateProjectMatchesRuntime(configured, { schemaVersion: 1 }),
    /cannot project configured providers/,
  );
});
