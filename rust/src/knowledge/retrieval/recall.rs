use std::collections::{BTreeMap, BTreeSet, HashMap};

use anyhow::Result;
use rusqlite::{params, Connection};
use sha2::{Digest, Sha256};

use crate::knowledge::embedding_batch::{
    average_piece_embeddings, prepare_embedding_inputs, EmbeddingBatchPolicy,
};
use crate::knowledge::{KnowledgeRetrievalLayer, KnowledgeUnitKind};

use super::query::{normalized_text_for_matching, NormalizedRetrievalRequest};
use super::{load_document_units, load_scoped_documents, KnowledgeCandidate};

fn deterministic_embedding(text: &str, dim: usize) -> Vec<f32> {
    let dim = dim.max(8);
    let mut vector = vec![0f32; dim];
    for token in text.split_whitespace() {
        let hash = Sha256::digest(token.as_bytes());
        let index = usize::from(hash[0]) % dim;
        let sign = if hash[1] % 2 == 0 { 1.0 } else { -1.0 };
        vector[index] += sign;
    }
    let norm = vector.iter().map(|value| value * value).sum::<f32>().sqrt();
    if norm > 0.0 {
        for value in &mut vector {
            *value /= norm;
        }
    }
    vector
}

fn merged_deterministic_embedding(
    text: &str,
    dim: usize,
    policy: EmbeddingBatchPolicy,
) -> Vec<f32> {
    let prepared = prepare_embedding_inputs(&[text.to_string()], policy);
    let pieces = prepared
        .into_iter()
        .map(|input| deterministic_embedding(&input.text, dim))
        .collect::<Vec<_>>();
    average_piece_embeddings(vec![pieces], 1)
        .into_iter()
        .next()
        .unwrap_or_default()
}

fn lexical_score(query: &str, candidate: &str) -> f64 {
    if query.trim().is_empty() || candidate.trim().is_empty() {
        return 0.0;
    }
    let query_norm = normalized_text_for_matching(query);
    let candidate_norm = normalized_text_for_matching(candidate);
    if query_norm.is_empty() || candidate_norm.is_empty() {
        return 0.0;
    }

    let mut raw = 0u64;
    if candidate_norm == query_norm {
        raw = raw.saturating_add(10_000);
    }
    if candidate_norm.contains(&query_norm) {
        raw = raw.saturating_add(500 + (query_norm.chars().count() as u64 * 50));
    }
    for token in query_norm.split_whitespace() {
        if token.len() < 2 {
            continue;
        }
        if candidate_norm.contains(token) {
            raw = raw.saturating_add(token.chars().count() as u64 * 220);
        }
    }
    if raw == 0 {
        0.0
    } else {
        let value = raw as f64;
        (value / (value + 4000.0)).clamp(0.0, 1.0)
    }
}

fn cosine_similarity(left: &[f32], right: &[f32]) -> f64 {
    if left.is_empty() || right.is_empty() || left.len() != right.len() {
        return 0.0;
    }
    let dot = left
        .iter()
        .zip(right.iter())
        .map(|(l, r)| f64::from(*l) * f64::from(*r))
        .sum::<f64>();
    dot.max(0.0)
}

fn load_embedding_map(
    conn: &Connection,
    target_kind: &str,
    target_ids: &BTreeSet<String>,
) -> Result<HashMap<String, Vec<f32>>> {
    let mut stmt = conn.prepare(
        r#"SELECT target_id, embedding_json
           FROM knowledge_embeddings
           WHERE target_kind = ?1"#,
    )?;
    let mut rows = stmt.query(params![target_kind])?;
    let mut out = HashMap::<String, Vec<f32>>::new();
    while let Some(row) = rows.next()? {
        let target_id: String = row.get(0)?;
        if !target_ids.is_empty() && !target_ids.contains(&target_id) {
            continue;
        }
        let embedding_json: String = row.get(1)?;
        let embedding = serde_json::from_str::<Vec<f32>>(&embedding_json).unwrap_or_default();
        if !embedding.is_empty() {
            out.insert(target_id, embedding);
        }
    }
    Ok(out)
}

