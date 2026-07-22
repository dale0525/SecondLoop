export class EntitlementWorkerError extends Error {
  constructor(status, code, message, { headers = {} } = {}) {
    super(code);
    this.name = "EntitlementWorkerError";
    this.status = status;
    this.code = code;
    this.publicMessage = message;
    this.headers = headers;
  }
}

export function fail(status, code, message, options) {
  throw new EntitlementWorkerError(status, code, message, options);
}

export function errorResponse(error, requestId) {
  const known = error instanceof EntitlementWorkerError
    || (error && typeof error === "object" && Number.isInteger(error.status)
      && typeof error.code === "string" && typeof error.publicMessage === "string");
  const status = known ? error.status : 503;
  const code = known ? error.code : "entitlement_service_unavailable";
  const message = known ? error.publicMessage : "The entitlement service is temporarily unavailable.";
  return Response.json({ error: { code, message, requestId } }, {
    status,
    headers: {
      "cache-control": "no-store",
      ...(known ? error.headers : {}),
    },
  });
}
