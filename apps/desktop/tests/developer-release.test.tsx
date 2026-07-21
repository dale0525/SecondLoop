import { cleanup, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import type { DeveloperProjectSnapshot } from "../src/shared/developerProject";
import App from "../src/renderer/App";
import type { DeveloperProviderDescriptor } from "../src/renderer/devProvidersApi";
import { installHostBootstrap } from "./hostBootstrapFixture";

class TestResizeObserver implements ResizeObserver {
  disconnect(): void {}
  observe(): void {}
  unobserve(): void {}
}

beforeEach(() => {
  vi.stubGlobal("ResizeObserver", TestResizeObserver);
});

afterEach(() => {
  cleanup();
  window.history.replaceState(null, "", "/");
  window.localStorage.clear();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
  delete window.agentWeave;
});

describe("developer release workspace", () => {
  it("opens the automation-first connection step without saving a partial project", async () => {
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
      name: "Connect the deployment account",
    })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Sign in and authorize Cloudflare" })).toBeInTheDocument();
    expect(screen.getByText("Recommended access stack")).toBeInTheDocument();
    expect(screen.queryByRole("heading", { name: "Choose the user identity plugin" })).not.toBeInTheDocument();
    expect(save).not.toHaveBeenCalled();
  });

  it("starts Cloudflare public OAuth from the primary action", async () => {
    const accessRequest = vi.fn(async (operation: string) => {
      if (operation === "status") return disconnectedControlStatus();
      if (operation === "cloudflare.connect") return undefined;
      throw new Error(`Unexpected operation: ${operation}`);
    });
    installReleaseBridge(userConfigurableSnapshot(), { accessRequest });
    window.history.replaceState(null, "", "/#developer/access/setup");
    const user = userEvent.setup();

    render(<App />);
    await user.click(await screen.findByRole("button", { name: "Sign in and authorize Cloudflare" }));

    expect(accessRequest).toHaveBeenCalledWith("cloudflare.connect", {
      client: { mode: "agent_weave_public" },
    });
    expect(await screen.findByText("Waiting for browser approval")).toBeInTheDocument();
  });

  it("keeps custom OAuth fields behind an explicit advanced override", async () => {
    installReleaseBridge(userConfigurableSnapshot());
    window.history.replaceState(null, "", "/#developer/access/setup");
    const user = userEvent.setup();

    render(<App />);

    expect(await screen.findByRole("button", {
      name: "Sign in and authorize Cloudflare",
    })).toBeInTheDocument();
    expect(screen.queryByText("Cloudflare OAuth client ID")).not.toBeInTheDocument();

    await user.click(screen.getByText("Use my own OAuth client"));
    await user.click(screen.getByRole("checkbox", { name: /Override the public OAuth client/ }));

    expect(screen.getByText("Cloudflare OAuth client ID")).toBeVisible();
    expect(screen.getByText("Authoritative scope catalog")).toBeVisible();
    expect(screen.getByRole("button", {
      name: "Connect custom Cloudflare client",
    })).toBeVisible();
  });

  it("uses the custom OAuth form directly when no public client is available", async () => {
    const accessRequest = vi.fn(async (operation: string) => {
      if (operation === "status") return controlStatus("disconnected", null, false);
      if (operation === "cloudflare.connect") return undefined;
      throw new Error(`Unexpected operation: ${operation}`);
    });
    installReleaseBridge(userConfigurableSnapshot(), { accessRequest });
    window.history.replaceState(null, "", "/#developer/access/setup");
    const user = userEvent.setup();

    render(<App />);

    expect(await screen.findByText("Cloudflare OAuth client ID")).toBeVisible();
    expect(screen.queryByRole("button", {
      name: "Sign in and authorize Cloudflare",
    })).not.toBeInTheDocument();
    await user.type(screen.getByRole("textbox", {
      name: "Cloudflare OAuth client ID",
    }), "custom-client");
    await user.type(screen.getByRole("textbox", {
      name: /Authoritative scope catalog/,
    }), "Workers Scripts Read=scope.read");
    await user.click(screen.getByRole("button", {
      name: "Connect custom Cloudflare client",
    }));

    expect(accessRequest).toHaveBeenCalledWith("cloudflare.connect", {
      client: {
        mode: "custom",
        clientId: "custom-client",
        scopeCatalog: { "Workers Scripts Read": "scope.read" },
      },
    });
  });

  it("binds the only Cloudflare account automatically and advances to required details", async () => {
    let phase: "select_account" | "ready" = "select_account";
    const accountId = "0123456789abcdef0123456789abcdef";
    const accessRequest = vi.fn(async (operation: string) => {
      if (operation === "status") return controlStatus(phase, phase === "ready" ? accountId : null);
      if (operation === "cloudflare.accounts") return [{
        accountId,
        displayName: "Only account",
        providerId: "cloudflare-workers",
      }];
      if (operation === "cloudflare.selectAccount") {
        phase = "ready";
        return undefined;
      }
      throw new Error(`Unexpected operation: ${operation}`);
    });
    installReleaseBridge(userConfigurableSnapshot(), { accessRequest });
    window.history.replaceState(null, "", "/#developer/access/setup");

    render(<App />);

    expect(await screen.findByRole("heading", {
      name: "Enter the details only your services know",
    })).toBeInTheDocument();
    expect(accessRequest).toHaveBeenCalledWith("cloudflare.selectAccount", { accountId });
    expect(screen.getByText("User sign-in")).toBeInTheDocument();
    expect(screen.getByText("Model service")).toBeInTheDocument();
  });

  it("recovers a completed Cloudflare authorization from the authoritative status", async () => {
    let phase: "select_account" | "ready" = "select_account";
    let statusRequests = 0;
    const accountId = "0123456789abcdef0123456789abcdef";
    const accessRequest = vi.fn(async (operation: string) => {
      if (operation === "status") {
        statusRequests += 1;
        if (statusRequests === 1) return disconnectedControlStatus();
        return controlStatus(phase, phase === "ready" ? accountId : null);
      }
      if (operation === "cloudflare.accounts") return [{
        accountId,
        displayName: "Only account",
        providerId: "cloudflare-workers",
      }];
      if (operation === "cloudflare.selectAccount") {
        phase = "ready";
        return undefined;
      }
      throw new Error(`Unexpected operation: ${operation}`);
    });
    installReleaseBridge(userConfigurableSnapshot(), { accessRequest });
    window.history.replaceState(null, "", "/#developer/access/setup");

    render(<App />);

    expect(await screen.findByRole("heading", {
      name: "Enter the details only your services know",
    })).toBeInTheDocument();
    expect(statusRequests).toBeGreaterThanOrEqual(3);
    expect(accessRequest).toHaveBeenCalledWith("cloudflare.selectAccount", { accountId });
  });

  it("offers an in-place retry when automatic account binding fails", async () => {
    let phase: "select_account" | "ready" = "select_account";
    let selectionAttempts = 0;
    const accountId = "0123456789abcdef0123456789abcdef";
    const accessRequest = vi.fn(async (operation: string) => {
      if (operation === "status") return controlStatus(phase, phase === "ready" ? accountId : null);
      if (operation === "cloudflare.accounts") return [{
        accountId,
        displayName: "Only account",
        providerId: "cloudflare-workers",
      }];
      if (operation === "cloudflare.selectAccount") {
        selectionAttempts += 1;
        if (selectionAttempts === 1) throw new Error("Temporary Cloudflare failure");
        phase = "ready";
        return undefined;
      }
      throw new Error(`Unexpected operation: ${operation}`);
    });
    installReleaseBridge(userConfigurableSnapshot(), { accessRequest });
    window.history.replaceState(null, "", "/#developer/access/setup");
    const user = userEvent.setup();

    render(<App />);

    expect(await screen.findByRole("alert")).toHaveTextContent("Temporary Cloudflare failure");
    const retry = screen.getByRole("button", { name: "Retry account binding" });
    expect(retry).toBeEnabled();
    await user.click(retry);

    expect(await screen.findByRole("heading", {
      name: "Enter the details only your services know",
    })).toBeInTheDocument();
    expect(selectionAttempts).toBe(2);
  });

  it("fills the OpenAI endpoint and authentication with one preset click", async () => {
    installReleaseBridge(userConfigurableSnapshot(), {
      controlStatus: controlStatus("ready", "0123456789abcdef0123456789abcdef"),
    });
    window.history.replaceState(null, "", "/#developer/access/setup");
    const user = userEvent.setup();

    render(<App />);
    await user.click(await screen.findByText("OpenAI"));

    expect(screen.getByText("Endpoint and authentication filled automatically")).toBeInTheDocument();
    expect(screen.getByText("https://api.openai.com")).toBeInTheDocument();
    expect(screen.queryByText("Upstream model URL")).not.toBeInTheDocument();
  });

  it("configures the only Firebase project without manual identity fields", async () => {
    let firebasePhase: "select_project" | "ready" = "select_project";
    const accessRequest = vi.fn(async (operation: string, input?: unknown) => {
      if (operation === "status") {
        return {
          ...controlStatus("ready", "0123456789abcdef0123456789abcdef") as Record<string, unknown>,
          firebaseAuthorization: {
            providerId: "google.firebase",
            phase: firebasePhase,
            projectId: firebasePhase === "ready" ? "sample-project-123" : null,
            expiresAtUnixMs: Date.now() + 60_000,
            publicOauthClientAvailable: true,
          },
        };
      }
      if (operation === "firebase.projects") return [{
        projectId: "sample-project-123",
        projectNumber: "123456789",
        displayName: "Sample Project",
      }];
      if (operation === "firebase.configure") {
        expect(input).toEqual({ projectId: "sample-project-123" });
        firebasePhase = "ready";
        return {
          projectId: "sample-project-123",
          displayName: "Sample Project",
          publicConfig: {
            projectId: "sample-project-123",
            firebaseWebKey: "public-firebase-web-key",
            webApplicationId: "1:123:web:abc",
            authDomain: "sample-project-123.firebaseapp.com",
          },
        };
      }
      throw new Error(`Unexpected operation: ${operation}`);
    });
    installReleaseBridge(userConfigurableSnapshot(), { accessRequest });
    window.history.replaceState(null, "", "/#developer/access/setup");

    render(<App />);

    expect(await screen.findByText("Firebase Email Login")).toBeInTheDocument();
    expect(await screen.findByText("Public login configuration verified")).toBeInTheDocument();
    expect(screen.getByText("sample-project-123")).toBeInTheDocument();
    expect(accessRequest).toHaveBeenCalledWith("firebase.configure", {
      projectId: "sample-project-123",
    });
    expect(screen.queryByText("Issuer URL")).not.toBeInTheDocument();
  });

  it("starts Firebase public OAuth from the primary action", async () => {
    const accountId = "0123456789abcdef0123456789abcdef";
    const accessRequest = vi.fn(async (operation: string) => {
      if (operation === "status") {
        return {
          ...controlStatus("ready", accountId) as Record<string, unknown>,
          firebaseAuthorization: {
            providerId: "google.firebase",
            phase: "disconnected",
            projectId: null,
            expiresAtUnixMs: null,
            publicOauthClientAvailable: true,
          },
        };
      }
      if (operation === "firebase.connect") return undefined;
      throw new Error(`Unexpected operation: ${operation}`);
    });
    installReleaseBridge(userConfigurableSnapshot(), { accessRequest });
    window.history.replaceState(null, "", "/#developer/access/setup");
    const user = userEvent.setup();

    render(<App />);
    await user.click(await screen.findByRole("button", { name: "Configure with Google" }));

    expect(accessRequest).toHaveBeenCalledWith("firebase.connect", {
      client: { mode: "agent_weave_public" },
    });
  });

  it("labels the Firebase fallback with the Google OAuth client identity", async () => {
    const accountId = "0123456789abcdef0123456789abcdef";
    const accessRequest = vi.fn(async (operation: string) => {
      if (operation === "status") {
        return {
          ...controlStatus("ready", accountId) as Record<string, unknown>,
          firebaseAuthorization: {
            providerId: "google.firebase",
            phase: "disconnected",
            projectId: null,
            expiresAtUnixMs: null,
            publicOauthClientAvailable: false,
          },
        };
      }
      if (operation === "firebase.connect") return undefined;
      throw new Error(`Unexpected operation: ${operation}`);
    });
    installReleaseBridge(userConfigurableSnapshot(), { accessRequest });
    window.history.replaceState(null, "", "/#developer/access/setup");
    const user = userEvent.setup();

    render(<App />);

    const clientId = await screen.findByRole("textbox", {
      name: "Google OAuth client ID",
    });
    expect(clientId).toBeVisible();
    expect(screen.queryByRole("textbox", {
      name: "Cloudflare OAuth client ID",
    })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", {
      name: "Configure with Google",
    })).not.toBeInTheDocument();

    await user.type(clientId, "custom-client.apps.googleusercontent.com");
    await user.click(screen.getByRole("button", { name: "Connect Google" }));

    expect(accessRequest).toHaveBeenCalledWith("firebase.connect", {
      client: {
        mode: "custom",
        clientId: "custom-client.apps.googleusercontent.com",
      },
    });
  });

  it("retries the Firebase project list without restarting Google authorization", async () => {
    let projectRequests = 0;
    const accessRequest = vi.fn(async (operation: string) => {
      if (operation === "status") {
        return {
          ...controlStatus(
            "ready",
            "0123456789abcdef0123456789abcdef",
          ) as Record<string, unknown>,
          firebaseAuthorization: {
            providerId: "google.firebase",
            phase: "select_project",
            projectId: null,
            expiresAtUnixMs: Date.now() + 60_000,
            publicOauthClientAvailable: true,
          },
        };
      }
      if (operation === "firebase.projects") {
        projectRequests += 1;
        if (projectRequests === 1) throw new Error("temporary project list failure");
        return [
          {
            projectId: "sample-project-123",
            projectNumber: "123456789",
            displayName: "Sample Project",
          },
          {
            projectId: "team-project-456",
            projectNumber: "987654321",
            displayName: "Team Project",
          },
        ];
      }
      throw new Error(`Unexpected operation: ${operation}`);
    });
    installReleaseBridge(userConfigurableSnapshot(), { accessRequest });
    window.history.replaceState(null, "", "/#developer/access/setup");
    const user = userEvent.setup();

    render(<App />);

    expect(await screen.findByRole("button", { name: "Retry project list" })).toBeVisible();
    await user.click(screen.getByRole("button", { name: "Retry project list" }));

    await waitFor(() => expect(projectRequests).toBe(2));
    expect(screen.queryByRole("button", { name: "Retry project list" })).not.toBeInTheDocument();
    expect(screen.getByRole("combobox", { name: "Firebase project" })).toBeVisible();
    expect(screen.queryByText(
      "Firebase projects could not be loaded. Reconnect Google and check project permissions.",
    )).not.toBeInTheDocument();
  });

  it("can continue after reviewing the connected account from the previous step", async () => {
    installReleaseBridge(userConfigurableSnapshot(), {
      controlStatus: controlStatus("ready", "0123456789abcdef0123456789abcdef"),
    });
    window.history.replaceState(null, "", "/#developer/access/setup");
    const user = userEvent.setup();

    render(<App />);
    expect(await screen.findByRole("heading", {
      name: "Enter the details only your services know",
    })).toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: "Back" }));

    expect(screen.getByRole("heading", {
      name: "Connect the deployment account",
    })).toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: "Continue" }));

    expect(screen.getByRole("heading", {
      name: "Enter the details only your services know",
    })).toBeInTheDocument();
  });

  it("clears the OpenAI authentication choice when switching to a custom model service", async () => {
    installReleaseBridge(userConfigurableSnapshot(), {
      controlStatus: controlStatus("ready", "0123456789abcdef0123456789abcdef"),
    });
    window.history.replaceState(null, "", "/#developer/access/setup");
    const user = userEvent.setup();

    render(<App />);
    await user.click(await screen.findByText("OpenAI"));
    await user.click(screen.getByText("OpenAI-compatible service"));

    expect(screen.getByText("Upstream model URL")).toBeVisible();
    expect(screen.getByRole("combobox", {
      name: /Upstream authentication/,
    })).toHaveTextContent("Choose an option");
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

function disconnectedControlStatus(): unknown {
  return controlStatus("disconnected", null);
}

function controlStatus(
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
