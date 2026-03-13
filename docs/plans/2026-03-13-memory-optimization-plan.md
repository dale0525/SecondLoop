# SecondLoop Memory Optimization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Improve SecondLoop's long-term memory quality by adding hotness-aware recall, generated stable memories, session-level compression, and dedup/merge policies without breaking the current local-first encrypted knowledge index.

**Architecture:** Keep the existing SQLite + encrypted knowledge index as the system of record, and add a thin “generated memory” layer on top instead of introducing a separate Agent filesystem like OpenViking. Deliver in phases: first improve retrieval ranking with usage signals, then synthesize durable memory documents from conversations/todos/attachments, and finally add dedup, packing, and evaluation so Ask AI becomes more stable across sessions.

**Tech Stack:** Rust (`rusqlite`, current `knowledge` / `rag` modules), Flutter debug surfaces, existing FRB bridge, `pixi` tasks for validation.

---

## Why this plan

This plan intentionally borrows only the parts of OpenViking that fit SecondLoop's product shape:

- Borrow: hotness-aware rerank, session summary, stable-memory synthesis, dedup/merge.
- Do not borrow: heavy URI filesystem abstraction, skill/resource/memory tree traversal, Agent OS concepts.
- Preserve: local-first encrypted storage, current message/attachment/todo knowledge indexing, current Ask AI flow.

## Chosen approach

Recommended approach: **extend the current knowledge index incrementally**.

Why this is the right fit:

1. `KnowledgeOriginType::Generated` already exists, so generated memories can live in the same schema.
2. The current retrieval stack already has request normalization, rerank, and token-budget packing, so we can inject hotness and durable memories with minimal architectural churn.
3. The current product promise is “Ask AI with relevant local context”, not “general agent memory OS”; this plan keeps the UX and privacy model intact.

---

### Task 1: Add hotness-aware recall to existing RAG

**Files:**
- Create: `rust/src/knowledge/usage.rs`
- Modify: `rust/src/knowledge/mod.rs`
- Modify: `rust/src/db/parts/27_knowledge_index.rs`
- Modify: `rust/src/knowledge/retrieval/rerank.rs`
- Modify: `rust/src/rag/mod.rs`
- Modify: `rust/src/rag/knowledge_contexts.rs`
- Test: `rust/src/knowledge/retrieval/rerank_tests.rs`
- Test: `rust/tests/rag_context_selection_v2.rs`

**Step 1: Write the failing tests**

Add tests that prove a recently used memory can outrank a merely recent memory when semantic scores are close.

```rust
#[test]
fn rerank_prefers_hot_recent_candidate_when_semantic_gap_is_small() {
    let cold = candidate_with_scores("cold", 0.78, 0.10, 0, 0);
    let hot = candidate_with_scores("hot", 0.74, 0.10, 12, 1);
    let out = rerank_with_usage(vec![cold, hot]);
    assert_eq!(out[0].document.document_id, "hot");
}
```

**Step 2: Run test to verify it fails**

Run: `pixi run cargo test --manifest-path rust/Cargo.toml knowledge::retrieval::rerank_tests::rerank_prefers_hot_recent_candidate_when_semantic_gap_is_small -- --exact --nocapture`

Expected: FAIL because retrieval candidates do not yet carry usage/hotness information.

**Step 3: Write minimal implementation**

Add a small usage layer instead of mutating retrieval code directly:

```rust
pub struct KnowledgeUsageStats {
    pub retrieve_count: i64,
    pub last_retrieved_at_ms: Option<i64>,
}

pub fn hotness_score(retrieve_count: i64, last_retrieved_at_ms: Option<i64>, now_ms: i64) -> f64 {
    // blend log-count with exponential recency decay
}
```

Then:

- create a new table in `27_knowledge_index.rs` keyed by `document_id`
- load usage stats during rerank
- blend `semantic + lexical + role + quality + recency + hotness`
- record usage after Ask AI actually selects and uses knowledge blocks

