import react from "@vitejs/plugin-react";
import type { ProxyOptions } from "vite";
import { defineConfig } from "vitest/config";

import { normalizeOwnerRequest } from "./src/preload/ownerTransport";
import { buildDesktopAppearance } from "../../scripts/build-desktop-appearance.mjs";
import { buildDesktopLocalization } from "../../scripts/build-desktop-localization.mjs";

const desktopAppearance = buildDesktopAppearance();
const desktopLocalization = buildDesktopLocalization();

export default defineConfig({
  base: "./",
  define: {
    __AGENTWEAVE_APPEARANCE__: JSON.stringify(desktopAppearance),
    __AGENTWEAVE_LOCALIZATION__: JSON.stringify(desktopLocalization)
  },
  build: {
    rollupOptions: {
      input: {
        approval: "approval.html",
        main: "index.html"
      }
    }
  },
  plugins: [react()],
  server: {
    proxy: {
      "/__agentweave": {
        target: "http://127.0.0.1:49321",
        changeOrigin: false,
        rewrite: (path) => path.replace(/^\/__agentweave/, ""),
        configure: (proxy) => {
          proxy.on("proxyReq", (proxyRequest) => {
            proxyRequest.removeHeader("authorization");
            proxyRequest.removeHeader("cookie");
            proxyRequest.removeHeader("x-agentweave-transport");
          });
        },
      },
      "/__owner/requester": ownerProxy(process.env.AGENTWEAVE_OWNER_TOKEN),
    }
  },
  test: {
    environment: "jsdom",
    setupFiles: "./vitest.setup.ts"
  }
});

function ownerProxy(token: string | undefined): ProxyOptions {
  const headers: Record<string, string> = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  return {
    target: "http://127.0.0.1:49321",
    changeOrigin: false,
    headers,
    rewrite: (path: string) => path.replace(/^\/__owner\/requester/, ""),
    bypass: (request, response) => {
      const path = request.url?.replace(/^\/__owner\/requester/, "") ?? "";
      try {
        normalizeOwnerRequest(path, request.method ?? "GET");
      } catch {
        response.statusCode = 403;
        response.end("Forbidden");
        return request.url;
      }
    },
    configure: (proxy) => {
      proxy.on("proxyReq", (proxyRequest) => {
        proxyRequest.removeHeader("authorization");
        proxyRequest.removeHeader("cookie");
        if (token) proxyRequest.setHeader("Authorization", `Bearer ${token}`);
      });
    }
  };
}
