import assert from "node:assert/strict";
import {
  chmodSync,
  cpSync,
  existsSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import {
  androidAppAssetPaths,
  androidSkillAssetPaths,
  androidRustLibraryPaths,
  androidNdkHostTag,
  createAndroidRustBuildConfig,
  makeAndroidGeneratedAssetsWritable,
  prepareAndroidAppAssetsAt,
  prepareAndroidSkillAssetsAt,
  runAndroidBuildSequence,
} from "./build-android-rust.mjs";
import {
  computeProjectDesiredHash,
  hashPublicValue,
  runtimeProviderProjection,
} from "./agentweave-project.mjs";
import { PROJECT_ROOT } from "./scaffold-agent-app.mjs";

test("Android NDK host tag follows the supported host platform", () => {
  assert.equal(androidNdkHostTag("darwin"), "darwin-x86_64");
  assert.equal(androidNdkHostTag("linux"), "linux-x86_64");
  assert.throws(
    () => androidNdkHostTag("win32"),
    /unsupported Android NDK host platform: win32/,
  );
});

test("Android Rust build validates required toolchain paths", () => {
  const existing = new Set([
    "/ndk",
    "/ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android31-clang",
    "/ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar",
    "/rustlib/aarch64-linux-android/lib",
  ]);
  const config = createAndroidRustBuildConfig({
    projectRoot: "/project",
    ndkRoot: "/ndk",
    platform: "linux",
    targetLibdir: "/rustlib/aarch64-linux-android/lib",
    pathExists: (path) => existing.has(path),
  });

  assert.equal(config.hostTag, "linux-x86_64");
  assert.equal(
    config.linker,
    "/ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android31-clang",
  );
  assert.equal(
    config.archiver,
    "/ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar",
  );
});

test("Android Rust build reports a missing target standard library", () => {
  assert.throws(
    () => createAndroidRustBuildConfig({
      projectRoot: "/project",
      ndkRoot: "/ndk",
      platform: "darwin",
      targetLibdir: "/missing/rustlib/aarch64-linux-android/lib",
      pathExists: (path) => path === "/ndk"
        || path.endsWith("aarch64-linux-android31-clang")
        || path.endsWith("llvm-ar"),
    }),
    /Android Rust target std not found.*rust-std-aarch64-linux-android/,
  );
});

test("Android Rust artifacts use variant-specific JNI directories", () => {
  assert.deepEqual(androidRustLibraryPaths("/project", "debug"), {
    source: "/project/target/aarch64-linux-android/debug/libmobile_ffi.so",
    destination: "/project/apps/android/app/build/generated/rustJniLibs/debug/arm64-v8a/libmobile_ffi.so",
  });
  assert.deepEqual(androidRustLibraryPaths("/project", "release"), {
    source: "/project/target/aarch64-linux-android/release/libmobile_ffi.so",
    destination: "/project/apps/android/app/build/generated/rustJniLibs/release/arm64-v8a/libmobile_ffi.so",
  });
});

test("Android skill bundle uses the generated main asset directory", () => {
  assert.deepEqual(androidSkillAssetPaths("/project"), {
    generatedRoot: "/project/apps/android/app/build/generated/skillAssets/main",
    assetRoot: "/project/apps/android/app/build/generated/skillAssets/main/builtin-skills",
    bundleRoot: "/project/apps/android/app/build/generated/skillAssets/main/builtin-skills/bundle",
    hashFile: "/project/apps/android/app/build/generated/skillAssets/main/builtin-skills/bundle.sha256",
    compatibilityRoot: "/project/apps/android/app/build/generated/skillAssets/main/skills",
    compatibilityManifest: "/project/apps/android/app/build/generated/skillAssets/main/skills/skill-bundle.json",
    compatibilityLock: "/project/apps/android/app/build/generated/skillAssets/main/skills/skill-bundle.lock",
  });
});

test("Android Agent App assets use a verified platform-specific package", () => {
  assert.deepEqual(androidAppAssetPaths("/project"), {
    assetRoot: "/project/apps/android/app/build/generated/skillAssets/main/agent-app",
    packageRoot: "/project/apps/android/app/build/generated/skillAssets/main/agent-app/package",
    hashFile: "/project/apps/android/app/build/generated/skillAssets/main/agent-app/app.sha256",
  });
});

test("Android app-managed packaging requires a verified lock and excludes developer state", () => {
  mkdirSync(join(PROJECT_ROOT, ".tool"), { recursive: true });
  const root = mkdtempSync(join(PROJECT_ROOT, ".tool", "android-managed-assets-"));
  try {
    const reference = join(PROJECT_ROOT, "examples", "managed-gateway-agent");
    assert.throws(
      () => prepareAndroidAppAssetsAt(root, { input: reference }),
      /deployment\.lock is required before packaging/,
    );

    const input = join(root, "managed-android-app");
    cpSync(reference, input, { recursive: true });
    const manifestPath = join(input, "agent-app.json");
    const projectPath = join(input, "agentweave-project.json");
    const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
    const project = JSON.parse(readFileSync(projectPath, "utf8"));
    manifest.compatibility.platforms = ["android"];
    writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
    mkdirSync(join(input, ".agentweave"));
    writeFileSync(
      join(input, ".agentweave", "deployment.lock"),
      `${JSON.stringify(managedDeploymentLock(project, manifest), null, 2)}\n`,
    );
    assert.throws(
      () => prepareAndroidAppAssetsAt(root, { input }),
      /private reverse-domain scheme/,
    );

    manifest.identity.provider.publicConfig.redirectUri =
      "com.example.managed-gateway-agent:/oidc/callback";
    project.providers.identity.publicConfig.redirectUri =
      "com.example.managed-gateway-agent:/oidc/callback";
    writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
    writeFileSync(projectPath, `${JSON.stringify(project, null, 2)}\n`);
    writeFileSync(
      join(input, ".agentweave", "deployment.lock"),
      `${JSON.stringify(managedDeploymentLock(project, manifest), null, 2)}\n`,
    );

    const result = prepareAndroidAppAssetsAt(root, { input });
    const packaged = JSON.parse(readFileSync(join(result.packageRoot, "agent-app.json"), "utf8"));
    assert.deepEqual(packaged.compatibility.platforms, ["android"]);
    assert.equal(existsSync(join(result.packageRoot, "agentweave-project.json")), false);
    assert.equal(existsSync(join(result.packageRoot, ".agentweave")), false);
    assert.match(readFileSync(result.hashFile, "utf8"), /^[0-9a-f]{64}\n$/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("Android packaging rejects an App that omits the android platform", () => {
  mkdirSync(join(PROJECT_ROOT, ".tool"), { recursive: true });
  const root = mkdtempSync(join(PROJECT_ROOT, ".tool", "android-platform-assets-"));
  try {
    assert.throws(
      () => prepareAndroidAppAssetsAt(root, {
        input: join(PROJECT_ROOT, "examples", "minimal-agent"),
      }),
      /declares the android platform/,
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("Android build prepares skill assets before compiling Rust", () => {
  const calls = [];

  runAndroidBuildSequence({
    prepareSkills: () => calls.push("bundle-skills --platform android"),
    buildRust: () => calls.push("cargo build -p mobile-ffi"),
  });

  assert.deepEqual(calls, [
    "bundle-skills --platform android",
    "cargo build -p mobile-ffi",
  ]);
});

test("Android build stops before Rust when skill bundling fails", () => {
  let rustStarted = false;

  assert.throws(
    () => runAndroidBuildSequence({
      prepareSkills: () => {
        throw new Error("bundle failed");
      },
      buildRust: () => {
        rustStarted = true;
      },
    }),
    /bundle failed/,
  );
  assert.equal(rustStarted, false);
});

test("Gradle always regenerates skill assets before native and package tasks", () => {
  const gradle = readFileSync(
    new URL("../apps/android/app/build.gradle.kts", import.meta.url),
    "utf8",
  );

  assert.match(gradle, /outputs\.upToDateWhen\s*\{\s*false\s*\}/);
  assert.match(
    gradle,
    /makeGeneratedAndroidAssetsWritable[\s\S]*--make-generated-assets-writable/,
  );
  assert.match(
    gradle,
    /prepareAndroidSkillAssets[\s\S]*dependsOn\(makeGeneratedAndroidAssetsWritable\)/,
  );
  assert.match(gradle, /buildRustNativeDebug[\s\S]*dependsOn\(prepareAndroidSkillAssets\)/);
  assert.match(gradle, /tasks\.named\("preBuild"\)[\s\S]*dependsOn\(prepareAndroidSkillAssets\)/);
});

test("Gradle permission preparation makes verified assets replaceable without following symlinks", {
  skip: process.platform === "win32",
}, () => {
  const root = mkdtempSync(join(tmpdir(), "agentweave-android-permissions-"));
  const external = mkdtempSync(join(tmpdir(), "agentweave-android-external-"));
  try {
    const generatedRoot = androidSkillAssetPaths(root).generatedRoot;
    const generation = join(generatedRoot, "builtin-skills/bundle/generations/test-generation");
    const manifest = join(generation, "skill-bundle.json");
    const externalFile = join(external, "must-remain-readonly.txt");
    mkdirSync(generation, { recursive: true });
    writeFileSync(manifest, "manifest");
    writeFileSync(externalFile, "external");
    symlinkSync(externalFile, join(generatedRoot, "external-link"));
    chmodSync(manifest, 0o400);
    chmodSync(generation, 0o500);
    chmodSync(externalFile, 0o400);

    assert.equal(lstatSync(generation).mode & 0o200, 0);
    assert.equal(lstatSync(manifest).mode & 0o200, 0);
    makeAndroidGeneratedAssetsWritable(root);

    assert.notEqual(lstatSync(generation).mode & 0o200, 0);
    assert.notEqual(lstatSync(manifest).mode & 0o200, 0);
    assert.equal(lstatSync(externalFile).mode & 0o200, 0);
    assert.doesNotThrow(() => rmSync(generatedRoot, { recursive: true }));
  } finally {
    rmSync(root, { recursive: true, force: true });
    rmSync(external, { recursive: true, force: true });
  }
});

test("Android asset preparation removes stale output and round-trips staged bundle hash", () => {
  const root = mkdtempSync(join(tmpdir(), "agentweave-android-assets-"));
  try {
    const skills = join(root, "skills");
    writeSkillFixture(skills, "android-skill", ["android"]);
    writeSkillFixture(skills, "desktop-skill", ["desktop"]);
    const stale = join(
      root,
      "apps/android/app/build/generated/skillAssets/main/builtin-skills/stale.txt",
    );
    mkdirSync(join(stale, ".."), { recursive: true });
    writeFileSync(stale, "stale");

    const result = prepareAndroidSkillAssetsAt(root, ({ sourceRoot, bundleRoot }) => {
      assert.equal(existsSync(join(sourceRoot, "android-skill/agentweave.json")), true);
      assert.equal(existsSync(join(sourceRoot, "desktop-skill")), false);
      const generation = join(bundleRoot, "generations/test-generation");
      mkdirSync(generation, { recursive: true });
      writeFileSync(join(bundleRoot, "current"), JSON.stringify({
        schemaVersion: 2,
        active: {
          generation: "test-generation",
          manifestSha256: "a".repeat(64),
          lockSha256: "b".repeat(64),
        },
        previous: null,
      }));
      writeFileSync(join(generation, "skill-bundle.json"), "manifest");
      writeFileSync(join(generation, "skill-bundle.lock"), "lock");
    });

    assert.equal(existsSync(stale), false);
    assert.match(result.contentHash, /^[0-9a-f]{64}$/);
    assert.equal(readFileSync(result.hashFile, "utf8"), `${result.contentHash}\n`);
    assert.equal(readFileSync(result.compatibilityManifest, "utf8"), "manifest");
    assert.equal(readFileSync(result.compatibilityLock, "utf8"), "lock");
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

function writeSkillFixture(skillsRoot, name, platforms) {
  const root = join(skillsRoot, name);
  mkdirSync(root, { recursive: true });
  writeFileSync(join(root, "agentweave.json"), JSON.stringify({
    schemaVersion: 1,
    id: `com.example.${name}`,
    version: "1.0.0",
    displayName: name,
    kind: "instruction_only",
    package: { includeInstructions: true, includeRuntime: false },
    compatibility: { platforms },
  }));
  writeFileSync(join(root, "SKILL.md"), `# ${name}\n`);
}

function managedDeploymentLock(project, manifest) {
  return {
    schemaVersion: 1,
    desiredHash: computeProjectDesiredHash(project),
    runtimeProjectionHash: hashPublicValue(runtimeProviderProjection(manifest)),
    gateway: {
      id: project.providers.gateway.id,
      version: project.providers.gateway.version,
      publicConfigHash: hashPublicValue(project.providers.gateway.publicConfig),
    },
    deployment: {
      provider: "cloudflare",
      reference: {
        ...project.deployment.cloudflare,
        versionId: "version-verified",
        deploymentId: "deployment-verified",
        endpoint: manifest.modelAccess.profile.baseUrl,
      },
    },
  };
}
