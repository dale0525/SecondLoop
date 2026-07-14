import { resolve } from "node:path";
import { defineConfig, type UserConfig } from "vite";

const targets = {
  "electron-main": {
    clean: true,
    input: "src/main/electronMain.ts",
    output: "main.cjs",
  },
  "electron-preload": {
    clean: false,
    input: "src/preload/index.ts",
    output: "preload.cjs",
  },
  "electron-approval-preload": {
    clean: false,
    input: "src/preload/approval.ts",
    output: "approval-preload.cjs",
  },
} as const;

export function getElectronBuildConfig(mode: string): UserConfig {
  const target = targets[mode as keyof typeof targets];
  if (!target) throw new Error(`Unsupported Electron build mode: ${mode}`);
  return {
    define: {
      "process.env": "process.env"
    },
    build: {
      emptyOutDir: target.clean,
      minify: false,
      outDir: "dist-electron",
      target: "node20",
      rollupOptions: {
        external: [
          "electron",
          "node:child_process",
          "node:crypto",
          "node:fs",
          "node:fs/promises",
          "node:path",
          "node:stream",
          "node:url",
        ],
        input: resolve(__dirname, target.input),
        output: {
          entryFileNames: target.output,
          format: "cjs",
          inlineDynamicImports: true,
        }
      }
    }
  };
}

export default defineConfig(({ mode }) => getElectronBuildConfig(mode));
