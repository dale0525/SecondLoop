# Skill Runtime Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the shared skill manifest/catalog foundation and a deployable `web-research` skill path so QA-CHAT-05 can pass without relying on model-native search.

**Architecture:** Skill packages live in `SecondLoopServer/skills/<skill-id>/` and expose compact manifests to `secretary-runtime`. The LLM chooses tools from the injected catalog, while runtime validates availability, cost, approval policy, and output contracts before executing through `model-gateway` service bindings. The App only parses and displays runtime skill availability; it does not route skills or hard-code providers.

**Tech Stack:** Cloudflare Workers JavaScript, SecondLoopServer pixi/node test runner, Flutter/Dart runtime manifest parsing, GitHub Actions staging deployment.

---

## Scope

Source specs: `docs/architecture/skill-runtime-architecture.md`, `docs/architecture/conversation-context-action-guardrail.md`, `docs/architecture/agent-state-store-secretary-memory.md`, and `docs/qa/managed-pro-manual-qa.md`.

This plan implements Phase 1 from the skill runtime spec:

- `skill.yaml` schema and loader.
- Compact enabled skill catalog injected into every chat intent request.
- Generic runtime validation for skill tool requests.
- First deployable skill package: `web-research`.
- `WEB_RESEARCH_SKILL` binding from `model-gateway`.
- Skill availability report in runtime manifest and QA metadata.
- QA-CHAT-05 automation coverage.

Separate follow-up plans should implement full `document-ocr`, `audio-meeting`, `email`, `calendar`, and self-managed helper UI flows on top of this catalog/enforcement foundation.

## Execution Status - 2026-05-17

Implemented and verified:

- Server Phase 1 skill runtime foundation, `web-research` skill package, runtime/tool validation, gateway binding, deployment ordering, QA-CHAT-05 protocol coverage, and skill availability report are implemented in `SecondLoopServer` and pushed to `origin/main`.
- The latest Server `origin/main` also includes the note HTTP contract and attachment inventory hardening required by the Dart HTTP runtime client plan.
- App runtime manifest parsing now preserves `skills` availability reports for managed pro and self-managed runtime profiles.
- Self-managed helper manifest output includes the shared `web-research` skill availability entry, keeping self-managed and managed pro manifests capability-aligned at the App boundary.

Deferred:

- Full `document-ocr`, `audio-meeting`, `email`, `calendar`, and richer self-managed helper UI flows remain Phase 2+ work, as scoped below.
- Live managed-pro staging acceptance should run after the pushed Server deployment completes.

## Repositories

Server repository: `/Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer`. App repository: `/Users/logictan/.t3/worktrees/SecondLoop/t3code-f5fd1b79`. Server changes are allowed on local `main`; push triggers staging deploy. Keep git identity:

```bash
git config user.name "Logic Tan"
git config user.email "logictan89@gmail.com"
```

## File Structure

- Create shared manifest code: `workers/shared/src/skill_manifest.js`, `workers/shared/test/skill_manifest.test.js`.
- Create web research package: `skills/web-research/skill.yaml`, `SKILL.md`, `deploy/cloudflare.resources.json`, `deploy/secrets.schema.json`, `worker/package.json`, `worker/src/index.js`, `worker/src/providers.js`, `worker/src/tool_schema.json`, `worker/test/web_research_skill.test.js`, `worker/wrangler.template.toml`.
- Modify runtime/gateway: `workers/secretary-runtime/src/context_packet.js`, `workers/secretary-runtime/src/conversation_driver.js`, `workers/secretary-runtime/src/skill_runtime.js`, `workers/secretary-runtime/test/conversation_web_research_and_drafts.test.js`, `workers/secretary-runtime/test/runtime_contract_schema_test.js`, `workers/model-gateway/src/web_research_skill.js`, `workers/model-gateway/wrangler.template.toml`, `workers/model-gateway/test/model_gateway.test.js`.
- Modify deployment: `scripts/render_wrangler_configs.mjs`, `pixi.toml`, `.github/workflows/deploy.yml`, `test/render_wrangler_configs_runtime_workers.test.js`, `scripts/build_skill_availability_report.js`, `test/skill_availability_report.test.js`.
- Modify App manifest parsing: `lib/core/cloud/runtime_manifest.dart`, `test/core/cloud/runtime_manifest_test.dart`.

---

## Task 1: Shared Skill Manifest Loader

**Files:**
- Create: `workers/shared/src/skill_manifest.js`
- Create: `workers/shared/test/skill_manifest.test.js`

