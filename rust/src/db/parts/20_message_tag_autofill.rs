const KV_MESSAGE_TAG_AUTOFILL_APPLY_ENABLED: &str = "tag_autofill.apply_enabled";
const MESSAGE_TAG_AUTOFILL_SCORE_THRESHOLD: f64 = 0.90;
const MESSAGE_TAG_AUTOFILL_MIN_SOURCE_COUNT: usize = 2;

#[derive(Clone, Debug)]
struct MessageTagAutofillJobRow {
    message_id: String,
    attempts: i64,
}

#[derive(Clone, Debug, Default)]
struct MessageTagAutofillCandidateScore {
    sources: std::collections::BTreeSet<String>,
    scores: Vec<f64>,
}

#[derive(Clone, Debug)]
struct MessageTagAutofillRankedCandidate {
    candidate_tag: String,
    score: f64,
    margin: f64,
    source_count: usize,
    sources: Vec<String>,
}

#[derive(Clone, Debug)]
struct MessageTagAutofillDecision {
    candidates: Vec<MessageTagAutofillRankedCandidate>,
    decision: &'static str,
    evidence: serde_json::Value,
}

fn message_tag_autofill_backoff_ms(attempts: i64) -> i64 {
    let clamped = attempts.clamp(1, 8);
    let base = 15_000i64;
    base.saturating_mul(1i64 << (clamped - 1))
}

fn message_tag_autofill_apply_enabled(conn: &Connection) -> bool {
    match kv_get_string(conn, KV_MESSAGE_TAG_AUTOFILL_APPLY_ENABLED) {
        Ok(Some(raw)) => {
            let normalized = raw.trim().to_ascii_lowercase();
            !(normalized == "0"
                || normalized == "false"
                || normalized == "no"
                || normalized == "off")
        }
        _ => true,
    }
}

fn add_candidate_signal(
    candidates: &mut std::collections::HashMap<String, MessageTagAutofillCandidateScore>,
    candidate_tag: &str,
    source: &str,
    score: f64,
) {
    let normalized_candidate = normalize_tag_name(candidate_tag);
    if normalized_candidate.is_empty() {
        return;
    }

    let score = score.clamp(0.0, 1.0);
    if score <= 0.0 {
        return;
    }

    let entry = candidates
        .entry(normalized_candidate)
        .or_default();
    if entry.sources.insert(source.to_string()) {
        entry.scores.push(score);
    }
}

fn combined_confidence(scores: &[f64]) -> f64 {
    if scores.is_empty() {
        return 0.0;
    }

    let mut remaining = 1.0f64;
    for value in scores {
        remaining *= 1.0 - value.clamp(0.0, 1.0);
    }
    (1.0 - remaining).clamp(0.0, 1.0)
}

fn direct_system_key_token_match(content: &str) -> Option<&'static str> {
    let normalized = normalize_tag_name(content);
    if normalized.is_empty() {
        return None;
    }

    let tokens = normalized.split_whitespace().collect::<Vec<_>>();
    if let Some(key) = SYSTEM_TAG_KEYS
        .into_iter()
        .find(|key| normalized == *key || tokens.contains(key))
    {
        return Some(key);
    }

    let has_non_ascii = !normalized.is_ascii();
    if !has_non_ascii {
        return None;
    }

    map_to_system_key(&normalized)
}

fn list_attachment_suggested_tag_signals_for_autofill(
    conn: &Connection,
    db_key: &[u8; 32],
    message_id: &str,
) -> Result<Vec<(String, String)>> {
    let payloads = list_message_attachment_annotation_payloads(conn, db_key, message_id)?;

    let mut out = Vec::<(String, String)>::new();

    for (index, payload) in payloads.iter().enumerate() {
        let mut payload_tags = Vec::<String>::new();
        let mut payload_seen = std::collections::HashSet::<String>::new();
        collect_suggested_tags_from_payload(payload, &mut payload_tags, &mut payload_seen, 0);
        payload_tags.truncate(MAX_SUGGESTED_TAGS_PER_MESSAGE);

        for tag in payload_tags {
            out.push((tag, format!("attachment_suggested_tag:{index}")));
        }
    }

    Ok(out)
}

