// @vitest-environment node

import { describe, expect, it, vi } from "vitest";

import { createDeveloperAccessBundleLifecycleController } from "../src/main/developerAccessBundleLifecycleController";
import type { DeveloperProjectSnapshot } from "../src/shared/developerProject";

describe("managed access bundle lifecycle controller", () => {
  it("derives inspect targets from the verified lock and never accepts Renderer targets", async () => {
    const calls: Array<{ pathname: string; body: unknown }> = [];
    const controller = createDeveloperAccessBundleLifecycleController({
      loadProject: async () => snapshot(),
      requestJson: async ({ pathname, body }) => {
        calls.push({ pathname, body });
        return inspectReceipt();
      },
    });

    const result = await controller.handle({ operation: "access.inspect" });

    expect(result).toMatchObject({ outcome: "ready" });
    expect(calls).toEqual([{
      pathname: "/dev/control/access/inspect",
      body: {
        gateway: gatewayTarget(),
        entitlementPolicy: entitlementTarget(),
      },
    }]);
    await expect(controller.handle({
      operation: "access.inspect",
      input: { gateway: { workerName: "attacker-worker" } },
    })).rejects.toThrow("does not accept input");
  });

  it("only rolls back to the previous verified Worker pair", async () => {
    const requestJson = vi.fn(async () => mutationReceipt(false));
    const record = vi.fn(async () => snapshot());
    const controller = createDeveloperAccessBundleLifecycleController({
      callbacks: { invalidate: vi.fn(), record },
      loadProject: async () => snapshot(),
      requestJson,
    });

    await expect(controller.handle({
      operation: "access.rollback",
      input: { gatewayVersionId: "arbitrary", entitlementVersionId: "entitlement-previous" },
    })).rejects.toThrow("previous verified bundle");

    const result = await controller.handle({
      operation: "access.rollback",
      input: {
        gatewayVersionId: "gateway-previous",
        entitlementVersionId: "entitlement-previous",
      },
    });
    expect(result).toMatchObject({ mutation: { outcome: "succeeded" } });
    expect(requestJson).toHaveBeenCalledWith(expect.objectContaining({
      pathname: "/dev/control/access/rollback",
      body: expect.objectContaining({
        restoreGatewayVersion: "gateway-previous",
        restoreEntitlementVersion: "entitlement-previous",
      }),
    }));
    expect(record).toHaveBeenCalledTimes(1);
  });

  it("requires the immutable Commerce projection confirmation during destroy", async () => {
    const current = snapshot();
    const invalidate = vi.fn(async () => ({ ...current, deploymentStatus: "missing" as const }));
    const requestJson = vi.fn(async ({ pathname }) => {
      if (pathname.endsWith("/plan")) return destroyPlan();
      if (pathname.endsWith("/apply")) return destroyReceipt();
      throw new Error(`Unexpected request ${pathname}`);
    });
    const controller = createDeveloperAccessBundleLifecycleController({
      callbacks: { invalidate, record: vi.fn() },
      loadProject: async () => current,
      requestJson,
    });
    const plan = await controller.handle({ operation: "access.destroyPlan" }) as { planHash: string };

    await expect(controller.handle({
      operation: "access.destroyApply",
      input: { planHash: plan.planHash, confirmCommerceProjectionRebuild: false },
    })).rejects.toThrow("confirmation is required");
    await expect(controller.handle({
      operation: "access.destroyApply",
      input: { planHash: plan.planHash, confirmCommerceProjectionRebuild: true },
    })).resolves.toMatchObject({ destroy: { outcome: "succeeded" } });
    expect(requestJson).toHaveBeenLastCalledWith(expect.objectContaining({
      body: {
        planHash: "d".repeat(64),
        confirmCommerceProjectionRebuild: true,
      },
    }));
    expect(invalidate).toHaveBeenCalledTimes(1);
  });

  it("rejects a lifecycle response that contains secret material", async () => {
    const controller = createDeveloperAccessBundleLifecycleController({
      loadProject: async () => snapshot(),
      requestJson: async () => ({ ...inspectReceipt(), apiKey: "must-not-cross" }),
    });
    await expect(controller.handle({ operation: "access.inspect" }))
      .rejects.toThrow("prohibited data");
  });
});

