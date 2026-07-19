export class GatewayError extends Error {
  constructor(status, code, publicMessage, options = {}) {
    super(code, options);
    this.name = "GatewayError";
    this.status = status;
    this.code = code;
    this.publicMessage = publicMessage;
    this.headers = options.headers ?? {};
    this.dispatchOutcome = options.dispatchOutcome ?? null;
  }
}

export function fail(status, code, publicMessage, options) {
  throw new GatewayError(status, code, publicMessage, options);
}

export function errorResponse(error, requestId) {
  const known = error instanceof GatewayError;
  const status = known ? error.status : 500;
  const code = known ? error.code : "internal_error";
  const message = known ? error.publicMessage : "The gateway could not complete the request.";
  const headers = new Headers({
    "cache-control": "no-store",
    "content-type": "application/json; charset=utf-8",
    "x-request-id": requestId,
    "x-content-type-options": "nosniff",
    ...known ? error.headers : {},
  });
  return new Response(JSON.stringify({
    error: {
      code,
      message,
      request_id: requestId,
    },
  }), { status, headers });
}

export function safeErrorCode(error) {
  return error instanceof GatewayError ? error.code : "internal_error";
}
