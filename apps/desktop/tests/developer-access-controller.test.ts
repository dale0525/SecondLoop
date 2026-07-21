// @vitest-environment node

import { createServer } from "node:net";

import { describe, expect, it, vi } from "vitest";

import { registerDeveloperAccessController } from "../src/main/developerAccessController";
import { DEVELOPER_ACCESS_REQUEST_CHANNEL } from "../src/shared/developerAccess";

describe("developer access controller", () => {
  it("keeps the Cloudflare authorization URL and callback credentials in Main", async () => {
    const port = await freePort();
    const redirectUri = `http://127.0.0.1:${port}/agentweave/cloudflare/callback`;
    const harness = ipcHarness();
    const callbacks: unknown[] = [];
    const openExternal = vi.fn(async () => undefined);
    const ensureCredentialVault = vi.fn(async () => undefined);
    const requests: string[] = [];
    const dispose = registerDeveloperAccessController({
      ensureCredentialVault,
      ipcMain: harness.ipcMain,
      loadProject: vi.fn(),
      openExternal,
      recordDeployment: vi.fn(),
      redirectUri,
      requesterWebContents: { id: 7 },
      sidecarRequest: async (pathname, init) => {
        requests.push(pathname);
        if (pathname.endsWith("/callback")) {
          callbacks.push(JSON.parse(String(init?.body)) as unknown);
          return jsonResponse({ accounts: [], status: authorizationStatus("select_account") });
        }
        if (pathname.endsWith("/authorization")) {
          return jsonResponse({
            authorizationUrl: "https://dash.cloudflare.com/oauth2/auth?state=private-state",
            expiresAtUnixMs: Date.now() + 60_000,
          });
        }
        if (pathname.endsWith("/pending")) return jsonResponse(authorizationStatus("disconnected"));
        throw new Error(`Unexpected request: ${pathname}`);
      },
      verifyDeployment: vi.fn(),
    });

    const started = await harness.invoke({
      operation: "cloudflare.connect",
      input: { client: { mode: "agent_weave_public" } },
    });
    expect(started).toMatchObject({ phase: "awaiting_callback" });
    expect(JSON.stringify(started)).not.toContain("authorizationUrl");
    expect(openExternal).toHaveBeenCalledWith(
      "https://dash.cloudflare.com/oauth2/auth?state=private-state",
    );
    const callbackUrl = `${redirectUri}?code=private-code&state=private-state`;
    const response = await fetch(callbackUrl, { redirect: "error" });
    expect(response.status).toBe(200);
    expect(callbacks).toEqual([{ callbackUrl }]);
    expect(ensureCredentialVault).toHaveBeenCalledTimes(1);
    expect(requests).not.toContain("private-code");
    dispose();
  });

  it("keeps Google authorization and Firebase callback credentials in Main", async () => {
    const port = await freePort();
    const firebaseRedirectUri = `http://127.0.0.1:${port}/agentweave/firebase/callback`;
    const harness = ipcHarness();
    const callbacks: unknown[] = [];
    const openExternal = vi.fn(async () => undefined);
    const dispose = registerDeveloperAccessController({
      ensureCredentialVault: async () => undefined,
      firebaseRedirectUri,
      ipcMain: harness.ipcMain,
      loadProject: vi.fn(),
      openExternal,
      recordDeployment: vi.fn(),
      redirectUri: "http://127.0.0.1:48971/agentweave/cloudflare/callback",
      requesterWebContents: { id: 7 },
      sidecarRequest: async (pathname, init) => {
        if (pathname.endsWith("/callback")) {
          callbacks.push(JSON.parse(String(init?.body)) as unknown);
          return jsonResponse({
            providerId: "google.firebase",
            phase: "select_project",
            projectId: null,
            expiresAtUnixMs: Date.now() + 60_000,
            publicOauthClientAvailable: true,
          });
        }
        if (pathname.endsWith("/authorization")) {
          return jsonResponse({
            authorizationUrl: "https://accounts.google.com/o/oauth2/v2/auth?state=private-state",
            expiresAtUnixMs: Date.now() + 60_000,
          });
        }
        if (pathname.endsWith("/pending")) return jsonResponse({});
        throw new Error(`Unexpected request: ${pathname}`);
      },
      verifyDeployment: vi.fn(),
    });

    const started = await harness.invoke({
      operation: "firebase.connect",
      input: { client: { mode: "agent_weave_public" } },
    });
    expect(started).toMatchObject({ phase: "awaiting_callback" });
    expect(JSON.stringify(started)).not.toContain("authorizationUrl");
    expect(openExternal).toHaveBeenCalledWith(
      "https://accounts.google.com/o/oauth2/v2/auth?state=private-state",
    );
    const callbackUrl = `${firebaseRedirectUri}?code=private-google-code&state=private-state`;
    const response = await fetch(callbackUrl, { redirect: "error" });
    expect(response.status).toBe(200);
    expect(callbacks).toEqual([{ callbackUrl }]);
    dispose();
  });

  it("binds deployment apply to the project revision used for its plan", async () => {
    const harness = ipcHarness();
    const sidecarBodies: unknown[] = [];
    let currentRevision = "a".repeat(64);
    const recordDeployment = vi.fn(async (_revision, _receipt) => {
      currentRevision = "b".repeat(64);
      return {
        appRoot: "/project/app",
        revision: currentRevision,
        desiredHash: `sha256:${"c".repeat(64)}`,
        manifest: {},
        project: {},
        deploymentStatus: "missing" as const,
        deploymentMessage: null,
      };
    });
    const verifyDeployment = vi.fn(async (_deployment, _revision, _test) => ({
      appRoot: "/project/app",
      revision: "b".repeat(64),
      desiredHash: `sha256:${"c".repeat(64)}`,
      manifest: {},
      project: {},
      deploymentStatus: "ready" as const,
      deploymentMessage: null,
    }));
    registerDeveloperAccessController({
      ensureCredentialVault: async () => undefined,
      ipcMain: harness.ipcMain,
      loadProject: async () => ({
        appRoot: "/project/app",
        revision: currentRevision,
        desiredHash: `sha256:${"d".repeat(64)}`,
        manifest: { appId: "com.example.app" },
        project: appManagedProject(),
        deploymentStatus: "missing",
        deploymentMessage: null,
      }),
      openExternal: vi.fn(),
      recordDeployment,
      redirectUri: "http://127.0.0.1:48971/agentweave/cloudflare/callback",
      requesterWebContents: { id: 7 },
      sidecarRequest: async (pathname, init) => {
        sidecarBodies.push(init?.body ? JSON.parse(String(init.body)) : null);
        if (pathname.endsWith("/plan")) {
          return jsonResponse({
            planHash: "e".repeat(64),
            target: gatewayTarget(),
            operations: [],
            drift: { status: "missing", differences: [] },
            expiresAtUnixMs: Date.now() + 60_000,
          });
        }
        if (pathname.endsWith("/apply")) {
          return jsonResponse({
            providerId: "cloudflare-workers",
            providerVersion: "0.1.0",
            target: gatewayTarget(),
            outcome: "applied",
            previousVersionId: null,
            versionId: "version-1",
            endpoint: "https://example-gateway.example.workers.dev",
            operationId: "4f290eb3-8712-4f7d-bde8-0a98aa95e33b",
            completedAtUnixMs: 1_700_000_000_000,
          });
        }
        if (pathname.endsWith("/test")) {
          return jsonResponse({
            target: gatewayTarget(),
            protocolVersion: "1",
            remoteVersion: "version-1",
            testedAtUnixMs: 1_700_000_000_100,
          });
        }
        if (pathname.endsWith("/status")) {
          return jsonResponse({
            authorization: authorizationStatus("ready"),
            gatewayTemplate: { version: "gateway-v1", sha256: "f".repeat(64) },
            sensitiveBindings: {},
          });
        }
        throw new Error(`Unexpected request: ${pathname}`);
      },
      verifyDeployment,
    });

    const plan = await harness.invoke({
      operation: "gateway.plan",
      input: {
        expectedProjectRevision: "a".repeat(64),
        sensitiveInputs: {
          "gateway.upstreamApiKey": { revision: "v1", value: "model-secret" },
          "entitlement.serviceCredential": {
            revision: "v1",
            value: "projection-secret-value-with-32-bytes",
          },
        },
      },
    });
    expect(plan.planHash).toBe("e".repeat(64));
    expect(JSON.stringify(sidecarBodies[0])).not.toContain("expectedProjectRevision");
    expect(sidecarBodies[0]).toMatchObject({
      project: {
        appId: "com.example.app",
        projectRevision: "a".repeat(64),
      },
    });
    const applied = await harness.invoke({
      operation: "gateway.apply",
      input: { planHash: "e".repeat(64) },
    });
    expect(applied.project.deploymentStatus).toBe("missing");
    expect(recordDeployment).toHaveBeenCalledWith(
      "a".repeat(64),
      expect.objectContaining({ endpoint: "https://example-gateway.example.workers.dev" }),
    );
    const recovered = await harness.invoke({ operation: "status" });
    expect(recovered.pendingDeployment).toMatchObject({
      deployment: { versionId: "version-1" },
      projectRevision: "b".repeat(64),
    });
    const tested = await harness.invoke({
      operation: "gateway.test",
    });
    expect(tested.project.deploymentStatus).toBe("ready");
    expect(verifyDeployment).toHaveBeenCalledWith(
      expect.objectContaining({ versionId: "version-1" }),
      "b".repeat(64),
      expect.objectContaining({ remoteVersion: "version-1" }),
    );
  });

  it("binds inspect, rotation, rollback, destroy, and re-verification to the trusted deployment", async () => {
    const harness = ipcHarness();
    const revision = "a".repeat(64);
    let currentProject = lifecycleProjectSnapshot(revision, "ready");
    const invalidateDeployment = vi.fn(async () => {
      currentProject = lifecycleProjectSnapshot(revision, "missing");
      return currentProject;
    });
    const sidecarCalls: Array<{ pathname: string; body: unknown }> = [];
    registerDeveloperAccessController({
      ensureCredentialVault: async () => undefined,
      invalidateDeployment,
      ipcMain: harness.ipcMain,
      loadProject: async () => currentProject,
      openExternal: vi.fn(),
      recordDeployment: vi.fn(),
      redirectUri: "http://127.0.0.1:48973/agentweave/cloudflare/callback",
      requesterWebContents: { id: 7 },
      sidecarRequest: async (pathname, init) => {
        const body = init?.body ? JSON.parse(String(init.body)) as unknown : null;
        sidecarCalls.push({ pathname, body });
        if (pathname.endsWith("/rotate")) {
          return jsonResponse({
            target: gatewayTarget(),
            bindingName: "UPSTREAM_API_KEY",
            configuredRevision: "rotation-2",
            operationId: "09cbab0c-d34c-4f8f-a200-4dd0b195a082",
            completedAtUnixMs: 1_700_000_000_200,
          });
        }
        if (pathname.endsWith("/rollback")) {
          return jsonResponse({
            target: gatewayTarget(),
            previousVersionId: "version-2",
            versionId: "version-1",
            operationId: "d4f6855d-18ac-475c-95f1-4e0710253b50",
            boundary: "worker_version_only",
            completedAtUnixMs: 1_700_000_000_300,
          });
        }
        if (pathname.endsWith("/inspect")) {
          const rolledBack = sidecarCalls.some((call) => call.pathname.endsWith("/rollback"));
          return jsonResponse(deploymentObservation(rolledBack ? "version-1" : "version-2"));
        }
        if (pathname.endsWith("/destroy/plan")) {
          return jsonResponse({
            planHash: "f".repeat(64),
            target: gatewayTarget(),
            resources: ["worker:example-gateway", "secret:UPSTREAM_API_KEY"],
            expiresAtUnixMs: Date.now() + 60_000,
          });
        }
        if (pathname.endsWith("/destroy/apply")) {
          return jsonResponse({
            planHash: "f".repeat(64),
            target: gatewayTarget(),
            deletedResources: ["worker:example-gateway", "secret:UPSTREAM_API_KEY"],
            operationId: "20fedf9f-ef83-4376-9d31-aa4da50a67ae",
            completedAtUnixMs: 1_700_000_000_400,
          });
        }
        if (pathname.endsWith("/status")) {
          return jsonResponse({
            authorization: authorizationStatus("ready"),
            gatewayTemplate: { version: "gateway-v1", sha256: "e".repeat(64) },
            sensitiveBindings: { UPSTREAM_API_KEY: "rotation-2" },
          });
        }
        throw new Error(`Unexpected request: ${pathname}`);
      },
      verifyDeployment: vi.fn(),
    });

    await expect(harness.invoke({
      operation: "gateway.inspect",
      input: { ...gatewayTarget(), workerName: "other-worker" },
    })).rejects.toThrow("verified developer project");
    await expect(harness.invoke({
      operation: "gateway.rotate",
      input: {
        target: gatewayTarget(),
        bindingName: "UNDECLARED_SECRET",
        revision: "rotation-2",
        value: "must-not-reach-sidecar",
        idempotencyKey: "6af52a76-bbe8-4671-8724-bce91356078d",
      },
    })).rejects.toThrow("not managed");
    expect(sidecarCalls).toHaveLength(0);
    const rotated = await harness.invoke({
      operation: "gateway.rotate",
      input: {
        target: gatewayTarget(),
        bindingName: "UPSTREAM_API_KEY",
        revision: "rotation-2",
        value: "new-upstream-secret",
        idempotencyKey: "6af52a76-bbe8-4671-8724-bce91356078d",
        expectedRemoteVersion: "version-1",
      },
    });
    expect(rotated).toMatchObject({
      deployment: { versionId: "version-2" },
      operation: { kind: "rotate", configuredRevision: "rotation-2" },
      project: { deploymentStatus: "missing" },
    });
    expect(JSON.stringify(rotated)).not.toContain("new-upstream-secret");
    expect(invalidateDeployment).toHaveBeenCalledTimes(1);
    const recovered = await harness.invoke({ operation: "status" });
    expect(recovered.pendingDeployment.deployment.versionId).toBe("version-2");

    const rolledBack = await harness.invoke({
      operation: "gateway.rollback",
      input: {
        target: gatewayTarget(),
        restoreVersion: "version-1",
        idempotencyKey: "3f9f339c-c345-47e6-9824-eaff8ad3ff90",
        expectedRemoteVersion: "version-2",
      },
    });
    expect(rolledBack).toMatchObject({
      deployment: { previousVersionId: "version-2", versionId: "version-1" },
      operation: { kind: "rollback", boundary: "worker_version_only" },
    });

    const destroyPlan = await harness.invoke({
      operation: "gateway.destroyPlan",
      input: {
        target: gatewayTarget(),
        idempotencyKey: "52ea7ab5-6d12-457a-9fd7-e370f43714d7",
        expectedRemoteVersion: "version-1",
      },
    });
    expect(destroyPlan.resources).toHaveLength(2);
    const destroyed = await harness.invoke({
      operation: "gateway.destroyApply",
      input: { planHash: "f".repeat(64) },
    });
    expect(destroyed).toMatchObject({
      destroy: { deletedResources: ["worker:example-gateway", "secret:UPSTREAM_API_KEY"] },
      project: { deploymentStatus: "missing" },
    });
    expect(invalidateDeployment).toHaveBeenCalledTimes(3);
  });

  it("rejects another renderer and any sensitive sidecar response", async () => {
    const harness = ipcHarness();
    registerDeveloperAccessController({
      ensureCredentialVault: async () => undefined,
      ipcMain: harness.ipcMain,
      loadProject: vi.fn(),
      openExternal: vi.fn(),
      recordDeployment: vi.fn(),
      redirectUri: "http://127.0.0.1:48972/agentweave/cloudflare/callback",
      requesterWebContents: { id: 7 },
      sidecarRequest: async () => jsonResponse({ tokenHandle: "must-not-cross" }),
      verifyDeployment: vi.fn(),
    });

    await expect(harness.invoke({ operation: "status" }, 8)).rejects.toThrow("restricted");
    await expect(harness.invoke({ operation: "status" })).rejects.toThrow("sensitive boundary");
  });
});

