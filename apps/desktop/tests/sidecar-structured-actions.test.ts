// @vitest-environment node

import { describe, expect, it, vi } from "vitest";

import {
  describeStructuredActionRequest,
  handleStructuredActionResponse,
} from "../src/main/sidecarStructuredActions";

describe("trusted structured action bridge", () => {
  it("maps only an opaque binding and constrained input to the fixed session path", () => {
    expect(describeStructuredActionRequest("structuredActions.accept", {
      bindingId: "binding-1",
      input: { confirmation: true },
      sessionId: "session-1",
    })).toEqual({
      body: { input: { confirmation: true } },
      method: "POST",
      pathname: "/sessions/session-1/structured-actions/binding-1/accept",
      structuredAction: true,
    });
    expect(() => describeStructuredActionRequest("structuredActions.accept", {
      bindingId: "binding-1",
      providerId: "attacker-controlled",
      sessionId: "session-1",
    })).toThrow(/unknown fields/);
  });

  it("opens a validated HTTPS Host directive and returns only the public receipt", async () => {
    const openExternal = vi.fn(async () => undefined);
    const receipt = { action_id: "connect", binding_id: "binding-1", payload: { status: "pending" } };
    await expect(handleStructuredActionResponse({
      openExternal,
      sidecarRequest: vi.fn(),
      value: {
        receipt,
        hostDirective: {
          type: "open_external",
          authorization_id: "authorization-1",
          expected_origin: "https://accounts.example.test",
          url: "https://accounts.example.test/oauth/authorize?state=secret",
        },
      },
    })).resolves.toEqual(receipt);
    expect(openExternal).toHaveBeenCalledWith(
      "https://accounts.example.test/oauth/authorize?state=secret",
    );
  });

  it.each([undefined, null])(
    "returns only the receipt when the Host directive is %s",
    async (hostDirective) => {
      const openExternal = vi.fn();
      const receipt = { action_id: "connect", binding_id: "binding-1" };
      await expect(handleStructuredActionResponse({
        openExternal,
        sidecarRequest: vi.fn(),
        value: { hostDirective, receipt },
      })).resolves.toEqual(receipt);
      expect(openExternal).not.toHaveBeenCalled();
    },
  );

  it.each([
    ["HTTP", "http://accounts.example.test/oauth", "http://accounts.example.test"],
    ["another origin", "https://attacker.example.test/oauth", "https://accounts.example.test"],
    ["userinfo", "https://user:secret@accounts.example.test/oauth", "https://accounts.example.test"],
    ["fragment", "https://accounts.example.test/oauth#secret", "https://accounts.example.test"],
  ])("rejects %s directives before opening a browser", async (_name, url, expectedOrigin) => {
    const openExternal = vi.fn();
    await expect(handleStructuredActionResponse({
      openExternal,
      sidecarRequest: vi.fn(),
      value: {
        receipt: { action_id: "connect" },
        hostDirective: {
          type: "open_external",
          authorization_id: "authorization-1",
          expected_origin: expectedOrigin,
          url,
        },
      },
    })).rejects.toThrow(/URL is invalid/);
    expect(openExternal).not.toHaveBeenCalled();
  });

  it("cancels a prepared OAuth transaction when the system browser cannot open", async () => {
    const sidecarRequest = vi.fn(async () => new Response("{}"));
    await expect(handleStructuredActionResponse({
      openExternal: vi.fn(async () => { throw new Error("system failure with secret URL"); }),
      sidecarRequest,
      value: {
        receipt: { action_id: "connect" },
        hostDirective: {
          type: "open_external",
          authorization_id: "authorization-1",
          expected_origin: "https://accounts.example.test",
          url: "https://accounts.example.test/oauth?state=secret",
        },
      },
    })).rejects.toThrow("Structured OAuth authorization could not be opened");
    expect(sidecarRequest).toHaveBeenCalledWith(
      "/host/oauth/authorizations/authorization-1",
      { method: "DELETE" },
    );
  });
});
