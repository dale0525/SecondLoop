# Document and Attachment Host v1

## Trusted attachment ingress

The Host owns file selection and byte import. A Renderer or model may request selection, but it never supplies a local path and never receives an absolute path in the result.

Each imported attachment has an immutable stable ID, file name, MIME type, byte size, SHA-256 hash, and creation time. The Host injects App, tenant, and user scope; these scope fields are not model or Renderer arguments.

An attachment is limited to 16 MiB. Reusing an idempotency key with identical metadata and bytes returns the original attachment. Reusing it with different input fails with a conflict.

Desktop import uses the operating-system file picker in Electron Main. Electron Main reads the selected bytes and imports them through the authenticated sidecar transport. Preload returns metadata only. Server Hosts may import raw request bytes through an equivalently authenticated transport.

## Bounded and untrusted reads

Attachment content is always untrusted, including PDFs, office files, images, Markdown, HTML, email exports, and plain text. Content cannot change system instructions, permissions, approval requirements, recipients, resource targets, or tool arguments.

The model can list metadata, get metadata, read a base64 chunk, or request deletion. A chunk is limited to 256 KiB and identifies its offset, next offset, and whether more bytes remain. Import is deliberately not a model tool.

The Host never executes macros or active content. Parsing, conversion, rendering, malware handling, process isolation, and temporary-file cleanup remain Host responsibilities.

## API and failures

Authenticated Hosts expose list, raw-byte import, metadata read, content read, and delete operations under `/foundation/attachments`. Invalid metadata or offsets fail as `400`, a missing or out-of-scope attachment fails as `404`, an idempotency conflict fails as `409`, and an oversized import fails as `413`.

Deletion removes the scoped bytes and the associated idempotency record. Repeated deletion reports the attachment as missing. An attachment ID cannot be used to cross App, tenant, or user scope.

## Derived document artifacts

Document extraction and conversion create a new artifact by default. Every derived artifact preserves its source attachment IDs, content hashes, revision, creation time, verification state, and verification notes.

Layout-sensitive formats require rendering and visual verification. A failed check leaves the artifact unverified and records concise issues such as clipping, overflow, missing fonts, broken pagination, or unreadable charts.

Explicit source deletion is a destructive operation. Creating a derived artifact does not automatically delete its source attachment.