function authorizationStatus(phase: string) {
  return {
    providerId: "cloudflare-workers",
    phase,
    accountId: null,
    expiresAtUnixMs: null,
    publicOauthClientAvailable: true,
  };
}

function gatewayTarget() {
  return {
    accountId: "0123456789abcdef0123456789abcdef",
    deploymentId: "deployment-1",
    workerName: "example-gateway",
    environment: "production",
  };
}

function lifecycleProjectSnapshot(
  revision: string,
  deploymentStatus: "ready" | "missing",
) {
  return {
    appRoot: "/project/app",
    revision,
    desiredHash: `sha256:${"d".repeat(64)}`,
    manifest: { appId: "com.example.app" },
    project: appManagedProject(),
    deploymentStatus,
    deploymentMessage: deploymentStatus === "ready" ? null : "Verification required",
    verifiedDeployment: deploymentStatus === "ready"
      ? {
          target: gatewayTarget(),
          versionId: "version-1",
          endpoint: "https://example-gateway.example.workers.dev/v1",
        }
      : null,
  };
}

function deploymentObservation(version: string) {
  return {
    target: gatewayTarget(),
    reachability: "reachable",
    remoteVersion: version,
    remoteEtag: `etag-${version}`,
    observedDesiredHash: "desired",
    activeArtifactHash: "artifact",
    endpoint: "https://example-gateway.example.workers.dev",
    gatewayProtocolVersion: "1",
    d1MigrationStatus: null,
    workersDevReady: true,
    observedAtUnixMs: 1_700_000_000_250,
  };
}

