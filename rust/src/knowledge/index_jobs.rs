use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{anyhow, Result};
use rusqlite::{params, Connection};
use sha2::{Digest, Sha256};

use crate::knowledge::embedding_batch::{batch_embedding_inputs, EmbeddingBatchPolicy};
use crate::knowledge::{
    build_chunk_units, build_section_units, build_segment_units, list_knowledge_units,
    normalize_text_for_source, segment_document_text, visit_source_knowledge_documents,
    ContentKnowledgeDocument, KnowledgeUnit, KnowledgeUnitKind, KnowledgeVersionSet, SegmentDraft,
};

const JOB_STAGES: &[&str] = &["normalize", "segment", "chunk", "embed", "finalize"];

fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|value| value.as_millis().min(i64::MAX as u128) as i64)
        .unwrap_or(0)
}

fn upsert_document(
    conn: &Connection,
    key: &[u8; 32],
    document: &ContentKnowledgeDocument,
) -> Result<()> {
    conn.execute(
        r#"INSERT INTO knowledge_documents(
               document_id,
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
               retrieval_policy_version,
               last_indexed_at_ms
           ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19)
           ON CONFLICT(document_id) DO UPDATE SET
               origin_type = excluded.origin_type,
               source_kind = excluded.source_kind,
               role = excluded.role,
               language = excluded.language,
               quality_score = excluded.quality_score,
               title = excluded.title,
               summary = excluded.summary,
               anchor_json = excluded.anchor_json,
               raw_text = excluded.raw_text,
               normalized_text = excluded.normalized_text,
               created_at_ms = excluded.created_at_ms,
               updated_at_ms = excluded.updated_at_ms,
               schema_version = excluded.schema_version,
               normalization_version = excluded.normalization_version,
               segmentation_version = excluded.segmentation_version,
               embedding_policy_version = excluded.embedding_policy_version,
               retrieval_policy_version = excluded.retrieval_policy_version,
               last_indexed_at_ms = excluded.last_indexed_at_ms"#,
        params![
            document.document_id,
            serde_json::to_string(&document.origin_type)?.trim_matches('"').to_string(),
            serde_json::to_string(&document.source_kind)?.trim_matches('"').to_string(),
            serde_json::to_string(&document.role)?.trim_matches('"').to_string(),
            document.language,
            document.quality_score,
            document.title,
            document.summary,
            serde_json::to_string(&document.anchors)?,
            crate::db::encode_knowledge_document_text(key, &document.document_id, "raw", &document.raw_text)?,
            crate::db::encode_knowledge_document_text(
                key,
                &document.document_id,
                "normalized",
                &document.normalized_text,
            )?,
            document.created_at_ms,
            document.updated_at_ms,
            document.versions.schema_version,
            document.versions.normalization_version,
            document.versions.segmentation_version,
            document.versions.embedding_policy_version,
            document.versions.retrieval_policy_version,
            Option::<i64>::None,
        ],
    )?;
    Ok(())
}

fn with_immediate_transaction<T>(conn: &Connection, f: impl FnOnce() -> Result<T>) -> Result<T> {
    conn.execute_batch("BEGIN IMMEDIATE;")?;
    match f() {
        Ok(value) => {
            conn.execute_batch("COMMIT;")?;
            Ok(value)
        }
        Err(error) => {
            let _ = conn.execute_batch("ROLLBACK;");
            Err(error)
        }
    }
}

fn unit_kind_name(unit_kind: KnowledgeUnitKind) -> Result<String> {
    Ok(serde_json::to_string(&unit_kind)?
        .trim_matches('"')
        .to_string())
}

fn insert_units(conn: &Connection, key: &[u8; 32], units: &[KnowledgeUnit]) -> Result<()> {
    for unit in units {
        conn.execute(
            r#"INSERT INTO knowledge_units(
                   unit_id,
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
               ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15)"#,
            params![
                unit.unit_id,
                unit.document_id,
                unit.parent_unit_id,
                unit_kind_name(unit.unit_kind)?,
                serde_json::to_string(&unit.source_kind)?
                    .trim_matches('"')
                    .to_string(),
                serde_json::to_string(&unit.role)?
                    .trim_matches('"')
                    .to_string(),
                unit.ordinal,
                unit.token_count,
                serde_json::to_string(&unit.anchors)?,
                crate::db::encode_knowledge_unit_text(key, &unit.unit_id, "raw", &unit.raw_text)?,
                crate::db::encode_knowledge_unit_text(
                    key,
                    &unit.unit_id,
                    "normalized",
                    &unit.normalized_text,
                )?,
                unit.prev_unit_id,
                unit.next_unit_id,
                unit.created_at_ms,
                unit.updated_at_ms,
            ],
        )?;
    }
    Ok(())
}

