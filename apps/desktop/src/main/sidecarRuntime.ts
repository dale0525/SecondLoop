import { accessSync, constants, statSync } from "node:fs";
import path from "node:path";

export type ManagedSidecarResolution = Readonly<{
  args: readonly string[];
  cacheRoot: string;
  command: string;
  cwd: string;
  dataRoot: string;
  env: NodeJS.ProcessEnv;
  mode: "managed";
  workspaceRoot: string;
}>;

export type ExternalSidecarResolution = Readonly<{
  baseUrl: string;
  mode: "external";
  transportToken: string | null;
}>;

export type UnavailableSidecarResolution = Readonly<{
  mode: "unavailable";
  reason:
    | "invalid-executable"
    | "invalid-server-token"
    | "invalid-server-url"
    | "missing-executable"
    | "missing-server-token";
}>;

export type DesktopSidecarResolution =
  | ExternalSidecarResolution
  | ManagedSidecarResolution
  | UnavailableSidecarResolution;

export type DesktopSidecarResolutionOptions = Readonly<{
  appPath: string;
  env: NodeJS.ProcessEnv;
  isExecutable?: (candidate: string) => boolean;
  isPackaged: boolean;
  platform?: NodeJS.Platform;
  resourcesPath: string;
  userDataPath: string;
}>;

export function resolveDesktopSidecar(
  options: DesktopSidecarResolutionOptions,
): DesktopSidecarResolution {
  if (options.env.AGENTWEAVE_SERVER_URL !== undefined) {
    const baseUrl = normalizeExternalBaseUrl(options.env.AGENTWEAVE_SERVER_URL);
    if (!baseUrl) return unavailable("invalid-server-url");
    const transportToken = normalizeExternalToken(options.env.AGENTWEAVE_SERVER_TOKEN);
    if (transportToken === undefined) return unavailable("invalid-server-token");
    if (!isLoopbackHostname(new URL(baseUrl).hostname) && transportToken === null) {
      return unavailable("missing-server-token");
    }
    return Object.freeze({ baseUrl, mode: "external", transportToken });
  }

  const platform = options.platform ?? process.platform;
  const executableName = platform === "win32" ? "agent-server.exe" : "agent-server";
  const explicitExecutable = options.env.AGENTWEAVE_SIDECAR_EXECUTABLE;
  const isExecutable = options.isExecutable ?? ((candidate) => executableExists(candidate, platform));
  const developmentRoot = path.resolve(options.appPath, "../..");
  let command: string | null = null;
  let cwd = options.isPackaged ? options.resourcesPath : developmentRoot;

  if (explicitExecutable !== undefined) {
    if (!path.isAbsolute(explicitExecutable) || !isExecutable(explicitExecutable)) {
      return unavailable("invalid-executable");
    }
    command = path.normalize(explicitExecutable);
  } else {
    const packaged = path.join(options.resourcesPath, "sidecar", executableName);
    if (isExecutable(packaged)) {
      command = packaged;
      cwd = options.resourcesPath;
    } else if (!options.isPackaged) {
      const development = path.join(developmentRoot, "target", "debug", executableName);
      if (isExecutable(development)) command = development;
    }
  }

  if (!command) return unavailable("missing-executable");

  const sidecarRoot = path.join(options.userDataPath, "sidecar");
  const dataRoot = path.join(sidecarRoot, "data");
  const cacheRoot = path.join(sidecarRoot, "cache");
  const workspaceRoot = path.join(sidecarRoot, "workspace");
  const childEnv = managedEnvironment({
    cacheRoot,
    cwd,
    dataRoot,
    env: options.env,
    isPackaged: options.isPackaged,
    resourcesPath: options.resourcesPath,
    workspaceRoot,
  });

  return Object.freeze({
    args: Object.freeze([]),
    cacheRoot,
    command,
    cwd,
    dataRoot,
    env: Object.freeze(childEnv),
    mode: "managed",
    workspaceRoot,
  });
}

