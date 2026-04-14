fn encode_string_list(values: &[String]) -> Result<String> {
    Ok(serde_json::to_string(values)?)
}

fn decode_string_list(raw: String) -> Result<Vec<String>> {
    Ok(serde_json::from_str(&raw)?)
}

fn encode_page_state(state: crate::knowledge::KnowledgePageState) -> Result<String> {
    Ok(serde_json::to_string(&state)?.trim_matches('"').to_string())
}

fn decode_page_state(raw: String) -> Result<crate::knowledge::KnowledgePageState> {
    Ok(serde_json::from_str(&format!("\"{raw}\""))?)
}

fn encode_page_type(page_type: crate::knowledge::KnowledgePageType) -> Result<String> {
    Ok(serde_json::to_string(&page_type)?.trim_matches('"').to_string())
}

fn decode_page_type(raw: String) -> Result<crate::knowledge::KnowledgePageType> {
    Ok(serde_json::from_str(&format!("\"{raw}\""))?)
}

fn encode_claim_type(claim_type: crate::knowledge::KnowledgeClaimType) -> Result<String> {
    Ok(serde_json::to_string(&claim_type)?.trim_matches('"').to_string())
}

fn decode_claim_type(raw: String) -> Result<crate::knowledge::KnowledgeClaimType> {
    Ok(serde_json::from_str(&format!("\"{raw}\""))?)
}

fn encode_claim_time_scope(scope: crate::knowledge::KnowledgeClaimTimeScope) -> Result<String> {
    Ok(serde_json::to_string(&scope)?.trim_matches('"').to_string())
}

fn decode_claim_time_scope(raw: String) -> Result<crate::knowledge::KnowledgeClaimTimeScope> {
    Ok(serde_json::from_str(&format!("\"{raw}\""))?)
}

fn encode_claim_status(status: crate::knowledge::KnowledgeClaimStatus) -> Result<String> {
    Ok(serde_json::to_string(&status)?.trim_matches('"').to_string())
}

fn decode_claim_status(raw: String) -> Result<crate::knowledge::KnowledgeClaimStatus> {
    Ok(serde_json::from_str(&format!("\"{raw}\""))?)
}

fn encode_history_change_type(
    change_type: crate::knowledge::KnowledgePageChangeType,
) -> Result<String> {
    Ok(serde_json::to_string(&change_type)?.trim_matches('"').to_string())
}

fn decode_history_change_type(raw: String) -> Result<crate::knowledge::KnowledgePageChangeType> {
    Ok(serde_json::from_str(&format!("\"{raw}\""))?)
}

fn encode_lint_kind(kind: crate::knowledge::KnowledgeLintKind) -> Result<String> {
    Ok(serde_json::to_string(&kind)?.trim_matches('"').to_string())
}

fn decode_lint_kind(raw: String) -> Result<crate::knowledge::KnowledgeLintKind> {
    Ok(serde_json::from_str(&format!("\"{raw}\""))?)
}

pub fn touch_knowledge_pages_usage(
    conn: &Connection,
    page_ids: &[String],
    now_ms: i64,
) -> Result<usize> {
    let unique = page_ids
        .iter()
        .filter(|value| !value.trim().is_empty())
        .cloned()
        .collect::<std::collections::BTreeSet<_>>();
    if unique.is_empty() {
        return Ok(0);
    }
    let mut touched = 0usize;
    for page_id in unique {
        touched += conn.execute(
            "UPDATE knowledge_pages SET last_used_at_ms = ?2 WHERE page_id = ?1",
            params![page_id, now_ms],
        )?;
    }
    Ok(touched)
}

