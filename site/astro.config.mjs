import { defineConfig } from "astro/config";

export default defineConfig({
  site: "https://agentweave.secondloop.app",
  output: "static",
  trailingSlash: "always",
  build: {
    assets: "assets",
  },
});
