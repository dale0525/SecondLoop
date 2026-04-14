pub fn get_knowledge_page_detail(
    conn: &Connection,
    key: &[u8; 32],
    page_id: &str,
) -> Result<Option<crate::knowledge::KnowledgePageDetail>> {
    let Some(row) = load_stored_knowledge_page_row(conn, page_id)? else {
        return Ok(None);
    };
    let page = stored_row_to_page(key, &row)?;
    let history = list_knowledge_page_history_internal(conn, page_id, 32)?;
    let version_snapshots = list_knowledge_page_version_snapshots_internal(conn, key, page_id, 32)?;
    let evidence_entries =
        list_knowledge_page_evidence_entries_internal(conn, key, &row.claim_ids)?;
    let lint_records = list_knowledge_page_lints_internal(conn, page_id)?;
    Ok(Some(crate::knowledge::KnowledgePageDetail {
        page,
        source_document_ids: row.source_document_ids,
        claim_ids: row.claim_ids,
        history,
        version_snapshots,
        evidence_entries,
        lint_records,
    }))
}

pub fn apply_knowledge_page_correction(
    conn: &Connection,
    key: &[u8; 32],
    page_id: &str,
    title: Option<String>,
    summary: Option<String>,
    body: Option<String>,
) -> Result<crate::knowledge::KnowledgePageDetail> {
    run_knowledge_page_mutation(conn, || {
        let now = now_ms();
        let Some(existing) = load_stored_knowledge_page_row(conn, page_id)? else {
            return Err(anyhow!("knowledge page not found: {page_id}"));
        };
        let preserved_state = existing.state;
        let preserved_policy = crate::knowledge::KnowledgeAnswerPolicy {
            default_allowed: existing.default_allowed,
            requires_temporal_framing: existing.requires_temporal_framing,
        };
        let next_manual_title = resolve_manual_page_text_update(
            key,
            page_id,
            "manual_title",
            title,
            existing.manual_title_blob.clone(),
            true,
        )?;
        let next_manual_summary = resolve_manual_page_text_update(
            key,
            page_id,
            "manual_summary",
            summary,
            existing.manual_summary_blob.clone(),
            true,
        )?;
        let next_manual_body = resolve_manual_page_text_update(
            key,
            page_id,
            "manual_body",
            body,
            existing.manual_body_blob.clone(),
            false,
        )?;
        conn.execute(
            r#"UPDATE knowledge_pages
               SET state = ?2,
                   answer_default_allowed = ?3,
                   answer_requires_temporal_framing = ?4,
                   updated_at_ms = ?5,
                   human_corrected = 1,
                   manual_title = ?6,
                   manual_summary = ?7,
                   manual_body = ?8
               WHERE page_id = ?1"#,
            params![
                page_id,
                encode_page_state(preserved_state)?,
                if preserved_policy.default_allowed { 1 } else { 0 },
                if preserved_policy.requires_temporal_framing {
                    1
                } else {
                    0
                },
                now,
                next_manual_title,
                next_manual_summary,
                next_manual_body,
            ],
        )?;
        let updated = get_knowledge_page_detail(conn, key, page_id)?
            .ok_or_else(|| anyhow!("knowledge page disappeared after correction"))?;
        replace_knowledge_page_lints(
            conn,
            page_id,
            &build_knowledge_page_lints(&updated.page, &updated.source_document_ids),
        )?;
        record_knowledge_page_change(
            conn,
            key,
            page_id,
            crate::knowledge::KnowledgePageChangeType::Corrected,
            "user",
            Some("Manual correction applied."),
            true,
            now,
        )?;
        get_knowledge_page_detail(conn, key, page_id)?
            .ok_or_else(|| anyhow!("knowledge page disappeared after correction"))
    })
}

