const KV_MESSAGE_TAG_AUTOFILL_APPLY_ENABLED: &str = "tag_autofill.apply_enabled";
const MESSAGE_TAG_AUTOFILL_SCORE_THRESHOLD: f64 = 0.90;
const MESSAGE_TAG_AUTOFILL_MARGIN_THRESHOLD: f64 = 0.18;
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
struct MessageTagAutofillDecision {
    candidate_tag: Option<String>,
    score: f64,
    margin: f64,
    source_count: usize,
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
    SYSTEM_TAG_KEYS
        .into_iter()
        .find(|key| normalized == *key || tokens.contains(key))
}

fn list_attachment_suggested_tags_for_autofill(
    conn: &Connection,
    db_key: &[u8; 32],
    message_id: &str,
) -> Result<Vec<String>> {
    let payloads = list_message_attachment_annotation_payloads(conn, db_key, message_id)?;

    let mut out = Vec::<String>::new();
    let mut seen = std::collections::HashSet::<String>::new();

    for payload in &payloads {
        collect_suggested_tags_from_payload(payload, &mut out, &mut seen, 0);
        if out.len() >= MAX_SUGGESTED_TAGS_PER_MESSAGE {
            break;
        }
    }

    out.truncate(MAX_SUGGESTED_TAGS_PER_MESSAGE);
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
                candidate_tag: None,
                score: 0.0,
                margin: 0.0,
                source_count: 0,
                decision: "skip",
                evidence: serde_json::json!({
                    "reason": "message_missing"
                }),
            });
        }
    };

    if message.role != "user" {
        return Ok(MessageTagAutofillDecision {
            candidate_tag: None,
            score: 0.0,
            margin: 0.0,
            source_count: 0,
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

    for suggested in list_attachment_suggested_tags_for_autofill(conn, db_key, message_id)? {
        add_candidate_signal(
            &mut candidates,
            &suggested,
            "attachment_suggested_tag",
            0.78,
        );
    }

    if candidates.is_empty() {
        return Ok(MessageTagAutofillDecision {
            candidate_tag: None,
            score: 0.0,
            margin: 0.0,
            source_count: 0,
            decision: "skip",
            evidence: serde_json::json!({
                "reason": "no_candidates"
            }),
        });
    }

    let mut ranked = candidates
        .iter()
        .map(|(candidate, info)| {
            (
                candidate.to_string(),
                combined_confidence(&info.scores),
                info.sources.len(),
                info.sources.iter().cloned().collect::<Vec<_>>(),
            )
        })
        .collect::<Vec<_>>();

    ranked.sort_by(|a, b| {
        b.1.partial_cmp(&a.1)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| b.2.cmp(&a.2))
            .then_with(|| a.0.cmp(&b.0))
    });

    let top = ranked[0].clone();
    let second_score = ranked.get(1).map(|item| item.1).unwrap_or(0.0);
    let margin = (top.1 - second_score).max(0.0);

    let decision = if top.1 >= MESSAGE_TAG_AUTOFILL_SCORE_THRESHOLD
        && margin >= MESSAGE_TAG_AUTOFILL_MARGIN_THRESHOLD
        && top.2 >= MESSAGE_TAG_AUTOFILL_MIN_SOURCE_COUNT
    {
        "apply_candidate"
    } else {
        "suggest_only"
    };

    let evidence_candidates = ranked
        .iter()
        .take(3)
        .map(|(candidate, score, source_count, sources)| {
            serde_json::json!({
                "candidate": candidate,
                "score": score,
                "source_count": source_count,
                "sources": sources,
            })
        })
        .collect::<Vec<_>>();

    Ok(MessageTagAutofillDecision {
        candidate_tag: Some(top.0),
        score: top.1,
        margin,
        source_count: top.2,
        decision,
        evidence: serde_json::json!({
            "candidates": evidence_candidates,
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
    applied: bool,
    now_ms: i64,
) -> Result<()> {
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
            decision.candidate_tag.as_deref(),
            decision.score,
            decision.margin,
            decision.source_count as i64,
            decision.decision,
            if applied { 1i64 } else { 0i64 },
            serde_json::to_string(&decision.evidence)?,
            now_ms,
        ],
    )?;
    Ok(())
}

fn apply_message_tag_autofill_candidate(
    conn: &Connection,
    db_key: &[u8; 32],
    message_id: &str,
    candidate_tag: &str,
) -> Result<bool> {
    if !message_tag_autofill_apply_enabled(conn) {
        return Ok(false);
    }

    let candidate_tag = candidate_tag.trim();
    if candidate_tag.is_empty() {
        return Ok(false);
    }

    let tag = upsert_tag(conn, db_key, candidate_tag)?;
    if !tag.is_system {
        return Ok(false);
    }

    let existing = list_message_tags(conn, db_key, message_id)?;
    if existing.iter().any(|item| item.id == tag.id) {
        return Ok(false);
    }

    if conn.is_autocommit() {
        let mut next_tag_ids = existing.into_iter().map(|item| item.id).collect::<Vec<_>>();
        next_tag_ids.push(tag.id);
        next_tag_ids.sort();
        next_tag_ids.dedup();
        set_message_tags(conn, db_key, message_id, &next_tag_ids)?;
        return Ok(true);
    }

    let inserted = conn.execute(
        r#"INSERT OR IGNORE INTO message_tags(message_id, tag_id, created_at_ms)
           VALUES (?1, ?2, ?3)"#,
        params![message_id, tag.id, now_ms()],
    )?;
    Ok(inserted > 0)
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

            let mut applied = false;
            if decision.decision == "apply_candidate" {
                if let Some(candidate_tag) = decision.candidate_tag.as_deref() {
                    applied = apply_message_tag_autofill_candidate(
                        conn,
                        db_key,
                        &message_id,
                        candidate_tag,
                    )?;
                }
            }

            write_message_tag_autofill_event(conn, &message_id, &decision, applied, now_ms)?;
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
