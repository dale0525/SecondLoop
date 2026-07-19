import { readFileSync } from "node:fs";

import { act, cleanup, render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";

import {
  DevSkillInventory,
  DevSkillPackage,
  DevSkillReloadResponse
} from "../src/renderer/api";
import App from "../src/renderer/App";
import {
  buildCreateSkillPrompt,
  buildModifySkillPrompt
} from "../src/renderer/devSkillPrompts";
import { DeveloperTools } from "../src/renderer/screens/DeveloperTools";
import { installHostBootstrap } from "./hostBootstrapFixture";

afterEach(() => {
  cleanup();
  window.history.replaceState(null, "", "/");
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
  delete window.agentWeave;
});

describe("developer skill prompts", () => {
  it("builds a create prompt for Codex skill-creator", () => {
    const prompt = buildCreateSkillPrompt("/home/developer/projects/AgentWeave/skills");

    expect(prompt).toContain("Use $skill-creator");
    expect(prompt).toContain("skills/");
    expect(prompt).not.toContain("/home/developer");
    expect(prompt).toContain("SKILL.md is a development authoring asset");
    expect(prompt).toContain("agentweave.json is the AgentWeave package contract");
  });

  it("builds a modify prompt with package diagnostics", () => {
    const skillPackage: DevSkillPackage = {
      id: "echo",
      path: "echo",
      name: "echo",
      description: "Echo a text payload.",
      hasSkillMd: false,
      hasRuntimeManifest: true,
      runtimeTools: ["echo"],
      packageKind: "runtime",
      bundleReady: true,
      runtimeReady: true,
      instructionReady: false,
      releaseReady: true,
      readinessIssues: [],
      requiredRuntimeTools: [],
      requiredConnectors: [],
      hasPackageMetadata: false,
      validation: {
        ok: false,
        errors: ["missing SKILL.md is informational only"],
        warnings: []
      }
    };

    const prompt = buildModifySkillPrompt(
      "/home/developer/projects/AgentWeave/skills",
      skillPackage
    );

    expect(prompt).toContain("Use $skill-creator");
    expect(prompt).toContain("Package path: skills/echo");
    expect(prompt).not.toContain("/home/developer");
    expect(prompt).toContain("runtime tools: echo");
    expect(prompt).toContain("Runtime ready: true");
    expect(prompt).toContain("Instruction ready: false");
    expect(prompt).toContain("Release ready: true");
    expect(prompt).toContain("missing SKILL.md is informational only");
  });
});

describe("DeveloperTools", () => {
  it("marks inactive tab panels as hidden", async () => {
    const user = userEvent.setup();

    render(
      <DeveloperTools
        initialInventory={inventoryWith("echo")}
        initialStatus="available"
        onBack={() => undefined}
      />,
    );

    await user.click(screen.getByRole("tab", { name: "Build" }));

    expect(screen.getByRole("tabpanel", { name: "Build" })).not.toHaveAttribute("hidden");
    expect(document.querySelector('.developer-tab-content[hidden]')).toBeInTheDocument();
    const testModuleUrl = import.meta.url;
    const css = readFileSync(new URL("../src/renderer/styles/developer.css", testModuleUrl), "utf8");
    expect(css).toMatch(/\.developer-tab-content\[hidden\]\s*\{[^}]*display:\s*none;/);
  });

  it("keeps mobile Skill Creator icon targets at least 44 pixels", () => {
    const testModuleUrl = import.meta.url;
    const css = readFileSync(
      new URL("../src/renderer/styles/developer-authoring.css", testModuleUrl),
      "utf8",
    );

    expect(css).toMatch(/\.developer-authoring-header \.icon-button,\s*\.developer-authoring-send\s*\{[^}]*width:\s*44px;[^}]*height:\s*44px;/);
  });

  it("routes #developer to the developer tools screen", async () => {
    installHostBootstrap();
    installDevApiBridge({ root: "/repo/skills", packages: [] });
    window.history.replaceState(null, "", "/#developer");

    render(<App />);

    expect(
      await screen.findByRole("main", { name: "Developer Tools" })
    ).toBeInTheDocument();
  });

  it("shows settings developer entry only when the dev API is available", async () => {
    installHostBootstrap();
    installDevApiBridge({ root: "/repo/skills", packages: [] });
    const user = userEvent.setup();

    render(<App />);

    await waitFor(() => expect(document.title).toBe("Secretary"));
    await user.click(screen.getByRole("button", { name: "Open settings" }));

    expect(
      await screen.findByRole("button", { name: "Open developer tools" })
    ).toBeInTheDocument();
  });

  it("keeps a reloaded inventory when leaving and reopening developer tools", async () => {
    installHostBootstrap();
    const initialInventory = inventoryWith("echo");
    const reloadedInventory = inventoryWith("planning");
    if (!window.agentWeave) throw new Error("Host bootstrap must be installed first");
    window.agentWeave.server = {
      request: async (operation) => {
        if (operation === "devSkills.list") return initialInventory;
        if (operation === "devSkills.reload") return reloadResponse(2, reloadedInventory);
        throw new Error(`Unexpected operation: ${operation}`);
      },
    };
    window.history.replaceState(null, "", "/#developer");
    const user = userEvent.setup();

    render(<App />);

    await user.click(await screen.findByRole("button", { name: "Reload diagnostics" }));
    expect(await screen.findByText("skills/planning")).toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: "Back to settings" }));
    await user.click(await screen.findByRole("button", { name: "Open developer tools" }));

    expect(await screen.findByText("skills/planning")).toBeInTheDocument();
    expect(screen.queryByText("skills/echo")).not.toBeInTheDocument();
  });

  it("hides settings developer entry when the dev API is unavailable", async () => {
    installHostBootstrap();
    mockFetch([new Response(JSON.stringify({ error: "not found" }), { status: 404 })]);

    render(<App />);

    await userEvent.click(screen.getByRole("button", { name: "Open settings" }));

    await waitFor(() => {
      expect(
        screen.queryByRole("button", { name: "Open developer tools" })
      ).not.toBeInTheDocument();
    });
  });

  it("rejects direct developer navigation outside the trusted Electron bridge", async () => {
    installHostBootstrap();
    window.history.replaceState(null, "", "/#developer");
    const fetchMock = mockFetch([jsonResponse({ root: "/repo/skills", packages: [] })]);

    render(<App />);

    expect(await screen.findByRole("main", { name: "Settings" })).toBeInTheDocument();
    expect(screen.queryByRole("main", { name: "Developer Tools" })).not.toBeInTheDocument();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("treats runtime-only missing SKILL.md diagnostics as informational", async () => {
    mockFetch([
      jsonResponse({
        root: "/repo/skills",
        packages: [
          {
            id: "echo",
            path: "echo",
            name: "echo",
            description: "Echo a text payload.",
            hasSkillMd: false,
            hasRuntimeManifest: true,
            runtimeTools: ["echo"],
            packageKind: "runtime",
            bundleReady: true,
            validation: {
              ok: false,
              errors: ["missing SKILL.md is informational only"],
              warnings: []
            }
          }
        ]
      })
    ]);

    render(<DeveloperTools onBack={() => undefined} />);

    expect(await screen.findByRole("heading", { name: "Skill packages" })).toBeInTheDocument();
    expect(screen.getAllByText("Runtime only")).toHaveLength(2);
    expect(screen.getByText("SKILL.md missing")).toBeInTheDocument();
    expect(screen.queryByText("Validation issues")).not.toBeInTheDocument();
    expect(screen.queryByText("Needs attention")).not.toBeInTheDocument();
  });

  it("renders package inventory and selected runtime-only details", async () => {
    mockFetch([
      jsonResponse({
        root: "/repo/skills",
        packages: [
          {
            id: "echo",
            path: "echo",
            name: "echo",
            description: "Echo a text payload.",
            hasSkillMd: false,
            hasRuntimeManifest: true,
            runtimeTools: ["echo"],
            packageKind: "runtime",
            bundleReady: true,
            validation: { ok: true, errors: [], warnings: [] }
          }
        ]
      })
    ]);

    render(<DeveloperTools onBack={() => undefined} />);

    expect(await screen.findByRole("heading", { name: "Skill packages" })).toBeInTheDocument();
    const list = screen.getByRole("list", { name: "Skill packages" });
    expect(within(list).getByRole("button", { name: /echo/i })).toBeInTheDocument();
    expect(screen.getByText("skills/echo")).toBeInTheDocument();
    expect(screen.getByText("SKILL.md missing")).toBeInTheDocument();
    expect(screen.queryByText("Broken")).not.toBeInTheDocument();
  });

  it("shows a disabled state when the development API is unavailable", async () => {
    mockFetch([new Response(JSON.stringify({ error: "not found" }), { status: 404 })]);

    render(<DeveloperTools onBack={() => undefined} />);

    expect(
      await screen.findByText("Development API is not available")
    ).toBeInTheDocument();
  });

  it("edits and reloads an instruction Skill through the Skill Creator conversation", async () => {
    const user = userEvent.setup();
    const inventory = inventoryWithInstruction("briefing");
    const source = instructionSource("briefing");
    const candidate = {
      directory: "briefing",
      manifest: {
        ...source.manifest,
        displayName: "Daily Briefing",
        requires: { packages: [], capabilities: [], runtimeTools: [], connectors: [] },
      },
      skillMd: "---\nname: briefing\ndescription: Prepare a concise daily briefing.\n---\n\n# Daily briefing\n\nSummarize verified facts and call out uncertainty.\n",
    };
    installHostBootstrap();
    const startTurn = vi.fn(async (_sessionId: string, _requestId: string, _content: string) => ({
      reused: false,
      turn: serverTurn("running"),
      userMessage: serverMessage("user-message", "user", "Make it concise"),
    }));
    const serverRequest = vi.fn(async (operation: string, input?: unknown) => {
      if (operation === "devSkills.read") return source;
      if (operation === "sessions.create") return serverSession();
      if (operation === "turns.events") {
        return {
          events: [serverEvent(0, "assistant_message_finished", {
            text: `The revised skill focuses on concise, verifiable briefings.\n\n<agentweave-skill-draft>${JSON.stringify(candidate)}</agentweave-skill-draft>`,
          }), serverEvent(1, "turn_finished")],
          hasMore: false,
          nextCursor: 1,
          turn: serverTurn("completed"),
        };
      }
      if (operation === "devSkills.update") {
        return { inventory, source: { ...source, ...candidate, sourceRevision: "b".repeat(64) } };
      }
      if (operation === "devSkills.reload") return reloadResponse(3, inventory);
      throw new Error(`Unexpected operation: ${operation} ${JSON.stringify(input)}`);
    });
    if (!window.agentWeave) throw new Error("Host bootstrap must be installed first");
    window.agentWeave.server = { request: serverRequest };
    window.agentWeave.modelSettings = modelSettingsBridge({ saved: true, startTurn });

    render(
      <DeveloperTools
        initialInventory={inventory}
        initialStatus="available"
        onBack={() => undefined}
      />,
    );

    await user.click(await screen.findByRole("button", { name: "Edit with Skill Creator" }));

    const dialog = screen.getByRole("dialog", { name: "Improve with Skill Creator" });
    const message = await within(dialog).findByRole("textbox", { name: "Message Skill Creator" });
    await user.type(message, "Make the briefing concise and distinguish facts from uncertainty.");
    await user.click(within(dialog).getByRole("button", { name: "Send to Skill Creator" }));

    await user.click(await within(dialog).findByRole("button", { name: "Apply skill" }));
    const snapshot = screen.getByText("Active snapshot 3");
    expect(snapshot).toBeInTheDocument();
    expect(await within(dialog).findByText("Skill saved and active")).toBeInTheDocument();
    expect(startTurn).toHaveBeenCalledWith(
      "skill-authoring-session",
      expect.any(String),
      expect.stringContaining("Use $skill-creator"),
    );
    expect(startTurn.mock.calls[0]?.[2]).toContain("<existing_skill_source>");
    expect(serverRequest).toHaveBeenCalledWith("devSkills.update", {
      directory: "briefing",
      expectedRevision: source.sourceRevision,
      manifest: candidate.manifest,
      skillMd: candidate.skillMd,
    });
  });

  it("routes unconfigured Skill Creator users to model settings", async () => {
    const user = userEvent.setup();
    const inventory = inventoryWithInstruction("briefing");
    installHostBootstrap();
    if (!window.agentWeave) throw new Error("Host bootstrap must be installed first");
    window.agentWeave.modelSettings = modelSettingsBridge({ saved: false });

    render(
      <DeveloperTools
        initialInventory={inventory}
        initialStatus="available"
        onBack={() => undefined}
      />,
    );

    await user.click(screen.getByRole("button", { name: "New skill" }));
    const dialog = screen.getByRole("dialog", { name: "Create with Skill Creator" });
    await user.click(await within(dialog).findByRole("button", { name: "Configure model" }));

    expect(screen.queryByRole("dialog", { name: "Create with Skill Creator" })).not.toBeInTheDocument();
    expect(screen.getByRole("tab", { name: "Model" })).toHaveAttribute("data-state", "active");
  });

  it("backs off running turn polls and clears partial messages after failure", async () => {
    const user = userEvent.setup();
    const emptyInventory: DevSkillInventory = { root: "/repo/skills", packages: [] };
    const eventRequestTimes: number[] = [];
    installHostBootstrap();
    const startTurn = vi.fn(async () => ({
      reused: false,
      turn: serverTurn("running"),
      userMessage: serverMessage("user-message", "user", "Create a planning skill"),
    }));
    const serverRequest = vi.fn(async (operation: string) => {
      if (operation === "sessions.create") return serverSession();
      if (operation === "turns.events") {
        eventRequestTimes.push(Date.now());
        if (eventRequestTimes.length === 1) {
          return {
            events: [serverEvent(0, "assistant_message_finished", {
              text: "A partial draft that must disappear.",
            })],
            hasMore: false,
            nextCursor: 0,
            turn: serverTurn("running"),
          };
        }
        return {
          events: [],
          hasMore: false,
          nextCursor: 0,
          turn: serverTurn("failed"),
        };
      }
      throw new Error(`Unexpected operation: ${operation}`);
    });
    if (!window.agentWeave) throw new Error("Host bootstrap must be installed first");
    window.agentWeave.server = { request: serverRequest };
    window.agentWeave.modelSettings = modelSettingsBridge({ saved: true, startTurn });

    render(
      <DeveloperTools
        initialInventory={emptyInventory}
        initialStatus="available"
        onBack={() => undefined}
      />,
    );

    await user.click(screen.getByRole("button", { name: "New skill" }));
    const dialog = screen.getByRole("dialog", { name: "Create with Skill Creator" });
    await user.type(
      await within(dialog).findByRole("textbox", { name: "Message Skill Creator" }),
      "Create a planning skill.",
    );
    await user.click(within(dialog).getByRole("button", { name: "Send to Skill Creator" }));

    expect(await within(dialog).findByText("A partial draft that must disappear.")).toBeInTheDocument();
    expect(await within(dialog).findByText(
      "Skill Creator could not complete that turn. Check the model connection and try again.",
    )).toBeInTheDocument();
    expect(within(dialog).queryByText("A partial draft that must disappear.")).not.toBeInTheDocument();
    expect(eventRequestTimes).toHaveLength(2);
    expect(eventRequestTimes[1]! - eventRequestTimes[0]!).toBeGreaterThanOrEqual(200);
  });

  it("disposes an authoring session that finishes creating after the dialog closes", async () => {
    const user = userEvent.setup();
    const emptyInventory: DevSkillInventory = { root: "/repo/skills", packages: [] };
    const createdSession = deferred<ReturnType<typeof serverSession>>();
    const startTurn = vi.fn(async () => ({}));
    installHostBootstrap();
    const serverRequest = vi.fn(async (operation: string) => {
      if (operation === "sessions.create") return createdSession.promise;
      if (operation === "sessions.load") {
        return { events: [], messages: [], session: serverSession() };
      }
      if (operation === "sessions.delete") return {};
      throw new Error(`Unexpected operation: ${operation}`);
    });
    if (!window.agentWeave) throw new Error("Host bootstrap must be installed first");
    window.agentWeave.server = { request: serverRequest };
    window.agentWeave.modelSettings = modelSettingsBridge({ saved: true, startTurn });

    render(
      <DeveloperTools
        initialInventory={emptyInventory}
        initialStatus="available"
        onBack={() => undefined}
      />,
    );

    await user.click(screen.getByRole("button", { name: "New skill" }));
    const dialog = screen.getByRole("dialog", { name: "Create with Skill Creator" });
    await user.type(
      await within(dialog).findByRole("textbox", { name: "Message Skill Creator" }),
      "Create a planning skill.",
    );
    await user.click(within(dialog).getByRole("button", { name: "Send to Skill Creator" }));
    await waitFor(() => expect(serverRequest).toHaveBeenCalledWith(
      "sessions.create",
      expect.any(Object),
    ));

    await user.click(within(dialog).getByRole("button", { name: "Close Skill Creator" }));
    expect(screen.queryByRole("dialog", { name: "Create with Skill Creator" })).not.toBeInTheDocument();
    await act(async () => createdSession.resolve(serverSession()));

    await waitFor(() => expect(serverRequest).toHaveBeenCalledWith(
      "sessions.delete",
      expect.objectContaining({ id: "skill-authoring-session" }),
    ));
    expect(startTurn).not.toHaveBeenCalled();
  });

  it("creates a new instruction Skill without asking for package fields", async () => {
    const user = userEvent.setup();
    const emptyInventory: DevSkillInventory = { root: "/repo/skills", packages: [] };
    const publishedInventory = inventoryWithInstruction("decision-log");
    const prepared = instructionSource("decision-log");
    const candidate = {
      directory: prepared.directory,
      manifest: {
        ...prepared.manifest,
        displayName: "Decision Log",
        compatibility: { platforms: ["desktop"] },
        requires: { packages: [], capabilities: [], runtimeTools: [], connectors: [] },
      },
      skillMd: "---\nname: decision-log\ndescription: Turn rough notes into a concise decision log.\n---\n\n# Decision log\n\nCapture decisions, owners, and unresolved questions.\n",
    };
    installHostBootstrap();
    const startTurn = vi.fn(async (_sessionId: string, _requestId: string, _content: string) => ({
      reused: false,
      turn: serverTurn("running"),
      userMessage: serverMessage("user-message", "user", "Create a decision log skill"),
    }));
    const serverRequest = vi.fn(async (operation: string) => {
      if (operation === "sessions.create") return serverSession();
      if (operation === "turns.events") {
        return {
          events: [serverEvent(0, "assistant_message_finished", {
            text: `The decision log skill is ready.\n<agentweave-skill-draft>${JSON.stringify(candidate)}</agentweave-skill-draft>`,
          }), serverEvent(1, "turn_finished")],
          hasMore: false,
          nextCursor: 1,
          turn: serverTurn("completed"),
        };
      }
      if (operation === "devSkills.create") {
        return { inventory: publishedInventory, source: { ...prepared, ...candidate } };
      }
      if (operation === "devSkills.reload") return reloadResponse(4, publishedInventory);
      throw new Error(`Unexpected operation: ${operation}`);
    });
    if (!window.agentWeave) throw new Error("Host bootstrap must be installed first");
    window.agentWeave.server = { request: serverRequest };
    window.agentWeave.modelSettings = modelSettingsBridge({ saved: true, startTurn });

    render(
      <DeveloperTools
        initialInventory={emptyInventory}
        initialStatus="available"
        onBack={() => undefined}
      />,
    );

    await user.click(screen.getByRole("button", { name: "New skill" }));
    const dialog = screen.getByRole("dialog", { name: "Create with Skill Creator" });
    const message = await within(dialog).findByRole("textbox", { name: "Message Skill Creator" });
    expect(dialog.querySelectorAll("input, select")).toHaveLength(0);
    expect(within(dialog).queryByText("Package ID")).not.toBeInTheDocument();
    expect(within(dialog).queryByText("Agent instructions (Markdown)")).not.toBeInTheDocument();
    await user.type(message, "Turn rough meeting notes into a decision log with owners and open questions.");
    await user.click(within(dialog).getByRole("button", { name: "Send to Skill Creator" }));
    await user.click(await within(dialog).findByRole("button", { name: "Apply skill" }));

    expect(startTurn.mock.calls[0]?.[2]).toContain("Use $skill-creator");
    expect(startTurn.mock.calls[0]?.[2]).not.toContain("<existing_skill_source>");
    expect(serverRequest).toHaveBeenCalledWith("devSkills.create", candidate);
    expect(screen.getByText("Active snapshot 4")).toBeInTheDocument();
  });

  it("deletes a package after confirmation and refreshes inventory", async () => {
    const user = userEvent.setup();
    const inventory = inventoryWithInstruction("echo");
    const source = instructionSource("echo");
    const fetchMock = mockFetch([
      jsonResponse(inventory),
      jsonResponse(source),
      jsonResponse({ root: "/repo/skills", packages: [] })
    ]);

    render(<DeveloperTools onBack={() => undefined} />);

    await user.click(await screen.findByRole("button", { name: "Delete package" }));
    await user.click(screen.getByRole("button", { name: "Delete echo" }));

    await waitFor(() => {
      expect(screen.getByText("No skill packages found")).toBeInTheDocument();
    });
    expect(fetchMock).toHaveBeenLastCalledWith(
      "/__agentweave/dev/skills/echo",
      expect.objectContaining({
        body: JSON.stringify({ expectedRevision: source.sourceRevision }),
        method: "DELETE"
      })
    );
  });

  it("closes the delete dialog and shows an error when deletion fails", async () => {
    const user = userEvent.setup();
    mockFetch([
      jsonResponse(inventoryWithInstruction("echo")),
      jsonResponse(instructionSource("echo")),
      new Response(JSON.stringify({ error: "delete failed" }), { status: 500 })
    ]);

    render(<DeveloperTools onBack={() => undefined} />);

    await user.click(await screen.findByRole("button", { name: "Delete package" }));
    await user.click(screen.getByRole("button", { name: "Delete echo" }));

    expect(
      await screen.findByText("Action failed. Keep the current inventory and try again.")
    ).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Delete echo" })).not.toBeInTheDocument();
    expect(screen.getAllByText("echo").length).toBeGreaterThan(0);
  });

  it("keeps the current inventory visible when reloading diagnostics fails", async () => {
    const user = userEvent.setup();
    const initialInventory = inventoryWith("echo");
    const publishedInventory = inventoryWith("echo", "planning");
    mockFetch([
      jsonResponse(initialInventory),
      jsonResponse({
        inventory: publishedInventory,
        previousGeneration: 1,
        activeGeneration: 2,
        activePackages: 2,
        inactivePackages: 0,
        reloadStatus: "published"
      }),
      jsonResponse(publishedInventory),
      new Response(JSON.stringify({ error: "reload failed" }), { status: 422 })
    ]);

    render(<DeveloperTools onBack={() => undefined} />);

    await screen.findByRole("button", { name: "Runtime source is read-only" });
    await user.click(screen.getByRole("button", { name: "Reload diagnostics" }));
    expect(await screen.findByText("Active snapshot 2")).toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: "Refresh skill packages" }));
    expect(await screen.findByText("Active snapshot 2")).toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: /planning/i }));
    expect(screen.getByText("skills/planning")).toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: "Reload diagnostics" }));

    expect(await screen.findByText("Action failed. Keep the current inventory and try again.")).toBeInTheDocument();
    expect(screen.getByText("Active snapshot 2")).toBeInTheDocument();
    expect(screen.getByText("skills/planning")).toBeInTheDocument();
    expect(screen.getAllByText("echo").length).toBeGreaterThan(0);
    expect(screen.queryByText("Development API is not available")).not.toBeInTheDocument();
  });

  it("serializes reload before refresh and preserves the published generation", async () => {
    const user = userEvent.setup();
    const pendingReload = deferred<Response>();
    const fetchMock = mockFetch([
      jsonResponse(inventoryWith("echo")),
      pendingReload.promise,
      jsonResponse(inventoryWith("echo"))
    ]);
    render(<DeveloperTools onBack={() => undefined} />);

    const reloadButton = await screen.findByRole("button", { name: "Reload diagnostics" });
    const refreshButton = screen.getByRole("button", { name: "Refresh skill packages" });
    act(() => {
      reloadButton.dispatchEvent(new MouseEvent("click", { bubbles: true }));
      refreshButton.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    });

    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(reloadButton).toBeDisabled();
    expect(refreshButton).toBeDisabled();
    expect(screen.getByRole("button", { name: "Validate all skill packages" })).toBeDisabled();
    expect(screen.getByRole("button", { name: "Delete package" })).toBeDisabled();

    await settleDeferred(
      pendingReload,
      jsonResponse(reloadResponse(6, inventoryWith("planning")))
    );
    expect(await screen.findByText("skills/planning")).toBeInTheDocument();
    expect(screen.getByText("Active snapshot 6")).toBeInTheDocument();
    expectWorkbenchBusy(false);

    await user.click(screen.getByRole("button", { name: "Refresh skill packages" }));
    expect(await screen.findByText("skills/echo")).toBeInTheDocument();
    expect(screen.getByText("Active snapshot 6")).toBeInTheDocument();
    expect(fetchMock).toHaveBeenCalledTimes(3);
  });

  it("serializes refresh before validate and reload, then accepts later operations", async () => {
    const user = userEvent.setup();
    const pendingRefresh = deferred<Response>();
    const fetchMock = mockFetch([
      jsonResponse(inventoryWith("echo")),
      pendingRefresh.promise,
      jsonResponse(reloadResponse(7, inventoryWith("echo"))),
      jsonResponse(inventoryWith("planning"))
    ]);
    render(<DeveloperTools onBack={() => undefined} />);

    const refreshButton = await screen.findByRole("button", {
      name: "Refresh skill packages"
    });
    const validateButton = screen.getByRole("button", {
      name: "Validate all skill packages"
    });
    const reloadButton = screen.getByRole("button", { name: "Reload diagnostics" });
    act(() => {
      refreshButton.dispatchEvent(new MouseEvent("click", { bubbles: true }));
      validateButton.dispatchEvent(new MouseEvent("click", { bubbles: true }));
      reloadButton.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    });

    expect(fetchMock).toHaveBeenCalledTimes(2);
    expectWorkbenchBusy(true);
    await settleDeferred(pendingRefresh, jsonResponse(inventoryWith("planning")));
    expect(await screen.findByText("skills/planning")).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "Reload diagnostics" }));
    expect(screen.getByText("skills/echo")).toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: "Validate all skill packages" }));
    expect(await screen.findByText("skills/planning")).toBeInTheDocument();
    expect(screen.getByText("Active snapshot 7")).toBeInTheDocument();
    expect(fetchMock).toHaveBeenCalledTimes(4);
  });
});

