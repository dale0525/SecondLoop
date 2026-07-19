export const HOST_BOOTSTRAP_LOAD_CHANNEL = "agentweave:host-bootstrap:load";
export const HOST_DISCOVERY_SCHEMA_VERSION = 2;

export type JsonValue = null | boolean | number | string | readonly JsonValue[] | {
  readonly [key: string]: JsonValue;
};

export type AgentAppProviderBinding = Readonly<{
  id: string;
  publicConfig: Readonly<Record<string, JsonValue>>;
  version: string;
}>;

export type AgentAppModelProfile = Readonly<{
  authentication: "none" | "user_identity";
  baseUrl: string;
  endpointType: "responses" | "chat_completions" | "completion";
  headers: Readonly<Record<string, string>>;
  modelName: string;
  providerId: string;
}>;

export type AgentAppHostAccess = Readonly<{
  entitlements: Readonly<{
    mode: "disabled" | "required";
    provider: AgentAppProviderBinding | null;
  }>;
  identity: Readonly<{
    mode: "local_single_user" | "required";
    provider: AgentAppProviderBinding | null;
  }>;
  modelAccess: Readonly<{
    configurationPolicy: "user_configurable" | "app_managed";
    profile: AgentAppModelProfile | null;
  }>;
}>;

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
  access: AgentAppHostAccess;
  features: readonly string[];
  identity: AgentAppHostIdentity;
  manifestSha256: string;
  platform: "desktop" | "android" | "ios" | "web" | "server";
  policy: AgentAppHostPolicy;
  requirements: AgentAppHostRequirements;
  runtimeVersion: string;
  schemaVersion: 2;
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
    "access",
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
    access: parseAccess(root.access),
  });
}

function parseAccess(value: unknown): AgentAppHostAccess {
  const access = exactRecord(value, "Host access configuration", [
    "modelAccess",
    "identity",
    "entitlements",
  ]);
  const modelAccess = exactRecord(access.modelAccess, "Model access", [
    "configurationPolicy",
    "profile",
  ]);
  const identity = exactRecord(access.identity, "Identity configuration", ["mode", "provider"]);
  const entitlements = exactRecord(access.entitlements, "Entitlement configuration", [
    "mode",
    "provider",
  ]);
  const identityMode = enumValue(identity.mode, "Identity mode", [
    "local_single_user",
    "required",
  ] as const);
  const entitlementMode = enumValue(entitlements.mode, "Entitlement mode", [
    "disabled",
    "required",
  ] as const);
  const identityProvider = nullableProvider(identity.provider, "Identity provider");
  const entitlementProvider = nullableProvider(entitlements.provider, "Entitlement provider");
  if ((identityMode === "required") !== (identityProvider !== null)) {
    throw new Error("Identity provider does not match the configured mode");
  }
  if ((entitlementMode === "required") !== (entitlementProvider !== null)) {
    throw new Error("Entitlement provider does not match the configured mode");
  }
  return Object.freeze({
    modelAccess: Object.freeze({
      configurationPolicy: enumValue(
        modelAccess.configurationPolicy,
        "Model configuration policy",
        ["user_configurable", "app_managed"] as const,
      ),
      profile: modelAccess.profile === null ? null : parseModelProfile(modelAccess.profile),
    }),
    identity: Object.freeze({ mode: identityMode, provider: identityProvider }),
    entitlements: Object.freeze({ mode: entitlementMode, provider: entitlementProvider }),
  });
}

function nullableProvider(value: unknown, label: string): AgentAppProviderBinding | null {
  if (value === null) return null;
  const provider = exactRecord(value, label, ["id", "version", "publicConfig"]);
  return Object.freeze({
    id: boundedString(provider.id, `${label} identifier`, 256),
    version: boundedString(provider.version, `${label} version`, 256),
    publicConfig: publicJsonObject(provider.publicConfig, `${label} public configuration`),
  });
}

