import { cleanup, render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import App from "../src/renderer/App";
import { OwnerSkillInventory, OwnerSkillPackage } from "../src/renderer/api";
import { OwnerPolicy } from "../src/renderer/ownerBridge";
import { OwnerSkills } from "../src/renderer/screens/OwnerSkills";
import type { ApprovalObservationResult } from "../src/shared/approvalObservation";
import detailFixture from "./fixtures/owner-package-detail.json";
import { installHostBootstrap } from "./hostBootstrapFixture";

class TestResizeObserver implements ResizeObserver {
  disconnect(): void {}
  observe(): void {}
  unobserve(): void {}
}

const ownerPolicy: OwnerPolicy = {
  mode: "owner_only",
  actorId: "owner-1",
  role: "owner",
  grants: ["inspect", "create_draft", "edit_draft", "validate", "activate", "rollback", "disable", "delete_managed"]
};
const inventorySummary = {
  package_id: "com.example.calendar", display_name: "Calendar Operations", version: "2.0.0", source_layer: "managed",
  status: "active", reason: "active", active_revision_id: "22222222-2222-4222-8222-222222222222",
  available: true, content_hash: "b454f82c5857ebabf342b7258e5cf7def78b7cd975814119462973de9a38df10",
  manageable: true
};
const inventoryActions = {
  can_edit_draft: true, can_validate_draft: true, can_request_activation: true,
  can_disable: true, can_request_removal: true, can_rollback: true
};
const inventory: OwnerSkillInventory = {
  effective: [inventorySummary],
  managed: [],
  packages: [{
    package_id: inventorySummary.package_id,
    effective: inventorySummary,
    managed: inventorySummary,
    built_in_collision: false,
    actions: inventoryActions
  }]
};

beforeEach(() => {
  vi.stubGlobal("ResizeObserver", TestResizeObserver);
  Object.defineProperty(window, "innerWidth", { configurable: true, value: 1280 });
});

afterEach(() => {
  cleanup();
  window.history.replaceState(null, "", "/");
  delete window.agentWeave;
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe("owner principal route gating", () => {
  it("hides settings and fails closed on direct route without inspect", async () => {
    window.history.replaceState(null, "", "/#owner-skills");
    installBridge({ policy: { ...ownerPolicy, grants: [] } });
    render(<App />);
    expect(screen.getByRole("main", { name: "Settings" })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Manage skills" })).not.toBeInTheDocument();
    await waitFor(() => expect(window.location.hash).toBe("#settings"));
  });

  it("uses the authenticated principal for an authorized owner route", async () => {
    const bridge = installBridge();
    render(<App />);
    await waitFor(() => expect(bridge.principal).toHaveBeenCalledTimes(1));
    await userEvent.click(screen.getByRole("button", { name: "Open settings" }));
    await userEvent.click(await screen.findByRole("button", { name: "Manage skills" }));
    expect(await screen.findByRole("main", { name: "Owner Skills" })).toBeInTheDocument();
    expect(await screen.findAllByText("Calendar Operations")).not.toHaveLength(0);
  });

  it("fails closed for a non-owner principal in owner_only mode", async () => {
    window.history.replaceState(null, "", "/#owner-skills");
    installBridge({ policy: { ...ownerPolicy, role: "operator" } });
    render(<App />);
    expect(screen.getByRole("main", { name: "Settings" })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Manage skills" })).not.toBeInTheDocument();
    await waitFor(() => expect(window.location.hash).toBe("#settings"));
  });
});

describe("owner workflows", () => {
  it("keeps all detail tabs shrinkable in the mobile viewport", async () => {
    Object.defineProperty(window, "innerWidth", { configurable: true, value: 390 });
    installBridge();
    renderOwner();
    await userEvent.click(await screen.findByRole("button", { name: /Calendar Operations/ }));

    const tabs = await screen.findAllByRole("tab");
    expect(tabs).toHaveLength(4);
    for (const tab of tabs) {
      expect(tab).toHaveStyle({ minWidth: "0", flex: "1 1 auto" });
    }
  });

  it("keeps effective builtin authoritative while showing a disabled managed collision", async () => {
    const effective = {
      package_id: "com.example.calendar", display_name: "Built-in Calendar", version: "3.0.0",
      source_layer: "builtin", status: "active", reason: "active",
      active_revision_id: "builtin:effective-hash", available: true, content_hash: "effective-hash", manageable: false
    };
    const managed = {
      package_id: "com.example.calendar", display_name: "Managed Calendar", version: "2.0.0",
      source_layer: "managed", status: "disabled", reason: "managed installation is disabled",
      active_revision_id: "22222222-2222-4222-8222-222222222222", available: false,
      content_hash: "managed-hash", manageable: false
    };
    const actions = {
      can_edit_draft: false, can_validate_draft: false, can_request_activation: false,
      can_disable: false, can_request_removal: false, can_rollback: false
    };
    const collision = {
      ...(structuredClone(detailFixture) as OwnerSkillPackage),
      display_name: effective.display_name,
      version: effective.version,
      source_layer: effective.source_layer,
      status: effective.status,
      active_revision_id: effective.active_revision_id,
      effective,
      managed,
      built_in_collision: true,
      actions
    };
    installBridge({
      detail: collision,
      inventory: {
        effective: [effective],
        managed: [managed],
        packages: [{ package_id: effective.package_id, effective, managed, built_in_collision: true, actions }]
      } as unknown as OwnerSkillInventory
    });

    renderOwner();

    expect(await screen.findByRole("heading", { name: "Built-in Calendar" })).toBeInTheDocument();
    expect(screen.getByText("Collision")).toBeInTheDocument();
    expect(screen.getByText("Managed disabled")).toBeInTheDocument();
    expect(screen.getByText("builtin:effective-hash")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Disable skill" })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Remove skill" })).not.toBeInTheDocument();
  });

  it("shows unavailable effective state while keeping backend-authorized recovery actions", async () => {
    const effective = {
      ...inventorySummary,
      status: "circuit_open",
      reason: "managed revision circuit open",
      available: false
    };
    const managed = { ...inventorySummary, status: "active", reason: "active", available: true };
    const detail = structuredClone(detailFixture) as OwnerSkillPackage;
    detail.status = effective.status;
    detail.reason = effective.reason;
    detail.effective = effective;
    detail.managed = managed;
    detail.actions = { ...inventoryActions, can_disable: true, can_rollback: true };
    detail.editable_draft = null;
    detail.revisions = detail.revisions.filter((revision) => !revision.editable);
    detail.revisions.push({
      ...structuredClone(detail.revisions[0]),
      revision_id: "11111111-1111-4111-8111-111111111111",
      status: "managed",
      version: "1.0.0"
    });
    installBridge({
      detail,
      inventory: {
        effective: [effective],
        managed: [managed],
        packages: [{
          package_id: effective.package_id,
          effective,
          managed,
          built_in_collision: false,
          actions: detail.actions
        }]
      }
    });

    renderOwner();

    expect(await screen.findByText("managed revision circuit open")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Disable skill" })).toBeEnabled();
    expect(screen.getByRole("button", { name: "Rollback to 1.0.0" })).toBeEnabled();
  });

  it("opens an independent approval surface and reloads after completion", async () => {
    const bridge = installBridge();
    renderOwner();
    await userEvent.click(await screen.findByRole("tab", { name: "Draft" }));
    await userEvent.click(screen.getByRole("button", { name: "Request activation" }));
    const dialog = await screen.findByRole("dialog", { name: "Skill activation approval requested" });
    expect(within(dialog).getByText("owner-1")).toBeInTheDocument();
    expect(within(dialog).getByText("Independent window")).toBeInTheDocument();
    await userEvent.click(within(dialog).getByRole("button", { name: "Open approval window" }));
    expect(await screen.findByText("Active snapshot 4")).toBeInTheDocument();
    expect(bridge.openApproval).toHaveBeenCalledWith("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa");
    expect(bridge.listSkills.mock.calls.length).toBeGreaterThan(1);
    expect(bridge.skillDetail.mock.calls.length).toBeGreaterThan(1);
  });

  it("keeps the request pending when the independent approval surface is unavailable", async () => {
    installBridge({ approvalError: new Error("Independent approval surface is unavailable") });
    renderOwner();
    await userEvent.click(await screen.findByRole("tab", { name: "Draft" }));
    await userEvent.click(screen.getByRole("button", { name: "Request activation" }));
    const dialog = await screen.findByRole("dialog", { name: "Skill activation approval requested" });
    await userEvent.click(within(dialog).getByRole("button", { name: "Open approval window" }));
    expect(await within(dialog).findByText("Independent approval surface is unavailable")).toBeInTheDocument();
  });

  it("keeps backend pending approval reopenable when observation is closed", async () => {
    const bridge = installBridge();
    bridge.openApproval
      .mockResolvedValueOnce({
        approvalId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        status: "closed"
      })
      .mockResolvedValueOnce({
        approvalId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        decision: "approve",
        status: "completed"
      });
    renderOwner();
    await userEvent.click(await screen.findByRole("tab", { name: "Draft" }));
    await userEvent.click(screen.getByRole("button", { name: "Request activation" }));
    const dialog = await screen.findByRole("dialog", { name: "Skill activation approval requested" });

    await userEvent.click(within(dialog).getByRole("button", { name: "Open approval window" }));

    expect(await within(dialog).findByRole("alert")).toHaveTextContent(
      "Approval window closed. The request remains pending."
    );
    expect(screen.queryByText("Skill operation approved")).not.toBeInTheDocument();
    await userEvent.click(within(dialog).getByRole("button", { name: "Open approval window" }));
    expect(await screen.findByText("Skill operation approved")).toBeInTheDocument();
    expect(bridge.openApproval).toHaveBeenCalledTimes(2);
  });

  it("does not expose a draft editor for an active package without editable_draft", async () => {
    const activeOnly = structuredClone(detailFixture) as OwnerSkillPackage;
    activeOnly.revisions = activeOnly.revisions.filter((revision) => !revision.editable);
    activeOnly.editable_draft = null;
    installBridge({ detail: activeOnly });
    renderOwner();
    expect(await screen.findAllByText("Calendar Operations")).not.toHaveLength(0);
    expect(screen.queryByRole("tab", { name: "Draft" })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Request activation" })).not.toBeInTheDocument();
  });

  it("invalidates activation, removal, and the global validation state after an edit", async () => {
    const bridge = installBridge();
    renderOwner();
    await userEvent.click(await screen.findByRole("tab", { name: "Draft" }));
    expect(screen.getByRole("button", { name: "Request activation" })).toBeEnabled();
    expect(screen.getByRole("button", { name: "Remove skill" })).toBeEnabled();
    await userEvent.type(screen.getByRole("textbox", { name: "Instructions" }), " changed");
    expect(screen.getByRole("button", { name: "Request activation" })).toBeDisabled();
    expect(screen.getByRole("button", { name: "Remove skill" })).toBeDisabled();
    expect(screen.getByText("Validation is required before activation or removal")).toBeInTheDocument();
    expect(screen.getByText("Validation has not run")).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "Validate draft" }));
    await waitFor(() => expect(screen.getByRole("button", { name: "Remove skill" })).toBeEnabled());
    await userEvent.click(screen.getByRole("button", { name: "Remove skill" }));
    expect(bridge.updateDraft).toHaveBeenLastCalledWith(
      "33333333-3333-4333-8333-333333333333",
      expect.arrayContaining([expect.objectContaining({ path: "SKILL.md", content: expect.stringContaining("changed") })])
    );
    expect(bridge.requestRemoval).toHaveBeenCalledWith("com.example.calendar");
  });

  it("invalidates all publication gates when required tools change", async () => {
    installBridge();
    renderOwner();
    await userEvent.click(await screen.findByRole("tab", { name: "Draft" }));
    await userEvent.type(screen.getByRole("textbox", { name: "Required host tools" }), ", calendar.write");
    expect(screen.getByRole("button", { name: "Request activation" })).toBeDisabled();
    expect(screen.getByRole("button", { name: "Remove skill" })).toBeDisabled();
    expect(screen.getByText("Validation is required before activation or removal")).toBeInTheDocument();
  });

  it("never offers rollback to an editable staging revision", async () => {
    installBridge();
    renderOwner();
    expect(await screen.findAllByText("Calendar Operations")).not.toHaveLength(0);
    await userEvent.click(screen.getByRole("tab", { name: "Revisions" }));
    expect(screen.queryByRole("button", { name: "Rollback to 2.1.0" })).not.toBeInTheDocument();
  });

  it("discards validation for package A after package B is selected", async () => {
    let resolveValidation!: (value: { ok: boolean; errors: string[]; warnings: string[] }) => void;
    const validation = new Promise<{ ok: boolean; errors: string[]; warnings: string[] }>((resolve) => {
      resolveValidation = resolve;
    });
    const packageA = packageDetail("com.example.calendar", "Calendar Operations", true);
    const packageB = packageDetail("com.example.mail", "Mail Operations", true);
    packageB.editable_draft!.validation = { ok: false, errors: ["Validation has not run"], warnings: [] };
    packageB.revisions[0].validation = { ok: false, errors: ["Validation has not run"], warnings: [] };
    const bridge = installBridge({
      details: { [packageA.package_id]: packageA, [packageB.package_id]: packageB },
      inventory: inventoryFor(packageA, packageB)
    });
    bridge.validateDraft.mockReturnValueOnce(validation);
    renderOwner();
    await userEvent.click(await screen.findByRole("tab", { name: "Draft" }));
    await userEvent.click(screen.getByRole("button", { name: "Validate draft" }));
    await waitFor(() => expect(bridge.validateDraft).toHaveBeenCalled());
    const list = screen.getByRole("list", { name: "Skill packages" });
    await userEvent.click(within(list).getByRole("button", { name: /Mail Operations/ }));
    expect(await screen.findByRole("heading", { name: "Mail Operations" })).toBeInTheDocument();
    await userEvent.click(screen.getByRole("tab", { name: "Draft" }));
    resolveValidation({ ok: true, errors: [], warnings: [] });
    await waitFor(() => expect(screen.getByRole("button", { name: "Request activation" })).toBeDisabled());
    expect(screen.getByText("Validation is required before activation or removal")).toBeInTheDocument();
  });

  it("shows a real instruction diff with unchanged front matter", async () => {
    installBridge();
    renderOwner();
    await userEvent.click(await screen.findByRole("tab", { name: "Draft" }));
    await userEvent.click(screen.getByRole("button", { name: "Request activation" }));
    const dialog = await screen.findByRole("dialog", { name: "Skill activation approval requested" });
    const unchanged = [...dialog.querySelectorAll('[data-diff-kind="unchanged"]')];
    const removed = [...dialog.querySelectorAll('[data-diff-kind="removed"]')];
    const added = [...dialog.querySelectorAll('[data-diff-kind="added"]')];
    expect(unchanged.some((line) => line.textContent?.endsWith("---"))).toBe(true);
    expect(removed.some((line) => line.textContent?.endsWith("Review daily calendar."))).toBe(true);
    expect(added.some((line) => line.textContent?.endsWith("Review calendar and summarize conflicts."))).toBe(true);
    expect(added.some((line) => line.textContent?.endsWith("Flag overlapping focus blocks."))).toBe(true);
  });

  it("merges authoritative validation requirements into approval", async () => {
    installBridge({ validation: {
      ok: true, errors: [], warnings: [], requiredTools: ["calendar.write"],
      requiredCapabilities: ["calendar.modify"], requiredConnectors: ["cloud.calendar"],
      dependencies: ["com.example.base"], permissionDiff: { capabilities: { added: ["calendar.modify"] } }
    }});
    renderOwner();
    await userEvent.click(await screen.findByRole("tab", { name: "Draft" }));
    await userEvent.click(screen.getByRole("button", { name: "Validate draft" }));
    await userEvent.click(await screen.findByRole("button", { name: "Request activation" }));
    const dialog = await screen.findByRole("dialog", { name: "Skill activation approval requested" });
    expect(within(dialog).getByText("calendar.write")).toBeInTheDocument();
    expect(within(dialog).getByText("calendar.modify")).toBeInTheDocument();
    expect(within(dialog).getByText("cloud.calendar")).toBeInTheDocument();
    expect(within(dialog).getByText("com.example.base")).toBeInTheDocument();
  });

  it("persists current editor bytes before validation and stops on save failure", async () => {
    const bridge = installBridge();
    bridge.updateDraft.mockRejectedValueOnce(new Error("Draft content is invalid"));
    renderOwner();
    await userEvent.click(await screen.findByRole("tab", { name: "Draft" }));
    await userEvent.type(screen.getByRole("textbox", { name: "Instructions" }), " unsaved");
    await userEvent.click(screen.getByRole("button", { name: "Validate draft" }));
    expect(await screen.findByText("Draft content is invalid")).toBeInTheDocument();
    expect(bridge.updateDraft).toHaveBeenCalled();
    expect(bridge.validateDraft).not.toHaveBeenCalled();
    expect((screen.getByRole("textbox", { name: "Instructions" }) as HTMLTextAreaElement).value).toContain("unsaved");
  });

  it("retains current editor content after authoritative validation errors", async () => {
    installBridge({ validation: { ok: false, errors: ["SKILL.md must start with front matter"], warnings: [] } });
    renderOwner();
    await userEvent.click(await screen.findByRole("tab", { name: "Draft" }));
    const editor = screen.getByRole("textbox", { name: "Instructions" });
    await userEvent.clear(editor);
    await userEvent.type(editor, "No front matter");
    await userEvent.click(screen.getByRole("button", { name: "Validate draft" }));
    expect(await screen.findByText("SKILL.md must start with front matter")).toBeInTheDocument();
    expect(editor).toHaveValue("No front matter");
    expect(screen.getByRole("button", { name: "Request activation" })).toBeDisabled();
  });

  it("keeps inventory visible and surfaces refresh failure", async () => {
    const bridge = installBridge();
    renderOwner();
    expect(await screen.findAllByText("Calendar Operations")).not.toHaveLength(0);
    bridge.listSkills.mockRejectedValueOnce(new Error("refresh unavailable"));
    await userEvent.click(screen.getByRole("button", { name: "Refresh skills" }));
    expect(await screen.findByText("refresh unavailable")).toBeInTheDocument();
    expect(screen.getAllByText("Calendar Operations")).not.toHaveLength(0);
  });

  it("keeps the approval dialog open and visible after approval failure", async () => {
    const bridge = installBridge();
    bridge.openApproval.mockRejectedValueOnce(new Error("approver service unavailable"));
    renderOwner();
    await userEvent.click(await screen.findByRole("tab", { name: "Draft" }));
    await userEvent.click(screen.getByRole("button", { name: "Request activation" }));
    const dialog = await screen.findByRole("dialog", { name: "Skill activation approval requested" });
    await userEvent.click(within(dialog).getByRole("button", { name: "Open approval window" }));
    expect(await within(dialog).findByRole("alert")).toHaveTextContent("approver service unavailable");
    expect(dialog).toBeInTheDocument();
  });

  it("resets to Overview after activation removes the Draft tab", async () => {
    let current = packageDetail("com.example.calendar", "Calendar Operations", true);
    const bridge = installBridge();
    bridge.skillDetail.mockImplementation(async () => structuredClone(current));
    renderOwner();
    await userEvent.click(await screen.findByRole("tab", { name: "Draft" }));
    await userEvent.click(screen.getByRole("button", { name: "Request activation" }));
    const dialog = await screen.findByRole("dialog", { name: "Skill activation approval requested" });
    current = packageDetail("com.example.calendar", "Calendar Operations", false);
    await userEvent.click(within(dialog).getByRole("button", { name: "Open approval window" }));
    expect(await screen.findByText("Active snapshot 4")).toBeInTheDocument();
    const overview = screen.getByRole("tab", { name: "Overview" });
    await waitFor(() => expect(overview).toHaveAttribute("data-state", "active"));
    expect(screen.getByText("Package kind")).toBeInTheDocument();
  });

  it("resets to Overview when switching from Draft to a package without a draft", async () => {
    const packageA = packageDetail("com.example.calendar", "Calendar Operations", true);
    const packageB = packageDetail("com.example.mail", "Mail Operations", false);
    installBridge({
      details: { [packageA.package_id]: packageA, [packageB.package_id]: packageB },
      inventory: inventoryFor(packageA, packageB)
    });
    renderOwner();
    await userEvent.click(await screen.findByRole("tab", { name: "Draft" }));
    const list = screen.getByRole("list", { name: "Skill packages" });
    await userEvent.click(within(list).getByRole("button", { name: /Mail Operations/ }));
    expect(await screen.findByRole("heading", { name: "Mail Operations" })).toBeInTheDocument();
    await waitFor(() => expect(screen.getByRole("tab", { name: "Overview" })).toHaveAttribute("data-state", "active"));
    expect(screen.queryByRole("tab", { name: "Draft" })).not.toBeInTheDocument();
  });

  it("resolves approval-required rollback with the approver and reloads", async () => {
    const rollbackDetail = structuredClone(detailFixture) as OwnerSkillPackage;
    rollbackDetail.editable_draft = null;
    rollbackDetail.revisions = rollbackDetail.revisions.filter((revision) => !revision.editable);
    rollbackDetail.revisions.push({
      ...structuredClone(rollbackDetail.revisions[0]),
      revision_id: "11111111-1111-4111-8111-111111111111",
      version: "1.0.0"
    });
    const bridge = installBridge({ detail: rollbackDetail });
    bridge.rollback.mockResolvedValueOnce({
      approval_id: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
      package_id: "com.example.calendar",
      permission_diff: {}, requested_by: "owner-1",
      revision_id: "11111111-1111-4111-8111-111111111111", status: "pending"
    });
    renderOwner();
    await userEvent.click(await screen.findByRole("button", { name: "Rollback to 1.0.0" }));
    const dialog = await screen.findByRole("dialog", { name: "Skill rollback approval requested" });
    await userEvent.click(within(dialog).getByRole("button", { name: "Open approval window" }));
    expect(bridge.openApproval).toHaveBeenCalledWith("cccccccc-cccc-4ccc-8ccc-cccccccccccc");
    expect(bridge.listSkills.mock.calls.length).toBeGreaterThan(1);
  });

  it("routes removal approval through the independent approver", async () => {
    const activeOnly = structuredClone(detailFixture) as OwnerSkillPackage;
    activeOnly.editable_draft = null;
    activeOnly.revisions = activeOnly.revisions.filter((revision) => !revision.editable);
    const bridge = installBridge({ detail: activeOnly });
    renderOwner();
    await userEvent.click(await screen.findByRole("button", { name: "Remove skill" }));
    const dialog = await screen.findByRole("dialog", { name: "Skill removal approval requested" });
    await userEvent.click(within(dialog).getByRole("button", { name: "Open approval window" }));
    expect(bridge.requestRemoval).toHaveBeenCalledWith("com.example.calendar");
    expect(bridge.openApproval).toHaveBeenCalledWith("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb");
  });

  it("hides inapplicable lifecycle actions for removed packages", async () => {
    const removed = structuredClone(detailFixture) as OwnerSkillPackage;
    removed.status = "removed";
    removed.actions = {
      ...removed.actions,
      can_disable: false,
      can_request_removal: false,
      can_rollback: false
    };
    removed.editable_draft = null;
    removed.revisions = removed.revisions.filter((revision) => !revision.editable);
    installBridge({ detail: removed });
    renderOwner();
    expect(await screen.findAllByText("Calendar Operations")).not.toHaveLength(0);
    expect(screen.queryByRole("button", { name: "Disable skill" })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Remove skill" })).not.toBeInTheDocument();
  });

  it("synchronizes the editor when refreshing the same selected package", async () => {
    const bridge = installBridge();
    let current = structuredClone(detailFixture) as OwnerSkillPackage;
    bridge.skillDetail.mockImplementation(async () => structuredClone(current));
    renderOwner();
    await userEvent.click(await screen.findByRole("tab", { name: "Draft" }));
    expect(screen.getByRole("textbox", { name: "Instructions" })).toHaveValue(current.editable_draft?.instructions);
    current = structuredClone(current);
    current.editable_draft!.instructions = "# Refreshed authoritative draft";
    current.revisions[0].instructions = "# Refreshed authoritative draft";
    await userEvent.click(screen.getByRole("button", { name: "Refresh skills" }));
    await waitFor(() => expect(screen.getByRole("textbox", { name: "Instructions" })).toHaveValue("# Refreshed authoritative draft"));
  });

  it("ignores an older inventory response that resolves last", async () => {
    let resolveOld!: (value: typeof inventory) => void;
    const old = new Promise<typeof inventory>((resolve) => { resolveOld = resolve; });
    const newerSummary = { ...inventorySummary, package_id: "com.example.newer" };
    const newer: OwnerSkillInventory = {
      effective: [newerSummary], managed: [],
      packages: [{ package_id: newerSummary.package_id, effective: newerSummary, managed: null, built_in_collision: false, actions: inventoryActions }]
    };
    const bridge = installBridge();
    bridge.listSkills.mockReset().mockReturnValueOnce(old).mockResolvedValueOnce(newer);
    bridge.skillDetail.mockImplementation(async (id: string) => ({ ...detailFixture, package_id: id, display_name: id }));
    renderOwner();
    await userEvent.click(screen.getByRole("button", { name: "Refresh skills" }));
    expect(await screen.findAllByText("com.example.newer")).not.toHaveLength(0);
    resolveOld(inventory);
    await waitFor(() => expect(screen.queryByText("com.example.calendar")).not.toBeInTheDocument());
  });

  it("keeps package controls as buttons and renders mobile revisions as vertical records", async () => {
    Object.defineProperty(window, "innerWidth", { configurable: true, value: 390 });
    installBridge();
    renderOwner();
    const list = await screen.findByRole("list", { name: "Skill packages" });
    const packageButton = within(list).getByRole("button");
    await userEvent.click(packageButton);
    await userEvent.click(await screen.findByRole("tab", { name: "Revisions" }));
    expect(screen.queryByRole("table", { name: "Revision history" })).not.toBeInTheDocument();
    expect(screen.getByRole("list", { name: "Revision history" })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Rollback to 2.1.0" })).not.toBeInTheDocument();
  });

  it("uses Radix icon buttons with tooltips for owner navigation actions", async () => {
    installBridge();
    renderOwner();
    expect(await screen.findAllByText("Calendar Operations")).not.toHaveLength(0);
    expect(screen.getByRole("button", { name: "Back to settings" })).toHaveClass("rt-IconButton");
    expect(screen.getByRole("button", { name: "Refresh skills" })).toHaveClass("rt-IconButton");
  });
});

function renderOwner() {
  return render(<OwnerSkills onBack={() => undefined} policy={ownerPolicy} />);
}

function installBridge(options: {
  policy?: OwnerPolicy;
  approvalError?: Error;
  detail?: OwnerSkillPackage;
  details?: Record<string, OwnerSkillPackage>;
  inventory?: OwnerSkillInventory;
  validation?: Record<string, unknown>;
} = {}) {
  const requester = principal(options.policy ?? ownerPolicy);
  const openApproval = vi.fn<(approvalId: string) => Promise<ApprovalObservationResult>>();
  if (options.approvalError) {
    openApproval.mockRejectedValue(options.approvalError);
  } else {
    openApproval.mockImplementation(async (approvalId: string) => ({
      approvalId,
      decision: "approve",
      resolution: { active_generation: 4 },
      status: "completed"
    }));
  }
  const api = {
    principal: vi.fn(async () => requester),
    listSkills: vi.fn(async () => options.inventory ?? inventory),
    skillDetail: vi.fn(async (id: string) => structuredClone(
      options.details?.[id] ?? options.detail ?? detailFixture
    )),
    createDraft: vi.fn(),
    updateDraft: vi.fn(async () => ({})),
    validateDraft: vi.fn(async () => options.validation ?? { ok: true, errors: [], warnings: [] }),
    requestActivation: vi.fn(async () => ({
      approval_id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", package_id: "com.example.calendar",
      permission_diff: {}, requested_by: "owner-1", revision_id: "33333333-3333-4333-8333-333333333333", status: "pending"
    })),
    rollback: vi.fn(async (): Promise<Record<string, unknown>> => ({ generation: 5 })),
    disable: vi.fn(async () => ({})),
    requestRemoval: vi.fn(async () => ({
      approval_id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", package_id: "com.example.calendar",
      permission_diff: {}, requested_by: "owner-1", revision_id: "22222222-2222-4222-8222-222222222222", status: "pending"
    }))
  };
  window.agentWeave = { owner: api, approval: { open: openApproval } };
  installHostBootstrap();
  return { ...api, openApproval };
}

function packageDetail(packageId: string, displayName: string, withDraft: boolean): OwnerSkillPackage {
  const detail = structuredClone(detailFixture) as OwnerSkillPackage;
  detail.package_id = packageId;
  detail.display_name = displayName;
  if (detail.effective) {
    detail.effective.package_id = packageId;
    detail.effective.display_name = displayName;
  }
  if (detail.managed) {
    detail.managed.package_id = packageId;
    detail.managed.display_name = displayName;
  }
  if (packageId !== "com.example.calendar") {
    detail.active_revision_id = "44444444-4444-4444-8444-444444444444";
    detail.revisions[0].revision_id = "55555555-5555-4555-8555-555555555555";
    detail.revisions[1].revision_id = detail.active_revision_id;
    detail.editable_draft!.revision_id = detail.revisions[0].revision_id;
  }
  if (!withDraft) {
    detail.revisions = detail.revisions.filter((revision) => !revision.editable);
    detail.editable_draft = null;
  }
  return detail;
}

function inventoryFor(...details: OwnerSkillPackage[]): OwnerSkillInventory {
  const packages = details.map((detail) => ({
    package_id: detail.package_id,
    effective: detail.effective,
    managed: detail.managed,
    built_in_collision: detail.built_in_collision,
    actions: detail.actions
  }));
  return {
    effective: packages.flatMap((item) => item.effective ? [item.effective] : []),
    managed: packages.flatMap((item) => item.managed ? [item.managed] : []),
    packages
  };
}

function principal(policy: OwnerPolicy) {
  const { actorId, role, grants, ...policyFields } = policy;
  return { actorId, role: role ?? "owner", grants, policy: policyFields };
}
