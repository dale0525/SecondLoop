import { readdir, readFile } from "node:fs/promises";

const preloadPaths = [
  new URL("../dist-electron/preload.cjs", import.meta.url),
  new URL("../dist-electron/approval-preload.cjs", import.meta.url),
];

for (const preloadPath of preloadPaths) {
  const source = await readFile(preloadPath, "utf8");
  const imports = [...source.matchAll(/require\((['"])(.*?)\1\)/g)]
    .map((match) => match[2]);
  const unsupported = imports.filter((specifier) => specifier !== "electron");
  if (unsupported.length > 0) {
    throw new Error(
      `Sandboxed preload contains unsupported require calls: ${unsupported.join(", ")}`,
    );
  }
}

const rendererAssets = await readdir(new URL("../dist/assets/", import.meta.url));
const untrustedBundlePaths = [
  ...preloadPaths,
  ...rendererAssets
    .filter((name) => name.endsWith(".js"))
    .map((name) => new URL(`../dist/assets/${name}`, import.meta.url)),
];
const forbiddenTransportDetails = [
  "127.0.0.1:49321",
  "AGENTWEAVE_APPROVER_TOKEN",
  "AGENTWEAVE_OWNER_TOKEN",
  "AGENTWEAVE_SERVER_TOKEN",
  "X-AgentWeave-Transport",
  "transportToken",
];
for (const bundlePath of untrustedBundlePaths) {
  const source = await readFile(bundlePath, "utf8");
  const forbidden = forbiddenTransportDetails.filter((value) => source.includes(value));
  if (forbidden.length > 0) {
    throw new Error(
      `Renderer-facing bundle contains private transport details: ${forbidden.join(", ")}`,
    );
  }
}

console.log("Renderer-facing bundles are self-contained and transport-private");