fn evaluate_message_tag_autofill(
    conn: &Connection,
    db_key: &[u8; 32],
    message_id: &str,
) -> Result<MessageTagAutofillDecision> {
    let message = match get_message_by_id_optional(conn, db_key, message_id)? {
        Some(value) => value,
        None => {
            return Ok(MessageTagAutofillDecision {
                candidates: Vec::new(),
                decision: "skip",
                evidence: serde_json::json!({
                    "reason": "message_missing"
                }),
            });
        }
    };

    if message.role != "user" {
        return Ok(MessageTagAutofillDecision {
            candidates: Vec::new(),
            decision: "skip",
            evidence: serde_json::json!({
                "reason": "not_user_message"
            }),
        });
    }

    let content = message.content.trim();
    let mut candidates = std::collections::HashMap::<String, MessageTagAutofillCandidateScore>::new();

    if let Some(system_key) = map_to_system_key(content) {
        let score = if normalize_tag_name(content) == system_key {
            0.98
        } else {
            0.76
        };
        add_candidate_signal(
            &mut candidates,
            system_key,
            "text_domain_map",
            score,
        );
    }

    if let Some(system_key) = direct_system_key_token_match(content) {
        add_candidate_signal(
            &mut candidates,
            system_key,
            "text_system_key_token",
            0.72,
        );
    }

    for (suggested, source) in list_attachment_suggested_tag_signals_for_autofill(conn, db_key, message_id)? {
        add_candidate_signal(
            &mut candidates,
            &suggested,
            &source,
            0.78,
        );
    }

    if candidates.is_empty() {
        return Ok(MessageTagAutofillDecision {
            candidates: Vec::new(),
            decision: "skip",
            evidence: serde_json::json!({
                "reason": "no_candidates"
            }),
        });
    }

    let mut ranked = candidates
        .iter()
        .map(|(candidate, info)| {
            MessageTagAutofillRankedCandidate {
                candidate_tag: candidate.to_string(),
                score: combined_confidence(&info.scores),
                margin: 0.0,
                source_count: info.sources.len(),
                sources: info.sources.iter().cloned().collect::<Vec<_>>(),
            }
        })
        .collect::<Vec<_>>();

    ranked.sort_by(|a, b| {
        b.score
            .partial_cmp(&a.score)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| b.source_count.cmp(&a.source_count))
            .then_with(|| a.candidate_tag.cmp(&b.candidate_tag))
    });

    for index in 0..ranked.len() {
        let next_score = ranked.get(index + 1).map(|item| item.score).unwrap_or(0.0);
        ranked[index].margin = (ranked[index].score - next_score).max(0.0);
    }

    let mut selected_candidates = ranked
        .iter()
        .filter(|candidate| {
            candidate.score >= MESSAGE_TAG_AUTOFILL_SCORE_THRESHOLD
                && candidate.source_count >= MESSAGE_TAG_AUTOFILL_MIN_SOURCE_COUNT
                && SYSTEM_TAG_KEYS.contains(&candidate.candidate_tag.as_str())
        })
        .take(MAX_SUGGESTED_TAGS_PER_MESSAGE)
        .cloned()
        .collect::<Vec<_>>();

    let decision = if selected_candidates.is_empty() {
        selected_candidates = ranked
            .iter()
            .take(MAX_SUGGESTED_TAGS_PER_MESSAGE)
            .cloned()
            .collect::<Vec<_>>();
        "suggest_only"
    } else {
        "apply_candidate"
    };

    let evidence_candidates = ranked
        .iter()
        .take(3)
        .map(|candidate| {
            serde_json::json!({
                "candidate": candidate.candidate_tag,
                "score": candidate.score,
                "margin": candidate.margin,
                "source_count": candidate.source_count,
                "sources": candidate.sources,
            })
        })
        .collect::<Vec<_>>();

    Ok(MessageTagAutofillDecision {
        candidates: selected_candidates.clone(),
        decision,
        evidence: serde_json::json!({
            "candidates": evidence_candidates,
            "selected_candidate_tags": selected_candidates
                .iter()
                .map(|candidate| candidate.candidate_tag.clone())
                .collect::<Vec<_>>(),
            "content_len": content.chars().count(),
        }),
    })
}

fn mark_message_tag_autofill_job_running(
    conn: &Connection,
    message_id: &str,
    now_ms: i64,
) -> Result<()> {
    conn.execute(
        r#"
UPDATE message_tag_autofill_jobs
SET status = 'running',
    updated_at_ms = ?2
WHERE message_id = ?1
"#,
        params![message_id, now_ms],
    )?;
    Ok(())
}

fn mark_message_tag_autofill_job_succeeded(
    conn: &Connection,
    message_id: &str,
    now_ms: i64,
) -> Result<()> {
    conn.execute(
        r#"
UPDATE message_tag_autofill_jobs
SET status = 'succeeded',
    next_retry_at_ms = NULL,
    last_error = NULL,
    updated_at_ms = ?2
WHERE message_id = ?1
"#,
        params![message_id, now_ms],
    )?;
    Ok(())
}

