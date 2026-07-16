import { cleanup, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";

import { Accounts } from "../src/renderer/screens/Accounts";
import { Memory } from "../src/renderer/screens/Memory";
import { FoundationActions } from "../src/renderer/screens/FoundationActions";

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe("Foundation host screens", () => {
  it("loads an account and performs an explicit trusted-host disconnect", async () => {
    const fetch = mockFetch([
      jsonResponse([account()]),
      jsonResponse({ account: account(), state: "connected", detail: null }),
      jsonResponse({ account: account(), state: "authentication_required", detail: "Disconnected" })
    ]);
    const user = userEvent.setup();

    render(<Accounts onBack={() => undefined} />);

    expect(await screen.findByRole("heading", { name: "Work Mail" })).toBeVisible();
    expect(screen.getByText("Host vault only")).toBeVisible();
    await user.click(screen.getByRole("button", { name: "Disconnect" }));

    expect(await screen.findByText("Sign-in required")).toBeVisible();
    expect(fetch).toHaveBeenLastCalledWith(
      "/__agentweave/foundation/mail/accounts/primary",
      expect.objectContaining({ method: "DELETE" })
    );
  });

  it("shows provenance and requires confirmation before forgetting", async () => {
    const fetch = mockFetch([
      jsonResponse([memory()]),
      jsonResponse({ action: "forgotten", record: { ...memory(), state: "tombstoned" } }),
      jsonResponse([])
    ]);
    const user = userEvent.setup();

    render(<Memory onBack={() => undefined} />);

    expect(
      (await screen.findAllByText("Meetings default to the afternoon")).length,
    ).toBeGreaterThan(0);
    expect(screen.getAllByText("Explicit user action").length).toBeGreaterThan(0);
    const forgetButtons = screen.getAllByRole("button", { name: "Forget" });
    await user.click(forgetButtons[0]);
    expect(screen.getByRole("heading", { name: "Forget this memory?" })).toBeVisible();
    await user.click(screen.getByRole("button", { name: "Forget permanently" }));

    await waitFor(() => expect(screen.getByText("Nothing committed here")).toBeVisible());
    expect(fetch).toHaveBeenCalledWith(
      expect.stringContaining("/foundation/memory/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"),
      expect.objectContaining({ method: "DELETE" })
    );
  });

  it("renders an authoritative Mail preview and resolves it once", async () => {
    const pending = foundationAction();
    const fetch = mockFetch([
      jsonResponse([pending]),
      jsonResponse({
        approval: { ...pending.approval, status: "consumed" },
        action: { ...pending.action, status: "succeeded", result: { state: "delivered" } },
        connectorResult: { replayed: false }
      })
    ]);
    const user = userEvent.setup();

    render(<FoundationActions onBack={() => undefined} />);

    expect(await screen.findByRole("heading", { name: "Quarterly review" })).toBeVisible();
    expect(screen.getByText("Recipient <recipient@example.test>")).toBeVisible();
    expect(screen.getByText("Send from primary to recipient@example.test")).toBeVisible();
    await user.click(screen.getByRole("button", { name: "Approve once" }));

    await waitFor(() => expect(screen.getAllByText("succeeded").length).toBeGreaterThan(0));
    expect(fetch).toHaveBeenLastCalledWith(
      expect.stringContaining(`/foundation/actions/${pending.approval.approval_id}`),
      expect.objectContaining({
        body: JSON.stringify({ decision: "approve_once" }),
        method: "POST"
      })
    );
  });
});

function account() {
  return {
    id: "primary",
    displayName: "Work Mail",
    primaryAddress: { name: "User", address: "user@example.test" },
    addresses: []
  };
}

function memory() {
  return {
    schemaVersion: 1,
    id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    kind: "user.preference",
    value: { text: "Meetings default to the afternoon", attributes: {} },
    evidence: [{
      source: "explicit_user_action",
      sourceId: "session-1",
      excerpt: "Remember this preference",
      observedAt: "2026-07-14T08:00:00Z"
    }],
    confidence: 10000,
    sensitivity: "personal",
    retention: { mode: "persistent" },
    state: "committed",
    version: 2,
    conflictKey: "meeting-time",
    supersedes: null,
    supersededBy: null,
    createdAt: "2026-07-14T08:00:00Z",
    updatedAt: "2026-07-14T08:00:00Z"
  };
}

function foundationAction() {
  return {
    approval: {
      approval_id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
      binding: {
        action_name: "mail_send",
        arguments_sha256: "a".repeat(64),
        expires_at: "2026-07-14T09:00:00Z",
        resource_target: "mail-account:primary",
        risk: "external_write",
        risk_summary: "Send from primary to recipient@example.test"
      },
      status: "pending"
    },
    action: {
      action_id: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
      action_name: "mail_send",
      arguments_sha256: "a".repeat(64),
      idempotency_key: "desktop-send-1",
      last_error: null,
      resource_target: "mail-account:primary",
      result: null,
      status: "waiting_approval"
    },
    preview: {
      id: "preview-1",
      accountId: "primary",
      draftId: "draft-1",
      draftRevision: 2,
      from: { name: "Local User", address: "local@example.test" },
      to: [{ name: "Recipient", address: "recipient@example.test" }],
      cc: [],
      bcc: [],
      subject: "Quarterly review",
      bodySha256: "b".repeat(64),
      attachments: [],
      previewHash: "c".repeat(64)
    }
  };
}

function jsonResponse(value: unknown): Response {
  return new Response(JSON.stringify(value), {
    status: 200,
    headers: { "Content-Type": "application/json" }
  });
}

function mockFetch(responses: Response[]) {
  const fetch = vi.fn(async () => {
    const response = responses.shift();
    if (!response) throw new Error("Unexpected fetch");
    return response;
  });
  vi.stubGlobal("fetch", fetch);
  return fetch;
}