function managedEnvironment(options: {
  cacheRoot: string;
  cwd: string;
  dataRoot: string;
  env: NodeJS.ProcessEnv;
  isPackaged: boolean;
  resourcesPath: string;
  workspaceRoot: string;
}): NodeJS.ProcessEnv {
  const env = allowedHostEnvironment(options.env);
  delete env.AGENTWEAVE_SERVER_URL;
  delete env.AGENTWEAVE_SERVER_TOKEN;
  delete env.AGENTWEAVE_SIDECAR_EXECUTABLE;
  delete env.AGENTWEAVE_DESKTOP_URL;
  delete env.AGENTWEAVE_LAUNCH_CONFIG_FD;
  delete env.AGENTWEAVE_LAUNCH_RESULT_FD;
  env.AGENTWEAVE_APP_DATA_ROOT = options.dataRoot;
  env.AGENTWEAVE_CACHE_ROOT = options.cacheRoot;
  env.AGENTWEAVE_DATABASE_URL = `sqlite://${path.join(options.dataRoot, "agentweave.db")}?mode=rwc`;
  env.AGENTWEAVE_MANAGED_SKILLS ??= "1";
  env.AGENTWEAVE_SKILLS_ROOT ??= path.join(
    options.isPackaged ? options.resourcesPath : options.cwd,
    "skills",
  );
  env.AGENTWEAVE_WORKSPACE_ROOT = options.workspaceRoot;
  return env;
}

const PASSTHROUGH_ENVIRONMENT = new Set([
  "COMSPEC",
  "DYLD_FALLBACK_LIBRARY_PATH",
  "DYLD_LIBRARY_PATH",
  "HOME",
  "HTTPS_PROXY",
  "HTTP_PROXY",
  "LANG",
  "LD_LIBRARY_PATH",
  "NO_PROXY",
  "PATH",
  "PATHEXT",
  "RUST_BACKTRACE",
  "RUST_LOG",
  "SSL_CERT_DIR",
  "SSL_CERT_FILE",
  "SYSTEMROOT",
  "TEMP",
  "TMP",
  "TMPDIR",
  "TZ",
  "USERPROFILE",
  "WINDIR",
  "https_proxy",
  "http_proxy",
  "no_proxy",
]);

function allowedHostEnvironment(source: NodeJS.ProcessEnv): NodeJS.ProcessEnv {
  return Object.fromEntries(Object.entries(source).filter(([name, value]) => (
    value !== undefined
    && (name.startsWith("AGENTWEAVE_") || PASSTHROUGH_ENVIRONMENT.has(name))
  )));
}

function normalizeExternalBaseUrl(value: string): string | null {
  try {
    const url = new URL(value);
    if (!new Set(["http:", "https:"]).has(url.protocol)) return null;
    if (url.protocol === "http:" && !isLoopbackHostname(url.hostname)) return null;
    if (url.username || url.password || url.search || url.hash) return null;
    if (url.pathname !== "/" && url.pathname !== "") return null;
    url.pathname = "/";
    return url.href;
  } catch {
    return null;
  }
}

function normalizeExternalToken(value: string | undefined): string | null | undefined {
  if (value === undefined || value === "") return null;
  return value.length >= 43
    && value.length <= 128
    && /^[A-Za-z0-9_-]+$/.test(value)
    ? value
    : undefined;
}

function isLoopbackHostname(hostname: string): boolean {
  return hostname === "localhost"
    || hostname === "[::1]"
    || hostname === "::1"
    || /^127(?:\.\d{1,3}){3}$/.test(hostname);
}

function executableExists(candidate: string, platform: NodeJS.Platform): boolean {
  try {
    if (!statSync(candidate).isFile()) return false;
    accessSync(candidate, platform === "win32" ? constants.F_OK : constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

function unavailable(reason: UnavailableSidecarResolution["reason"]): UnavailableSidecarResolution {
  return Object.freeze({
    mode: "unavailable",
    reason,
  });
}
