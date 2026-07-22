import { fail } from "./errors.js";

export function concat(...values) {
  const output = new Uint8Array(values.reduce((sum, value) => sum + value.byteLength, 0));
  let offset = 0;
  for (const value of values) {
    output.set(value, offset);
    offset += value.byteLength;
  }
  return output;
}

export function canonical(domain, fields, body) {
  return concat(new TextEncoder().encode(`${domain}\n${fields.join("\n")}\n`), body);
}

export function base64Url(bytes) {
  let binary = "";
  for (const value of new Uint8Array(bytes)) binary += String.fromCharCode(value);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

export function decodeBase64Url(value) {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]+$/.test(value)) throw new TypeError("invalid base64url");
  const normalized = value.replaceAll("-", "+").replaceAll("_", "/") + "=".repeat((4 - value.length % 4) % 4);
  const decoded = atob(normalized);
  return Uint8Array.from(decoded, (character) => character.charCodeAt(0));
}

export async function hmacKey(secret, cryptoImpl = globalThis.crypto) {
  if (typeof secret !== "string" || secret.length < 16 || secret.length > 4096) {
    throw new TypeError("invalid HMAC secret");
  }
  return cryptoImpl.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}

export async function hmacHex(secret, body, cryptoImpl = globalThis.crypto) {
  const signature = await cryptoImpl.subtle.sign("HMAC", await hmacKey(secret, cryptoImpl), body);
  return [...new Uint8Array(signature)].map((value) => value.toString(16).padStart(2, "0")).join("");
}

export async function sha256Hex(body, cryptoImpl = globalThis.crypto) {
  const digest = await cryptoImpl.subtle.digest("SHA-256", body);
  return [...new Uint8Array(digest)].map((value) => value.toString(16).padStart(2, "0")).join("");
}

export async function subjectRef(config, identity, secret, cryptoImpl = globalThis.crypto) {
  const values = [
    config.appId,
    identity.providerId,
    identity.issuer,
    identity.tenant,
    identity.subject,
  ];
  if (values.some((value) => typeof value !== "string" || value === "" || value.length > 2048)) {
    fail(401, "authentication_failed", "A valid user identity is required.");
  }
  const body = new TextEncoder().encode(values.map((value) => `${value.length}:${value}`).join("|"));
  const signature = await cryptoImpl.subtle.sign("HMAC", await hmacKey(secret, cryptoImpl), body);
  return `v1_${base64Url(signature)}`;
}

export async function boundedRequestBody(request, maximum) {
  const declared = Number(request.headers.get("content-length"));
  if (Number.isFinite(declared) && declared > maximum) {
    fail(413, "request_too_large", "The request is too large.");
  }
  const body = new Uint8Array(await request.arrayBuffer());
  if (body.byteLength === 0 || body.byteLength > maximum) {
    fail(body.byteLength === 0 ? 400 : 413, "invalid_request", "The request body is invalid.");
  }
  return body;
}
