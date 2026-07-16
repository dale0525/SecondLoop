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

  it("renders canonical Calendar and Contacts previews and fences unknown actions", async () => {
    const fetch = mockFetch([jsonResponse([
      calendarAction(),
      contactAction(),
      unknownAction(),
    ])]);
    const user = userEvent.setup();

    render(<FoundationActions onBack={() => undefined} />);

    expect(await screen.findByRole("heading", { name: "Board review" })).toBeVisible();
    expect(screen.getByText("Create event")).toBeVisible();
    expect(screen.getByText("Asia/Shanghai")).toBeVisible();
    expect(screen.getByText("Ada <ada@example.test>")).toBeVisible();

    await user.click(screen.getByRole("button", { name: /Ada Lovelace/ }));
    expect(await screen.findByRole("heading", { name: "Ada Lovelace" })).toBeVisible();
    expect(screen.getByText("work: ada@example.test")).toBeVisible();
    expect(screen.getByText("Analytical Engine")).toBeVisible();

    await user.click(screen.getByRole("button", { name: /custom\.external\.write/ }));
    expect(await screen.findByRole("heading", { name: "custom.external.write" })).toBeVisible();
    expect(screen.getByText(/Only its immutable binding is shown/)).toBeVisible();
    expect(screen.getByText(/Approval is unavailable/)).toBeVisible();
    expect(screen.queryByRole("button", { name: "Approve once" })).not.toBeInTheDocument();
    expect(fetch).toHaveBeenCalledTimes(1);
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

function calendarAction() {
  return actionWith({
    actionName: "calendar.event.create",
    id: "calendar",
    preview: {
      accountId: "acct.primary",
      attendeeVisible: true,
      conflicts: [],
      content: {
        attendees: [{ address: "ada@example.test", displayName: "Ada", response: "needs_action" }],
        calendarId: "primary",
        description: null,
        end: "2026-07-16T11:00:00Z",
        location: "Studio",
        recurrence: null,
        start: "2026-07-16T10:00:00Z",
        timezone: "Asia/Shanghai",
        title: "Board review",
      },
      eventId: null,
      expectedVersion: null,
      idempotencyKey: "calendar-create-1",
      kind: "create",
      previewHash: "d".repeat(64),
      previewId: "calendar-preview-1",
    },
    resourceTarget: "calendar:primary",
  });
}

function contactAction() {
  return actionWith({
    actionName: "contacts.contact.update",
    id: "contact",
    preview: {
      accountId: "acct.primary",
      contactId: "contact-1",
      expectedVersion: 2,
      idempotencyKey: "contact-update-1",
      previewHash: "e".repeat(64),
      previewId: "contact-preview-1",
      replacement: {
        displayName: "Ada Lovelace",
        id: "contact-1",
        identities: [{ kind: "email", label: "work", value: "ada@example.test" }],
        organization: "Analytical Engine",
        providerId: "people/ada",
        relationship: "Collaborator",
        updatedAt: "2026-07-16T00:00:00Z",
        version: 3,
      },
    },
    resourceTarget: "contact:contact-1",
  });
}

function unknownAction() {
  return actionWith({
    actionName: "custom.external.write",
    id: "unknown",
    preview: { subject: "Fields must not be guessed" },
    resourceTarget: "custom:resource-1",
  });
}

function actionWith({ actionName, id, preview, resourceTarget }: {
  actionName: string;
  id: string;
  preview: unknown;
  resourceTarget: string;
}) {
  return {
    action: {
      action_id: `${id}-action`,
      action_name: actionName,
      arguments_sha256: "a".repeat(64),
      idempotency_key: `${id}-idempotency`,
      last_error: null,
      resource_target: resourceTarget,
      result: null,
      status: "waiting_approval",
    },
    approval: {
      approval_id: `${id}-approval`,
      binding: {
        action_name: actionName,
        arguments_sha256: "a".repeat(64),
        expires_at: "2026-07-16T12:00:00Z",
        resource_target: resourceTarget,
        risk: "external_write",
        risk_summary: `Review ${actionName}`,
      },
      status: "pending",
    },
    preview,
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
