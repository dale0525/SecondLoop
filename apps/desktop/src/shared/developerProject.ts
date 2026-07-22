export const DEVELOPER_PROJECT_LOAD_CHANNEL = "agentweave:developer-project:load";
export const DEVELOPER_PROJECT_SAVE_CHANNEL = "agentweave:developer-project:save";
export const DEVELOPER_PROJECT_PACKAGE_CHANNEL = "agentweave:developer-project:package";
export const DEVELOPER_PROJECT_SHOW_OUTPUT_CHANNEL = "agentweave:developer-project:show-output";

export type DeveloperDeploymentStatus = "not_required" | "missing" | "ready" | "stale";

export type DeveloperVerifiedDeployment = Readonly<{
  target: Readonly<{
    accountId: string;
    deploymentId: string;
    workerName: string;
    environment?: string;
  }>;
  versionId: string;
  endpoint: string;
}>;

export type DeveloperVerifiedAccessBundle = Readonly<{
  bundleRevision: string;
  projectionSecretRevision: string;
  rollbackTarget: null | Readonly<{
    gatewayVersionId: string;
    entitlementVersionId: string;
  }>;
  gateway: DeveloperVerifiedDeployment;
  entitlementPolicy: DeveloperVerifiedDeployment;
  commerce: null | Readonly<{
    providerId: string;
    providerVersion: string;
    environment: "test" | "production";
    databaseId: string;
    migrationHash: string;
    capabilities: ReadonlyArray<string>;
    webhookVerifiedAtUnixMs: number;
    portalVerifiedAtUnixMs: number;
  }>;
  testedAtUnixMs: number;
}>;

export type DeveloperProjectSnapshot = Readonly<{
  appRoot: string;
  revision: string;
  desiredHash: string;
  manifest: Record<string, unknown>;
  project: Record<string, unknown>;
  deploymentStatus: DeveloperDeploymentStatus;
  deploymentMessage: string | null;
  verifiedDeployment?: DeveloperVerifiedDeployment | null;
  verifiedBundle?: DeveloperVerifiedAccessBundle | null;
}>;

export type DeveloperProjectSaveRequest = Readonly<{
  expectedRevision: string;
  project: unknown;
}>;

export type DeveloperPackageReceipt = Readonly<{
  outputPath: string;
  summary: string;
}>;
