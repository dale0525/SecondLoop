import assert from "node:assert/strict";
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { extname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const siteRoot = fileURLToPath(new URL("..", import.meta.url));
const distRoot = join(siteRoot, "dist");
const routes = [
  ["index.html", "lang=\"en\"", "Build the agent app."],
  ["privacy/index.html", "lang=\"en\"", "Google API Services User Data Policy"],
  ["terms/index.html", "lang=\"en\"", "Terms of service"],
  ["oauth-help/index.html", "lang=\"en\"", "https://www.googleapis.com/auth/cloud-platform"],
  ["zh/index.html", "lang=\"zh-CN\"", "构建你的 Agent App"],
  ["zh/privacy/index.html", "lang=\"zh-CN\"", "Google API Services User Data Policy"],
  ["zh/terms/index.html", "lang=\"zh-CN\"", "服务条款"],
  ["zh/oauth-help/index.html", "lang=\"zh-CN\"", "开发者工具 → 补充必要信息 → 用户登录"],
];

assert.ok(existsSync(distRoot), "site/dist must exist before verification");

for (const [route, language, requiredCopy] of routes) {
  const path = join(distRoot, route);
  assert.ok(existsSync(path), `missing built route: ${route}`);
  const html = readFileSync(path, "utf8");
  assert.match(html, /<h1[\s>]/, `${route} must contain a primary heading`);
  assert.ok(html.includes(language), `${route} must declare ${language}`);
  assert.ok(html.includes(requiredCopy), `${route} is missing required copy`);
  assert.match(html, /rel="canonical"/, `${route} must expose a canonical URL`);
  assert.doesNotMatch(html, /fonts\.googleapis\.com|google-analytics\.com|googletagmanager\.com/i);
  assert.doesNotMatch(html, /<(script|img)[^>]+(?:src)="https?:\/\//i, `${route} must not load remote scripts or images`);
}

const privacy = readFileSync(join(distRoot, "privacy/index.html"), "utf8");
assert.ok(privacy.includes("Limited Use requirements"));
assert.ok(privacy.includes("not uploaded to a SecondLoop-operated credential service"));

const oauthHelp = readFileSync(join(distRoot, "oauth-help/index.html"), "utf8");
assert.ok(oauthHelp.includes("S256 PKCE"));
assert.ok(oauthHelp.includes("127.0.0.1"));
assert.ok(oauthHelp.includes("https://www.googleapis.com/auth/firebase"));

for (const publicFile of ["_headers", "favicon.svg", "robots.txt", "sitemap.xml"]) {
  assert.ok(existsSync(join(distRoot, publicFile)), `missing public artifact: ${publicFile}`);
}

const headers = readFileSync(join(distRoot, "_headers"), "utf8");
assert.ok(headers.includes("Content-Security-Policy"));
assert.ok(headers.includes("frame-ancestors 'none'"));

const codeExtensions = new Set([".astro", ".css", ".js", ".mjs", ".ts", ".tsx"]);
const oversized = [];

function scan(directory) {
  for (const entry of readdirSync(directory)) {
    if (["dist", "node_modules", ".astro"].includes(entry)) continue;
    const path = join(directory, entry);
    const stat = statSync(path);
    if (stat.isDirectory()) {
      scan(path);
      continue;
    }
    if (!codeExtensions.has(extname(path))) continue;
    const lines = readFileSync(path, "utf8").split(/\r?\n/).length;
    if (lines > 1000) oversized.push(`${relative(siteRoot, path)}:${lines}`);
  }
}

scan(siteRoot);
assert.deepEqual(oversized, [], `code-like files exceed 1,000 lines: ${oversized.join(", ")}`);

console.log(`verified ${routes.length} static AgentWeave routes`);
