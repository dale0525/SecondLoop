// @vitest-environment node

import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";

import { afterEach, describe, expect, it, vi } from "vitest";

import {
  invalidateDeveloperGatewayDeployment,
  recordDeveloperGatewayDeployment,
  registerDeveloperProjectController,
  verifyDeveloperGatewayDeployment,
} from "../src/main/developerProjectController";
import {
  DEVELOPER_PROJECT_LOAD_CHANNEL,
  DEVELOPER_PROJECT_PACKAGE_CHANNEL,
  DEVELOPER_PROJECT_SAVE_CHANNEL,
  DEVELOPER_PROJECT_SHOW_OUTPUT_CHANNEL,
} from "../src/shared/developerProject";

const roots: string[] = [];

describe("developer project controller", () => {
  afterEach(async () => {
    await Promise.all(roots.splice(0).map((root) => rm(root, { force: true, recursive: true })));
  });

  it("saves only the validated public projection with optimistic concurrency", async () => {
    const root = await fixtureRoot();
    const harness = ipcHarness();
    const packageApp = vi.fn();
    const refreshRuntime = vi.fn(async () => undefined);
    registerDeveloperProjectController({
      appRoot: root,
      ipcMain: harness.ipcMain,
      packageApp,
      refreshRuntime,
      requesterWebContents: { id: 7 },
      showItemInFolder: vi.fn(),
    });
    const initial = await harness.invoke(DEVELOPER_PROJECT_LOAD_CHANNEL, undefined);
    const project = appManagedProject();

    const saved = await harness.invoke(DEVELOPER_PROJECT_SAVE_CHANNEL, {
      expectedRevision: initial.revision,
      project,
    });

    expect(saved.deploymentStatus).toBe("missing");
    expect(refreshRuntime).toHaveBeenCalledTimes(1);
    expect(saved.manifest.modelAccess.configurationPolicy).toBe("app_managed");
    expect(saved.manifest.identity.provider.id).toBe("agentweave.identity.oidc");
    expect(saved.manifest.entitlements.provider.id).toBe("agentweave.entitlements.static");
    const diskManifest = JSON.parse(await readFile(path.join(root, "agent-app.json"), "utf8"));
    expect(diskManifest.modelAccess).toEqual(project.modelAccess);
    await expect(harness.invoke(DEVELOPER_PROJECT_SAVE_CHANNEL, {
      expectedRevision: initial.revision,
      project,
    })).rejects.toThrow("changed on disk");
    await expect(harness.invoke(DEVELOPER_PROJECT_PACKAGE_CHANNEL, undefined))
      .rejects.toThrow("must be deployed");
    expect(packageApp).not.toHaveBeenCalled();
  });

  it("packages a ready BYOK project and reveals only the verified output", async () => {
    const root = await fixtureRoot();
    const output = path.join(path.dirname(root), "dist", "Example.app");
    await mkdir(output, { recursive: true });
    const harness = ipcHarness();
    const showItemInFolder = vi.fn();
    registerDeveloperProjectController({
      appRoot: root,
      ipcMain: harness.ipcMain,
      packageApp: vi.fn(async () => ({ outputPath: output, summary: "Packaged Example" })),
      requesterWebContents: { id: 7 },
      showItemInFolder,
    });

    const receipt = await harness.invoke(DEVELOPER_PROJECT_PACKAGE_CHANNEL, undefined);
    await harness.invoke(DEVELOPER_PROJECT_SHOW_OUTPUT_CHANNEL, undefined);

    expect(receipt.outputPath).toBe(await import("node:fs/promises").then(({ realpath }) => realpath(output)));
    expect(showItemInFolder).toHaveBeenCalledWith(receipt.outputPath);
  });

  it("records an endpoint, then creates a public deployment lock only after verification", async () => {
    const root = await fixtureRoot();
    const harness = ipcHarness();
    registerDeveloperProjectController({
      appRoot: root,
      ipcMain: harness.ipcMain,
      packageApp: vi.fn(),
      requesterWebContents: { id: 7 },
      showItemInFolder: vi.fn(),
    });
    const initial = await harness.invoke(DEVELOPER_PROJECT_LOAD_CHANNEL, undefined);
    const saved = await harness.invoke(DEVELOPER_PROJECT_SAVE_CHANNEL, {
      expectedRevision: initial.revision,
      project: appManagedProject(),
    });

    const deployment = {
      providerId: "cloudflare-workers",
      providerVersion: "0.1.0",
      target: {
        accountId: "0123456789abcdef0123456789abcdef",
        deploymentId: "deployment-1",
        workerName: "example-agent-gateway",
        environment: "production",
      },
      outcome: "applied" as const,
      previousVersionId: null,
      versionId: "version-1",
      endpoint: "https://example-agent-gateway.example.workers.dev",
      operationId: "4f290eb3-8712-4f7d-bde8-0a98aa95e33b",
      completedAtUnixMs: 1_700_000_000_000,
    };
    const deployed = await recordDeveloperGatewayDeployment({
      appRoot: root,
      expectedRevision: saved.revision,
      receipt: deployment,
    });

    expect(deployed.deploymentStatus).toBe("missing");
    expect((deployed.project.modelAccess as any).profile.baseUrl)
      .toBe("https://example-agent-gateway.example.workers.dev/v1");
    await expect(readFile(path.join(root, ".agentweave", "deployment.lock"), "utf8"))
      .rejects.toMatchObject({ code: "ENOENT" });
    const verified = await verifyDeveloperGatewayDeployment({
      appRoot: root,
      deployment,
      expectedRevision: deployed.revision,
      test: {
        target: {
          workerName: "example-agent-gateway",
          environment: "production",
          deploymentId: "deployment-1",
          accountId: "0123456789abcdef0123456789abcdef",
        },
        protocolVersion: "1",
        remoteVersion: "version-1",
        testedAtUnixMs: 1_700_000_000_100,
      },
    });

    expect(verified.deploymentStatus).toBe("ready");
    expect(verified.verifiedDeployment).toEqual({
      target: deployment.target,
      versionId: "version-1",
      endpoint: "https://example-agent-gateway.example.workers.dev/v1",
    });
    const lock = JSON.parse(
      await readFile(path.join(root, ".agentweave", "deployment.lock"), "utf8"),
    );
    expect(JSON.stringify(lock)).not.toMatch(/token|secret|credential|awdev/i);
    const invalidated = await invalidateDeveloperGatewayDeployment({
      appRoot: root,
      expectedRevision: verified.revision,
    });
    expect(invalidated.deploymentStatus).toBe("missing");
    expect(invalidated.verifiedDeployment).toBeNull();
    await expect(recordDeveloperGatewayDeployment({
      appRoot: root,
      expectedRevision: saved.revision,
      receipt: { ...deployment, outcome: "already_converged" },
    })).rejects.toThrow("changed after");
  });

  it("rejects callers from another renderer", async () => {
    const root = await fixtureRoot();
    const harness = ipcHarness();
    registerDeveloperProjectController({
      appRoot: root,
      ipcMain: harness.ipcMain,
      packageApp: vi.fn(),
      requesterWebContents: { id: 7 },
      showItemInFolder: vi.fn(),
    });

    await expect(harness.invoke(DEVELOPER_PROJECT_LOAD_CHANNEL, undefined, 8))
      .rejects.toThrow("restricted");
  });
});

