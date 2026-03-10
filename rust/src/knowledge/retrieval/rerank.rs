use std::collections::{BTreeMap, HashMap, HashSet};

use anyhow::Result;
use rusqlite::Connection;

use crate::knowledge::{KnowledgeRetrievalLayer, KnowledgeRole, KnowledgeUnit, KnowledgeUnitKind};

use super::query::{normalized_text_for_matching, NormalizedRetrievalRequest};
use super::{load_document_units, KnowledgeCandidate};

fn role_weight(role: KnowledgeRole) -> f64 {
    match role {
        KnowledgeRole::Evidence => 1.0,
        KnowledgeRole::Body => 0.92,
        KnowledgeRole::Caption => 0.84,
        KnowledgeRole::Summary => 0.68,
        KnowledgeRole::Title => 0.58,
        KnowledgeRole::Metadata => 0.24,
    }
}

fn text_similarity(left: &str, right: &str) -> f64 {
    let left_tokens = normalized_text_for_matching(left)
        .split_whitespace()
        .map(str::to_string)
        .collect::<HashSet<_>>();
    let right_tokens = normalized_text_for_matching(right)
        .split_whitespace()
        .map(str::to_string)
        .collect::<HashSet<_>>();
    if left_tokens.is_empty() || right_tokens.is_empty() {
        return 0.0;
    }
    let intersection = left_tokens.intersection(&right_tokens).count() as f64;
    let union = left_tokens.union(&right_tokens).count() as f64;
    if union <= 0.0 {
        0.0
    } else {
        (intersection / union).clamp(0.0, 1.0)
    }
}

fn base_score(candidate: &KnowledgeCandidate, newest_ms: i64) -> f64 {
    let recency = if newest_ms <= 0 {
        1.0
    } else {
        (candidate.updated_at_ms() as f64 / newest_ms as f64).clamp(0.0, 1.0)
    };
    (candidate.semantic_score * 0.45)
        + (candidate.lexical_score * 0.25)
        + (role_weight(candidate.role) * 0.15)
        + (candidate.document.quality_score * 0.05)
        + (recency * 0.10)
        + candidate.expansion_score
}

fn inject_candidate(
    pool: &mut BTreeMap<String, KnowledgeCandidate>,
    candidate: KnowledgeCandidate,
) {
    pool.entry(candidate.key())
        .and_modify(|existing| {
            if candidate.score > existing.score {
                *existing = candidate.clone();
            }
        })
        .or_insert(candidate);
}

fn neighbor_candidate(
    document: &crate::knowledge::ContentKnowledgeDocument,
    unit: &KnowledgeUnit,
) -> KnowledgeCandidate {
    let mut candidate =
        KnowledgeCandidate::from_unit(document, unit, KnowledgeRetrievalLayer::Chunk, 0.0, 0.0);
    candidate.expansion_score = 0.18;
    candidate.score = 0.18;
    candidate
}

fn section_candidate(
    document: &crate::knowledge::ContentKnowledgeDocument,
    unit: &KnowledgeUnit,
) -> KnowledgeCandidate {
    let mut candidate =
        KnowledgeCandidate::from_unit(document, unit, KnowledgeRetrievalLayer::Section, 0.0, 0.0);
    candidate.expansion_score = 0.12;
    candidate.score = 0.12;
    candidate
}

pub(crate) fn rerank_knowledge_candidates(
    conn: &Connection,
    key: &[u8; 32],
    request: &NormalizedRetrievalRequest,
    candidates: Vec<KnowledgeCandidate>,
) -> Result<Vec<KnowledgeCandidate>> {
    if candidates.is_empty() {
        return Ok(Vec::new());
    }

    let newest_ms = candidates
        .iter()
        .map(KnowledgeCandidate::updated_at_ms)
        .max()
        .unwrap_or(0);
    let mut seeds = candidates;
    seeds.sort_by(|left, right| {
        base_score(right, newest_ms)
            .partial_cmp(&base_score(left, newest_ms))
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    let mut pool = BTreeMap::<String, KnowledgeCandidate>::new();
    for candidate in &seeds {
        let mut candidate = candidate.clone();
        candidate.score = base_score(&candidate, newest_ms);
        inject_candidate(&mut pool, candidate);
    }

    let mut chunk_cache = HashMap::<String, Vec<KnowledgeUnit>>::new();
    let mut section_cache = HashMap::<String, Vec<KnowledgeUnit>>::new();
    for candidate in seeds.iter().take(request.top_k.max(1)) {
        if candidate.unit_kind != Some(KnowledgeUnitKind::Chunk) {
            continue;
        }
        let document_id = candidate.document.document_id.clone();
        let chunks = if let Some(cached) = chunk_cache.get(&document_id) {
            cached.clone()
        } else {
            let loaded = load_document_units(conn, key, &document_id, KnowledgeUnitKind::Chunk)?;
            chunk_cache.insert(document_id.clone(), loaded.clone());
            loaded
        };
        let sections = if let Some(cached) = section_cache.get(&document_id) {
            cached.clone()
        } else {
            let loaded = load_document_units(conn, key, &document_id, KnowledgeUnitKind::Section)?;
            section_cache.insert(document_id.clone(), loaded.clone());
            loaded
        };
        let Some(unit_id) = candidate.unit_id.as_deref() else {
            continue;
        };
        let Some(current_chunk) = chunks.iter().find(|unit| unit.unit_id == unit_id) else {
            continue;
        };
        if let Some(prev_id) = current_chunk.prev_unit_id.as_deref() {
            if let Some(prev_chunk) = chunks.iter().find(|unit| unit.unit_id == prev_id) {
                inject_candidate(
                    &mut pool,
                    neighbor_candidate(&candidate.document, prev_chunk),
                );
            }
        }
        if let Some(next_id) = current_chunk.next_unit_id.as_deref() {
            if let Some(next_chunk) = chunks.iter().find(|unit| unit.unit_id == next_id) {
                inject_candidate(
                    &mut pool,
                    neighbor_candidate(&candidate.document, next_chunk),
                );
            }
        }
        if let Some(section) = sections
            .iter()
            .min_by_key(|section| (section.ordinal - current_chunk.ordinal).abs())
        {
            inject_candidate(&mut pool, section_candidate(&candidate.document, section));
        }
    }

    let mut remaining = pool.into_values().collect::<Vec<_>>();
    let mut selected = Vec::<KnowledgeCandidate>::new();
    while !remaining.is_empty() && selected.len() < request.candidate_limit {
        let mut best_index = None;
        let mut best_score = f64::NEG_INFINITY;
        for (index, candidate) in remaining.iter().enumerate() {
            let redundancy = selected
                .iter()
                .map(|chosen| text_similarity(&candidate.normalized_text, &chosen.normalized_text))
                .fold(0.0, f64::max);
            let score = base_score(candidate, newest_ms) - (redundancy * 0.25);
            if score > best_score {
                best_score = score;
                best_index = Some(index);
            }
        }
        let Some(index) = best_index else { break };
        let mut chosen = remaining.swap_remove(index);
        chosen.score = best_score;
        if selected
            .iter()
            .any(|existing| existing.key() == chosen.key())
        {
            continue;
        }
        selected.push(chosen);
    }

    selected.sort_by(|left, right| {
        right
            .score
            .partial_cmp(&left.score)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| right.layer.cmp(&left.layer))
    });
    Ok(selected)
}
