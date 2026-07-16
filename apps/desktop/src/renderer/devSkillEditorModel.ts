import type { DevSkillSource } from "./devSkillsApi";

export type EditableDevSkillKind = "instruction_only" | "host_tools_only";

export type DevSkillEditorDraft = {
  description: string;
  directory: string;
  displayName: string;
  instructions: string;
  kind: EditableDevSkillKind;
  packageId: string;
  requiredConnectors: string;
  requiredRuntimeTools: string;
  skillName: string;
};

export type DevSkillDraftIssue =
  | "description"
  | "directory"
  | "displayName"
  | "hostRequirements"
  | "instructions"
  | "packageId"
  | "skillName";

export type PreparedDevSkillSource = {
  directory: string;
  manifest: Record<string, unknown>;
  skillMd: string;
};

const DIRECTORY_PATTERN = /^[a-z0-9](?:[a-z0-9-]{0,126}[a-z0-9])?$/;
const PACKAGE_SEGMENT_PATTERN = /^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/;

export function emptyDevSkillDraft(appId = "app.local"): DevSkillEditorDraft {
  return {
    description: "",
    directory: "",
    displayName: "",
    instructions: "",
    kind: "instruction_only",
    packageId: `${normalizedPackagePrefix(appId)}.skill`,
    requiredConnectors: "",
    requiredRuntimeTools: "",
    skillName: "",
  };
}

export function draftFromDevSkillSource(source: DevSkillSource): DevSkillEditorDraft {
  const manifest = source.manifest;
  const requirements = recordValue(manifest.requires);
  const frontMatter = parseSkillMd(source.skillMd);
  return {
    description: frontMatter.description,
    directory: source.directory,
    displayName: stringValue(manifest.displayName),
    instructions: frontMatter.body,
    kind: manifest.kind === "host_tools_only" ? "host_tools_only" : "instruction_only",
    packageId: stringValue(manifest.id),
    requiredConnectors: stringList(requirements.connectors).join("\n"),
    requiredRuntimeTools: stringList(requirements.runtimeTools).join("\n"),
    skillName: frontMatter.name || source.directory,
  };
}

export function validateDevSkillDraft(draft: DevSkillEditorDraft): DevSkillDraftIssue[] {
  const issues: DevSkillDraftIssue[] = [];
  if (!DIRECTORY_PATTERN.test(draft.directory)) issues.push("directory");
  if (!validPackageId(draft.packageId)) issues.push("packageId");
  if (!draft.displayName.trim()) issues.push("displayName");
  if (!draft.skillName.trim()) issues.push("skillName");
  if (!draft.description.trim()) issues.push("description");
  if (!draft.instructions.trim()) issues.push("instructions");
  if (
    draft.kind === "host_tools_only"
    && splitRequirementList(draft.requiredRuntimeTools).length === 0
    && splitRequirementList(draft.requiredConnectors).length === 0
  ) {
    issues.push("hostRequirements");
  }
  return issues;
}

export function prepareDevSkillSource(
  draft: DevSkillEditorDraft,
  current?: DevSkillSource,
): PreparedDevSkillSource {
  const issues = validateDevSkillDraft(draft);
  if (issues.length > 0) throw new Error(`Invalid skill draft: ${issues.join(", ")}`);

  const manifest = cloneRecord(current?.manifest);
  const requirements = recordValue(manifest.requires);
  manifest.schemaVersion = 1;
  manifest.id = draft.packageId.trim();
  manifest.version = typeof manifest.version === "string" ? manifest.version : "0.1.0";
  manifest.displayName = draft.displayName.trim();
  manifest.kind = draft.kind;
  manifest.package = { includeInstructions: true, includeRuntime: false };
  manifest.compatibility = Object.keys(recordValue(manifest.compatibility)).length > 0
    ? recordValue(manifest.compatibility)
    : { platforms: ["desktop"] };
  manifest.requires = {
    packages: stringList(requirements.packages),
    capabilities: stringList(requirements.capabilities),
    runtimeTools: draft.kind === "host_tools_only"
      ? splitRequirementList(draft.requiredRuntimeTools)
      : [],
    connectors: draft.kind === "host_tools_only"
      ? splitRequirementList(draft.requiredConnectors)
      : [],
  };

  return {
    directory: draft.directory,
    manifest,
    skillMd: renderSkillMd(current?.skillMd, draft),
  };
}

export function suggestedPackageId(appId: string, directory: string): string {
  const suffix = DIRECTORY_PATTERN.test(directory) ? directory : "skill";
  return `${normalizedPackagePrefix(appId)}.${suffix}`;
}

export function suggestedDirectory(value: string): string {
  return value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 128)
    .replace(/-+$/g, "");
}

function renderSkillMd(current: string | undefined, draft: DevSkillEditorDraft): string {
  const parsed = parseSkillMd(current ?? "");
  const otherLines = parsed.headerLines.filter((line) => (
    !line.startsWith("name:") && !line.startsWith("description:")
  ));
  const header = [
    `name: ${draft.skillName.trim()}`,
    `description: ${JSON.stringify(draft.description.trim())}`,
    ...otherLines,
  ].join("\n");
  return `---\n${header}\n---\n\n${draft.instructions.trim()}\n`;
}

function parseSkillMd(value: string): {
  body: string;
  description: string;
  headerLines: string[];
  name: string;
} {
  const normalized = value.replace(/\r\n?/g, "\n");
  const match = normalized.match(/^---\n([\s\S]*?)\n---(?:\n|$)([\s\S]*)$/);
  if (!match) return { body: normalized.trim(), description: "", headerLines: [], name: "" };
  const headerLines = (match[1] ?? "").split("\n").filter((line) => line.trim().length > 0);
  return {
    body: (match[2] ?? "").trim(),
    description: scalarValue(headerLines.find((line) => line.startsWith("description:"))),
    headerLines,
    name: scalarValue(headerLines.find((line) => line.startsWith("name:"))),
  };
}

function scalarValue(line: string | undefined): string {
  if (!line) return "";
  const value = line.slice(line.indexOf(":") + 1).trim();
  if (value.startsWith('"') && value.endsWith('"')) {
    try {
      const decoded = JSON.parse(value);
      if (typeof decoded === "string") return decoded;
    } catch {
      return value.slice(1, -1);
    }
  }
  return value.replace(/^'|'$/g, "");
}

function splitRequirementList(value: string): string[] {
  return [...new Set(value.split(/[\n,]/).map((item) => item.trim()).filter(Boolean))].sort();
}

function validPackageId(value: string): boolean {
  const segments = value.trim().split(".");
  return value.length <= 128
    && segments.length >= 3
    && segments.every((segment) => PACKAGE_SEGMENT_PATTERN.test(segment));
}

function normalizedPackagePrefix(appId: string): string {
  const segments = appId
    .toLowerCase()
    .split(".")
    .map((segment) => segment.replace(/[^a-z0-9-]/g, "-").replace(/^-+|-+$/g, ""))
    .filter(Boolean);
  while (segments.length < 2) segments.push("local");
  return segments.join(".");
}

function cloneRecord(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  return JSON.parse(JSON.stringify(value)) as Record<string, unknown>;
}

function recordValue(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function stringList(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

function stringValue(value: unknown): string {
  return typeof value === "string" ? value : "";
}
