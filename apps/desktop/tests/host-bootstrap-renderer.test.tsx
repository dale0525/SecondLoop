import { act, cleanup, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";

import App from "../src/renderer/App";
import {
  hostDiscoveryFixture,
  installHostBootstrap,
} from "./hostBootstrapFixture";

describe("trusted Renderer bootstrap", () => {
  afterEach(() => {
    cleanup();
    delete window.agentWeave;
    window.history.replaceState(null, "", "/");
    document.title = "";
    vi.restoreAllMocks();
  });

  it("binds trusted App identity and declared Host surfaces", async () => {
    installHostBootstrap();
    render(<App />);

    await waitFor(() => expect(document.title).toBe("Secretary"));

    await userEvent.click(screen.getByRole("button", { name: "Open settings" }));
    expect(await screen.findByText("Trusted App: Secretary 0.1.0")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Open Mail accounts" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Open Pending actions" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Open Memory ledger" })).toBeInTheDocument();
  });

  it("fails closed on direct optional routes when bootstrap is unavailable", async () => {
    window.history.replaceState(null, "", "/#memory");
    render(<App />);

    expect(screen.getByRole("main", { name: "Settings" })).toBeInTheDocument();
    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Trusted App configuration is unavailable",
    );
    expect(screen.queryByRole("main", { name: "Memory ledger" })).not.toBeInTheDocument();
    await waitFor(() => expect(window.location.hash).toBe("#settings"));
  });

  it("does not render an optional route while bootstrap is still loading", async () => {
    const discovery = hostDiscoveryFixture();
    installHostBootstrap(discovery);
    let resolve!: (value: typeof discovery) => void;
    window.agentWeave!.hostBootstrap = {
      load: () => new Promise((complete) => {
        resolve = complete;
      }),
    };
    window.history.replaceState(null, "", "/#memory");
    render(<App />);

    expect(screen.getByRole("main", { name: "Settings" })).toBeInTheDocument();
    expect(screen.queryByRole("main", { name: "Memory ledger" })).not.toBeInTheDocument();

    await waitFor(() => expect(resolve).toBeTypeOf("function"));
    await act(async () => {
      resolve(discovery);
      await Promise.resolve();
    });
    expect(await screen.findByRole("main", { name: "Memory ledger" })).toBeInTheDocument();
  });

  it("combines feature, capability, and policy gates", async () => {
    installHostBootstrap(hostDiscoveryFixture({ externalSideEffects: "deny" }));
    window.history.replaceState(null, "", "/#settings");
    render(<App />);

    expect(await screen.findByRole("button", { name: "Open Mail accounts" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Open Memory ledger" })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Open Pending actions" })).not.toBeInTheDocument();
  });

  it("keeps all optional routes closed for an App without declared features", async () => {
    installHostBootstrap(hostDiscoveryFixture({
      externalSideEffects: "deny",
      features: [],
      memoryPersistence: "disabled",
      skillManagement: "disabled",
    }));
    window.history.replaceState(null, "", "/#accounts");
    render(<App />);

    expect(await screen.findByText("Trusted App: Secretary 0.1.0")).toBeInTheDocument();
    expect(screen.queryByRole("heading", { name: "Accounts & data" })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Open developer tools" })).not.toBeInTheDocument();
    await waitFor(() => expect(window.location.hash).toBe("#settings"));
  });

  it("retries a recoverable bootstrap failure", async () => {
    const discovery = hostDiscoveryFixture();
    installHostBootstrap(discovery);
    const load = vi.fn()
      .mockRejectedValueOnce(new Error("sidecar starting"))
      .mockResolvedValueOnce(discovery);
    window.agentWeave!.hostBootstrap = { load };
    const ensureRunning = vi.fn().mockResolvedValue({
      schemaVersion: 1,
      mode: "managed",
      state: "ready",
      attempt: 2,
      canEnsureRunning: false,
      lastExit: null,
    });
    window.agentWeave!.sidecar = {
      ensureRunning,
      status: vi.fn(),
    };
    window.history.replaceState(null, "", "/#settings");
    render(<App />);

    await userEvent.click(await screen.findByRole("button", { name: "Retry" }));

    expect(await screen.findByText("Trusted App: Secretary 0.1.0")).toBeInTheDocument();
    expect(ensureRunning).toHaveBeenCalledOnce();
    expect(load).toHaveBeenCalledTimes(2);
  });

  it("keeps bootstrap unavailable when sidecar recovery fails", async () => {
    installHostBootstrap();
    const load = vi.fn().mockRejectedValue(new Error("sidecar unavailable"));
    window.agentWeave!.hostBootstrap = { load };
    const ensureRunning = vi.fn().mockRejectedValue(new Error("launch failed"));
    window.agentWeave!.sidecar = {
      ensureRunning,
      status: vi.fn(),
    };
    window.history.replaceState(null, "", "/#settings");
    render(<App />);

    await userEvent.click(await screen.findByRole("button", { name: "Retry" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Trusted App configuration is unavailable",
    );
    expect(ensureRunning).toHaveBeenCalledOnce();
    expect(load).toHaveBeenCalledOnce();
  });
});