fn replace_units(
    conn: &Connection,
    key: &[u8; 32],
    document_id: &str,
    units: &[KnowledgeUnit],
) -> Result<()> {
    conn.execute(
        "DELETE FROM knowledge_units WHERE document_id = ?1",
        params![document_id],
    )?;
    insert_units(conn, key, units)
}

fn replace_units_of_kind(
    conn: &Connection,
    key: &[u8; 32],
    document_id: &str,
    unit_kind: KnowledgeUnitKind,
    units: &[KnowledgeUnit],
) -> Result<()> {
    conn.execute(
        "DELETE FROM knowledge_units WHERE document_id = ?1 AND unit_kind = ?2",
        params![document_id, unit_kind_name(unit_kind)?],
    )?;
    insert_units(conn, key, units)
}

// TODO(knowledge-phase2): Replace this Phase 1 placeholder with actual embedder calls
// before retrieval reads from `knowledge_embeddings`. The deterministic vector
// keeps the staged rebuild/storage pipeline testable in Phase 1 without yet
// coupling foundation work to provider selection, model warmup, or network I/O.
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

fn store_embeddings_for_document(
    conn: &Connection,
    document: &ContentKnowledgeDocument,
    section_units: &[KnowledgeUnit],
    chunk_units: &[KnowledgeUnit],
) -> Result<usize> {
    let (model_name, dim) = crate::db::read_knowledge_embedding_model_state(conn)?;
    let policy = EmbeddingBatchPolicy::default();
    let mut total = 0usize;

    let doc_inputs =
        batch_embedding_inputs(std::slice::from_ref(&document.normalized_text), policy);
    for batch in doc_inputs {
        for text in batch {
            conn.execute(
                r#"INSERT OR REPLACE INTO knowledge_embeddings(
                       target_kind, target_id, unit_kind, model_name, dim, embedding_json, created_at_ms, updated_at_ms
                   ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)"#,
                params![
                    "document",
                    document.document_id,
                    Option::<String>::None,
                    model_name,
                    dim,
                    serde_json::to_string(&deterministic_embedding(&text, dim as usize))?,
                    now_ms(),
                    now_ms(),
                ],
            )?;
            total += 1;
        }
    }

    for unit in section_units.iter().chain(chunk_units.iter()) {
        let kind_name = serde_json::to_string(&unit.unit_kind)?
            .trim_matches('"')
            .to_string();
        for batch in batch_embedding_inputs(std::slice::from_ref(&unit.normalized_text), policy) {
            for text in batch {
                conn.execute(
                    r#"INSERT OR REPLACE INTO knowledge_embeddings(
                           target_kind, target_id, unit_kind, model_name, dim, embedding_json, created_at_ms, updated_at_ms
                       ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)"#,
                    params![
                        "unit",
                        unit.unit_id,
                        kind_name,
                        model_name,
                        dim,
                        serde_json::to_string(&deterministic_embedding(&text, dim as usize))?,
                        now_ms(),
                        now_ms(),
                    ],
                )?;
                total += 1;
            }
        }
    }

    Ok(total)
}

fn queue_jobs_for_document(conn: &Connection, document_id: &str) -> Result<()> {
    let now = now_ms();
    for stage in JOB_STAGES {
        conn.execute(
            r#"INSERT OR REPLACE INTO knowledge_index_jobs(
                   document_id, stage, status, attempts, next_retry_at_ms, last_error, created_at_ms, updated_at_ms
               ) VALUES (?1, ?2, 'pending', 0, NULL, NULL, ?3, ?3)"#,
            params![document_id, stage, now],
        )?;
    }
    Ok(())
}