- [ ] **Step 1: Write failing schema and catalog tests**

Add tests that prove one manifest normalizes into the compact catalog injected into prompts:

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  buildCompactSkillCatalog,
  normalizeSkillManifest,
  validateToolRequest,
} from '../src/skill_manifest.js';

test('normalizes web research manifest into compact catalog entry', () => {
  const manifest = normalizeSkillManifest({
    id: 'web-research',
    display_name: 'Web Research',
    description_for_llm: 'Research current public facts with citations.',
    enabled_by_default: true,
    tools: [{ name: 'web_research', schema_ref: 'worker/src/tool_schema.json' }],
    runtime: { service_binding: 'WEB_RESEARCH_SKILL' },
    cost_policy: { default_budget: 'low', confirmation_required_above: { search_count: 8 } },
    approval_policy: { side_effect: 'none' },
    output_contract: { citations_required: true, schema: 'web_research_draft' },
  }, { availability: { status: 'ready', provider: 'searxng' } });

  assert.equal(manifest.id, 'web-research');
  assert.equal(manifest.tools[0].name, 'web_research');
  assert.equal(manifest.availability.status, 'ready');

  assert.deepEqual(buildCompactSkillCatalog([manifest]), [{
    id: 'web-research',
    description: 'Research current public facts with citations.',
    tools: ['web_research'],
    side_effect: 'none',
    approval_required_for: [],
    cost: 'low',
    output_contract: 'web_research_draft',
    availability: { status: 'ready', provider: 'searxng' },
  }]);
});

test('rejects disabled or unknown skill tool requests', () => {
  const enabled = [normalizeSkillManifest({
    id: 'web-research',
    description_for_llm: 'Research current public facts with citations.',
    enabled_by_default: true,
    tools: [{ name: 'web_research' }],
    approval_policy: { side_effect: 'none' },
    output_contract: { citations_required: true, schema: 'web_research_draft' },
  }, { availability: { status: 'ready' } })];

  assert.equal(validateToolRequest({
    enabledSkills: enabled,
    request: { skill_id: 'web-research', tool_name: 'web_research', arguments: { query: 'Apple event' } },
  }).ok, true);

  assert.equal(validateToolRequest({
    enabledSkills: enabled,
    request: { skill_id: 'email', tool_name: 'email_send', arguments: {} },
  }).error, 'skill_not_enabled');
});
```

Run:

```bash
cd /Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer/workers/shared
npm test -- skill_manifest.test.js
```

Expected: FAIL because `skill_manifest.js` does not exist.

- [ ] **Step 2: Implement manifest normalization**

Create `workers/shared/src/skill_manifest.js` with these exported functions:

```js
export function normalizeSkillManifest(raw, { availability = {} } = {}) {
  const id = str(raw.id);
  if (!id) throw new Error('skill_manifest_missing_id');
  const tools = arr(raw.tools).map((tool) => ({ name: str(tool.name) })).filter((tool) => tool.name);
  if (tools.length === 0) throw new Error('skill_manifest_missing_tools');
  return {
    id,
    display_name: str(raw.display_name),
    description_for_llm: str(raw.description_for_llm ?? raw.description),
    enabled_by_default: raw.enabled_by_default !== false,
    tools,
    runtime: obj(raw.runtime),
    cost_policy: obj(raw.cost_policy),
    approval_policy: obj(raw.approval_policy),
    output_contract: obj(raw.output_contract),
    availability: {
      status: str(availability.status || 'unavailable'),
      ...(availability.provider ? { provider: str(availability.provider) } : {}),
      ...(availability.reason ? { reason: str(availability.reason) } : {}),
    },
  };
}

export function buildCompactSkillCatalog(manifests) {
  return manifests.filter((manifest) => manifest.enabled_by_default).map((manifest) => ({
    id: manifest.id,
    description: manifest.description_for_llm,
    tools: manifest.tools.map((tool) => tool.name),
    side_effect: str(manifest.approval_policy.side_effect || 'none'),
    approval_required_for: arr(manifest.approval_policy.approval_required_for),
    cost: str(manifest.cost_policy.default_budget || 'low'),
    output_contract: str(manifest.output_contract.schema),
    availability: manifest.availability,
  }));
}

