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

    expect(prompt).toContain("Use the existing skill-creator skill");
    expect(prompt).toContain("skills/");
    expect(prompt).not.toContain("/home/developer");
    expect(prompt).toContain("SKILL.md is a development authoring asset");
    expect(prompt).toContain("skill.json is the AgentWeave runtime contract");
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

    expect(prompt).toContain("Use the existing skill-creator skill");
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

  it("opens, saves, and reloads an instruction Skill in the simple editor", async () => {
    const user = userEvent.setup();
    const inventory = inventoryWithInstruction("briefing");
    const source = {
      directory: "briefing",
      sourceRevision: "a".repeat(64),
      manifest: {
        schemaVersion: 1,
        id: "com.example.secretary.briefing",
        version: "0.1.0",
        displayName: "Briefing",
        kind: "instruction_only",
        package: { includeInstructions: true, includeRuntime: false },
        compatibility: { platforms: ["desktop"] },
        requires: { packages: [], capabilities: [], runtimeTools: [], connectors: [] }
      },
      skillMd: "---\nname: briefing\ndescription: Prepare a briefing.\n---\n\n# Briefing\n"
    };
    const fetchMock = mockFetch([
      jsonResponse(inventory),
      jsonResponse(source),
      jsonResponse({ inventory, source: { ...source, sourceRevision: "b".repeat(64) } }),
      jsonResponse(reloadResponse(3, inventory))
    ]);

    render(<DeveloperTools onBack={() => undefined} />);

    await user.click(await screen.findByRole("button", { name: "Edit skill" }));

    const dialog = screen.getByRole("dialog", { name: "Edit skill" });
    const displayName = await within(dialog).findByDisplayValue("Briefing");
    await user.clear(displayName);
    await user.type(displayName, "Daily Briefing");
    await user.click(within(dialog).getByRole("button", { name: "Save and reload" }));

    await waitFor(() => expect(screen.queryByRole("dialog", { name: "Edit skill" })).not.toBeInTheDocument());
    const snapshot = screen.getByText("Active snapshot 3");
    expect(snapshot).toBeInTheDocument();
    expect(snapshot.closest(".developer-status-banner")).not.toHaveClass(
      "developer-status-banner-error",
    );
    expect(fetchMock).toHaveBeenNthCalledWith(2, "/__agentweave/dev/skills/briefing", expect.objectContaining({ method: "GET" }));
    expect(fetchMock).toHaveBeenNthCalledWith(3, "/__agentweave/dev/skills/briefing", expect.objectContaining({ method: "PUT" }));
    expect(fetchMock).toHaveBeenNthCalledWith(4, "/__agentweave/dev/skills/reload", expect.objectContaining({ method: "POST" }));
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
