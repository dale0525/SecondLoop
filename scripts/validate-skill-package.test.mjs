import assert from "node:assert/strict";
import test from "node:test";

import { validateSkillPackageContract } from "./validate-skill-package.mjs";

function descriptor(kind, overrides = {}) {
  return {
    kind,
    package: {
      includeInstructions: true,
      includeRuntime: false,
      ...overrides.package,
    },
    requires: {
      runtimeTools: [],
      connectors: [],
      ...overrides.requires,
    },
  };
}

test("skill package contract accepts each supported package kind", () => {
  assert.doesNotThrow(() => validateSkillPackageContract(descriptor("instruction_only")));
  assert.doesNotThrow(() => validateSkillPackageContract(descriptor("host_tools_only", {
    requires: { runtimeTools: ["task_list"] },
  })));
  assert.doesNotThrow(() => validateSkillPackageContract(descriptor("native_runtime", {
    package: { includeRuntime: true },
  })));
});

test("instruction-only App packages reject runtime tools before release", () => {
  assert.throws(
    () => validateSkillPackageContract(descriptor("instruction_only", {
      requires: { runtimeTools: ["task_list"] },
    }), "daily-routines manifest"),
    /daily-routines manifest instruction_only must include instructions and exclude runtime tools/,
  );
});

test("host-tools-only and native-runtime contracts require their runtime declarations", () => {
  assert.throws(
    () => validateSkillPackageContract(descriptor("host_tools_only")),
    /host_tools_only must include instructions/,
  );
  assert.throws(
    () => validateSkillPackageContract(descriptor("native_runtime")),
    /native_runtime must include native runtime/,
  );
});
