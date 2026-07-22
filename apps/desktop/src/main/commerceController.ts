import {
  COMMERCE_CHECKOUT_CHANNEL,
  COMMERCE_PORTAL_CHANNEL,
  COMMERCE_STATUS_CHANNEL,
  parseBillingStatus,
  type CommerceOpenReceipt,
} from "../shared/commerce";
import type { SidecarRequest } from "./sidecarSupervisor";

const MAX_RESPONSE_BYTES = 256 * 1024;

type IpcEvent = { sender: { id: number } };
type IpcMainLike = {
  handle(channel: string, handler: (event: IpcEvent, value?: unknown) => unknown): void;
  removeHandler(channel: string): void;
};

export function registerCommerceController(options: {
  ipcMain: IpcMainLike;
  openExternal: (url: string) => Promise<unknown> | unknown;
  requesterWebContents: { id: number };
  sidecarRequest: SidecarRequest;
}): () => void {
  const trusted = (event: IpcEvent) => {
    if (event.sender.id !== options.requesterWebContents.id) {
      throw new Error("Billing control is restricted to the requester window");
    }
  };
  options.ipcMain.handle(COMMERCE_STATUS_CHANNEL, async (event) => {
    trusted(event);
    return parseBillingStatus(await requestJson(options.sidecarRequest, "/commerce/status"));
  });
  options.ipcMain.handle(COMMERCE_CHECKOUT_CHANNEL, async (event, value) => {
    trusted(event);
    const planId = planRequest(value);
    const response = record(await requestJson(options.sidecarRequest, "/commerce/checkout", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ planId }),
    }));
    await openBillingDestination(options.openExternal, response.checkoutUrl);
    return Object.freeze<CommerceOpenReceipt>({ opened: true });
  });
  options.ipcMain.handle(COMMERCE_PORTAL_CHANNEL, async (event, value) => {
    trusted(event);
    if (value !== undefined) throw new Error("Customer portal does not accept Provider parameters");
    const response = record(await requestJson(
      options.sidecarRequest,
      "/commerce/customer-portal",
      { method: "POST" },
    ));
    await openBillingDestination(options.openExternal, response.portalUrl);
    const verificationNonce = boundedText(response.verificationNonce, 256);
    const verification = record(await requestJson(
      options.sidecarRequest,
      "/commerce/customer-portal/verified",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ verificationNonce }),
      },
    ));
    if (verification.verified !== true) {
      throw new Error("commerce_portal_verification_failed");
    }
    return Object.freeze<CommerceOpenReceipt>({ opened: true });
  });
  return () => {
    options.ipcMain.removeHandler(COMMERCE_STATUS_CHANNEL);
    options.ipcMain.removeHandler(COMMERCE_CHECKOUT_CHANNEL);
    options.ipcMain.removeHandler(COMMERCE_PORTAL_CHANNEL);
  };
}

async function openBillingDestination(
  openExternal: (url: string) => Promise<unknown> | unknown,
  value: unknown,
): Promise<void> {
  const url = trustedCreemUrl(value);
  try {
    await openExternal(url);
  } catch {
    throw new Error("commerce_browser_open_failed");
  }
}

function planRequest(value: unknown): string {
  const input = record(value);
  if (Object.keys(input).length !== 1 || !Object.hasOwn(input, "planId")) {
    throw new Error("Billing checkout request is invalid");
  }
  return boundedText(input.planId, 128);
}

async function requestJson(request: SidecarRequest, pathname: string, init?: RequestInit): Promise<unknown> {
  const response = await request(pathname, init);
  const declared = Number(response.headers.get("content-length"));
  if (Number.isFinite(declared) && declared > MAX_RESPONSE_BYTES) {
    throw new Error("Billing response is too large");
  }
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes.byteLength === 0 || bytes.byteLength > MAX_RESPONSE_BYTES) {
    throw new Error("Billing response is invalid");
  }
  let value: unknown;
  try {
    value = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)) as unknown;
  } catch {
    throw new Error("Billing response is invalid");
  }
  if (!response.ok) {
    const code = record(value).code;
    throw new Error(typeof code === "string" && /^commerce_[a-z0-9_]+$/.test(code)
      ? code
      : "commerce_unavailable");
  }
  return value;
}

function trustedCreemUrl(value: unknown): string {
  const parsed = new URL(boundedText(value, 2048));
  const host = parsed.hostname;
  if (parsed.protocol !== "https:" || parsed.username || parsed.password || parsed.hash
    || (host !== "creem.io" && !host.endsWith(".creem.io"))) {
    throw new Error("Billing provider returned an invalid browser destination");
  }
  return parsed.toString();
}

function boundedText(value: unknown, maximum: number): string {
  if (typeof value !== "string" || !value || value.length > maximum || /[\r\n\0]/.test(value)) {
    throw new Error("Billing value is invalid");
  }
  return value;
}

function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Billing response is invalid");
  }
  return value as Record<string, unknown>;
}
