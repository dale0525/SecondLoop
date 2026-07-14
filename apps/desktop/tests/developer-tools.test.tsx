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
    window.history.replaceState(null, "", "/#developer");
    mockFetch([
      jsonResponse({
        root: "/repo/skills",
        packages: []
      })
    ]);

    render(<App />);

    expect(
      await screen.findByRole("main", { name: "Developer Tools" })
    ).toBeInTheDocument();
  });

  it("shows settings developer entry only when the dev API is available", async () => {
    installHostBootstrap();
    const user = userEvent.setup();
    mockFetch([
      jsonResponse({ root: "/repo/skills", packages: [] }),
      jsonResponse({ root: "/repo/skills", packages: [] })
    ]);

    render(<App />);

    await user.click(screen.getByRole("button", { name: "Open settings" }));

    expect(
      await screen.findByRole("button", { name: "Open developer tools" })
    ).toBeInTheDocument();
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

  it("opens a skill-creator prompt dialog for a selected package", async () => {
    const user = userEvent.setup();
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

    await user.click(
      await screen.findByRole("button", { name: "Modify with skill-creator" })
    );

    const dialog = screen.getByRole("dialog", { name: "skill-creator prompt" });
    expect(dialog).toBeInTheDocument();
    expect(
      within(dialog).getByText(/Use the existing skill-creator skill/)
    ).toBeInTheDocument();
  });

  it("deletes a package after confirmation and refreshes inventory", async () => {
    const user = userEvent.setup();
    const fetchMock = mockFetch([
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
      }),
      jsonResponse({ root: "/repo/skills", packages: [] })
    ]);

    render(<DeveloperTools onBack={() => undefined} />);

    await user.click(await screen.findByRole("button", { name: "Delete package" }));
    await user.click(screen.getByRole("button", { name: "Delete echo" }));

    await waitFor(() => {
      expect(screen.getByText("No skill packages found")).toBeInTheDocument();
    });
    expect(fetchMock).toHaveBeenLastCalledWith(
      "http://127.0.0.1:49321/dev/skills/echo",
      expect.objectContaining({ method: "DELETE" })
    );
  });

  it("closes the delete dialog and shows an error when deletion fails", async () => {
    const user = userEvent.setup();
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
      }),
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

    await screen.findByRole("button", { name: "Modify with skill-creator" });
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
