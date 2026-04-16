const DEFAULT_MAX_CONTEXT_CHARS: usize = 6000;
const DEFAULT_COMPRESS_SENTENCES: usize = 3;
const DEFAULT_MMR_LAMBDA: f64 = 0.55;
const DEFAULT_MIN_RELEVANCE: f64 = 0.20;
const DEFAULT_MIN_RELEVANCE_WITHOUT_LEXICAL_MATCH: f64 = 0.55;
const DEFAULT_RELATIVE_RELEVANCE_FLOOR: f64 = 0.45;
const DEFAULT_MAX_DISTANCE_WITHOUT_LEXICAL_MATCH: f64 = 0.35;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum ContextSource {
    Message,
    TodoThread,
    Event,
    TodoActivity,
    AttachmentChunk,
    ExternalDocument,
}

#[derive(Clone, Debug)]
pub(crate) struct ContextItem {
    pub(crate) source: ContextSource,
    pub(crate) id: String,
    pub(crate) created_at_ms: i64,
    pub(crate) distance: Option<f64>,
    pub(crate) text: String,
    pub(crate) citation_suffix: Option<String>,
}

fn now_ms() -> i64 {
    crate::platform::time::now_ms()
}

fn lite_normalize_text(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for ch in text.chars() {
        if ch.is_alphanumeric() {
            out.extend(ch.to_lowercase());
        } else {
            out.push(' ');
        }
    }
    out.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn lite_compact_text(text: &str) -> String {
    text.chars().filter(|c| !c.is_whitespace()).collect()
}

fn lite_collect_bigrams(chars: &[char]) -> std::collections::HashSet<u64> {
    let mut set = std::collections::HashSet::new();
    if chars.len() < 2 {
        return set;
    }
    for i in 0..(chars.len() - 1) {
        let a = chars[i] as u64;
        let b = chars[i + 1] as u64;
        set.insert((a << 32) | b);
    }
    set
}

pub(crate) fn lite_score(query: &str, candidate: &str) -> u64 {
    let query_norm = lite_normalize_text(query);
    let query_compact = lite_compact_text(&query_norm);
    if query_compact.is_empty() {
        return 0;
    }

    let cand_norm = lite_normalize_text(candidate);
    if cand_norm.is_empty() {
        return 0;
    }

    let cand_compact = lite_compact_text(&cand_norm);
    if cand_compact.is_empty() {
        return 0;
    }

    let query_chars: Vec<char> = query_compact.chars().collect();
    let query_bigrams = lite_collect_bigrams(&query_chars);

    let mut score = 0u64;

    if cand_norm == query_norm {
        score = score.saturating_add(10_000);
    }

    if !query_norm.is_empty() && cand_norm.contains(&query_norm) {
        score = score.saturating_add(500);
        score = score.saturating_add((query_compact.chars().count() as u64).saturating_mul(50));
    }

    for token in query_norm.split_whitespace() {
        if token.len() < 2 {
            continue;
        }
        if cand_norm.contains(token) {
            score = score.saturating_add((token.chars().count() as u64).saturating_mul(200));
        }
    }

    if !query_bigrams.is_empty() {
        let cand_chars: Vec<char> = cand_compact.chars().collect();
        let cand_bigrams = lite_collect_bigrams(&cand_chars);
        let overlap = query_bigrams.intersection(&cand_bigrams).count() as u64;
        score = score.saturating_add(overlap.saturating_mul(50));
    }

    score
}

fn lite_score_strict(query: &str, candidate: &str) -> u64 {
    let query_norm = lite_normalize_text(query);
    let query_compact = lite_compact_text(&query_norm);
    if query_compact.is_empty() {
        return 0;
    }

    let cand_norm = lite_normalize_text(candidate);
    if cand_norm.is_empty() {
        return 0;
    }

    let cand_compact = lite_compact_text(&cand_norm);
    if cand_compact.is_empty() {
        return 0;
    }

    let mut score = 0u64;

    if cand_norm == query_norm {
        score = score.saturating_add(10_000);
    }

    if !query_norm.is_empty() && cand_norm.contains(&query_norm) {
        score = score.saturating_add(500);
        score = score.saturating_add((query_compact.chars().count() as u64).saturating_mul(50));
    }

    for token in query_norm.split_whitespace() {
        if token.len() < 3 {
            continue;
        }
        if cand_norm.contains(token) {
            score = score.saturating_add((token.chars().count() as u64).saturating_mul(300));
        }
    }

    score
}

fn lite_similarity(a: &str, b: &str) -> f64 {
    let a_norm = lite_normalize_text(a);
    let a_compact = lite_compact_text(&a_norm);
    let b_norm = lite_normalize_text(b);
    let b_compact = lite_compact_text(&b_norm);
    if a_compact.is_empty() || b_compact.is_empty() {
        return 0.0;
    }
    let a_chars: Vec<char> = a_compact.chars().collect();
    let b_chars: Vec<char> = b_compact.chars().collect();
    let a_bigrams = lite_collect_bigrams(&a_chars);
    let b_bigrams = lite_collect_bigrams(&b_chars);
    if a_bigrams.is_empty() || b_bigrams.is_empty() {
        return 0.0;
    }
    let inter = a_bigrams.intersection(&b_bigrams).count() as f64;
    let union = a_bigrams.union(&b_bigrams).count() as f64;
    if union <= 0.0 {
        0.0
    } else {
        (inter / union).clamp(0.0, 1.0)
    }
}

fn split_sentences(text: &str) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    let mut buf = String::new();
    for ch in text.chars() {
        let is_boundary = ch == '\n'
            || ch == '.'
            || ch == '!'
            || ch == '?'
            || ch == '。'
            || ch == '！'
            || ch == '？';

        if is_boundary {
            let trimmed = buf.trim();
            if !trimmed.is_empty() {
                out.push(trimmed.to_string());
            }
            buf.clear();
            continue;
        }

        buf.push(ch);
    }
    let trimmed = buf.trim();
    if !trimmed.is_empty() {
        out.push(trimmed.to_string());
    }
    out
}

