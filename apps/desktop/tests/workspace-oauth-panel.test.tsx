import { cleanup, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { I18nProvider } from "../src/renderer/i18n/I18nProvider";
import { WorkspaceOAuthPanel } from "../src/renderer/product/WorkspaceOAuthPanel";

beforeEach(() => window.localStorage.clear());

afterEach(() => {
  cleanup();
  delete window.agentWeave;
  window.localStorage.clear();
  vi.restoreAllMocks();
});

describe("Workspace OAuth panel", () => {
  it("polls a Google authorization and stores only public connector bindings", async () => {
    const request = vi.fn(async (operation: string) => {
      if (operation === "oauth.start") {
        return {
          authorizationId: "authorization-1",
          expiresAt: "2026-07-16T01:00:00Z",
          providerId: "google-workspace",
          status: "pending",
        };
      }
      if (operation === "oauth.status") {
        return {
          authorizationId: "authorization-1",
          bindings: [
            { accountId: "acct.google", connectorId: "agentweave-mail" },
            { accountId: "acct.google", connectorId: "agentweave-calendar" },
            { accountId: "acct.google", connectorId: "agentweave-contacts" },
          ],
          connectorIds: ["agentweave-mail", "agentweave-calendar", "agentweave-contacts"],
          createdAt: "2026-07-16T00:00:00Z",
          errorCode: null,
          expiresAt: "2026-07-16T01:00:00Z",
          providerId: "google-workspace",
          requestedCapabilities: ["mail", "calendar", "contacts"],
          status: "completed",
          updatedAt: "2026-07-16T00:01:00Z",
        };
      }
      throw new Error(`Unexpected operation: ${operation}`);
    });
    window.agentWeave = {
      approval: { open: vi.fn() },
      owner: {} as NonNullable<Window["agentWeave"]>["owner"],
      server: { request },
    };
    const onBindingsChanged = vi.fn();
    const user = userEvent.setup();

    render(
      <I18nProvider>
        <WorkspaceOAuthPanel onBindingsChanged={onBindingsChanged} />
      </I18nProvider>,
    );
    await user.click(screen.getAllByRole("button", { name: "connections.workspace.authorize" })[0]);

    await waitFor(() => expect(onBindingsChanged).toHaveBeenCalledOnce(), { timeout: 2_500 });
    expect(screen.getByText("acct.google")).toBeVisible();
    expect(request).toHaveBeenNthCalledWith(1, "oauth.start", {
      connectorIds: ["agentweave-mail", "agentweave-calendar", "agentweave-contacts"],
      providerId: "google-workspace",
      requestedCapabilities: ["mail", "calendar", "contacts"],
    });
    const stored = window.localStorage.getItem("agentweave.workspace.bindings.v1") ?? "";
    expect(stored).toContain("acct.google");
    expect(stored).not.toMatch(/access.?token|refresh.?token|verifier|secret/i);
  });
});