pub(crate) fn recall_knowledge_candidates(
    conn: &Connection,
    key: &[u8; 32],
    request: &NormalizedRetrievalRequest,
) -> Result<Vec<KnowledgeCandidate>> {
    if request.normalized_query.trim().is_empty() {
        return Ok(Vec::new());
    }

    let documents = load_scoped_documents(conn, key, request)?;
    if documents.is_empty() {
        return Ok(Vec::new());
    }

    let query_vector = merged_deterministic_embedding(
        &request.normalized_query,
        64,
        EmbeddingBatchPolicy::default(),
    );

    let document_ids = documents
        .iter()
        .map(|document| document.document_id.clone())
        .collect::<BTreeSet<_>>();
    let document_embeddings = load_embedding_map(conn, "document", &document_ids)?;

    let mut document_candidates = Vec::<KnowledgeCandidate>::new();
    for document in &documents {
        let combined_text = format!(
            "{}\n{}\n{}",
            document.title.clone().unwrap_or_default(),
            document.summary.clone().unwrap_or_default(),
            document.normalized_text
        );
        let lexical = lexical_score(&request.normalized_query, &combined_text);
        let semantic = document_embeddings
            .get(&document.document_id)
            .map(|embedding| cosine_similarity(&query_vector, embedding))
            .unwrap_or(0.0);
        if lexical > 0.0 || semantic > 0.0 {
            document_candidates.push(KnowledgeCandidate::from_document(
                document, semantic, lexical,
            ));
        }
    }

    let top_document_ids = document_candidates
        .iter()
        .cloned()
        .map(|candidate| {
            (
                candidate.document.document_id.clone(),
                candidate.semantic_score.max(candidate.lexical_score),
            )
        })
        .collect::<Vec<_>>();
    let mut top_document_ids = top_document_ids;
    top_document_ids.sort_by(|left, right| {
        right
            .1
            .partial_cmp(&left.1)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| left.0.cmp(&right.0))
    });
    let selected_document_ids = top_document_ids
        .into_iter()
        .take(request.candidate_limit.max(request.top_k))
        .map(|(document_id, _)| document_id)
        .collect::<BTreeSet<_>>();

    let mut unit_ids = BTreeSet::<String>::new();
    let mut section_units = Vec::<(
        crate::knowledge::ContentKnowledgeDocument,
        crate::knowledge::KnowledgeUnit,
    )>::new();
    let mut chunk_units = Vec::<(
        crate::knowledge::ContentKnowledgeDocument,
        crate::knowledge::KnowledgeUnit,
    )>::new();
    for document in &documents {
        if !selected_document_ids.contains(&document.document_id) {
            continue;
        }
        for unit in
            load_document_units(conn, key, &document.document_id, KnowledgeUnitKind::Section)?
        {
            unit_ids.insert(unit.unit_id.clone());
            section_units.push((document.clone(), unit));
        }
        for unit in load_document_units(conn, key, &document.document_id, KnowledgeUnitKind::Chunk)?
        {
            unit_ids.insert(unit.unit_id.clone());
            chunk_units.push((document.clone(), unit));
        }
    }

    let unit_embeddings = load_embedding_map(conn, "unit", &unit_ids)?;
    let mut section_candidates = Vec::<KnowledgeCandidate>::new();
    for (document, unit) in &section_units {
        let lexical = lexical_score(&request.normalized_query, &unit.normalized_text);
        let semantic = unit_embeddings
            .get(&unit.unit_id)
            .map(|embedding| cosine_similarity(&query_vector, embedding))
            .unwrap_or(0.0);
        if lexical > 0.0 || semantic > 0.0 {
            section_candidates.push(KnowledgeCandidate::from_unit(
                document,
                unit,
                KnowledgeRetrievalLayer::Section,
                semantic,
                lexical,
            ));
        }
    }

    let mut chunk_candidates = Vec::<KnowledgeCandidate>::new();
    for (document, unit) in &chunk_units {
        let lexical = lexical_score(&request.normalized_query, &unit.normalized_text);
        let semantic = unit_embeddings
            .get(&unit.unit_id)
            .map(|embedding| cosine_similarity(&query_vector, embedding))
            .unwrap_or(0.0);
        if lexical > 0.0 || semantic > 0.0 {
            chunk_candidates.push(KnowledgeCandidate::from_unit(
                document,
                unit,
                KnowledgeRetrievalLayer::Chunk,
                semantic,
                lexical,
            ));
        }
    }

    let mut merged = BTreeMap::<String, KnowledgeCandidate>::new();
    let per_layer_budget = (request.candidate_limit.max(6) / 3).max(2);
    for layer_candidates in [&document_candidates, &section_candidates, &chunk_candidates] {
        let mut semantic_ranked = layer_candidates.to_vec();
        semantic_ranked.sort_by(|left, right| {
            right
                .semantic_score
                .partial_cmp(&left.semantic_score)
                .unwrap_or(std::cmp::Ordering::Equal)
                .then_with(|| {
                    right
                        .lexical_score
                        .partial_cmp(&left.lexical_score)
                        .unwrap_or(std::cmp::Ordering::Equal)
                })
        });
        for candidate in semantic_ranked
            .into_iter()
            .filter(|candidate| candidate.semantic_score > 0.0)
            .take(per_layer_budget)
        {
            merged.entry(candidate.key()).or_insert(candidate);
        }

        let mut lexical_ranked = layer_candidates.to_vec();
        lexical_ranked.sort_by(|left, right| {
            right
                .lexical_score
                .partial_cmp(&left.lexical_score)
                .unwrap_or(std::cmp::Ordering::Equal)
                .then_with(|| {
                    right
                        .semantic_score
                        .partial_cmp(&left.semantic_score)
                        .unwrap_or(std::cmp::Ordering::Equal)
                })
        });
        for candidate in lexical_ranked
            .into_iter()
            .filter(|candidate| candidate.lexical_score > 0.0)
            .take(per_layer_budget)
        {
            merged.entry(candidate.key()).or_insert(candidate);
        }
    }

    let mut out = merged.into_values().collect::<Vec<_>>();
    out.sort_by(|left, right| {
        right
            .semantic_score
            .max(right.lexical_score)
            .partial_cmp(&left.semantic_score.max(left.lexical_score))
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| right.layer.cmp(&left.layer))
    });
    Ok(out)
}
