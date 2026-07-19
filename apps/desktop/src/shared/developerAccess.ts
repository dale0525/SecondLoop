export const DEVELOPER_ACCESS_REQUEST_CHANNEL = "agentweave:developer-access:request";

export type DeveloperAccessOperation =
  | "status"
  | "cloudflare.connect"
  | "cloudflare.cancel"
  | "cloudflare.disconnect"
  | "cloudflare.accounts"
  | "cloudflare.selectAccount"
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
