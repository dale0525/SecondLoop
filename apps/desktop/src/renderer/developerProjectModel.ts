import type { DeveloperProviderDescriptor } from "./devProvidersApi";

export type ProviderSelection = {
  id: string;
  version: string;
  publicConfig: Record<string, unknown>;
};

export type ManagedModelProfile = {
  providerId: string;
  endpointType: "responses" | "chat_completions" | "completion";
  baseUrl: string;
  modelName: string;
  authentication: "user_identity";
  headers: Record<string, string>;
};

export type PlanLimits = {
  maxRequests: number;
  maxUnits: number;
  maxConcurrency: number;
};

export type EntitlementPolicyPlan = {
  id: string;
  displayName: string;
  enabled?: boolean;
  productId?: string;
  allowedModels: string[];
  limits: PlanLimits;
};

export type ManagedEntitlementDeployment =
  | { mode: "external_service" }
  | {
      mode: "managed_worker";
      workerName: string;
      policy:
        | {
            sourceMode: "uniform_bounded";
            tenantLimits: Pick<PlanLimits, "maxRequests" | "maxUnits">;
            uniformPlan: EntitlementPolicyPlan;
          }
        | {
            sourceMode: "commerce_provider";
            tenantLimits: Pick<PlanLimits, "maxRequests" | "maxUnits">;
            productPlans: EntitlementPolicyPlan[];
          };
    };

export type DeveloperProjectDocument = {
  schemaVersion: 2;
  providers: {
    identity: ProviderSelection | null;
    entitlement: ProviderSelection | null;
    commerce: ProviderSelection | null;
    gateway: ProviderSelection | null;
  };
  modelAccess:
    | { configurationPolicy: "user_configurable" }
    | { configurationPolicy: "app_managed"; profile: ManagedModelProfile };
  deployment: null | {
    provider: "cloudflare";
    cloudflare: {
      accountId: string;
      gatewayWorkerName: string;
      environment: "development" | "staging" | "production";
      entitlement: ManagedEntitlementDeployment;
    };
  };
};

export type ManagedProjectDraft = DeveloperProjectDocument & {
  modelAccess: { configurationPolicy: "app_managed"; profile: ManagedModelProfile };
  providers: {
    identity: ProviderSelection;
    entitlement: ProviderSelection;
    commerce: ProviderSelection | null;
    gateway: ProviderSelection;
  };
  deployment: NonNullable<DeveloperProjectDocument["deployment"]>;
};

export function parseDeveloperProject(value: unknown): DeveloperProjectDocument {
  if (!isRecord(value) || !isRecord(value.providers)) {
    throw new Error("Developer project is invalid");
  }
  if (value.schemaVersion === 2) return structuredClone(value) as DeveloperProjectDocument;
  if (value.schemaVersion !== 1) throw new Error("Developer project is invalid");
  const legacy = structuredClone(value) as {
    providers: Omit<DeveloperProjectDocument["providers"], "commerce">;
    modelAccess: DeveloperProjectDocument["modelAccess"];
    deployment: null | {
      provider: "cloudflare";
      cloudflare: {
        accountId: string;
        workerName: string;
        environment: "development" | "staging" | "production";
      };
    };
  };
  return {
    schemaVersion: 2,
    providers: { ...legacy.providers, commerce: null },
    modelAccess: legacy.modelAccess,
    deployment: legacy.deployment === null ? null : {
      provider: "cloudflare",
      cloudflare: {
        accountId: legacy.deployment.cloudflare.accountId,
        gatewayWorkerName: legacy.deployment.cloudflare.workerName,
        environment: legacy.deployment.cloudflare.environment,
        entitlement: { mode: "external_service" },
      },
    },
  };
}

export function userConfigurableProject(
  source: DeveloperProjectDocument,
): DeveloperProjectDocument {
  return {
    ...structuredClone(source),
    schemaVersion: 2,
    providers: { identity: null, entitlement: null, commerce: null, gateway: null },
    modelAccess: { configurationPolicy: "user_configurable" },
    deployment: null,
  };
}

