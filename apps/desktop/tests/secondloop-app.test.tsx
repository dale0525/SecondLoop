import { cleanup, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import App from "../src/renderer/App";
import type { AgentAppHostDiscovery } from "../src/shared/hostBootstrap";
import {
  hostDiscoveryFixture,
  installHostBootstrap,
} from "./hostBootstrapFixture";

class TestResizeObserver implements ResizeObserver {
  disconnect(): void {}
  observe(): void {}
  unobserve(): void {}
}

beforeEach(() => {
  vi.stubGlobal("ResizeObserver", TestResizeObserver);
});

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
    await waitFor(() => {
      expect(screen.getByRole("button", { name: "Send message" })).toBeDisabled();
    });

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

  it("onboards Mail through the trusted configuration flow and clears the password", async () => {
    installSecondLoopBootstrap();
    const mail = stubMailOnboardingFetch();
    window.history.replaceState(null, "", "/#connections");
    const user = userEvent.setup();
    render(<App />);

    await user.click(await screen.findByRole("button", {
      name: /Add account|connections\.mailOnboarding\.add$/,
    }));
    await user.type(screen.getByLabelText(
      /Email address|connections\.mailOnboarding\.email/,
    ), "user@example.test");
    await user.type(screen.getByLabelText(
      /App password|connections\.mailOnboarding\.password/,
    ), "one-time-password-marker");
    await user.click(screen.getByRole("button", {
      name: /Save and test|connections\.mailOnboarding\.saveAndTest/,
    }));

    await waitFor(() => expect(mail.saved).not.toBeNull());
    expect(mail.saved?.password).toBe("one-time-password-marker");
    await waitFor(() => {
      expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
    });
    expect(document.body).not.toHaveTextContent("one-time-password-marker");
    expect((await screen.findAllByText("user@example.test")).length).toBeGreaterThan(0);
    expect(mail.fetch.mock.calls.some(([input, init]) => (
      String(input).includes("/foundation/mail/accounts/") && init?.method === "POST"
    ))).toBe(true);
  });

  it("keeps editable Mail fields but clears the password after a failed live test", async () => {
    installSecondLoopBootstrap();
    const mail = stubMailOnboardingFetch({ failConnect: true });
    window.history.replaceState(null, "", "/#connections");
    const user = userEvent.setup();
    render(<App />);

    await user.click(await screen.findByRole("button", {
      name: /Add account|connections\.mailOnboarding\.add$/,
    }));
    const email = screen.getByLabelText(
      /Email address|connections\.mailOnboarding\.email/,
    );
    const password = screen.getByLabelText(
      /App password|connections\.mailOnboarding\.password/,
    );
    await user.type(email, "retry@example.test");
    await user.type(password, "failed-test-secret");
    await user.click(screen.getByRole("button", {
      name: /Save and test|connections\.mailOnboarding\.saveAndTest/,
    }));

    expect(await screen.findByRole("alert"))
      .toHaveTextContent(/The settings were saved|connections\.mailOnboarding\.testFailed/);
    expect(email).toHaveValue("retry@example.test");
    expect(password).toHaveValue("");
    expect(mail.saved?.password).toBe("failed-test-secret");
    expect(screen.getByRole("button", {
      name: /Test again|connections\.mailOnboarding\.retryTest/,
    })).toBeEnabled();
  });

  it("edits a Mail account only with an explicit credential rotation", async () => {
    installSecondLoopBootstrap();
    const mail = stubMailOnboardingFetch({ initialConfiguration: mailConfigurationFixture() });
    window.history.replaceState(null, "", "/#connections");
    const user = userEvent.setup();
    render(<App />);

    await user.click(await screen.findByRole("button", {
      name: /Edit|connections\.mailOnboarding\.edit/,
    }));
    expect(screen.getByLabelText(
      /Email address|connections\.mailOnboarding\.email/,
    )).toHaveValue("user@example.test");
    const password = screen.getByLabelText(
      /App password|connections\.mailOnboarding\.password/,
    );
    expect(password).toHaveValue("");
    await user.type(password, "rotated-secret");
    await user.click(screen.getByRole("button", {
      name: /Save and test|connections\.mailOnboarding\.saveAndTest/,
    }));

    await waitFor(() => expect(screen.queryByRole("dialog")).not.toBeInTheDocument());
    expect(mail.saved?.password).toBe("rotated-secret");
    expect(mail.saved).not.toHaveProperty("id");
  });

  it("removes Mail settings and credentials only after confirmation", async () => {
    installSecondLoopBootstrap();
    const mail = stubMailOnboardingFetch({ initialConfiguration: mailConfigurationFixture() });
    window.history.replaceState(null, "", "/#connections");
    const user = userEvent.setup();
    render(<App />);

    await user.click(await screen.findByRole("button", {
      name: /Remove|connections\.mailOnboarding\.remove/,
    }));
    expect(screen.getByRole("dialog")).toBeVisible();
    expect(mail.deleted).toBe(false);
    await user.click(screen.getByRole("button", {
      name: /Remove account|connections\.mailOnboarding\.confirmRemove/,
    }));

    await waitFor(() => expect(mail.deleted).toBe(true));
    expect(await screen.findByText(
      /No Mail account is configured|connections\.mailOnboarding\.emptyTitle/,
    )).toBeVisible();
  });

  it("exports and restores encrypted data through the trusted Desktop bridge", async () => {
    const exportBackup = vi.fn(async () => ({
      bytes: 4096,
      createdAt: "2026-07-14T10:00:00Z",
      exported: true as const,
      sha256: "a".repeat(64),
    }));
    const restoreBackup = vi.fn(async () => ({
      accepted: true as const,
      backup: {
        appId: "com.secondloop.secretary",
        createdAt: "2026-07-14T10:00:00Z",
        envelopeSha256: "b".repeat(64),
        plaintextBytes: 2048,
        plaintextSha256: "c".repeat(64),
      },
      restarted: true as const,
    }));
    window.agentWeave = {
      approval: { open: async () => { throw new Error("unavailable"); } },
      dataProtection: {
        exportBackup,
        restoreBackup,
        status: async () => ({
          atRestEncryption: "not_provided",
          backupEncryption: "aes-256-gcm",
          backupFormat: "agentweave-backup-v1",
          enabled: true,
          pendingRestart: false,
          restoreRollbackAvailable: false,
        }),
      },
      owner: {} as NonNullable<Window["agentWeave"]>["owner"],
    };
    installSecondLoopBootstrap();
    stubFoundationFetch();
    const user = userEvent.setup();
    const { container } = render(<App />);

    await waitFor(() => expect(window.location.hash).toBe("#today"));
    const settings = container.querySelectorAll<HTMLButtonElement>(
      ".secondloop-sidebar .secondloop-nav-item",
    )[5];
    await user.click(settings);
    expect(await screen.findByText("settings.dataProtection.encryptedBackupReady"))
      .toBeVisible();

    await user.click(screen.getByRole("button", { name: "settings.dataProtection.export" }));
    await waitFor(() => expect(exportBackup).toHaveBeenCalledOnce());
    expect(screen.getByText("settings.dataProtection.exported")).toBeVisible();

    await user.click(screen.getByRole("button", { name: "settings.dataProtection.restore" }));
    await user.click(screen.getByRole("button", { name: "settings.dataProtection.confirmRestore" }));
    await waitFor(() => expect(restoreBackup).toHaveBeenCalledOnce());
    expect(screen.getByText("settings.dataProtection.restored")).toBeVisible();
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

  it("shows authoritative Calendar events, tasks, and schedules and completes a task once", async () => {
    installSecondLoopBootstrap();
    const fetch = stubTodayWorkflowFetch();
    const user = userEvent.setup();
    render(<App />);

    expect(await screen.findByText("Prepare the briefing")).toBeInTheDocument();
    expect(screen.getByText("Morning reminder")).toBeInTheDocument();
    expect(screen.getByText("Calendar review")).toBeInTheDocument();
    expect(screen.getByText("today.sourceTasks · today.sourceStatus.ready")).toBeInTheDocument();
    expect(screen.getByText("today.sourceCalendar · today.sourceStatus.ready")).toBeInTheDocument();
    expect(screen.getByText("today.sourceContacts · today.sourceStatus.ready")).toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: "today.completeTask" }));

    await waitFor(() => expect(fetch.mock.calls.some(([input, init]) => (
      String(input).includes("/foundation/tasks/task-1/status")
      && init?.method === "POST"
    ))).toBe(true));
    expect(screen.queryByText("Prepare the briefing")).not.toBeInTheDocument();
  });

  it("captures one task and one independently scheduled reminder", async () => {
    installSecondLoopBootstrap();
    const fetch = stubTodayWorkflowFetch();
    const user = userEvent.setup();
    render(<App />);

    await user.click(await screen.findByRole("button", { name: "today.addTask" }));
    await user.type(screen.getByPlaceholderText("today.taskPlaceholder"), "Reply to Ada");
    await user.click(screen.getByRole("button", { name: "today.saveTask" }));

    await waitFor(() => {
      expect(fetch.mock.calls.filter(([input, init]) => (
        String(input).endsWith("/foundation/tasks") && init?.method === "POST"
      ))).toHaveLength(1);
      expect(fetch.mock.calls.filter(([input, init]) => (
        String(input).endsWith("/foundation/schedules") && init?.method === "POST"
      ))).toHaveLength(1);
    });
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
    features: [...base.features, "attachments", "data-protection", "local-notifications"],
    requirements: {
      ...base.requirements,
      capabilities: [
        ...base.requirements.capabilities,
        "attachments",
        "data-protection",
        "scheduler",
      ],
      packages: [
        ...base.requirements.packages,
        { id: "agentweave.foundation.documents", version: "=0.2.0" },
      ],
      runtimeTools: [
        ...base.requirements.runtimeTools,
        "attachment_get",
        "attachment_read",
        "notification_enqueue",
      ],
    },
  };
  installHostBootstrap(discovery);
}

