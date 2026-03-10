use std::collections::VecDeque;

use anyhow::Result;
use rusqlite::{params, Connection, OptionalExtension};

use crate::knowledge::{
    ContentKnowledgeDocument, KnowledgeAnchorSet, KnowledgeIndexStatus, KnowledgeUnit,
    KnowledgeUnitKind, KnowledgeVersionSet, KnowledgeViewerDocument, KnowledgeViewerPage,
};

fn decode_document_row(
    _conn: &Connection,
    key: &[u8; 32],
    row: &rusqlite::Row<'_>,
) -> Result<ContentKnowledgeDocument> {
    let document_id: String = row.get(0)?;
    let origin_type_json: String = row.get(1)?;
    let source_kind_json: String = row.get(2)?;
    let role_json: String = row.get(3)?;
    let language: Option<String> = row.get(4)?;
    let quality_score: f64 = row.get(5)?;
    let title: Option<String> = row.get(6)?;
    let summary: Option<String> = row.get(7)?;
    let anchor_json: String = row.get(8)?;
    let raw_blob: Vec<u8> = row.get(9)?;
    let normalized_blob: Vec<u8> = row.get(10)?;
    let created_at_ms: i64 = row.get(11)?;
    let updated_at_ms: i64 = row.get(12)?;
    let versions = KnowledgeVersionSet {
        schema_version: row.get(13)?,
        normalization_version: row.get(14)?,
        segmentation_version: row.get(15)?,
        embedding_policy_version: row.get(16)?,
        retrieval_policy_version: row.get(17)?,
    };
    Ok(ContentKnowledgeDocument {
        document_id: document_id.clone(),
        origin_type: serde_json::from_str(&format!("\"{origin_type_json}\""))?,
        source_kind: serde_json::from_str(&format!("\"{source_kind_json}\""))?,
        role: serde_json::from_str(&format!("\"{role_json}\""))?,
        language,
        quality_score,
        created_at_ms,
        updated_at_ms,
        versions,
        anchors: serde_json::from_str(&anchor_json)?,
        title,
        summary,
        raw_text: crate::db::decode_knowledge_document_text(key, &document_id, "raw", &raw_blob)?,
        normalized_text: crate::db::decode_knowledge_document_text(
            key,
            &document_id,
            "normalized",
            &normalized_blob,
        )?,
    })
}

fn decode_unit_row(key: &[u8; 32], row: &rusqlite::Row<'_>) -> Result<KnowledgeUnit> {
    let unit_id: String = row.get(0)?;
    let document_id: String = row.get(1)?;
    let parent_unit_id: Option<String> = row.get(2)?;
    let unit_kind_json: String = row.get(3)?;
    let source_kind_json: String = row.get(4)?;
    let role_json: String = row.get(5)?;
    let ordinal: i64 = row.get(6)?;
    let token_count: i64 = row.get(7)?;
    let anchor_json: String = row.get(8)?;
    let raw_blob: Vec<u8> = row.get(9)?;
    let normalized_blob: Vec<u8> = row.get(10)?;
    let prev_unit_id: Option<String> = row.get(11)?;
    let next_unit_id: Option<String> = row.get(12)?;
    let created_at_ms: i64 = row.get(13)?;
    let updated_at_ms: i64 = row.get(14)?;
    Ok(KnowledgeUnit {
        unit_id: unit_id.clone(),
        document_id,
        parent_unit_id,
        unit_kind: serde_json::from_str(&format!("\"{unit_kind_json}\""))?,
        source_kind: serde_json::from_str(&format!("\"{source_kind_json}\""))?,
        role: serde_json::from_str(&format!("\"{role_json}\""))?,
        ordinal,
        token_count,
        raw_text: crate::db::decode_knowledge_unit_text(key, &unit_id, "raw", &raw_blob)?,
        normalized_text: crate::db::decode_knowledge_unit_text(
            key,
            &unit_id,
            "normalized",
            &normalized_blob,
        )?,
        anchors: serde_json::from_str(&anchor_json)?,
        prev_unit_id,
        next_unit_id,
        created_at_ms,
        updated_at_ms,
    })
}

pub fn list_knowledge_documents(
    conn: &Connection,
    key: &[u8; 32],
    limit: usize,
    offset: usize,
) -> Result<Vec<ContentKnowledgeDocument>> {
    let mut stmt = conn.prepare(
        r#"SELECT document_id,
                  origin_type,
                  source_kind,
                  role,
                  language,
                  quality_score,
                  title,
                  summary,
                  anchor_json,
                  raw_text,
                  normalized_text,
                  created_at_ms,
                  updated_at_ms,
                  schema_version,
                  normalization_version,
                  segmentation_version,
                  embedding_policy_version,
                  retrieval_policy_version
           FROM knowledge_documents
           ORDER BY updated_at_ms DESC, document_id ASC
           LIMIT ?1 OFFSET ?2"#,
    )?;
    let mut rows = stmt.query(params![limit as i64, offset as i64])?;
    let mut out = Vec::<ContentKnowledgeDocument>::new();
    while let Some(row) = rows.next()? {
        let document = match decode_document_row(conn, key, row) {
            Ok(document) => document,
            Err(_) => continue,
        };
        out.push(document);
    }
    Ok(out)
}

