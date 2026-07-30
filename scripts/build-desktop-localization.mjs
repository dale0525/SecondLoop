import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  PROJECT_ROOT,
  resolveConfinedPath,
  validateAgentApp,
} from "./scaffold-agent-app.mjs";

const HOST_CATALOG_ROOT = resolve(
  dirname(fileURLToPath(import.meta.url)),
  "../resources/i18n/host",
);
const HOST_LOCALES = [
  { id: "en", label: "English" },
  { id: "zh-CN", label: "简体中文" },
];

function readCatalog(path, label) {
  try {
    const document = JSON.parse(readFileSync(path, "utf8"));
    if (!document || Array.isArray(document) || typeof document !== "object") {
      throw new Error("catalog must be an object");
    }
    return document;
  } catch (error) {
    throw new Error(`${label} is invalid: ${error instanceof Error ? error.message : String(error)}`);
  }
}

function hostCatalog(locale) {
  const selected = HOST_LOCALES.find((entry) => entry.id.toLowerCase() === locale.toLowerCase())?.id
    ?? "en";
  return readCatalog(join(HOST_CATALOG_ROOT, `${selected}.json`), `host locale '${selected}'`);
}

export function buildDesktopLocalization(appRootInput = process.env.AGENTWEAVE_APP_ROOT) {
  const english = hostCatalog("en");
  if (!appRootInput) {
    return {
      defaultLocale: "en",
      locales: HOST_LOCALES.map((entry) => ({
        ...entry,
        messages: { ...english, ...hostCatalog(entry.id) },
      })),
    };
  }

  const appRoot = resolveConfinedPath(PROJECT_ROOT, appRootInput, "desktop Agent App root");
  const { app } = validateAgentApp(appRoot, {
    validateProject: false,
    validateRuntimeProviders: false,
  });
  if (!app.localization) {
    return {
      defaultLocale: "en",
      locales: HOST_LOCALES.map((entry) => ({
        ...entry,
        messages: { ...english, ...hostCatalog(entry.id) },
      })),
    };
  }
  return {
    defaultLocale: app.localization.defaultLocale,
    locales: app.localization.locales.map((entry) => ({
      id: entry.id,
      label: entry.label,
      messages: {
        ...english,
        ...hostCatalog(entry.id),
        ...readCatalog(
          resolveConfinedPath(appRoot, entry.resource, `App locale '${entry.id}'`),
          `App locale '${entry.id}'`,
        ),
      },
    })),
  };
}
