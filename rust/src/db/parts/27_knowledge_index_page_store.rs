pub fn replace_knowledge_claims(
    conn: &Connection,
    key: &[u8; 32],
    claims: &[crate::knowledge::KnowledgeClaim],
) -> Result<()> {
    conn.execute_batch("BEGIN IMMEDIATE;")?;
    let result = replace_knowledge_claims_in_transaction(conn, key, claims);

    match result {
        Ok(()) => {
            conn.execute_batch("COMMIT;")?;
            Ok(())
        }
        Err(error) => {
            let _ = conn.execute_batch("ROLLBACK;");
            Err(error)
        }
    }
}

pub(crate) fn replace_knowledge_claims_in_transaction(
    conn: &Connection,
    key: &[u8; 32],
    claims: &[crate::knowledge::KnowledgeClaim],
) -> Result<()> {
    conn.execute("DELETE FROM knowledge_claims", [])?;
    for claim in claims {
        conn.execute(
            r#"INSERT INTO knowledge_claims(
                   claim_id,
                   subject_id,
                   claim_type,
                   facet_key,
                   statement,
                   normalized_value,
                   time_scope,
                   valid_from_ms,
                   valid_until_ms,
                   confidence,
                   source_ref_ids_json,
                   source_count,
                   conflict_with_claim_ids_json,
                   status,
                   human_confirmed,
                   human_corrected,
                   answer_allowed,
                   created_at_ms,
                   updated_at_ms
               ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19)"#,
            params![
                claim.claim_id,
                claim.subject_id,
                encode_claim_type(claim.claim_type)?,
                claim.facet_key,
                encode_knowledge_claim_text(key, &claim.claim_id, "statement", &claim.statement)?,
                claim.normalized_value
                    .as_ref()
                    .map(|value| {
                        encode_knowledge_claim_text(
                            key,
                            &claim.claim_id,
                            "normalized_value",
                            value,
                        )
                    })
                    .transpose()?,
                encode_claim_time_scope(claim.time_scope)?,
                claim.valid_from_ms,
                claim.valid_until_ms,
                claim.confidence,
                encode_string_list(&claim.source_ref_ids)?,
                claim.source_count,
                encode_string_list(&claim.conflict_with_claim_ids)?,
                encode_claim_status(claim.status)?,
                if claim.human_confirmed { 1 } else { 0 },
                if claim.human_corrected { 1 } else { 0 },
                if claim.answer_allowed { 1 } else { 0 },
                claim.created_at_ms,
                claim.updated_at_ms,
            ],
        )?;
    }
    Ok(())
}

#[cfg_attr(not(test), allow(dead_code))]
pub(crate) fn upsert_compiled_knowledge_pages(
    conn: &Connection,
    key: &[u8; 32],
    pages: &[crate::knowledge::compiler::CompiledKnowledgePageRecord],
) -> Result<()> {
    conn.execute_batch("BEGIN IMMEDIATE;")?;
    let result = upsert_compiled_knowledge_pages_in_transaction(conn, key, pages);

    match result {
        Ok(()) => {
            conn.execute_batch("COMMIT;")?;
            Ok(())
        }
        Err(error) => {
            let _ = conn.execute_batch("ROLLBACK;");
            Err(error)
        }
    }
}