function stubFoundationFetch(): void {
  vi.stubGlobal("fetch", vi.fn(async (input: string | URL | Request) => {
    const url = String(input);
    return jsonResponse(url.includes("/foundation/tasks?")
      ? { tasks: [], nextCursor: null }
      : []);
  }));
}

function stubVerticalSliceFetch() {
  const fetch = vi.fn(async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    if (url.includes("/foundation/memory?")) return jsonResponse([memoryFixture()]);
    if (url.endsWith("/foundation/mail/account-configurations")) return jsonResponse([]);
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
    if (url.includes("/foundation/tasks?")) return jsonResponse({ tasks: [], nextCursor: null });
    if (url.includes("/foundation/schedules?")) return jsonResponse([]);
    if (url.includes("/foundation/calendar/events?")) return jsonResponse([]);
    if (url.includes("/foundation/contacts?")) return jsonResponse([]);
    throw new Error(`Unexpected request: ${init?.method ?? "GET"} ${url}`);
  });
  vi.stubGlobal("fetch", fetch);
  return fetch;
}

function stubMailOnboardingFetch({
  failConnect = false,
  initialConfiguration = null,
}: {
  failConnect?: boolean;
  initialConfiguration?: Record<string, unknown> | null;
} = {}) {
  let configuration = initialConfiguration;
  const state: {
    deleted: boolean;
    saved: Record<string, unknown> | null;
    fetch: ReturnType<typeof vi.fn>;
  } = {
    deleted: false,
    saved: null,
    fetch: vi.fn(),
  };
  state.fetch.mockImplementation(async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    if (url.endsWith("/foundation/mail/account-configurations") && init?.method !== "PUT") {
      return jsonResponse(configuration ? [configuration] : []);
    }
    if (url.includes("/foundation/mail/account-configurations/") && init?.method === "PUT") {
      const body = JSON.parse(String(init.body)) as Record<string, unknown>;
      const id = decodeURIComponent(url.split("/").at(-1) ?? "primary");
      state.saved = body;
      configuration = { ...body, id, credentialConfigured: true };
      return jsonResponse(configuration);
    }
    if (url.includes("/foundation/mail/account-configurations/") && init?.method === "DELETE") {
      configuration = null;
      state.deleted = true;
      return jsonResponse({ deleted: true });
    }
    if (url.endsWith("/foundation/mail/accounts")) {
      return jsonResponse(configuration ? [{
        addresses: [],
        displayName: configuration.displayName,
        id: configuration.id,
        primaryAddress: {
          address: configuration.primaryAddress,
          name: configuration.primaryName ?? null,
        },
      }] : []);
    }
    if (url.includes("/foundation/mail/accounts/") && init?.method === "POST" && failConnect) {
      return new Response(JSON.stringify({ error: "connection failed" }), {
        headers: { "content-type": "application/json" },
        status: 503,
      });
    }
    if (url.includes("/foundation/mail/accounts/")) {
      const account = {
        addresses: [],
        displayName: configuration?.displayName ?? "Gmail",
        id: configuration?.id ?? "primary",
        primaryAddress: {
          address: configuration?.primaryAddress ?? "user@example.test",
          name: configuration?.primaryName ?? null,
        },
      };
      return jsonResponse({ account, detail: null, state: "connected" });
    }
    if (url.includes("/foundation/tasks?")) {
      return jsonResponse({ tasks: [], nextCursor: null });
    }
    if (url.includes("/foundation/schedules?")) return jsonResponse([]);
    if (url.endsWith("/foundation/actions")) return jsonResponse([]);
    if (url.includes("/foundation/calendar/events?")) return jsonResponse([]);
    if (url.includes("/foundation/contacts?")) return jsonResponse([]);
    throw new Error(`Unexpected request: ${init?.method ?? "GET"} ${url}`);
  });
  vi.stubGlobal("fetch", state.fetch);
  return state;
}

