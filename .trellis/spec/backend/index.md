# Dart Core And Runtime Client Guidelines

This project is a Flutter/Dart app. There are no server route handlers in this
open-source repository. Treat this directory as guidance for the app's core
service layer, local backend abstraction, HTTP clients, persistence adapters,
logging, and tests.

## Guides

| Guide | Scope |
|-------|-------|
| [Directory Structure](./directory-structure.md) | `lib/core`, `lib/web_app`, service/client boundaries, and where new core code belongs |
| [API Clients And Auth](./api-client-guidelines.md) | Client-side HTTP path construction, bearer tokens, and request contracts visible in this repo |
| [Persistence Guidelines](./database-guidelines.md) | Local stores, caches, preferences, and current non-ORM persistence patterns |
| [Error Handling](./error-handling.md) | Exceptions, HTTP failures, response parsing, and UI error surfacing |
| [Logging Guidelines](./logging-guidelines.md) | Structured persisted event logs and best-effort debug diagnostics |
| [Quality Guidelines](./quality-guidelines.md) | Verification commands, tests, privacy boundaries, and product-doc alignment |

Keep these specs source-backed. Do not document private backend implementation
details, infrastructure, logs, secrets, or repository paths here.