**Step 4: Run focused tests to verify it passes**

Run: `pixi run cargo test --manifest-path rust/Cargo.toml rerank_prefers_hot_recent_candidate_when_semantic_gap_is_small`

Expected: PASS.

**Step 5: Commit**

```bash
git add rust/src/knowledge/usage.rs rust/src/knowledge/mod.rs rust/src/db/parts/27_knowledge_index.rs rust/src/knowledge/retrieval/rerank.rs rust/src/rag/mod.rs rust/src/rag/knowledge_contexts.rs rust/src/knowledge/retrieval/rerank_tests.rs rust/tests/rag_context_selection_v2.rs
git commit -m "✨ feat(memory): add hotness-aware knowledge reranking"
```

---

### Task 2: Introduce generated stable-memory documents

**Files:**
- Create: `rust/src/knowledge/memory_synthesis.rs`
- Modify: `rust/src/knowledge/mod.rs`
- Modify: `rust/src/knowledge/models.rs`
- Modify: `rust/src/knowledge/index_jobs.rs`
- Modify: `rust/src/knowledge/source_adapters.rs`
- Modify: `rust/src/db/parts/27_knowledge_index.rs`
- Test: `rust/src/knowledge/source_adapters_tests.rs`
- Test: `rust/src/knowledge/index_jobs_tests.rs`

**Step 1: Write the failing tests**

Add tests that expect generated documents to appear in the rebuild pipeline when a conversation contains repeated user preferences or durable project facts.

```rust
#[test]
fn rebuild_emits_generated_preference_memory_documents() {
    let docs = collect_docs_after_messages(vec![
        "Please answer in concise Chinese.",
        "Keep responses short and practical.",
    ]);
    assert!(docs.iter().any(|doc| doc.origin_type == KnowledgeOriginType::Generated));
}
```

**Step 2: Run test to verify it fails**

Run: `pixi run cargo test --manifest-path rust/Cargo.toml rebuild_emits_generated_preference_memory_documents`

Expected: FAIL because only raw message/attachment/imported documents are currently emitted.

**Step 3: Write minimal implementation**

Create a synthesis module that groups candidate source content into a small number of durable categories:

```rust
pub enum GeneratedMemoryKind {
    Profile,
    Preference,
    Event,
    Pattern,
}
```

Rules for V1:

- `Profile`: stable self-description or recurring identity facts.
- `Preference`: repeated style / formatting / workflow instructions.
- `Event`: important user decisions with timestamps.
- `Pattern`: recurring task strategies inferred from todo/history threads.

Persist these as encrypted `knowledge_documents` with `origin_type = Generated`, deterministic `document_id`, and anchors pointing back to source messages/todos.

**Step 4: Run focused tests to verify it passes**

Run: `pixi run cargo test --manifest-path rust/Cargo.toml generated_preference_memory`

Expected: PASS for source adapter and index job coverage.

**Step 5: Commit**

```bash
git add rust/src/knowledge/memory_synthesis.rs rust/src/knowledge/mod.rs rust/src/knowledge/models.rs rust/src/knowledge/index_jobs.rs rust/src/knowledge/source_adapters.rs rust/src/db/parts/27_knowledge_index.rs rust/src/knowledge/source_adapters_tests.rs rust/src/knowledge/index_jobs_tests.rs
git commit -m "✨ feat(memory): synthesize durable generated memory documents"
```

---

### Task 3: Add dedup and merge policies for stable memories

**Files:**
- Create: `rust/src/knowledge/memory_dedup.rs`
- Modify: `rust/src/knowledge/memory_synthesis.rs`
- Modify: `rust/src/knowledge/models.rs`
- Modify: `rust/src/knowledge/rebuild.rs`
- Test: `rust/src/knowledge/models_tests.rs`
- Test: `rust/src/knowledge/source_adapters_tests.rs`
- Test: `rust/tests/vector_search_dedup.rs`