#[derive(Clone, Debug)]
struct StoredKnowledgePageRow {
    page_id: String,
    page_type: crate::knowledge::KnowledgePageType,
    state: crate::knowledge::KnowledgePageState,
    default_allowed: bool,
    requires_temporal_framing: bool,
    confidence_level: f64,
    source_count: i64,
    conflict_count: i64,
    created_at_ms: i64,
    updated_at_ms: i64,
    last_used_at_ms: Option<i64>,
    human_corrected: bool,
    tags: Vec<String>,
    primary_evidence_ids: Vec<String>,
    related_page_ids: Vec<String>,
    source_document_ids: Vec<String>,
    claim_ids: Vec<String>,
    compiled_title_blob: Vec<u8>,
    compiled_summary_blob: Vec<u8>,
    compiled_body_blob: Vec<u8>,
    manual_title_blob: Option<Vec<u8>>,
    manual_summary_blob: Option<Vec<u8>>,
    manual_body_blob: Option<Vec<u8>>,
}

fn load_stored_knowledge_page_row(
    conn: &Connection,
    page_id: &str,
) -> Result<Option<StoredKnowledgePageRow>> {
    let row = conn
        .query_row(
        r#"SELECT page_id,
                  page_type,
                  state,
                  answer_default_allowed,
                  answer_requires_temporal_framing,
                  confidence_level,
                  source_count,
                  conflict_count,
                  created_at_ms,
                  updated_at_ms,
                  last_used_at_ms,
                  human_corrected,
                  tags_json,
                  primary_evidence_json,
                  related_page_ids_json,
                  source_document_ids_json,
                  claim_ids_json,
                  compiled_title,
                  compiled_summary,
                  compiled_body,
                  manual_title,
                  manual_summary,
                  manual_body
           FROM knowledge_pages
           WHERE page_id = ?1"#,
        params![page_id],
        |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, i64>(3)?,
                row.get::<_, i64>(4)?,
                row.get::<_, f64>(5)?,
                row.get::<_, i64>(6)?,
                row.get::<_, i64>(7)?,
                row.get::<_, i64>(8)?,
                row.get::<_, i64>(9)?,
                row.get::<_, Option<i64>>(10)?,
                row.get::<_, i64>(11)?,
                row.get::<_, String>(12)?,
                row.get::<_, String>(13)?,
                row.get::<_, String>(14)?,
                row.get::<_, String>(15)?,
                row.get::<_, String>(16)?,
                row.get::<_, Vec<u8>>(17)?,
                row.get::<_, Vec<u8>>(18)?,
                row.get::<_, Vec<u8>>(19)?,
                row.get::<_, Option<Vec<u8>>>(20)?,
                row.get::<_, Option<Vec<u8>>>(21)?,
                row.get::<_, Option<Vec<u8>>>(22)?,
            ))
        },
    )
    .optional()
    .map_err(anyhow::Error::from)?;

    let Some(row) = row else {
        return Ok(None);
    };

    Ok(Some(StoredKnowledgePageRow {
        page_id: row.0,
        page_type: decode_page_type(row.1)?,
        state: decode_page_state(row.2)?,
        default_allowed: row.3 != 0,
        requires_temporal_framing: row.4 != 0,
        confidence_level: row.5,
        source_count: row.6,
        conflict_count: row.7,
        created_at_ms: row.8,
        updated_at_ms: row.9,
        last_used_at_ms: row.10,
        human_corrected: row.11 != 0,
        tags: decode_string_list(row.12)?,
        primary_evidence_ids: decode_string_list(row.13)?,
        related_page_ids: decode_string_list(row.14)?,
        source_document_ids: decode_string_list(row.15)?,
        claim_ids: decode_string_list(row.16)?,
        compiled_title_blob: row.17,
        compiled_summary_blob: row.18,
        compiled_body_blob: row.19,
        manual_title_blob: row.20,
        manual_summary_blob: row.21,
        manual_body_blob: row.22,
    }))
}