pub fn mark_knowledge_page_wrong(
    conn: &Connection,
    key: &[u8; 32],
    page_id: &str,
    reason: crate::knowledge::KnowledgeWrongReason,
    note: Option<String>,
) -> Result<crate::knowledge::KnowledgePageDetail> {
    run_knowledge_page_mutation(conn, || {
        let now = now_ms();
        let Some(detail) = get_knowledge_page_detail(conn, key, page_id)? else {
            return Err(anyhow!("knowledge page not found: {page_id}"));
        };
        let next_state = crate::knowledge::apply_wrong_reason(detail.page.state, reason);
        let next_policy = crate::knowledge::state_default_answer_policy(next_state);
        conn.execute(
            r#"UPDATE knowledge_pages
               SET state = ?2,
                   answer_default_allowed = ?3,
                   answer_requires_temporal_framing = ?4,
                   updated_at_ms = ?5
               WHERE page_id = ?1"#,
            params![
                page_id,
                encode_page_state(next_state)?,
                if next_policy.default_allowed { 1 } else { 0 },
                if next_policy.requires_temporal_framing { 1 } else { 0 },
                now,
            ],
        )?;
        record_knowledge_page_change(
            conn,
            key,
            page_id,
            match next_state {
                crate::knowledge::KnowledgePageState::Archived => {
                    crate::knowledge::KnowledgePageChangeType::Archived
                }
                _ => crate::knowledge::KnowledgePageChangeType::Downgraded,
            },
            "user",
            note.as_deref(),
            true,
            now,
        )?;
        let updated = get_knowledge_page_detail(conn, key, page_id)?
            .ok_or_else(|| anyhow!("knowledge page missing after wrong flow"))?;
        replace_knowledge_page_lints(
            conn,
            page_id,
            &build_knowledge_page_lints(&updated.page, &updated.source_document_ids),
        )?;
        get_knowledge_page_detail(conn, key, page_id)?
            .ok_or_else(|| anyhow!("knowledge page missing after lint refresh"))
    })
}

pub fn set_knowledge_page_answer_allowed(
    conn: &Connection,
    key: &[u8; 32],
    page_id: &str,
    allowed: bool,
    note: Option<String>,
) -> Result<crate::knowledge::KnowledgePageDetail> {
    run_knowledge_page_mutation(conn, || {
        let now = now_ms();
        let Some(detail) = get_knowledge_page_detail(conn, key, page_id)? else {
            return Err(anyhow!("knowledge page not found: {page_id}"));
        };
        let next_state = if allowed {
            if detail.page.state == crate::knowledge::KnowledgePageState::AnswerMuted {
                restore_state_before_answer_muted(conn, key, page_id)?
            } else {
                detail.page.state
            }
        } else if matches!(
            detail.page.state,
            crate::knowledge::KnowledgePageState::Archived
                | crate::knowledge::KnowledgePageState::Removed
        ) {
            detail.page.state
        } else {
            crate::knowledge::KnowledgePageState::AnswerMuted
        };
        if allowed
            && matches!(
                next_state,
                crate::knowledge::KnowledgePageState::Archived
                    | crate::knowledge::KnowledgePageState::Removed
            )
        {
            return Err(anyhow!(
                "knowledge page cannot be re-enabled for answers in state: {next_state:?}"
            ));
        }
        let next_policy = answer_policy_for_state_with_override(next_state, allowed);
        conn.execute(
            r#"UPDATE knowledge_pages
               SET state = ?2,
                   answer_default_allowed = ?3,
                   answer_requires_temporal_framing = ?4,
                   updated_at_ms = ?5
               WHERE page_id = ?1"#,
            params![
                page_id,
                encode_page_state(next_state)?,
                if next_policy.default_allowed { 1 } else { 0 },
                if next_policy.requires_temporal_framing { 1 } else { 0 },
                now,
            ],
        )?;
        record_knowledge_page_change(
            conn,
            key,
            page_id,
            if allowed {
                crate::knowledge::KnowledgePageChangeType::Updated
            } else {
                crate::knowledge::KnowledgePageChangeType::Muted
            },
            "user",
            note.as_deref(),
            true,
            now,
        )?;
        let updated = get_knowledge_page_detail(conn, key, page_id)?
            .ok_or_else(|| anyhow!("knowledge page missing after answer policy update"))?;
        replace_knowledge_page_lints(
            conn,
            page_id,
            &build_knowledge_page_lints(&updated.page, &updated.source_document_ids),
        )?;
        get_knowledge_page_detail(conn, key, page_id)?
            .ok_or_else(|| anyhow!("knowledge page missing after lint refresh"))
    })
}