fn mark_message_tag_autofill_job_failed(
    conn: &Connection,
    message_id: &str,
    attempts: i64,
    next_retry_at_ms: i64,
    last_error: &str,
    now_ms: i64,
) -> Result<()> {
    conn.execute(
        r#"
UPDATE message_tag_autofill_jobs
SET status = 'failed',
    attempts = ?2,
    next_retry_at_ms = ?3,
    last_error = ?4,
    updated_at_ms = ?5
WHERE message_id = ?1
"#,
        params![message_id, attempts, next_retry_at_ms, last_error, now_ms],
    )?;
    Ok(())
}

fn list_due_message_tag_autofill_jobs(
    conn: &Connection,
    now_ms: i64,
    limit: i64,
) -> Result<Vec<MessageTagAutofillJobRow>> {
    let limit = limit.clamp(1, 200);
    let mut stmt = conn.prepare(
        r#"
SELECT message_id,
       attempts
FROM message_tag_autofill_jobs
WHERE status IN ('pending', 'failed', 'running')
  AND (next_retry_at_ms IS NULL OR next_retry_at_ms <= ?1)
ORDER BY updated_at_ms ASC, message_id ASC
LIMIT ?2
"#,
    )?;

    let mut rows = stmt.query(params![now_ms, limit])?;
    let mut out = Vec::<MessageTagAutofillJobRow>::new();
    while let Some(row) = rows.next()? {
        out.push(MessageTagAutofillJobRow {
            message_id: row.get(0)?,
            attempts: row.get(1)?,
        });
    }
    Ok(out)
}

fn write_message_tag_autofill_event(
    conn: &Connection,
    message_id: &str,
    decision: &MessageTagAutofillDecision,
    applied_candidate_tags: &std::collections::BTreeSet<String>,
    now_ms: i64,
) -> Result<()> {
    let evidence_json = serde_json::to_string(&decision.evidence)?;
    if decision.candidates.is_empty() {
        conn.execute(
            r#"
INSERT INTO message_tag_autofill_events(
  id,
  message_id,
  candidate_tag,
  score,
  margin,
  source_count,
  decision,
  applied,
  evidence_json,
  created_at_ms
)
VALUES (?1, ?2, NULL, 0, 0, 0, ?3, 0, ?4, ?5)
"#,
            params![
                uuid::Uuid::new_v4().to_string(),
                message_id,
                decision.decision,
                evidence_json,
                now_ms,
            ],
        )?;
        return Ok(());
    }

    for candidate in &decision.candidates {
        conn.execute(
            r#"
INSERT INTO message_tag_autofill_events(
  id,
  message_id,
  candidate_tag,
  score,
  margin,
  source_count,
  decision,
  applied,
  evidence_json,
  created_at_ms
)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
"#,
            params![
                uuid::Uuid::new_v4().to_string(),
                message_id,
                candidate.candidate_tag.as_str(),
                candidate.score,
                candidate.margin,
                candidate.source_count as i64,
                decision.decision,
                if applied_candidate_tags.contains(&candidate.candidate_tag) {
                    1i64
                } else {
                    0i64
                },
                evidence_json,
                now_ms,
            ],
        )?;
    }
    Ok(())
}

