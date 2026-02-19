const TAG_MERGE_FEEDBACK_ACTION_ACCEPT: &str = "accept";
const TAG_MERGE_FEEDBACK_ACTION_DISMISS: &str = "dismiss";
const TAG_MERGE_FEEDBACK_ACTION_LATER: &str = "later";

fn normalize_tag_merge_key(raw: &str) -> String {
    normalize_tag_name(raw)
        .chars()
        .filter(|ch| ch.is_alphanumeric())
        .collect::<String>()
}

fn load_tag_usage_counts(conn: &Connection) -> Result<std::collections::BTreeMap<String, i64>> {
    let mut stmt = conn.prepare(
        r#"SELECT tag_id, COUNT(*)
           FROM message_tags
           GROUP BY tag_id"#,
    )?;
    let mut rows = stmt.query([])?;
    let mut out = std::collections::BTreeMap::<String, i64>::new();
    while let Some(row) = rows.next()? {
        let tag_id: String = row.get(0)?;
        let usage_count: i64 = row.get(1)?;
        out.insert(tag_id, usage_count);
    }
    Ok(out)
}

fn choose_merge_direction<'a>(
    left: &'a Tag,
    right: &'a Tag,
    usage_counts: &std::collections::BTreeMap<String, i64>,
) -> (&'a Tag, &'a Tag, i64, i64) {
    let left_usage = usage_counts.get(&left.id).copied().unwrap_or(0);
    let right_usage = usage_counts.get(&right.id).copied().unwrap_or(0);

    if left.is_system && !right.is_system {
        return (right, left, right_usage, left_usage);
    }
    if right.is_system && !left.is_system {
        return (left, right, left_usage, right_usage);
    }

    if left_usage < right_usage {
        return (left, right, left_usage, right_usage);
    }
    if right_usage < left_usage {
        return (right, left, right_usage, left_usage);
    }

    if left.created_at_ms > right.created_at_ms {
        return (left, right, left_usage, right_usage);
    }
    if right.created_at_ms > left.created_at_ms {
        return (right, left, right_usage, left_usage);
    }

    if left.id > right.id {
        return (left, right, left_usage, right_usage);
    }

    (right, left, right_usage, left_usage)
}

fn push_merge_candidate(
    best_by_source: &mut std::collections::BTreeMap<String, TagMergeSuggestion>,
    source: &Tag,
    target: &Tag,
    reason: &str,
    score: f64,
    source_usage_count: i64,
    target_usage_count: i64,
) {
    if source.is_system || source.id == target.id || source_usage_count <= 0 {
        return;
    }

    let candidate = TagMergeSuggestion {
        source_tag: source.clone(),
        target_tag: target.clone(),
        reason: reason.to_string(),
        score,
        source_usage_count,
        target_usage_count,
    };

    let replace = match best_by_source.get(&source.id) {
        None => true,
        Some(existing) => {
            score > existing.score
                || (score == existing.score
                    && target_usage_count > existing.target_usage_count)
                || (score == existing.score
                    && target_usage_count == existing.target_usage_count
                    && target.id < existing.target_tag.id)
        }
    };

    if replace {
        best_by_source.insert(source.id.clone(), candidate);
    }
}

fn normalize_feedback_action(raw: &str) -> Option<&'static str> {
    let normalized = raw.trim().to_ascii_lowercase();
    match normalized.as_str() {
        TAG_MERGE_FEEDBACK_ACTION_ACCEPT => Some(TAG_MERGE_FEEDBACK_ACTION_ACCEPT),
        TAG_MERGE_FEEDBACK_ACTION_DISMISS => Some(TAG_MERGE_FEEDBACK_ACTION_DISMISS),
        TAG_MERGE_FEEDBACK_ACTION_LATER => Some(TAG_MERGE_FEEDBACK_ACTION_LATER),
        _ => None,
    }
}

pub fn record_tag_merge_feedback(
    conn: &Connection,
    source_tag_id: &str,
    target_tag_id: &str,
    reason: &str,
    action: &str,
) -> Result<()> {
    let source_tag_id = source_tag_id.trim();
    if source_tag_id.is_empty() {
        return Err(anyhow!("source_tag_id cannot be empty"));
    }

    let target_tag_id = target_tag_id.trim();
    if target_tag_id.is_empty() {
        return Err(anyhow!("target_tag_id cannot be empty"));
    }

    if source_tag_id == target_tag_id {
        return Err(anyhow!("source_tag_id and target_tag_id must differ"));
    }

    let action = normalize_feedback_action(action)
        .ok_or_else(|| anyhow!("unsupported feedback action: {action}"))?;

    let reason = reason.trim();
    let reason = if reason.is_empty() {
        "manual"
    } else {
        reason
    };

    let (accept_inc, dismiss_inc, later_inc) = match action {
        TAG_MERGE_FEEDBACK_ACTION_ACCEPT => (1i64, 0i64, 0i64),
        TAG_MERGE_FEEDBACK_ACTION_DISMISS => (0i64, 1i64, 0i64),
        TAG_MERGE_FEEDBACK_ACTION_LATER => (0i64, 0i64, 1i64),
        _ => unreachable!(),
    };

    let now = now_ms();
    conn.execute(
        r#"INSERT INTO tag_merge_feedback(
               source_tag_id,
               target_tag_id,
               reason,
               accept_count,
               dismiss_count,
               later_count,
               updated_at_ms
           )
           VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
           ON CONFLICT(source_tag_id, target_tag_id, reason) DO UPDATE SET
             accept_count = tag_merge_feedback.accept_count + excluded.accept_count,
             dismiss_count = tag_merge_feedback.dismiss_count + excluded.dismiss_count,
             later_count = tag_merge_feedback.later_count + excluded.later_count,
             updated_at_ms = excluded.updated_at_ms"#,
        params![
            source_tag_id,
            target_tag_id,
            reason,
            accept_inc,
            dismiss_inc,
            later_inc,
            now
        ],
    )?;

    Ok(())
}

