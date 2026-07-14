export const ATTACHMENT_PICK_IMPORT_CHANNEL = "agentweave:attachments:pick-import";

export type AttachmentMetadata = Readonly<{
  id: string;
  fileName: string;
  mimeType: string;
  sizeBytes: number;
  sha256: string;
  createdAt: string;
}>;

export function parseAttachmentMetadata(value: unknown): AttachmentMetadata {
  if (!isRecord(value)) throw new Error("Attachment metadata is invalid");
  const keys = ["createdAt", "fileName", "id", "mimeType", "sha256", "sizeBytes"];
  if (Object.keys(value).some((key) => !keys.includes(key))) {
    throw new Error("Attachment metadata contains unknown fields");
  }
  if (
    typeof value.id !== "string"
    || !/^[0-9a-f-]{36}$/i.test(value.id)
    || typeof value.fileName !== "string"
    || value.fileName.length === 0
    || value.fileName.length > 255
    || typeof value.mimeType !== "string"
    || value.mimeType.length === 0
    || value.mimeType.length > 255
    || !Number.isSafeInteger(value.sizeBytes)
    || (value.sizeBytes as number) < 0
    || typeof value.sha256 !== "string"
    || !/^[0-9a-f]{64}$/.test(value.sha256)
    || typeof value.createdAt !== "string"
    || !Number.isFinite(Date.parse(value.createdAt))
  ) {
    throw new Error("Attachment metadata is invalid");
  }
  return Object.freeze({
    id: value.id,
    fileName: value.fileName,
    mimeType: value.mimeType,
    sizeBytes: value.sizeBytes as number,
    sha256: value.sha256,
    createdAt: value.createdAt,
  });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