function appManagedProject() {
  return {
    schemaVersion: 1,
    providers: {
      identity: { id: "agentweave.identity.oidc", version: "0.1.0", publicConfig: {} },
      entitlement: {
        id: "agentweave.entitlements.http",
        version: "0.1.0",
        publicConfig: {},
      },
      gateway: { id: "cloudflare-workers", version: "0.1.0", publicConfig: {} },
    },
    modelAccess: {
      configurationPolicy: "app_managed",
      profile: {
        providerId: "cloudflare-gateway",
        endpointType: "responses",
        baseUrl: "https://gateway.example.test/v1",
        modelName: "approved-model",
        authentication: "user_identity",
        headers: {},
      },
    },
    deployment: {
      provider: "cloudflare",
      cloudflare: {
        accountId: "0123456789abcdef0123456789abcdef",
        workerName: "example-gateway",
        environment: "production",
      },
    },
  };
}

function jsonResponse(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function ipcHarness() {
  let handler: ((event: { sender: { id: number } }, value: unknown) => unknown) | undefined;
  return {
    ipcMain: {
      handle: (channel: string, candidate: typeof handler) => {
        if (channel === DEVELOPER_ACCESS_REQUEST_CHANNEL) handler = candidate;
      },
      removeHandler: () => {
        handler = undefined;
      },
    },
    invoke: async (value: unknown, sender = 7): Promise<any> => {
      if (!handler) throw new Error("Missing developer access handler");
      return handler({ sender: { id: sender } }, value);
    },
  };
}

function freePort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const server = createServer();
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      if (!address || typeof address === "string") {
        server.close();
        reject(new Error("Could not allocate callback port"));
        return;
      }
      const port = address.port;
      server.close((error) => error ? reject(error) : resolve(port));
    });
  });
}