fn feedback_pair_adjustment(accept_count: i64, dismiss_count: i64, later_count: i64) -> f64 {
    let accepted = accept_count.max(0) as f64;
    let dismissed = dismiss_count.max(0) as f64;
    let later = later_count.max(0) as f64;

    let delta = accepted * 0.22 - dismissed * 0.36 - later * 0.14;
    delta.clamp(-0.45, 0.35)
}

fn load_pair_feedback_adjustments(
    conn: &Connection,
) -> Result<std::collections::BTreeMap<(String, String), f64>> {
    let mut stmt = conn.prepare(
        r#"SELECT source_tag_id,
                  target_tag_id,
                  SUM(accept_count) AS accept_total,
                  SUM(dismiss_count) AS dismiss_total,
                  SUM(later_count) AS later_total
           FROM tag_merge_feedback
           GROUP BY source_tag_id, target_tag_id"#,
    )?;
    let mut rows = stmt.query([])?;

    let mut out = std::collections::BTreeMap::<(String, String), f64>::new();
    while let Some(row) = rows.next()? {
        let source_tag_id: String = row.get(0)?;
        let target_tag_id: String = row.get(1)?;
        let accept_total: i64 = row.get(2)?;
        let dismiss_total: i64 = row.get(3)?;
        let later_total: i64 = row.get(4)?;

        let adjustment = feedback_pair_adjustment(accept_total, dismiss_total, later_total);
        if adjustment == 0.0 {
            continue;
        }

        out.insert((source_tag_id, target_tag_id), adjustment);
    }

    Ok(out)
}

fn load_reason_feedback_adjustments(conn: &Connection) -> Result<std::collections::BTreeMap<String, f64>> {
    let mut stmt = conn.prepare(
        r#"SELECT reason,
                  SUM(accept_count) AS accept_total,
                  SUM(dismiss_count) AS dismiss_total,
                  SUM(later_count) AS later_total
           FROM tag_merge_feedback
           GROUP BY reason"#,
    )?;
    let mut rows = stmt.query([])?;

    let mut out = std::collections::BTreeMap::<String, f64>::new();
    while let Some(row) = rows.next()? {
        let reason: String = row.get(0)?;
        let accept_total: i64 = row.get(1)?;
        let dismiss_total: i64 = row.get(2)?;
        let later_total: i64 = row.get(3)?;

        let accepted = accept_total.max(0) as f64;
        let dismissed = dismiss_total.max(0) as f64;
        let later = later_total.max(0) as f64;

        let mut adjustment = accepted * 0.05 - dismissed * 0.16 - later * 0.07;

        if reason == "name_contains" {
            let total = accepted + dismissed + later;
            if dismissed >= 3.0 && total > 0.0 {
                let dismiss_ratio = dismissed / total;
                if dismiss_ratio >= 0.6 {
                    adjustment -= 0.18;
                }
            }
        }

        adjustment = adjustment.clamp(-0.40, 0.12);
        if adjustment == 0.0 {
            continue;
        }

        out.insert(reason, adjustment);
    }

    Ok(out)
}

pub fn apply_tag_merge_feedback_scores(
    conn: &Connection,
    suggestions: &mut [TagMergeSuggestion],
) -> Result<()> {
    if suggestions.is_empty() {
        return Ok(());
    }

    let pair_adjustments = load_pair_feedback_adjustments(conn)?;
    let reason_adjustments = load_reason_feedback_adjustments(conn)?;

    for suggestion in suggestions {
        let pair_key = (
            suggestion.source_tag.id.clone(),
            suggestion.target_tag.id.clone(),
        );

        let pair_delta = pair_adjustments.get(&pair_key).copied().unwrap_or(0.0);
        let reason_delta = reason_adjustments
            .get(suggestion.reason.as_str())
            .copied()
            .unwrap_or(0.0);

        suggestion.score = (suggestion.score + pair_delta + reason_delta).clamp(0.01, 0.99);
    }

    Ok(())
}
