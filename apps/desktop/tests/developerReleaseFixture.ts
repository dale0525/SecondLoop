import type { DeveloperProviderDescriptor } from "../src/renderer/devProvidersApi";
import type { DeveloperProjectSnapshot } from "../src/shared/developerProject";
import { installHostBootstrap } from "./hostBootstrapFixture";

export function installReleaseBridge(
  snapshot: DeveloperProjectSnapshot,
  overrides: {
    accessRequest?: (operation: string, input?: unknown) => Promise<unknown>;
    controlStatus?: unknown;
    packageApp?: () => Promise<{ outputPath: string; summary: string }>;
    save?: (request: unknown) => Promise<DeveloperProjectSnapshot>;
  } = {},
): void {
  installHostBootstrap();
  if (!window.agentWeave) throw new Error("Host bootstrap must be installed first");
  window.agentWeave.server = {
    request: async (operation) => {
      if (operation === "devSkills.list") return { root: "/repo/skills", packages: [] };
      if (operation === "devProviders.list") return providerDescriptors();
      throw new Error(`Unexpected operation: ${operation}`);
    },
  };
  window.agentWeave.developerProject = {
    load: async () => snapshot,
    packageApp: overrides.packageApp ?? (async () => ({
      outputPath: "/tmp/AgentWeave.app",
      summary: "Packaged AgentWeave",
    })),
    save: overrides.save ?? (async () => snapshot),
    showOutput: async () => undefined,
  };
  window.agentWeave.developerAccess = {
    request: async (operation, input) => {
      if (overrides.accessRequest) return overrides.accessRequest(operation, input);
      if (operation !== "status") throw new Error(`Unexpected operation: ${operation}`);
      return overrides.controlStatus ?? disconnectedControlStatus();
    },
  };
}

export function disconnectedControlStatus(): unknown {
  return controlStatus("disconnected", null);
}

export function controlStatus(
  phase: "disconnected" | "select_account" | "ready",
  accountId: string | null,
  publicOauthClientAvailable = true,
): unknown {
  return {
    authorization: {
      providerId: "cloudflare-workers",
      phase,
      accountId,
      expiresAtUnixMs: null,
      publicOauthClientAvailable,
    },
    gatewayTemplate: { version: "gateway-v1", sha256: "a".repeat(64) },
    sensitiveBindings: {},
    pendingDeployment: null,
  };
}

export function userConfigurableSnapshot(): DeveloperProjectSnapshot {
  const project = {
    schemaVersion: 1,
    providers: { identity: null, entitlement: null, gateway: null },
    modelAccess: { configurationPolicy: "user_configurable" },
    deployment: null,
  };
  return {
    appRoot: "/repo/example-app",
    revision: "b".repeat(64),
    desiredHash: `sha256:${"c".repeat(64)}`,
    manifest: {
      schemaVersion: 2,
      appId: "com.example.agent",
      version: "0.1.0",
      modelAccess: project.modelAccess,
      identity: { mode: "local_single_user" },
      entitlements: { mode: "disabled" },
    },
    project,
    deploymentStatus: "not_required",
    deploymentMessage: null,
  };
}

export function managedSnapshot(
  deploymentStatus: DeveloperProjectSnapshot["deploymentStatus"],
): DeveloperProjectSnapshot {
  const project = {
    schemaVersion: 1,
    providers: {
      identity: { id: "agentweave.identity.oidc", version: "0.1.0", publicConfig: {} },
      entitlement: { id: "agentweave.entitlements.http", version: "0.1.0", publicConfig: {} },
      gateway: { id: "cloudflare-workers", version: "0.1.0", publicConfig: {} },
    },
    modelAccess: {
      configurationPolicy: "app_managed",
      profile: {
        providerId: "cloudflare-gateway",
        endpointType: "responses",
        baseUrl: "https://example.workers.dev/v1",
        modelName: "approved-model",
        authentication: "user_identity",
        headers: {},
      },
    },
    deployment: {
      provider: "cloudflare",
      cloudflare: {
        accountId: "0123456789abcdef0123456789abcdef",
        workerName: "example-gateway",
        environment: "production",
      },
    },
  };
  return {
    ...userConfigurableSnapshot(),
    project,
    manifest: {
      ...userConfigurableSnapshot().manifest,
      modelAccess: project.modelAccess,
      identity: { mode: "required", provider: project.providers.identity },
      entitlements: { mode: "required", provider: project.providers.entitlement },
    },
    deploymentStatus,
    deploymentMessage: "Deploy and verify the configured gateway before packaging.",
  };
}