fn initialize_rebuild(conn: &Connection, key: &[u8; 32]) -> Result<()> {
    with_immediate_transaction(conn, || {
        crate::db::reset_knowledge_index(conn)?;
        let rebuild_started_at_ms = now_ms();
        let mut total_documents = 0i64;
        visit_source_knowledge_documents(conn, key, |mut document| {
            document.versions = KnowledgeVersionSet::current();
            upsert_document(conn, key, &document)?;
            queue_jobs_for_document(conn, &document.document_id)?;
            total_documents += 1;
            Ok(())
        })?;
        conn.execute(
            r#"UPDATE knowledge_rebuild_state
               SET status = 'running',
                   rebuild_required = 0,
                   stale_reason = NULL,
                   last_error = NULL,
                   last_rebuild_started_at_ms = ?1,
                   current_document_id = NULL,
                   current_stage = NULL,
                   documents_indexed = 0,
                   units_indexed = 0,
                   embeddings_indexed = 0,
                   total_documents = ?2,
                   cancel_requested = 0
               WHERE state_key = 1"#,
            params![rebuild_started_at_ms, total_documents],
        )?;
        Ok(())
    })
}

fn segment_drafts_from_units(units: &[KnowledgeUnit]) -> Vec<SegmentDraft> {
    units
        .iter()
        .map(|unit| SegmentDraft {
            ordinal: unit.ordinal,
            text: unit.normalized_text.clone(),
            role: unit.role,
            anchors: unit.anchors.clone(),
        })
        .collect()
}

fn document_by_id(
    conn: &Connection,
    key: &[u8; 32],
    document_id: &str,
) -> Result<ContentKnowledgeDocument> {
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
    let row = stmt.query_row(params![document_id], |row| {
        Ok((
            row.get::<_, String>(0)?,
            row.get::<_, String>(1)?,
            row.get::<_, String>(2)?,
            row.get::<_, String>(3)?,
            row.get::<_, Option<String>>(4)?,
            row.get::<_, f64>(5)?,
            row.get::<_, Option<String>>(6)?,
            row.get::<_, Option<String>>(7)?,
            row.get::<_, String>(8)?,
            row.get::<_, Vec<u8>>(9)?,
            row.get::<_, Vec<u8>>(10)?,
            row.get::<_, i64>(11)?,
            row.get::<_, i64>(12)?,
            row.get::<_, i64>(13)?,
            row.get::<_, i64>(14)?,
            row.get::<_, i64>(15)?,
            row.get::<_, i64>(16)?,
            row.get::<_, i64>(17)?,
        ))
    })?;
    let doc = ContentKnowledgeDocument {
        document_id: row.0.clone(),
        origin_type: serde_json::from_str(&format!("\"{}\"", row.1))?,
        source_kind: serde_json::from_str(&format!("\"{}\"", row.2))?,
        role: serde_json::from_str(&format!("\"{}\"", row.3))?,
        language: row.4,
        quality_score: row.5,
        title: row.6,
        summary: row.7,
        anchors: serde_json::from_str(&row.8)?,
        raw_text: crate::db::decode_knowledge_document_text(key, &row.0, "raw", &row.9)?,
        normalized_text: crate::db::decode_knowledge_document_text(
            key,
            &row.0,
            "normalized",
            &row.10,
        )?,
        created_at_ms: row.11,
        updated_at_ms: row.12,
        versions: KnowledgeVersionSet {
            schema_version: row.13,
            normalization_version: row.14,
            segmentation_version: row.15,
            embedding_policy_version: row.16,
            retrieval_policy_version: row.17,
        },
    };
    Ok(doc)
}

fn mark_job_done(conn: &Connection, document_id: &str, stage: &str) -> Result<()> {
    conn.execute(
        r#"UPDATE knowledge_index_jobs
           SET status = 'done',
               attempts = attempts + 1,
               next_retry_at_ms = NULL,
               last_error = NULL,
               updated_at_ms = ?3
           WHERE document_id = ?1 AND stage = ?2"#,
        params![document_id, stage, now_ms()],
    )?;
    Ok(())
}

fn mark_job_failed(
    conn: &Connection,
    document_id: &str,
    stage: &str,
    error: &anyhow::Error,
) -> Result<()> {
    let message = error.to_string();
    conn.execute(
        r#"UPDATE knowledge_index_jobs
           SET status = 'failed',
               attempts = attempts + 1,
               next_retry_at_ms = ?3,
               last_error = ?4,
               updated_at_ms = ?3
           WHERE document_id = ?1 AND stage = ?2"#,
        params![document_id, stage, now_ms() + 5_000, message],
    )?;
    conn.execute(
        r#"UPDATE knowledge_rebuild_state
           SET status = 'failed',
               last_error = ?1,
               current_document_id = ?2,
               current_stage = ?3
           WHERE state_key = 1"#,
        params![message, document_id, stage],
    )?;
    Ok(())
}

