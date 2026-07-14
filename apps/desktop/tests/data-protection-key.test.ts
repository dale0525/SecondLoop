// @vitest-environment node

import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it } from "vitest";

import { loadOrCreateDataProtectionKey } from "../src/main/dataProtectionKey";

const roots: string[] = [];

afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { force: true, recursive: true });
});

describe("desktop data protection key", () => {
  it("persists only an operating-system-encrypted 32-byte key", () => {
    const root = temporaryRoot();
    const storagePath = path.join(root, "data-protection-key.v1.json");
    const expected = Buffer.alloc(32, 7);
    const safeStorage = {
      decryptString: (value: Buffer) => value.toString("utf8").slice(4),
      encryptString: (value: string) => Buffer.from(`enc:${value}`),
      isEncryptionAvailable: () => true,
    };

    expect(loadOrCreateDataProtectionKey({
      randomKey: () => Buffer.from(expected),
      safeStorage,
      storagePath,
    })?.key).toEqual(expected);
    expect(loadOrCreateDataProtectionKey({ safeStorage, storagePath })?.key).toEqual(expected);
    const stored = readFileSync(storagePath, "utf8");
    expect(stored).not.toContain(expected.toString("hex"));
    expect(stored).not.toContain(expected.toString("base64"));
  });

  it("disables backup encryption when operating-system encryption is unavailable", () => {
    const storagePath = path.join(temporaryRoot(), "key.json");
    expect(loadOrCreateDataProtectionKey({
      safeStorage: {
        decryptString: () => "",
        encryptString: () => Buffer.alloc(0),
        isEncryptionAvailable: () => false,
      },
      storagePath,
    })).toBeNull();
  });

  it("fails closed for malformed stored key material", () => {
    const storagePath = path.join(temporaryRoot(), "key.json");
    writeFileSync(storagePath, JSON.stringify({ schemaVersion: 1, encryptedKey: "bad" }));
    expect(() => loadOrCreateDataProtectionKey({
      safeStorage: {
        decryptString: () => "not-base64",
        encryptString: () => Buffer.alloc(0),
        isEncryptionAvailable: () => true,
      },
      storagePath,
    })).toThrow(/invalid/);
  });
});

function temporaryRoot(): string {
  const root = mkdtempSync(path.join(tmpdir(), "agentweave-data-protection-"));
  roots.push(root);
  return root;
}