pub(crate) fn upsert_compiled_knowledge_pages_in_transaction(
    conn: &Connection,
    key: &[u8; 32],
    pages: &[crate::knowledge::compiler::CompiledKnowledgePageRecord],
) -> Result<()> {
        for item in pages {
            let existing = load_stored_knowledge_page_row(conn, &item.page.page_id)?;
            let existing_page = existing
                .as_ref()
                .map(|row| stored_row_to_page(key, row))
                .transpose()?;
            let preserve_manual_removed = existing
                .as_ref()
                .is_some_and(|row| row.tags.iter().any(|tag| tag == MANUAL_REMOVED_TAG));
            let preserve_merged_archived = existing
                .as_ref()
                .is_some_and(|row| row.tags.iter().any(|tag| tag == MERGED_ARCHIVED_TAG));
            let preserved_state = match existing.as_ref().map(|row| row.state) {
                Some(crate::knowledge::KnowledgePageState::Removed) if preserve_manual_removed => {
                    crate::knowledge::KnowledgePageState::Removed
                }
                Some(crate::knowledge::KnowledgePageState::Removed) | None => item.page.state,
                Some(state) => state,
            };
            let existing_allowed = existing
                .as_ref()
                .map(|row| row.default_allowed)
                .unwrap_or(item.page.answer_policy.default_allowed);
            let allowed = match preserved_state {
                crate::knowledge::KnowledgePageState::Archived
                | crate::knowledge::KnowledgePageState::Removed => false,
                _ => existing_allowed,
            };
            let answer_policy = answer_policy_for_state_with_override(preserved_state, allowed);
            let created_at_ms = existing
                .as_ref()
                .map(|row| row.created_at_ms)
                .unwrap_or(item.page.created_at_ms);
            let updated_at_ms = item
                .page
                .updated_at_ms
                .max(existing.as_ref().map(|row| row.updated_at_ms).unwrap_or(0));
            let last_used_at_ms = existing.as_ref().and_then(|row| row.last_used_at_ms);
            let state_before_answer_muted = existing
                .as_ref()
                .and_then(|row| row.state_before_answer_muted);
            let human_corrected = existing.as_ref().is_some_and(|row| {
                row.manual_title_blob.is_some()
                    || row.manual_summary_blob.is_some()
                    || row.manual_body_blob.is_some()
                    || row.human_corrected
            });
            let preserve_merged_provenance = existing
                .as_ref()
                .is_some_and(|row| row.tags.iter().any(|tag| tag == MERGED_PROVENANCE_TAG));
            let tags = if preserve_merged_provenance
                || preserve_manual_removed
                || preserve_merged_archived
            {
                normalize_knowledge_string_set(
                    &existing
                        .as_ref()
                        .into_iter()
                        .flat_map(|row| row.tags.iter())
                        .chain(item.page.tags.iter())
                        .cloned()
                        .collect::<Vec<_>>(),
                    32,
                )
            } else {
                item.page.tags.clone()
            };
            let primary_evidence_ids = if preserve_merged_provenance {
                normalize_knowledge_string_set(
                    &existing
                        .as_ref()
                        .into_iter()
                        .flat_map(|row| row.primary_evidence_ids.iter())
                        .chain(item.page.primary_evidence_ids.iter())
                        .cloned()
                        .collect::<Vec<_>>(),
                    32,
                )
            } else {
                item.page.primary_evidence_ids.clone()
            };
            let related_page_ids = if preserve_merged_provenance {
                normalize_knowledge_string_set(
                    &existing
                        .as_ref()
                        .into_iter()
                        .flat_map(|row| row.related_page_ids.iter())
                        .chain(item.page.related_page_ids.iter())
                        .cloned()
                        .collect::<Vec<_>>(),
                    32,
                )
            } else {
                item.page.related_page_ids.clone()
            };
            let source_document_ids = if preserve_merged_provenance {
                normalize_knowledge_string_set(
                    &existing
                        .as_ref()
                        .into_iter()
                        .flat_map(|row| row.source_document_ids.iter())
                        .chain(item.source_document_ids.iter())
                        .cloned()
                        .collect::<Vec<_>>(),
                    128,
                )
            } else {
                item.source_document_ids.clone()
            };
            let claim_ids = if preserve_merged_provenance {
                normalize_knowledge_string_set(
                    &existing
                        .as_ref()
                        .into_iter()
                        .flat_map(|row| row.claim_ids.iter())
                        .chain(item.claim_ids.iter())
                        .cloned()
                        .collect::<Vec<_>>(),
                    256,
                )
            } else {
                item.claim_ids.clone()
            };
            let page_id = item.page.page_id.clone();
            let visible_title = if existing
                .as_ref()
                .is_some_and(|row| row.manual_title_blob.is_some())
            {
                existing_page
                    .as_ref()
                    .map(|page| page.title.clone())
                    .unwrap_or_else(|| item.page.title.clone())
            } else {
                item.page.title.clone()
            };
            let visible_summary = if existing
                .as_ref()
                .is_some_and(|row| row.manual_summary_blob.is_some())
            {
                existing_page
                    .as_ref()
                    .map(|page| page.current_summary.clone())
                    .unwrap_or_else(|| item.page.current_summary.clone())
            } else {
                item.page.current_summary.clone()
            };
            let visible_body = if existing
                .as_ref()
                .is_some_and(|row| row.manual_body_blob.is_some())
            {
                existing_page
                    .as_ref()
                    .map(|page| page.current_body.clone())
                    .unwrap_or_else(|| item.page.current_body.clone())
            } else {
                item.page.current_body.clone()
            };
            let effective_page = crate::knowledge::KnowledgePage {
                page_id: item.page.page_id.clone(),
                page_type: item.page.page_type,
                title: visible_title,
                current_summary: visible_summary,
                current_body: visible_body,
                state: preserved_state,
                answer_policy: answer_policy.clone(),
                confidence_level: if preserve_merged_provenance {
                    existing
                        .as_ref()
                        .map(|row| row.confidence_level)
                        .unwrap_or(item.page.confidence_level)
                        .max(item.page.confidence_level)
                } else {
                    item.page.confidence_level
                },
                created_at_ms,
                updated_at_ms,
                last_used_at_ms,
                source_count: if preserve_merged_provenance {
                    existing
                        .as_ref()
                        .map(|row| row.source_count)
                        .unwrap_or(item.page.source_count)
                        .max(item.page.source_count)
                } else {
                    item.page.source_count
                },
                conflict_count: if preserve_merged_provenance {
                    count_current_conflicts_for_claim_ids(conn, key, &claim_ids)?
                } else {
                    item.page.conflict_count
                },
                human_corrected,
                tags: tags.clone(),
                primary_evidence_ids: primary_evidence_ids.clone(),
                related_page_ids: related_page_ids.clone(),
            };

            conn.execute(
                r#"INSERT INTO knowledge_pages(
                       page_id,
                       page_type,
                       state,
                       state_before_answer_muted,
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
                   ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21, ?22, ?23, ?24)
                   ON CONFLICT(page_id) DO UPDATE SET
                     page_type = excluded.page_type,
                     state = excluded.state,
                     state_before_answer_muted = COALESCE(knowledge_pages.state_before_answer_muted, excluded.state_before_answer_muted),
                     answer_default_allowed = excluded.answer_default_allowed,
                     answer_requires_temporal_framing = excluded.answer_requires_temporal_framing,
                     confidence_level = excluded.confidence_level,
                     source_count = excluded.source_count,
                     conflict_count = excluded.conflict_count,
                     updated_at_ms = excluded.updated_at_ms,
                     last_used_at_ms = COALESCE(knowledge_pages.last_used_at_ms, excluded.last_used_at_ms),
                     human_corrected = excluded.human_corrected,
                     tags_json = excluded.tags_json,
                     primary_evidence_json = excluded.primary_evidence_json,
                     related_page_ids_json = excluded.related_page_ids_json,
                     source_document_ids_json = excluded.source_document_ids_json,
                     claim_ids_json = excluded.claim_ids_json,
                     compiled_title = excluded.compiled_title,
                     compiled_summary = excluded.compiled_summary,
                     compiled_body = excluded.compiled_body,
                     manual_title = COALESCE(knowledge_pages.manual_title, excluded.manual_title),
                     manual_summary = COALESCE(knowledge_pages.manual_summary, excluded.manual_summary),
                     manual_body = COALESCE(knowledge_pages.manual_body, excluded.manual_body)"#,
                params![
                    item.page.page_id,
                    encode_page_type(item.page.page_type)?,
                    encode_page_state(preserved_state)?,
                    encode_optional_page_state(state_before_answer_muted)?,
                    if answer_policy.default_allowed { 1 } else { 0 },
                    if answer_policy.requires_temporal_framing { 1 } else { 0 },
                    effective_page.confidence_level,
                    effective_page.source_count,
                    effective_page.conflict_count,
                    created_at_ms,
                    updated_at_ms,
                    last_used_at_ms,
                    if human_corrected { 1 } else { 0 },
                    encode_string_list(&tags)?,
                    encode_string_list(&primary_evidence_ids)?,
                    encode_string_list(&related_page_ids)?,
                    encode_string_list(&source_document_ids)?,
                    encode_string_list(&claim_ids)?,
                    encode_knowledge_page_text(key, &page_id, "compiled_title", &item.page.title)?,
                    encode_knowledge_page_text(
                        key,
                        &page_id,
                        "compiled_summary",
                        &item.page.current_summary,
                    )?,
                    encode_knowledge_page_text(key, &page_id, "compiled_body", &item.page.current_body)?,
                    existing.as_ref().and_then(|row| row.manual_title_blob.clone()),
                    existing.as_ref().and_then(|row| row.manual_summary_blob.clone()),
                    existing.as_ref().and_then(|row| row.manual_body_blob.clone()),
                ],
            )?;

            replace_knowledge_page_lints(
                conn,
                &page_id,
                &build_knowledge_page_lints(&effective_page, &source_document_ids),
            )?;

            match existing_page {
                None => record_knowledge_page_change(
                    conn,
                    key,
                    &page_id,
                    crate::knowledge::KnowledgePageChangeType::Created,
                    "system",
                    Some("Compiled from current claims."),
                    answer_policy.default_allowed,
                    updated_at_ms,
                )?,
                Some(previous) if previous != effective_page => record_knowledge_page_change(
                    conn,
                    key,
                    &page_id,
                    crate::knowledge::KnowledgePageChangeType::Updated,
                    "system",
                    Some("Recompiled from source claims."),
                    previous.current_body != effective_page.current_body,
                    updated_at_ms,
                )?,
                Some(_) => {}
            }
        }
        Ok(())
}