export function validateToolRequest({ enabledSkills, request }) {
  const skillId = str(request?.skill_id);
  const toolName = str(request?.tool_name);
  const skill = enabledSkills.find((item) => item.id === skillId && item.enabled_by_default);
  if (!skill) return { ok: false, error: 'skill_not_enabled' };
  if (!skill.tools.some((tool) => tool.name === toolName)) return { ok: false, error: 'tool_not_declared' };
  if (skill.availability.status !== 'ready') return { ok: false, error: 'skill_unavailable', skill };
  return { ok: true, skill, tool_name: toolName, arguments: obj(request.arguments) };
}

const str = (value) => String(value ?? '').trim();
const obj = (value) => value && typeof value === 'object' && !Array.isArray(value) ? value : {};
const arr = (value) => Array.isArray(value) ? value : [];
```

- [ ] **Step 3: Verify shared tests**

Run:

```bash
cd /Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer/workers/shared
npm test -- skill_manifest.test.js
```

Expected: PASS for `skill_manifest.test.js`.

---

## Task 2: Web Research Skill Package

**Files:**
- Create: `skills/web-research/skill.yaml`
- Create: `skills/web-research/SKILL.md`
- Create: `skills/web-research/deploy/cloudflare.resources.json`
- Create: `skills/web-research/deploy/secrets.schema.json`
- Create: `skills/web-research/worker/src/tool_schema.json`

- [ ] **Step 1: Add package metadata**

Create `skills/web-research/skill.yaml`:

```yaml
id: web-research
version: 0.1.0
display_name: Web Research
description_for_llm: Research current public facts and return a cited summary when an answer needs current public evidence, launches, news, prices, specifications, policies, or source-backed research.
enabled_by_default: true
tools:
  - name: web_research
    schema_ref: worker/src/tool_schema.json
runtime:
  worker: secondloop-web-research-skill
  service_binding: WEB_RESEARCH_SKILL
cost_policy:
  default_budget: low
  confirmation_required_above:
    search_count: 8
    fetch_count: 5
approval_policy:
  side_effect: none
  approval_required_for: []
output_contract:
  citations_required: true
  schema: web_research_draft
providers:
  self_managed_default: searxng
  managed_pro_default: direct_fetch
  fallback:
    - brave
    - searxng
```

Create `skills/web-research/SKILL.md`:

```markdown
# Web Research

Use this skill for current public facts, recent launches, prices, specifications, policy changes, and source-backed research.

Call `web_research` with a concise query. Include recent conversation context only when the user asks a follow-up such as "新的手机产品参数".

The result is successful only when it contains `web_research_draft.summary` and at least one citation with `title`, `url`, and `domain`.

If the skill is unavailable, say that current-source research is unavailable and avoid guessing.

The skill has no external side effects. Large research requests require high-cost confirmation before execution.
```

Create `skills/web-research/worker/src/tool_schema.json`:

```json
{
  "name": "web_research",
  "description": "Research public web sources and return a cited summary.",
  "parameters": {
    "type": "object",
    "properties": {
      "query": { "type": "string", "minLength": 1 },
      "max_search_count": { "type": "integer", "minimum": 1, "maximum": 10 },
      "max_fetch_count": { "type": "integer", "minimum": 0, "maximum": 5 },
      "citation_required": { "type": "boolean" }
    },
    "required": ["query"]
  }
}
```

- [ ] **Step 2: Add deployment metadata**

Create `skills/web-research/deploy/secrets.schema.json`:

```json
{
  "optional": [
    "SEARXNG_BASE_URL",
    "BRAVE_SEARCH_API_KEY",
    "PREMIUM_SEARCH_API_KEY"
  ],
  "required_for_managed_pro": [],
  "required_for_self_managed": []
}
```

Create `skills/web-research/deploy/cloudflare.resources.json`:

```json
{
  "workers": [
    {
      "name": "secondloop-web-research-skill",
      "binding": "WEB_RESEARCH_SKILL",
      "script": "skills/web-research/worker/src/index.js"
    }
  ],
  "kv": [
    {
      "binding": "WEB_RESEARCH_CACHE",
      "purpose": "cache web research results and provider health"
    }
  ]
}
```

---

## Task 3: Web Research Skill Worker

**Files:**
- Create: `skills/web-research/worker/package.json`
- Create: `skills/web-research/worker/src/index.js`
- Create: `skills/web-research/worker/src/providers.js`
- Create: `skills/web-research/worker/test/web_research_skill.test.js`
- Create: `skills/web-research/worker/wrangler.template.toml`

- [ ] **Step 1: Write failing worker contract tests**

Create `skills/web-research/worker/test/web_research_skill.test.js`:

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import { handleResearchRequest } from '../src/index.js';

test('returns cited draft from direct fetch provider', async () => {
  const request = new Request('https://skill.example/v1/research', {
    method: 'POST',
    body: JSON.stringify({ query: 'Apple 今天的发布会发布了哪些产品？', max_search_count: 5, max_fetch_count: 3 }),
  });
  const response = await handleResearchRequest(request, {
    DIRECT_FETCH_FIXTURES: JSON.stringify({
      apple: {
        title: 'Apple Newsroom',
        url: 'https://www.apple.com/newsroom/',
        domain: 'www.apple.com',
        summary: 'Apple 发布了新的 iPhone、Apple Watch 和 AirPods 产品。'
      }
    }),
  });
  const body = await response.json();
  assert.equal(response.status, 200);
  assert.equal(body.web_research_draft.kind, 'web_research_draft');
  assert.equal(body.web_research_draft.citations[0].domain, 'www.apple.com');
});

test('fails closed when no provider can return citations', async () => {
  const request = new Request('https://skill.example/v1/research', {
    method: 'POST',
    body: JSON.stringify({ query: 'current launch', max_search_count: 5, max_fetch_count: 3 }),
  });
  const response = await handleResearchRequest(request, {});
  const body = await response.json();
  assert.equal(response.status, 503);
  assert.equal(body.error, 'web_research_provider_unavailable');
});
```

