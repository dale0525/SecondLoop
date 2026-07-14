# Desktop Sidecar Supervisor

## Status and scope

This document defines the Electron-owned lifecycle for the local AgentWeave Rust sidecar. It covers process discovery, startup, health readiness, logging, crash recovery, shutdown, and the minimum Renderer recovery control.

Managed Electron launches use a dynamic authenticated loopback endpoint. The fixed loopback URL remains available only to the explicit browser-development workflow and is not a production security boundary.

## Trust boundaries

- Electron Main is the lifecycle and transport authority. It chooses the executable, arguments, working directory, environment, data directories, launch pipes, endpoint, and per-launch credential.
- Preload exposes status, `ensureRunning()`, and a closed set of typed product operations. Renderer cannot provide an executable, argument, environment variable, path, endpoint, HTTP header, credential, signal, or process identifier.
- The Rust sidecar remains the authority for Agent App resolution, Runtime policy, credentials, storage, approvals, and external side effects.
- Health readiness requires a launch result bound to the expected launch UUID and child PID, followed by an authenticated request while that child generation remains current. It does not replace Host bootstrap validation.
- An externally managed server URL is supported for explicit development and integration use, but Electron does not claim ownership of that process and cannot restart or terminate it. Plain HTTP external URLs are restricted to loopback hosts. Non-loopback endpoints require HTTPS and a valid `AGENTWEAVE_SERVER_TOKEN`.

## Launch modes

| Mode | Source | Lifecycle behavior |
| --- | --- | --- |
| `managed` | Explicit `AGENTWEAVE_SIDECAR_EXECUTABLE`, packaged resource, or existing development binary | Electron starts, monitors, restarts, and stops the child |
| `external` | Explicit loopback HTTP or authenticated HTTPS `AGENTWEAVE_SERVER_URL` | Electron uses the endpoint but never signals the process |
| `unavailable` | No safe executable or external endpoint can be resolved | Optional Runtime surfaces fail closed and recovery remains unavailable |

An explicit external endpoint takes precedence over process discovery. This keeps the existing development workflow usable while preventing two sidecars from competing for the same endpoint.
An invalid explicit URL or executable fails closed instead of silently selecting a different launch mode.

## Lifecycle states

The public status schema is versioned independently from the internal implementation. It exposes only bounded operational facts:

```text
idle -> starting -> ready -> stopping -> stopped
          |          |
          v          v
        failed     crashed -> starting
                         \-> circuit_open
```

- `idle`: a managed executable was resolved but no launch has started.
- `starting`: one child is being spawned or is waiting for health readiness.
- `ready`: the current child passed health readiness.
- `stopping`: Electron requested an orderly shutdown and is waiting for exit.
- `stopped`: the owned child exited after an explicit stop.
- `failed`: spawn or startup readiness failed.
- `crashed`: a ready child exited unexpectedly and restart evaluation is in progress.
- `circuit_open`: too many unexpected exits occurred inside the restart window.
- `external`: the configured endpoint is not owned by Electron; its process state is not inferred.
- `unavailable`: no launch target exists.

Status never contains the executable path, command line, environment, database path, endpoint credentials, stdout, stderr, or raw exception text.

## Startup protocol

1. Resolve one launch mode in Electron Main. Renderer input is not consulted.
2. Bind the sidecar data, cache, database, and workspace roots under Electron `userData`, ignoring inherited root overrides, and create directories with owner-only permissions where the platform supports them.
3. Build a bounded child environment from explicit `AGENTWEAVE_*` configuration and a small operating-system allowlist. Unrelated host credentials are not inherited.
4. Create a launch UUID and 256-bit transport credential, spawn one non-detached child, and pass the launch document through an inherited host-to-child pipe. The credential never enters argv, environment values, URLs, Renderer state, or logs.
5. Read one bounded child-to-host launch result. Require schema version 1, the exact launch UUID and child PID, and a dynamic `127.0.0.1` HTTP origin.
6. Poll `/health` through the authenticated Main-process transport until it succeeds or the startup deadline expires.
7. Treat the child as `ready` only if it remains the current owned generation when authenticated health succeeds. Business, bootstrap, notification, Owner, and Approver requests use the same private transport.
8. If the child exits, emits a process error, returns an invalid handshake, or misses the startup deadline, clear the credential, terminate that generation, and publish a bounded failure state.
9. Resolve trusted App discovery separately through the Host bootstrap contract. Health success alone never opens optional Renderer routes.

Concurrent `start()` or `ensureRunning()` calls share one in-flight operation and cannot create duplicate children.

## Crash recovery and circuit breaker

Unexpected exits are tracked in a rolling restart window. A bounded backoff precedes automatic restart. When the configured crash limit is reached, the supervisor enters `circuit_open` and stops launching children automatically.

`ensureRunning()` is the only Renderer-reachable recovery action. Electron ignores it while the child is ready or already starting. From `failed`, `stopped`, or `circuit_open`, it clears only the automatic crash history and attempts one new managed launch. It never changes executable, endpoint, arguments, environment, or paths.

## Shutdown protocol

Electron application shutdown is gated on supervisor cleanup:

1. Mark the current generation as explicitly stopping so its exit cannot trigger restart.
2. Send `SIGTERM` to the owned child.
3. Wait for bounded graceful exit.
4. Send `SIGKILL` if the child does not exit before the deadline.
5. Resolve cleanup only after the exit event or the forced-shutdown deadline.

Electron never signals an external-mode process. Repeated cleanup calls share the same operation and remain safe during window close and application quit races.

## Logging and privacy

Child output is line-buffered, length-bounded, and sanitized before entering Electron logs. Sanitization removes bearer credentials, secret-shaped JSON or key-value fields, email addresses, and long token-like values. Partial trailing lines and oversized output are bounded. The supervisor never persists mail bodies or raw child output itself.

Sanitization is defense in depth. The sidecar must continue to avoid logging secrets and private content at the source.

## Acceptance behavior

- Starting twice creates one child.
- Startup becomes ready only after health succeeds for the current child.
- Managed launches use a different dynamic endpoint and credential after every restart.
- Unauthenticated, cross-generation, and Renderer-originated raw requests cannot use the managed sidecar.
- Spawn failures, startup timeouts, and pre-readiness exits fail deterministically.
- Explicit stop does not restart the child and escalates to forced termination when required.
- Unexpected exits restart with bounded backoff and open the circuit at the configured limit.
- Renderer recovery cannot mutate launch configuration.
- Sandboxed preload bundles are self-contained and cannot depend on local CommonJS chunks.
- Renderer and preload bundles contain no sidecar endpoint, transport header, or Owner/Approver credential lookup.
- External mode is never killed or restarted by Electron.
- Sidecar output is bounded and sanitized before logging.
- Closing Electron does not leave an owned child running.
