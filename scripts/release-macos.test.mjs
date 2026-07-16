import assert from "node:assert/strict";
import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { join } from "node:path";
import test from "node:test";

import {
  createMacUpdateMetadata,
  describeReleaseArtifact,
  normalizeMacArchitectures,
  parseDeveloperIdSignature,
  releaseArtifactNames,
  releaseFileSlug,
} from "../apps/desktop/scripts/release-macos.mjs";
import { PROJECT_ROOT } from "./scaffold-agent-app.mjs";

const TEST_ROOT = join(PROJECT_ROOT, ".tool");
const RELEASE_WORKFLOW = join(PROJECT_ROOT, ".github/workflows/macos-desktop-release.yml");

test("macOS release names are stable and architecture-specific", () => {
  assert.equal(releaseFileSlug("Secretary Agent"), "secretary-agent");
  assert.deepEqual(releaseArtifactNames({
    appName: "Secretary Agent",
    architecture: "arm64",
    version: "1.2.3",
  }), {
    appArchive: "secretary-agent-1.2.3-macos-arm64.zip",
    diskImage: "secretary-agent-1.2.3-macos-arm64.dmg",
    metadata: "secretary-agent-1.2.3-macos-arm64.json",
  });
});

test("macOS architectures normalize deterministic universal binaries", () => {
  assert.equal(normalizeMacArchitectures("arm64"), "arm64");
  assert.equal(normalizeMacArchitectures("x86_64"), "x64");
  assert.equal(normalizeMacArchitectures("x86_64 arm64 x86_64"), "universal");
  assert.throws(() => normalizeMacArchitectures("ppc"), /unsupported macOS architecture/);
});

test("release signatures require Developer ID Application and a valid Team ID", () => {
  assert.deepEqual(parseDeveloperIdSignature([
    "Authority=Developer ID Application: Example Corp (AB12CD34EF)",
    "Authority=Developer ID Certification Authority",
    "TeamIdentifier=AB12CD34EF",
  ].join("\n")), {
    identity: "Developer ID Application: Example Corp (AB12CD34EF)",
    teamId: "AB12CD34EF",
  });
  assert.throws(() => parseDeveloperIdSignature([
    "Signature=adhoc",
    "TeamIdentifier=not set",
  ].join("\n")), /Developer ID Application/);
  assert.throws(() => parseDeveloperIdSignature([
    "Authority=Developer ID Application: Example Corp",
    "TeamIdentifier=bad",
  ].join("\n")), /invalid TeamIdentifier/);
});

test("release artifact metadata binds HTTPS URL, bytes, and SHA-256", () => {
  mkdirSync(TEST_ROOT, { recursive: true });
  const temp = mkdtempSync(join(TEST_ROOT, "release-metadata-"));
  try {
    const artifact = join(temp, "secretary-agent.dmg");
    writeFileSync(artifact, "signed fixture", "utf8");
    assert.deepEqual(describeReleaseArtifact({
      downloadBaseUrl: "https://example.test/releases/v1/",
      kind: "disk_image",
      notarized: true,
      path: artifact,
    }), {
      downloadUrl: "https://example.test/releases/v1/secretary-agent.dmg",
      fileName: "secretary-agent.dmg",
      kind: "disk_image",
      notarized: true,
      sha256: "f6ee8f3108de139c0ced39ec732c8ebb2ac57bcef5e25e1dfa7a0e8e241d10f8",
      sizeBytes: 14,
    });
    assert.throws(() => describeReleaseArtifact({
      downloadBaseUrl: "http://example.test/releases/v1",
      kind: "disk_image",
      notarized: false,
      path: artifact,
    }), /must use HTTPS/);
  } finally {
    rmSync(temp, { force: true, recursive: true });
  }
});

test("update metadata binds App identity, signature, and artifacts", () => {
  const artifact = {
    downloadUrl: "https://example.test/releases/v1/app.dmg",
    fileName: "app.dmg",
    kind: "disk_image",
    notarized: true,
    sha256: "a".repeat(64),
    sizeBytes: 42,
  };
  assert.deepEqual(createMacUpdateMetadata({
    app: {
      appName: "Secretary Agent",
      architecture: "arm64",
      buildVersion: "7",
      bundleId: "com.example.secretary-agent.app",
      minimumSystemVersion: "12.0",
      version: "1.2.3",
    },
    artifacts: [artifact],
    publishedAt: "2026-07-15T12:00:00Z",
    teamId: "AB12CD34EF",
  }), {
    app: {
      buildVersion: "7",
      bundleId: "com.example.secretary-agent.app",
      name: "Secretary Agent",
      version: "1.2.3",
    },
    architecture: "arm64",
    artifacts: [artifact],
    minimumSystemVersion: "12.0",
    platform: "macos",
    publishedAt: "2026-07-15T12:00:00.000Z",
    schemaVersion: 1,
    signature: {
      teamId: "AB12CD34EF",
      type: "developer_id_application",
    },
  });
  assert.throws(() => createMacUpdateMetadata({
    app: {},
    artifacts: [artifact],
    publishedAt: "not-a-date",
    teamId: "AB12CD34EF",
  }), /publishedAt/);
});

test("release workflow keeps credentials behind a protected manual gate", () => {
  const workflow = readFileSync(RELEASE_WORKFLOW, "utf8");
  assert.match(workflow, /^  workflow_dispatch:/m);
  assert.doesNotMatch(workflow, /^  (pull_request|push|schedule):/m);
  assert.match(workflow, /^    environment: macos-release$/m);
  assert.match(workflow, /default: false\n        type: boolean/);
  for (const secret of [
    "APPLE_APP_SPECIFIC_PASSWORD",
    "APPLE_ID",
    "APPLE_TEAM_ID",
    "MACOS_CERTIFICATE_P12_BASE64",
    "MACOS_CERTIFICATE_PASSWORD",
    "MACOS_SIGN_IDENTITY",
  ]) {
    assert.match(workflow, new RegExp(`secrets\\.${secret}`));
  }
  assert.match(workflow, /--notary-profile agentweave-ci/);
  assert.match(workflow, /if: always\(\)/);
});
