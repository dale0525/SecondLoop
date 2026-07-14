import { readFile } from "node:fs/promises";

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

console.log("Sandboxed preload bundles are self-contained");
