# Local Sidecar Transport

AgentWeave supports an authenticated, process-scoped transport for a desktop host that launches `agent-server` as a child process. The contract is opt-in in this release so existing browser-based development remains compatible.

## Security boundary

- The host creates a fresh launch identifier and a cryptographically random transport credential for every child process.
- The credential is sent through an inherited pipe. It must not appear in command-line arguments, environment values, URLs, renderer state, or logs.
- The server binds to an ephemeral port on `127.0.0.1` and reports only its schema version, launch identifier, process identifier, and origin through a second inherited pipe.
- Every HTTP route, including health and development routes, requires the `X-AgentWeave-Transport` header. Rejections use a generic `401` response.
- Authenticated mode does not enable CORS. A desktop renderer must call the sidecar through trusted Main-process IPC instead of receiving the origin or credential.
- Transport authentication and Owner/Approver authorization are separate layers. An Owner API request can require both `X-AgentWeave-Transport` and its existing `Authorization: Bearer ...` credential.

The current inherited-pipe implementation is available on Unix platforms. Supplying the opt-in descriptor variables on another platform fails closed.

## Launch contract

The launcher allocates two child file descriptors and sets their decimal descriptor numbers in:

```text
AGENTWEAVE_LAUNCH_CONFIG_FD
AGENTWEAVE_LAUNCH_RESULT_FD
```

The first descriptor is host-to-child. The host writes one bounded JSON document and closes the pipe:

```json
{
  "schemaVersion": 1,
  "launchId": "7f21b128-918e-4b03-91f9-14a95c842ee4",
  "transportToken": "a-base64url-credential-with-at-least-256-bits-of-entropy"
}
```

The input is limited to 4096 bytes, rejects unknown fields, requires a canonical UUID, and accepts only a 43-to-128-character base64url-compatible credential.

The second descriptor is child-to-host. After binding the listener, the sidecar writes one newline-terminated JSON document and closes the pipe:

```json
{
  "schemaVersion": 1,
  "launchId": "7f21b128-918e-4b03-91f9-14a95c842ee4",
  "pid": 18442,
  "origin": "http://127.0.0.1:53119"
}
```

The launch result never contains the transport credential. The host must validate every field, match the launch and process identifiers, require loopback HTTP with an ephemeral port, and perform an authenticated health check before declaring the sidecar ready.

## Electron integration

Managed Electron launches always use this contract. Main owns the launch pipes, validated origin, credential, health check, and all HTTP requests. The regular and approval Preloads expose closed typed operations over requester-bound IPC; neither Preload accepts a raw URL, path, method, header, or credential from Renderer.

Session, Foundation, development, Host bootstrap, model, notification, Owner, and Approver traffic all travels through Main. The transport header is added after Renderer-controlled data has been removed. Owner and Approver calls add their separate Bearer authorization in Main, so possession of one authorization layer cannot replace the other.

Every crash restart creates a new launch UUID, endpoint, and credential. The prior credential buffer is cleared when its child generation stops being authoritative. Public sidecar status never includes any of these private transport details.

## Development compatibility

When neither descriptor variable is present, `agent-server` keeps the explicit development behavior and listens without transport authentication on `127.0.0.1:49321`. Supplying only one descriptor variable, invalid descriptors, or an invalid launch document aborts startup.

The fixed unauthenticated port is a development compatibility mode, not a production desktop transport. A managed Electron launch must use the authenticated contract. Run the dual-instance acceptance check with:

```bash
pixi run sidecar-transport-check
```

Browser development reaches the fixed port only through the Vite development proxy. Explicit Electron external mode uses `AGENTWEAVE_SERVER_URL`; non-loopback URLs require HTTPS and a base64url-compatible `AGENTWEAVE_SERVER_TOKEN`. External mode never grants Electron ownership of that server process.