fn process_stage(conn: &Connection, key: &[u8; 32], document_id: &str, stage: &str) -> Result<()> {
    conn.execute(
        r#"UPDATE knowledge_rebuild_state
           SET current_document_id = ?1,
               current_stage = ?2,
               status = CASE
                   WHEN status = 'failed' THEN status
                   ELSE 'running'
               END
           WHERE state_key = 1"#,
        params![document_id, stage],
    )?;

    match stage {
        "normalize" => {
            let mut document = document_by_id(conn, key, document_id)?;
            document.normalized_text =
                normalize_text_for_source(document.source_kind, &document.raw_text);
            document.versions = KnowledgeVersionSet::current();
            upsert_document(conn, key, &document)?;
        }
        "segment" => {
            let document = document_by_id(conn, key, document_id)?;
            let segments = segment_document_text(&document);
            let mut units = build_section_units(&document, &segments);
            units.extend(build_segment_units(&document, &segments));
            replace_units(conn, key, document_id, &units)?;
        }
        "chunk" => {
            let document = document_by_id(conn, key, document_id)?;
            let segment_units = list_knowledge_units(
                conn,
                key,
                document_id,
                Some(KnowledgeUnitKind::Segment),
                10_000,
                0,
            )?;
            if segment_units.is_empty() {
                return Err(anyhow!(
                    "segment units missing for chunk stage: {document_id}"
                ));
            }
            let segments = segment_drafts_from_units(&segment_units);
            let chunks = build_chunk_units(&document, &segments, 192, 256);
            replace_units_of_kind(conn, key, document_id, KnowledgeUnitKind::Chunk, &chunks)?;
        }
        "embed" => {
            conn.execute(
                "DELETE FROM knowledge_embeddings WHERE target_id = ?1 OR target_id IN (SELECT unit_id FROM knowledge_units WHERE document_id = ?1)",
                params![document_id],
            )?;
            let document = document_by_id(conn, key, document_id)?;
            let sections = list_knowledge_units(
                conn,
                key,
                document_id,
                Some(KnowledgeUnitKind::Section),
                10_000,
                0,
            )?;
            let chunks = list_knowledge_units(
                conn,
                key,
                document_id,
                Some(KnowledgeUnitKind::Chunk),
                10_000,
                0,
            )?;
            let added = store_embeddings_for_document(conn, &document, &sections, &chunks)? as i64;
            conn.execute(
                r#"UPDATE knowledge_rebuild_state
                   SET embeddings_indexed = embeddings_indexed + ?1
                   WHERE state_key = 1"#,
                params![added],
            )?;
        }
        "finalize" => {
            let (units_count,): (i64,) = conn.query_row(
                "SELECT COUNT(*) FROM knowledge_units WHERE document_id = ?1",
                params![document_id],
                |row| Ok((row.get(0)?,)),
            )?;
            conn.execute(
                r#"UPDATE knowledge_documents
                   SET last_indexed_at_ms = ?2
                   WHERE document_id = ?1"#,
                params![document_id, now_ms()],
            )?;
            conn.execute(
                r#"UPDATE knowledge_rebuild_state
                   SET documents_indexed = documents_indexed + 1,
                       units_indexed = units_indexed + ?1
                   WHERE state_key = 1"#,
                params![units_count],
            )?;
        }
        _ => return Err(anyhow!("unsupported knowledge stage: {stage}")),
    }

    mark_job_done(conn, document_id, stage)
}

fn clear_failed_rebuild_status_if_recovered(conn: &Connection) -> Result<()> {
    let failed_jobs: i64 = conn.query_row(
        "SELECT COUNT(*) FROM knowledge_index_jobs WHERE status = 'failed'",
        [],
        |row| row.get(0),
    )?;
    if failed_jobs == 0 {
        conn.execute(
            r#"UPDATE knowledge_rebuild_state
               SET status = 'running',
                   last_error = NULL
               WHERE state_key = 1
                 AND status = 'failed'"#,
            [],
        )?;
    }
    Ok(())
}

