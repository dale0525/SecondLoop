import type { DeveloperCreemWebhookBootstrapReceipt } from "../shared/developerAccess";
import type { DeveloperProjectSnapshot } from "../shared/developerProject";

export type CreemProduct = Readonly<{
  id: string;
  name: string;
  description: string;
  environment: "test" | "production";
  priceMinor: number;
  currency: string;
  billingType: string;
  billingPeriod: string;
  active: boolean;
}>;

export type CreemProductDiscovery = Readonly<{
  environment: "test" | "production";
  configuredRevision: string;
  products: readonly CreemProduct[];
}>;

export async function bootstrapCreemWebhook(
  project: DeveloperProjectSnapshot,
): Promise<DeveloperCreemWebhookBootstrapReceipt> {
  return parseBootstrap(await request("commerce.creem.bootstrap", {
    expectedProjectRevision: project.revision,
    idempotencyKey: crypto.randomUUID(),
  }));
}

export async function discoverCreemProducts(input: {
  environment: "test" | "production";
  apiKey: string;
}): Promise<CreemProductDiscovery> {
  return parseProducts(await request("commerce.creem.products", {
    environment: input.environment,
    apiKey: input.apiKey,
    revision: `ui-${crypto.randomUUID()}`,
  }));
}

export async function openCreemWebhookDashboard(): Promise<void> {
  const response = record(await request("commerce.creem.dashboard"));
  if (response.opened !== true) throw new Error("Creem Dashboard could not be opened");
}

async function request(operation: "commerce.creem.bootstrap" | "commerce.creem.dashboard" | "commerce.creem.products", input?: unknown) {
  const api = window.agentWeave?.developerAccess;
  if (!api) throw new Error("Developer access API is unavailable");
  return api.request(operation, input);
}

function parseBootstrap(value: unknown): DeveloperCreemWebhookBootstrapReceipt {
  const receipt = record(value);
  const state = text(receipt.state);
  if (!new Set(["bootstrap_ready", "existing_entitlement", "commerce_active"]).has(state)) {
    throw new Error("Creem webhook bootstrap response is invalid");
  }
  const endpoint = httpsUrl(receipt.endpoint);
  const webhookUrl = httpsUrl(receipt.webhookUrl);
  const expectedWebhook = new URL(endpoint);
  expectedWebhook.pathname = "/agentweave/commerce/v1/webhooks/creem";
  expectedWebhook.search = "";
  expectedWebhook.hash = "";
  if (expectedWebhook.toString() !== webhookUrl) {
    throw new Error("Creem webhook URL is not bound to the Entitlement Worker");
  }
  const target = record(receipt.target);
  return Object.freeze({
    state: state as DeveloperCreemWebhookBootstrapReceipt["state"],
    providerId: text(receipt.providerId),
    providerVersion: text(receipt.providerVersion),
    target: Object.freeze({
      accountId: text(target.accountId),
      deploymentId: text(target.deploymentId),
      workerName: text(target.workerName),
      ...(target.environment === undefined
        ? {}
        : { environment: text(target.environment) }),
    }),
    versionId: text(receipt.versionId),
    endpoint,
    webhookUrl,
    operationId: receipt.operationId === null ? null : text(receipt.operationId),
    completedAtUnixMs: positiveInteger(receipt.completedAtUnixMs),
  });
}

function parseProducts(value: unknown): CreemProductDiscovery {
  const receipt = record(value);
  if (!Array.isArray(receipt.products)
    || (receipt.environment !== "test" && receipt.environment !== "production")) {
    throw new Error("Creem product response is invalid");
  }
  return Object.freeze({
    environment: receipt.environment,
    configuredRevision: text(receipt.configuredRevision),
    products: Object.freeze(receipt.products.map((candidate) => {
      const product = record(candidate);
      return Object.freeze({
        id: text(product.id),
        name: text(product.name),
        description: typeof product.description === "string" ? product.description : "",
        environment: product.environment as "test" | "production",
        priceMinor: integer(product.priceMinor),
        currency: text(product.currency),
        billingType: text(product.billingType),
        billingPeriod: text(product.billingPeriod),
        active: product.active === true,
      });
    })),
  });
}

function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Developer Commerce response is invalid");
  }
  return value as Record<string, unknown>;
}

function text(value: unknown): string {
  if (typeof value !== "string" || !value || value.length > 8 * 1024 || /[\r\n\0]/.test(value)) {
    throw new Error("Developer Commerce text is invalid");
  }
  return value;
}

function httpsUrl(value: unknown): string {
  const result = text(value);
  const url = new URL(result);
  if (url.protocol !== "https:" || url.username || url.password
    || !url.hostname.endsWith(".workers.dev")) {
    throw new Error("Developer Commerce URL is invalid");
  }
  return result;
}

function integer(value: unknown): number {
  if (!Number.isSafeInteger(value) || Number(value) < 0) {
    throw new Error("Developer Commerce integer is invalid");
  }
  return Number(value);
}

function positiveInteger(value: unknown): number {
  const result = integer(value);
  if (result === 0) throw new Error("Developer Commerce integer is invalid");
  return result;
}