function snapshot(): DeveloperProjectSnapshot {
  return {
    appRoot: "/project/app",
    revision: "a".repeat(64),
    desiredHash: `sha256:${"b".repeat(64)}`,
    manifest: {},
    project: {},
    deploymentStatus: "ready",
    deploymentMessage: null,
    verifiedBundle: {
      bundleRevision: `sha256:${"c".repeat(64)}`,
      projectionSecretRevision: "auto-revision",
      rollbackTarget: {
        gatewayVersionId: "gateway-previous",
        entitlementVersionId: "entitlement-previous",
      },
      gateway: {
        target: gatewayTarget(),
        versionId: "gateway-current",
        endpoint: "https://gateway.example.workers.dev/v1",
      },
      entitlementPolicy: {
        target: entitlementTarget(),
        versionId: "entitlement-current",
        endpoint: "https://entitlement.example.workers.dev",
      },
      commerce: null,
      testedAtUnixMs: 1_800_000_000_000,
    },
  };
}

function gatewayTarget() {
  return {
    accountId: "0123456789abcdef0123456789abcdef",
    deploymentId: "production",
    workerName: "example-gateway",
    environment: "production",
  };
}

function entitlementTarget() {
  return {
    accountId: "0123456789abcdef0123456789abcdef",
    deploymentId: "production",
    workerName: "example-gateway-entitlements",
    environment: "production",
  };
}

function inspectReceipt() {
  const observation = (target: ReturnType<typeof gatewayTarget>, version: string) => ({
    target,
    reachability: "reachable",
    remoteVersion: version,
    remoteEtag: "etag",
    observedDesiredHash: "f".repeat(64),
    activeArtifactHash: "e".repeat(64),
    endpoint: `https://${target.workerName}.example.workers.dev`,
    gatewayProtocolVersion: "2",
    d1MigrationStatus: "in_sync",
    workersDevReady: true,
    observedAtUnixMs: 1_800_000_000_000,
  });
  return {
    schemaVersion: 1,
    bundleId: "access-production",
    outcome: "ready",
    resources: {
      "model-gateway": {
        resourceId: "model-gateway",
        observation: observation(gatewayTarget(), "gateway-current"),
        errorCode: null,
        safeMessage: null,
      },
      "entitlement-policy": {
        resourceId: "entitlement-policy",
        observation: observation(entitlementTarget(), "entitlement-current"),
        errorCode: null,
        safeMessage: null,
      },
    },
    inspectedAtUnixMs: 1_800_000_000_000,
  };
}

function mutationReceipt(rotation: boolean) {
  return {
    schemaVersion: 1,
    operationId: "4f290eb3-8712-4f7d-bde8-0a98aa95e33b",
    outcome: "succeeded",
    ...(rotation ? { configuredRevision: "auto-new" } : {}),
    resources: {
      "model-gateway": lifecycleResource("model-gateway", gatewayTarget(), "gateway-previous"),
      "entitlement-policy": lifecycleResource(
        "entitlement-policy",
        entitlementTarget(),
        "entitlement-previous",
      ),
    },
    verification: bundleVerification(),
    completedAtUnixMs: 1_800_000_000_100,
  };
}

function lifecycleResource(resourceId: string, target: object, versionId: string | null) {
  return {
    resourceId,
    target,
    status: "applied",
    versionId,
    previousVersionId: null,
    configuredRevision: null,
    rollbackBoundary: null,
    errorCode: null,
    safeMessage: null,
  };
}

function bundleVerification() {
  const test = (target: object, remoteVersion: string) => ({
    target,
    protocolVersion: "2",
    remoteVersion,
    testedAtUnixMs: 1_800_000_000_100,
  });
  return {
    gateway: test(gatewayTarget(), "gateway-previous"),
    entitlementPolicy: test(entitlementTarget(), "entitlement-previous"),
    commerce: null,
    projectionSecretRevision: "auto-revision",
    testedAtUnixMs: 1_800_000_000_100,
  };
}

function destroyPlan() {
  return {
    schemaVersion: 1,
    planHash: "d".repeat(64),
    bundleId: "access-production",
    resources: [{
      resourceId: "model-gateway",
      target: gatewayTarget(),
      resources: ["worker-script:example-gateway"],
      ownership: "exclusive",
      deleteRequiresConfirmation: false,
    }, {
      resourceId: "entitlement-policy",
      target: entitlementTarget(),
      resources: ["worker-script:example-gateway-entitlements", "d1-database:commerce"],
      ownership: "exclusive",
      deleteRequiresConfirmation: true,
    }],
    commerceDataLossRequiresConfirmation: true,
    expiresAtUnixMs: 1_900_000_000_000,
  };
}

function destroyReceipt() {
  return {
    schemaVersion: 1,
    planHash: "d".repeat(64),
    operationId: "4f290eb3-8712-4f7d-bde8-0a98aa95e33b",
    outcome: "succeeded",
    resources: {
      "model-gateway": lifecycleResource("model-gateway", gatewayTarget(), null),
      "entitlement-policy": lifecycleResource(
        "entitlement-policy",
        entitlementTarget(),
        null,
      ),
    },
    completedAtUnixMs: 1_800_000_000_200,
  };
}