function skillPackage(id: string): DevSkillPackage {
  return {
    id,
    path: id,
    name: id,
    description: `${id} package.`,
    hasSkillMd: true,
    hasRuntimeManifest: true,
    runtimeTools: [`${id}_tool`],
    packageKind: "combined",
    bundleReady: true,
    runtimeReady: true,
    instructionReady: true,
    releaseReady: true,
    readinessIssues: [],
    requiredRuntimeTools: [],
    requiredConnectors: [],
    hasPackageMetadata: true,
    validation: { ok: true, errors: [], warnings: [] }
  };
}

function inventoryWith(...ids: string[]): DevSkillInventory {
  return {
    root: "/repo/skills",
    packages: ids.map(skillPackage)
  };
}

function inventoryWithInstruction(id: string): DevSkillInventory {
  return {
    root: "/repo/skills",
    packages: [{
      ...skillPackage(id),
      hasRuntimeManifest: false,
      runtimeTools: [],
      packageKind: "instruction",
    }]
  };
}

function instructionSource(id: string) {
  return {
    directory: id,
    sourceRevision: "a".repeat(64),
    manifest: {
      schemaVersion: 1,
      id: `com.example.${id}`,
      version: "0.1.0",
      displayName: id,
      kind: "instruction_only",
      package: { includeInstructions: true, includeRuntime: false }
    },
    skillMd: `---\nname: ${id}\ndescription: ${id} instructions.\n---\n\n# ${id}\n`
  };
}

