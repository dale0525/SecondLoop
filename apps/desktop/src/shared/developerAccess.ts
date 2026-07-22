export const DEVELOPER_ACCESS_REQUEST_CHANNEL = "agentweave:developer-access:request";

export type DeveloperAccessOperation =
  | "status"
  | "cloudflare.connect"
  | "cloudflare.cancel"
  | "cloudflare.disconnect"
  | "cloudflare.accounts"
  | "cloudflare.selectAccount"
  | "firebase.connect"
  | "firebase.cancel"
  | "firebase.disconnect"
  | "firebase.projects"
  | "firebase.configure"
  | "access.plan"
  | "access.apply"
  | "access.test"
  | "access.inspect"
  | "access.rotate"
  | "access.rollback"
  | "access.destroyPlan"
  | "access.destroyApply"
  | "commerce.creem.products"
  | "commerce.creem.dashboard"
  | "gateway.plan"
  | "gateway.apply"
  | "gateway.inspect"
  | "gateway.test"
  | "gateway.rotate"
  | "gateway.rollback"
  | "gateway.destroyPlan"
  | "gateway.destroyApply";

export type DeveloperAccessRequest = Readonly<{
  operation: DeveloperAccessOperation;
  input?: unknown;
}>;

export type DeveloperGatewayDeploymentReceipt = Readonly<{
  providerId: string;
  providerVersion: string;
  target: Readonly<{
    accountId: string;
    deploymentId: string;
    workerName: string;
    environment?: string;
  }>;
  outcome: "applied" | "already_converged" | "recovered_after_uncertain_write";
  previousVersionId: string | null;
  versionId: string;
  endpoint: string;
  operationId: string;
  completedAtUnixMs: number;
}>;

export type DeveloperDeploymentProjectUpdate = Readonly<{
  deployment: DeveloperGatewayDeploymentReceipt;
  project: import("./developerProject").DeveloperProjectSnapshot;
}>;

export type DeveloperPendingDeployment = Readonly<{
  deployment: DeveloperGatewayDeploymentReceipt;
  projectRevision: string;
}>;

export type DeveloperGatewayTestReceipt = Readonly<{
  target: DeveloperGatewayDeploymentReceipt["target"];
  protocolVersion: string;
  remoteVersion: string;
  testedAtUnixMs: number;
}>;

export type DeveloperGatewayTestProjectUpdate = Readonly<{
  test: DeveloperGatewayTestReceipt;
  project: import("./developerProject").DeveloperProjectSnapshot;
}>;

export type DeveloperAccessBundleResourceStatus =
  | "applied"
  | "already_converged"
  | "failed"
  | "uncertain"
  | "blocked";

export type DeveloperAccessBundleResourceReceipt = Readonly<{
  resourceId: string;
  status: DeveloperAccessBundleResourceStatus;
  target: DeveloperGatewayDeploymentReceipt["target"];
  versionId: string | null;
  previousVersionId: string | null;
  endpoint: string | null;
  errorCode: string | null;
  safeMessage: string | null;
}>;

export type DeveloperAccessBundleReceipt = Readonly<{
  schemaVersion: number;
  providerId: string;
  providerVersion: string;
  bundleId: string;
  planHash: string;
  operationId: string;
  outcome:
    | "succeeded"
    | "failed_before_activation"
    | "entitlement_ready_gateway_failed"
    | "gateway_active_verification_failed"
    | "uncertain_remote_state";
  resources: Readonly<Record<string, DeveloperAccessBundleResourceReceipt>>;
  completedAtUnixMs: number;
}>;

export type DeveloperAccessBundleProjectUpdate = Readonly<{
  bundle: DeveloperAccessBundleReceipt;
  project: import("./developerProject").DeveloperProjectSnapshot;
}>;

export type DeveloperAccessBundlePlan = Readonly<{
  schemaVersion: number;
  bundleId: string;
  desiredHash: string;
  planHash: string;
  resources: ReadonlyArray<Readonly<{
    resourceId: string;
    kind: string;
    purpose: string;
    dependencies: ReadonlyArray<string>;
    ownership: "exclusive" | "shared";
    target: DeveloperGatewayDeploymentReceipt["target"];
    operations: ReadonlyArray<Readonly<{
      kind: string;
      resource: string;
      destructive: boolean;
    }>>;
    drift: unknown | null;
  }>>;
  expiresAtUnixMs: number;
}>;

