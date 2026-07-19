import { DevSkillPackage } from "./api";

export function buildCreateSkillPrompt(root: string): string {
  const safeRoot = safeSkillRootLabel(root);

  return [
    "Use $skill-creator to guide a natural-language conversation that creates a new AgentWeave skill package.",
    "",
    `Target skills directory: ${safeRoot}/`,
    "",
    "Authoring constraints:",
    "- Ask one focused question at a time until the intended behavior and triggering examples are clear.",
    "- Plan only reusable resources that the user actually needs.",
    "- SKILL.md is a development authoring asset for Codex guidance.",
    "- agentweave.json is the AgentWeave package contract.",
    "- This developer flow can author instruction_only or host_tools_only packages.",
    "- Keep the generated SKILL.md concise and use imperative instructions.",
    "- Do not claim files were written or validated; the Host applies and validates the candidate."
  ].join("\n");
}

export function buildModifySkillPrompt(
  root: string,
  skillPackage: DevSkillPackage
): string {
  const safePackagePath = safeSkillPackagePath(root, skillPackage.path);
  const readinessIssueItems = skillPackage.readinessIssues ?? [];
  const requiredRuntimeTools = skillPackage.requiredRuntimeTools ?? [];
  const requiredConnectors = skillPackage.requiredConnectors ?? [];
  const runtimeTools =
    skillPackage.runtimeTools.length > 0
      ? skillPackage.runtimeTools.join(", ")
      : "none";
  const errors =
    skillPackage.validation.errors.length > 0
      ? skillPackage.validation.errors.map((error) => `- ${error}`).join("\n")
      : "- none";
  const warnings =
    skillPackage.validation.warnings.length > 0
      ? skillPackage.validation.warnings
          .map((warning) => `- ${warning}`)
          .join("\n")
      : "- none";
  const readinessIssues =
    readinessIssueItems.length > 0
      ? readinessIssueItems.map((issue) => `- ${issue}`).join("\n")
      : "- none";

  return [
    "Use $skill-creator to guide a natural-language conversation that improves this AgentWeave skill package.",
    "",
    `Package path: ${safePackagePath}`,
    `Package name: ${skillPackage.name}`,
    `Description: ${skillPackage.description}`,
    `Package kind: ${skillPackage.packageKind}`,
    `Files present: SKILL.md=${skillPackage.hasSkillMd}, skill.json=${skillPackage.hasRuntimeManifest}`,
    `runtime tools: ${runtimeTools}`,
    `Bundle ready: ${skillPackage.bundleReady}`,
    `Runtime ready: ${skillPackage.runtimeReady ?? false}`,
    `Instruction ready: ${skillPackage.instructionReady ?? false}`,
    `Release ready: ${skillPackage.releaseReady ?? skillPackage.bundleReady}`,
    `Required runtime tools: ${requiredRuntimeTools.join(", ") || "none"}`,
    `Required connectors: ${requiredConnectors.join(", ") || "none"}`,
    "",
    "Readiness issues:",
    readinessIssues,
    "",
    "Validation errors:",
    errors,
    "",
    "Validation warnings:",
    warnings,
    "",
    "Ask one focused question at a time when the requested change is ambiguous.",
    "Remember: SKILL.md is a development authoring asset; agentweave.json is the AgentWeave package contract.",
    "Do not claim files were written or validated; the Host applies and validates the candidate."
  ].join("\n");
}

function safeSkillPackagePath(root: string, packagePath: string): string {
  const normalizedPackagePath = packagePath
    .replaceAll("\\", "/")
    .replace(/^\/+/, "");
  return [safeSkillRootLabel(root), normalizedPackagePath]
    .filter(Boolean)
    .join("/");
}

function safeSkillRootLabel(root: string): string {
  const parts = root.split(/[\\/]+/).filter(Boolean);
  const label = parts.at(-1);
  if (!label || label === ".") {
    return "skills";
  }
  return label;
}