fn resolve_manual_page_text_update(
    key: &[u8; 32],
    page_id: &str,
    field: &str,
    value: Option<String>,
    existing: Option<Vec<u8>>,
    empty_clears_override: bool,
) -> Result<Option<Vec<u8>>> {
    let Some(value) = value else {
        return Ok(existing);
    };
    if empty_clears_override && value.trim().is_empty() {
        return Ok(None);
    }
    encode_optional_page_text(key, page_id, field, Some(value))
}

fn restore_state_before_answer_muted(
    conn: &Connection,
    key: &[u8; 32],
    page_id: &str,
) -> Result<crate::knowledge::KnowledgePageState> {
    let snapshots = list_knowledge_page_version_snapshots_internal(conn, key, page_id, 8)?;
    Ok(snapshots
        .into_iter()
        .find_map(|snapshot| {
            (snapshot.state != crate::knowledge::KnowledgePageState::AnswerMuted)
                .then_some(snapshot.state)
        })
        .unwrap_or(crate::knowledge::KnowledgePageState::Active))
}

fn count_conflicts_for_claim_ids(
    conn: &Connection,
    key: &[u8; 32],
    claim_ids: &[String],
) -> Result<i64> {
    let mut by_facet = std::collections::BTreeMap::<
        String,
        std::collections::BTreeSet<String>,
    >::new();
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

pub fn archive_knowledge_page(
    conn: &Connection,
    key: &[u8; 32],
    page_id: &str,
    note: Option<String>,
) -> Result<crate::knowledge::KnowledgePageDetail> {
    set_knowledge_page_state(
        conn,
        key,
        page_id,
        crate::knowledge::KnowledgePageState::Archived,
        crate::knowledge::KnowledgePageChangeType::Archived,
        note,
    )
}

pub fn remove_knowledge_page(
    conn: &Connection,
    key: &[u8; 32],
    page_id: &str,
    note: Option<String>,
) -> Result<crate::knowledge::KnowledgePageDetail> {
    set_knowledge_page_state(
        conn,
        key,
        page_id,
        crate::knowledge::KnowledgePageState::Removed,
        crate::knowledge::KnowledgePageChangeType::Removed,
        note,
    )
}

pub fn merge_knowledge_page_into(
    conn: &Connection,
    key: &[u8; 32],
    page_id: &str,
    target_page_id: &str,
    note: Option<String>,
) -> Result<crate::knowledge::KnowledgePageDetail> {
    if page_id == target_page_id {
        return Err(anyhow!("cannot merge a page into itself"));
    }
    conn.execute_batch("BEGIN IMMEDIATE;")?;
    let result = (|| -> Result<crate::knowledge::KnowledgePageDetail> {
        let source_row = load_stored_knowledge_page_row(conn, page_id)?
            .ok_or_else(|| anyhow!("knowledge page not found: {page_id}"))?;
        let target_row = load_stored_knowledge_page_row(conn, target_page_id)?
            .ok_or_else(|| anyhow!("knowledge page not found: {target_page_id}"))?;
        let source = stored_row_to_page(key, &source_row)?;
        let target = stored_row_to_page(key, &target_row)?;
        if source.page_type != target.page_type {
            return Err(anyhow!(
                "knowledge pages can only be merged within the same page type"
            ));
        }

        let now = now_ms();
        let merged_reason = note.unwrap_or_else(|| format!("Merged into {target_page_id}."));
        let merged_tags = normalize_knowledge_string_set(
            &target
                .tags
                .iter()
                .chain(source.tags.iter())
                .chain(std::iter::once(&MERGED_PROVENANCE_TAG.to_string()))
                .cloned()
                .collect::<Vec<_>>(),
            32,
        );
        let merged_primary_evidence_ids = normalize_knowledge_string_set(
            &target
                .primary_evidence_ids
                .iter()
                .chain(source.primary_evidence_ids.iter())
                .cloned()
                .collect::<Vec<_>>(),
            32,
        );
        let merged_related_page_ids = normalize_knowledge_string_set(
            &target
                .related_page_ids
                .iter()
                .chain(source.related_page_ids.iter())
                .filter(|value| value.as_str() != page_id && value.as_str() != target_page_id)
                .cloned()
                .collect::<Vec<_>>(),
            32,
        );
        let merged_source_document_ids = normalize_knowledge_string_set(
            &target_row
                .source_document_ids
                .iter()
                .chain(source_row.source_document_ids.iter())
                .cloned()
                .collect::<Vec<_>>(),
            128,
        );
        let merged_claim_ids = normalize_knowledge_string_set(
            &target_row
                .claim_ids
                .iter()
                .chain(source_row.claim_ids.iter())
                .cloned()
                .collect::<Vec<_>>(),
            256,
        );
        let merged_summary = merge_page_text(&target.current_summary, &source.current_summary);
        let merged_body = merge_page_text(&target.current_body, &source.current_body);
        let merged_confidence = target.confidence_level.max(source.confidence_level);
        let merged_source_count = target.source_count.saturating_add(source.source_count);
        let merged_conflict_count =
            count_conflicts_for_claim_ids(conn, key, &merged_claim_ids)?;
        let merged_source_tags = normalize_knowledge_string_set(
            &source
                .tags
                .iter()
                .chain(std::iter::once(&MERGED_ARCHIVED_TAG.to_string()))
                .cloned()
                .collect::<Vec<_>>(),
            32,
        );
        let merged_target_state = match target.state {
            crate::knowledge::KnowledgePageState::Archived
            | crate::knowledge::KnowledgePageState::Removed => {
                crate::knowledge::KnowledgePageState::Active
            }
            state => state,
        };
        let merged_target_allowed = match merged_target_state {
            crate::knowledge::KnowledgePageState::Archived
            | crate::knowledge::KnowledgePageState::Removed => false,
            _ => target.answer_policy.default_allowed,
        };
        let merged_target_policy =
            answer_policy_for_state_with_override(merged_target_state, merged_target_allowed);

        conn.execute(
            r#"UPDATE knowledge_pages
               SET state = ?2,
                   answer_default_allowed = ?3,
                   answer_requires_temporal_framing = ?4,
                   confidence_level = ?5,
                   source_count = ?6,
                   conflict_count = ?7,
                   updated_at_ms = ?8,
                   human_corrected = 1,
                   tags_json = ?9,
                   primary_evidence_json = ?10,
                   related_page_ids_json = ?11,
                   source_document_ids_json = ?12,
                   claim_ids_json = ?13,
                   compiled_summary = ?14,
                   compiled_body = ?15,
                   manual_summary = ?16,
                   manual_body = ?17
               WHERE page_id = ?1"#,
            params![
                target_page_id,
                encode_page_state(merged_target_state)?,
                if merged_target_policy.default_allowed { 1 } else { 0 },
                if merged_target_policy.requires_temporal_framing { 1 } else { 0 },
                merged_confidence,
                merged_source_count,
                merged_conflict_count,
                now,
                encode_string_list(&merged_tags)?,
                encode_string_list(&merged_primary_evidence_ids)?,
                encode_string_list(&merged_related_page_ids)?,
                encode_string_list(&merged_source_document_ids)?,
                encode_string_list(&merged_claim_ids)?,
                encode_knowledge_page_text(key, target_page_id, "compiled_summary", &merged_summary)?,
                encode_knowledge_page_text(key, target_page_id, "compiled_body", &merged_body)?,
                encode_knowledge_page_text(key, target_page_id, "manual_summary", &merged_summary)?,
                encode_knowledge_page_text(key, target_page_id, "manual_body", &merged_body)?,
            ],
        )?;
        conn.execute(
            r#"UPDATE knowledge_pages
               SET state = ?2,
                   answer_default_allowed = 0,
                   answer_requires_temporal_framing = 0,
                   updated_at_ms = ?3,
                   tags_json = ?4
               WHERE page_id = ?1"#,
            params![
                page_id,
                encode_page_state(crate::knowledge::KnowledgePageState::Archived)?,
                now,
                encode_string_list(&merged_source_tags)?,
            ],
        )?;
        record_knowledge_page_change(
            conn,
            key,
            page_id,
            crate::knowledge::KnowledgePageChangeType::Merged,
            "user",
            Some(&merged_reason),
            true,
            now,
        )?;
        record_knowledge_page_change(
            conn,
            key,
            target_page_id,
            crate::knowledge::KnowledgePageChangeType::Updated,
            "user",
            Some(&format!("Merged content and provenance from {page_id}.")),
            false,
            now,
        )?;
        let updated_target = get_knowledge_page_detail(conn, key, target_page_id)?
            .ok_or_else(|| anyhow!("knowledge page missing after target merge"))?;
        replace_knowledge_page_lints(
            conn,
            target_page_id,
            &build_knowledge_page_lints(&updated_target.page, &updated_target.source_document_ids),
        )?;
        let updated = get_knowledge_page_detail(conn, key, page_id)?
            .ok_or_else(|| anyhow!("knowledge page missing after merge"))?;
        replace_knowledge_page_lints(
            conn,
            page_id,
            &build_knowledge_page_lints(&updated.page, &updated.source_document_ids),
        )?;
        get_knowledge_page_detail(conn, key, page_id)?
            .ok_or_else(|| anyhow!("knowledge page missing after merge lint refresh"))
    })();

    match result {
        Ok(detail) => {
            conn.execute_batch("COMMIT;")?;
            Ok(detail)
        }
        Err(error) => {
            let _ = conn.execute_batch("ROLLBACK;");
            Err(error)
        }
    }
}

fn set_knowledge_page_state(
    conn: &Connection,
    key: &[u8; 32],
    page_id: &str,
    next_state: crate::knowledge::KnowledgePageState,
    change_type: crate::knowledge::KnowledgePageChangeType,
    note: Option<String>,
) -> Result<crate::knowledge::KnowledgePageDetail> {
    run_knowledge_page_mutation(conn, || {
        let now = now_ms();
        let Some(detail) = get_knowledge_page_detail(conn, key, page_id)? else {
            return Err(anyhow!("knowledge page not found: {page_id}"));
        };
        let next_policy = crate::knowledge::state_default_answer_policy(next_state);
        let mut next_tags = detail
            .page
            .tags
            .iter()
            .filter(|tag| tag.as_str() != MANUAL_REMOVED_TAG)
            .cloned()
            .collect::<Vec<_>>();
        if next_state == crate::knowledge::KnowledgePageState::Removed {
            next_tags.push(MANUAL_REMOVED_TAG.to_string());
        }
        let next_tags = normalize_knowledge_string_set(&next_tags, 32);
        conn.execute(
            r#"UPDATE knowledge_pages
               SET state = ?2,
                   answer_default_allowed = ?3,
                   answer_requires_temporal_framing = ?4,
                   updated_at_ms = ?5,
                   tags_json = ?6
               WHERE page_id = ?1"#,
            params![
                page_id,
                encode_page_state(next_state)?,
                if next_policy.default_allowed { 1 } else { 0 },
                if next_policy.requires_temporal_framing { 1 } else { 0 },
                now,
                encode_string_list(&next_tags)?,
            ],
        )?;
        record_knowledge_page_change(
            conn,
            key,
            page_id,
            change_type,
            "user",
            note.as_deref(),
            true,
            now,
        )?;
        let updated = get_knowledge_page_detail(conn, key, page_id)?
            .ok_or_else(|| anyhow!("knowledge page missing after state update"))?;
        replace_knowledge_page_lints(
            conn,
            page_id,
            &build_knowledge_page_lints(&updated.page, &updated.source_document_ids),
        )?;
        get_knowledge_page_detail(conn, key, page_id)?
            .ok_or_else(|| anyhow!("knowledge page missing after lint refresh"))
    })
}

fn run_knowledge_page_mutation<T, F>(conn: &Connection, action: F) -> Result<T>
where
    F: FnOnce() -> Result<T>,
{
    conn.execute_batch("BEGIN IMMEDIATE;")?;
    let result = action();

    match result {
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
