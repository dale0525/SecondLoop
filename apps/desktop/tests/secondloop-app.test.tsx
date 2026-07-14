import { cleanup, render, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";

import App from "../src/renderer/App";
import type { AgentAppHostDiscovery } from "../src/shared/hostBootstrap";
import {
  hostDiscoveryFixture,
  installHostBootstrap,
} from "./hostBootstrapFixture";

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
  };
  installHostBootstrap(discovery);
}

function stubFoundationFetch(): void {
  vi.stubGlobal("fetch", vi.fn(async () => new Response("[]", {
    status: 200,
    headers: { "Content-Type": "application/json" },
  })));
}