**Step 1: Write the failing tests**

Add tests for the category-specific policy:

- preferences merge into one evolving memory
- profile appends/refreshes instead of multiplying
- events stay append-only
- near-duplicate generated memories collapse to one canonical document

```rust
#[test]
fn generated_preferences_merge_by_facet_key() {
    let docs = synthesize_twice("response_style", "concise chinese");
    assert_eq!(docs.len(), 1);
}
```

**Step 2: Run test to verify it fails**

Run: `pixi run cargo test --manifest-path rust/Cargo.toml generated_preferences_merge_by_facet_key`

Expected: FAIL because generated memories are not yet deduplicated by category/facet.

**Step 3: Write minimal implementation**

Implement deterministic merge keys and policy objects:

```rust
pub enum MemoryMergePolicy {
    AppendOnly,
    ReplaceLatest,
    MergeByFacet,
}
```

Rules for V1:

- `Profile` -> `ReplaceLatest`
- `Preference` -> `MergeByFacet`
- `Pattern` -> `MergeByFacet`
- `Event` -> `AppendOnly`

Use lightweight lexical similarity first; only add LLM merge later if deterministic heuristics are insufficient.

**Step 4: Run focused tests to verify it passes**

Run: `pixi run cargo test --manifest-path rust/Cargo.toml generated_preferences_merge_by_facet_key vector_search_dedup`

Expected: PASS.

**Step 5: Commit**

```bash
git add rust/src/knowledge/memory_dedup.rs rust/src/knowledge/memory_synthesis.rs rust/src/knowledge/models.rs rust/src/knowledge/rebuild.rs rust/src/knowledge/models_tests.rs rust/src/knowledge/source_adapters_tests.rs rust/tests/vector_search_dedup.rs
git commit -m "✨ feat(memory): add deterministic generated-memory dedup policies"
```

---

### Task 4: Upgrade session compression from prompt-packing to memory-aware summarization

**Files:**
- Create: `rust/src/knowledge/session_digest.rs`
- Modify: `rust/src/rag/mod.rs`
- Modify: `rust/src/rag/context_selection.rs`
- Modify: `rust/src/knowledge/retrieval/pack.rs`
- Modify: `rust/src/knowledge/retrieval/query.rs`
- Test: `rust/src/knowledge/retrieval/pack_tests.rs`
- Test: `rust/tests/rag_prompt.rs`
- Test: `rust/tests/ask_ai_prompt_includes_history.rs`

**Step 1: Write the failing tests**

Add tests that prove Ask AI prefers:

- a short stable session digest over dumping many raw snippets
- highlighted preference/profile memories for broad planning questions
- raw evidence chunks only when the question is detail-seeking

```rust
#[test]
fn pack_prefers_digest_plus_evidence_over_many_redundant_chunks() {
    let blocks = pack_for_question("plan my week", candidates());
    assert!(blocks.iter().any(|b| b.rendered_text.contains("session digest")));
}
```

**Step 2: Run test to verify it fails**

Run: `pixi run cargo test --manifest-path rust/Cargo.toml pack_prefers_digest_plus_evidence_over_many_redundant_chunks`

Expected: FAIL because packer currently truncates by token budget but does not distinguish digest vs. evidence intent.

**Step 3: Write minimal implementation**

Add a V1 session digest generator that builds one compact summary per conversation window:

- `topic`
- `user_intent`
- `open_loops`
- `decisions`
- `relevant_preferences`

Then change the packer to apply intent-sensitive ordering:

- planning / summary questions -> digest first
- factual / recall questions -> evidence first
- when over budget -> keep digest + top evidence instead of many equivalent chunks

**Step 4: Run focused tests to verify it passes**

Run: `pixi run cargo test --manifest-path rust/Cargo.toml pack_prefers_digest_plus_evidence_over_many_redundant_chunks rag_prompt ask_ai_prompt_includes_history`