export function managedCommerceSnapshot(): DeveloperProjectSnapshot {
  const accountId = "0123456789abcdef0123456789abcdef";
  const project = {
    schemaVersion: 2,
    providers: {
      identity: { id: "agentweave.identity.oidc", version: "0.1.0", publicConfig: {} },
      entitlement: {
        id: "agentweave.entitlements.cloudflare_policy",
        version: "0.1.0",
        publicConfig: {},
      },
      commerce: { id: "agentweave.commerce.creem", version: "0.1.0", publicConfig: {} },
      gateway: {
        id: "cloudflare-workers",
        version: "0.1.0",
        publicConfig: { upstreamBaseUrl: "https://api.openai.com/v1" },
      },
    },
    modelAccess: {
      configurationPolicy: "app_managed",
      profile: {
        providerId: "cloudflare-gateway",
        endpointType: "responses",
        baseUrl: "https://example-gateway.workers.dev/v1",
        modelName: "approved-model",
        authentication: "user_identity",
        headers: {},
      },
    },
    deployment: {
      provider: "cloudflare",
      cloudflare: {
        accountId,
        gatewayWorkerName: "example-gateway",
        environment: "production",
        entitlement: {
          mode: "managed_worker",
          workerName: "example-entitlements",
          policy: {
            sourceMode: "commerce_provider",
            tenantLimits: { maxRequests: 0, maxUnits: 0 },
            productPlans: [{
              id: "pro",
              productId: "prod_pro",
              displayName: "Pro",
              enabled: true,
              allowedModels: ["approved-model"],
              limits: { maxRequests: 0, maxUnits: 0, maxConcurrency: 0 },
            }],
          },
        },
      },
    },
  };
  return {
    ...userConfigurableSnapshot(),
    project,
    deploymentStatus: "ready",
    deploymentMessage: null,
    verifiedBundle: {
      bundleRevision: `sha256:${"d".repeat(64)}`,
      projectionSecretRevision: "revision-1",
      rollbackTarget: null,
      gateway: {
        target: { accountId, deploymentId: "production", workerName: "example-gateway" },
        versionId: "gateway-version",
        endpoint: "https://example-gateway.workers.dev/v1",
      },
      entitlementPolicy: {
        target: { accountId, deploymentId: "production", workerName: "example-entitlements" },
        versionId: "entitlement-version",
        endpoint: "https://example-entitlements.workers.dev",
      },
      commerce: {
        providerId: "agentweave.commerce.creem",
        providerVersion: "0.1.0",
        environment: "test",
        databaseId: "database-1",
        migrationHash: `sha256:${"e".repeat(64)}`,
        capabilities: ["customer_portal_v1", "signed_webhook_v1"],
        webhookVerifiedAtUnixMs: 1_800_000_000_000,
        portalVerifiedAtUnixMs: 0,
      },
      testedAtUnixMs: 1_800_000_000_000,
    },
  } as DeveloperProjectSnapshot;
}

function providerDescriptors(): DeveloperProviderDescriptor[] {
  const gatewayFields = [
    { ...field("upstreamBaseUrl", "Upstream model URL"), field_type: "https_url" as const },
    {
      ...field("upstreamAuthentication", "Upstream authentication", true, "bearer"),
      allowed_values: ["bearer", "x_api_key", "api_key"],
    },
  ];
  return [
    descriptor("identity", "agentweave.identity.firebase", "Firebase Email Login", [
      field("projectId", "Firebase Project ID"),
      field("firebaseWebKey", "Firebase web key"),
      field("webApplicationId", "Firebase Web App ID"),
      field("authDomain", "Authentication domain", false),
    ]),
    descriptor("identity", "agentweave.identity.oidc", "OpenID Connect", [
      field("preset", "Provider preset", true, "generic"),
      field("issuer", "Issuer URL"),
      field("clientId", "Client ID"),
      field("audience", "Gateway audience"),
      { ...field("scopes", "Scopes", true, ["openid"]), field_type: "string_list" },
      { ...field("redirectUri", "Login callback"), field_type: "url" },
    ]),
    {
      ...descriptor("entitlement", "agentweave.entitlements.http", "Developer service entitlements", [
        { ...field("baseUrl", "Service URL"), field_type: "https_url" },
      ]),
      capabilities: ["gateway_policy_projection_v1"],
      configuration_schema: {
        schema_version: 1,
        migration_version: 1,
        public_fields: [{ ...field("baseUrl", "Service URL"), field_type: "https_url" }],
        sensitive_fields: [{
          id: "serviceCredential",
          label: "Service credential",
          description: "Entitlement service credential.",
          required: true,
          purpose: "entitlement_service_authorization",
          rotation_supported: true,
        }],
      },
    },
    {
      ...descriptor(
        "entitlement",
        "agentweave.entitlements.cloudflare_policy",
        "Cloudflare Entitlement Policy",
        [],
      ),
      capabilities: ["gateway_policy_projection_v2"],
    },
    {
      ...descriptor("commerce", "agentweave.commerce.creem", "Creem Subscriptions", []),
      capabilities: [
        "checkout_session_v1",
        "customer_portal_v1",
        "product_discovery_v1",
        "signed_webhook_v1",
        "subscription_reconciliation_v1",
        "test_environment_v1",
      ],
    },
    {
      ...descriptor("gateway_deployment", "cloudflare-workers", "Cloudflare Workers", gatewayFields),
      configuration_schema: {
        schema_version: 1,
        migration_version: 1,
        public_fields: gatewayFields,
        sensitive_fields: [{
          id: "upstreamApiKey",
          label: "Upstream API key",
          description: "Model provider credential.",
          required: true,
          purpose: "model_upstream_authorization",
          rotation_supported: true,
        }],
      },
    },
  ];
}

function descriptor(
  kind: DeveloperProviderDescriptor["kind"],
  providerId: string,
  displayName: string,
  publicFields: DeveloperProviderDescriptor["configuration_schema"]["public_fields"],
): DeveloperProviderDescriptor {
  return {
    schema_version: 1,
    package_id: `${providerId}.package`,
    provider_id: providerId,
    provider_version: "0.1.0",
    kind,
    display_name: displayName,
    description: `${displayName} fixture`,
    documentation_url: "https://example.test/docs",
    risk_notice: "Review provider configuration.",
    platforms: ["macos"],
    capabilities: [],
    configuration_schema: {
      schema_version: 1,
      migration_version: 1,
      public_fields: publicFields,
      sensitive_fields: [],
    },
  };
}

function field(
  id: string,
  label: string,
  required = true,
  defaultValue: unknown = null,
): DeveloperProviderDescriptor["configuration_schema"]["public_fields"][number] {
  return {
    id,
    label,
    description: `${label} fixture`,
    field_type: "string",
    required,
    default_value: defaultValue,
    allowed_values: [],
    minimum_length: null,
    maximum_length: null,
    advanced: false,
  };
}
