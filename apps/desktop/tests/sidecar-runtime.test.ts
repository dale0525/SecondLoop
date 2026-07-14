import path from "node:path";

import { describe, expect, it, vi } from "vitest";

import { resolveDesktopSidecar } from "../src/main/sidecarRuntime";

const TRANSPORT_TOKEN = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ";

const baseOptions = {
  appPath: "/repo/apps/desktop",
  env: {
    AGENTWEAVE_APP_DATA_ROOT: "/untrusted/override",
    PATH: "/usr/bin",
    UNRELATED_SECRET: "must-not-be-inherited",
  },
  isPackaged: false,
  platform: "darwin" as const,
  resourcesPath: "/app/resources",
  userDataPath: "/user/AgentWeave",
};

describe("desktop sidecar runtime resolution", () => {
  it("gives an explicit external URL priority without resolving an executable", () => {
    const isExecutable = vi.fn(() => true);
    const resolution = resolveDesktopSidecar({
      ...baseOptions,
      env: {
        AGENTWEAVE_SERVER_URL: "https://sidecar.example.test",
        AGENTWEAVE_SERVER_TOKEN: TRANSPORT_TOKEN,
        AGENTWEAVE_SIDECAR_EXECUTABLE: "/ignored/agent-server",
      },
      isExecutable,
    });

    expect(resolution).toEqual({
      baseUrl: "https://sidecar.example.test/",
      mode: "external",
      transportToken: TRANSPORT_TOKEN,
    });
    expect(isExecutable).not.toHaveBeenCalled();
  });

  it("fails closed for an invalid explicit URL or executable", () => {
    expect(resolveDesktopSidecar({
      ...baseOptions,
      env: { AGENTWEAVE_SERVER_URL: "file:///tmp/server.sock" },
      isExecutable: () => true,
    })).toMatchObject({ mode: "unavailable", reason: "invalid-server-url" });
    expect(resolveDesktopSidecar({
      ...baseOptions,
      env: { AGENTWEAVE_SERVER_URL: "https://sidecar.example.test" },
      isExecutable: () => true,
    })).toMatchObject({ mode: "unavailable", reason: "missing-server-token" });
    expect(resolveDesktopSidecar({
      ...baseOptions,
      env: {
        AGENTWEAVE_SERVER_TOKEN: "short",
        AGENTWEAVE_SERVER_URL: "http://127.0.0.1:49321",
      },
      isExecutable: () => true,
    })).toMatchObject({ mode: "unavailable", reason: "invalid-server-token" });
    expect(resolveDesktopSidecar({
      ...baseOptions,
      env: { AGENTWEAVE_SERVER_URL: "http://sidecar.example.test" },
      isExecutable: () => true,
    })).toMatchObject({ mode: "unavailable", reason: "invalid-server-url" });

    expect(resolveDesktopSidecar({
      ...baseOptions,
      env: { AGENTWEAVE_SIDECAR_EXECUTABLE: "relative/agent-server" },
      isExecutable: () => true,
    })).toMatchObject({ mode: "unavailable", reason: "invalid-executable" });
  });

  it("prefers the packaged executable and prepares private runtime paths", () => {
    const packagedExecutable = "/app/resources/sidecar/agent-server";
    const resolution = resolveDesktopSidecar({
      ...baseOptions,
      isExecutable: (candidate) => candidate === packagedExecutable,
      isPackaged: true,
    });

    expect(resolution).toMatchObject({
      command: packagedExecutable,
      cwd: "/app/resources",
      mode: "managed",
      dataRoot: path.join("/user/AgentWeave", "sidecar", "data"),
      cacheRoot: path.join("/user/AgentWeave", "sidecar", "cache"),
    });
    if (resolution.mode !== "managed") throw new Error("Expected managed resolution");
    expect(resolution.env).toMatchObject({
      AGENTWEAVE_APP_DATA_ROOT: "/user/AgentWeave/sidecar/data",
      AGENTWEAVE_CACHE_ROOT: "/user/AgentWeave/sidecar/cache",
      AGENTWEAVE_DATABASE_URL: "sqlite:///user/AgentWeave/sidecar/data/agentweave.db?mode=rwc",
      AGENTWEAVE_MANAGED_SKILLS: "1",
      AGENTWEAVE_SKILLS_ROOT: "/app/resources/skills",
      AGENTWEAVE_WORKSPACE_ROOT: "/user/AgentWeave/sidecar/workspace",
      PATH: "/usr/bin",
    });
    expect(resolution.env).not.toHaveProperty("UNRELATED_SECRET");
  });

  it("falls back to an existing development build only outside packaged apps", () => {
    const developmentExecutable = "/repo/target/debug/agent-server";
    const resolution = resolveDesktopSidecar({
      ...baseOptions,
      isExecutable: (candidate) => candidate === developmentExecutable,
    });

    expect(resolution).toMatchObject({
      command: developmentExecutable,
      cwd: "/repo",
      mode: "managed",
    });
    expect(resolveDesktopSidecar({
      ...baseOptions,
      isExecutable: (candidate) => candidate === developmentExecutable,
      isPackaged: true,
    })).toMatchObject({ mode: "unavailable", reason: "missing-executable" });
  });
});