fn stored_row_to_page(
    key: &[u8; 32],
    row: &StoredKnowledgePageRow,
) -> Result<crate::knowledge::KnowledgePage> {
    let compiled_title = decode_knowledge_page_text(key, &row.page_id, "compiled_title", &row.compiled_title_blob)?;
    let compiled_summary =
        decode_knowledge_page_text(key, &row.page_id, "compiled_summary", &row.compiled_summary_blob)?;
    let compiled_body = decode_knowledge_page_text(key, &row.page_id, "compiled_body", &row.compiled_body_blob)?;
    let manual_title = row
        .manual_title_blob
        .as_ref()
        .map(|blob| decode_knowledge_page_text(key, &row.page_id, "manual_title", blob))
        .transpose()?;
    let manual_summary = row
        .manual_summary_blob
        .as_ref()
        .map(|blob| decode_knowledge_page_text(key, &row.page_id, "manual_summary", blob))
        .transpose()?;
    let manual_body = row
        .manual_body_blob
        .as_ref()
        .map(|blob| decode_knowledge_page_text(key, &row.page_id, "manual_body", blob))
        .transpose()?;

    Ok(crate::knowledge::KnowledgePage {
        page_id: row.page_id.clone(),
        page_type: row.page_type,
        title: manual_title.unwrap_or(compiled_title),
        current_summary: manual_summary.unwrap_or(compiled_summary),
        current_body: manual_body.unwrap_or(compiled_body),
        state: row.state,
        answer_policy: crate::knowledge::KnowledgeAnswerPolicy {
            default_allowed: row.default_allowed,
            requires_temporal_framing: row.requires_temporal_framing,
        },
        confidence_level: row.confidence_level,
        created_at_ms: row.created_at_ms,
        updated_at_ms: row.updated_at_ms,
        last_used_at_ms: row.last_used_at_ms,
        source_count: row.source_count,
        conflict_count: row.conflict_count,
        human_corrected: row.human_corrected,
        tags: row.tags.clone(),
        primary_evidence_ids: row.primary_evidence_ids.clone(),
        related_page_ids: row.related_page_ids.clone(),
    })
}

pub(crate) fn load_current_knowledge_page(
    conn: &Connection,
    key: &[u8; 32],
    page_id: &str,
) -> Result<Option<crate::knowledge::KnowledgePage>> {
    load_stored_knowledge_page_row(conn, page_id)?
        .as_ref()
        .map(|row| stored_row_to_page(key, row))
        .transpose()
}

fn evidence_kind_for_claim_status(
    status: crate::knowledge::KnowledgeClaimStatus,
) -> crate::knowledge::KnowledgePageEvidenceKind {
    match status {
        crate::knowledge::KnowledgeClaimStatus::Active
        | crate::knowledge::KnowledgeClaimStatus::Supporting => {
            crate::knowledge::KnowledgePageEvidenceKind::Support
        }
        crate::knowledge::KnowledgeClaimStatus::Disputed => {
            crate::knowledge::KnowledgePageEvidenceKind::Conflict
        }
        crate::knowledge::KnowledgeClaimStatus::Candidate
        | crate::knowledge::KnowledgeClaimStatus::Outdated
        | crate::knowledge::KnowledgeClaimStatus::Dismissed => {
            crate::knowledge::KnowledgePageEvidenceKind::Supplement
        }
    }
}

fn list_knowledge_page_history_internal(
    conn: &Connection,
    page_id: &str,
    limit: usize,
) -> Result<Vec<crate::knowledge::KnowledgePageChangeRecord>> {
    let mut stmt = conn.prepare(
        r#"SELECT change_id, page_id, change_type, actor, reason, answer_impacted, created_at_ms
           FROM knowledge_page_history
           WHERE page_id = ?1
           ORDER BY created_at_ms DESC, change_id DESC
           LIMIT ?2"#,
    )?;
    let mut rows = stmt.query(params![page_id, limit as i64])?;
    let mut out = Vec::new();
    while let Some(row) = rows.next()? {
        out.push(crate::knowledge::KnowledgePageChangeRecord {
            change_id: row.get(0)?,
            page_id: row.get(1)?,
            change_type: decode_history_change_type(row.get(2)?)?,
            actor: row.get(3)?,
            reason: normalize_optional_trimmed(row.get(4)?),
            answer_impacted: row.get::<_, i64>(5)? != 0,
            created_at_ms: row.get(6)?,
        });
    }
    Ok(out)
}

