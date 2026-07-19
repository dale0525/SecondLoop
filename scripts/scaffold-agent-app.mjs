import {
  existsSync,
  lstatSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  realpathSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { dirname, extname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

import { validateSkillPackageContract } from "./validate-skill-package.mjs";
import { validateAgentWeaveProjectWorkspace, validateRuntimeProviderProjection } from "./agentweave-project.mjs";

import {
  VSCODE_BUILTIN_THEME_IDS,
  parseJsonc,
  validateVsCodeThemeDocument,
} from "./vscode-theme.mjs";

export const PROJECT_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
export const FOUNDATION_CATALOG_PATH = join(PROJECT_ROOT, "catalog", "foundation-skills.json");
export const AGENT_APP_TEMPLATE_PATH = join(PROJECT_ROOT, "templates", "agent-app");
export const SUPPORTED_CATALOG_SCHEMA_VERSION = 1;
export const SUPPORTED_APP_SCHEMA_VERSION = 2;
export const SUPPORTED_PACKAGE_SCHEMA_VERSION = 1;

const ALLOWED_AUDIENCES = new Set(["consumer", "developer"]);
const ALLOWED_STABILITIES = new Set(["stable", "preview", "planned"]);
const ALLOWED_WAVES = new Set(["available", "wave1", "wave2"]);
const ALLOWED_PLATFORMS = new Set(["android", "desktop", "server"]);
const ALLOWED_SENSITIVITY_LEVELS = new Set([
  "public_or_user_directed",
  "workspace_private",
  "sensitive",
  "highly_sensitive",
]);
const SECRET_KEYS = new Set([
  "apikey",
  "accesstoken",
  "refreshtoken",
  "password",
  "clientsecret",
  "secret",
]);
const REQUIRED_TEMPLATE_FILES = [
  "README.md",
  "agent-app.json",
  "agentweave-project.json",
  "fonts/README.md",
  "locales/README.md",
  "locales/en.json",
  "locales/zh-CN.json",
  "packages/README.md",
  "prompts/developer.md",
  "prompts/system.md",
  "themes/README.md",
];
const VSCODE_BUILTIN_THEME_ID_SET = new Set(VSCODE_BUILTIN_THEME_IDS);
const FONT_FILE_PATTERN = /^(ui|display|mono)(?:-(100|200|300|400|500|600|700|800|900))?(?:-(italic))?\.(woff2|woff|ttf|otf)$/i;
const MAX_FONT_FILES = 24;
const MAX_FONT_FILE_BYTES = 8 * 1024 * 1024;
const MAX_TOTAL_FONT_BYTES = 32 * 1024 * 1024;
const MAX_APP_LOCALES = 32;
const MAX_LOCALE_MESSAGE_BYTES = 4096;

function fail(message) {
  throw new Error(message);
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function requireObject(value, label) {
  if (!isPlainObject(value)) fail(`${label} must be an object`);
  return value;
}

function requireOnlyKeys(value, allowed, label) {
  for (const key of Object.keys(value)) {
    if (!allowed.includes(key)) fail(`${label} contains unknown field '${key}'`);
  }
}

function requireString(value, label) {
  if (typeof value !== "string" || value.trim() === "") {
    fail(`${label} must be a non-empty string`);
  }
  return value;
}

function requireBoolean(value, label) {
  if (typeof value !== "boolean") fail(`${label} must be a boolean`);
  return value;
}

function requireInteger(value, label) {
  if (!Number.isInteger(value)) fail(`${label} must be an integer`);
  return value;
}

function requireStringArray(value, label, { nonEmpty = false, allowed } = {}) {
  if (!Array.isArray(value) || (nonEmpty && value.length === 0)) {
    fail(`${label} must be ${nonEmpty ? "a non-empty" : "an"} array`);
  }
  const seen = new Set();
  for (const item of value) {
    requireString(item, `${label} entry`);
    if (allowed && !allowed.has(item)) fail(`${label} contains unsupported value '${item}'`);
    if (seen.has(item)) fail(`${label} contains duplicate value '${item}'`);
    seen.add(item);
  }
  return value;
}

function requireSchemaVersion(value, supported, label) {
  requireInteger(value, label);
  if (value > supported) fail(`${label} ${value} is newer than supported version ${supported}`);
  if (value !== supported) fail(`${label} ${value} is unsupported; expected ${supported}`);
}

function requireSemver(value, label) {
  requireString(value, label);
  if (!/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(value)) {
    fail(`${label} must be a semantic version`);
  }
}

function normalizeSecretKey(key) {
  return key.toLowerCase().replaceAll(/[^a-z0-9]/g, "");
}

function isSecretKey(key) {
  const normalized = normalizeSecretKey(key);
  return SECRET_KEYS.has(normalized)
    || normalized.includes("password")
    || normalized.includes("secret")
    || normalized.includes("oauth")
    || normalized.includes("token")
    || normalized.includes("credential");
}

function rejectEmbeddedSecrets(value, path = "agent-app.json") {
  if (Array.isArray(value)) {
    value.forEach((item, index) => rejectEmbeddedSecrets(item, `${path}[${index}]`));
    return;
  }
  if (!isPlainObject(value)) return;
  for (const [key, child] of Object.entries(value)) {
    if (isSecretKey(key)) {
      fail(`${path}.${key} must not contain secret material`);
    }
    rejectEmbeddedSecrets(child, `${path}.${key}`);
  }
}

function pathIsWithin(root, candidate) {
  const rel = relative(root, candidate);
  return rel === "" || (!rel.startsWith(`..${sep}`) && rel !== ".." && !isAbsolute(rel));
}

function rejectSymlinkSegments(root, target, label) {
  const rel = relative(root, target);
  let current = root;
  for (const segment of rel.split(sep).filter(Boolean)) {
    current = join(current, segment);
    if (!existsSync(current)) break;
    if (lstatSync(current).isSymbolicLink()) fail(`${label} crosses symbolic link '${current}'`);
  }
}

export function resolveConfinedPath(root, input, label = "path", { allowRoot = false } = {}) {
  requireString(input, label);
  if (input.includes("\0")) fail(`${label} contains a NUL byte`);
  const rootReal = realpathSync(root);
  const target = resolve(root, input);
  if (!pathIsWithin(rootReal, target)) fail(`${label} escapes '${rootReal}'`);
  if (!allowRoot && target === rootReal) fail(`${label} must not target '${rootReal}' itself`);
  rejectSymlinkSegments(rootReal, target, label);
  if (existsSync(target)) {
    const targetReal = realpathSync(target);
    if (!pathIsWithin(rootReal, targetReal)) fail(`${label} resolves outside '${rootReal}'`);
  }
  return target;
}

function readJson(path, label = path) {
  let value;
  try {
    value = JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    fail(`${label} is not valid JSON: ${error instanceof Error ? error.message : String(error)}`);
  }
  return requireObject(value, label);
}

function sorted(values) {
  return [...values].sort();
}

function requireSameStrings(actual, expected, label) {
  if (JSON.stringify(sorted(actual)) !== JSON.stringify(sorted(expected))) {
    fail(`${label} does not match local package metadata`);
  }
}

function validateDependencies(value, label) {
  const dependencies = requireObject(value, label);
  for (const field of [
    "packages",
    "runtimeFeatures",
    "runtimeCapabilities",
    "connectors",
    "hostTools",
  ]) {
    requireStringArray(dependencies[field], `${label}.${field}`);
  }
  return dependencies;
}

function validatePermissions(value, label) {
  const permissions = requireObject(value, label);
  const required = requireStringArray(permissions.required, `${label}.required`);
  const conditional = requireStringArray(permissions.conditional, `${label}.conditional`);
  const overlap = required.find((permission) => conditional.includes(permission));
  if (overlap) fail(`${label} repeats '${overlap}' as required and conditional`);
}

function validateSensitivity(value, label) {
  const sensitivity = requireObject(value, label);
  requireString(sensitivity.level, `${label}.level`);
  if (!ALLOWED_SENSITIVITY_LEVELS.has(sensitivity.level)) {
    fail(`${label}.level '${sensitivity.level}' is unsupported`);
  }
  requireStringArray(sensitivity.categories, `${label}.categories`, { nonEmpty: true });
}

function validateReplacementContract(value, label) {
  const contract = requireObject(value, label);
  requireString(contract.id, `${label}.id`);
  requireInteger(contract.majorVersion, `${label}.majorVersion`);
  if (contract.majorVersion < 1) fail(`${label}.majorVersion must be positive`);
  requireBoolean(contract.replaceable, `${label}.replaceable`);
  requireBoolean(contract.canDisable, `${label}.canDisable`);
  requireStringArray(contract.requirements, `${label}.requirements`, { nonEmpty: true });
  return contract;
}

function validateLocalPackage(skill, catalogRoot) {
  if (skill.localPackage === undefined) return;
  const localPackage = requireObject(skill.localPackage, `${skill.id}.localPackage`);
  const packageRoot = resolveConfinedPath(
    catalogRoot,
    requireString(localPackage.path, `${skill.id}.localPackage.path`),
    `${skill.id}.localPackage.path`,
  );
  if (!existsSync(packageRoot) || !statSync(packageRoot).isDirectory()) {
    fail(`${skill.id}.localPackage.path does not identify a directory`);
  }
  const manifestPath = resolveConfinedPath(
    packageRoot,
    requireString(localPackage.manifest, `${skill.id}.localPackage.manifest`),
    `${skill.id}.localPackage.manifest`,
  );
  if (!existsSync(manifestPath) || !statSync(manifestPath).isFile()) {
    fail(`${skill.id}.localPackage.manifest does not identify a file`);
  }
  const manifest = readJson(manifestPath, `${skill.id} package manifest`);
  requireSchemaVersion(
    manifest.schemaVersion,
    SUPPORTED_PACKAGE_SCHEMA_VERSION,
    `${skill.id} package schemaVersion`,
  );
  if (manifest.id !== skill.id) fail(`${skill.id} does not match local package id '${manifest.id}'`);
  if (manifest.version !== skill.version) {
    fail(`${skill.id} version '${skill.version}' does not match local package '${manifest.version}'`);
  }
  const compatibility = requireObject(manifest.compatibility, `${skill.id} compatibility`);
  requireStringArray(compatibility.platforms, `${skill.id} compatibility.platforms`, {
    nonEmpty: true,
    allowed: ALLOWED_PLATFORMS,
  });
  requireSameStrings(skill.platforms, compatibility.platforms, `${skill.id} platforms`);
  const requires = requireObject(manifest.requires, `${skill.id} requires`);
  for (const field of ["packages", "capabilities", "runtimeTools", "connectors"]) {
    requireStringArray(requires[field], `${skill.id} requires.${field}`);
  }
  requireSameStrings(skill.dependencies.packages, requires.packages, `${skill.id} package dependencies`);
  requireSameStrings(
    skill.dependencies.runtimeCapabilities,
    requires.capabilities,
    `${skill.id} runtime capabilities`,
  );
  requireSameStrings(skill.dependencies.hostTools, requires.runtimeTools, `${skill.id} host tools`);
  requireSameStrings(skill.dependencies.connectors, requires.connectors, `${skill.id} connectors`);
}

export function validateCatalogData(catalog, { root = PROJECT_ROOT } = {}) {
  requireObject(catalog, "foundation catalog");
  requireSchemaVersion(
    catalog.schemaVersion,
    SUPPORTED_CATALOG_SCHEMA_VERSION,
    "foundation catalog schemaVersion",
  );
  requireString(catalog.catalogId, "foundation catalog catalogId");
  requireSemver(catalog.catalogVersion, "foundation catalog catalogVersion");
  const policy = requireObject(catalog.replacementPolicy, "foundation catalog replacementPolicy");
  if (policy.selection !== "app_manifest") fail("replacementPolicy.selection must be 'app_manifest'");
  if (policy.identity !== "replacement_contract") {
    fail("replacementPolicy.identity must be 'replacement_contract'");
  }
  if (policy.versioning !== "semantic_major") {
    fail("replacementPolicy.versioning must be 'semantic_major'");
  }
  if (policy.fallback !== "disabled") fail("replacementPolicy.fallback must be 'disabled'");
  requireStringArray(policy.mustNotBypass, "replacementPolicy.mustNotBypass", { nonEmpty: true });
  requireObject(catalog.waves, "foundation catalog waves");
  for (const wave of ALLOWED_WAVES) requireString(catalog.waves[wave], `waves.${wave}`);
  if (!Array.isArray(catalog.skills) || catalog.skills.length === 0) {
    fail("foundation catalog skills must be a non-empty array");
  }

  const ids = new Set();
  const contracts = new Set();
  let consumerDefaults = 0;
  for (const entry of catalog.skills) {
    const skill = requireObject(entry, "foundation skill");
    const id = requireString(skill.id, "foundation skill id");
    if (ids.has(id)) fail(`foundation catalog contains duplicate skill '${id}'`);
    ids.add(id);
    requireSemver(skill.version, `${id}.version`);
    requireString(skill.displayName, `${id}.displayName`);
    requireString(skill.description, `${id}.description`);
    const audience = requireStringArray(skill.audience, `${id}.audience`, {
      nonEmpty: true,
      allowed: ALLOWED_AUDIENCES,
    });
    requireBoolean(skill.consumerDefault, `${id}.consumerDefault`);
    requireString(skill.stability, `${id}.stability`);
    if (!ALLOWED_STABILITIES.has(skill.stability)) fail(`${id}.stability is unsupported`);
    requireString(skill.wave, `${id}.wave`);
    if (!ALLOWED_WAVES.has(skill.wave)) fail(`${id}.wave is unsupported`);
    requireStringArray(skill.platforms, `${id}.platforms`, {
      nonEmpty: true,
      allowed: ALLOWED_PLATFORMS,
    });
    skill.dependencies = validateDependencies(skill.dependencies, `${id}.dependencies`);
    validatePermissions(skill.permissions, `${id}.permissions`);
    validateSensitivity(skill.dataSensitivity, `${id}.dataSensitivity`);
    const contract = validateReplacementContract(skill.replacementContract, `${id}.replacementContract`);
    if (contracts.has(contract.id)) fail(`duplicate replacement contract '${contract.id}'`);
    contracts.add(contract.id);
    if (skill.consumerDefault) {
      consumerDefaults += 1;
      if (!audience.includes("consumer")) fail(`${id} is default but not consumer-facing`);
      if (skill.stability === "planned") fail(`${id} is planned and cannot be consumer-default`);
    }
    if (audience.length === 1 && audience[0] === "developer" && skill.consumerDefault) {
      fail(`${id} is developer-only and cannot be consumer-default`);
    }
    validateLocalPackage(skill, root);
  }
  if (consumerDefaults === 0) fail("foundation catalog must provide a consumer default");
  for (const skill of catalog.skills) {
    for (const dependency of skill.dependencies.packages) {
      if (!ids.has(dependency)) fail(`${skill.id} depends on unknown package '${dependency}'`);
    }
  }
  return catalog;
}

export function validateCatalogFile(path = FOUNDATION_CATALOG_PATH) {
  const confined = resolveConfinedPath(PROJECT_ROOT, path, "catalog path");
  if (!existsSync(confined) || !statSync(confined).isFile()) {
    fail(`catalog path '${confined}' does not identify a file`);
  }
  return validateCatalogData(readJson(confined, "foundation catalog"));
}

function validateAppId(value) {
  requireString(value, "agent app appId");
  const segments = value.split(".");
  const valid = segments.length >= 3 && segments.every((segment) => (
    segment.length > 0
      && !segment.startsWith("-")
      && !segment.endsWith("-")
      && /^[a-z0-9-]+$/.test(segment)
  ));
  if (!valid || value.length > 128) {
    fail("agent app appId must be a reverse-DNS identifier");
  }
}

function validateAppName(value) {
  requireString(value, "agent app displayName");
  if (value !== value.trim() || value.length > 80 || /[\u0000-\u001f\u007f]/.test(value)) {
    fail("agent app displayName must be at most 80 characters without control characters");
  }
}

function validatePromptFile(appRoot, value, label) {
  const promptPath = validatePortableResourceFile(appRoot, value, label);
  const content = readFileSync(promptPath, "utf8");
  if (content.trim() === "") fail(`${label} must not be empty`);
}

function validatePortableResourceFile(appRoot, value, label) {
  const relativePath = requireString(value, label);
  if (
    isAbsolute(relativePath)
    || relativePath.includes("\\")
    || relativePath.split("/").some((segment) => segment === "" || segment === "." || segment === "..")
  ) {
    fail(`${label} must be a portable relative path`);
  }
  const promptPath = resolveConfinedPath(appRoot, relativePath, label);
  if (!existsSync(promptPath) || !statSync(promptPath).isFile()) {
    fail(`${label} does not identify a file`);
  }
  return promptPath;
}

function validateAppearanceId(value, label) {
  requireString(value, label);
  const valid = value.split(".").every((segment) => (
    segment.length > 0
      && !segment.startsWith("-")
      && !segment.endsWith("-")
      && /^[a-z0-9-]+$/.test(segment)
  ));
  if (value.length > 128 || !valid) {
    fail(`${label} must be a lowercase theme identifier`);
  }
  return value;
}

function validateThemeResource(appRoot, relativePath, label, stack = []) {
  if (!relativePath.startsWith("themes/")) fail(`${label} must be inside the themes directory`);
  if (![".json", ".jsonc"].includes(extname(relativePath).toLowerCase())) {
    fail(`${label} must be a .json or .jsonc file`);
  }
  if (stack.length >= 8) fail(`${label} include depth exceeds 8`);
  const themePath = validatePortableResourceFile(appRoot, relativePath, label);
  if (stack.includes(themePath)) fail(`${label} contains an include cycle`);
  const document = validateVsCodeThemeDocument(
    parseJsonc(readFileSync(themePath, "utf8"), label),
    label,
  );
  if (document.include) {
    const includedPath = resolve(dirname(themePath), document.include);
    const includedRelative = relative(appRoot, includedPath).split(sep).join("/");
    validateThemeResource(appRoot, includedRelative, `${label}.include`, [...stack, themePath]);
  }
}

function validateAppearance(appRoot, appearance) {
  if (appearance === undefined || appearance === null) return;
  requireObject(appearance, "agent app appearance");
  requireOnlyKeys(appearance, ["defaultTheme", "themes"], "agent app appearance");
  const themes = requireObject(appearance.themes, "agent app appearance.themes");
  requireOnlyKeys(themes, ["builtins", "custom"], "agent app appearance.themes");
  const builtins = requireStringArray(
    themes.builtins,
    "agent app appearance.themes.builtins",
    { allowed: VSCODE_BUILTIN_THEME_ID_SET },
  );
  if (!Array.isArray(themes.custom)) fail("agent app appearance.themes.custom must be an array");
  const selected = new Set(builtins);
  for (const [index, entryValue] of themes.custom.entries()) {
    const label = `agent app appearance.themes.custom[${index}]`;
    const entry = requireObject(entryValue, label);
    requireOnlyKeys(entry, ["id", "label", "path"], label);
    const id = validateAppearanceId(entry.id, `${label}.id`);
    if (selected.has(id)) fail(`agent app appearance contains duplicate theme '${id}'`);
    selected.add(id);
    if (entry.label !== undefined && entry.label !== null) validateAppName(entry.label);
    validateThemeResource(appRoot, requireString(entry.path, `${label}.path`), `${label}.path`);
  }
  const defaultTheme = validateAppearanceId(
    appearance.defaultTheme,
    "agent app appearance.defaultTheme",
  );
  if (!selected.has(defaultTheme)) {
    fail("agent app appearance.defaultTheme must select a packaged theme");
  }
}

function validateLocaleId(value, label) {
  requireString(value, label);
  const segments = value.split("-");
  const primary = segments[0] ?? "";
  const valid = primary.length >= 2
    && primary.length <= 8
    && /^[a-z]+$/.test(primary)
    && segments.slice(1).every((segment) => /^[A-Za-z0-9]{1,8}$/.test(segment));
  if (!valid || value.length > 64) {
    fail(`${label} must be a BCP 47 tag such as 'en' or 'zh-CN'`);
  }
  return value;
}

function messagePlaceholders(value) {
  return [...value.matchAll(/\{([A-Za-z][A-Za-z0-9_]*)\}/g)]
    .map((match) => match[1])
    .sort();
}

function validateLocaleCatalog(appRoot, resource, label) {
  if (!resource.startsWith("locales/") || extname(resource).toLowerCase() !== ".json") {
    fail(`${label} must be a JSON file inside the locales directory`);
  }
  const path = validatePortableResourceFile(appRoot, resource, label);
  const catalog = readJson(path, label);
  requireObject(catalog, label);
  for (const [key, value] of Object.entries(catalog)) {
    if (!/^[a-z][A-Za-z0-9]*(?:[._-][A-Za-z0-9]+)*$/.test(key)) {
      fail(`${label} contains invalid message key '${key}'`);
    }
    if (typeof value !== "string" || value.trim() === "" || Buffer.byteLength(value, "utf8") > MAX_LOCALE_MESSAGE_BYTES) {
      fail(`${label}.${key} must be a non-empty string no larger than ${MAX_LOCALE_MESSAGE_BYTES} bytes`);
    }
  }
  return catalog;
}

function validateLocalization(appRoot, localization) {
  if (localization === undefined || localization === null) return;
  requireObject(localization, "agent app localization");
  requireOnlyKeys(localization, ["defaultLocale", "locales"], "agent app localization");
  const defaultLocale = validateLocaleId(
    localization.defaultLocale,
    "agent app localization.defaultLocale",
  );
  if (!Array.isArray(localization.locales) || localization.locales.length === 0) {
    fail("agent app localization.locales must be a non-empty array");
  }
  if (localization.locales.length > MAX_APP_LOCALES) {
    fail(`agent app localization.locales must contain at most ${MAX_APP_LOCALES} locales`);
  }
  const ids = new Set();
  const catalogs = [];
  for (const [index, entryValue] of localization.locales.entries()) {
    const label = `agent app localization.locales[${index}]`;
    const entry = requireObject(entryValue, label);
    requireOnlyKeys(entry, ["id", "label", "resource"], label);
    const id = validateLocaleId(entry.id, `${label}.id`);
    if (ids.has(id)) fail(`agent app localization contains duplicate locale '${id}'`);
    ids.add(id);
    validateAppName(entry.label);
    const resource = requireString(entry.resource, `${label}.resource`);
    catalogs.push({ id, messages: validateLocaleCatalog(appRoot, resource, `${label}.resource`) });
  }
  if (!ids.has(defaultLocale)) {
    fail("agent app localization.defaultLocale must select a packaged locale");
  }
  const reference = catalogs.find((entry) => entry.id === defaultLocale).messages;
  const referenceKeys = Object.keys(reference).sort();
  for (const catalog of catalogs) {
    const keys = Object.keys(catalog.messages).sort();
    if (JSON.stringify(keys) !== JSON.stringify(referenceKeys)) {
      fail(`agent app locale '${catalog.id}' must contain the same message keys as '${defaultLocale}'`);
    }
    for (const key of referenceKeys) {
      if (JSON.stringify(messagePlaceholders(catalog.messages[key])) !== JSON.stringify(messagePlaceholders(reference[key]))) {
        fail(`agent app locale '${catalog.id}' message '${key}' must preserve placeholders from '${defaultLocale}'`);
      }
    }
  }
}

function validateFontDirectory(appRoot) {
  const fontsRoot = join(appRoot, "fonts");
  if (!existsSync(fontsRoot)) return;
  if (!statSync(fontsRoot).isDirectory() || lstatSync(fontsRoot).isSymbolicLink()) {
    fail("Agent App fonts must be a real directory");
  }
  const fontFiles = [];
  for (const entry of readdirSync(fontsRoot, { withFileTypes: true })) {
    if (entry.isSymbolicLink()) fail(`Agent App font '${entry.name}' must not be a symlink`);
    if (entry.isDirectory()) fail(`Agent App fonts must not contain directory '${entry.name}'`);
    if (!entry.isFile()) fail(`Agent App fonts contain unsupported entry '${entry.name}'`);
    if (entry.name.toLowerCase() === "readme.md") continue;
    if (!FONT_FILE_PATTERN.test(entry.name)) {
      fail(`Agent App font '${entry.name}' does not follow the font slot convention`);
    }
    fontFiles.push(entry.name);
  }
  if (fontFiles.length > MAX_FONT_FILES) fail(`Agent App fonts exceed ${MAX_FONT_FILES} files`);
  let totalBytes = 0;
  for (const name of fontFiles) {
    const path = resolveConfinedPath(fontsRoot, name, `Agent App font '${name}'`);
    const bytes = statSync(path).size;
    if (bytes === 0 || bytes > MAX_FONT_FILE_BYTES) {
      fail(`Agent App font '${name}' must be between 1 byte and ${MAX_FONT_FILE_BYTES} bytes`);
    }
    totalBytes += bytes;
  }
  if (totalBytes > MAX_TOTAL_FONT_BYTES) fail("Agent App fonts exceed the 32 MiB total limit");
}

export function validateAgentApp(
  appPath,
  { catalogPath = FOUNDATION_CATALOG_PATH, validateProject = true } = {},
) {
  const appRoot = resolveConfinedPath(PROJECT_ROOT, appPath, "agent app path");
  if (!existsSync(appRoot) || !statSync(appRoot).isDirectory()) {
    fail(`agent app path '${appRoot}' does not identify a directory`);
  }
  const catalog = validateCatalogFile(catalogPath);
  const manifestPath = resolveConfinedPath(appRoot, "agent-app.json", "agent app manifest");
  if (!existsSync(manifestPath) || !statSync(manifestPath).isFile()) {
    fail("agent app manifest is missing");
  }
  const app = readJson(manifestPath, "agent app manifest");
  rejectEmbeddedSecrets(app);
  validateRuntimeProviderProjection(app);
  requireOnlyKeys(
    app,
    [
      "schemaVersion",
      "appId",
      "package",
      "compatibility",
      "requires",
      "features",
      "policy",
      "branding",
      "appearance",
      "localization",
      "instructions",
      "modelAccess",
      "identity",
      "entitlements",
    ],
    "agent app manifest",
  );
  validateAppId(app.appId);

  const appPackage = requireObject(app.package, "agent app package");
  requireOnlyKeys(appPackage, ["id", "version"], "agent app package");
  validateAppId(appPackage.id);
  requireSemver(appPackage.version, "agent app package.version");

  const compatibility = requireObject(app.compatibility, "agent app compatibility");
  requireOnlyKeys(compatibility, ["runtime", "platforms"], "agent app compatibility");
  if (compatibility.runtime !== null && compatibility.runtime !== undefined) {
    requireString(compatibility.runtime, "agent app compatibility.runtime");
  }
  const platforms = requireStringArray(compatibility.platforms, "agent app compatibility.platforms", {
    nonEmpty: true,
    allowed: ALLOWED_PLATFORMS,
  });

  const requirements = requireObject(app.requires, "agent app requires");
  requireOnlyKeys(
    requirements,
    ["packages", "capabilities", "runtimeTools", "connectors"],
    "agent app requires",
  );
  if (!Array.isArray(requirements.packages)) fail("agent app requires.packages must be an array");
  for (const field of ["capabilities", "runtimeTools", "connectors"]) {
    requireStringArray(requirements[field], `agent app requires.${field}`);
  }
  requireStringArray(app.features, "agent app features");
  const catalogById = new Map(catalog.skills.map((skill) => [skill.id, skill]));
  const localById = collectAppLocalPackages(appRoot);
  const enabled = new Set();
  for (const selection of requirements.packages) {
    const selected = requireObject(selection, "agent app package requirement");
    requireOnlyKeys(selected, ["id", "version"], "agent app package requirement");
    const id = requireString(selected.id, "agent app required package id");
    validateAppId(id);
    const requestedVersion = requireString(selected.version, `${id} required version`);
    if (enabled.has(id)) fail(`agent app contains duplicate skill '${id}'`);
    enabled.add(id);
    const skill = catalogById.get(id) ?? localById.get(id);
    if (!skill) fail(`agent app selects unknown skill '${id}'`);
    if (requestedVersion !== skill.version && requestedVersion !== `=${skill.version}`) {
      fail(`agent app selects incompatible ${id} version`);
    }
    if (skill.stability === "planned") fail(`agent app cannot enable planned skill '${id}'`);
    if (skill.audience && !skill.audience.includes("consumer")) {
      fail(`consumer Agent App cannot enable '${id}'`);
    }
    for (const platform of platforms) {
      if (!skill.platforms.includes(platform)) fail(`${id} does not support app platform '${platform}'`);
    }
  }
  for (const id of enabled) {
    const skill = catalogById.get(id) ?? localById.get(id);
    for (const dependency of skill.dependencies.packages) {
      if (!enabled.has(dependency)) fail(`${id} requires enabled package '${dependency}'`);
    }
    requireDeclaredRequirements(id, skill.dependencies, requirements);
  }

  const policy = requireObject(app.policy, "agent app policy");
  requireOnlyKeys(
    policy,
    [
      "externalSideEffects",
      "network",
      "backgroundExecution",
      "memoryPersistence",
      "skillManagement",
    ],
    "agent app policy",
  );
  if (policy.externalSideEffects !== "deny" && policy.externalSideEffects !== "require_approval") {
    fail("agent app policy.externalSideEffects must deny or require approval");
  }
  if (policy.network !== "deny" && policy.network !== "declared_only") {
    fail("agent app policy.network must be deny or declared_only");
  }
  if (policy.backgroundExecution !== "disabled" && policy.backgroundExecution !== "declared_only") {
    fail("agent app policy.backgroundExecution must be disabled or declared_only");
  }
  if (!["disabled", "local_only", "configured_provider"].includes(policy.memoryPersistence)) {
    fail("agent app policy.memoryPersistence is unsupported");
  }
  if (policy.skillManagement !== "disabled" && policy.skillManagement !== "owner_only") {
    fail("agent app policy.skillManagement must be disabled or owner_only");
  }

  const branding = requireObject(app.branding, "agent app branding");
  requireOnlyKeys(
    branding,
    ["displayName", "shortName", "description", "icon", "wordmark", "accentColor"],
    "agent app branding",
  );
  validateAppName(branding.displayName);
  if (branding.shortName !== undefined && branding.shortName !== null) {
    validateAppName(branding.shortName);
  }
  if (branding.description !== undefined && branding.description !== null) {
    requireString(branding.description, "agent app branding.description");
  }
  if (branding.accentColor !== undefined && branding.accentColor !== null) {
    if (!/^#[0-9A-Fa-f]{6}(?:[0-9A-Fa-f]{2})?$/.test(branding.accentColor)) {
      fail("agent app branding.accentColor must be #RRGGBB or #RRGGBBAA");
    }
  }
  for (const field of ["icon", "wordmark"]) {
    if (branding[field] !== undefined && branding[field] !== null) {
      validatePromptFile(appRoot, branding[field], `agent app branding.${field}`);
    }
  }

  validateAppearance(appRoot, app.appearance);
  validateFontDirectory(appRoot);
  validateLocalization(appRoot, app.localization);

  const instructions = requireObject(app.instructions, "agent app instructions");
  requireOnlyKeys(instructions, ["system", "developer", "additional"], "agent app instructions");
  validatePromptFile(appRoot, instructions.system, "agent app instructions.system");
  if (instructions.developer !== undefined && instructions.developer !== null) {
    validatePromptFile(appRoot, instructions.developer, "agent app instructions.developer");
  }
  requireStringArray(instructions.additional, "agent app instructions.additional");
  for (const [index, additional] of instructions.additional.entries()) {
    validatePromptFile(appRoot, additional, `agent app instructions.additional[${index}]`);
  }
  if (validateProject) validateAgentWeaveProjectWorkspace(appRoot, { app });
  return { app, catalog };
}

function collectAppLocalPackages(appRoot) {
  const packagesRoot = join(appRoot, "packages");
  const packages = new Map();
  if (!existsSync(packagesRoot)) return packages;
  if (!statSync(packagesRoot).isDirectory()) fail("Agent App packages must be a directory");
  for (const entry of readdirSync(packagesRoot, { withFileTypes: true })) {
    if (entry.isSymbolicLink()) fail(`Agent App package '${entry.name}' must not be a symlink`);
    if (!entry.isDirectory()) continue;
    const root = resolveConfinedPath(packagesRoot, entry.name, `Agent App package '${entry.name}'`);
    const manifestPath = resolveConfinedPath(root, "agentweave.json", `${entry.name} manifest`);
    if (!existsSync(manifestPath)) continue;
    const manifest = readJson(manifestPath, `${entry.name} manifest`);
    rejectEmbeddedSecrets(manifest);
    validateSkillPackageContract(manifest, `${entry.name} manifest`);
    requireSchemaVersion(
      manifest.schemaVersion,
      SUPPORTED_PACKAGE_SCHEMA_VERSION,
      `${entry.name} schemaVersion`,
    );
    const id = requireString(manifest.id, `${entry.name} id`);
    validateAppId(id);
    if (packages.has(id)) fail(`Agent App contains duplicate local package '${id}'`);
    const version = requireString(manifest.version, `${id} version`);
    requireSemver(version, `${id} version`);
    const compatibility = requireObject(manifest.compatibility, `${id} compatibility`);
    const platforms = requireStringArray(compatibility.platforms, `${id} platforms`, {
      nonEmpty: true,
      allowed: ALLOWED_PLATFORMS,
    });
    const requires = requireObject(manifest.requires, `${id} requires`);
    for (const field of ["packages", "capabilities", "runtimeTools", "connectors"]) {
      requireStringArray(requires[field], `${id} requires.${field}`);
    }
    packages.set(id, {
      id,
      version,
      platforms,
      dependencies: {
        packages: requires.packages,
        runtimeCapabilities: requires.capabilities,
        hostTools: requires.runtimeTools,
        connectors: requires.connectors,
      },
    });
  }
  return packages;
}

function requireDeclaredRequirements(id, dependencies, requirements) {
  for (const [dependencyField, appField] of [
    ["runtimeCapabilities", "capabilities"],
    ["hostTools", "runtimeTools"],
    ["connectors", "connectors"],
  ]) {
    for (const required of dependencies[dependencyField]) {
      if (!requirements[appField].includes(required)) {
        fail(`${id} requires declared App ${appField} '${required}'`);
      }
    }
  }
}

function listFiles(root, prefix = "") {
  const directory = prefix ? join(root, prefix) : root;
  const files = [];
  for (const entry of readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    const rel = prefix ? join(prefix, entry.name) : entry.name;
    if (entry.isSymbolicLink()) fail(`template contains symbolic link '${rel}'`);
    if (entry.isDirectory()) files.push(...listFiles(root, rel));
    else if (entry.isFile()) files.push(rel);
    else fail(`template contains unsupported entry '${rel}'`);
  }
  return files.sort();
}

export function validateAgentAppTemplate(templatePath = AGENT_APP_TEMPLATE_PATH) {
  const templateRoot = resolveConfinedPath(PROJECT_ROOT, templatePath, "template path");
  if (!existsSync(templateRoot) || !statSync(templateRoot).isDirectory()) {
    fail("agent app template directory is missing");
  }
  const files = listFiles(templateRoot);
  for (const required of REQUIRED_TEMPLATE_FILES) {
    if (!files.includes(required)) fail(`agent app template is missing '${required}'`);
  }
  const manifest = readFileSync(join(templateRoot, "agent-app.json"), "utf8");
  if (
    !manifest.includes("{{APP_ID}}")
    || !manifest.includes("{{PACKAGE_ID}}")
    || !manifest.includes("{{APP_NAME}}")
  ) {
    fail("agent app template manifest is missing required placeholders");
  }
  return { files, templateRoot };
}

function renderTemplateFile(path, bytes, { appId, name }) {
  let content = bytes
    .replaceAll("{{APP_ID}}", appId)
    .replaceAll("{{PACKAGE_ID}}", `${appId}.app`)
    .replaceAll("{{APP_NAME}}", name);
  if (content.includes("{{")) fail(`template '${path}' contains an unresolved placeholder`);
  if (path === "agent-app.json") {
    const manifest = requireObject(JSON.parse(content), "rendered agent app manifest");
    content = `${JSON.stringify(manifest, null, 2)}\n`;
  }
  return content;
}

export function scaffoldAgentApp({ name, appId, output }) {
  validateAppName(name);
  validateAppId(appId);
  const catalog = validateCatalogFile();
  const { files, templateRoot } = validateAgentAppTemplate();
  const outputRoot = resolveConfinedPath(PROJECT_ROOT, output, "output path");
  if (existsSync(outputRoot)) {
    if (!statSync(outputRoot).isDirectory()) fail("output path already exists and is not a directory");
    if (readdirSync(outputRoot).length > 0) fail("output directory must be empty");
  }
  const rendered = files.map((path) => ({
    content: renderTemplateFile(path, readFileSync(join(templateRoot, path), "utf8"), { appId, name }),
    path,
  }));
  mkdirSync(outputRoot, { recursive: true });
  for (const file of rendered) {
    const destination = resolveConfinedPath(outputRoot, file.path, `template destination '${file.path}'`);
    mkdirSync(dirname(destination), { recursive: true });
    writeFileSync(destination, file.content, { encoding: "utf8", flag: "wx" });
  }
  const validated = validateAgentApp(outputRoot);
  if (validated.catalog.catalogId !== catalog.catalogId) fail("generated app catalog changed during scaffold");
  return outputRoot;
}

export function validateTarget(input) {
  const target = resolveConfinedPath(PROJECT_ROOT, input, "validation target");
  if (!existsSync(target)) fail(`validation target '${target}' does not exist`);
  if (statSync(target).isDirectory()) return validateAgentApp(target);
  if (!statSync(target).isFile()) fail("validation target must be a file or directory");
  const document = readJson(target, "validation target");
  if ("catalogId" in document && "skills" in document) return validateCatalogFile(target);
  if ("appId" in document) return validateAgentApp(dirname(target));
  fail("validation target is neither a foundation catalog nor an Agent App manifest");
}

function usage() {
  return [
    "Usage:",
    "  node scripts/scaffold-agent-app.mjs --name <name> --app-id <id> --output <path>",
    "  node scripts/scaffold-agent-app.mjs --validate [catalog-or-app-path]",
    "  node scripts/scaffold-agent-app.mjs --output <app-path> --validate",
  ].join("\n");
}

function parseArgs(argv) {
  const result = { appId: undefined, help: false, name: undefined, output: undefined, validate: undefined };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--help" || arg === "-h") {
      result.help = true;
      continue;
    }
    if (arg === "--validate") {
      const next = argv[index + 1];
      if (next && !next.startsWith("--")) {
        result.validate = next;
        index += 1;
      } else {
        result.validate = true;
      }
      continue;
    }
    const field = arg === "--name" ? "name" : arg === "--app-id" ? "appId" : arg === "--output" ? "output" : null;
    if (!field) fail(`unknown argument '${arg}'`);
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) fail(`${arg} requires a value`);
    result[field] = value;
    index += 1;
  }
  return result;
}

export function runCli(argv = process.argv.slice(2)) {
  const args = parseArgs(argv);
  if (args.help) {
    console.log(usage());
    return;
  }
  const wantsCreate = args.name !== undefined || args.appId !== undefined;
  if (wantsCreate) {
    if (!args.name || !args.appId || !args.output) fail("--name, --app-id, and --output are required together");
    if (typeof args.validate === "string") fail("creation cannot use --validate with a separate target");
    const output = scaffoldAgentApp({ name: args.name, appId: args.appId, output: args.output });
    console.log(`Created and validated Agent App at ${relative(PROJECT_ROOT, output)}`);
    return;
  }
  if (args.validate !== undefined) {
    const target = typeof args.validate === "string" ? args.validate : args.output ?? FOUNDATION_CATALOG_PATH;
    validateTarget(target);
    console.log(`Validated ${relative(PROJECT_ROOT, resolve(PROJECT_ROOT, target)) || "."}`);
    return;
  }
  fail(`missing scaffold or validation arguments\n${usage()}`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    runCli();
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  }
}