pub fn list_knowledge_units(
    conn: &Connection,
    key: &[u8; 32],
    document_id: &str,
    unit_kind: Option<KnowledgeUnitKind>,
    limit: usize,
    offset: usize,
) -> Result<Vec<KnowledgeUnit>> {
    let kind_filter = unit_kind
        .map(|value| -> Result<String> {
            Ok(serde_json::to_string(&value)?.trim_matches('"').to_string())
        })
        .transpose()?;
    let mut stmt = conn.prepare(
        r#"SELECT unit_id,
                  document_id,
                  parent_unit_id,
                  unit_kind,
                  source_kind,
                  role,
                  ordinal,
                  token_count,
                  anchor_json,
                  raw_text,
                  normalized_text,
                  prev_unit_id,
                  next_unit_id,
                  created_at_ms,
                  updated_at_ms
           FROM knowledge_units
           WHERE document_id = ?1
             AND (?2 IS NULL OR unit_kind = ?2)
           ORDER BY ordinal ASC, unit_id ASC
           LIMIT ?3 OFFSET ?4"#,
    )?;
    let mut rows = stmt.query(params![
        document_id,
        kind_filter,
        limit as i64,
        offset as i64
    ])?;
    let mut out = Vec::<KnowledgeUnit>::new();
    while let Some(row) = rows.next()? {
        let unit = match decode_unit_row(key, row) {
            Ok(unit) => unit,
            Err(_) => continue,
        };
        out.push(unit);
    }
    Ok(out)
}

fn count_knowledge_units(
    conn: &Connection,
    document_id: &str,
    unit_kind: Option<KnowledgeUnitKind>,
) -> Result<i64> {
    let kind_filter = unit_kind
        .map(|value| -> Result<String> {
            Ok(serde_json::to_string(&value)?.trim_matches('"').to_string())
        })
        .transpose()?;
    Ok(conn.query_row(
        r#"SELECT COUNT(*)
           FROM knowledge_units
           WHERE document_id = ?1
             AND (?2 IS NULL OR unit_kind = ?2)"#,
        params![document_id, kind_filter],
        |row| row.get(0),
    )?)
}

pub fn get_knowledge_document(
    conn: &Connection,
    key: &[u8; 32],
    document_id: &str,
) -> Result<Option<ContentKnowledgeDocument>> {
    let mut stmt = conn.prepare(
        r#"SELECT document_id,
                  origin_type,
                  source_kind,
                  role,
                  language,
                  quality_score,
                  title,
                  summary,
                  anchor_json,
                  raw_text,
                  normalized_text,
                  created_at_ms,
                  updated_at_ms,
                  schema_version,
                  normalization_version,
                  segmentation_version,
                  embedding_policy_version,
                  retrieval_policy_version
           FROM knowledge_documents
           WHERE document_id = ?1"#,
    )?;
    let mut rows = stmt.query(params![document_id])?;
    let Some(row) = rows.next()? else {
        return Ok(None);
    };
    Ok(Some(decode_document_row(conn, key, row)?))
}

pub fn read_knowledge_viewer_document(
    conn: &Connection,
    key: &[u8; 32],
    document_id: &str,
) -> Result<KnowledgeViewerDocument> {
    let document = get_knowledge_document(conn, key, document_id)?
        .ok_or_else(|| anyhow::anyhow!("knowledge document not found"))?;
    Ok(KnowledgeViewerDocument {
        document,
        total_units: count_knowledge_units(conn, document_id, None)?,
        section_count: count_knowledge_units(conn, document_id, Some(KnowledgeUnitKind::Section))?,
        chunk_count: count_knowledge_units(conn, document_id, Some(KnowledgeUnitKind::Chunk))?,
    })
}

pub fn list_knowledge_viewer_units(
    conn: &Connection,
    key: &[u8; 32],
    document_id: &str,
    unit_kind: Option<KnowledgeUnitKind>,
    limit: usize,
    offset: usize,
) -> Result<KnowledgeViewerPage> {
    let total = count_knowledge_units(conn, document_id, unit_kind)?;
    let units = list_knowledge_units(conn, key, document_id, unit_kind, limit, offset)?;
    Ok(KnowledgeViewerPage {
        document_id: document_id.to_string(),
        unit_kind,
        offset: offset as i64,
        limit: limit as i64,
        total,
        units,
    })
}