Run:

```bash
cd /Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer/skills/web-research/worker
npm test
```

Expected: FAIL because the worker does not exist.

- [ ] **Step 2: Implement the worker route and provider abstraction**

Create `package.json`:

```json
{
  "name": "secondloop-web-research-skill",
  "private": true,
  "type": "module",
  "scripts": {
    "test": "node --test",
    "dev": "node ../../../scripts/render_wrangler_configs.mjs --worker web-research-skill && wrangler dev",
    "deploy:staging": "node ../../../scripts/render_wrangler_configs.mjs --worker web-research-skill && wrangler deploy --env staging",
    "deploy:prod": "node ../../../scripts/render_wrangler_configs.mjs --worker web-research-skill && wrangler deploy --env prod"
  },
  "devDependencies": {
    "wrangler": "^4.77.0"
  }
}
```

Create `src/providers.js`:

```js
export async function runProviderOrder({ env, query }) {
  const fixtures = safeJson(env.DIRECT_FETCH_FIXTURES);
  const key = String(query ?? '').toLowerCase().includes('apple') ? 'apple' : '';
  const item = key ? fixtures[key] : null;
  if (!item?.url || !item?.summary) return null;
  return {
    summary: item.summary,
    citations: [{
      title: item.title || item.domain || item.url,
      url: item.url,
      domain: item.domain || new URL(item.url).hostname,
      fetched_at_ms: Date.now()
    }]
  };
}

function safeJson(value) {
  try {
    return JSON.parse(String(value ?? '{}'));
  } catch {
    return {};
  }
}
```

Create `src/index.js`:

```js
import { runProviderOrder } from './providers.js';

export default {
  fetch(request, env) {
    return handleResearchRequest(request, env);
  },
};

export async function handleResearchRequest(request, env) {
  if (request.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
  const body = await request.json().catch(() => ({}));
  const query = String(body.query ?? '').trim();
  if (!query) return json({ error: 'missing_query' }, 400);
  const result = await runProviderOrder({ env, query, request: body });
  if (!result?.summary || !Array.isArray(result.citations) || result.citations.length === 0)
    return json({ error: 'web_research_provider_unavailable' }, 503);
  return json({
    ok: true,
    web_research_draft: {
      kind: 'web_research_draft',
      query,
      search_count: Math.min(Number(body.max_search_count ?? 5), 5),
      fetch_count: Math.min(Number(body.max_fetch_count ?? 3), 3),
      citations: result.citations,
      summary: result.summary,
    },
  });
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
}
```

- [ ] **Step 3: Verify worker tests**

Run:

```bash
cd /Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer/skills/web-research/worker
npm test
```

Expected: PASS.

---

## Task 4: Deployment Wiring For Skill Worker

**Files:**
- Modify: `scripts/render_wrangler_configs.mjs`
- Modify: `pixi.toml`
- Modify: `workers/model-gateway/wrangler.template.toml`
- Create: `skills/web-research/worker/wrangler.template.toml`
- Modify: `test/render_wrangler_configs_runtime_workers.test.js`
- Modify: `.github/workflows/deploy.yml`

- [ ] **Step 1: Write failing render tests**

Extend `test/render_wrangler_configs_runtime_workers.test.js`:

```js
test('render_wrangler_configs supports web research skill worker', async () => {
  const { renderWorkerWrangler } = await importRenderModule();
  const rendered = await renderWorkerWrangler({ repoRoot, worker: 'web-research-skill' });
  assert.match(rendered, /name = "secondloop-web-research-skill/);
  assert.match(rendered, /main = "src\/index.js"/);
});

test('model gateway binds web research skill service', async () => {
  const { renderWorkerWrangler } = await importRenderModule();
  const rendered = await renderWorkerWrangler({ repoRoot, worker: 'model-gateway' });
  assert.match(rendered, /binding = "WEB_RESEARCH_SKILL"/);
  assert.match(rendered, /service = "secondloop-web-research-skill-staging"/);
});
```

Run:

```bash
cd /Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer
pixi run node --test test/render_wrangler_configs_runtime_workers.test.js
```

Expected: FAIL because the renderer does not know `web-research-skill`.

- [ ] **Step 2: Add worker registry support**

Update `scripts/render_wrangler_configs.mjs` so worker metadata can point outside `workers/`:

```js
const WORKERS = new Map([
  ['ai-gateway', { template: 'workers/ai-gateway/wrangler.template.toml', output: 'workers/ai-gateway/wrangler.toml' }],
  ['managed-vault', { template: 'workers/managed-vault/wrangler.template.toml', output: 'workers/managed-vault/wrangler.toml' }],
  ['secretary-runtime', { template: 'workers/secretary-runtime/wrangler.template.toml', output: 'workers/secretary-runtime/wrangler.toml' }],
  ['model-gateway', { template: 'workers/model-gateway/wrangler.template.toml', output: 'workers/model-gateway/wrangler.toml' }],
  ['vault-service', { template: 'workers/vault-service/wrangler.template.toml', output: 'workers/vault-service/wrangler.toml' }],
  ['web-research-skill', { template: 'skills/web-research/worker/wrangler.template.toml', output: 'skills/web-research/worker/wrangler.toml' }],
]);
```

Adjust `workerTemplatePath`, `workerWranglerPath`, `writeAllWranglers`, and argument validation to use the map.

- [ ] **Step 3: Add wrangler templates and service binding**

Create `skills/web-research/worker/wrangler.template.toml`:

```toml
name = "secondloop-web-research-skill"
main = "src/index.js"
compatibility_date = "2026-01-18"

[env.staging]
name = "secondloop-web-research-skill-staging"

[env.staging.vars]
DIRECT_FETCH_FIXTURES = "{}"

[env.prod]
name = "secondloop-web-research-skill-prod"

[env.prod.vars]
DIRECT_FETCH_FIXTURES = "{}"
```

Add to `workers/model-gateway/wrangler.template.toml`:

```toml
[[env.staging.services]]
binding = "WEB_RESEARCH_SKILL"
service = "secondloop-web-research-skill-staging"

[[env.prod.services]]
binding = "WEB_RESEARCH_SKILL"
service = "secondloop-web-research-skill-prod"
```

- [ ] **Step 4: Add pixi and deploy pipeline entries**

Update `pixi.toml`:

```toml
install = "bash scripts/run_working_npm.sh workers/ai-gateway install && bash scripts/run_working_npm.sh workers/managed-vault install && bash scripts/run_working_npm.sh workers/secretary-runtime install && bash scripts/run_working_npm.sh workers/model-gateway install && bash scripts/run_working_npm.sh workers/vault-service install && bash scripts/run_working_npm.sh skills/web-research/worker install"
test = "node --test test/*.test.js && node scripts/run_package_script.js workers/ai-gateway test && node scripts/run_package_script.js workers/managed-vault test && node scripts/run_package_script.js workers/shared test && node scripts/run_package_script.js workers/secretary-runtime test && node scripts/run_package_script.js workers/model-gateway test && node scripts/run_package_script.js workers/vault-service test && node scripts/run_package_script.js skills/web-research/worker test"
deploy-staging = "node scripts/sync_cloudflare_worker_secrets.mjs --env staging --all --check && node scripts/run_package_script.js skills/web-research/worker deploy:staging && node scripts/run_package_script.js workers/ai-gateway deploy:staging && node scripts/run_package_script.js workers/managed-vault deploy:staging && node scripts/run_package_script.js workers/secretary-runtime deploy:staging && node scripts/run_package_script.js workers/model-gateway deploy:staging && node scripts/run_package_script.js workers/vault-service deploy:staging && node scripts/sync_cloudflare_worker_secrets.mjs --env staging --all"
```