pub fn mark_missing_knowledge_pages_removed(
    conn: &Connection,
    key: &[u8; 32],
    active_page_ids: &[String],
) -> Result<()> {
    let placeholders = if active_page_ids.is_empty() {
        String::new()
    } else {
        active_page_ids
            .iter()
            .enumerate()
            .map(|(index, _)| format!("?{}", index + 1))
            .collect::<Vec<_>>()
            .join(", ")
    };
    let sql = if active_page_ids.is_empty() {
        "SELECT page_id, state, tags_json FROM knowledge_pages".to_string()
    } else {
        format!(
            "SELECT page_id, state, tags_json FROM knowledge_pages WHERE page_id NOT IN ({placeholders})"
        )
    };
    let mut stmt = conn.prepare(&sql)?;
    let values = active_page_ids.iter().map(String::as_str).collect::<Vec<_>>();
    let mut rows = stmt.query(rusqlite::params_from_iter(values.iter().copied()))?;
    let now = now_ms();
    while let Some(row) = rows.next()? {
        let page_id: String = row.get(0)?;
        let state = decode_page_state(row.get(1)?)?;
        let tags = decode_string_list(row.get(2)?)?;
        if matches!(
            state,
            crate::knowledge::KnowledgePageState::Archived
                | crate::knowledge::KnowledgePageState::Removed
        )
            || tags.iter().any(|tag| tag == MERGED_ARCHIVED_TAG)
        {
            continue;
        }
        conn.execute(
            r#"UPDATE knowledge_pages
               SET state = ?2,
                   state_before_answer_muted = NULL,
                   answer_default_allowed = 0,
                   answer_requires_temporal_framing = 0,
                   updated_at_ms = ?3
               WHERE page_id = ?1"#,
            params![
                page_id,
                encode_page_state(crate::knowledge::KnowledgePageState::Removed)?,
                now,
            ],
        )?;
        replace_knowledge_page_lints(
            conn,
            &page_id,
            &[crate::knowledge::KnowledgeLintRecord {
                lint_id: format!("lint:{page_id}:removed"),
                page_id: page_id.clone(),
                kind: crate::knowledge::KnowledgeLintKind::UnusedKnowledge,
                summary: "This page no longer has supporting claims.".to_string(),
                created_at_ms: now,
            }],
        )?;
        record_knowledge_page_change(
            conn,
            key,
            &page_id,
            crate::knowledge::KnowledgePageChangeType::Removed,
            "system",
            Some("Removed because no source claims remain."),
            true,
            now,
        )?;
    }
    Ok(())
}

