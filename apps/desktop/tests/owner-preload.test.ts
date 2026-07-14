import { beforeEach, describe, expect, it, vi } from "vitest";

import {
  createOwnerTransport,
  normalizeOwnerRequest
} from "../src/preload/ownerTransport";

beforeEach(() => {
  vi.restoreAllMocks();
});

describe("owner preload capability", () => {
  it("rejects traversal, non-owner paths, origins, and unsupported methods", () => {
    for (const path of [
      "/owner/../sessions",
      "/owner/%2e%2e/sessions",
      "/owner/skills/../../model/test",
      "/sessions",
      "http://attacker.invalid/owner/skills"
    ]) {
      expect(() => normalizeOwnerRequest(path, "GET")).toThrow(/not allowed/);
    }
    expect(() => normalizeOwnerRequest("/owner/skills", "PATCH")).toThrow(
      /method is not allowed/
    );
  });

  it("exposes only typed owner operations over one trusted IPC channel", async () => {
    const invoke = vi.fn(async () => ({ effective: [], managed: [] }));
    const transport = createOwnerTransport({ invoke });

    await transport.listSkills();

    expect(invoke).toHaveBeenCalledWith(
      "agentweave:owner:request",
      { operation: "listSkills" },
    );
  });

  it("does not expose approver identity or resolution capability to requester renderer", () => {
    const transport = createOwnerTransport({
      invoke: vi.fn(),
    });

    expect("approverPrincipal" in transport).toBe(false);
    expect("resolveApproval" in transport).toBe(false);
    expect(Object.keys(transport)).not.toContain("request");
  });
});
