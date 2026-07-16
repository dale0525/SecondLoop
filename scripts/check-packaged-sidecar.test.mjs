import assert from "node:assert/strict";
import {
  chmodSync,
  mkdirSync,
  mkdtempSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { join } from "node:path";
import test from "node:test";

import {
  assertPackagedDiscovery,
  assertPackagedMailPreviewEvent,
  foundationScenarioSupported,
  packagedSidecarPlan,
  scriptedModelReply,
} from "./check-packaged-sidecar.mjs";
import { PROJECT_ROOT } from "./scaffold-agent-app.mjs";

const TEST_ROOT = join(PROJECT_ROOT, ".tool");

function fixture() {
  mkdirSync(TEST_ROOT, { recursive: true });
  const root = mkdtempSync(join(TEST_ROOT, "packaged-sidecar-"));
  const bundleRoot = join(root, "Fixture.app");
  const resourcesRoot = join(bundleRoot, "Contents", "Resources");
  const appRoot = join(resourcesRoot, "agent-app", "app");
  const sidecarPath = join(resourcesRoot, "sidecar", "agent-server");
  mkdirSync(appRoot, { recursive: true });
  mkdirSync(join(resourcesRoot, "skills"), { recursive: true });
  mkdirSync(join(sidecarPath, ".."), { recursive: true });
  writeFileSync(sidecarPath, "fixture", "utf8");
  chmodSync(sidecarPath, 0o755);
  writeFileSync(join(appRoot, "agent-app.json"), `${JSON.stringify({
    appId: "com.example.fixture",
    package: { id: "com.example.fixture.app", version: "1.2.3" },
    requires: {
      capabilities: ["memory-provider", "host-tools"],
      connectors: ["fixture-connector"],
      runtimeTools: ["memory_search", "memory_get"],
    },
    branding: { displayName: "Fixture" },
  }, null, 2)}\n`, "utf8");
  return { bundleRoot, root };
}

test("packaged sidecar plan is bound to App resources and manifest identity", () => {
  const item = fixture();
  try {
    const plan = packagedSidecarPlan(item.bundleRoot);

    assert.equal(plan.bundleRoot, item.bundleRoot);
    assert.equal(plan.expected.appId, "com.example.fixture");
    assert.equal(plan.expected.packageId, "com.example.fixture.app");
    assert.equal(plan.expected.displayName, "Fixture");
    assert.deepEqual(plan.expected.capabilities, ["memory-provider", "host-tools"]);
  } finally {
    rmSync(item.root, { force: true, recursive: true });
  }
});

test("packaged discovery must match identity and declared capability sets", () => {
  const expected = {
    appId: "com.example.fixture",
    packageId: "com.example.fixture.app",
    version: "1.2.3",
    displayName: "Fixture",
    capabilities: ["host-tools", "memory-provider"],
    runtimeTools: ["memory_get", "memory_search"],
    connectors: ["fixture-connector"],
  };
  const discovery = {
    schemaVersion: 1,
    platform: "desktop",
    identity: {
      appId: "com.example.fixture",
      packageId: "com.example.fixture.app",
      version: "1.2.3",
      displayName: "Fixture",
    },
    requirements: {
      capabilities: ["memory-provider", "host-tools"],
      runtimeTools: ["memory_search", "memory_get"],
      connectors: ["fixture-connector"],
    },
  };

  assert.equal(assertPackagedDiscovery(discovery, expected), true);
  assert.throws(
    () => assertPackagedDiscovery({ ...discovery, identity: { ...discovery.identity, appId: "wrong" } }, expected),
    /identity does not match/,
  );
  assert.throws(
    () => assertPackagedDiscovery({
      ...discovery,
      requirements: { ...discovery.requirements, capabilities: ["memory-provider"] },
    }, expected),
    /capabilities do not match/,
  );
});

test("packaged sidecar plan rejects an incomplete App bundle", () => {
  mkdirSync(TEST_ROOT, { recursive: true });
  const root = mkdtempSync(join(TEST_ROOT, "packaged-sidecar-invalid-"));
  const bundleRoot = join(root, "Invalid.app");
  mkdirSync(bundleRoot, { recursive: true });
  try {
    assert.throws(() => packagedSidecarPlan(bundleRoot), /packaged Agent App is missing/);
  } finally {
    rmSync(root, { force: true, recursive: true });
  }
});

test("packaged Foundation scenario requires the complete reusable contract", () => {
  const expected = {
    capabilities: [
      "approval-engine",
      "durable-actions",
      "mail-connector",
      "memory-provider",
    ],
    connectors: ["agentweave-mail"],
    runtimeTools: [
      "mail_draft_create",
      "mail_send_preview",
      "memory_confirm",
      "memory_propose",
    ],
  };

  assert.equal(foundationScenarioSupported(expected), true);
  assert.equal(foundationScenarioSupported({
    ...expected,
    runtimeTools: expected.runtimeTools.filter((tool) => tool !== "memory_confirm"),
  }), false);
  assert.equal(foundationScenarioSupported({ ...expected, connectors: [] }), false);
});

test("packaged Mail preview persists only bounded success metadata", () => {
  const event = {
    payload: {
      type: "tool_call_finished",
      call_id: "foundation-mail-preview",
      persistence: "metadata_only",
      result_metadata: { ok: true, serialized_bytes: 512 },
    },
  };

  assert.equal(assertPackagedMailPreviewEvent(event), true);
  assert.throws(
    () => assertPackagedMailPreviewEvent({
      payload: { ...event.payload, result: { secret: "must-not-persist" } },
    }),
    /persistence policy is invalid/,
  );
  assert.throws(
    () => assertPackagedMailPreviewEvent({
      payload: { ...event.payload, result_metadata: { ok: false } },
    }),
    /persistence policy is invalid/,
  );
});

test("scripted model advances only through successful Foundation tool results", () => {
  const body = scriptedBody();
  const proposed = scriptedModelReply(body);
  assert.equal(proposed.choices[0].finish_reason, "tool_calls");
  assert.equal(toolCall(proposed).id, "foundation-memory-propose");
  assert.equal(toolArguments(proposed).draft.retention.mode, "persistent");

  body.messages.push(toolMessage("foundation-memory-propose", {
    action: "proposed",
    record: {
      id: "00000000-0000-4000-8000-000000000001",
      version: 1,
    },
  }));
  const confirmed = scriptedModelReply(body);
  assert.equal(toolCall(confirmed).id, "foundation-memory-confirm");
  assert.equal(toolArguments(confirmed).expectedVersion, 1);

  body.messages.push(toolMessage("foundation-memory-confirm", {
    id: "00000000-0000-4000-8000-000000000001",
    version: 2,
  }));
  const drafted = scriptedModelReply(body);
  assert.equal(toolCall(drafted).id, "foundation-mail-draft");
  assert.deepEqual(toolArguments(drafted).content.attachments, []);

  body.messages.push(toolMessage("foundation-mail-draft", {
    id: "draft-1",
    revision: 1,
  }));
  const previewed = scriptedModelReply(body);
  assert.equal(toolCall(previewed).id, "foundation-mail-preview");
  assert.equal(toolCall(previewed).function.name, "mail_send_preview");
  assert.equal(toolArguments(previewed).draftId, "draft-1");
  assert.equal("idempotencyKey" in toolArguments(previewed), false);

  body.messages.push(toolMessage("foundation-mail-preview", {
    id: "preview-1",
    idempotencyKey: "packaged-foundation-send-v1",
  }));
  const completed = scriptedModelReply(body);
  assert.equal(completed.choices[0].finish_reason, "stop");
  assert.equal(completed.choices[0].message.content, "Packaged Foundation scenario completed.");

  const failed = scriptedBody();
  failed.messages.push({
    role: "tool",
    tool_call_id: "foundation-memory-propose",
    content: JSON.stringify({
      ok: false,
      data: null,
      error: { code: "failed", message: "failed" },
    }),
  });
  assert.throws(() => scriptedModelReply(failed), /tool result .* failed/);
});

function scriptedBody() {
  return {
    messages: [],
    tools: [
      "mail_draft_create",
      "mail_send_preview",
      "memory_confirm",
      "memory_propose",
    ].map((name) => ({
      type: "function",
      function: {
        name: name === "mail_send_preview" ? name : `ga_fixture_${name}`,
        parameters: { type: "object" },
      },
    })),
  };
}

function toolMessage(callId, output) {
  const data = callId.startsWith("foundation-mail-") ? {
    connector_id: "agentweave-mail",
    tool_name: "fixture",
    action_hash: "a".repeat(64),
    replayed: false,
    output,
  } : output;
  return {
    role: "tool",
    tool_call_id: callId,
    content: JSON.stringify({ ok: true, data, error: null }),
  };
}

function toolCall(reply) {
  return reply.choices[0].message.tool_calls[0];
}

function toolArguments(reply) {
  return JSON.parse(toolCall(reply).function.arguments);
}