export function managedProjectDraft(
  source: DeveloperProjectDocument,
  providers: readonly DeveloperProviderDescriptor[],
  appId: string,
): ManagedProjectDraft {
  const existingIdentity = source.providers.identity
    ? providerBySelection(providers, source.providers.identity)
    : null;
  const existingEntitlement = source.providers.entitlement
    ? providerBySelection(providers, source.providers.entitlement)
    : null;
  const existingGateway = source.providers.gateway
    ? providerBySelection(providers, source.providers.gateway)
    : null;
  const existingCommerce = source.providers.commerce
    ? providerBySelection(providers, source.providers.commerce)
    : null;
  if (source.modelAccess.configurationPolicy === "app_managed"
    && source.providers.identity
    && source.providers.entitlement
    && source.providers.gateway
    && source.deployment
    && existingIdentity?.kind === "identity"
    && existingEntitlement?.kind === "entitlement"
    && existingEntitlement.capabilities.some((capability) => [
      "gateway_policy_projection_v1",
      "gateway_policy_projection_v2",
    ].includes(capability))
    && existingGateway?.kind === "gateway_deployment"
    && (!source.providers.commerce || existingCommerce?.kind === "commerce")) {
    return structuredClone(source) as ManagedProjectDraft;
  }
  const identity = providers.find((provider) => provider.kind === "identity"
    && provider.provider_id === "agentweave.identity.firebase")
    ?? requiredProvider(providers, "identity", "agentweave.identity.oidc");
  const entitlement = providers.find((provider) => provider.kind === "entitlement"
    && provider.provider_id === "agentweave.entitlements.cloudflare_policy")
    ?? providers.find((provider) => provider.kind === "entitlement"
      && provider.capabilities.includes("gateway_policy_projection_v2"))
    ?? providers.find((provider) => provider.kind === "entitlement"
      && provider.capabilities.includes("gateway_policy_projection_v1"));
  const gateway = requiredProvider(providers, "gateway_deployment", "cloudflare-workers");
  if (!entitlement) throw new Error("No gateway-compatible entitlement plugin is installed");
  const workerName = defaultWorkerName(appId);
  const supportsManagedWorker = entitlement.provider_id === "agentweave.entitlements.cloudflare_policy"
    || entitlement.capabilities.includes("gateway_policy_projection_v2");
  return {
    schemaVersion: 2,
    providers: {
      identity: selectionFromDescriptor(identity, identity.provider_id === "agentweave.identity.oidc"
        ? {
            preset: "auth0",
            scopes: ["openid", "profile", "offline_access"],
            redirectUri: "http://127.0.0.1:8978/agentweave/identity/callback",
            gatewayAlgorithm: "RS256",
            gatewayDeviceMode: "disabled",
            gatewayRequireNbf: false,
          }
        : {}),
      entitlement: selectionFromDescriptor(entitlement),
      commerce: null,
      gateway: selectionFromDescriptor(gateway),
    },
    modelAccess: {
      configurationPolicy: "app_managed",
      profile: {
        providerId: "cloudflare-gateway",
        endpointType: "responses",
        baseUrl: `https://${workerName}.workers.dev/v1`,
        modelName: "",
        authentication: "user_identity",
        headers: {},
      },
    },
    deployment: {
      provider: "cloudflare",
      cloudflare: {
        accountId: "",
        gatewayWorkerName: workerName,
        environment: "production",
        entitlement: supportsManagedWorker
          ? {
              mode: "managed_worker",
              workerName: managedEntitlementWorkerName(workerName),
              policy: {
                sourceMode: "uniform_bounded",
                tenantLimits: { maxRequests: 0, maxUnits: 0 },
                uniformPlan: {
                  id: "default",
                  displayName: "Default plan",
                  allowedModels: [],
                  limits: { maxRequests: 0, maxUnits: 0, maxConcurrency: 0 },
                },
              },
            }
          : { mode: "external_service" },
      },
    },
  };
}

