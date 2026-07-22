export const COMMERCE_STATUS_CHANNEL = "agentweave:commerce:status";
export const COMMERCE_CHECKOUT_CHANNEL = "agentweave:commerce:checkout";
export const COMMERCE_PORTAL_CHANNEL = "agentweave:commerce:customer-portal";

export type BillingPlan = Readonly<{
  id: string;
  displayName: string;
  allowedModels: readonly string[];
  limits: Readonly<{
    maxRequests: number;
    maxUnits: number;
    maxConcurrency: number;
  }>;
}>;

export type BillingSubscription = Readonly<{
  status: string;
  paidThrough: number | null;
  periodStart: number | null;
  periodEnd: number | null;
  revoked: boolean;
}>;

export type BillingStatus = Readonly<{
  mode: "uniform_bounded" | "commerce_provider";
  plan: BillingPlan | null;
  subscription: BillingSubscription | null;
  customerBound: boolean;
  availablePlans: readonly BillingPlan[];
}>;

export type CommerceOpenReceipt = Readonly<{ opened: true }>;

export function parseBillingStatus(value: unknown): BillingStatus {
  const root = record(value);
  if (root.mode !== "uniform_bounded" && root.mode !== "commerce_provider") {
    throw new Error("Billing status is invalid");
  }
  if (!Array.isArray(root.availablePlans) || root.availablePlans.length > 256) {
    throw new Error("Billing status is invalid");
  }
  return Object.freeze({
    mode: root.mode,
    plan: root.plan === null ? null : parsePlan(root.plan),
    subscription: root.subscription === null ? null : parseSubscription(root.subscription),
    customerBound: bool(root.customerBound),
    availablePlans: Object.freeze(root.availablePlans.map(parsePlan)),
  });
}

export function parseCommerceOpenReceipt(value: unknown): CommerceOpenReceipt {
  const root = record(value);
  if (root.opened !== true) throw new Error("Billing browser action failed");
  return Object.freeze({ opened: true });
}

function parsePlan(value: unknown): BillingPlan {
  const plan = record(value);
  const limits = record(plan.limits);
  if (!Array.isArray(plan.allowedModels) || plan.allowedModels.length > 128) {
    throw new Error("Billing plan is invalid");
  }
  return Object.freeze({
    id: text(plan.id, 128),
    displayName: text(plan.displayName, 512),
    allowedModels: Object.freeze(plan.allowedModels.map((model) => text(model, 256))),
    limits: Object.freeze({
      maxRequests: integer(limits.maxRequests),
      maxUnits: integer(limits.maxUnits),
      maxConcurrency: integer(limits.maxConcurrency),
    }),
  });
}

function parseSubscription(value: unknown): BillingSubscription {
  const subscription = record(value);
  return Object.freeze({
    status: text(subscription.status, 64),
    paidThrough: nullableInteger(subscription.paidThrough),
    periodStart: nullableInteger(subscription.periodStart),
    periodEnd: nullableInteger(subscription.periodEnd),
    revoked: bool(subscription.revoked),
  });
}

function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Billing response is invalid");
  }
  return value as Record<string, unknown>;
}

function text(value: unknown, maximum: number): string {
  if (typeof value !== "string" || !value || value.length > maximum || /[\r\n\0]/.test(value)) {
    throw new Error("Billing response is invalid");
  }
  return value;
}

function integer(value: unknown): number {
  if (!Number.isSafeInteger(value) || Number(value) < 0) throw new Error("Billing response is invalid");
  return Number(value);
}

function nullableInteger(value: unknown): number | null {
  return value === null || value === undefined ? null : integer(value);
}

function bool(value: unknown): boolean {
  if (typeof value !== "boolean") throw new Error("Billing response is invalid");
  return value;
}
