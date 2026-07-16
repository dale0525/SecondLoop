import type { SidecarApiOperation } from "../shared/sidecarApi";

type ErrorPayload = {
  error?: string;
};

export async function requestServer<T>(
  operation: SidecarApiOperation,
  input: unknown,
  developmentPath: string,
  developmentInit: RequestInit,
): Promise<T> {
  const bridge = window.agentWeave?.server;
  if (bridge) return bridge.request(operation, input) as Promise<T>;
  return requestDevelopmentJson<T>(developmentPath, developmentInit);
}

export async function requestDevelopmentJson<T>(path: string, init: RequestInit): Promise<T> {
  if (!import.meta.env.DEV) throw new Error("Trusted sidecar IPC is unavailable");
  const response = await fetch(`/__agentweave${path}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      ...init.headers,
    },
  });
  const payload = await readPayload(response);
  if (!response.ok) throw new Error(getErrorMessage(payload, response));
  return payload as T;
}

async function readPayload(response: Response): Promise<unknown> {
  const text = await response.text();
  if (!text) return {};
  try {
    return JSON.parse(text);
  } catch {
    return { error: text };
  }
}

function getErrorMessage(payload: unknown, response: Response): string {
  if (isErrorPayload(payload) && payload.error) return payload.error;
  return response.statusText || `HTTP ${response.status}`;
}

function isErrorPayload(payload: unknown): payload is ErrorPayload {
  return typeof payload === "object" && payload !== null && "error" in payload;
}
