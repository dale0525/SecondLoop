// @vitest-environment node

import { describe, expect, it, vi } from "vitest";

import { registerSidecarApiController } from "../src/main/sidecarApiController";
import { SIDECAR_API_REQUEST_CHANNEL } from "../src/shared/sidecarApi";

describe("trusted sidecar API controller", () => {
  it("maps the developer provider catalog to its read-only endpoint", async () => {
    const harness = ipcHarness();
    const sidecarRequest = vi.fn(async () => new Response("[]"));
    registerSidecarApiController({
      ipcMain: harness.ipcMain,
      openExternal: vi.fn(),
      requesterWebContents: { id: 42 },
      sidecarRequest,
    });

    const result = await harness.invoke(
      { sender: { id: 42 } },
      { operation: "devProviders.list" },
    );

    expect(result).toEqual([]);
    expect(sidecarRequest).toHaveBeenCalledWith(
      "/dev/providers",
      expect.objectContaining({ method: "GET" }),
    );
  });

  it("maps typed operations to fixed sidecar requests", async () => {
    const harness = ipcHarness();
    const sidecarRequest = vi.fn(async () => new Response(JSON.stringify([{ id: "memory-1" }])));
    registerSidecarApiController({
      ipcMain: harness.ipcMain,
      openExternal: vi.fn(),
      requesterWebContents: { id: 42 },
      sidecarRequest,
    });

    await expect(harness.invoke(
      { sender: { id: 42 } },
      { input: { limit: 25, query: "flight" }, operation: "memory.list" },
    )).resolves.toEqual([{ id: "memory-1" }]);
    expect(sidecarRequest).toHaveBeenCalledWith(
      "/foundation/memory?query=flight&limit=25",
      expect.objectContaining({ method: "GET" }),
    );

    await harness.invoke(
      { sender: { id: 42 } },
      {
        input: {
          expectedUpdatedAt: "2026-07-14T10:00:00Z",
          id: "session-1",
          title: "Renamed",
        },
        operation: "sessions.update",
      },
    );
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      "/sessions/session-1",
      expect.objectContaining({
        body: JSON.stringify({
          title: "Renamed",
          expectedUpdatedAt: "2026-07-14T10:00:00Z",
        }),
        method: "PATCH",
      }),
    );

    await harness.invoke(
      { sender: { id: 42 } },
      {
        input: { after: 7, limit: 50, sessionId: "session-1", turnId: "turn-1", waitMs: 5000 },
        operation: "turns.events",
      },
    );
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      "/sessions/session-1/turns/turn-1/events?after=7&limit=50&waitMs=5000",
      expect.objectContaining({ method: "GET" }),
    );

    await harness.invoke(
      { sender: { id: 42 } },
      {
        input: { after: 11, limit: 100, sessionId: "session-1", waitMs: 20000 },
        operation: "sessions.events",
      },
    );
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      "/sessions/session-1/events?after=11&limit=100&waitMs=20000",
      expect.objectContaining({ method: "GET" }),
    );

    await harness.invoke(
      { sender: { id: 42 } },
      {
        input: { sessionId: "session-1", turnId: "turn-1" },
        operation: "turns.cancel",
      },
    );
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      "/sessions/session-1/turns/turn-1/cancel",
      expect.objectContaining({ method: "POST" }),
    );
  });

  it("maps bounded Dev Skill authoring operations to the current App packages API", async () => {
    const harness = ipcHarness();
    const sidecarRequest = vi.fn(async () => new Response(JSON.stringify({ ok: true })));
    registerSidecarApiController({
      ipcMain: harness.ipcMain,
      openExternal: vi.fn(),
      requesterWebContents: { id: 42 },
      sidecarRequest,
    });
    const manifest = {
      id: "com.example.briefing",
      name: "Briefing",
      version: "0.1.0",
    };

    await harness.invoke(
      { sender: { id: 42 } },
      {
        input: { directory: "briefing", manifest, skillMd: "# Briefing\n\nPrepare a briefing." },
        operation: "devSkills.create",
      },
    );
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      "/dev/skills",
      expect.objectContaining({
        body: JSON.stringify({
          directory: "briefing",
          manifest,
          skillMd: "# Briefing\n\nPrepare a briefing.",
        }),
        method: "POST",
      }),
    );

    await harness.invoke(
      { sender: { id: 42 } },
      { input: { directory: "briefing" }, operation: "devSkills.read" },
    );
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      "/dev/skills/briefing",
      expect.objectContaining({ method: "GET" }),
    );

    const expectedRevision = "a".repeat(64);
    await harness.invoke(
      { sender: { id: 42 } },
      {
        input: {
          directory: "briefing",
          expectedRevision,
          manifest,
          skillMd: "# Briefing\n\nPrepare the daily briefing.",
        },
        operation: "devSkills.update",
      },
    );
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      "/dev/skills/briefing",
      expect.objectContaining({
        body: JSON.stringify({
          expectedRevision,
          manifest,
          skillMd: "# Briefing\n\nPrepare the daily briefing.",
        }),
        method: "PUT",
      }),
    );

    await harness.invoke(
      { sender: { id: 42 } },
      {
        input: { expectedRevision, id: "briefing" },
        operation: "devSkills.delete",
      },
    );
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      "/dev/skills/briefing",
      expect.objectContaining({
        body: JSON.stringify({ expectedRevision }),
        method: "DELETE",
      }),
    );
  });

  it.each([
    ["a traversal directory", {
      input: { directory: "../secret" },
      operation: "devSkills.read",
    }, /directory is invalid/],
    ["an invalid revision", {
      input: {
        directory: "briefing",
        expectedRevision: "stale",
        manifest: {},
        skillMd: "# Briefing",
      },
      operation: "devSkills.update",
    }, /expectedRevision is invalid/],
    ["a delete without a revision", {
      input: { id: "briefing" },
      operation: "devSkills.delete",
    }, /expectedRevision is invalid/],
    ["an unknown create field", {
      input: {
        directory: "briefing",
        manifest: {},
        path: "/tmp/secret",
        skillMd: "# Briefing",
      },
      operation: "devSkills.create",
    }, /unknown fields/],
    ["an oversized manifest", {
      input: {
        directory: "briefing",
        manifest: { description: "x".repeat(65 * 1_024) },
        skillMd: "# Briefing",
      },
      operation: "devSkills.create",
    }, /manifest is invalid/],
  ])("rejects Dev Skill input containing %s before sidecar access", async (_name, request, error) => {
    const harness = ipcHarness();
    const sidecarRequest = vi.fn();
    registerSidecarApiController({
      ipcMain: harness.ipcMain,
      openExternal: vi.fn(),
      requesterWebContents: { id: 42 },
      sidecarRequest,
    });

    await expect(harness.invoke({ sender: { id: 42 } }, request)).rejects.toThrow(error as RegExp);
    expect(sidecarRequest).not.toHaveBeenCalled();
  });

  it("maps every task operation to the fixed Foundation Tasks API", async () => {
    const harness = ipcHarness();
    const sidecarRequest = vi.fn(async () => new Response(JSON.stringify({ id: "task-1" })));
    registerSidecarApiController({
      ipcMain: harness.ipcMain,
      openExternal: vi.fn(),
      requesterWebContents: { id: 42 },
      sidecarRequest,
    });
    const content = {
      title: "Prepare briefing",
      notes: "Use the latest figures",
      dueAt: "2026-07-16T09:30:00+08:00",
      timezone: "Asia/Shanghai",
      recurrence: null,
      priority: "high",
      tags: ["work"],
    };

    await harness.invoke(
      { sender: { id: 42 } },
      {
        input: {
          cursor: "next-page",
          dueAfter: "2026-07-15T00:00:00Z",
          dueBefore: "2026-07-20T00:00:00Z",
          limit: 25,
          status: "open",
          tag: "work",
          text: "briefing",
        },
        operation: "tasks.list",
      },
    );
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      "/foundation/tasks?status=open&dueAfter=2026-07-15T00%3A00%3A00Z&dueBefore=2026-07-20T00%3A00%3A00Z&tag=work&text=briefing&limit=25&cursor=next-page",
      expect.objectContaining({ method: "GET" }),
    );

    await harness.invoke(
      { sender: { id: 42 } },
      { input: { id: "task-1" }, operation: "tasks.get" },
    );
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      "/foundation/tasks/task-1",
      expect.objectContaining({ method: "GET" }),
    );

    await harness.invoke(
      { sender: { id: 42 } },
      { input: { content, idempotencyKey: "create-1" }, operation: "tasks.create" },
    );
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      "/foundation/tasks",
      expect.objectContaining({
        body: JSON.stringify({ content, idempotencyKey: "create-1" }),
        method: "POST",
      }),
    );

    await harness.invoke(
      { sender: { id: 42 } },
      { input: { content, expectedVersion: 2, id: "task-1" }, operation: "tasks.update" },
    );
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      "/foundation/tasks/task-1",
      expect.objectContaining({
        body: JSON.stringify({ content, expectedVersion: 2 }),
        method: "PATCH",
      }),
    );

    await harness.invoke(
      { sender: { id: 42 } },
      {
        input: { expectedVersion: 3, id: "task-1", status: "completed" },
        operation: "tasks.setStatus",
      },
    );
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      "/foundation/tasks/task-1/status",
      expect.objectContaining({
        body: JSON.stringify({ expectedVersion: 3, status: "completed" }),
        method: "POST",
      }),
    );

    await harness.invoke(
      { sender: { id: 42 } },
      { input: { expectedVersion: 4, id: "task-1" }, operation: "tasks.delete" },
    );
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      "/foundation/tasks/task-1",
      expect.objectContaining({ body: JSON.stringify({ expectedVersion: 4 }), method: "DELETE" }),
    );
  });

  it("maps bounded Mail configuration only to the trusted Host API", async () => {
    const harness = ipcHarness();
    const sidecarRequest = vi.fn(async () => new Response(JSON.stringify({ configured: true })));
    const ensureCredentialVault = vi.fn(async () => undefined);
    registerSidecarApiController({
      ensureCredentialVault,
      ipcMain: harness.ipcMain,
      openExternal: vi.fn(),
      requesterWebContents: { id: 42 },
      sidecarRequest,
    });
    const password = "transient-app-password";
    await harness.invoke(
      { sender: { id: 42 } },
      {
        operation: "mail.configuration.put",
        input: {
          id: "primary",
          displayName: "Primary Mail",
          primaryAddress: "user@example.test",
          username: "user@example.test",
          password,
          imapHost: "imap.example.test",
          imapPort: 993,
          imapTls: "implicit",
          smtpHost: "smtp.example.test",
          smtpPort: 587,
          smtpTls: "start_tls",
        },
      },
    );
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      "/foundation/mail/account-configurations/primary",
      expect.objectContaining({
        method: "PUT",
        body: expect.stringContaining(password),
      }),
    );
    await harness.invoke(
      { sender: { id: 42 } },
      { operation: "mail.configuration.delete", input: { id: "primary" } },
    );
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      "/foundation/mail/account-configurations/primary",
      expect.objectContaining({ method: "DELETE" }),
    );
    expect(ensureCredentialVault).toHaveBeenCalledTimes(2);
  });

  it("provisions the Credential Vault before OAuth sidecar access", async () => {
    const harness = ipcHarness();
    const order: string[] = [];
    const ensureCredentialVault = vi.fn(async () => {
      order.push("vault");
    });
    const sidecarRequest = vi.fn(async () => {
      order.push("request");
      return new Response(JSON.stringify(oauthStartResponse()));
    });
    registerSidecarApiController({
      ensureCredentialVault,
      ipcMain: harness.ipcMain,
      openExternal: vi.fn(),
      requesterWebContents: { id: 42 },
      sidecarRequest,
    });

    await harness.invoke(
      { sender: { id: 42 } },
      { input: oauthStartInput(), operation: "oauth.start" },
    );
    expect(order).toEqual(["vault", "request"]);
  });

  it.each([
    ["invalid TLS", { imapTls: "disabled" }, /imapTls is invalid/],
    ["blank password", { password: "  " }, /password is invalid/],
    ["unknown Mail field", { credentialPath: "/tmp/secret" }, /unknown fields/],
  ])("rejects %s before Mail sidecar access", async (_name, override, error) => {
    const harness = ipcHarness();
    const sidecarRequest = vi.fn();
    registerSidecarApiController({
      ipcMain: harness.ipcMain,
      openExternal: vi.fn(),
      requesterWebContents: { id: 42 },
      sidecarRequest,
    });
    await expect(harness.invoke(
      { sender: { id: 42 } },
      {
        operation: "mail.configuration.put",
        input: {
          id: "primary",
          displayName: "Primary Mail",
          primaryAddress: "user@example.test",
          username: "user@example.test",
          password: "secret",
          imapHost: "imap.example.test",
          imapPort: 993,
          imapTls: "implicit",
          smtpHost: "smtp.example.test",
          smtpPort: 587,
          smtpTls: "start_tls",
          ...override,
        },
      },
    )).rejects.toThrow(error as RegExp);
    expect(sidecarRequest).not.toHaveBeenCalled();
  });

  it("maps attachment metadata operations without exposing attachment bytes", async () => {
    const harness = ipcHarness();
    const sidecarRequest = vi.fn(async () => new Response(JSON.stringify([])));
    registerSidecarApiController({
      ipcMain: harness.ipcMain,
      openExternal: vi.fn(),
      requesterWebContents: { id: 42 },
      sidecarRequest,
    });
    const id = "123e4567-e89b-12d3-a456-426614174000";

    await harness.invoke(
      { sender: { id: 42 } },
      { input: { limit: 10 }, operation: "attachments.list" },
    );
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      "/foundation/attachments?limit=10",
      expect.objectContaining({ method: "GET" }),
    );

    await harness.invoke(
      { sender: { id: 42 } },
      { input: { id }, operation: "attachments.get" },
    );
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      `/foundation/attachments/${id}`,
      expect.objectContaining({ method: "GET" }),
    );

    await harness.invoke(
      { sender: { id: 42 } },
      { input: { id }, operation: "attachments.delete" },
    );
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      `/foundation/attachments/${id}`,
      expect.objectContaining({ method: "DELETE" }),
    );
  });

  it("opens a validated OAuth authorization in Main and returns only non-secret state", async () => {
    const harness = ipcHarness();
    const openExternal = vi.fn(async () => undefined);
    const sidecarRequest = vi.fn(async () => new Response(JSON.stringify(oauthStartResponse())));
    registerSidecarApiController({
      ipcMain: harness.ipcMain,
      openExternal,
      requesterWebContents: { id: 42 },
      sidecarRequest,
    });

    const result = await harness.invoke(
      { sender: { id: 42 } },
      {
        input: {
          connectorIds: ["google-mail"],
          providerId: "google-workspace",
          requestedCapabilities: ["mail.read", "mail.send"],
        },
        operation: "oauth.start",
      },
    );

    expect(sidecarRequest).toHaveBeenCalledWith(
      "/host/oauth/authorizations",
      expect.objectContaining({
        body: JSON.stringify({
          providerId: "google-workspace",
          connectorIds: ["google-mail"],
          requestedCapabilities: ["mail.read", "mail.send"],
        }),
        method: "POST",
      }),
    );
    expect(openExternal).toHaveBeenCalledWith(
      "https://accounts.example.com/oauth/authorize?state=server-secret-state",
    );
    expect(result).toEqual({
      authorizationId: "authorization-1",
      expiresAt: "2026-07-16T10:15:00Z",
      providerId: "google-workspace",
      status: "pending",
    });
    expect(JSON.stringify(result)).not.toMatch(
      /authorizationUrl|authorizationOrigin|secret-state/,
    );
  });

  it("accepts OAuth request fields echoed in a different order", async () => {
    const harness = ipcHarness();
    const openExternal = vi.fn(async () => undefined);
    const sidecarRequest = vi.fn(async () => new Response(JSON.stringify(oauthStartResponse({
      connectorIds: ["google-calendar", "google-mail"],
      requestedCapabilities: ["mail.send", "mail.read"],
    }))));
    registerSidecarApiController({
      ipcMain: harness.ipcMain,
      openExternal,
      requesterWebContents: { id: 42 },
      sidecarRequest,
    });

    await expect(harness.invoke(
      { sender: { id: 42 } },
      {
        input: {
          connectorIds: ["google-mail", "google-calendar"],
          providerId: "google-workspace",
          requestedCapabilities: ["mail.read", "mail.send"],
        },
        operation: "oauth.start",
      },
    )).resolves.toEqual({
      authorizationId: "authorization-1",
      expiresAt: "2026-07-16T10:15:00Z",
      providerId: "google-workspace",
      status: "pending",
    });
    expect(openExternal).toHaveBeenCalledOnce();
  });

  it.each([
    ["provider", { providerId: "microsoft-graph" }],
    ["connector", { connectorIds: ["google-calendar"] }],
    ["extra connector", { connectorIds: ["google-mail", "google-calendar"] }],
    ["capability", { requestedCapabilities: ["mail.read"] }],
    ["extra capability", {
      requestedCapabilities: ["mail.read", "mail.send", "calendar.read"],
    }],
  ])("rejects a mismatched OAuth %s echo without opening it", async (_name, overrides) => {
    const harness = ipcHarness();
    const openExternal = vi.fn();
    const sidecarRequest = vi.fn(async () => new Response(JSON.stringify(
      oauthStartResponse(overrides),
    )));
    registerSidecarApiController({
      ipcMain: harness.ipcMain,
      openExternal,
      requesterWebContents: { id: 42 },
      sidecarRequest,
    });

    await expect(harness.invoke(
      { sender: { id: 42 } },
      { input: oauthStartInput(), operation: "oauth.start" },
    )).rejects.toThrow(/OAuth authorization/);
    expect(openExternal).not.toHaveBeenCalled();
    expect(sidecarRequest).toHaveBeenCalledOnce();
  });

  it.each([
    ["a different origin", {
      authorizationOrigin: "https://login.attacker.invalid",
    }],
    ["HTTP", {
      authorizationOrigin: "http://accounts.example.com",
      authorizationUrl: "http://accounts.example.com/oauth/authorize",
    }],
    ["userinfo", {
      authorizationOrigin: "https://accounts.example.com",
      authorizationUrl: "https://user:password@accounts.example.com/oauth/authorize",
    }],
    ["a fragment", {
      authorizationUrl: "https://accounts.example.com/oauth/authorize#state=leaked",
    }],
    ["an OAuth state response field", {
      state: "must-not-cross-main-boundary",
    }],
  ])("rejects an OAuth start response containing %s without opening it", async (_name, overrides) => {
    const harness = ipcHarness();
    const openExternal = vi.fn();
    const sidecarRequest = vi.fn(async () => new Response(JSON.stringify(oauthStartResponse(overrides))));
    registerSidecarApiController({
      ipcMain: harness.ipcMain,
      openExternal,
      requesterWebContents: { id: 42 },
      sidecarRequest,
    });

    await expect(harness.invoke(
      { sender: { id: 42 } },
      { input: oauthStartInput(), operation: "oauth.start" },
    )).rejects.toThrow(/OAuth authorization|unknown fields/);
    expect(openExternal).not.toHaveBeenCalled();
  });

  it("cancels a pending OAuth authorization when the system browser cannot open", async () => {
    const harness = ipcHarness();
    const sidecarRequest = vi.fn(async () => new Response(JSON.stringify(oauthStartResponse())));
    registerSidecarApiController({
      ipcMain: harness.ipcMain,
      openExternal: vi.fn(async () => {
        throw new Error("failed for https://accounts.example.com/?state=server-secret-state");
      }),
      requesterWebContents: { id: 42 },
      sidecarRequest,
    });

    await expect(harness.invoke(
      { sender: { id: 42 } },
      { input: oauthStartInput(), operation: "oauth.start" },
    )).rejects.toThrow("OAuth authorization could not be opened");
    await expect(harness.invoke(
      { sender: { id: 42 } },
      { input: oauthStartInput(), operation: "oauth.start" },
    )).rejects.not.toThrow(/server-secret-state/);
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      "/host/oauth/authorizations/authorization-1",
      { method: "DELETE" },
    );
  });

  it("rejects unknown OAuth input fields and other renderers before sidecar access", async () => {
    const harness = ipcHarness();
    const openExternal = vi.fn();
    const sidecarRequest = vi.fn();
    registerSidecarApiController({
      ipcMain: harness.ipcMain,
      openExternal,
      requesterWebContents: { id: 42 },
      sidecarRequest,
    });

    await expect(harness.invoke(
      { sender: { id: 42 } },
      {
        input: { ...oauthStartInput(), redirectUri: "https://attacker.invalid/callback" },
        operation: "oauth.start",
      },
    )).rejects.toThrow(/unknown fields/);
    await expect(harness.invoke(
      { sender: { id: 7 } },
      { input: oauthStartInput(), operation: "oauth.start" },
    )).rejects.toThrow(/requester window/);
    expect(sidecarRequest).not.toHaveBeenCalled();
    expect(openExternal).not.toHaveBeenCalled();
  });

  it.each([
    ["an oversized provider identifier", {
      ...oauthStartInput(),
      providerId: "p".repeat(129),
    }, /providerId is invalid/],
    ["too many connector identifiers", {
      ...oauthStartInput(),
      connectorIds: Array.from({ length: 33 }, (_value, index) => `connector-${index}`),
    }, /connectorIds is invalid/],
    ["an invalid capability identifier", {
      ...oauthStartInput(),
      requestedCapabilities: ["mail.read", "../credential"],
    }, /requestedCapabilities is invalid/],
    ["an extra status field", {
      authorizationId: "authorization-1",
      providerId: "google-workspace",
    }, /unknown fields/],
  ])("rejects OAuth input containing %s before sidecar access", async (_name, input, error) => {
    const harness = ipcHarness();
    const openExternal = vi.fn();
    const sidecarRequest = vi.fn();
    registerSidecarApiController({
      ipcMain: harness.ipcMain,
      openExternal,
      requesterWebContents: { id: 42 },
      sidecarRequest,
    });

    await expect(harness.invoke(
      { sender: { id: 42 } },
      {
        input,
        operation: _name === "an extra status field" ? "oauth.status" : "oauth.start",
      },
    )).rejects.toThrow(error as RegExp);
    expect(sidecarRequest).not.toHaveBeenCalled();
    expect(openExternal).not.toHaveBeenCalled();
  });

  it("maps OAuth status and cancellation to fixed authorization paths", async () => {
    const harness = ipcHarness();
    const sidecarRequest = vi.fn(async (_pathname: string, init?: RequestInit) => new Response(
      JSON.stringify(oauthViewResponse(init?.method === "DELETE" ? "cancelled" : "pending")),
    ));
    registerSidecarApiController({
      ipcMain: harness.ipcMain,
      openExternal: vi.fn(),
      requesterWebContents: { id: 42 },
      sidecarRequest,
    });

    await expect(harness.invoke(
      { sender: { id: 42 } },
      { input: { authorizationId: "authorization-1" }, operation: "oauth.status" },
    )).resolves.toEqual({
      authorizationId: "authorization-1",
      bindings: [],
      connectorIds: ["google-mail"],
      createdAt: "2026-07-16T10:00:00Z",
      errorCode: null,
      expiresAt: "2026-07-16T10:15:00Z",
      providerId: "google-workspace",
      requestedCapabilities: ["mail.read", "mail.send"],
      status: "pending",
      updatedAt: "2026-07-16T10:00:00Z",
    });
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      "/host/oauth/authorizations/authorization-1",
      expect.objectContaining({ method: "GET" }),
    );

    await expect(harness.invoke(
      { sender: { id: 42 } },
      { input: { authorizationId: "authorization-1" }, operation: "oauth.cancel" },
    )).resolves.toEqual(expect.objectContaining({ status: "cancelled" }));
    expect(sidecarRequest).toHaveBeenLastCalledWith(
      "/host/oauth/authorizations/authorization-1",
      expect.objectContaining({ method: "DELETE" }),
    );
  });

  it.each(["authorizationUrl", "code", "credentialId", "state", "token", "verifier"])(
    "rejects an OAuth status response containing secret-shaped field %s",
    async (field) => {
      const harness = ipcHarness();
      const sidecarRequest = vi.fn(async () => new Response(JSON.stringify({
        ...oauthViewResponse("pending"),
        [field]: "must-not-cross-main-boundary",
      })));
      registerSidecarApiController({
        ipcMain: harness.ipcMain,
        openExternal: vi.fn(),
        requesterWebContents: { id: 42 },
        sidecarRequest,
      });

      let rejection: unknown;
      try {
        await harness.invoke(
          { sender: { id: 42 } },
          { input: { authorizationId: "authorization-1" }, operation: "oauth.status" },
        );
      } catch (error) {
        rejection = error;
      }
      expect(rejection).toBeInstanceOf(Error);
      expect(String(rejection)).toMatch(/unknown fields/);
      expect(String(rejection)).not.toContain("must-not-cross-main-boundary");
    },
  );

  it.each([
    ["invalid task identifier", { input: { id: "../secret" }, operation: "tasks.get" }, /id is invalid/],
    ["oversized title", taskCreate({ title: "x".repeat(1_025) }, "create-1"), /title is invalid/],
    ["oversized notes", taskCreate({ notes: "x".repeat(65_537) }, "create-1"), /notes is invalid/],
    ["oversized idempotency key", taskCreate({}, "x".repeat(513)), /idempotencyKey is invalid/],
    ["blank idempotency key", taskCreate({}, "   "), /idempotencyKey is invalid/],
    ["invalid version", {
      input: { expectedVersion: 0, id: "task-1", status: "completed" },
      operation: "tasks.setStatus",
    }, /expectedVersion is invalid/],
    ["invalid status", {
      input: { expectedVersion: 1, id: "task-1", status: "archived" },
      operation: "tasks.setStatus",
    }, /status is invalid/],
    ["unknown input field", {
      input: { id: "task-1", path: "/etc/passwd" },
      operation: "tasks.get",
    }, /unknown fields/],
    ["unknown content field", taskCreate({ path: "/etc/passwd" }, "create-1"), /unknown fields/],
  ])("rejects %s before task sidecar access", async (_name, request, error) => {
    const harness = ipcHarness();
    const sidecarRequest = vi.fn();
    registerSidecarApiController({
      ipcMain: harness.ipcMain,
      openExternal: vi.fn(),
      requesterWebContents: { id: 42 },
      sidecarRequest,
    });

    await expect(harness.invoke({ sender: { id: 42 } }, request)).rejects.toThrow(error as RegExp);
    expect(sidecarRequest).not.toHaveBeenCalled();
  });

  it("rejects other renderers and arbitrary operations before sidecar access", async () => {
    const harness = ipcHarness();
    const sidecarRequest = vi.fn();
    registerSidecarApiController({
      ipcMain: harness.ipcMain,
      openExternal: vi.fn(),
      requesterWebContents: { id: 42 },
      sidecarRequest,
    });

    await expect(harness.invoke(
      { sender: { id: 7 } },
      { operation: "memory.list" },
    )).rejects.toThrow(/requester window/);
    await expect(harness.invoke(
      { sender: { id: 42 } },
      { input: { path: "http://attacker.invalid" }, operation: "raw.fetch" },
    )).rejects.toThrow(/operation is not allowed/);
    await expect(harness.invoke(
      { sender: { id: 42 } },
      { input: { id: ".." }, operation: "memory.get" },
    )).rejects.toThrow(/id is invalid/);
    await expect(harness.invoke(
      { sender: { id: 42 } },
      {
        input: { after: -1, providerId: "attacker", sessionId: "session-1" },
        operation: "sessions.events",
      },
    )).rejects.toThrow(/invalid/);
    expect(sidecarRequest).not.toHaveBeenCalled();
  });
});