async function fixtureRoot(): Promise<string> {
  const parent = await mkdtemp(path.join(tmpdir(), "agentweave-project-controller-"));
  roots.push(parent);
  const root = path.join(parent, "app");
  await mkdir(root, { recursive: true });
  await writeFile(path.join(root, "agent-app.json"), JSON.stringify({
    schemaVersion: 2,
    appId: "com.example.app",
    modelAccess: { configurationPolicy: "user_configurable" },
    identity: { mode: "local_single_user" },
    entitlements: { mode: "disabled" },
  }));
  await writeFile(path.join(root, "agentweave-project.json"), JSON.stringify({
    schemaVersion: 1,
    providers: { identity: null, entitlement: null, gateway: null },
    modelAccess: { configurationPolicy: "user_configurable" },
    deployment: null,
  }));
  return root;
}

function appManagedProject() {
  return {
    schemaVersion: 1,
    providers: {
      identity: {
        id: "agentweave.identity.oidc",
        version: "0.1.0",
        publicConfig: {
          issuer: "https://identity.example.test",
          clientId: "public-client",
          audience: "https://gateway.example.test",
        },
      },
      entitlement: {
        id: "agentweave.entitlements.static",
        version: "0.1.0",
        publicConfig: { allow: true, quota: { requests: 1000 } },
      },
      gateway: {
        id: "cloudflare-workers",
        version: "0.1.0",
        publicConfig: {},
      },
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
        workerName: "example-agent-gateway",
        environment: "production",
      },
    },
  };
}

function ipcHarness() {
  const handlers = new Map<string, (event: { sender: { id: number } }, value: unknown) => unknown>();
  return {
    ipcMain: {
      handle: (channel: string, handler: (event: { sender: { id: number } }, value: unknown) => unknown) => {
        handlers.set(channel, handler);
      },
      removeHandler: (channel: string) => handlers.delete(channel),
    },
    invoke: async (channel: string, value: unknown, sender = 7) => {
      const handler = handlers.get(channel);
      if (!handler) throw new Error(`Missing IPC handler: ${channel}`);
      return handler({ sender: { id: sender } }, value) as Promise<any>;
    },
  };
}
