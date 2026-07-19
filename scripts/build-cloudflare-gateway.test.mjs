import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import { bundleCloudflareGateway } from "./build-cloudflare-gateway.mjs";

test("bundles the fixed Cloudflare Worker without development paths", async () => {
  const root = mkdtempSync(join(tmpdir(), "agentweave-gateway-bundle-"));
  try {
    const output = join(root, "gateway.mjs");
    const first = await bundleCloudflareGateway({ output });
    const firstBytes = readFileSync(output);
    const second = await bundleCloudflareGateway({ output });
    const secondBytes = readFileSync(output);

    assert.equal(first.version, "0.3.0");
    assert.equal(first.sha256, second.sha256);
    assert.deepEqual(firstBytes, secondBytes);
    assert.match(firstBytes.toString("utf8"), /ConcurrencyLimiter/);
    assert.doesNotMatch(firstBytes.toString("utf8"), /sourceMappingURL|file:\/\//);
  } finally {
    rmSync(root, { force: true, recursive: true });
  }
});
