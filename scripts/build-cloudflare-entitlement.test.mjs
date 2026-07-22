import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import { bundleCloudflareEntitlement } from "./build-cloudflare-entitlement.mjs";

test("bundles the fixed entitlement Worker deterministically without secrets or development paths", async () => {
  const root = mkdtempSync(join(tmpdir(), "agentweave-entitlement-bundle-"));
  try {
    const output = join(root, "entitlement.mjs");
    const first = await bundleCloudflareEntitlement({ output });
    const firstBytes = readFileSync(output);
    const second = await bundleCloudflareEntitlement({ output });
    const secondBytes = readFileSync(output);
    const text = firstBytes.toString("utf8");

    assert.equal(first.version, "0.1.0");
    assert.equal(first.sha256, second.sha256);
    assert.deepEqual(firstBytes, secondBytes);
    assert.match(text, /customer_portal_v1/);
    assert.match(text, /agentweave\/commerce\/v1\/webhooks\/creem/);
    assert.doesNotMatch(text, /sourceMappingURL|file:\/\/|webhook-secret-sentinel/);
  } finally {
    rmSync(root, { force: true, recursive: true });
  }
});