function reloadResponse(
  activeGeneration: number,
  inventory: DevSkillInventory
): DevSkillReloadResponse {
  return {
    inventory,
    previousGeneration: activeGeneration - 1,
    activeGeneration,
    activePackages: inventory.packages.length,
    inactivePackages: 0,
    reloadStatus: "published"
  };
}

async function settleDeferred<T>(pending: ReturnType<typeof deferred<T>>, value: T) {
  await act(async () => {
    pending.resolve(value);
    await Promise.resolve();
    await Promise.resolve();
  });
}

function expectWorkbenchBusy(isBusy: boolean) {
  const workbench = screen
    .getByRole("main", { name: "Developer Tools" })
    .querySelector("[aria-busy]");
  expect(workbench).toHaveAttribute("aria-busy", String(isBusy));
}

function modelSettingsBridge(options: {
  saved: boolean;
  startTurn?: (sessionId: string, requestId: string, content: string) => Promise<unknown>;
}): NonNullable<NonNullable<Window["agentWeave"]>["modelSettings"]> {
  return {
    clearApiKey: async () => ({}),
    load: async () => ({
      apiKeyConfigured: options.saved,
      baseUrl: "https://models.example.test/v1",
      endpointType: "responses",
      modelName: "agent-model",
      saved: options.saved,
    }),
    postSessionMessage: async () => ({}),
    save: async () => ({}),
    startSessionTurn: options.startTurn ?? (async () => ({})),
    testConnection: async () => ({}),
  };
}

