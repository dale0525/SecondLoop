import { cleanup, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";

import App from "../src/renderer/App";
import { getBundledLocalization } from "../src/renderer/i18n/I18nProvider";
import { installHostBootstrap } from "./hostBootstrapFixture";

describe("desktop localization", () => {
  afterEach(() => {
    cleanup();
    window.localStorage.clear();
    window.history.replaceState(null, "", "/");
    document.documentElement.lang = "";
    delete window.agentWeave;
    vi.unstubAllGlobals();
  });

  it("bundles English and Simplified Chinese host catalogs", () => {
    const bundle = getBundledLocalization();
    expect(bundle.defaultLocale).toBe("en");
    expect(bundle.locales.map((locale) => locale.id)).toEqual(["en", "zh-CN"]);
    expect(bundle.locales.find((locale) => locale.id === "zh-CN")?.messages["developer.title"])
      .toBe("开发者工具");
  });

  it("switches language immediately and persists the selection", async () => {
    const user = userEvent.setup();
    installHostBootstrap();
    window.history.replaceState(null, "", "/#settings");
    render(<App />);

    await user.click(screen.getByRole("radio", { name: /简体中文/ }));

    await waitFor(() => expect(screen.getByRole("heading", { name: "设置" })).toBeInTheDocument());
    expect(screen.getByRole("heading", { name: "账户与数据" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "模型连接" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "测试连接" })).toBeInTheDocument();
    expect(document.documentElement).toHaveAttribute("lang", "zh-CN");
    expect(window.localStorage.getItem("agentweave.localization.locale.v1")).toBe("zh-CN");
  });

  it("localizes the developer workbench shell", async () => {
    window.localStorage.setItem("agentweave.localization.locale.v1", "zh-CN");
    window.agentWeave = {
      approval: { open: async () => { throw new Error("unavailable"); } },
      owner: {} as NonNullable<Window["agentWeave"]>["owner"],
      server: {
        request: async (operation: string) => {
          if (operation === "devSkills.list") return { packages: [], root: "/app/packages" };
          throw new Error(`Unexpected operation: ${operation}`);
        },
      },
    };
    installHostBootstrap();
    window.history.replaceState(null, "", "/#developer");
    render(<App />);

    expect(await screen.findByRole("heading", { name: "开发者工具" })).toBeInTheDocument();
    expect(screen.getByLabelText("刷新 Skill 包")).toBeInTheDocument();
  });

  it("localizes Mail, Memory, and Action Foundation surfaces", async () => {
    window.localStorage.setItem("agentweave.localization.locale.v1", "zh-CN");
    vi.stubGlobal("fetch", vi.fn(async () => new Response("[]", {
      headers: { "Content-Type": "application/json" },
      status: 200,
    })));
    installHostBootstrap();
    window.history.replaceState(null, "", "/#accounts");
    render(<App />);

    expect(await screen.findByRole("main", { name: "邮箱账户" })).toBeInTheDocument();
    expect(await screen.findByText("没有邮箱账户")).toBeInTheDocument();

    window.location.hash = "#memory";
    window.dispatchEvent(new HashChangeEvent("hashchange"));
    expect(await screen.findByRole("main", { name: "记忆账本" })).toBeInTheDocument();
    expect(await screen.findByText("这里还没有已确认的记忆")).toBeInTheDocument();

    window.location.hash = "#actions";
    window.dispatchEvent(new HashChangeEvent("hashchange"));
    expect(await screen.findByRole("main", { name: "行动中心" })).toBeInTheDocument();
    expect(await screen.findByText("没有等待处理的行动")).toBeInTheDocument();
  });
});