fn anchor_match_score(query: &KnowledgeAnchorSet, candidate: &KnowledgeAnchorSet) -> i64 {
    let mut score = 0i64;
    if let Some(message_id) = query.message_id.as_deref() {
        if candidate.message_id.as_deref() == Some(message_id) {
            score += 5;
        }
    }
    if let Some(conversation_id) = query.conversation_id.as_deref() {
        if candidate.conversation_id.as_deref() == Some(conversation_id) {
            score += 3;
        }
    }
    if let Some(attachment_sha256) = query.attachment_sha256.as_deref() {
        if candidate.attachment_sha256.as_deref() == Some(attachment_sha256) {
            score += 5;
        }
    }
    if let Some(page_index) = query.page_index {
        if candidate.page_index == Some(page_index) {
            score += 4;
        }
    }
    if let Some(frame_index) = query.frame_index {
        if candidate.frame_index == Some(frame_index) {
            score += 4;
        }
    }
    if let Some(start_ms) = query.start_ms {
        let candidate_start = candidate.start_ms.unwrap_or(i64::MIN);
        let candidate_end = candidate.end_ms.unwrap_or(candidate_start);
        if start_ms >= candidate_start && start_ms <= candidate_end {
            score += 4;
        }
    }
    if let Some(end_ms) = query.end_ms {
        let candidate_start = candidate.start_ms.unwrap_or(i64::MIN);
        let candidate_end = candidate.end_ms.unwrap_or(candidate_start);
        if end_ms >= candidate_start && end_ms <= candidate_end {
            score += 4;
        }
    }
    if let Some(speaker) = query.speaker.as_deref() {
        if candidate.speaker.as_deref() == Some(speaker) {
            score += 4;
        }
    }
    if let Some(section_label) = query.section_label.as_deref() {
        if candidate.section_label.as_deref() == Some(section_label) {
            score += 4;
        }
    }
    if let Some(source_filename) = query.source_filename.as_deref() {
        if candidate.source_filename.as_deref() == Some(source_filename) {
            score += 2;
        }
    }
    score
}

fn unit_kind_rank(unit_kind: KnowledgeUnitKind) -> i64 {
    match unit_kind {
        KnowledgeUnitKind::Chunk => 3,
        KnowledgeUnitKind::Section => 2,
        KnowledgeUnitKind::Segment => 1,
    }
}

pub fn list_knowledge_units_around_anchor(
    conn: &Connection,
    key: &[u8; 32],
    document_id: &str,
    anchor: &KnowledgeAnchorSet,
    before: usize,
    after: usize,
) -> Result<Vec<KnowledgeUnit>> {
    const PAGE_SIZE: usize = 256;

    let mut recent = VecDeque::<KnowledgeUnit>::with_capacity(before);
    let mut best_before = Vec::<KnowledgeUnit>::new();
    let mut best_after = Vec::<KnowledgeUnit>::new();
    let mut best_unit = None::<KnowledgeUnit>;
    let mut best_score = 0i64;
    let mut best_kind_rank = 0i64;
    let mut best_index = 0usize;
    let mut remaining_after = 0usize;

    let mut offset = 0usize;
    let mut index = 0usize;
    loop {
        let page = list_knowledge_units(conn, key, document_id, None, PAGE_SIZE, offset)?;
        if page.is_empty() {
            break;
        }
        let count = page.len();
        for unit in page {
            let score = anchor_match_score(anchor, &unit.anchors);
            let kind_rank = unit_kind_rank(unit.unit_kind);
            let is_better = score > best_score
                || (score == best_score && kind_rank > best_kind_rank)
                || (score == best_score && kind_rank == best_kind_rank && index > best_index);
            if is_better {
                best_score = score;
                best_kind_rank = kind_rank;
                best_index = index;
                best_unit = Some(unit.clone());
                best_before = recent.iter().cloned().collect();
                best_after.clear();
                remaining_after = after;
            } else if best_unit.is_some() && remaining_after > 0 && index > best_index {
                best_after.push(unit.clone());
                remaining_after = remaining_after.saturating_sub(1);
            }

            if before > 0 {
                if recent.len() == before {
                    recent.pop_front();
                }
                recent.push_back(unit);
            }

            index += 1;
        }
        if count < PAGE_SIZE {
            break;
        }
        offset += count;
    }

    let Some(best_unit) = best_unit else {
        return Ok(Vec::new());
    };
    if best_score <= 0 {
        return Ok(Vec::new());
    }
    let mut out = best_before;
    out.push(best_unit);
    out.extend(best_after);
    Ok(out)
}