fn list_knowledge_page_version_snapshots_internal(
    conn: &Connection,
    key: &[u8; 32],
    page_id: &str,
    limit: usize,
) -> Result<Vec<crate::knowledge::KnowledgePageVersionSnapshot>> {
    let mut stmt = conn.prepare(
        r#"SELECT version_id,
                  page_id,
                  change_type,
                  actor,
                  reason,
                  state,
                  answer_default_allowed,
                  answer_requires_temporal_framing,
                  confidence_level,
                  source_count,
                  conflict_count,
                  human_corrected,
                  title,
                  summary,
                  body,
                  created_at_ms
           FROM knowledge_page_versions
           WHERE page_id = ?1
           ORDER BY created_at_ms DESC, version_id DESC
           LIMIT ?2"#,
    )?;
    let mut rows = stmt.query(params![page_id, limit as i64])?;
    let mut out = Vec::new();
    while let Some(row) = rows.next()? {
        let version_id: String = row.get(0)?;
        out.push(crate::knowledge::KnowledgePageVersionSnapshot {
            version_id: version_id.clone(),
            page_id: row.get(1)?,
            change_type: decode_history_change_type(row.get(2)?)?,
            actor: row.get(3)?,
            reason: normalize_optional_trimmed(row.get(4)?),
            state: decode_page_state(row.get(5)?)?,
            answer_policy: crate::knowledge::KnowledgeAnswerPolicy {
                default_allowed: row.get::<_, i64>(6)? != 0,
                requires_temporal_framing: row.get::<_, i64>(7)? != 0,
            },
            confidence_level: row.get(8)?,
            source_count: row.get(9)?,
            conflict_count: row.get(10)?,
            human_corrected: row.get::<_, i64>(11)? != 0,
            title: decode_knowledge_page_version_text(key, &version_id, "title", &row.get::<_, Vec<u8>>(12)?)?,
            summary: decode_knowledge_page_version_text(key, &version_id, "summary", &row.get::<_, Vec<u8>>(13)?)?,
            body: decode_knowledge_page_version_text(key, &version_id, "body", &row.get::<_, Vec<u8>>(14)?)?,
            created_at_ms: row.get(15)?,
        });
    }
    Ok(out)
}

fn list_knowledge_page_evidence_entries_internal(
    conn: &Connection,
    key: &[u8; 32],
    claim_ids: &[String],
) -> Result<Vec<crate::knowledge::KnowledgePageEvidenceEntry>> {
    let mut out = Vec::new();
    for claim_id in claim_ids {
        let row = conn
            .query_row(
                r#"SELECT statement, source_ref_ids_json, status, updated_at_ms
                   FROM knowledge_claims
                   WHERE claim_id = ?1"#,
                params![claim_id],
                |row| {
                    Ok((
                        row.get::<_, Vec<u8>>(0)?,
                        row.get::<_, String>(1)?,
                        row.get::<_, String>(2)?,
                        row.get::<_, i64>(3)?,
                    ))
                },
            )
            .optional()?;
        let Some((statement_blob, source_ref_ids_json, status_raw, updated_at_ms)) = row else {
            continue;
        };
        let status = decode_claim_status(status_raw)?;
        out.push(crate::knowledge::KnowledgePageEvidenceEntry {
            evidence_id: format!("evidence:{claim_id}"),
            kind: evidence_kind_for_claim_status(status),
            summary: decode_knowledge_claim_text(key, claim_id, "statement", &statement_blob)?,
            source_ref_ids: decode_string_list(source_ref_ids_json)?,
            created_at_ms: updated_at_ms,
        });
    }
    out.sort_by(|left, right| {
        right
            .created_at_ms
            .cmp(&left.created_at_ms)
            .then_with(|| left.evidence_id.cmp(&right.evidence_id))
    });
    Ok(out)
}

pub fn list_recent_knowledge_page_changes(
    conn: &Connection,
    limit: usize,
) -> Result<Vec<crate::knowledge::KnowledgePageChangeRecord>> {
    let mut stmt = conn.prepare(
        r#"SELECT change_id, page_id, change_type, actor, reason, answer_impacted, created_at_ms
           FROM knowledge_page_history
           ORDER BY created_at_ms DESC, change_id DESC
           LIMIT ?1"#,
    )?;
    let mut rows = stmt.query(params![limit.max(1) as i64])?;
    let mut out = Vec::new();
    while let Some(row) = rows.next()? {
        out.push(crate::knowledge::KnowledgePageChangeRecord {
            change_id: row.get(0)?,
            page_id: row.get(1)?,
            change_type: decode_history_change_type(row.get(2)?)?,
            actor: row.get(3)?,
            reason: normalize_optional_trimmed(row.get(4)?),
            answer_impacted: row.get::<_, i64>(5)? != 0,
            created_at_ms: row.get(6)?,
        });
    }
    Ok(out)
}

