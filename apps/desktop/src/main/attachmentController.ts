import { randomUUID } from "node:crypto";
import path from "node:path";

import {
  ATTACHMENT_PICK_IMPORT_CHANNEL,
  parseAttachmentMetadata,
  type AttachmentMetadata,
} from "../shared/attachments";
import type { SidecarRequest } from "./sidecarSupervisor";

const MAX_ATTACHMENT_BYTES = 16 * 1024 * 1024;
const MAX_RESPONSE_BYTES = 64 * 1024;

type IpcEvent = { sender: { id: number } };

type IpcMainLike = {
  handle(channel: string, handler: (event: IpcEvent) => unknown): void;
  removeHandler(channel: string): void;
};

export function registerAttachmentController(options: {
  ipcMain: IpcMainLike;
  pickFile: () => Promise<string | null>;
  readFile: (filePath: string) => Promise<Uint8Array>;
  requesterWebContents: { id: number };
  sidecarRequest: SidecarRequest;
  uuid?: () => string;
}): () => void {
  options.ipcMain.handle(ATTACHMENT_PICK_IMPORT_CHANNEL, async (event) => {
    if (event.sender.id !== options.requesterWebContents.id) {
      throw new Error("Attachment import is restricted to the requester window");
    }
    let selectedPath: string | null;
    try {
      selectedPath = await options.pickFile();
    } catch {
      throw new Error("Attachment selection failed");
    }
    if (!selectedPath) return null;

    let content: Uint8Array;
    try {
      content = await options.readFile(selectedPath);
    } catch {
      throw new Error("Selected attachment could not be read");
    }
    if (content.byteLength > MAX_ATTACHMENT_BYTES) {
      throw new Error("Selected attachment exceeds the 16 MiB limit");
    }

    const fileName = path.basename(selectedPath);
    const mimeType = mimeTypeForFileName(fileName);
    const response = await options.sidecarRequest(
      `/foundation/attachments?${new URLSearchParams({ fileName })}`,
      {
        body: Uint8Array.from(content).buffer,
        headers: {
          "Content-Type": mimeType,
          "Idempotency-Key": `desktop-import-${(options.uuid ?? randomUUID)()}`,
        },
        method: "POST",
      },
    );
    return readMetadataResponse(response);
  });
  return () => options.ipcMain.removeHandler(ATTACHMENT_PICK_IMPORT_CHANNEL);
}

async function readMetadataResponse(response: Response): Promise<AttachmentMetadata> {
  const declaredLength = Number(response.headers.get("content-length"));
  if (Number.isFinite(declaredLength) && declaredLength > MAX_RESPONSE_BYTES) {
    throw new Error("Attachment response is too large");
  }
  const text = await response.text();
  if (new TextEncoder().encode(text).byteLength > MAX_RESPONSE_BYTES) {
    throw new Error("Attachment response is too large");
  }
  let value: unknown;
  try {
    value = text ? JSON.parse(text) : {};
  } catch {
    throw new Error("Attachment response is invalid");
  }
  if (!response.ok) {
    throw new Error(
      isRecord(value) && typeof value.error === "string"
        ? value.error.slice(0, 1_024)
        : `AgentWeave server returned HTTP ${response.status}`,
    );
  }
  return parseAttachmentMetadata(value);
}

function mimeTypeForFileName(fileName: string): string {
  switch (path.extname(fileName).toLowerCase()) {
    case ".csv": return "text/csv";
    case ".gif": return "image/gif";
    case ".htm":
    case ".html": return "text/html";
    case ".jpeg":
    case ".jpg": return "image/jpeg";
    case ".json": return "application/json";
    case ".md": return "text/markdown";
    case ".pdf": return "application/pdf";
    case ".png": return "image/png";
    case ".txt": return "text/plain";
    case ".webp": return "image/webp";
    default: return "application/octet-stream";
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
