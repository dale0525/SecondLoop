import { cleanup, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import App from "../src/renderer/App";
import {
  controlStatus,
  disconnectedControlStatus,
  installReleaseBridge,
  managedCommerceSnapshot,
  managedSnapshot,
  userConfigurableSnapshot,
} from "./developerReleaseFixture";

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

  it("keeps each sensitive value beside the service that owns it", async () => {
    installReleaseBridge(userConfigurableSnapshot(), {
      controlStatus: controlStatus("ready", "0123456789abcdef0123456789abcdef"),
    });
    window.history.replaceState(null, "", "/#developer/access/setup");

    render(<App />);

    const modelSection = (await screen.findByRole("heading", { name: "Model service" })).closest("section");
    expect(modelSection).not.toBeNull();
    expect(modelSection).toHaveTextContent("Upstream API key");
    expect(screen.queryByRole("heading", { name: "Deployment secrets" })).not.toBeInTheDocument();
  });

  it("prepares the Creem webhook only after Cloudflare and Creem are selected", async () => {
    const accountId = "0123456789abcdef0123456789abcdef";
    const initial = userConfigurableSnapshot();
    const save = vi.fn(async (request: unknown) => ({
      ...initial,
      revision: "c".repeat(64),
      project: (request as { project: Record<string, unknown> }).project,
    }));
    const accessRequest = vi.fn(async (operation: string) => {
      if (operation === "status") return controlStatus("ready", accountId);
      if (operation === "commerce.creem.bootstrap") return {
        state: "bootstrap_ready",
        providerId: "cloudflare-workers",
        providerVersion: "0.1.0",
        target: {
          accountId,
          deploymentId: "deployment-1",
          workerName: "com-example-agent-entitlements",
          environment: "production",
        },
        versionId: "version-setup",
        endpoint: "https://com-example-agent-entitlements.workers.dev",
        webhookUrl: "https://com-example-agent-entitlements.workers.dev/agentweave/commerce/v1/webhooks/creem",
        operationId: "4f290eb3-8712-4f7d-bde8-0a98aa95e33b",
        completedAtUnixMs: 1_700_000_000_000,
      };
      throw new Error(`Unexpected operation: ${operation}`);
    });
    installReleaseBridge(initial, {
      accessRequest,
      controlStatus: controlStatus("ready", accountId),
      save,
    });
    window.history.replaceState(null, "", "/#developer/access/setup");
    const user = userEvent.setup();

    render(<App />);
    await screen.findByRole("heading", { name: "Subscription source and usage policy" });
    expect(accessRequest).not.toHaveBeenCalledWith("commerce.creem.bootstrap", expect.anything());

    await user.click(screen.getByText("Creem"));

    expect(await screen.findByText("Webhook URL ready")).toBeInTheDocument();
    expect(screen.getByText(
      "https://com-example-agent-entitlements.workers.dev/agentweave/commerce/v1/webhooks/creem",
    )).toBeInTheDocument();
    expect(accessRequest).toHaveBeenCalledWith("commerce.creem.bootstrap", expect.objectContaining({
      expectedProjectRevision: "c".repeat(64),
    }));
    expect(screen.getAllByText("Creem API key")).toHaveLength(1);
    expect(screen.getAllByText("Creem Webhook Secret")).toHaveLength(1);
    expect(screen.queryByRole("heading", { name: "Deployment secrets" })).not.toBeInTheDocument();
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

  it("restores Creem verification guidance from an existing verified access bundle", async () => {
    const snapshot = managedCommerceSnapshot();
    installReleaseBridge(snapshot, {
      controlStatus: controlStatus("ready", "0123456789abcdef0123456789abcdef"),
    });
    window.history.replaceState(null, "", "/#developer/access/setup");

    render(<App />);

    expect(await screen.findByRole("heading", {
      name: "Complete the Creem Test path",
    })).toBeInTheDocument();
    expect(screen.getByRole("link", {
      name: "Open Subscription & billing",
    })).toHaveAttribute("href", "#settings");
    expect(screen.getByText(
      "https://example-entitlements.workers.dev/agentweave/commerce/v1/webhooks/creem",
    )).toBeInTheDocument();
  });

  it("reuses a verified Creem Worker without redeploying when configuration is reopened", async () => {
    const accountId = "0123456789abcdef0123456789abcdef";
    const snapshot = managedCommerceSnapshot();
    const accessRequest = vi.fn(async (operation: string) => {
      if (operation === "status") return controlStatus("ready", accountId);
      throw new Error(`Unexpected operation: ${operation}`);
    });
    installReleaseBridge(snapshot, { accessRequest });
    window.history.replaceState(null, "", "/#developer/access/setup");
    const user = userEvent.setup();

    render(<App />);
    await screen.findByRole("heading", { name: "Complete the Creem Test path" });
    await user.click(screen.getByRole("button", { name: /Required details/ }));

    expect(await screen.findByText("Webhook URL ready")).toBeInTheDocument();
    expect(screen.getByLabelText("Creem API key")).toBeEnabled();
    expect(screen.getByLabelText(/Creem Webhook Secret/)).toBeEnabled();
    expect(accessRequest).not.toHaveBeenCalledWith("commerce.creem.bootstrap", expect.anything());
  });

  it("shows the safe resource message for a partial access bundle inspection", async () => {
    const snapshot = managedCommerceSnapshot();
    const accountId = "0123456789abcdef0123456789abcdef";
    installReleaseBridge(snapshot, {
      accessRequest: async (operation) => {
        if (operation === "status") return controlStatus("ready", accountId);
        if (operation === "access.inspect") return {
          schemaVersion: 1,
          bundleId: "access-production",
          outcome: "partial",
          resources: {
            "model-gateway": {
              resourceId: "model-gateway",
              observation: null,
              errorCode: "remote_state_uncertain_after_timeout",
              safeMessage: "The Gateway response timed out; inspect Cloudflare before retrying.",
            },
          },
          inspectedAtUnixMs: 1_800_000_000_000,
        };
        throw new Error(`Unexpected operation: ${operation}`);
      },
    });
    window.history.replaceState(null, "", "/#developer/access/setup");
    const user = userEvent.setup();

    render(<App />);
    await user.click(await screen.findByRole("button", { name: "Inspect drift" }));

    expect(await screen.findByText(
      "The Gateway response timed out; inspect Cloudflare before retrying.",
    )).toBeInTheDocument();
    expect(screen.getByText("partial")).toBeInTheDocument();
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
