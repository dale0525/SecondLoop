use super::progress_metrics::{pull_progress_counts, report_pull_progress};
use super::pull_recovery::{
    attempt_remote_ahead_repair, maybe_recover_stale_since_map, repeated_remote_ahead_repair_error,
    PullResponseWithMax, RemoteAheadRepairOutcome, RemoteAheadRepairTracker,
};
use crate::crypto::{decrypt_bytes, encrypt_bytes};
use anyhow::{anyhow, Result};
use base64::engine::general_purpose::STANDARD as B64_STD;
use base64::Engine as _;
use rusqlite::{params, Connection, OptionalExtension};
use std::collections::BTreeMap;

fn reset_progress_baseline(
    since: &BTreeMap<String, i64>,
    progress_start_since: &mut BTreeMap<String, i64>,
    progress_high_water_since: &mut BTreeMap<String, i64>,
    total_ops: &mut Option<u64>,
    done_ops: &mut u64,
    reported_done: &mut u64,
) {
    *progress_start_since = since.clone();
    *progress_high_water_since = since.clone();
    *total_ops = None;
    *done_ops = 0;
    *reported_done = 0;
}

pub fn pull_with_progress(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    base_url: &str,
    vault_id: &str,
    id_token: &str,
    progress: &mut dyn FnMut(u64, u64),
) -> Result<u64> {
    const PULL_LIMIT: i64 = 500;
    let http = super::runtime::client()?;
    let mut local_device_id = super::super::get_or_create_device_id(conn)?;
    let _ = super::runtime::ensure_device_registered(
        &http,
        base_url,
        vault_id,
        id_token,
        &local_device_id,
    )?;
    let scope_id = super::runtime::scope_id(base_url, vault_id);
    let _ = super::state_machine::transition(
        conn,
        &scope_id,
        super::state_machine::ManagedVaultSyncState::PullingIncremental,
    );
    let mut since = super::load_since_map(conn, &scope_id)?;
    let mut progress_start_since = since.clone();
    let mut progress_high_water_since = progress_start_since.clone();
    let endpoint_json = super::runtime::url(base_url, &format!("/v1/vaults/{vault_id}/ops:pull"))?;
    let endpoint_json_v2 =
        super::runtime::url(base_url, &format!("/v1/vaults/{vault_id}/ops:pull_v2"))?;
    let mut applied: u64 = 0;
    let mut total_ops: Option<u64> = None;
    let mut done_ops = 0u64;
    let mut forbidden_device_recovery_attempted = false;
    let mut reported_done = 0u64;
    let mut remote_ahead_repair_tracker = RemoteAheadRepairTracker::default();
    let mut stale_cursor_recovery_attempted = false;
    loop {
        let checkpoint_state = super::checkpoint::load_checkpoint_state(conn, &scope_id)?;
        let should_try_v2 = checkpoint_state.supports_pull_v2 != Some(false);
        if should_try_v2 {
            let request_v2 = super::v2_client::PullRequestV2 {
                device_id: local_device_id.as_str(),
                checkpoint_token: checkpoint_state.checkpoint_token.as_deref(),
                since: if checkpoint_state.checkpoint_token.is_none() && !since.is_empty() {
                    Some(&since)
                } else {
                    None
                },
                limit: PULL_LIMIT,
            };
            match super::v2_client::fetch_pull_v2_json(
                &http,
                &endpoint_json_v2,
                id_token,
                &request_v2,
            )? {
                super::v2_client::PullV2RouteResult::Parsed(parsed) => {
                    super::checkpoint::mark_pull_v2_supported(conn, &scope_id, "ops:pull_v2")?;
                    if parsed.meta.reseed_required {
                        let _ = super::state_machine::transition(
                            conn,
                            &scope_id,
                            super::state_machine::ManagedVaultSyncState::ReseedRequired,
                        );
                        since = super::reseed::apply_history_lower_bound_reset(
                            conn,
                            &scope_id,
                            parsed.meta.history_lower_bound.as_ref(),
                            None,
                        )?;
                        let _ = super::state_machine::transition(
                            conn,
                            &scope_id,
                            super::state_machine::ManagedVaultSyncState::Rebootstrapping,
                        );
                        reset_progress_baseline(
                            &since,
                            &mut progress_start_since,
                            &mut progress_high_water_since,
                            &mut total_ops,
                            &mut done_ops,
                            &mut reported_done,
                        );
                        stale_cursor_recovery_attempted = false;
                        remote_ahead_repair_tracker = RemoteAheadRepairTracker::default();
                        continue;
                    }

                    if let Some(high_water) = parsed.meta.high_water {
                        let computed_done = super::v2_client::sum_since(&since);
                        total_ops = Some(high_water);
                        done_ops = report_pull_progress(
                            progress,
                            &mut reported_done,
                            computed_done.min(high_water),
                            high_water,
                        );
                    }

                    let decoded_ops: Vec<super::apply_batch::PullCipherOp> = parsed
                        .ops
                        .iter()
                        .map(|op| {
                            Ok(super::apply_batch::PullCipherOp {
                                device_id: op.device_id.clone(),
                                seq: op.seq,
                                op_id: op.op_id.clone(),
                                ciphertext: B64_STD
                                    .decode(op.ciphertext_b64.as_bytes())
                                    .map_err(|e| anyhow!("invalid ciphertext_b64: {e}"))?,
                            })
                        })
                        .collect::<Result<Vec<_>>>()?;
                    let mut next_since =
                        super::apply_batch::next_since_from_ops(&since, &decoded_ops);
                    if next_since == since && (!decoded_ops.is_empty() || parsed.meta.has_more) {
                        return Err(anyhow!("managed-vault pull_v2 made no progress"));
                    }

                    let batch_applied = super::apply_batch::apply_pull_cipher_ops(
                        conn,
                        db_key,
                        sync_key,
                        &scope_id,
                        &since,
                        &mut next_since,
                        &decoded_ops,
                    )?;
                    applied += batch_applied;

                    if let Some(high_water) = parsed.meta.high_water {
                        let computed_done = super::v2_client::sum_since(&next_since);
                        total_ops = Some(high_water);
                        done_ops = report_pull_progress(
                            progress,
                            &mut reported_done,
                            computed_done.min(high_water),
                            high_water,
                        );
                    }
                    for (device_id, next_seq) in &next_since {
                        progress_high_water_since
                            .entry(device_id.clone())
                            .and_modify(|seq| *seq = (*seq).max(*next_seq))
                            .or_insert(*next_seq);
                    }
                    super::checkpoint::store_checkpoint_success(
                        conn,
                        &scope_id,
                        &parsed.meta.generation_id,
                        parsed.meta.checkpoint_token.as_deref(),
                        parsed.meta.protocol_version,
                        "ops:pull_v2",
                    )?;
                    since = next_since;

                    if parsed.meta.has_more {
                        continue;
                    }
                    break;
                }
                super::v2_client::PullV2RouteResult::Unsupported => {
                    super::checkpoint::mark_pull_v2_unsupported(conn, &scope_id)?;
                }
                super::v2_client::PullV2RouteResult::Forbidden => {
                    if !forbidden_device_recovery_attempted {
                        forbidden_device_recovery_attempted = true;
                        if let Ok(Some(next_device_id)) =
                            super::try_recover_pull_forbidden_by_rotating_device_id(
                                conn,
                                &http,
                                base_url,
                                vault_id,
                                id_token,
                                &local_device_id,
                            )
                        {
                            local_device_id = next_device_id;
                            continue;
                        }
                    }
                }
                super::v2_client::PullV2RouteResult::RetryLegacy => {}
            }
        }

        let request = super::PullRequest {
            device_id: local_device_id.as_str(),
            since: since.clone(),
            limit: PULL_LIMIT,
        };
        let resp = http
            .post(&endpoint_json)
            .bearer_auth(id_token)
            .json(&request)
            .send()?;
        let status = resp.status();
        if status.as_u16() == 403 && !forbidden_device_recovery_attempted {
            forbidden_device_recovery_attempted = true;
            if let Ok(Some(next_device_id)) =
                super::try_recover_pull_forbidden_by_rotating_device_id(
                    conn,
                    &http,
                    base_url,
                    vault_id,
                    id_token,
                    &local_device_id,
                )
            {
                local_device_id = next_device_id;
                continue;
            }
        }
        if !status.is_success() {
            let text = resp.text().unwrap_or_default();
            return Err(anyhow!("managed-vault pull failed: HTTP {status} {text}"));
        }
        let body = resp.bytes()?;
        let parsed: PullResponseWithMax = serde_json::from_slice(body.as_ref())?;
        if !parsed.needs_reseed.is_empty() {
            since = super::reseed::apply_history_lower_bound_reset(
                conn,
                &scope_id,
                Some(&parsed.history_lower_bound),
                Some(&parsed.needs_reseed),
            )?;
            reset_progress_baseline(
                &since,
                &mut progress_start_since,
                &mut progress_high_water_since,
                &mut total_ops,
                &mut done_ops,
                &mut reported_done,
            );
            stale_cursor_recovery_attempted = false;
            remote_ahead_repair_tracker = RemoteAheadRepairTracker::default();
            continue;
        }
        if !parsed.max.is_empty() {
            let (computed_done, computed_total) =
                pull_progress_counts(&progress_start_since, &since, &parsed.max);
            total_ops = Some(computed_total);
            done_ops =
                report_pull_progress(progress, &mut reported_done, computed_done, computed_total);
        }
        let mut next_since = since.clone();
        for (device_id, last_seq) in &parsed.next {
            next_since.insert(device_id.to_string(), *last_seq);
        }
        if next_since == since && !parsed.ops.is_empty() {
            return Err(anyhow!("managed-vault pull made no progress"));
        }
        if parsed.ops.is_empty() {
            match attempt_remote_ahead_repair(
                &mut remote_ahead_repair_tracker,
                conn,
                &scope_id,
                &local_device_id,
                &mut since,
                &parsed.max,
            )? {
                RemoteAheadRepairOutcome::Recovered => {
                    let (computed_done, computed_total) =
                        pull_progress_counts(&progress_start_since, &since, &parsed.max);
                    total_ops = Some(computed_total);
                    done_ops = report_pull_progress(
                        progress,
                        &mut reported_done,
                        computed_done,
                        computed_total,
                    );
                    continue;
                }
                RemoteAheadRepairOutcome::Exhausted(devices) => {
                    return Err(repeated_remote_ahead_repair_error(&devices));
                }
                RemoteAheadRepairOutcome::NotNeeded => {}
            }

            if !stale_cursor_recovery_attempted
                && maybe_recover_stale_since_map(conn, &scope_id, &local_device_id, &mut since)?
            {
                stale_cursor_recovery_attempted = true;
                continue;
            }
        }
        let decoded_ops: Vec<super::apply_batch::PullCipherOp> = parsed
            .ops
            .iter()
            .map(|op| {
                Ok(super::apply_batch::PullCipherOp {
                    device_id: op.device_id.clone(),
                    seq: op.seq,
                    op_id: op.op_id.clone(),
                    ciphertext: B64_STD
                        .decode(op.ciphertext_b64.as_bytes())
                        .map_err(|e| anyhow!("invalid ciphertext_b64: {e}"))?,
                })
            })
            .collect::<Result<Vec<_>>>()?;
        let batch_applied = super::apply_batch::apply_pull_cipher_ops(
            conn,
            db_key,
            sync_key,
            &scope_id,
            &since,
            &mut next_since,
            &decoded_ops,
        )?;
        applied += batch_applied;

        if !parsed.max.is_empty() {
            let (computed_done, computed_total) =
                pull_progress_counts(&progress_start_since, &next_since, &parsed.max);
            total_ops = Some(computed_total);
            done_ops =
                report_pull_progress(progress, &mut reported_done, computed_done, computed_total);
        } else if let Some(total) = total_ops {
            let mut delta = 0u64;
            for (device_id, next_seq) in &next_since {
                let prev = progress_high_water_since
                    .get(device_id)
                    .copied()
                    .unwrap_or(0);
                if *next_seq > prev {
                    delta += (*next_seq - prev) as u64;
                }
            }
            done_ops += delta;
            done_ops = report_pull_progress(progress, &mut reported_done, done_ops, total);
        } else {
            let mut delta = 0u64;
            for (device_id, next_seq) in &next_since {
                let prev = since.get(device_id).copied().unwrap_or(0);
                if *next_seq > prev {
                    delta += (*next_seq - prev) as u64;
                }
            }
            done_ops += delta;
            if delta > 0 {
                progress(done_ops, done_ops.saturating_add(1));
                reported_done = done_ops;
            }
        }
        for (device_id, next_seq) in &next_since {
            progress_high_water_since
                .entry(device_id.clone())
                .and_modify(|seq| *seq = (*seq).max(*next_seq))
                .or_insert(*next_seq);
        }
        since = next_since;
        if parsed.ops.len() < (PULL_LIMIT as usize) {
            match attempt_remote_ahead_repair(
                &mut remote_ahead_repair_tracker,
                conn,
                &scope_id,
                &local_device_id,
                &mut since,
                &parsed.max,
            )? {
                RemoteAheadRepairOutcome::Recovered => continue,
                RemoteAheadRepairOutcome::Exhausted(devices) => {
                    return Err(repeated_remote_ahead_repair_error(&devices));
                }
                RemoteAheadRepairOutcome::NotNeeded => {}
            }

            if !stale_cursor_recovery_attempted
                && maybe_recover_stale_since_map(conn, &scope_id, &local_device_id, &mut since)?
            {
                stale_cursor_recovery_attempted = true;
                continue;
            }
            break;
        }
    }

    let _ = super::state_machine::transition(
        conn,
        &scope_id,
        super::state_machine::ManagedVaultSyncState::BlobBackfill,
    );
    let app_dir = super::super::app_dir_from_conn(conn)?;
    let download_ctx = super::attachments::AttachmentUploadContext {
        conn,
        db_key,
        sync_key,
        http: &http,
        base_url,
        vault_id,
        id_token,
        app_dir: app_dir.as_path(),
    };

    let missing_blob_refs =
        super::artifacts::list_missing_embedding_artifact_blob_refs(&download_ctx)?;
    let mut total_units = total_ops.unwrap_or(done_ops);
    let mut done_units = done_ops;
    if !missing_blob_refs.is_empty() {
        total_units += missing_blob_refs.len() as u64;
        progress(done_units, total_units);
    } else if total_ops.is_some() || done_ops > 0 {
        progress(done_units, total_units);
    }

    if !missing_blob_refs.is_empty() {
        let mut on_downloaded = |delta: u64| {
            done_units = (done_units + delta).min(total_units);
            progress(done_units, total_units);
        };
        let outcome = super::artifacts::download_embedding_artifact_blobs_by_refs(
            &download_ctx,
            &missing_blob_refs,
            Some(&mut on_downloaded),
        )?;
        total_units = total_units.saturating_sub(outcome.missing_remote);
        done_units = done_units.min(total_units);
    }

    let _ = super::blob_repair::process_pending_blob_repairs(&download_ctx, 8)?;

    progress(done_units, total_units);
    let _ = super::state_machine::transition(
        conn,
        &scope_id,
        super::state_machine::ManagedVaultSyncState::Completed,
    );

    Ok(applied)
}

