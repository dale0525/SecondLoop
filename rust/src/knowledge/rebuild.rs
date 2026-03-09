use anyhow::Result;
use rusqlite::{params, Connection, OptionalExtension};

use crate::knowledge::{
    ContentKnowledgeDocument, KnowledgeIndexStatus, KnowledgeUnit, KnowledgeUnitKind,
    KnowledgeVersionSet,
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
    let kind_filter = unit_kind.map(|value| {
        serde_json::to_string(&value)
            .unwrap()
            .trim_matches('"')
            .to_string()
    });
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
