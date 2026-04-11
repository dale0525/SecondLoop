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
    let local_device_id = super::super::get_or_create_device_id(conn)?;
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
    let progress_start_since = since.clone();
    let mut progress_high_water_since = progress_start_since.clone();
    let endpoint_json = super::runtime::url(base_url, &format!("/v1/vaults/{vault_id}/ops:pull"))?;
    let endpoint_json_v2 =
        super::runtime::url(base_url, &format!("/v1/vaults/{vault_id}/ops:pull_v2"))?;
    let mut applied: u64 = 0;
    let mut total_ops: Option<u64> = None;
    let mut done_ops = 0u64;
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
                limit: PULL_LIMIT,
            };
            match super::v2_client::fetch_pull_v2_json(
                &http,
                &endpoint_json_v2,
                id_token,
                &request_v2,
            )? {
                Some(parsed) => {
                    super::checkpoint::mark_pull_v2_supported(conn, &scope_id, "ops:pull_v2")?;
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

                    if parsed.meta.reseed_required {
                        let _ = super::state_machine::transition(
                            conn,
                            &scope_id,
                            super::state_machine::ManagedVaultSyncState::ReseedRequired,
                        );
                        super::reseed::restart_incremental_pull(conn, &scope_id)?;
                        let _ = super::state_machine::transition(
                            conn,
                            &scope_id,
                            super::state_machine::ManagedVaultSyncState::Rebootstraping,
                        );
                        since.clear();
                        stale_cursor_recovery_attempted = false;
                        remote_ahead_repair_tracker = RemoteAheadRepairTracker::default();
                        continue;
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
                None => super::checkpoint::mark_pull_v2_unsupported(conn, &scope_id)?,
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
        if !status.is_success() {
            let text = resp.text().unwrap_or_default();
            return Err(anyhow!("managed-vault pull failed: HTTP {status} {text}"));
        }
        let body = resp.bytes()?;
        let parsed: PullResponseWithMax = serde_json::from_slice(body.as_ref())?;
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
mod tests {
    use super::*;

    use std::io::{Read, Write};
    use std::net::{TcpListener, TcpStream};
    use std::sync::{Arc, Mutex};
    use std::thread;

    use base64::engine::general_purpose::STANDARD as B64_STD;
    use tempfile::tempdir;

    use crate::sync::{kv_get_i64, kv_set_i64};

    #[derive(Default)]
    struct ServerState {
        seen_since_values: Vec<i64>,
        seen_secondary_since_values: Vec<i64>,
    }

    fn read_http_request(stream: &mut TcpStream) -> (String, Vec<u8>) {
        let mut raw = Vec::new();
        let mut buf = [0u8; 1024];
        let mut header_end = None;
        loop {
            let n = stream.read(&mut buf).expect("read request");
            if n == 0 {
                break;
            }
            raw.extend_from_slice(&buf[..n]);
            if let Some(pos) = raw.windows(4).position(|w| w == b"\r\n\r\n") {
                header_end = Some(pos + 4);
                break;
            }
        }

        let header_end = header_end.expect("header end");
        let headers = String::from_utf8_lossy(&raw[..header_end]).to_string();
        let content_length = headers
            .lines()
            .find_map(|line| {
                let lower = line.to_ascii_lowercase();
                lower
                    .strip_prefix("content-length:")
                    .and_then(|v| v.trim().parse::<usize>().ok())
            })
            .unwrap_or(0);
        let mut body = raw[header_end..].to_vec();
        while body.len() < content_length {
            let n = stream.read(&mut buf).expect("read body");
            if n == 0 {
                break;
            }
            body.extend_from_slice(&buf[..n]);
        }
        (headers, body)
    }

    fn respond_json(stream: &mut TcpStream, status: &str, body: &str) {
        let response = format!(
            "HTTP/1.1 {status}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
            body.len(),
            body
        );
        stream
            .write_all(response.as_bytes())
            .expect("write response");
    }

    fn spawn_progress_recovery_server(
        remote_device_id: String,
        encrypted_op_b64: String,
        expected_op_id: String,
    ) -> (String, Arc<Mutex<ServerState>>) {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind listener");
        let addr = format!("http://{}", listener.local_addr().expect("local addr"));
        let state = Arc::new(Mutex::new(ServerState::default()));
        let state_for_thread = Arc::clone(&state);

        thread::spawn(move || {
            for _ in 0..3 {
                let (mut stream, _) = listener.accept().expect("accept");
                let (headers, body) = read_http_request(&mut stream);
                let request_line = headers.lines().next().unwrap_or_default().to_string();

                if request_line.starts_with("POST /v1/vaults/test-vault/devices ") {
                    respond_json(
                        &mut stream,
                        "200 OK",
                        r#"{"device_id":"local-device-progress"}"#,
                    );
                    continue;
                }

                if request_line.starts_with("POST /v1/vaults/test-vault/ops:pull ") {
                    let payload: serde_json::Value =
                        serde_json::from_slice(&body).expect("parse pull body");
                    let since_value = payload["since"][remote_device_id.as_str()]
                        .as_i64()
                        .unwrap_or(0);
                    state_for_thread
                        .lock()
                        .expect("lock state")
                        .seen_since_values
                        .push(since_value);

                    if since_value == 174 {
                        respond_json(
                            &mut stream,
                            "200 OK",
                            &format!(
                                r#"{{"ops":[],"next":{{}},"max":{{"{device_id}":262}}}}"#,
                                device_id = remote_device_id
                            ),
                        );
                        continue;
                    }

                    if since_value == 0 {
                        respond_json(
                            &mut stream,
                            "200 OK",
                            &format!(
                                r#"{{"ops":[{{"device_id":"{device_id}","seq":262,"op_id":"{op_id}","ciphertext_b64":"{ciphertext}"}}],"next":{{"{device_id}":262}},"max":{{"{device_id}":262}}}}"#,
                                device_id = remote_device_id,
                                op_id = expected_op_id,
                                ciphertext = encrypted_op_b64,
                            ),
                        );
                        continue;
                    }

                    respond_json(
                        &mut stream,
                        "200 OK",
                        &format!(
                            r#"{{"ops":[],"next":{{"{device_id}":262}},"max":{{"{device_id}":262}}}}"#,
                            device_id = remote_device_id
                        ),
                    );
                    continue;
                }

                respond_json(&mut stream, "404 Not Found", r#"{"error":"not_found"}"#);
            }
        });

        (addr, state)
    }

    fn spawn_progress_partial_then_recovery_server(
        first_device_id: String,
        first_ops: Vec<(i64, String, String)>,
        stalled_device_id: String,
        stalled_encrypted_op_b64: String,
        stalled_op_id: String,
    ) -> (String, Arc<Mutex<ServerState>>) {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind listener");
        let addr = format!("http://{}", listener.local_addr().expect("local addr"));
        let state = Arc::new(Mutex::new(ServerState::default()));
        let state_for_thread = Arc::clone(&state);

        thread::spawn(move || {
            for _ in 0..4 {
                let (mut stream, _) = listener.accept().expect("accept");
                let (headers, body) = read_http_request(&mut stream);
                let request_line = headers.lines().next().unwrap_or_default().to_string();

                if request_line.starts_with("POST /v1/vaults/test-vault/devices ") {
                    respond_json(
                        &mut stream,
                        "200 OK",
                        r#"{"device_id":"local-device-progress"}"#,
                    );
                    continue;
                }

                if request_line.starts_with("POST /v1/vaults/test-vault/ops:pull ") {
                    let payload: serde_json::Value =
                        serde_json::from_slice(&body).expect("parse pull body");
                    let first_since = payload["since"][first_device_id.as_str()]
                        .as_i64()
                        .unwrap_or(0);
                    let stalled_since = payload["since"][stalled_device_id.as_str()]
                        .as_i64()
                        .unwrap_or(174);

                    let mut snapshot = state_for_thread.lock().expect("lock state");
                    snapshot.seen_since_values.push(stalled_since);
                    snapshot.seen_secondary_since_values.push(first_since);
                    drop(snapshot);

                    if first_since == 0 && stalled_since == 174 {
                        let first_ops_json = first_ops
                            .iter()
                            .map(|(seq, op_id, ciphertext_b64)| {
                                serde_json::json!({
                                    "device_id": first_device_id,
                                    "seq": seq,
                                    "op_id": op_id,
                                    "ciphertext_b64": ciphertext_b64,
                                })
                            })
                            .collect::<Vec<_>>();
                        respond_json(
                            &mut stream,
                            "200 OK",
                            &format!(
                                r#"{{"ops":{first_ops_json},"next":{{"{first_device_id}":500}},"max":{{"{first_device_id}":500,"{stalled_device_id}":262}}}}"#,
                                first_device_id = first_device_id,
                                first_ops_json = serde_json::Value::Array(first_ops_json),
                                stalled_device_id = stalled_device_id,
                            ),
                        );
                        continue;
                    }

                    if first_since == 500 && stalled_since == 174 {
                        respond_json(
                            &mut stream,
                            "200 OK",
                            &format!(
                                r#"{{"ops":[],"next":{{}},"max":{{"{first_device_id}":500,"{stalled_device_id}":262}}}}"#,
                                first_device_id = first_device_id,
                                stalled_device_id = stalled_device_id,
                            ),
                        );
                        continue;
                    }

                    if first_since == 500 && stalled_since == 0 {
                        respond_json(
                            &mut stream,
                            "200 OK",
                            &format!(
                                r#"{{"ops":[{{"device_id":"{stalled_device_id}","seq":262,"op_id":"{stalled_op_id}","ciphertext_b64":"{stalled_ciphertext}"}}],"next":{{"{stalled_device_id}":262}},"max":{{"{first_device_id}":500,"{stalled_device_id}":262}}}}"#,
                                first_device_id = first_device_id,
                                stalled_device_id = stalled_device_id,
                                stalled_op_id = stalled_op_id,
                                stalled_ciphertext = stalled_encrypted_op_b64,
                            ),
                        );
                        continue;
                    }

                    respond_json(
                        &mut stream,
                        "200 OK",
                        &format!(
                            r#"{{"ops":[],"next":{{"{first_device_id}":500,"{stalled_device_id}":262}},"max":{{"{first_device_id}":500,"{stalled_device_id}":262}}}}"#,
                            first_device_id = first_device_id,
                            stalled_device_id = stalled_device_id,
                        ),
                    );
                    continue;
                }

                respond_json(&mut stream, "404 Not Found", r#"{"error":"not_found"}"#);
            }
        });

        (addr, state)
    }

    #[test]
    fn pull_with_progress_recovers_when_remote_cursor_is_ahead_but_first_response_is_empty() {
        let db_key = [41u8; 32];
        let sync_key = [42u8; 32];
        let remote_device_id = "remote-device-progress";

        let dir = tempdir().expect("tempdir");
        let conn = crate::db::open(dir.path()).expect("open");
        conn.execute(
            r#"INSERT INTO kv(key, value) VALUES ('device_id', 'local-device-progress')"#,
            [],
        )
        .expect("set local device id");

        let op_id = "op-progress-recovery";
        let op_json = serde_json::json!({
            "op_id": op_id,
            "device_id": remote_device_id,
            "seq": 262,
            "ts_ms": 1_775_811_648_824i64,
            "type": "conversation.upsert.v1",
            "payload": {
                "conversation_id": "conversation-progress-recovery",
                "title": "Recovered title",
                "created_at_ms": 1_775_811_648_824i64,
                "updated_at_ms": 1_775_811_648_824i64,
            }
        });
        let plaintext = serde_json::to_vec(&op_json).expect("serialize op");
        let ciphertext = encrypt_bytes(
            &sync_key,
            &plaintext,
            format!("sync.ops:{remote_device_id}:262").as_bytes(),
        )
        .expect("encrypt op");
        let encrypted_op_b64 = B64_STD.encode(ciphertext);

        let (base_url, server_state) = spawn_progress_recovery_server(
            remote_device_id.to_string(),
            encrypted_op_b64,
            op_id.to_string(),
        );
        let scope_id = crate::sync::managed_vault::runtime::scope_id(&base_url, "test-vault");
        kv_set_i64(
            &conn,
            &format!("managed_vault.last_pulled_seq:{scope_id}:{remote_device_id}"),
            174,
        )
        .expect("set stale cursor");

        let mut seen_progress = Vec::new();
        let applied = pull_with_progress(
            &conn,
            &db_key,
            &sync_key,
            &base_url,
            "test-vault",
            "test-token",
            &mut |done, total| seen_progress.push((done, total)),
        )
        .expect("pull with recovery");

        assert_eq!(applied, 1);
        assert_eq!(seen_progress.first().copied(), Some((0, 88)));
        assert_eq!(seen_progress.last().copied(), Some((88, 88)));

        let conversations =
            crate::db::list_conversations(&conn, &db_key).expect("list conversations");
        assert!(
            conversations
                .iter()
                .any(|conversation| conversation.id == "conversation-progress-recovery"),
            "expected recovered conversation to exist, got {conversations:?}"
        );

        let repaired_cursor = kv_get_i64(
            &conn,
            &format!("managed_vault.last_pulled_seq:{scope_id}:{remote_device_id}"),
        )
        .expect("get repaired cursor");
        assert_eq!(repaired_cursor, Some(262));

        let seen_since_values = server_state
            .lock()
            .expect("lock state")
            .seen_since_values
            .clone();
        assert_eq!(seen_since_values, vec![174, 0]);
    }

    #[test]
    fn pull_with_progress_does_not_reset_completed_work_when_remote_cursor_is_repaired() {
        let db_key = [51u8; 32];
        let sync_key = [52u8; 32];
        let first_device_id = "remote-device-fast";
        let stalled_device_id = "remote-device-stalled";

        let dir = tempdir().expect("tempdir");
        let conn = crate::db::open(dir.path()).expect("open");
        conn.execute(
            r#"INSERT INTO kv(key, value) VALUES ('device_id', 'local-device-progress')"#,
            [],
        )
        .expect("set local device id");

        let first_ops = (1..=500)
            .map(|seq| {
                let op_id = format!("op-progress-first-{seq}");
                let op_json = serde_json::json!({
                    "op_id": op_id,
                    "device_id": first_device_id,
                    "seq": seq,
                    "ts_ms": 1_775_811_648_824i64 + seq,
                    "type": "conversation.upsert.v1",
                    "payload": {
                        "conversation_id": format!("conversation-progress-first-{seq}"),
                        "title": format!("First title {seq}"),
                        "created_at_ms": 1_775_811_648_824i64 + seq,
                        "updated_at_ms": 1_775_811_648_824i64 + seq,
                    }
                });
                let plaintext = serde_json::to_vec(&op_json).expect("serialize first op");
                let ciphertext = encrypt_bytes(
                    &sync_key,
                    &plaintext,
                    format!("sync.ops:{first_device_id}:{seq}").as_bytes(),
                )
                .expect("encrypt first op");
                (seq, op_id, B64_STD.encode(ciphertext))
            })
            .collect::<Vec<_>>();

        let stalled_op_id = "op-progress-stalled";
        let stalled_op_json = serde_json::json!({
            "op_id": stalled_op_id,
            "device_id": stalled_device_id,
            "seq": 262,
            "ts_ms": 1_775_811_648_825i64,
            "type": "conversation.upsert.v1",
            "payload": {
                "conversation_id": "conversation-progress-stalled",
                "title": "Stalled title",
                "created_at_ms": 1_775_811_648_825i64,
                "updated_at_ms": 1_775_811_648_825i64,
            }
        });
        let stalled_plaintext = serde_json::to_vec(&stalled_op_json).expect("serialize stalled op");
        let stalled_ciphertext = encrypt_bytes(
            &sync_key,
            &stalled_plaintext,
            format!("sync.ops:{stalled_device_id}:262").as_bytes(),
        )
        .expect("encrypt stalled op");

        let (base_url, server_state) = spawn_progress_partial_then_recovery_server(
            first_device_id.to_string(),
            first_ops,
            stalled_device_id.to_string(),
            B64_STD.encode(stalled_ciphertext),
            stalled_op_id.to_string(),
        );
        let scope_id = crate::sync::managed_vault::runtime::scope_id(&base_url, "test-vault");
        kv_set_i64(
            &conn,
            &format!("managed_vault.last_pulled_seq:{scope_id}:{stalled_device_id}"),
            174,
        )
        .expect("set stalled cursor");

        let mut seen_progress = Vec::new();
        let applied = pull_with_progress(
            &conn,
            &db_key,
            &sync_key,
            &base_url,
            "test-vault",
            "test-token",
            &mut |done, total| seen_progress.push((done, total)),
        )
        .expect("pull with recovery");

        assert!(applied >= 500);
        assert!(
            seen_progress
                .windows(2)
                .all(|window| window[1].0 >= window[0].0),
            "progress should not go backwards: {seen_progress:?}"
        );
        assert_eq!(seen_progress.last().copied(), Some((588, 588)));

        let conversations =
            crate::db::list_conversations(&conn, &db_key).expect("list conversations");
        assert!(
            conversations
                .iter()
                .any(|conversation| conversation.id == "conversation-progress-first-1"),
            "expected first conversation to exist, got {conversations:?}"
        );
        assert!(
            conversations
                .iter()
                .any(|conversation| conversation.id == "conversation-progress-stalled"),
            "expected stalled conversation to exist, got {conversations:?}"
        );

        let snapshot = server_state.lock().expect("lock state");
        assert_eq!(snapshot.seen_secondary_since_values, vec![0, 500, 500]);
        assert_eq!(snapshot.seen_since_values, vec![174, 174, 0]);
    }
}