pub fn push_ops_only_with_progress(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    base_url: &str,
    vault_id: &str,
    id_token: &str,
    progress: &mut dyn FnMut(u64, u64),
) -> Result<u64> {
    const PUSH_LIMIT: i64 = 200;
    const MAX_REPAIR_ATTEMPTS: usize = 10;

    let http = super::runtime::client()?;
    let device_id = super::super::get_or_create_device_id(conn)?;
    let _ =
        super::runtime::ensure_device_registered(&http, base_url, vault_id, id_token, &device_id)?;

    let scope_id = super::runtime::scope_id(base_url, vault_id);
    let last_pushed_key = format!("managed_vault.last_pushed_seq:{scope_id}:{device_id}");
    let legacy_last_pushed_key = format!("managed_vault.last_pushed_seq:{scope_id}");
    if super::super::kv_get_i64(conn, &last_pushed_key)?.is_none() {
        let legacy = super::super::kv_get_i64(conn, &legacy_last_pushed_key)?.unwrap_or(0);
        super::super::kv_set_i64(conn, &last_pushed_key, legacy)?;
    }

    let initial_last_pushed_seq = super::super::kv_get_i64(conn, &last_pushed_key)?.unwrap_or(0);
    let mut total_ops = conn
        .query_row(
            r#"SELECT count(*) FROM oplog WHERE device_id = ?1 AND seq > ?2"#,
            params![device_id.as_str(), initial_last_pushed_seq],
            |row| row.get::<_, i64>(0),
        )?
        .max(0) as u64;

    let has_remote_device_ops: bool = conn.query_row(
        r#"SELECT EXISTS(SELECT 1 FROM oplog WHERE device_id != ?1 LIMIT 1)"#,
        params![device_id.as_str()],
        |row| row.get(0),
    )?;

    let can_skip_fresh_device_push =
        if total_ops == 0 && initial_last_pushed_seq == 0 && has_remote_device_ops {
            super::probe::managed_remote_metadata_matches_local_snapshot(
                conn, &http, base_url, vault_id, id_token, &device_id,
            )
            .unwrap_or(false)
        } else {
            false
        };

    if can_skip_fresh_device_push {
        progress(0, 0);
        return Ok(0);
    }

    crate::db::backfill_attachments_oplog_if_needed(conn, db_key)?;

    total_ops = conn
        .query_row(
            r#"SELECT count(*) FROM oplog WHERE device_id = ?1 AND seq > ?2"#,
            params![device_id.as_str(), initial_last_pushed_seq],
            |row| row.get::<_, i64>(0),
        )?
        .max(0) as u64;

    let mut done_ops = 0u64;
    progress(0, total_ops);

    if total_ops == 0 {
        return Ok(0);
    }

    let endpoint = super::runtime::url(base_url, &format!("/v1/vaults/{vault_id}/ops:push"))?;
    let mut repair_attempt = 0usize;
    let mut pushed_total = 0u64;

    loop {
        let last_pushed_seq = super::super::kv_get_i64(conn, &last_pushed_key)?.unwrap_or(0);

        let mut stmt = conn.prepare(
            r#"SELECT op_id, seq, op_json
               FROM oplog
               WHERE device_id = ?1 AND seq > ?2
               ORDER BY seq ASC
               LIMIT ?3"#,
        )?;
        let mut rows = stmt.query(params![device_id.as_str(), last_pushed_seq, PUSH_LIMIT])?;

        let mut ops: Vec<super::PushOp> = Vec::new();
        let mut max_seq = last_pushed_seq;
        while let Some(row) = rows.next()? {
            let op_id: String = row.get(0)?;
            let seq: i64 = row.get(1)?;
            let op_json_blob: Vec<u8> = row.get(2)?;

            let plaintext = decrypt_bytes(
                db_key,
                &op_json_blob,
                format!("oplog.op_json:{op_id}").as_bytes(),
            )?;

            let ciphertext = encrypt_bytes(
                sync_key,
                &plaintext,
                format!("sync.ops:{device_id}:{seq}").as_bytes(),
            )?;
            let ciphertext_b64 = B64_STD.encode(ciphertext);
            ops.push(super::PushOp {
                seq,
                op_id,
                ciphertext_b64,
            });
            max_seq = max_seq.max(seq);
        }

        if ops.is_empty() {
            break;
        }

        let resp = http
            .post(&endpoint)
            .bearer_auth(id_token)
            .json(&super::PushRequest {
                device_id: device_id.as_str(),
                ops,
            })
            .send()?;

        let status = resp.status();
        let text = resp.text().unwrap_or_default();

        if status.is_success() {
            let parsed: super::PushResponse = serde_json::from_str(&text)?;
            if parsed.max_seq > last_pushed_seq {
                super::super::kv_set_i64(conn, &last_pushed_key, parsed.max_seq)?;
            }

            let pushed = max_seq.saturating_sub(last_pushed_seq) as u64;
            pushed_total += pushed;
            done_ops = (done_ops + pushed).min(total_ops);
            progress(done_ops, total_ops);

            repair_attempt = 0;
            continue;
        }

        if status.as_u16() != 409 || repair_attempt >= MAX_REPAIR_ATTEMPTS {
            return Err(anyhow!("managed-vault push failed: HTTP {status} {text}"));
        }

        let parsed_err: super::PushErrorResponse = match serde_json::from_str(&text) {
            Ok(v) => v,
            Err(_) => return Err(anyhow!("managed-vault push failed: HTTP {status} {text}")),
        };

        if parsed_err.error == "seq_gap" {
            if let Some(expected_next) = parsed_err.expected_next_seq {
                let next_last_pushed = expected_next.saturating_sub(1).max(0);
                super::super::kv_set_i64(conn, &last_pushed_key, next_last_pushed)?;
                let min_local_pending_seq: Option<i64> = conn.query_row(
                    r#"SELECT MIN(seq) FROM oplog WHERE device_id = ?1 AND seq > ?2"#,
                    params![device_id.as_str(), next_last_pushed],
                    |row| row.get(0),
                )?;
                if let Some(min_seq) = min_local_pending_seq {
                    if min_seq > expected_next {
                        super::rebase_local_device_seqs(
                            conn,
                            db_key,
                            device_id.as_str(),
                            min_seq,
                            expected_next,
                        )?;
                    }
                }
                repair_attempt += 1;
                continue;
            }
        }

        if parsed_err.error == "conflict"
            && parsed_err.conflict_kind.as_deref() == Some("seq")
            && parsed_err.expected_next_seq.is_some()
            && parsed_err.conflict_seq.is_some()
        {
            let from_seq = parsed_err.conflict_seq.unwrap_or(0);
            let expected_next = parsed_err.expected_next_seq.unwrap_or(0);
            if from_seq > 0 && expected_next > from_seq {
                let next_last_pushed = from_seq - 1;
                super::super::kv_set_i64(
                    conn,
                    &last_pushed_key,
                    next_last_pushed.max(last_pushed_seq),
                )?;
                super::rebase_local_device_seqs(
                    conn,
                    db_key,
                    device_id.as_str(),
                    from_seq,
                    expected_next,
                )?;
                repair_attempt += 1;
                continue;
            }
        }

        if parsed_err.error == "conflict"
            && parsed_err.conflict_kind.as_deref() == Some("op_id")
            && parsed_err.expected_next_seq.is_some()
            && parsed_err.op_id.as_deref().is_some()
        {
            let conflict_op_id = parsed_err.op_id.clone().unwrap_or_default();
            if !conflict_op_id.trim().is_empty() {
                let local_conflict_seq: Option<i64> = conn
                    .query_row(
                        r#"SELECT seq FROM oplog WHERE op_id = ?1 AND device_id = ?2"#,
                        params![conflict_op_id.as_str(), device_id.as_str()],
                        |row| row.get(0),
                    )
                    .optional()?;

                if let Some(conflict_seq) = local_conflict_seq {
                    let _ = conn.execute(
                        r#"DELETE FROM oplog WHERE op_id = ?1 AND device_id = ?2"#,
                        params![conflict_op_id.as_str(), device_id.as_str()],
                    )?;

                    if conflict_seq > 0 {
                        super::rebase_local_device_seqs(
                            conn,
                            db_key,
                            device_id.as_str(),
                            conflict_seq + 1,
                            conflict_seq,
                        )?;
                    }

                    repair_attempt += 1;
                    continue;
                }
            }
        }

        return Err(anyhow!("managed-vault push failed: HTTP {status} {text}"));
    }

    if pushed_total > 0 {
        super::maybe_run_managed_vault_retention(conn, &scope_id)?;
    }

    progress(done_ops, total_ops);
    Ok(pushed_total)
}

#[cfg(test)]
mod tests;