fn compress_context_text(query: &str, text: &str) -> String {
    let sentences = split_sentences(text);
    if sentences.is_empty() {
        return String::new();
    }

    let mut scored: Vec<(usize, u64)> = Vec::new();
    for (i, s) in sentences.iter().enumerate() {
        let score = lite_score_strict(query, s);
        if score == 0 {
            continue;
        }
        scored.push((i, score));
    }

    if scored.is_empty() {
        let take_n = DEFAULT_COMPRESS_SENTENCES.min(sentences.len());
        return sentences
            .into_iter()
            .take(take_n)
            .collect::<Vec<_>>()
            .join("\n");
    }

    scored.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0)));
    if scored.len() > DEFAULT_COMPRESS_SENTENCES {
        scored.truncate(DEFAULT_COMPRESS_SENTENCES);
    }
    scored.sort_by(|a, b| a.0.cmp(&b.0));

    let mut selected: Vec<String> = Vec::new();
    for (idx, _) in scored {
        if let Some(s) = sentences.get(idx) {
            selected.push(s.to_string());
        }
    }
    selected.join("\n")
}

#[derive(Clone, Copy, Debug)]
struct RankedContextItem {
    relevance: f64,
    lexical_score: u64,
    idx: usize,
}

fn rank_context_items(question: &str, candidates: &[ContextItem]) -> Vec<RankedContextItem> {
    let now = now_ms();
    let mut scored: Vec<RankedContextItem> = Vec::new();

    for (i, item) in candidates.iter().enumerate() {
        let semantic = item
            .distance
            .map(|d| 1.0 / (1.0 + d.max(0.0)))
            .unwrap_or(0.0);

        let lexical_score = lite_score(question, &item.text);
        let lexical = if lexical_score == 0 {
            0.0
        } else {
            let s = lexical_score as f64;
            (s / (s + 4000.0)).clamp(0.0, 1.0)
        };

        let age_ms = now.saturating_sub(item.created_at_ms).max(0) as f64;
        let age_days = age_ms / (24.0 * 60.0 * 60.0 * 1000.0);
        let recency = (-age_days / 14.0).exp().clamp(0.0, 1.0);

        // When distance is missing (e.g. time-window retrieval), lexical should dominate.
        let semantic_w = if item.distance.is_some() { 0.6 } else { 0.0 };
        let lexical_w = if item.distance.is_some() { 0.3 } else { 0.9 };
        let recency_w = 0.1;

        let relevance = (semantic_w * semantic) + (lexical_w * lexical) + (recency_w * recency);
        scored.push(RankedContextItem {
            relevance,
            lexical_score,
            idx: i,
        });
    }

    scored.sort_by(|a, b| {
        b.relevance
            .partial_cmp(&a.relevance)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    scored
}

fn passes_relevance_gate(
    item: &ContextItem,
    ranked: RankedContextItem,
    best_relevance: f64,
) -> bool {
    let has_lexical_match = ranked.lexical_score > 0;
    let strong_semantic_match = item
        .distance
        .is_some_and(|distance| distance <= DEFAULT_MAX_DISTANCE_WITHOUT_LEXICAL_MATCH);

    if !has_lexical_match && !strong_semantic_match {
        return false;
    }

    let min_relevance = if has_lexical_match {
        DEFAULT_MIN_RELEVANCE
    } else {
        DEFAULT_MIN_RELEVANCE_WITHOUT_LEXICAL_MATCH
    };
    let relative_floor = (best_relevance * DEFAULT_RELATIVE_RELEVANCE_FLOOR).max(min_relevance);
    ranked.relevance >= relative_floor
}

fn mmr_select_indices(question: &str, candidates: &[ContextItem], max_items: usize) -> Vec<usize> {
    let ranked = rank_context_items(question, candidates);
    let Some(best_relevance) = ranked.first().map(|item| item.relevance) else {
        return Vec::new();
    };

    let eligible_ranked = ranked
        .into_iter()
        .filter(|ranked| passes_relevance_gate(&candidates[ranked.idx], *ranked, best_relevance))
        .collect::<Vec<_>>();
    let max_items = max_items.min(eligible_ranked.len());
    if max_items == 0 {
        return Vec::new();
    }

    let mut selected: Vec<usize> = Vec::new();
    let mut remaining: Vec<usize> = eligible_ranked.iter().map(|ranked| ranked.idx).collect();

    // Start with highest relevance.
    if let Some(first) = remaining.first().copied() {
        selected.push(first);
        remaining.retain(|i| *i != first);
    }

    let relevance_by_idx: std::collections::HashMap<usize, f64> = eligible_ranked
        .into_iter()
        .map(|ranked| (ranked.idx, ranked.relevance))
        .collect();

    while selected.len() < max_items && !remaining.is_empty() {
        let mut best_idx: Option<usize> = None;
        let mut best_score: f64 = f64::NEG_INFINITY;

        for &idx in &remaining {
            let relevance = *relevance_by_idx.get(&idx).unwrap_or(&0.0);
            let mut max_sim = 0.0f64;
            for &sidx in &selected {
                let sim = lite_similarity(&candidates[idx].text, &candidates[sidx].text);
                if sim > max_sim {
                    max_sim = sim;
                }
            }
            let mmr_score =
                (DEFAULT_MMR_LAMBDA * relevance) - ((1.0 - DEFAULT_MMR_LAMBDA) * max_sim);
            if mmr_score > best_score {
                best_score = mmr_score;
                best_idx = Some(idx);
            }
        }

        let Some(chosen) = best_idx else { break };
        selected.push(chosen);
        remaining.retain(|i| *i != chosen);
    }

    selected
}

pub(crate) fn build_contexts_v2(
    question: &str,
    candidates: Vec<ContextItem>,
    top_k: usize,
) -> Vec<String> {
    let max_items = top_k.max(1);
    let selected_indices = mmr_select_indices(question, &candidates, max_items);

    let mut out: Vec<String> = Vec::new();
    let mut seen: std::collections::HashSet<String> = std::collections::HashSet::new();
    let mut used_chars: usize = 0;

    for idx in selected_indices {
        let item = &candidates[idx];
        let Some(text) = render_context_item_for_prompt(question, item) else {
            continue;
        };

        if !seen.insert(text.clone()) {
            continue;
        }

        let len = text.len();
        if used_chars > 0 && used_chars.saturating_add(len) > DEFAULT_MAX_CONTEXT_CHARS {
            break;
        }
        if used_chars == 0 && len > DEFAULT_MAX_CONTEXT_CHARS {
            // Still include one context rather than returning empty.
            out.push(text);
            break;
        }

        used_chars = used_chars.saturating_add(len);
        out.push(text);
    }

    out
}

pub(crate) fn render_context_item_for_prompt(question: &str, item: &ContextItem) -> Option<String> {
    let mut text = compress_context_text(question, &item.text);
    if text.is_empty() {
        return None;
    }

    let prefix = match item.source {
        ContextSource::Message => None,
        ContextSource::TodoThread => Some(format!("TODO_THREAD id={}\n", item.id)),
        ContextSource::Event => Some(format!("EVENT id={}\n", item.id)),
        ContextSource::TodoActivity => Some(format!("TODO_ACTIVITY id={}\n", item.id)),
        ContextSource::AttachmentChunk => Some(format!("ATTACHMENT_CHUNK id={}\n", item.id)),
        ContextSource::ExternalDocument => Some(format!("EXTERNAL_DOCUMENT id={}\n", item.id)),
    };
    if let Some(prefix) = prefix {
        let mut combined = String::with_capacity(prefix.len() + text.len());
        combined.push_str(&prefix);
        combined.push_str(&text);
        text = combined;
    }

    if let Some(suffix) = item.citation_suffix.as_deref() {
        if !suffix.is_empty() && !text.contains(suffix) {
            if !text.is_empty() && !text.ends_with('\n') {
                text.push('\n');
            }
            text.push_str(suffix);
        }
    }

    Some(text)
}

#[cfg(test)]
mod tests {
    use super::{build_contexts_v2, ContextItem, ContextSource};

    #[test]
    fn build_contexts_v2_drops_low_relevance_tail_candidates() {
        let contexts = build_contexts_v2(
            "分析最近的视频开头台词",
            vec![
                ContextItem {
                    source: ContextSource::Message,
                    id: "video-script".to_string(),
                    created_at_ms: 1_800_000_000_000,
                    distance: Some(0.05),
                    text: "分析叁月聚粮最近的视频，尤其是开头部分的台词".to_string(),
                    citation_suffix: None,
                },
                ContextItem {
                    source: ContextSource::Message,
                    id: "github".to_string(),
                    created_at_ms: 1_800_000_000_000,
                    distance: Some(0.8),
                    text: "https://github.com/QwenLM/Qwen3-ASR".to_string(),
                    citation_suffix: None,
                },
                ContextItem {
                    source: ContextSource::TodoThread,
                    id: "todo-work".to_string(),
                    created_at_ms: 1_800_000_000_000,
                    distance: Some(0.85),
                    text: "TODO_THREAD todo_id=1\nTODO [in_progress] 今天上班要穿西装".to_string(),
                    citation_suffix: None,
                },
                ContextItem {
                    source: ContextSource::AttachmentChunk,
                    id: "wav".to_string(),
                    created_at_ms: 1_800_000_000_000,
                    distance: Some(0.9),
                    text: "罗妈.WAV".to_string(),
                    citation_suffix: None,
                },
            ],
            4,
        );

        assert_eq!(contexts.len(), 1);
        assert!(contexts[0].contains("开头部分的台词"));
    }
}
