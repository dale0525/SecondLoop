import { cleanup, render, screen, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

import App from "../src/renderer/App";
import { hostDiscoveryFixture, installHostBootstrap } from "./hostBootstrapFixture";

describe("app-managed model settings", () => {
  afterEach(() => {
    cleanup();
    window.localStorage.clear();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
    window.history.replaceState(null, "", "/");
    delete window.agentWeave;
  });

  it("does not expose model settings for an app-managed release", async () => {
    installHostBootstrap(hostDiscoveryFixture({
      access: {
        modelAccess: {
          configurationPolicy: "app_managed",
          profile: {
            authentication: "user_identity",
            baseUrl: "https://gateway.example.test/v1",
            endpointType: "responses",
            headers: {},
            modelName: "managed-model",
            providerId: "example.gateway",
          },
        },
        identity: {
          mode: "required",
          provider: {
            id: "agentweave.identity.oidc",
            publicConfig: { issuer: "https://identity.example.test" },
            version: "^1.0.0",
          },
        },
        entitlements: {
          mode: "required",
          provider: {
            id: "agentweave.entitlements.http",
            publicConfig: { endpoint: "https://access.example.test" },
            version: "^1.0.0",
          },
        },
      },
    }));
    window.history.replaceState(null, "", "/#settings");

    render(<App />);

    await waitFor(() => expect(document.title).toBe("Secretary"));
    expect(screen.queryByRole("heading", { name: "Model connection" })).not.toBeInTheDocument();
    expect(screen.queryByLabelText("Base URL")).not.toBeInTheDocument();
    expect(screen.queryByLabelText("API key")).not.toBeInTheDocument();
    expect(screen.queryByLabelText("Model name")).not.toBeInTheDocument();
  });

  it("keeps user-facing settings free of skill controls", () => {
    window.history.replaceState(null, "", "/#settings");

    render(<App />);

    expect(screen.queryByRole("switch")).not.toBeInTheDocument();
    expect(screen.queryByText(/skill/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/tool/i)).not.toBeInTheDocument();
  });
});