export function selectionFromDescriptor(
  descriptor: DeveloperProviderDescriptor,
  overrides: Record<string, unknown> = {},
): ProviderSelection {
  const defaults = Object.fromEntries(descriptor.configuration_schema.public_fields
    .filter((field) => field.default_value !== null)
    .map((field) => [field.id, structuredClone(field.default_value)]));
  return {
    id: descriptor.provider_id,
    version: descriptor.provider_version,
    publicConfig: { ...defaults, ...overrides },
  };
}

export function updateProviderConfig(
  selection: ProviderSelection,
  field: string,
  value: unknown,
): ProviderSelection {
  const publicConfig = { ...selection.publicConfig };
  if (value === "" || value === undefined || value === null) delete publicConfig[field];
  else publicConfig[field] = value;
  return { ...selection, publicConfig };
}

export function validateManagedDraft(
  draft: ManagedProjectDraft,
  providers: readonly DeveloperProviderDescriptor[] = [],
): string[] {
  const issues: string[] = [];
  const gateway = draft.providers.gateway.publicConfig;
  const entitlement = draft.providers.entitlement.publicConfig;
  const managedEntitlement = draft.deployment.cloudflare.entitlement;
  for (const [label, value] of [
    ["Upstream model URL", gateway.upstreamBaseUrl],
    ["Model name", draft.modelAccess.profile.modelName],
    ["Cloudflare account", draft.deployment.cloudflare.accountId],
  ]) {
    if (typeof value !== "string" || value.trim() === "") issues.push(`${label} is required`);
  }
  if (!/^[0-9a-f]{32}$/i.test(draft.deployment.cloudflare.accountId)) {
    issues.push("Cloudflare account ID is invalid");
  }
  if (!/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(
    draft.deployment.cloudflare.gatewayWorkerName,
  )) issues.push("Gateway Worker name is invalid");
  if (managedEntitlement.mode === "external_service") {
    if (typeof entitlement.baseUrl !== "string" || entitlement.baseUrl.trim() === "") {
      issues.push("Entitlement service URL is required in external mode");
    }
  } else {
    if (!/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(managedEntitlement.workerName)) {
      issues.push("Entitlement Worker name is invalid");
    }
    if (managedEntitlement.workerName === draft.deployment.cloudflare.gatewayWorkerName) {
      issues.push("Entitlement and Gateway Worker names must differ");
    }
    const plans = managedEntitlement.policy.sourceMode === "uniform_bounded"
      ? [managedEntitlement.policy.uniformPlan]
      : managedEntitlement.policy.productPlans;
    if (plans.filter((plan) => plan.enabled !== false).length === 0) {
      issues.push("At least one entitlement plan must be enabled");
    }
    for (const plan of plans.filter((candidate) => candidate.enabled !== false)) {
      if (!plan.id.trim()) issues.push("Plan ID is required");
      if (plan.allowedModels.length === 0) issues.push(`${plan.displayName || plan.id} needs an allowed model`);
      if (managedEntitlement.policy.sourceMode === "commerce_provider"
        && (!plan.productId || !/^prod_[A-Za-z0-9_]+$/.test(plan.productId))) {
        issues.push(`${plan.displayName || plan.id} has an invalid Creem product`);
      }
      for (const [field, value] of Object.entries(plan.limits)) {
        if (!Number.isSafeInteger(value) || value < 0) {
          issues.push(`${plan.displayName || plan.id} ${field} must be a non-negative integer`);
        }
      }
      if (plan.limits.maxConcurrency > 1000) {
        issues.push(`${plan.displayName || plan.id} concurrency exceeds the system ceiling`);
      }
    }
    const commerceRequired = managedEntitlement.policy.sourceMode === "commerce_provider";
    if (commerceRequired !== (draft.providers.commerce !== null)) {
      issues.push("Commerce provider selection does not match the entitlement policy");
    }
    if (commerceRequired && providers.length > 0) {
      const descriptor = draft.providers.commerce
        ? providerBySelection(providers, draft.providers.commerce)
        : null;
      const capabilities = new Set(descriptor?.capabilities ?? []);
      for (const capability of [
        "checkout_session_v1",
        "customer_portal_v1",
        "product_discovery_v1",
        "signed_webhook_v1",
        "subscription_reconciliation_v1",
        "test_environment_v1",
      ]) {
        if (!capabilities.has(capability)) issues.push(`Commerce provider is missing ${capability}`);
      }
    }
  }
  if (providers.length > 0) {
    for (const [label, selection] of [
      ["Identity", draft.providers.identity],
      ["Entitlement", draft.providers.entitlement],
      ...(draft.providers.commerce ? [["Commerce", draft.providers.commerce] as const] : []),
      ["Gateway", draft.providers.gateway],
    ] as const) {
      const descriptor = providerBySelection(providers, selection);
      if (!descriptor) {
        issues.push(`${label} plugin is unavailable or incompatible`);
        continue;
      }
      for (const field of descriptor.configuration_schema.public_fields) {
        if (field.visible_when
          && selection.publicConfig[field.visible_when.field_id] !== field.visible_when.equals) continue;
        const value = selection.publicConfig[field.id];
        if (label === "Entitlement"
          && managedEntitlement.mode === "managed_worker"
          && field.id === "baseUrl") continue;
        if (field.required && !hasValue(value)) {
          issues.push(`${field.label} is required`);
          continue;
        }
        if (!hasValue(value)) continue;
        if (field.field_type === "integer" && !Number.isSafeInteger(value)) {
          issues.push(`${field.label} must be an integer`);
        }
        if (field.field_type === "https_url" && !validUrl(value, true)) {
          issues.push(`${field.label} must be a credential-free HTTPS URL`);
        }
        if (field.field_type === "url" && !validUrl(value, false)) {
          issues.push(`${field.label} must be a valid URL`);
        }
      }
    }
  }
  return [...new Set(issues)];
}

