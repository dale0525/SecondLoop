export const HOST_BOOTSTRAP_LOAD_CHANNEL = "agentweave:host-bootstrap:load";
export const HOST_DISCOVERY_SCHEMA_VERSION = 1;

export type AgentAppHostIdentity = Readonly<{
  accentColor: string | null;
  appId: string;
  description: string | null;
  displayName: string;
  packageId: string;
  shortName: string | null;
  version: string;
}>;

export type AgentAppHostPolicy = Readonly<{
  backgroundExecution: "disabled" | "declared_only" | "enabled";
  externalSideEffects: "deny" | "require_approval" | "allow_by_policy";
  memoryPersistence: "disabled" | "local_only" | "configured_provider";
  network: "deny" | "declared_only" | "unrestricted";
  skillManagement: "disabled" | "owner_only" | "runtime_policy";
}>;

export type AgentAppHostPackageRequirement = Readonly<{
  id: string;
  version: string;
}>;

export type AgentAppHostRequirements = Readonly<{
  capabilities: readonly string[];
  connectors: readonly string[];
  packages: readonly AgentAppHostPackageRequirement[];
  runtimeTools: readonly string[];
}>;

export type AgentAppHostDiscovery = Readonly<{
  features: readonly string[];
  identity: AgentAppHostIdentity;
  manifestSha256: string;
  platform: "desktop" | "android" | "ios" | "web" | "server";
  policy: AgentAppHostPolicy;
  requirements: AgentAppHostRequirements;
  runtimeVersion: string;
  schemaVersion: 1;
}>;

export function parseHostDiscovery(value: unknown): AgentAppHostDiscovery {
  const root = exactRecord(value, "Host discovery", [
    "schemaVersion",
    "manifestSha256",
    "runtimeVersion",
    "platform",
    "identity",
    "features",
    "requirements",
    "policy",
  ]);
  if (root.schemaVersion !== HOST_DISCOVERY_SCHEMA_VERSION) {
    throw new Error("Host discovery schema is unsupported");
  }
  const manifestSha256 = boundedString(root.manifestSha256, "Manifest hash", 64);
  if (!/^[0-9a-f]{64}$/.test(manifestSha256)) {
    throw new Error("Manifest hash is invalid");
  }
  const platform = enumValue(root.platform, "Platform", [
    "desktop",
    "android",
    "ios",
    "web",
    "server",
  ] as const);

  return Object.freeze({
    schemaVersion: HOST_DISCOVERY_SCHEMA_VERSION,
    manifestSha256,
    runtimeVersion: boundedString(root.runtimeVersion, "Runtime version", 256),
    platform,
    identity: parseIdentity(root.identity),
    features: stringSet(root.features, "Features"),
    requirements: parseRequirements(root.requirements),
    policy: parsePolicy(root.policy),
  });
}

function parseIdentity(value: unknown): AgentAppHostIdentity {
  const identity = exactRecord(value, "Host identity", [
    "appId",
    "packageId",
    "version",
    "displayName",
    "shortName",
    "description",
    "accentColor",
  ]);
  const accentColor = nullableString(identity.accentColor, "Accent color", 32);
  if (accentColor !== null && !/^#[0-9a-fA-F]{6}$/.test(accentColor)) {
    throw new Error("Accent color is invalid");
  }
  return Object.freeze({
    appId: boundedString(identity.appId, "App identifier", 256),
    packageId: boundedString(identity.packageId, "Package identifier", 256),
    version: boundedString(identity.version, "App version", 256),
    displayName: boundedString(identity.displayName, "Display name", 256),
    shortName: nullableString(identity.shortName, "Short name", 128),
    description: nullableString(identity.description, "Description", 4096),
    accentColor,
  });
}

function parseRequirements(value: unknown): AgentAppHostRequirements {
  const requirements = exactRecord(value, "Host requirements", [
    "packages",
    "capabilities",
    "runtimeTools",
    "connectors",
  ]);
  if (!Array.isArray(requirements.packages) || requirements.packages.length > 256) {
    throw new Error("Package requirements are invalid");
  }
  const packages = requirements.packages.map((value, index) => {
    const item = exactRecord(value, `Package requirement ${index}`, ["id", "version"]);
    return Object.freeze({
      id: boundedString(item.id, "Package identifier", 256),
      version: boundedString(item.version, "Package version", 256),
    });
  });
  if (new Set(packages.map((item) => item.id)).size !== packages.length) {
    throw new Error("Package requirements contain duplicates");
  }
  return Object.freeze({
    packages: Object.freeze(packages),
    capabilities: stringSet(requirements.capabilities, "Capabilities"),
    runtimeTools: stringSet(requirements.runtimeTools, "Runtime tools"),
    connectors: stringSet(requirements.connectors, "Connectors"),
  });
}

function parsePolicy(value: unknown): AgentAppHostPolicy {
  const policy = exactRecord(value, "Host policy", [
    "externalSideEffects",
    "network",
    "backgroundExecution",
    "memoryPersistence",
    "skillManagement",
  ]);
  return Object.freeze({
    externalSideEffects: enumValue(policy.externalSideEffects, "External side-effect policy", [
      "deny",
      "require_approval",
      "allow_by_policy",
    ] as const),
    network: enumValue(policy.network, "Network policy", [
      "deny",
      "declared_only",
      "unrestricted",
    ] as const),
    backgroundExecution: enumValue(policy.backgroundExecution, "Background policy", [
      "disabled",
      "declared_only",
      "enabled",
    ] as const),
    memoryPersistence: enumValue(policy.memoryPersistence, "Memory policy", [
      "disabled",
      "local_only",
      "configured_provider",
    ] as const),
    skillManagement: enumValue(policy.skillManagement, "Skill management policy", [
      "disabled",
      "owner_only",
      "runtime_policy",
    ] as const),
  });
}

function stringSet(value: unknown, label: string): readonly string[] {
  if (!Array.isArray(value) || value.length > 512) {
    throw new Error(`${label} are invalid`);
  }
  const strings = value.map((item) => boundedString(item, label, 256));
  if (new Set(strings).size !== strings.length) {
    throw new Error(`${label} contain duplicates`);
  }
  return Object.freeze(strings);
}

function exactRecord(
  value: unknown,
  label: string,
  keys: readonly string[],
): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${label} is invalid`);
  }
  const record = value as Record<string, unknown>;
  if (Object.keys(record).some((key) => !keys.includes(key))) {
    throw new Error(`${label} contains unknown fields`);
  }
  if (keys.some((key) => !Object.hasOwn(record, key))) {
    throw new Error(`${label} is incomplete`);
  }
  return record;
}

function boundedString(value: unknown, label: string, maximum: number): string {
  if (typeof value !== "string" || value.length === 0 || value.length > maximum) {
    throw new Error(`${label} is invalid`);
  }
  return value;
}

function nullableString(value: unknown, label: string, maximum: number): string | null {
  return value === null ? null : boundedString(value, label, maximum);
}

function enumValue<const T extends readonly string[]>(
  value: unknown,
  label: string,
  allowed: T,
): T[number] {
  if (typeof value !== "string" || !allowed.includes(value)) {
    throw new Error(`${label} is unsupported`);
  }
  return value as T[number];
}