pub fn cancel_knowledge_rebuild(conn: &Connection, _key: &[u8; 32]) -> Result<()> {
    conn.execute(
        "UPDATE knowledge_rebuild_state SET cancel_requested = 1 WHERE state_key = 1",
        [],
    )?;
    Ok(())
}

pub fn read_knowledge_index_status(
    conn: &Connection,
    _key: &[u8; 32],
) -> Result<KnowledgeIndexStatus> {
    let row = conn
        .query_row(
            r#"SELECT knowledge_schema_version,
                      normalization_version,
                      segmentation_version,
                      embedding_policy_version,
                      retrieval_policy_version,
                      last_indexed_model_name,
                      last_indexed_dim,
                      status,
                      rebuild_required,
                      stale_reason,
                      last_error,
                      last_rebuild_started_at_ms,
                      last_rebuild_completed_at_ms,
                      current_document_id,
                      current_stage,
                      documents_indexed,
                      units_indexed,
                      embeddings_indexed,
                      total_documents
               FROM knowledge_rebuild_state
               WHERE state_key = 1"#,
            [],
            |row| {
                Ok((
                    row.get::<_, i64>(0)?,
                    row.get::<_, i64>(1)?,
                    row.get::<_, i64>(2)?,
                    row.get::<_, i64>(3)?,
                    row.get::<_, i64>(4)?,
                    row.get::<_, Option<String>>(5)?,
                    row.get::<_, Option<i64>>(6)?,
                    row.get::<_, String>(7)?,
                    row.get::<_, i64>(8)?,
                    row.get::<_, Option<String>>(9)?,
                    row.get::<_, Option<String>>(10)?,
                    row.get::<_, Option<i64>>(11)?,
                    row.get::<_, Option<i64>>(12)?,
                    row.get::<_, Option<String>>(13)?,
                    row.get::<_, Option<String>>(14)?,
                    row.get::<_, i64>(15)?,
                    row.get::<_, i64>(16)?,
                    row.get::<_, i64>(17)?,
                    row.get::<_, i64>(18)?,
                ))
            },
        )
        .optional()?;

    let Some((
        schema_version,
        normalization_version,
        segmentation_version,
        embedding_policy_version,
        retrieval_policy_version,
        last_indexed_model_name,
        last_indexed_dim,
        mut status,
        rebuild_required,
        mut stale_reason,
        last_error,
        last_rebuild_started_at_ms,
        last_rebuild_completed_at_ms,
        current_document_id,
        current_stage,
        documents_indexed,
        units_indexed,
        embeddings_indexed,
        total_documents,
    )) = row
    else {
        return Ok(KnowledgeIndexStatus {
            status: "empty".to_string(),
            rebuild_required: false,
            stale_reason: None,
            last_error: None,
            last_rebuild_started_at_ms: None,
            last_rebuild_completed_at_ms: None,
            current_document_id: None,
            current_stage: None,
            documents_indexed: 0,
            units_indexed: 0,
            embeddings_indexed: 0,
            total_documents: 0,
            last_indexed_model_name: None,
            last_indexed_dim: None,
            versions: KnowledgeVersionSet::current(),
        });
    };

    let versions = KnowledgeVersionSet {
        schema_version,
        normalization_version,
        segmentation_version,
        embedding_policy_version,
        retrieval_policy_version,
    };
    let current_versions = KnowledgeVersionSet::current();
    let (current_model_name, current_dim) = crate::db::read_knowledge_embedding_model_state(conn)?;
    let version_mismatch = versions != current_versions;
    let model_mismatch = last_indexed_model_name
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(|value| value != current_model_name)
        .unwrap_or(false)
        || last_indexed_dim
            .map(|value| value != current_dim)
            .unwrap_or(false);
    let preserve_runtime_status = matches!(
        status.as_str(),
        "requested" | "running" | "failed" | "cancelled"
    );
    if (version_mismatch || model_mismatch) && !preserve_runtime_status {
        status = "stale".to_string();
        if stale_reason.is_none() {
            stale_reason = Some(if version_mismatch {
                "version_mismatch".to_string()
            } else {
                "embedding_model_changed".to_string()
            });
        }
    }

    Ok(KnowledgeIndexStatus {
        status,
        rebuild_required: rebuild_required != 0 || version_mismatch || model_mismatch,
        stale_reason,
        last_error,
        last_rebuild_started_at_ms,
        last_rebuild_completed_at_ms,
        current_document_id,
        current_stage,
        documents_indexed,
        units_indexed,
        embeddings_indexed,
        total_documents,
        last_indexed_model_name,
        last_indexed_dim,
        versions,
    })
}