export function providerBySelection(
  providers: readonly DeveloperProviderDescriptor[],
  selection: ProviderSelection,
): DeveloperProviderDescriptor | null {
  return providers.find((provider) => provider.provider_id === selection.id
    && provider.provider_version === selection.version) ?? null;
}

function requiredProvider(
  providers: readonly DeveloperProviderDescriptor[],
  kind: DeveloperProviderDescriptor["kind"],
  id: string,
): DeveloperProviderDescriptor {
  const provider = providers.find((candidate) => candidate.kind === kind
    && candidate.provider_id === id);
  if (!provider) throw new Error(`Required provider is unavailable: ${id}`);
  return provider;
}

function defaultWorkerName(appId: string): string {
  const normalized = `${appId.replaceAll(/[^a-z0-9]+/gi, "-").toLowerCase()}-gateway`
    .replaceAll(/^-+|-+$/g, "");
  if (normalized.length <= 63) return normalized;
  let hash = 2166136261;
  for (const character of appId) hash = Math.imul(hash ^ character.charCodeAt(0), 16777619);
  return `${normalized.slice(0, 54).replace(/-+$/, "")}-${(hash >>> 0).toString(16).padStart(8, "0")}`;
}

export function managedEntitlementWorkerName(gatewayWorkerName: string): string {
  const candidate = `${gatewayWorkerName}-entitlements`;
  if (candidate.length <= 63) return candidate;
  let hash = 2166136261;
  for (const character of candidate) {
    hash = Math.imul(hash ^ character.charCodeAt(0), 16777619);
  }
  return `${gatewayWorkerName.slice(0, 41).replace(/-+$/, "")}-entitlements-${
    (hash >>> 0).toString(16).padStart(8, "0")
  }`;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasValue(value: unknown): boolean {
  if (typeof value === "string") return value.trim().length > 0;
  if (Array.isArray(value)) return value.length > 0;
  if (value && typeof value === "object") return Object.keys(value).length > 0;
  return value !== undefined && value !== null;
}

function validUrl(value: unknown, httpsOnly: boolean): boolean {
  if (typeof value !== "string") return false;
  try {
    const parsed = new URL(value);
    return (!httpsOnly || parsed.protocol === "https:") && !parsed.username && !parsed.password;
  } catch {
    return false;
  }
}
