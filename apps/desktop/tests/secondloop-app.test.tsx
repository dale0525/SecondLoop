import { cleanup, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";

import App from "../src/renderer/App";
import type { AgentAppHostDiscovery } from "../src/shared/hostBootstrap";
import {
  hostDiscoveryFixture,
  installHostBootstrap,
} from "./hostBootstrapFixture";

describe("SecondLoop product shell", () => {
  afterEach(() => {
    cleanup();
    delete window.agentWeave;
    window.history.replaceState(null, "", "/");
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it("opens Today by default and navigates all six product routes", async () => {
    installSecondLoopBootstrap();
    stubFoundationFetch();
    const user = userEvent.setup();
    const { container } = render(<App />);

    await waitFor(() => expect(window.location.hash).toBe("#today"));
    expect(container.querySelector(".today-screen")).toBeInTheDocument();

    const desktopRoutes = Array.from(
      container.querySelectorAll<HTMLButtonElement>(
        ".secondloop-sidebar .secondloop-nav-item",
      ),
    );
    expect(desktopRoutes).toHaveLength(6);

    await user.click(desktopRoutes[1]);
    expect(window.location.hash).toBe("#chat");
    expect(container.querySelector(".chat-shell")).toBeInTheDocument();

    await user.click(desktopRoutes[2]);
    expect(window.location.hash).toBe("#actions");
    expect(container.querySelector(".actions-layout")).toBeInTheDocument();

    await user.click(desktopRoutes[3]);
    expect(window.location.hash).toBe("#memory");
    expect(container.querySelector(".memory-layout")).toBeInTheDocument();

    await user.click(desktopRoutes[4]);
    expect(window.location.hash).toBe("#connections");
    expect(container.querySelector(".connections-screen")).toBeInTheDocument();

    await user.click(desktopRoutes[5]);
    expect(window.location.hash).toBe("#settings");
    expect(container.querySelector(".settings-screen")).toBeInTheDocument();
  });

  it("keeps developer surfaces closed by trusted product policy", async () => {
    installSecondLoopBootstrap();
    stubFoundationFetch();
    window.history.replaceState(null, "", "/#developer");
    const { container } = render(<App />);

    await waitFor(() => expect(window.location.hash).toBe("#settings"));
    expect(container.querySelector(".settings-screen")).toBeInTheDocument();
    expect(container.querySelector(".developer-screen")).not.toBeInTheDocument();
    expect(container.querySelector(".owner-skills-screen")).not.toBeInTheDocument();
  });

  it("opens Connections and Settings from the narrow More sheet", async () => {
    installSecondLoopBootstrap();
    stubFoundationFetch();
    const user = userEvent.setup();
    const { container } = render(<App />);

    await waitFor(() => expect(window.location.hash).toBe("#today"));
    const more = container.querySelector<HTMLButtonElement>(
      ".secondloop-mobile-nav-item",
    );
    expect(more).not.toBeNull();
    await user.click(more!);

    const sheetItems = Array.from(
      document.querySelectorAll<HTMLButtonElement>(".secondloop-more-item"),
    );
    expect(sheetItems).toHaveLength(2);
    await user.click(sheetItems[0]);

    expect(window.location.hash).toBe("#connections");
    expect(container.querySelector(".connections-screen")).toBeInTheDocument();
  });

  it("keeps the Memory, Mail, and approval workflow authoritative and single-use", async () => {
    installSecondLoopBootstrap();
    const fetch = stubVerticalSliceFetch();
    window.history.replaceState(null, "", "/#memory");
    const user = userEvent.setup();
    const { container } = render(<App />);

    expect((await screen.findAllByText("Meetings default to the afternoon")).length)
      .toBeGreaterThan(0);
    expect(screen.getByText("Explicit user action")).toBeInTheDocument();

    const desktopRoutes = Array.from(
      container.querySelectorAll<HTMLButtonElement>(
        ".secondloop-sidebar .secondloop-nav-item",
      ),
    );
    await user.click(desktopRoutes[4]);
    expect((await screen.findAllByText("Work Mail")).length).toBeGreaterThan(0);
    expect(screen.getAllByText("user@example.test").length).toBeGreaterThan(0);

    await user.click(desktopRoutes[2]);
    expect((await screen.findAllByText("Quarterly review")).length).toBeGreaterThan(0);
    const approve = container.querySelector<HTMLButtonElement>(
      ".action-decision-row button:last-of-type",
    );
    expect(approve).not.toBeNull();
    await user.click(approve!);

    await waitFor(() => {
      expect(container.querySelector(".action-terminal-note")).toBeInTheDocument();
    });
    expect(container.querySelector(".action-decision-row")).not.toBeInTheDocument();
    expect(fetch.mock.calls.filter(([input, init]) => (
      String(input).includes("/foundation/actions/approval-1")
      && init?.method === "POST"
    ))).toHaveLength(1);
  });
});

function installSecondLoopBootstrap(): void {
  const base = hostDiscoveryFixture({ skillManagement: "disabled" });
  const discovery: AgentAppHostDiscovery = {
    ...base,
    identity: {
      ...base.identity,
      appId: "com.secondloop.secretary",
      packageId: "com.secondloop.app",
      displayName: "SecondLoop",
      shortName: "SecondLoop",
    },
  };
  installHostBootstrap(discovery);
}

function stubFoundationFetch(): void {
  vi.stubGlobal("fetch", vi.fn(async () => new Response("[]", {
    status: 200,
    headers: { "Content-Type": "application/json" },
  })));
}

function stubVerticalSliceFetch() {
  const fetch = vi.fn(async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    if (url.includes("/foundation/memory?")) return jsonResponse([memoryFixture()]);
    if (url.endsWith("/foundation/mail/accounts")) return jsonResponse([accountFixture()]);
    if (url.endsWith("/foundation/mail/accounts/primary")) {
      return jsonResponse({ account: accountFixture(), detail: null, state: "connected" });
    }
    if (url.endsWith("/foundation/actions/approval-1") && init?.method === "POST") {
      const action = actionFixture();
      return jsonResponse({
        action: { ...action.action, status: "succeeded" },
        approval: { ...action.approval, status: "consumed" },
        connectorResult: { replayed: false },
      });
    }
    if (url.endsWith("/foundation/actions")) return jsonResponse([actionFixture()]);
    throw new Error(`Unexpected request: ${init?.method ?? "GET"} ${url}`);
  });
  vi.stubGlobal("fetch", fetch);
  return fetch;
}

function accountFixture() {
  return {
    addresses: [],
    displayName: "Work Mail",
    id: "primary",
    primaryAddress: { address: "user@example.test", name: "User" },
  };
}

function memoryFixture() {
  return {
    confidence: 10000,
    conflictKey: "meeting-time",
    createdAt: "2026-07-14T08:00:00Z",
    evidence: [{
      excerpt: "Remember this preference",
      observedAt: "2026-07-14T08:00:00Z",
      source: "explicit_user_action",
      sourceId: "session-1",
    }],
    id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    kind: "user.preference",
    retention: { mode: "persistent" },
    schemaVersion: 1,
    sensitivity: "personal",
    state: "committed",
    supersededBy: null,
    supersedes: null,
    updatedAt: "2026-07-14T08:00:00Z",
    value: { attributes: {}, text: "Meetings default to the afternoon" },
    version: 2,
  };
}

function actionFixture() {
  return {
    action: {
      action_id: "action-1",
      action_name: "mail_send",
      arguments_sha256: "a".repeat(64),
      idempotency_key: "secondloop-send-1",
      last_error: null,
      resource_target: "mail-account:primary",
      result: null,
      status: "waiting_approval",
    },
    approval: {
      approval_id: "approval-1",
      binding: {
        action_name: "mail_send",
        arguments_sha256: "a".repeat(64),
        expires_at: "2026-07-14T09:00:00Z",
        resource_target: "mail-account:primary",
        risk: "external_write",
        risk_summary: "Send from primary to recipient@example.test",
      },
      status: "pending",
    },
    preview: {
      accountId: "primary",
      attachments: [],
      bcc: [],
      bodySha256: "b".repeat(64),
      cc: [],
      draftId: "draft-1",
      draftRevision: 2,
      from: { address: "local@example.test", name: "Local User" },
      id: "preview-1",
      previewHash: "c".repeat(64),
      subject: "Quarterly review",
      to: [{ address: "recipient@example.test", name: "Recipient" }],
    },
  };
}

function jsonResponse(value: unknown): Response {
  return new Response(JSON.stringify(value), {
    headers: { "Content-Type": "application/json" },
    status: 200,
  });
}