fn finalize_if_complete(conn: &Connection) -> Result<()> {
    let pending: i64 = conn.query_row(
        r#"SELECT COUNT(*)
           FROM knowledge_index_jobs
           WHERE status != 'done'"#,
        [],
        |row| row.get(0),
    )?;
    if pending > 0 {
        return Ok(());
    }
    let (model_name, dim) = crate::db::read_knowledge_embedding_model_state(conn)?;
    conn.execute(
        r#"UPDATE knowledge_rebuild_state
           SET status = 'complete',
               rebuild_required = 0,
               stale_reason = NULL,
               last_error = NULL,
               last_rebuild_completed_at_ms = ?1,
               current_document_id = NULL,
               current_stage = NULL,
               knowledge_schema_version = ?2,
               normalization_version = ?3,
               segmentation_version = ?4,
               embedding_policy_version = ?5,
               retrieval_policy_version = ?6,
               last_indexed_model_name = ?7,
               last_indexed_dim = ?8
           WHERE state_key = 1"#,
        params![
            now_ms(),
            crate::knowledge::KNOWLEDGE_SCHEMA_VERSION,
            crate::knowledge::KNOWLEDGE_NORMALIZATION_VERSION,
            crate::knowledge::KNOWLEDGE_SEGMENTATION_VERSION,
            crate::knowledge::KNOWLEDGE_EMBEDDING_POLICY_VERSION,
            crate::knowledge::KNOWLEDGE_RETRIEVAL_POLICY_VERSION,
            model_name,
            dim,
        ],
    )?;
    Ok(())
}

pub fn ensure_knowledge_rebuild_requested(conn: &Connection) -> Result<()> {
    crate::db::ensure_knowledge_rebuild_state_defaults(conn)?;
    conn.execute(
        r#"UPDATE knowledge_rebuild_state
           SET status = 'requested',
               rebuild_required = 0,
               stale_reason = NULL,
               last_error = NULL,
               current_document_id = NULL,
               current_stage = NULL,
               cancel_requested = 0
           WHERE state_key = 1"#,
        [],
    )?;
    Ok(())
}

pub fn process_pending_knowledge_index_jobs_active(
    conn: &Connection,
    key: &[u8; 32],
    _app_dir: &Path,
    limit: usize,
) -> Result<usize> {
    let cancel_requested: i64 = conn.query_row(
        "SELECT cancel_requested FROM knowledge_rebuild_state WHERE state_key = 1",
        [],
        |row| row.get(0),
    )?;
    if cancel_requested != 0 {
        conn.execute(
            r#"UPDATE knowledge_rebuild_state
               SET status = 'cancelled',
                   current_document_id = NULL,
                   current_stage = NULL
               WHERE state_key = 1"#,
            [],
        )?;
        return Ok(0);
    }

    let status: String = conn.query_row(
        "SELECT status FROM knowledge_rebuild_state WHERE state_key = 1",
        [],
        |row| row.get(0),
    )?;
    if status == "requested" || status == "empty" || status == "stale" {
        initialize_rebuild(conn, key)?;
    }

    let mut stmt = conn.prepare(
        r#"SELECT document_id, stage
           FROM knowledge_index_jobs
           WHERE status IN ('pending', 'failed')
             AND (next_retry_at_ms IS NULL OR next_retry_at_ms <= ?1)
           ORDER BY CASE stage
                      WHEN 'normalize' THEN 0
                      WHEN 'segment' THEN 1
                      WHEN 'chunk' THEN 2
                      WHEN 'embed' THEN 3
                      WHEN 'finalize' THEN 4
                      ELSE 99
                    END ASC,
                    updated_at_ms ASC,
                    document_id ASC
           LIMIT ?2"#,
    )?;
    let mut rows = stmt.query(params![now_ms(), limit.max(1) as i64])?;
    let mut jobs = Vec::<(String, String)>::new();
    while let Some(row) = rows.next()? {
        jobs.push((row.get(0)?, row.get(1)?));
    }

    let mut processed = 0usize;
    let mut first_error: Option<anyhow::Error> = None;
    for (document_id, stage) in jobs {
        match process_stage(conn, key, &document_id, &stage) {
            Ok(()) => processed += 1,
            Err(error) => {
                if let Err(mark_error) = mark_job_failed(conn, &document_id, &stage, &error) {
                    if first_error.is_none() {
                        first_error = Some(anyhow!(
                            "failed to record knowledge job failure for {document_id}:{stage}: {mark_error}; original stage error: {error}"
                        ));
                    }
                    continue;
                }
                if first_error.is_none() {
                    first_error = Some(error);
                }
            }
        }
    }

    if first_error.is_none() {
        clear_failed_rebuild_status_if_recovered(conn)?;
    }
    finalize_if_complete(conn)?;
    if let Some(error) = first_error {
        return Err(error);
    }
    Ok(processed)
}
