import { act, cleanup, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";

import {
  DevSkillInventory,
  DevSkillPackage,
  DevSkillReloadResponse
} from "../src/renderer/api";
import { DeveloperTools } from "../src/renderer/screens/DeveloperTools";

vi.mock("../src/renderer/components/developer/DeleteSkillDialog", () => ({
  DeleteSkillDialog: ({
    onConfirm,
    skillPackage
  }: {
    onConfirm: (skillPackage: DevSkillPackage) => Promise<void>;
    skillPackage: DevSkillPackage | null;
  }) =>
    skillPackage ? (
      <button onClick={() => void onConfirm(skillPackage)} type="button">
        Confirm delete {skillPackage.id}
      </button>
    ) : null
}));

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe("DeveloperTools delete concurrency", () => {
  it("blocks delete while reload is pending and allows it after publication", async () => {
    const user = userEvent.setup();
    const pendingReload = deferred<Response>();
    const fetchMock = mockFetch([
      jsonResponse(inventoryWith("echo", "planning")),
      pendingReload.promise,
      jsonResponse(instructionSource("echo")),
      jsonResponse(inventoryWith("planning"))
    ]);
    render(<DeveloperTools onBack={() => undefined} />);

    const reloadButton = await screen.findByRole("button", { name: "Reload diagnostics" });
    await user.click(screen.getByRole("button", { name: "Delete package" }));
    const confirmDelete = screen.getByRole("button", { name: "Confirm delete echo" });
    act(() => {
      reloadButton.dispatchEvent(new MouseEvent("click", { bubbles: true }));
      confirmDelete.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    });

    expect(fetchMock).toHaveBeenCalledTimes(2);
    await settleDeferred(
      pendingReload,
      jsonResponse(reloadResponse(6, inventoryWith("echo", "planning")))
    );
    expect(screen.getByText("Active snapshot 6")).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "Confirm delete echo" }));
    await waitFor(() => expect(screen.queryByText("skills/echo")).not.toBeInTheDocument());
    expect(screen.getByText("skills/planning")).toBeInTheDocument();
    expect(screen.getByText("Active snapshot 6")).toBeInTheDocument();
    expect(fetchMock).toHaveBeenCalledTimes(4);
    expectWorkbenchBusy(false);
  });

  it("blocks reload while delete is pending and allows reload after deletion", async () => {
    const user = userEvent.setup();
    const pendingDelete = deferred<Response>();
    const fetchMock = mockFetch([
      jsonResponse(inventoryWith("echo", "planning")),
      jsonResponse(instructionSource("echo")),
      pendingDelete.promise,
      jsonResponse(reloadResponse(7, inventoryWith("planning")))
    ]);
    render(<DeveloperTools onBack={() => undefined} />);

    const reloadButton = await screen.findByRole("button", { name: "Reload diagnostics" });
    await user.click(screen.getByRole("button", { name: "Delete package" }));
    const confirmDelete = screen.getByRole("button", { name: "Confirm delete echo" });
    act(() => {
      confirmDelete.dispatchEvent(new MouseEvent("click", { bubbles: true }));
      reloadButton.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    });

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(3));
    await settleDeferred(pendingDelete, jsonResponse(inventoryWith("planning")));
    expect(await screen.findByText("skills/planning")).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "Reload diagnostics" }));
    expect(await screen.findByText("Active snapshot 7")).toBeInTheDocument();
    expect(fetchMock).toHaveBeenCalledTimes(4);
    expectWorkbenchBusy(false);
  });
});

function skillPackage(id: string): DevSkillPackage {
  return {
    id,
    path: id,
    name: id,
    description: `${id} package.`,
    hasSkillMd: true,
    hasRuntimeManifest: false,
    runtimeTools: [],
    packageKind: "instruction",
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

function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<T>((resolvePromise, rejectPromise) => {
    resolve = resolvePromise;
    reject = rejectPromise;
  });
  return { promise, reject, resolve };
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
