import { createHash } from "node:crypto";
import { closeSync, mkdirSync, openSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { dirname, isAbsolute, join, resolve } from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const SCRIPT_ROOT = dirname(fileURLToPath(import.meta.url));
export const PROJECT_ROOT = resolve(SCRIPT_ROOT, "..");
export const DEFAULT_GATEWAY_OUTPUT = join(
  PROJECT_ROOT,
  ".tool/cloudflare-gateway/gateway.mjs",
);
const ENTRY_POINT = join(PROJECT_ROOT, "gateway/cloudflare-worker/src/index.js");
const MAX_ARTIFACT_BYTES = 16 * 1024 * 1024;

function esbuild() {
  const require = createRequire(join(PROJECT_ROOT, "apps/desktop/package.json"));
  return require("esbuild");
}

export async function bundleCloudflareGateway({ output = DEFAULT_GATEWAY_OUTPUT } = {}) {
  if (!isAbsolute(output)) throw new Error("Cloudflare gateway output path must be absolute");
  const result = await esbuild().build({
    absWorkingDir: PROJECT_ROOT,
    bundle: true,
    entryPoints: [ENTRY_POINT],
    format: "esm",
    legalComments: "none",
    minify: false,
    platform: "browser",
    sourcemap: false,
    target: ["es2022"],
    treeShaking: true,
    write: false,
  });
  if (result.outputFiles?.length !== 1) {
    throw new Error("Cloudflare gateway bundler returned an unexpected artifact set");
  }
  const bytes = result.outputFiles[0].contents;
  if (bytes.byteLength === 0 || bytes.byteLength > MAX_ARTIFACT_BYTES) {
    throw new Error("Cloudflare gateway artifact size is invalid");
  }
  const text = new TextDecoder().decode(bytes);
  if (/sourceMappingURL|file:\/\/|\.\.\/src\//.test(text)) {
    throw new Error("Cloudflare gateway artifact contains a development-only reference");
  }
  mkdirSync(dirname(output), { recursive: true, mode: 0o700 });
  const temporary = `${output}.${process.pid}.${Date.now()}.tmp`;
  let descriptor;
  try {
    descriptor = openSync(temporary, "wx", 0o600);
    writeFileSync(descriptor, bytes);
    closeSync(descriptor);
    descriptor = undefined;
    renameSync(temporary, output);
  } finally {
    if (descriptor !== undefined) closeSync(descriptor);
    rmSync(temporary, { force: true });
  }
  return Object.freeze({
    bytes: bytes.byteLength,
    output,
    sha256: createHash("sha256").update(bytes).digest("hex"),
    version: "0.3.0",
  });
}

function parseOutput(argv) {
  if (argv.length === 0) return DEFAULT_GATEWAY_OUTPUT;
  if (argv.length !== 2 || argv[0] !== "--output" || !isAbsolute(argv[1])) {
    throw new Error("Usage: build-cloudflare-gateway [--output <absolute-path>]");
  }
  return argv[1];
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  bundleCloudflareGateway({ output: parseOutput(process.argv.slice(2)) })
    .then((receipt) => console.log(JSON.stringify(receipt)))
    .catch((error) => {
      console.error(error instanceof Error ? error.message : String(error));
      process.exitCode = 1;
    });
}