function mailConfigurationFixture(): Record<string, unknown> {
  return {
    archiveMailbox: "Archive",
    credentialConfigured: true,
    displayName: "Work Mail",
    draftsMailbox: "Drafts",
    id: "primary",
    imapHost: "imap.example.test",
    imapPort: 993,
    imapTls: "implicit",
    primaryAddress: "user@example.test",
    primaryName: "Local User",
    sentMailbox: "Sent",
    smtpHost: "smtp.example.test",
    smtpPort: 587,
    smtpTls: "start_tls",
    trashMailbox: "Trash",
    username: "user@example.test",
  };
}

function stubTodayWorkflowFetch() {
  const due = new Date(Date.now() + 30 * 60_000).toISOString();
  const eventEnd = new Date(Date.now() + 60 * 60_000).toISOString();
  const fetch = vi.fn(async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    if (url.includes("/foundation/tasks?")) {
      return jsonResponse({ tasks: [taskFixture(due)], nextCursor: null });
    }
    if (url.includes("/foundation/schedules?")) return jsonResponse([scheduleFixture(due)]);
    if (url.endsWith("/foundation/tasks/task-1/status") && init?.method === "POST") {
      return jsonResponse({ ...taskFixture(due), status: "completed", version: 2 });
    }
    if (url.endsWith("/foundation/tasks") && init?.method === "POST") {
      return jsonResponse({ ...taskFixture(due), id: "task-created" });
    }
    if (url.endsWith("/foundation/schedules") && init?.method === "POST") {
      return jsonResponse({ ...scheduleFixture(due), id: "schedule-created" });
    }
    if (url.endsWith("/foundation/actions")) return jsonResponse([]);
    if (url.endsWith("/foundation/mail/accounts")) return jsonResponse([accountFixture()]);
    if (url.includes("/foundation/calendar/events?")) {
      return jsonResponse([calendarEventFixture(due, eventEnd)]);
    }
    if (url.includes("/foundation/contacts?")) return jsonResponse([]);
    throw new Error(`Unexpected request: ${init?.method ?? "GET"} ${url}`);
  });
  vi.stubGlobal("fetch", fetch);
  return fetch;
}

function calendarEventFixture(start: string, end: string) {
  return {
    content: {
      attendees: [],
      calendarId: "primary",
      description: null,
      end,
      location: "Studio",
      recurrence: null,
      start,
      timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      title: "Calendar review",
    },
    id: "event-1",
    providerId: "provider-event-1",
    status: "confirmed",
    updatedAt: new Date().toISOString(),
    version: 1,
  };
}

function taskFixture(dueAt: string) {
  return {
    id: "task-1",
    content: {
      title: "Prepare the briefing",
      notes: null,
      dueAt,
      timezone: "Asia/Shanghai",
      recurrence: null,
      priority: "high",
      tags: [],
    },
    status: "open",
    version: 1,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    completedAt: null,
  };
}

function scheduleFixture(nextRunAt: string) {
  return {
    id: "schedule-1",
    request: {
      app_id: "com.secondloop.secretary",
      tenant_id: "local",
      user_id: "local-user",
      name: "Morning reminder",
      schedule: { kind: "one_shot", at: nextRunAt },
      misfire: { kind: "fire_once" },
      payload: {},
    },
    status: "active",
    next_run_at: nextRunAt,
    version: 1,
  };
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
