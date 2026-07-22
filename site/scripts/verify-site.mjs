import assert from "node:assert/strict";
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { extname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const siteRoot = fileURLToPath(new URL("..", import.meta.url));
const distRoot = join(siteRoot, "dist");
const routes = [
  ["index.html", "lang=\"en\"", "AgentWeave is an open-source"],
  ["privacy/index.html", "lang=\"en\"", "Google API Services User Data Policy"],
  ["terms/index.html", "lang=\"en\"", "Terms of service"],
  ["oauth-help/index.html", "lang=\"en\"", "https://www.googleapis.com/auth/cloud-platform"],
  ["zh/index.html", "lang=\"zh-CN\"", "AgentWeave 是开源的"],
  ["zh/privacy/index.html", "lang=\"zh-CN\"", "Google API Services User Data Policy"],
  ["zh/terms/index.html", "lang=\"zh-CN\"", "服务条款"],
  ["zh/oauth-help/index.html", "lang=\"zh-CN\"", "开发者工具 → 补充必要信息 → 用户登录"],
];
const remoteResourcePattern = /<(?:script|img)\b[^>]*\bsrc="https?:\/\/[^\"]*"[^>]*>|<link\b(?=[^>]*\brel="(?:stylesheet|preload|modulepreload)")(?=[^>]*\bhref="https?:\/\/)[^>]*>/i;

assert.match('<link rel="stylesheet" href="https://example.com/app.css">', remoteResourcePattern);
assert.match('<link href="https://example.com/app.css" rel="preload" as="style">', remoteResourcePattern);

assert.ok(existsSync(distRoot), "site/dist must exist before verification");

for (const [route, language, requiredCopy] of routes) {
  const path = join(distRoot, route);
  assert.ok(existsSync(path), `missing built route: ${route}`);
  const html = readFileSync(path, "utf8");
  assert.match(html, /<h1[\s>]/, `${route} must contain a primary heading`);
  assert.ok(html.includes(language), `${route} must declare ${language}`);
  assert.ok(html.includes(requiredCopy), `${route} is missing required copy`);
  assert.ok(!html.includes("AgentWeave Developer Tools by SecondLoop"), `${route} uses the retired OAuth application name`);
  assert.match(html, /rel="canonical"/, `${route} must expose a canonical URL`);
  assert.ok(html.includes('property="og:image" content="https://agentweave.secondloop.app/favicon.svg"'), `${route} must expose an Open Graph image`);
  assert.ok(html.includes('name="twitter:image" content="https://agentweave.secondloop.app/favicon.svg"'), `${route} must expose a Twitter image`);
  assert.doesNotMatch(html, /fonts\.googleapis\.com|google-analytics\.com|googletagmanager\.com/i);
  assert.doesNotMatch(html, remoteResourcePattern, `${route} must not load remote scripts, images, or stylesheets`);
}

const privacy = readFileSync(join(distRoot, "privacy/index.html"), "utf8");
assert.ok(privacy.includes("Limited Use requirements"));
assert.ok(privacy.includes("not uploaded to a SecondLoop-operated credential service"));

const home = readFileSync(join(distRoot, "index.html"), "utf8");
assert.ok(home.includes("AgentWeave is an open-source Agent App Framework that weaves"));
assert.ok(home.includes("</span> <em>Agent App Framework.</em>"));

const zhHome = readFileSync(join(distRoot, "zh/index.html"), "utf8");
assert.ok(zhHome.includes("AgentWeave 是一个开源 Agent App Framework，把"));
assert.ok(zhHome.includes("</span> <em>Agent App Framework。</em>"));

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