fn list_knowledge_page_lints_internal(
    conn: &Connection,
    page_id: &str,
) -> Result<Vec<crate::knowledge::KnowledgeLintRecord>> {
    let mut stmt = conn.prepare(
        r#"SELECT lint_id, page_id, kind, summary, created_at_ms
           FROM knowledge_page_lints
           WHERE page_id = ?1
           ORDER BY created_at_ms DESC, lint_id DESC"#,
    )?;
    let mut rows = stmt.query(params![page_id])?;
    let mut out = Vec::new();
    while let Some(row) = rows.next()? {
        out.push(crate::knowledge::KnowledgeLintRecord {
            lint_id: row.get(0)?,
            page_id: row.get(1)?,
            kind: decode_lint_kind(row.get(2)?)?,
            summary: row.get(3)?,
            created_at_ms: row.get(4)?,
        });
    }
    Ok(out)
}

fn append_knowledge_page_history(
    conn: &Connection,
    page_id: &str,
    change_type: crate::knowledge::KnowledgePageChangeType,
    actor: &str,
    reason: Option<&str>,
    answer_impacted: bool,
    created_at_ms: i64,
) -> Result<()> {
    conn.execute(
        r#"INSERT INTO knowledge_page_history(
               change_id,
               page_id,
               change_type,
               actor,
               reason,
               answer_impacted,
               created_at_ms
           ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)"#,
        params![
            uuid::Uuid::new_v4().to_string(),
            page_id,
            encode_history_change_type(change_type)?,
            actor,
            normalize_optional_trimmed(reason.map(ToString::to_string)),
            if answer_impacted { 1 } else { 0 },
            created_at_ms,
        ],
    )?;
    Ok(())
}

fn append_knowledge_page_version_snapshot(
    conn: &Connection,
    key: &[u8; 32],
    page: &crate::knowledge::KnowledgePage,
    change_type: crate::knowledge::KnowledgePageChangeType,
    actor: &str,
    reason: Option<&str>,
    created_at_ms: i64,
) -> Result<()> {
    let version_id = uuid::Uuid::new_v4().to_string();
    conn.execute(
        r#"INSERT INTO knowledge_page_versions(
               version_id,
               page_id,
               change_type,
               actor,
               reason,
               state,
               answer_default_allowed,
               answer_requires_temporal_framing,
               confidence_level,
               source_count,
               conflict_count,
               human_corrected,
               title,
               summary,
               body,
               created_at_ms
           ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16)"#,
        params![
            version_id.clone(),
            &page.page_id,
            encode_history_change_type(change_type)?,
            actor,
            normalize_optional_trimmed(reason.map(ToString::to_string)),
            encode_page_state(page.state)?,
            if page.answer_policy.default_allowed { 1 } else { 0 },
            if page.answer_policy.requires_temporal_framing {
                1
            } else {
                0
            },
            page.confidence_level,
            page.source_count,
            page.conflict_count,
            if page.human_corrected { 1 } else { 0 },
            encode_knowledge_page_version_text(key, &version_id, "title", &page.title)?,
            encode_knowledge_page_version_text(
                key,
                &version_id,
                "summary",
                &page.current_summary,
            )?,
            encode_knowledge_page_version_text(key, &version_id, "body", &page.current_body)?,
            created_at_ms,
        ],
    )?;
    Ok(())
}

