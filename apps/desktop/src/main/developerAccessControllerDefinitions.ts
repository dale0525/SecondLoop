import type {
  DeveloperAccessOperation,
  DeveloperGatewayDeploymentReceipt,
} from "../shared/developerAccess";

export const MAX_RESPONSE_BYTES = 1024 * 1024;
export const MAX_REQUEST_BYTES = 2 * 1024 * 1024;
export const PLAN_HASH = /^[a-f0-9]{64}$/;
export const PROJECT_REVISION = /^[a-f0-9]{64}$/;
export const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export type IpcEvent = { sender: { id: number } };
export type IpcMainLike = {
  handle(
    channel: string,
    handler: (event: IpcEvent, value: unknown) => unknown,
  ): void;
  removeHandler(channel: string): void;
};
export type RequestDescription = Readonly<{
  body?: unknown;
  method: "DELETE" | "GET" | "POST";
  pathname: string;
  planRevision?: string;
}>;
export type PendingDeployment = Readonly<{
  deployment: DeveloperGatewayDeploymentReceipt;
  projectRevision: string;
}>;

export const DEVELOPER_ACCESS_OPERATIONS = new Set<DeveloperAccessOperation>([
  "status",
  "cloudflare.connect",
  "cloudflare.cancel",
  "cloudflare.disconnect",
  "cloudflare.accounts",
  "cloudflare.selectAccount",
  "firebase.connect",
  "firebase.cancel",
  "firebase.disconnect",
  "firebase.projects",
  "firebase.configure",
  "access.plan",
  "access.apply",
  "access.test",
  "access.inspect",
  "access.rotate",
  "access.rollback",
  "access.destroyPlan",
  "access.destroyApply",
  "commerce.creem.bootstrap",
  "commerce.creem.products",
  "commerce.creem.dashboard",
  "gateway.plan",
  "gateway.apply",
  "gateway.inspect",
  "gateway.test",
  "gateway.rotate",
  "gateway.rollback",
  "gateway.destroyPlan",
  "gateway.destroyApply",
]);

export const LIFECYCLE_TARGET_OPERATIONS = new Set<DeveloperAccessOperation>([
  "gateway.inspect",
  "gateway.rotate",
  "gateway.rollback",
  "gateway.destroyPlan",
]);
