import { fail } from "./errors.js";
import { allowedResponseHeaders } from "./policy.js";

const DEFINITIVE_REJECTION_STATUSES = new Set([
  400,
  401,
  402,
  403,
  404,
  405,
  406,
  409,
  413,
  415,
  422,
  429,
]);

function runInBackground(context, promise) {
  const guarded = promise.catch(() => undefined);
  if (typeof context?.waitUntil === "function") context.waitUntil(guarded);
  else void guarded;
}

function once(operation) {
  let promise;
  return (...args) => {
    if (!promise) promise = Promise.resolve().then(() => operation(...args));
    return promise;
  };
}

export async function fetchModelUpstream(fetchImpl, prepared, { signal } = {}) {
  let response;
  try {
    response = await fetchImpl(prepared.upstreamUrl, {
      method: "POST",
      headers: prepared.headers,
      body: prepared.body,
      redirect: "manual",
      signal,
    });
  } catch {
    fail(502, "upstream_unavailable", "The model service is temporarily unavailable.", {
      dispatchOutcome: "uncertain",
    });
  }
  if (response.status < 200 || response.status >= 300) {
    try {
      await response.body?.cancel("redacted upstream error");
    } catch {
      // The upstream body is intentionally discarded and never logged or returned.
    }
    const rejected = DEFINITIVE_REJECTION_STATUSES.has(response.status);
    fail(502, rejected ? "upstream_rejected" : "upstream_unavailable", rejected
      ? "The model service rejected the request."
      : "The model service result is temporarily unavailable.", {
      dispatchOutcome: rejected ? "rejected" : "uncertain",
      headers: response.headers.get("retry-after")
        ? { "retry-after": response.headers.get("retry-after") }
        : {},
    });
  }
  return response;
}

export function streamingResponse(config, upstream, requestId, context, finalize) {
  const headers = allowedResponseHeaders(config, upstream.headers);
  headers.set("x-request-id", requestId);
  const finalizeOnce = once(finalize);
  if (!upstream.body) {
    runInBackground(context, finalizeOnce("completed"));
    return new Response(null, { status: upstream.status, headers });
  }

  const transform = new TransformStream();
  const completion = upstream.body.pipeTo(transform.writable)
    .then(
      () => finalizeOnce("completed"),
      () => finalizeOnce("cancelled"),
    );
  runInBackground(context, completion);
  return new Response(transform.readable, {
    status: upstream.status,
    headers,
  });
}
