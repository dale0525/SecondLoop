import { requestServer } from "./trustedServerRequest";

export type DevSkillPackageKind =
  | "runtime"
  | "instruction"
  | "combined"
  | "empty"
  | "invalid";

export type DevSkillValidation = {
  ok: boolean;
  errors: string[];
  warnings: string[];
};

export type DevSkillPackage = {
  id: string;
  path: string;
  name: string;
  description: string;
  hasSkillMd: boolean;
  hasRuntimeManifest: boolean;
  runtimeTools: string[];
  packageKind: DevSkillPackageKind;
  bundleReady: boolean;
  runtimeReady: boolean;
  instructionReady: boolean;
  releaseReady: boolean;
  readinessIssues: string[];
  requiredRuntimeTools: string[];
  requiredConnectors: string[];
  hasPackageMetadata: boolean;
  validation: DevSkillValidation;
};

export type DevSkillInventory = {
  root: string;
  packages: DevSkillPackage[];
};

export type DevSkillReloadResponse = {
  inventory: DevSkillInventory;
  previousGeneration: number;
  activeGeneration: number;
  activePackages: number;
  inactivePackages: number;
  reloadStatus: "published";
};

export type DevSkillSource = {
  directory: string;
  sourceRevision: string;
  skillMd: string;
  manifest: Record<string, unknown>;
};

export type DevSkillMutationResponse = {
  inventory: DevSkillInventory;
  source: DevSkillSource;
};

export async function listDevSkills(): Promise<DevSkillInventory> {
  return parseInventory(await requestServer(
    "devSkills.list",
    undefined,
    "/dev/skills",
    { method: "GET" },
  ));
}

export async function validateDevSkills(): Promise<DevSkillInventory> {
  return parseInventory(await requestServer(
    "devSkills.validate",
    undefined,
    "/dev/skills/validate",
    { method: "POST" },
  ));
}

export async function reloadDevSkills(): Promise<DevSkillReloadResponse> {
  const value = await requestServer<unknown>(
    "devSkills.reload",
    undefined,
    "/dev/skills/reload",
    { method: "POST" },
  );
  if (!isRecord(value) || value.reloadStatus !== "published") {
    throw new Error("Dev Skill reload response is invalid");
  }
  return { ...value, inventory: parseInventory(value.inventory) } as DevSkillReloadResponse;
}

export async function readDevSkill(directory: string): Promise<DevSkillSource> {
  return requestServer(
    "devSkills.read",
    { directory },
    `/dev/skills/${encodeURIComponent(directory)}`,
    { method: "GET" },
  );
}

export async function createDevSkill(input: {
  directory: string;
  skillMd: string;
  manifest: Record<string, unknown>;
}): Promise<DevSkillMutationResponse> {
  return requestServer("devSkills.create", input, "/dev/skills", {
    body: JSON.stringify(input),
    method: "POST",
  });
}

export async function updateDevSkill(
  directory: string,
  input: { expectedRevision: string; skillMd: string; manifest: Record<string, unknown> },
): Promise<DevSkillMutationResponse> {
  return requestServer(
    "devSkills.update",
    { directory, ...input },
    `/dev/skills/${encodeURIComponent(directory)}`,
    { body: JSON.stringify(input), method: "PUT" },
  );
}

export async function deleteDevSkill(id: string): Promise<DevSkillInventory> {
  const source = await readDevSkill(id);
  const input = { expectedRevision: source.sourceRevision };
  return parseInventory(await requestServer(
    "devSkills.delete",
    { id, ...input },
    `/dev/skills/${encodeURIComponent(id)}`,
    { body: JSON.stringify(input), method: "DELETE" },
  ));
}

function parseInventory(value: unknown): DevSkillInventory {
  if (!isRecord(value) || typeof value.root !== "string" || !Array.isArray(value.packages)) {
    throw new Error("Dev Skill inventory is invalid");
  }
  return value as DevSkillInventory;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