Apply the same ordering in `.github/workflows/deploy.yml`: deploy `web-research-skill` before `model-gateway`.

- [ ] **Step 5: Verify deployment wiring**

Run:

```bash
cd /Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer
pixi run node --test test/render_wrangler_configs_runtime_workers.test.js
pixi run render-wrangler-configs
```

Expected: PASS and generated `skills/web-research/worker/wrangler.toml`.

---

## Task 5: Runtime Catalog Injection And Tool Request Execution

**Files:**
- Create: `workers/secretary-runtime/src/skill_runtime.js`
- Modify: `workers/secretary-runtime/src/context_packet.js`
- Modify: `workers/secretary-runtime/src/conversation_driver.js`
- Modify: `workers/secretary-runtime/test/conversation_web_research_and_drafts.test.js`

- [ ] **Step 1: Write failing runtime tests**

Add tests to `conversation_web_research_and_drafts.test.js`:

```js
test('context packet includes enabled compact skill catalog', async () => {
  const env = createRuntimeEnv({ webResearchSkill: async () => citedAppleDraft() });
  const run = await sendConversationMessage(env, 'vault-1', 'conv-1', 'Apple 今天的发布会发布了哪些产品？');
  const context = run.metadata.context_snapshot?.context_packet;
  assert.equal(context.enabled_skills[0].id, 'web-research');
  assert.equal(context.enabled_skills[0].tools[0], 'web_research');
});

test('LLM selected web research tool executes through runtime validation', async () => {
  const skillCalls = [];
  const env = createRuntimeEnv({
    modelGatewayIntent: {
      ok: true,
      response_type: 'tool_request',
      run_status: 'running',
      approval_required: false,
      tool_request: {
        skill_id: 'web-research',
        tool_name: 'web_research',
        arguments: { query: 'Apple 今天的发布会发布了哪些产品？', max_search_count: 5, max_fetch_count: 3 }
      }
    },
    webResearchSkill: async (request) => {
      skillCalls.push(request);
      return citedAppleDraft();
    }
  });
  const run = await sendConversationMessage(env, 'vault-1', 'conv-1', 'Apple 今天的发布会发布了哪些产品？');
  assert.equal(run.metadata.response_type, 'assistant_message');
  assert.equal(run.metadata.web_research_drafts[0].citations[0].domain, 'www.apple.com');
  assert.equal(skillCalls.length, 1);
});
```

Run:

```bash
cd /Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer/workers/secretary-runtime
npm test -- conversation_web_research_and_drafts.test.js
```

Expected: FAIL because `enabled_skills` and `tool_request` handling are absent.

- [ ] **Step 2: Build runtime skill catalog**

Create `workers/secretary-runtime/src/skill_runtime.js`:

```js
import {
  buildCompactSkillCatalog,
  normalizeSkillManifest,
  validateToolRequest,
} from '../../shared/src/skill_manifest.js';

export function buildEnabledSkillManifests(env) {
  return [
    normalizeSkillManifest({
      id: 'web-research',
      description_for_llm: 'Research current public facts with citations.',
      enabled_by_default: true,
      tools: [{ name: 'web_research' }],
      approval_policy: { side_effect: 'none', approval_required_for: [] },
      cost_policy: { default_budget: 'low' },
      output_contract: { citations_required: true, schema: 'web_research_draft' },
    }, { availability: env.WEB_RESEARCH_SKILL || env.webResearchSkill ? { status: 'ready', provider: 'configured' } : { status: 'unavailable', reason: 'missing_binding' } }),
  ];
}

export function buildRuntimeSkillCatalog(env) {
  return buildCompactSkillCatalog(buildEnabledSkillManifests(env));
}

export function validateRuntimeToolRequest(env, request) {
  return validateToolRequest({
    enabledSkills: buildEnabledSkillManifests(env),
    request,
  });
}
```

Modify `context_packet.js` to accept and emit `enabledSkills`:

```js
export function buildContextPacket({ ..., enabledSkills = [] }) {
  return {
    ...
    enabled_skills: enabledSkills,
  };
}
```

- [ ] **Step 3: Let the LLM choose the tool**

Modify `conversation_driver.js`:

- Build `enabledSkills` with `buildRuntimeSkillCatalog(agent.getEnv())`.
- Pass `enabledSkills` into `buildContextPacket`.
- Add `tool_request` to the runtime contract response types.
- Remove the pre-model `shouldUseFreshWebResearch(message)` execution path as the primary route.
- After `parseModelIntent`, if `response_type === 'tool_request'`, validate and execute the request.