export type DeveloperAccessCommerceVerification = Readonly<{
  databaseId: string;
  migrationHash: string;
  capabilities: ReadonlyArray<string>;
  webhookVerifiedAtUnixMs: number | null;
  portalVerifiedAtUnixMs: number | null;
}>;

export type DeveloperAccessBundleTestReceipt = Readonly<{
  gateway: DeveloperGatewayTestReceipt;
  entitlementPolicy: DeveloperGatewayTestReceipt;
  commerce: DeveloperAccessCommerceVerification | null;
  projectionSecretRevision: string;
  testedAtUnixMs: number;
}>;

export type DeveloperAccessBundleVerificationUpdate = Readonly<{
  test: DeveloperAccessBundleTestReceipt;
  project: import("./developerProject").DeveloperProjectSnapshot;
}>;

export type DeveloperPendingAccessBundle = Readonly<{
  bundle: DeveloperAccessBundleReceipt;
  projectRevision: string;
}>;

export type DeveloperAccessBundleMutationOutcome =
  | "succeeded"
  | "failed_before_activation"
  | "entitlement_ready_gateway_failed"
  | "verification_failed"
  | "partial"
  | "uncertain_remote_state";

export type DeveloperAccessBundleLifecycleResourceReceipt = Readonly<{
  resourceId: string;
  target: DeveloperGatewayDeploymentReceipt["target"];
  status: DeveloperAccessBundleResourceStatus;
  versionId: string | null;
  previousVersionId: string | null;
  configuredRevision: string | null;
  rollbackBoundary: unknown | null;
  errorCode: string | null;
  safeMessage: string | null;
}>;

export type DeveloperAccessBundleMutationReceipt = Readonly<{
  schemaVersion: number;
  operationId: string;
  outcome: DeveloperAccessBundleMutationOutcome;
  configuredRevision?: string;
  resources: Readonly<Record<string, DeveloperAccessBundleLifecycleResourceReceipt>>;
  verification: DeveloperAccessBundleTestReceipt | null;
  completedAtUnixMs: number;
}>;

export type DeveloperAccessBundleInspectReceipt = Readonly<{
  schemaVersion: number;
  bundleId: string;
  outcome: "ready" | "partial" | "unavailable";
  resources: Readonly<Record<string, Readonly<{
    resourceId: string;
    observation: null | Readonly<{
      target: DeveloperGatewayDeploymentReceipt["target"];
      reachability: "reachable" | "missing" | "unauthorized" | "unreachable";
      remoteVersion: string | null;
      remoteEtag: string | null;
      observedDesiredHash: string | null;
      activeArtifactHash: string | null;
      endpoint: string | null;
      gatewayProtocolVersion: string | null;
      d1MigrationStatus: string | null;
      workersDevReady: boolean | null;
      observedAtUnixMs: number;
    }>;
    errorCode: string | null;
    safeMessage: string | null;
  }>>>;
  inspectedAtUnixMs: number;
}>;

export type DeveloperAccessBundleDestroyPlan = Readonly<{
  schemaVersion: number;
  planHash: string;
  bundleId: string;
  resources: ReadonlyArray<Readonly<{
    resourceId: string;
    target: DeveloperGatewayDeploymentReceipt["target"];
    resources: ReadonlyArray<string>;
    ownership: "exclusive" | "shared";
    deleteRequiresConfirmation: boolean;
  }>>;
  commerceDataLossRequiresConfirmation: boolean;
  expiresAtUnixMs: number;
}>;

export type DeveloperAccessBundleDestroyReceipt = Readonly<{
  schemaVersion: number;
  planHash: string;
  operationId: string;
  outcome: DeveloperAccessBundleMutationOutcome;
  resources: DeveloperAccessBundleMutationReceipt["resources"];
  completedAtUnixMs: number;
}>;
