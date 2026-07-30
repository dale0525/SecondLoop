const FIREBASE_IDENTITY_PROVIDER_ID = "agentweave.identity.firebase";

export function validateKnownProviderPublicConfig(providerId, publicConfig, label) {
  if (providerId !== FIREBASE_IDENTITY_PROVIDER_ID) return publicConfig;
  requireOnlyKeys(
    publicConfig,
    ["projectId", "firebaseWebKey", "webApplicationId", "authDomain"],
    label,
  );
  requireFields(publicConfig, ["projectId", "firebaseWebKey", "webApplicationId"], label);
  requireString(publicConfig.projectId, `${label}.projectId`, 30);
  if (!/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/.test(publicConfig.projectId)) {
    throw new Error(`${label}.projectId must be a valid Firebase project ID`);
  }
  requireString(publicConfig.firebaseWebKey, `${label}.firebaseWebKey`, 2048);
  requireString(publicConfig.webApplicationId, `${label}.webApplicationId`, 2048);
  if (publicConfig.authDomain !== undefined && publicConfig.authDomain !== null) {
    requireString(publicConfig.authDomain, `${label}.authDomain`, 2048);
    if (!publicConfig.authDomain.split(".").every((domainLabel) => (
      /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$/.test(domainLabel)
    ))) {
      throw new Error(`${label}.authDomain must be a valid Firebase authentication domain`);
    }
  }
  return publicConfig;
}

function requireOnlyKeys(value, allowed, label) {
  const allowedKeys = new Set(allowed);
  for (const key of Object.keys(value)) {
    if (!allowedKeys.has(key)) throw new Error(`${label} contains unknown field '${key}'`);
  }
}

function requireFields(value, required, label) {
  for (const field of required) {
    if (!Object.hasOwn(value, field)) throw new Error(`${label}.${field} is required`);
  }
}

function requireString(value, label, maxBytes) {
  if (
    typeof value !== "string"
    || value.trim() === ""
    || value !== value.trim()
    || /\p{Cc}/u.test(value)
    || Buffer.byteLength(value, "utf8") > maxBytes
  ) {
    throw new Error(`${label} must be a non-empty bounded string without control characters`);
  }
}