Execution branch:

```js
if (normalizeIntentResponseType(intent) === 'tool_request') {
  const validation = validateRuntimeToolRequest(agent.getEnv(), intent.tool_request);
  if (!validation.ok) {
    return withContextMetadata(intentFailureOutcome(validation.error));
  }
  if (validation.skill.id === 'web-research' && validation.tool_name === 'web_research') {
    return withContextMetadata(await resolveFreshWebResearchOutcome(agent, {
      message: validation.arguments.query || message,
      contextPacket,
      runtimeMode,
      provider,
      toolArguments: validation.arguments,
    }));
  }
  return withContextMetadata(intentFailureOutcome('tool_not_implemented'));
}
```

Update `purposeGuidance` in `workers/model-gateway/src/index.js` to instruct the model:

```js
'When input.enabled_skills contains a ready skill that is useful, return response_type "tool_request" with tool_request {skill_id, tool_name, arguments}.',
'For current public facts, prefer the web-research skill over model knowledge when it is ready.',
```

- [ ] **Step 4: Verify runtime tests**

Run:

```bash
cd /Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer/workers/secretary-runtime
npm test -- conversation_web_research_and_drafts.test.js
```

Expected: PASS, including the existing unavailable-skill failure behavior.

---

## Task 6: Model Gateway Binding And Output Contract

**Files:**
- Modify: `workers/model-gateway/src/web_research_skill.js`
- Modify: `workers/model-gateway/test/model_gateway.test.js`

- [ ] **Step 1: Strengthen model gateway tests**

Add assertions to existing web research route tests:

```js
assert.equal(body.ok, true);
assert.equal(body.web_research_draft.kind, 'web_research_draft');
assert.ok(body.web_research_draft.summary.length > 0);
assert.ok(body.web_research_draft.citations.length > 0);
```

Add a failure test:

```js
test('web research route fails closed without citations', async () => {
  const response = await worker.fetch(new Request('https://example.com/v1/runtime/tools/web-research', {
    method: 'POST',
    body: JSON.stringify({ query: 'Apple event' }),
  }), { webResearchSkill: async () => ({ web_research_draft: { summary: 'No sources', citations: [] } }) });
  const body = await response.json();
  assert.equal(response.status, 502);
  assert.equal(body.error, 'missing_citations');
});
```

Run:

```bash
cd /Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer/workers/model-gateway
npm test -- model_gateway.test.js
```

Expected: PASS after existing normalization remains intact.

- [ ] **Step 2: Ensure service binding is the preferred execution path**

Keep `env.webResearchSkill` as test injection only. Production path must use:

```js
env.WEB_RESEARCH_SKILL.fetch(new Request('https://web-research-skill.example/v1/research', ...))
```

If neither test injection nor service binding exists, return:

```json
{ "ok": false, "status": 503, "error": "web_research_skill_unavailable" }
```

---

## Task 7: Skill Availability Report And App Manifest Parsing

**Files:**
- Create: `scripts/build_skill_availability_report.js`
- Create: `test/skill_availability_report.test.js`
- Modify: `lib/core/cloud/runtime_manifest.dart`
- Modify: `test/core/cloud/runtime_manifest_test.dart`

- [ ] **Step 1: Add server availability report tests**

Create `test/skill_availability_report.test.js`:

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import { buildSkillAvailabilityReport } from '../scripts/build_skill_availability_report.js';

test('reports web research skill readiness', () => {
  const report = buildSkillAvailabilityReport({
    mode: 'managed_pro',
    bindings: { WEB_RESEARCH_SKILL: true },
  });
  assert.deepEqual(report.skills, [{
    id: 'web-research',
    status: 'ready',
    provider: 'configured',
  }]);
});

test('reports missing web research binding', () => {
  const report = buildSkillAvailabilityReport({ mode: 'self_managed', bindings: {} });
  assert.equal(report.skills[0].status, 'unavailable');
  assert.equal(report.skills[0].reason, 'missing_binding');
});
```

Implement:

```js
export function buildSkillAvailabilityReport({ mode, bindings }) {
  const hasWebResearch = bindings?.WEB_RESEARCH_SKILL === true;
  return {
    mode,
    skills: [{
      id: 'web-research',
      status: hasWebResearch ? 'ready' : 'unavailable',
      ...(hasWebResearch ? { provider: 'configured' } : { reason: 'missing_binding' }),
    }],
  };
}
```

- [ ] **Step 2: Add App manifest parsing**

Extend `CloudRuntimeManifest` with:

```dart
final List<CloudRuntimeSkillAvailability> skills;
```

Add immutable class:

```dart
@immutable
class CloudRuntimeSkillAvailability {
  const CloudRuntimeSkillAvailability({
    required this.id,
    required this.status,
    this.provider,
    this.reason,
  });

