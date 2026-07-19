import { createServer, type Server } from "node:http";

const MAX_CALLBACK_URL_BYTES = 16 * 1024;
const DEFAULT_LIFETIME_MS = 11 * 60 * 1_000;

export type IdentityCallbackListener = Readonly<{
  close(): Promise<void>;
  setExpiresAt(expiresAt: string): void;
}>;

export async function prepareIdentityCallbackListener(options: {
  callback: (callbackUrl: string) => Promise<void>;
  redirectUri: string;
}): Promise<IdentityCallbackListener> {
  const redirect = parseDesktopRedirectUri(options.redirectUri);
  let handled = false;
  let closed = false;
  let timer: NodeJS.Timeout | null = null;
  const server = createServer(async (request, response) => {
    response.setHeader("cache-control", "no-store");
    response.setHeader("content-type", "text/plain; charset=utf-8");
    response.setHeader("x-content-type-options", "nosniff");
    if (
      handled
      || request.method !== "GET"
      || !isLoopbackAddress(request.socket.remoteAddress)
      || request.headers.host !== redirect.host
      || !request.url
      || Buffer.byteLength(request.url, "utf8") > MAX_CALLBACK_URL_BYTES
    ) {
      response.statusCode = handled ? 410 : 400;
      response.end("Authorization callback was rejected.");
      return;
    }
    let callback: URL;
    try {
      callback = new URL(request.url, redirect.origin);
    } catch {
      response.statusCode = 400;
      response.end("Authorization callback was rejected.");
      return;
    }
    if (
      callback.origin !== redirect.origin
      || callback.pathname !== redirect.pathname
      || callback.hash
    ) {
      response.statusCode = 400;
      response.end("Authorization callback was rejected.");
      return;
    }
    handled = true;
    try {
      await options.callback(callback.toString());
      response.statusCode = 200;
      response.end("Authorization completed. You can return to the app.");
    } catch {
      response.statusCode = 400;
      response.end("Authorization could not be completed. Return to the app and try again.");
    } finally {
      void close();
    }
  });

  const close = (): Promise<void> => {
    if (closed) return Promise.resolve();
    closed = true;
    if (timer) clearTimeout(timer);
    timer = null;
    return new Promise((resolve) => server.close(() => resolve()));
  };
  const setTimer = (delay: number) => {
    if (timer) clearTimeout(timer);
    timer = setTimeout(() => void close(), Math.max(1, delay));
    timer.unref?.();
  };

  await listen(server, redirect);
  setTimer(DEFAULT_LIFETIME_MS);
  return Object.freeze({
    close,
    setExpiresAt: (expiresAt: string) => {
      const expiry = Date.parse(expiresAt);
      if (!Number.isFinite(expiry)) throw new Error("Identity authorization expiry is invalid");
      setTimer(Math.min(DEFAULT_LIFETIME_MS, expiry - Date.now()));
    },
  });
}

export function parseDesktopRedirectUri(value: string): URL {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw new Error("Identity callback URI is invalid");
  }
  if (
    url.protocol !== "http:"
    || url.hostname !== "127.0.0.1"
    || !url.port
    || Number(url.port) < 1_024
    || Number(url.port) > 65_535
    || url.username
    || url.password
    || url.search
    || url.hash
    || !url.pathname.startsWith("/")
    || url.pathname === "/"
  ) {
    throw new Error("Identity callback URI must use a fixed 127.0.0.1 loopback port and path");
  }
  return url;
}

function listen(server: Server, redirect: URL): Promise<void> {
  return new Promise((resolve, reject) => {
    const onError = () => reject(new Error("Identity callback listener is unavailable"));
    server.once("error", onError);
    server.listen(Number(redirect.port), redirect.hostname, () => {
      server.removeListener("error", onError);
      resolve();
    });
  });
}

function isLoopbackAddress(value: string | undefined): boolean {
  return value === "127.0.0.1" || value === "::ffff:127.0.0.1";
}