fn count_current_conflicts_for_claim_ids(
    conn: &Connection,
    key: &[u8; 32],
    claim_ids: &[String],
) -> Result<i64> {
    let mut by_facet =
        std::collections::BTreeMap::<String, std::collections::BTreeSet<String>>::new();
    for claim_id in claim_ids {
        let row = conn
            .query_row(
                r#"SELECT facet_key, statement, status
                   FROM knowledge_claims
                   WHERE claim_id = ?1"#,
                params![claim_id],
                |row| {
                    Ok((
                        row.get::<_, String>(0)?,
                        row.get::<_, Vec<u8>>(1)?,
                        row.get::<_, String>(2)?,
                    ))
                },
            )
            .optional()?;
        let Some((facet_key, statement_blob, status_raw)) = row else {
            continue;
        };
        if decode_claim_status(status_raw)? == crate::knowledge::KnowledgeClaimStatus::Dismissed {
            continue;
        }
        let statement = decode_knowledge_claim_text(key, claim_id, "statement", &statement_blob)?;
        by_facet.entry(facet_key).or_default().insert(statement);
    }
    Ok(by_facet.values().filter(|values| values.len() > 1).count() as i64)
}

pub fn list_knowledge_page_summaries(
    conn: &Connection,
    key: &[u8; 32],
) -> Result<Vec<crate::knowledge::KnowledgePageSummary>> {
    let mut stmt = conn.prepare(
        r#"SELECT page_id,
                  page_type,
                  state,
                  answer_default_allowed,
                  answer_requires_temporal_framing,
                  source_count,
                  conflict_count,
                  updated_at_ms,
                  last_used_at_ms,
                  human_corrected,
                  tags_json,
                  primary_evidence_json,
                  compiled_title,
                  compiled_summary,
                  manual_title,
                  manual_summary
           FROM knowledge_pages
           WHERE state NOT IN ('archived', 'removed')
           ORDER BY COALESCE(last_used_at_ms, 0) DESC, updated_at_ms DESC, page_id ASC"#,
    )?;
    let rows = stmt
        .query_map([], read_knowledge_page_summary_sql_row)?
        .collect::<std::result::Result<Vec<_>, _>>()
        .map_err(anyhow::Error::from)?;
    let mut out = Vec::new();
    for row in rows {
        out.push(decode_knowledge_page_summary(key, row)?);
    }
    Ok(out)
}