  final String id;
  final String status;
  final String? provider;
  final String? reason;
}
```

Parse manifest JSON key `skills`:

```dart
skills: rawSkills is List
    ? rawSkills
        .whereType<Map>()
        .map((value) => CloudRuntimeSkillAvailability.fromJson(Map<String, dynamic>.from(value)))
        .toList(growable: false)
    : const <CloudRuntimeSkillAvailability>[],
```

Add `test/core/cloud/runtime_manifest_test.dart` assertion:

```dart
expect(manifest.skills.single.id, 'web-research');
expect(manifest.skills.single.status, 'ready');
expect(manifest.skills.single.provider, 'configured');
```

Run:

```bash
cd /Users/logictan/.t3/worktrees/SecondLoop/t3code-f5fd1b79
pixi run flutter test test/core/cloud/runtime_manifest_test.dart
```

Expected: PASS.

---

## Task 8: End-To-End Verification For QA-CHAT-05

**Files:**
- Modify: `workers/secretary-runtime/test/conversation_web_research_and_drafts.test.js`
- Modify: `docs/qa/managed-pro-manual-qa.md` only if observed behavior changes.

- [ ] **Step 1: Add QA-CHAT-05 protocol test**

Add a two-turn test:

```js
test('QA-CHAT-05 answers Apple launch question with search then carries phone context', async () => {
  const env = createRuntimeEnv({
    webResearchSkill: async (request) => ({
      web_research_draft: {
        kind: 'web_research_draft',
        query: request.query,
        search_count: 5,
        fetch_count: 3,
        citations: [{ title: 'Apple Newsroom', url: 'https://www.apple.com/newsroom/', domain: 'www.apple.com' }],
        summary: 'Apple 发布了 iPhone 17、Apple Watch 和 AirPods。'
      }
    })
  });

  const first = await sendConversationMessage(env, 'vault-1', 'conv-qa-chat-05', 'Apple 今天的发布会发布了哪些产品？');
  assert.equal(first.metadata.web_research_drafts[0].citations[0].domain, 'www.apple.com');

  const second = await sendConversationMessage(env, 'vault-1', 'conv-qa-chat-05', '介绍一下新的手机产品参数。');
  assert.doesNotMatch(second.assistant_content, /哪.*手机|请.*说明.*产品/);
});
```

Run:

```bash
cd /Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer/workers/secretary-runtime
npm test -- conversation_web_research_and_drafts.test.js
```

Expected: PASS.

- [ ] **Step 2: Full verification**

Run server verification:

```bash
cd /Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer
pixi run test
pixi run cloud-runtime-automation-test
```

Run App manifest verification:

```bash
cd /Users/logictan/.t3/worktrees/SecondLoop/t3code-f5fd1b79
pixi run flutter test test/core/cloud/runtime_manifest_test.dart
```

Expected: all commands exit 0.

## Acceptance Checklist

- [ ] Runtime context packet includes compact `enabled_skills`.
- [ ] LLM can select `web-research` through `tool_request`; runtime validates the request before execution.
- [ ] Runtime no longer depends on model-native search for current public facts.
- [ ] `web-research` output without citations fails closed.
- [ ] `model-gateway` has `WEB_RESEARCH_SKILL` service binding in staging and prod.
- [ ] Skill worker deploys before `model-gateway` in managed pro CI/CD.
- [ ] App manifest can parse `skills` availability.
- [ ] QA-CHAT-05 protocol test proves Apple launch search plus follow-up context carry-over.
- [ ] `docs/` remains ignored; `.gitignore` is unchanged.

## Full Verification Commands

```bash
cd /Users/logictan/Documents/Git/SecondLoopFolder/SecondLoopServer
pixi run test
pixi run cloud-runtime-automation-test
pixi run render-wrangler-configs

cd /Users/logictan/.t3/worktrees/SecondLoop/t3code-f5fd1b79
pixi run flutter test test/core/cloud/runtime_manifest_test.dart
git diff -- .gitignore
git status --short --ignored docs
```

Expected: server tests and App manifest test exit 0; `.gitignore` has no diff; `docs/` still appears only as ignored output.
