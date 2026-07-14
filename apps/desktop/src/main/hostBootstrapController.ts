import {
  HOST_BOOTSTRAP_LOAD_CHANNEL,
  parseHostDiscovery,
  type AgentAppHostDiscovery,
} from "../shared/hostBootstrap";

const MAX_BOOTSTRAP_BYTES = 256 * 1024;
const BOOTSTRAP_TIMEOUT_MS = 5_000;

type IpcEvent = { sender: { id: number } };

type IpcMainLike = {
  handle(channel: string, handler: (event: IpcEvent) => unknown): void;
  removeHandler(channel: string): void;
};

export type HostBootstrapControllerOptions = {
  fetchImpl?: typeof fetch;
  ipcMain: IpcMainLike;
  requesterWebContents: { id: number };
  serverBaseUrl?: string;
};

export function registerHostBootstrapController(
  options: HostBootstrapControllerOptions,
): () => void {
  options.ipcMain.handle(HOST_BOOTSTRAP_LOAD_CHANNEL, async (event) => {
    if (event.sender.id !== options.requesterWebContents.id) {
      throw new Error("Host bootstrap is restricted to the requester window");
    }
    return loadHostBootstrap(options);
  });

  return () => options.ipcMain.removeHandler(HOST_BOOTSTRAP_LOAD_CHANNEL);
}

async function loadHostBootstrap(
  options: HostBootstrapControllerOptions,
): Promise<AgentAppHostDiscovery> {
  const baseUrl = options.serverBaseUrl ?? "http://127.0.0.1:49321";
  let response: Response;
  try {
    response = await (options.fetchImpl ?? fetch)(new URL("/host/bootstrap", baseUrl), {
      cache: "no-store",
      headers: { Accept: "application/json" },
      method: "GET",
      signal: AbortSignal.timeout(BOOTSTRAP_TIMEOUT_MS),
    });
  } catch {
    throw new Error("Host bootstrap is unavailable");
  }
  const declaredLength = Number(response.headers.get("content-length"));
  if (Number.isFinite(declaredLength) && declaredLength > MAX_BOOTSTRAP_BYTES) {
    throw new Error("Host bootstrap response is too large");
  }
  if (!response.ok) {
    throw new Error(`Host bootstrap is unavailable (HTTP ${response.status})`);
  }
  const body = await response.text();
  if (body.length === 0 || new TextEncoder().encode(body).byteLength > MAX_BOOTSTRAP_BYTES) {
    throw new Error("Host bootstrap response is invalid");
  }
  let value: unknown;
  try {
    value = JSON.parse(body);
  } catch {
    throw new Error("Host bootstrap response is invalid");
  }
  const discovery = parseHostDiscovery(value);
  if (discovery.platform !== "desktop") {
    throw new Error("Host bootstrap platform is unsupported");
  }
  return discovery;
}