Expected: PASS.

**Step 5: Commit**

```bash
git add rust/src/knowledge/session_digest.rs rust/src/rag/mod.rs rust/src/rag/context_selection.rs rust/src/knowledge/retrieval/pack.rs rust/src/knowledge/retrieval/query.rs rust/src/knowledge/retrieval/pack_tests.rs rust/tests/rag_prompt.rs rust/tests/ask_ai_prompt_includes_history.rs
git commit -m "✨ feat(memory): add session-digest-aware context packing"
```

---

### Task 5: Add observability, evaluation, and rollout controls

**Files:**
- Modify: `rust/src/api/knowledge.rs`
- Modify: `lib/features/settings/knowledge_index_debug_page.dart`
- Modify: `lib/features/settings/knowledge_index_status_card.dart`
- Create: `rust/tests/generated_memory_smoke.rs`
- Create: `rust/tests/ask_ai_generated_memory_priority.rs`
- Modify: `README.md`
- Modify: `README.zh-CN.md`

**Step 1: Write the failing tests**

Add integration tests that verify:

- generated memories are indexed and retrievable
- hotness changes rerank order
- Ask AI can cite generated memories without swallowing source evidence

```rust
#[test]
fn ask_ai_prefers_generated_preference_memory_for_style_questions() {
    let out = ask_ai_contexts("reply in my usual style");
    assert!(out.iter().any(|ctx| ctx.contains("generated_memory:preference")));
}
```

**Step 2: Run test to verify it fails**

Run: `pixi run cargo test --manifest-path rust/Cargo.toml ask_ai_prefers_generated_preference_memory_for_style_questions`

Expected: FAIL because generated memory visibility and weighting are not yet surfaced.

**Step 3: Write minimal implementation**

Expose debug counters and feature flags:

- generated memory documents count
- per-category counts
- knowledge usage stats count
- last synthesis time
- toggle: enable generated memory retrieval
- toggle: enable hotness rerank

Update docs to explain privacy boundaries: generated memories remain local and encrypted like existing knowledge documents.

**Step 4: Run focused tests to verify it passes**

Run: `pixi run cargo test --manifest-path rust/Cargo.toml generated_memory_smoke ask_ai_generated_memory_priority`

Expected: PASS.

**Step 5: Commit**

```bash
git add rust/src/api/knowledge.rs lib/features/settings/knowledge_index_debug_page.dart lib/features/settings/knowledge_index_status_card.dart rust/tests/generated_memory_smoke.rs rust/tests/ask_ai_generated_memory_priority.rs README.md README.zh-CN.md
git commit -m "✨ feat(memory): add rollout controls and generated-memory observability"
```

---

## Rollout order

Implement in this exact order:

1. Task 1 only, ship behind a flag.
2. Task 2 with deterministic synthesis only.
3. Task 3 once duplicate behavior is visible in test data.
4. Task 4 after retrieval quality is stable.
5. Task 5 before enabling by default.

## Non-goals for V1

- No standalone memory service.
- No separate vector database outside the current local storage model.
- No automatic always-on LLM extraction on every keystroke.
- No OpenViking-style resource/skill tree abstraction.
- No cloud-only memory feature that breaks local-first guarantees.

## Success criteria

- Ask AI retrieves fewer but more durable snippets for planning / summary prompts.
- Stable user preferences survive across sessions without duplicating endlessly.
- Recent frequently used memories rank above stale ones when semantic scores are close.
- All new memory artifacts remain encrypted and queryable through the existing knowledge viewer/debug surfaces.
- Focused Rust tests pass through `pixi run cargo test --manifest-path rust/Cargo.toml ...` for each phase before broader CI.

## Recommended implementation mode

Start with **Task 1 only** in the next execution. It is the smallest change, easiest to validate, and gives measurable retrieval gains without introducing any new user-visible memory semantics.