function serverSession() {
  return {
    created_at: "2026-07-19T00:00:00Z",
    id: "skill-authoring-session",
    title: "Skill Creator",
    updated_at: "2026-07-19T00:00:00Z",
  };
}

function serverMessage(id: string, role: string, content: string) {
  return {
    content,
    created_at: "2026-07-19T00:00:00Z",
    id,
    role,
    session_id: "skill-authoring-session",
  };
}

function serverTurn(status: "running" | "completed" | "failed") {
  return {
    assistant_message_id: status === "completed" ? "assistant-message" : null,
    failure_message: status === "failed" ? "model failed" : null,
    finished_at: status === "running" ? null : "2026-07-19T00:00:01Z",
    id: "skill-authoring-turn",
    request_id: "request-1",
    session_id: "skill-authoring-session",
    started_at: "2026-07-19T00:00:00Z",
    status,
    updated_at: "2026-07-19T00:00:01Z",
    user_message_id: "user-message",
  };
}

function serverEvent(index: number, type: string, payload: Record<string, unknown> = {}) {
  return {
    created_at: "2026-07-19T00:00:01Z",
    event_index: index,
    id: `event-${index}`,
    kind: type,
    payload: { type, ...payload },
    session_id: "skill-authoring-session",
    turn_id: "skill-authoring-turn",
  };
}

function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<T>((resolvePromise, rejectPromise) => {
    resolve = resolvePromise;
    reject = rejectPromise;
  });
  return { promise, reject, resolve };
}

function jsonResponse(body: unknown): Response {
  return new Response(JSON.stringify(body), {
    headers: { "Content-Type": "application/json" },
    status: 200
  });
}

function mockFetch(responses: Array<Response | Promise<Response>>) {
  const fetchMock = vi.fn();
  for (const response of responses) {
    fetchMock.mockResolvedValueOnce(response);
  }
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}

function installDevApiBridge(inventory: DevSkillInventory): void {
  if (!window.agentWeave) throw new Error("Host bootstrap must be installed first");
  window.agentWeave.server = {
    request: async (operation) => {
      if (operation !== "devSkills.list") throw new Error(`Unexpected operation: ${operation}`);
      return inventory;
    },
  };
}