function taskCreate(overrides: Record<string, unknown>, idempotencyKey: string) {
  return {
    input: {
      content: {
        title: "Prepare briefing",
        priority: "normal",
        tags: [],
        ...overrides,
      },
      idempotencyKey,
    },
    operation: "tasks.create",
  };
}

function oauthStartInput() {
  return {
    connectorIds: ["google-mail"],
    providerId: "google-workspace",
    requestedCapabilities: ["mail.read", "mail.send"],
  };
}

function oauthStartResponse(overrides: Record<string, unknown> = {}) {
  return {
    authorizationId: "authorization-1",
    authorizationOrigin: "https://accounts.example.com",
    authorizationUrl: "https://accounts.example.com/oauth/authorize?state=server-secret-state",
    connectorIds: ["google-mail"],
    expiresAt: "2026-07-16T10:15:00Z",
    providerId: "google-workspace",
    requestedCapabilities: ["mail.read", "mail.send"],
    status: "pending",
    ...overrides,
  };
}

function oauthViewResponse(status: "cancelled" | "pending") {
  return {
    authorizationId: "authorization-1",
    bindings: [],
    connectorIds: ["google-mail"],
    createdAt: "2026-07-16T10:00:00Z",
    errorCode: status === "cancelled" ? "authorization_cancelled" : null,
    expiresAt: "2026-07-16T10:15:00Z",
    providerId: "google-workspace",
    requestedCapabilities: ["mail.read", "mail.send"],
    status,
    updatedAt: "2026-07-16T10:00:00Z",
  };
}

function ipcHarness() {
  let handler: ((event: { sender: { id: number } }, value: unknown) => unknown) | null = null;
  return {
    ipcMain: {
      handle: (channel: string, next: typeof handler) => {
        expect(channel).toBe(SIDECAR_API_REQUEST_CHANNEL);
        handler = next;
      },
      removeHandler: () => undefined,
    },
    invoke: (event: { sender: { id: number } }, value: unknown) => {
      if (!handler) throw new Error("IPC handler was not registered");
      return Promise.resolve(handler(event, value));
    },
  };
}