fn record_knowledge_page_change(
    conn: &Connection,
    key: &[u8; 32],
    page_id: &str,
    change_type: crate::knowledge::KnowledgePageChangeType,
    actor: &str,
    reason: Option<&str>,
    answer_impacted: bool,
    created_at_ms: i64,
) -> Result<()> {
    append_knowledge_page_history(
        conn,
        page_id,
        change_type,
        actor,
        reason,
        answer_impacted,
        created_at_ms,
    )?;
    let page = load_current_knowledge_page(conn, key, page_id)?
        .ok_or_else(|| anyhow!("knowledge page not found while recording version: {page_id}"))?;
    append_knowledge_page_version_snapshot(
        conn,
        key,
        &page,
        change_type,
        actor,
        reason,
        created_at_ms,
    )?;
    Ok(())
}

fn replace_knowledge_page_lints(
    conn: &Connection,
    page_id: &str,
    lints: &[crate::knowledge::KnowledgeLintRecord],
) -> Result<()> {
    conn.execute(
        "DELETE FROM knowledge_page_lints WHERE page_id = ?1",
        params![page_id],
    )?;
    for lint in lints {
        conn.execute(
            r#"INSERT INTO knowledge_page_lints(lint_id, page_id, kind, summary, created_at_ms)
               VALUES (?1, ?2, ?3, ?4, ?5)"#,
            params![
                lint.lint_id,
                lint.page_id,
                encode_lint_kind(lint.kind)?,
                lint.summary,
                lint.created_at_ms,
            ],
        )?;
    }
    Ok(())
}

fn build_knowledge_page_lints(
    page: &crate::knowledge::KnowledgePage,
    source_document_ids: &[String],
) -> Vec<crate::knowledge::KnowledgeLintRecord> {
    let now = now_ms();
    let mut out = Vec::new();
    if page.conflict_count > 0 {
        out.push(crate::knowledge::KnowledgeLintRecord {
            lint_id: format!("lint:{}:conflict", page.page_id),
            page_id: page.page_id.clone(),
            kind: crate::knowledge::KnowledgeLintKind::Conflict,
            summary: "Conflicting claims exist on this page.".to_string(),
            created_at_ms: now,
        });
    }
    if source_document_ids.len() <= 1 {
        out.push(crate::knowledge::KnowledgeLintRecord {
            lint_id: format!("lint:{}:evidence", page.page_id),
            page_id: page.page_id.clone(),
            kind: crate::knowledge::KnowledgeLintKind::EvidenceWeakness,
            summary: "This page is supported by very little evidence.".to_string(),
            created_at_ms: now,
        });
    }
    if page.human_corrected {
        out.push(crate::knowledge::KnowledgeLintRecord {
            lint_id: format!("lint:{}:manual", page.page_id),
            page_id: page.page_id.clone(),
            kind: crate::knowledge::KnowledgeLintKind::RegenerationRisk,
            summary: "This page has manual corrections and should not be silently overwritten."
                .to_string(),
            created_at_ms: now,
        });
    }
    if matches!(
        page.state,
        crate::knowledge::KnowledgePageState::Outdated
            | crate::knowledge::KnowledgePageState::NeedsReview
    ) {
        out.push(crate::knowledge::KnowledgeLintRecord {
            lint_id: format!("lint:{}:state", page.page_id),
            page_id: page.page_id.clone(),
            kind: crate::knowledge::KnowledgeLintKind::Staleness,
            summary: "This page needs a review before it can be fully trusted.".to_string(),
            created_at_ms: now,
        });
    }
    if !page.answer_policy.default_allowed {
        out.push(crate::knowledge::KnowledgeLintRecord {
            lint_id: format!("lint:{}:muted", page.page_id),
            page_id: page.page_id.clone(),
            kind: crate::knowledge::KnowledgeLintKind::UnusedKnowledge,
            summary: "This page is excluded from answer generation.".to_string(),
            created_at_ms: now,
        });
    }
    out
}

fn answer_policy_for_state_with_override(
    state: crate::knowledge::KnowledgePageState,
    allowed: bool,
) -> crate::knowledge::KnowledgeAnswerPolicy {
    let mut policy = crate::knowledge::state_default_answer_policy(state);
    policy.default_allowed = allowed;
    policy.requires_temporal_framing =
        allowed && state == crate::knowledge::KnowledgePageState::Outdated;
    policy
}
