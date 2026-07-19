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

export type DeveloperProjectDocument = {
  schemaVersion: 1;
  providers: {
    identity: ProviderSelection | null;
    entitlement: ProviderSelection | null;
    gateway: ProviderSelection | null;
  };
  modelAccess:
    | { configurationPolicy: "user_configurable" }
    | { configurationPolicy: "app_managed"; profile: ManagedModelProfile };
  deployment: null | {
    provider: "cloudflare";
    cloudflare: {
      accountId: string;
      workerName: string;
      environment: "development" | "staging" | "production";
    };
  };
};

export type ManagedProjectDraft = DeveloperProjectDocument & {
  modelAccess: { configurationPolicy: "app_managed"; profile: ManagedModelProfile };
  providers: {
    identity: ProviderSelection;
    entitlement: ProviderSelection;
    gateway: ProviderSelection;
  };
  deployment: NonNullable<DeveloperProjectDocument["deployment"]>;
};

export function parseDeveloperProject(value: unknown): DeveloperProjectDocument {
  if (!isRecord(value) || value.schemaVersion !== 1 || !isRecord(value.providers)) {
    throw new Error("Developer project is invalid");
  }
  return structuredClone(value) as DeveloperProjectDocument;
}

export function userConfigurableProject(
  source: DeveloperProjectDocument,
): DeveloperProjectDocument {
  return {
    ...structuredClone(source),
    providers: { identity: null, entitlement: null, gateway: null },
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
  if (source.modelAccess.configurationPolicy === "app_managed"
    && source.providers.identity
    && source.providers.entitlement
    && source.providers.gateway
    && source.deployment
    && existingIdentity?.kind === "identity"
    && existingEntitlement?.kind === "entitlement"
    && existingEntitlement.capabilities.includes("gateway_policy_projection_v1")
    && existingGateway?.kind === "gateway_deployment") {
    return structuredClone(source) as ManagedProjectDraft;
  }
  const identity = requiredProvider(providers, "identity", "agentweave.identity.oidc");
  const entitlement = providers.find((provider) => provider.kind === "entitlement"
    && provider.capabilities.includes("gateway_policy_projection_v1"));
  const gateway = requiredProvider(providers, "gateway_deployment", "cloudflare-workers");
  if (!entitlement) throw new Error("No gateway-compatible entitlement plugin is installed");
  const workerName = defaultWorkerName(appId);
  return {
    schemaVersion: 1,
    providers: {
      identity: selectionFromDescriptor(identity, {
        preset: "auth0",
        scopes: ["openid", "profile", "offline_access"],
        redirectUri: "http://127.0.0.1:8978/agentweave/identity/callback",
        gatewayAlgorithm: "RS256",
        gatewayDeviceMode: "disabled",
        gatewayRequireNbf: false,
      }),
      entitlement: selectionFromDescriptor(entitlement),
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
      cloudflare: { accountId: "", workerName, environment: "production" },
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
  const identity = draft.providers.identity.publicConfig;
  const gateway = draft.providers.gateway.publicConfig;
  const entitlement = draft.providers.entitlement.publicConfig;
  for (const [label, value] of [
    ["Identity issuer", identity.issuer],
    ["Identity client ID", identity.clientId],
    ["Gateway audience", identity.audience],
    ["Entitlement service URL", entitlement.baseUrl],
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
    draft.deployment.cloudflare.workerName,
  )) issues.push("Worker name is invalid");
  if (providers.length > 0) {
    for (const [label, selection] of [
      ["Identity", draft.providers.identity],
      ["Entitlement", draft.providers.entitlement],
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
