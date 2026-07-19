import { cleanup, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";

import type { DeveloperProjectSnapshot } from "../src/shared/developerProject";
import App from "../src/renderer/App";
import type { DeveloperProviderDescriptor } from "../src/renderer/devProvidersApi";
import { installHostBootstrap } from "./hostBootstrapFixture";

afterEach(() => {
  cleanup();
  window.history.replaceState(null, "", "/");
  window.localStorage.clear();
  vi.restoreAllMocks();
  delete window.agentWeave;
});

describe("developer release workspace", () => {
  it("deep-links model delivery into the guided access setup without saving", async () => {
    const save = vi.fn();
    installReleaseBridge(userConfigurableSnapshot(), { save });
    window.history.replaceState(null, "", "/#developer/model");
    const user = userEvent.setup();

    render(<App />);

    expect(await screen.findByRole("heading", {
      name: "Choose who controls the model connection",
    })).toBeInTheDocument();
    await user.click(screen.getByText("The App provides the model"));

    expect(window.location.hash).toBe("#developer/access/setup");
    expect(await screen.findByRole("heading", {
      name: "Choose the user identity plugin",
    })).toBeInTheDocument();
    expect(save).not.toHaveBeenCalled();
  });

  it("packages a user-configurable App only after every release check passes", async () => {
    const packageApp = vi.fn(async () => ({
      outputPath: "/tmp/AgentWeave.app",
      summary: "Packaged AgentWeave",
    }));
    installReleaseBridge(userConfigurableSnapshot(), { packageApp });
    window.history.replaceState(null, "", "/#developer/build");
    const user = userEvent.setup();

    render(<App />);

    const packageButton = await screen.findByRole("button", { name: "Package desktop App" });
    expect(packageButton).toBeEnabled();
    await user.click(packageButton);

    expect(packageApp).toHaveBeenCalledTimes(1);
    expect(await screen.findByText("Packaged AgentWeave")).toBeInTheDocument();
    expect(screen.getByText("/tmp/AgentWeave.app")).toBeInTheDocument();
  });

  it("keeps packaging blocked when the managed gateway has no verified lock", async () => {
    const packageApp = vi.fn();
    installReleaseBridge(managedSnapshot("missing"), { packageApp });
    window.history.replaceState(null, "", "/#developer/build");

    render(<App />);

    const packageButton = await screen.findByRole("button", { name: "Package desktop App" });
    expect(packageButton).toBeDisabled();
    expect(screen.getByText("Packaging blocked")).toBeInTheDocument();
    expect(screen.getByText("Deploy and verify the configured gateway before packaging.")).toBeInTheDocument();
    expect(packageApp).not.toHaveBeenCalled();
  });

  it("recovers a newly applied deployment after the setup view is reopened", async () => {
    const snapshot = managedSnapshot("missing");
    installReleaseBridge(snapshot, {
      controlStatus: {
        authorization: {
          providerId: "cloudflare-workers",
          phase: "ready",
          accountId: "0123456789abcdef0123456789abcdef",
          expiresAtUnixMs: Date.now() + 60_000,
          publicOauthClientAvailable: true,
        },
        gatewayTemplate: { version: "gateway-v1", sha256: "a".repeat(64) },
        sensitiveBindings: {},
        pendingDeployment: {
          deployment: {
            providerId: "cloudflare-workers",
            providerVersion: "0.1.0",
            target: {
              accountId: "0123456789abcdef0123456789abcdef",
              deploymentId: "deployment-1",
              workerName: "example-gateway",
              environment: "production",
            },
            outcome: "applied",
            previousVersionId: null,
            versionId: "version-1",
            endpoint: "https://example.workers.dev",
            operationId: "4f290eb3-8712-4f7d-bde8-0a98aa95e33b",
            completedAtUnixMs: 1_700_000_000_000,
          },
          projectRevision: snapshot.revision,
        },
      },
    });
    window.history.replaceState(null, "", "/#developer/access/setup");
    const user = userEvent.setup();

    render(<App />);
    await user.click(await screen.findByRole("button", { name: /Deploy and verify/ }));

    expect(screen.getByText("Deployed")).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Deployment operations" })).toBeInTheDocument();
    expect(screen.getByText("example-gateway")).toBeInTheDocument();
  });

  it("renders the release navigation and model decision in Simplified Chinese", async () => {
    window.localStorage.setItem("agentweave.localization.locale.v1", "zh-CN");
    installReleaseBridge(userConfigurableSnapshot());
    window.history.replaceState(null, "", "/#developer/model");

    render(<App />);

    expect(await screen.findByRole("tab", { name: "用户与访问" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "选择由谁控制模型连接" })).toBeInTheDocument();
  });
});

function installReleaseBridge(
  snapshot: DeveloperProjectSnapshot,
  overrides: {
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
    request: async (operation) => {
      if (operation !== "status") throw new Error(`Unexpected operation: ${operation}`);
      return overrides.controlStatus ?? {
        authorization: {
          providerId: "cloudflare-workers",
          phase: "disconnected",
          accountId: null,
          expiresAtUnixMs: null,
          publicOauthClientAvailable: true,
        },
        gatewayTemplate: { version: "gateway-v1", sha256: "a".repeat(64) },
        sensitiveBindings: {},
        pendingDeployment: null,
      };
    },
  };
}

function userConfigurableSnapshot(): DeveloperProjectSnapshot {
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

function managedSnapshot(
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

function providerDescriptors(): DeveloperProviderDescriptor[] {
  return [
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
      ...descriptor("gateway_deployment", "cloudflare-workers", "Cloudflare Workers", [
        { ...field("upstreamBaseUrl", "Upstream model URL"), field_type: "https_url" },
      ]),
      configuration_schema: {
        schema_version: 1,
        migration_version: 1,
        public_fields: [{ ...field("upstreamBaseUrl", "Upstream model URL"), field_type: "https_url" }],
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