fn apply_message_tag_autofill_candidates(
    conn: &Connection,
    db_key: &[u8; 32],
    message_id: &str,
    candidate_tags: &[String],
) -> Result<std::collections::BTreeSet<String>> {
    if !message_tag_autofill_apply_enabled(conn) {
        return Ok(std::collections::BTreeSet::new());
    }

    if candidate_tags.is_empty() {
        return Ok(std::collections::BTreeSet::new());
    }

    let manual_tag_names = list_manual_message_tag_names(conn, db_key, message_id)?;
    if manual_tag_names.len() >= MAX_SUGGESTED_TAGS_PER_MESSAGE {
        return Ok(std::collections::BTreeSet::new());
    }

    let manual_tag_name_set = manual_tag_names.into_iter().collect::<std::collections::HashSet<_>>();
    let existing = list_message_tags(conn, db_key, message_id)?;
    let existing_tag_name_set = existing
        .iter()
        .map(|tag| normalize_tag_name(&tag.name))
        .collect::<std::collections::HashSet<_>>();
    let existing_autofill_tag_name_set = list_message_tag_autofill_applied_tag_names(conn, message_id)?
        .into_iter()
        .filter(|tag_name| existing_tag_name_set.contains(tag_name))
        .collect::<std::collections::HashSet<_>>();
    let remaining_budget = MAX_SUGGESTED_TAGS_PER_MESSAGE
        .saturating_sub(manual_tag_name_set.len())
        .saturating_sub(existing_autofill_tag_name_set.len());
    if remaining_budget == 0 {
        return Ok(std::collections::BTreeSet::new());
    }

    let mut next_tag_ids = existing
        .iter()
        .map(|item| item.id.clone())
        .collect::<std::collections::BTreeSet<_>>();
    let mut newly_inserted_tag_ids = Vec::<String>::new();
    let mut applied_candidate_tags = std::collections::BTreeSet::<String>::new();

    for raw_candidate_tag in candidate_tags {
        if applied_candidate_tags.len() >= remaining_budget {
            break;
        }

        let candidate_tag = raw_candidate_tag.trim();
        if candidate_tag.is_empty() {
            continue;
        }

        let normalized_candidate_tag = normalize_tag_name(candidate_tag);
        if normalized_candidate_tag.is_empty()
            || manual_tag_name_set.contains(&normalized_candidate_tag)
            || existing_autofill_tag_name_set.contains(&normalized_candidate_tag)
            || applied_candidate_tags.contains(&normalized_candidate_tag)
        {
            continue;
        }

        let tag = upsert_tag(conn, db_key, candidate_tag)?;
        if !tag.is_system {
            continue;
        }

        if next_tag_ids.insert(tag.id.clone()) {
            newly_inserted_tag_ids.push(tag.id);
            applied_candidate_tags.insert(normalized_candidate_tag);
        }
    }

    if applied_candidate_tags.is_empty() {
        return Ok(applied_candidate_tags);
    }

    if conn.is_autocommit() {
        let next_tag_ids = next_tag_ids.into_iter().collect::<Vec<_>>();
        set_message_tags(conn, db_key, message_id, &next_tag_ids)?;
        return Ok(applied_candidate_tags);
    }

    let created_at_ms = now_ms();
    for tag_id in newly_inserted_tag_ids {
        let _ = conn.execute(
            r#"INSERT OR IGNORE INTO message_tags(message_id, tag_id, created_at_ms)
               VALUES (?1, ?2, ?3)"#,
            params![message_id, tag_id, created_at_ms],
        )?;
    }
    Ok(applied_candidate_tags)
}

fn list_message_tag_autofill_applied_tag_names(
    conn: &Connection,
    message_id: &str,
) -> Result<std::collections::HashSet<String>> {
    let mut stmt = conn.prepare(
        r#"
SELECT candidate_tag
FROM message_tag_autofill_events
WHERE message_id = ?1
  AND applied = 1
  AND candidate_tag IS NOT NULL
"#,
    )?;
    let mut rows = stmt.query(params![message_id])?;
    let mut out = std::collections::HashSet::<String>::new();
    while let Some(row) = rows.next()? {
        let Some(candidate_tag) = row.get::<_, Option<String>>(0)? else {
            continue;
        };
        let normalized = normalize_tag_name(&candidate_tag);
        if !normalized.is_empty() {
            out.insert(normalized);
        }
    }
    Ok(out)
}