function parseModelProfile(value: unknown): AgentAppModelProfile {
  const profile = exactRecord(value, "Model profile", [
    "providerId",
    "endpointType",
    "baseUrl",
    "modelName",
    "authentication",
    "headers",
  ]);
  let parsedUrl: URL;
  try {
    parsedUrl = new URL(boundedString(profile.baseUrl, "Model base URL", 2048));
  } catch {
    throw new Error("Model base URL is invalid");
  }
  if (!["http:", "https:"].includes(parsedUrl.protocol) || parsedUrl.username || parsedUrl.password) {
    throw new Error("Model base URL is invalid");
  }
  return Object.freeze({
    providerId: boundedString(profile.providerId, "Model provider identifier", 256),
    endpointType: enumValue(profile.endpointType, "Model endpoint type", [
      "responses",
      "chat_completions",
      "completion",
    ] as const),
    baseUrl: parsedUrl.toString().replace(/\/$/, ""),
    modelName: boundedString(profile.modelName, "Model name", 4096),
    authentication: enumValue(profile.authentication, "Model authentication", [
      "none",
      "user_identity",
    ] as const),
    headers: stringRecord(profile.headers, "Model headers", 32),
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

function stringRecord(
  value: unknown,
  label: string,
  maximumEntries: number,
): Readonly<Record<string, string>> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${label} are invalid`);
  }
  const entries = Object.entries(value as Record<string, unknown>);
  if (entries.length > maximumEntries) throw new Error(`${label} are invalid`);
  const result: Record<string, string> = {};
  for (const [key, item] of entries) {
    const name = boundedString(key, `${label} name`, 256);
    const normalized = name.replace(/[^A-Za-z0-9]/g, "").toLowerCase();
    if (
      normalized === "authorization"
      || normalized === "proxyauthorization"
      || normalized.includes("apikey")
      || normalized.includes("token")
      || normalized.includes("secret")
      || normalized.includes("credential")
    ) {
      throw new Error(`${label} contain a sensitive field`);
    }
    if (typeof item !== "string" || item.length > 4096) {
      throw new Error(`${label} are invalid`);
    }
    result[name] = item;
  }
  return Object.freeze(result);
}

function publicJsonObject(value: unknown, label: string): Readonly<Record<string, JsonValue>> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${label} is invalid`);
  }
  const encoded = JSON.stringify(value);
  if (encoded.length > 65_536) throw new Error(`${label} is too large`);
  return validateJsonObject(value as Record<string, unknown>, label, 0);
}

function validateJsonObject(
  value: Record<string, unknown>,
  label: string,
  depth: number,
): Readonly<Record<string, JsonValue>> {
  if (depth > 16) throw new Error(`${label} is too deeply nested`);
  const result: Record<string, JsonValue> = {};
  for (const [key, item] of Object.entries(value)) {
    const normalized = key.replace(/[^A-Za-z0-9]/g, "").toLowerCase();
    if (
      normalized.includes("password")
      || normalized.includes("secret")
      || normalized.includes("oauth")
      || normalized.includes("token")
      || normalized.includes("credential")
      || ["apikey", "accesskey", "privatekey", "clientkey"].includes(normalized)
    ) {
      throw new Error(`${label} contains a credential-shaped field`);
    }
    result[key] = validateJsonValue(item, label, depth + 1);
  }
  return Object.freeze(result);
}

function validateJsonValue(value: unknown, label: string, depth: number): JsonValue {
  if (value === null || typeof value === "boolean" || typeof value === "string") return value;
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (Array.isArray(value)) {
    if (depth > 16) throw new Error(`${label} is too deeply nested`);
    return Object.freeze(value.map((item) => validateJsonValue(item, label, depth + 1)));
  }
  if (value && typeof value === "object") {
    return validateJsonObject(value as Record<string, unknown>, label, depth);
  }
  throw new Error(`${label} contains a non-JSON value`);
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
