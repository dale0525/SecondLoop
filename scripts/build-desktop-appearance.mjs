import {
  existsSync,
  lstatSync,
  readFileSync,
  readdirSync,
  statSync,
} from "node:fs";
import { basename, dirname, extname, join, relative, resolve } from "node:path";

import {
  PROJECT_ROOT,
  resolveConfinedPath,
  validateAgentApp,
} from "./scaffold-agent-app.mjs";
import {
  VSCODE_THEME_CATALOG,
  mergeVsCodeTheme,
  parseJsonc,
  validateVsCodeThemeDocument,
} from "./vscode-theme.mjs";

const DEFAULT_THEME_ID = VSCODE_THEME_CATALOG.defaultTheme;
const FONT_FILE_PATTERN = /^(ui|display|mono)(?:-(100|200|300|400|500|600|700|800|900))?(?:-(italic))?\.(woff2|woff|ttf|otf)$/i;
const MAX_FONT_FILES = 24;
const MAX_FONT_FILE_BYTES = 8 * 1024 * 1024;
const MAX_TOTAL_FONT_BYTES = 32 * 1024 * 1024;

export function buildDesktopAppearance(appRootInput = process.env.AGENTWEAVE_APP_ROOT) {
  if (!appRootInput) {
    return {
      defaultTheme: DEFAULT_THEME_ID,
      fontFaces: [],
      themes: VSCODE_THEME_CATALOG.themes.map((theme) => ({ ...theme, sourceKind: "builtin" })),
    };
  }

  const appRoot = resolveConfinedPath(PROJECT_ROOT, appRootInput, "desktop Agent App root");
  const { app } = validateAgentApp(appRoot, {
    validateProject: false,
    validateRuntimeProviders: false,
  });
  const appearance = app.appearance ?? defaultAppearance();
  const catalogById = new Map(VSCODE_THEME_CATALOG.themes.map((theme) => [theme.id, theme]));
  const builtinThemes = appearance.themes.builtins.map((id) => ({
    ...catalogById.get(id),
    sourceKind: "builtin",
  }));
  const customThemes = appearance.themes.custom.map((entry) => {
    const theme = loadCustomTheme(appRoot, entry.path);
    return {
      colors: theme.colors ?? {},
      id: entry.id,
      label: entry.label ?? theme.name ?? basename(entry.path, extname(entry.path)),
      source: entry.path,
      sourceKind: "custom",
      type: normalizeThemeType(theme.type, theme.colors?.["editor.background"]),
    };
  });

  return {
    defaultTheme: appearance.defaultTheme,
    fontFaces: loadFontFaces(appRoot),
    themes: [...builtinThemes, ...customThemes],
  };
}

function defaultAppearance() {
  return {
    defaultTheme: DEFAULT_THEME_ID,
    themes: {
      builtins: VSCODE_THEME_CATALOG.themes.map((theme) => theme.id),
      custom: [],
    },
  };
}

function loadCustomTheme(appRoot, relativePath, stack = []) {
  if (stack.length >= 8) throw new Error(`VS Code theme include depth exceeds 8 at '${relativePath}'`);
  const themePath = resolveConfinedPath(appRoot, relativePath, "VS Code theme path");
  if (stack.includes(themePath)) throw new Error(`VS Code theme include cycle at '${relativePath}'`);
  const document = validateVsCodeThemeDocument(
    parseJsonc(readFileSync(themePath, "utf8"), `VS Code theme '${relativePath}'`),
    `VS Code theme '${relativePath}'`,
  );
  if (!document.include) return document;
  const included = resolve(dirname(themePath), document.include);
  const includedRelative = relative(appRoot, included).split("\\").join("/");
  const base = loadCustomTheme(appRoot, includedRelative, [...stack, themePath]);
  return mergeVsCodeTheme(base, document);
}

function loadFontFaces(appRoot) {
  const fontsRoot = join(appRoot, "fonts");
  if (!existsSync(fontsRoot)) return [];
  if (!statSync(fontsRoot).isDirectory() || lstatSync(fontsRoot).isSymbolicLink()) {
    throw new Error("Agent App fonts must be a real directory");
  }
  const files = readdirSync(fontsRoot, { withFileTypes: true })
    .filter((entry) => entry.isFile() && entry.name.toLowerCase() !== "readme.md")
    .sort((left, right) => left.name.localeCompare(right.name));
  if (files.length > MAX_FONT_FILES) throw new Error(`Agent App fonts exceed ${MAX_FONT_FILES} files`);

  let totalBytes = 0;
  return files.map((entry) => {
    const match = FONT_FILE_PATTERN.exec(entry.name);
    if (!match) throw new Error(`Agent App font '${entry.name}' does not follow the font slot convention`);
    const path = resolveConfinedPath(fontsRoot, entry.name, `Agent App font '${entry.name}'`);
    const bytes = readFileSync(path);
    if (bytes.length === 0 || bytes.length > MAX_FONT_FILE_BYTES) {
      throw new Error(`Agent App font '${entry.name}' must be between 1 byte and ${MAX_FONT_FILE_BYTES} bytes`);
    }
    totalBytes += bytes.length;
    if (totalBytes > MAX_TOTAL_FONT_BYTES) throw new Error("Agent App fonts exceed the 32 MiB total limit");
    const extension = match[4].toLowerCase();
    return {
      dataUrl: `data:${fontMimeType(extension)};base64,${bytes.toString("base64")}`,
      format: fontFormat(extension),
      slot: match[1].toLowerCase(),
      style: match[3] ? "italic" : "normal",
      weight: match[2] ?? "400",
    };
  });
}

function normalizeThemeType(type, background) {
  if (["dark", "light", "hcDark", "hcLight"].includes(type)) return type;
  if (typeof background !== "string") return "dark";
  const hex = background.match(/^#([0-9a-f]{6})/i)?.[1];
  if (!hex) return "dark";
  const channels = [0, 2, 4].map((offset) => Number.parseInt(hex.slice(offset, offset + 2), 16));
  const luminance = (channels[0] * 299 + channels[1] * 587 + channels[2] * 114) / 1000;
  return luminance >= 150 ? "light" : "dark";
}

function fontMimeType(extension) {
  if (extension === "woff2") return "font/woff2";
  if (extension === "woff") return "font/woff";
  if (extension === "ttf") return "font/ttf";
  return "font/otf";
}

function fontFormat(extension) {
  if (extension === "ttf") return "truetype";
  if (extension === "otf") return "opentype";
  return extension;
}