pub fn enqueue_message_tag_autofill_job(
    conn: &Connection,
    message_id: &str,
    reason: &str,
    now_ms: i64,
) -> Result<()> {
    let message_id = message_id.trim();
    if message_id.is_empty() {
        return Err(anyhow!("message_id is required"));
    }

    let reason = {
        let normalized = reason.trim();
        if normalized.is_empty() {
            "manual".to_string()
        } else {
            normalized.to_string()
        }
    };

    let row: Option<(String, i64)> = conn
        .query_row(
            r#"SELECT role, COALESCE(is_deleted, 0) FROM messages WHERE id = ?1"#,
            params![message_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .optional()?;

    let Some((role, is_deleted)) = row else {
        return Ok(());
    };

    if role != "user" || is_deleted != 0 {
        return Ok(());
    }

    conn.execute(
        r#"
INSERT INTO message_tag_autofill_jobs(
  message_id,
  reason,
  status,
  attempts,
  next_retry_at_ms,
  last_error,
  created_at_ms,
  updated_at_ms
)
VALUES (?1, ?2, 'pending', 0, NULL, NULL, ?3, ?3)
ON CONFLICT(message_id) DO UPDATE SET
  reason = excluded.reason,
  status = 'pending',
  attempts = 0,
  next_retry_at_ms = NULL,
  last_error = NULL,
  updated_at_ms = excluded.updated_at_ms
"#,
        params![message_id, reason, now_ms],
    )?;

    Ok(())
}

pub fn process_pending_message_tag_autofill_jobs(
    conn: &Connection,
    db_key: &[u8; 32],
    now_ms: i64,
    limit: i64,
) -> Result<usize> {
    let jobs = list_due_message_tag_autofill_jobs(conn, now_ms, limit)?;
    if jobs.is_empty() {
        return Ok(0);
    }

    let mut processed = 0usize;

    for job in jobs {
        let message_id = job.message_id;
        if message_id.trim().is_empty() {
            continue;
        }

        let step_result: Result<()> = (|| {
            mark_message_tag_autofill_job_running(conn, &message_id, now_ms)?;

            let decision = evaluate_message_tag_autofill(conn, db_key, &message_id)?;

            let mut applied_candidate_tags = std::collections::BTreeSet::<String>::new();
            if decision.decision == "apply_candidate" {
                let candidate_tags = decision
                    .candidates
                    .iter()
                    .map(|candidate| candidate.candidate_tag.clone())
                    .collect::<Vec<_>>();
                applied_candidate_tags =
                    apply_message_tag_autofill_candidates(conn, db_key, &message_id, &candidate_tags)?;
            }

            write_message_tag_autofill_event(
                conn,
                &message_id,
                &decision,
                &applied_candidate_tags,
                now_ms,
            )?;
            mark_message_tag_autofill_job_succeeded(conn, &message_id, now_ms)?;

            Ok(())
        })();

        match step_result {
            Ok(()) => {
                processed = processed.saturating_add(1);
            }
            Err(err) => {
                let attempts = job.attempts.saturating_add(1);
                let next_retry_at_ms = now_ms.saturating_add(message_tag_autofill_backoff_ms(attempts));
                let _ = mark_message_tag_autofill_job_failed(
                    conn,
                    &message_id,
                    attempts,
                    next_retry_at_ms,
                    &err.to_string(),
                    now_ms,
                );
            }
        }
    }

    Ok(processed)
}

pub fn run_message_tag_autofill_for_message(
    conn: &Connection,
    db_key: &[u8; 32],
    message_id: &str,
    reason: &str,
    now_ms: i64,
) -> Result<()> {
    enqueue_message_tag_autofill_job(conn, message_id, reason, now_ms)?;
    let _ = process_pending_message_tag_autofill_jobs(conn, db_key, now_ms, 8)?;
    Ok(())
}

pub fn enqueue_message_tag_autofill_jobs_for_attachment_messages(
    conn: &Connection,
    attachment_sha256: &str,
    now_ms: i64,
) -> Result<u32> {
    let mut stmt = conn.prepare(
        r#"
SELECT m.id
FROM message_attachments ma
JOIN messages m ON m.id = ma.message_id
WHERE ma.attachment_sha256 = ?1
  AND COALESCE(m.is_deleted, 0) = 0
  AND m.role = 'user'
ORDER BY m.created_at ASC, m.id ASC
"#,
    )?;

    let mut rows = stmt.query(params![attachment_sha256])?;
    let mut count = 0u32;
    while let Some(row) = rows.next()? {
        let message_id: String = row.get(0)?;
        enqueue_message_tag_autofill_job(conn, &message_id, "attachment_annotation_ok", now_ms)?;
        count = count.saturating_add(1);
    }

    Ok(count)
}

pub fn list_message_tag_autofill_suggested_tags(
    conn: &Connection,
    message_id: &str,
    limit: usize,
) -> Result<Vec<String>> {
    if message_id.trim().is_empty() || limit == 0 {
        return Ok(Vec::new());
    }

    let clamped_limit = limit.clamp(1, 20) as i64;
    let mut stmt = conn.prepare(
        r#"
SELECT candidate_tag
FROM message_tag_autofill_events
WHERE message_id = ?1
  AND candidate_tag IS NOT NULL
  AND decision IN ('suggest_only', 'apply_candidate')
ORDER BY created_at_ms DESC
LIMIT ?2
"#,
    )?;

    let mut rows = stmt.query(params![message_id, clamped_limit])?;
    let mut out = Vec::<String>::new();
    let mut seen = std::collections::HashSet::<String>::new();
    while let Some(row) = rows.next()? {
        let Some(candidate_tag) = row.get::<_, Option<String>>(0)? else {
            continue;
        };
        let normalized = normalize_tag_name(&candidate_tag);
        if normalized.is_empty() {
            continue;
        }
        if seen.insert(normalized.clone()) {
            out.push(normalized);
        }
    }

    Ok(out)
}
