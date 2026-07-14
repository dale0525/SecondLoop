const PACKAGE_KINDS = new Set([
  "host_tools_only",
  "instruction_only",
  "native_runtime",
]);

function fail(label, message) {
  throw new Error(`${label} ${message}`);
}

function requireBoolean(value, label, field) {
  if (typeof value !== "boolean") fail(label, `${field} must be a boolean`);
  return value;
}

function requireArray(value, label, field) {
  if (!Array.isArray(value)) fail(label, `${field} must be an array`);
  return value;
}

export function validateSkillPackageContract(manifest, label = "skill package") {
  if (!PACKAGE_KINDS.has(manifest.kind)) fail(label, "kind is unsupported");
  if (!manifest.package || typeof manifest.package !== "object" || Array.isArray(manifest.package)) {
    fail(label, "package must be an object");
  }
  if (!manifest.requires || typeof manifest.requires !== "object" || Array.isArray(manifest.requires)) {
    fail(label, "requires must be an object");
  }

  const includeInstructions = requireBoolean(
    manifest.package.includeInstructions,
    label,
    "package.includeInstructions",
  );
  const includeRuntime = requireBoolean(
    manifest.package.includeRuntime,
    label,
    "package.includeRuntime",
  );
  const runtimeTools = requireArray(manifest.requires.runtimeTools, label, "requires.runtimeTools");
  const connectors = requireArray(manifest.requires.connectors, label, "requires.connectors");
  const hasHostTools = runtimeTools.length > 0 || connectors.length > 0;

  if (manifest.kind === "instruction_only" && (!includeInstructions || includeRuntime || hasHostTools)) {
    fail(label, "instruction_only must include instructions and exclude runtime tools, connectors, and native runtime");
  }
  if (manifest.kind === "host_tools_only" && (!includeInstructions || includeRuntime || !hasHostTools)) {
    fail(label, "host_tools_only must include instructions, exclude native runtime, and require a runtime tool or connector");
  }
  if (manifest.kind === "native_runtime" && !includeRuntime) {
    fail(label, "native_runtime must include native runtime");
  }
  return manifest;
}