pub fn list_knowledge_page_summaries_by_ids(
    conn: &Connection,
    key: &[u8; 32],
    page_ids: &[String],
) -> Result<Vec<crate::knowledge::KnowledgePageSummary>> {
    if page_ids.is_empty() {
        return Ok(Vec::new());
    }
    let placeholders = page_ids
        .iter()
        .enumerate()
        .map(|(index, _)| format!("?{}", index + 1))
        .collect::<Vec<_>>()
        .join(", ");
    let sql = format!(
        r#"SELECT page_id,
                  page_type,
                  state,
                  answer_default_allowed,
                  answer_requires_temporal_framing,
                  source_count,
                  conflict_count,
                  updated_at_ms,
                  last_used_at_ms,
                  human_corrected,
                  tags_json,
                  primary_evidence_json,
                  compiled_title,
                  compiled_summary,
                  manual_title,
                  manual_summary
           FROM knowledge_pages
           WHERE state NOT IN ('archived', 'removed')
             AND page_id IN ({placeholders})"#
    );
    let mut stmt = conn.prepare(&sql)?;
    let rows = stmt
        .query_map(
            rusqlite::params_from_iter(page_ids.iter().map(String::as_str)),
            read_knowledge_page_summary_sql_row,
        )?
        .collect::<std::result::Result<Vec<_>, _>>()
        .map_err(anyhow::Error::from)?;
    let mut summaries_by_id =
        std::collections::BTreeMap::<String, crate::knowledge::KnowledgePageSummary>::new();
    for row in rows {
        let summary = decode_knowledge_page_summary(key, row)?;
        summaries_by_id.insert(summary.page_id.clone(), summary);
    }
    Ok(page_ids
        .iter()
        .filter_map(|page_id| summaries_by_id.remove(page_id))
        .collect())
}

pub fn list_answer_excluded_knowledge_page_ids(conn: &Connection) -> Result<Vec<String>> {
    let mut stmt = conn.prepare(
        r#"SELECT page_id
           FROM knowledge_pages
           WHERE answer_default_allowed = 0
              OR state IN ('archived', 'removed')
           ORDER BY page_id ASC"#,
    )?;
    let page_ids = stmt
        .query_map([], |row| row.get::<_, String>(0))?
        .collect::<std::result::Result<Vec<_>, _>>()
        .map_err(anyhow::Error::from)?;
    Ok(page_ids)
}
