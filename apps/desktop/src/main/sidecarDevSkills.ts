import type { SidecarApiOperation } from "../shared/sidecarApi";

type DevSkillRequestDescription = {
  body?: unknown;
  method: "DELETE" | "GET" | "POST" | "PUT";
  pathname: string;
};

export function describeDevSkillRequest(
  operation: SidecarApiOperation,
  value: unknown,
): DevSkillRequestDescription | null {
  switch (operation) {
    case "devSkills.list":
      return get("/dev/skills");
    case "devSkills.create": {
      const input = exactRecord(value, ["directory", "manifest", "skillMd"]);
      return json("POST", "/dev/skills", {
        directory: directory(input.directory),
        manifest: boundedJson(input.manifest, "manifest"),
        skillMd: nonBlankString(input.skillMd, "skillMd", 256 * 1024),
      });
    }
    case "devSkills.read": {
      const input = exactRecord(value, ["directory"]);
      return get(`/dev/skills/${directory(input.directory)}`);
    }
    case "devSkills.update": {
      const input = exactRecord(value, ["directory", "expectedRevision", "manifest", "skillMd"]);
      const packageDirectory = directory(input.directory);
      return json("PUT", `/dev/skills/${packageDirectory}`, {
        expectedRevision: hash(input.expectedRevision, "expectedRevision"),
        manifest: boundedJson(input.manifest, "manifest"),
        skillMd: nonBlankString(input.skillMd, "skillMd", 256 * 1024),
      });
    }
    case "devSkills.validate":
      return { method: "POST", pathname: "/dev/skills/validate" };
    case "devSkills.reload":
      return { method: "POST", pathname: "/dev/skills/reload" };
    case "devSkills.delete": {
      const input = exactRecord(value, ["expectedRevision", "id"]);
      return json("DELETE", `/dev/skills/${directory(input.id)}`, {
        expectedRevision: hash(input.expectedRevision, "expectedRevision"),
      });
    }
    default:
      return null;
  }
}

function get(pathname: string): DevSkillRequestDescription {
  return { method: "GET", pathname };
}

function json(
  method: "DELETE" | "POST" | "PUT",
  pathname: string,
  body: unknown,
): DevSkillRequestDescription {
  return { body, method, pathname };
}

function directory(value: unknown): string {
  if (typeof value !== "string" || !/^[a-z0-9](?:[a-z0-9-]{0,126}[a-z0-9])?$/.test(value)) {
    throw new Error("Skill package directory is invalid");
  }
  return encodeURIComponent(value);
}

function hash(value: unknown, name: string): string {
  if (typeof value !== "string" || !/^[a-f0-9]{64}$/i.test(value)) {
    throw new Error(`${name} is invalid`);
  }
  return value;
}

function boundedJson(value: unknown, name: string): unknown {
  let serialized: string;
  try {
    serialized = JSON.stringify(value);
  } catch {
    throw new Error(`${name} is invalid`);
  }
  if (serialized === undefined || new TextEncoder().encode(serialized).byteLength > 64 * 1024) {
    throw new Error(`${name} is invalid`);
  }
  return value;
}

function nonBlankString(value: unknown, name: string, maximum: number): string {
  if (typeof value !== "string" || !value.trim() || value.length > maximum) {
    throw new Error(`${name} is invalid`);
  }
  return value;
}

function exactRecord(value: unknown, allowedKeys: readonly string[]): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Sidecar API input is invalid");
  }
  const record = value as Record<string, unknown>;
  if (Object.keys(record).some((key) => !allowedKeys.includes(key))) {
    throw new Error("Sidecar API input contains unknown fields");
  }
  return record;
}
