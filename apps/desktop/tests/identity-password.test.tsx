import { cleanup, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, expect, it, vi } from "vitest";

import App from "../src/renderer/App";
import { hostDiscoveryFixture, installHostBootstrap } from "./hostBootstrapFixture";

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
  delete window.agentWeave;
});

it("renders Firebase email login and sends credentials through the identity bridge", async () => {
  installHostBootstrap(hostDiscoveryFixture({
    access: {
      modelAccess: { configurationPolicy: "app_managed", profile: null },
      identity: {
        mode: "required",
        provider: {
          id: "agentweave.identity.firebase",
          version: "^0.1.0",
          publicConfig: {
            projectId: "sample-project-123",
            firebaseWebKey: "public-web-key",
            webApplicationId: "1:123:web:abc",
          },
        },
      },
      entitlements: { mode: "disabled", provider: null },
    },
  }));
  const password = vi.fn(async () => ({
    state: "signed_in" as const,
    account: {
      id: `usr_${"a".repeat(64)}`,
      authenticatedAt: new Date().toISOString(),
      expiresAt: new Date(Date.now() + 60_000).toISOString(),
    },
  }));
  const status = vi.fn(async () => ({ state: "signed_out" as const, account: null }));
  if (!window.agentWeave) throw new Error("Host bootstrap is unavailable");
  window.agentWeave.identity = {
    logout: async () => ({ state: "signed_out", account: null }),
    password,
    start: async () => ({ state: "waiting", expiresAt: new Date().toISOString() }),
    status,
  };
  const user = userEvent.setup();

  render(<App />);

  await screen.findByRole("textbox", { name: "Email" });
  await waitFor(() => expect(status).toHaveBeenCalled());
  const email = screen.getByRole("textbox", { name: "Email" });
  await user.type(email, "person@example.test");
  await user.type(screen.getByLabelText("Password"), "password-sentinel");
  await user.click(screen.getByRole("button", { name: "Sign in with email" }));

  await waitFor(() => {
    expect(password).toHaveBeenCalledWith({
      email: "person@example.test",
      password: "password-sentinel",
    });
  });
});
