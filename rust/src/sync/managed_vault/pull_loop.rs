use anyhow::{anyhow, Result};
use base64::engine::general_purpose::STANDARD as B64_STD;
use base64::Engine as _;
use rusqlite::Connection;
use std::collections::BTreeMap;

use super::pull_recovery::{
    attempt_remote_ahead_repair, decode_pull_bin_response, maybe_recover_stale_since_map,
    probe_failure_indicates_json_unavailable, probe_pull_response_with_max,
    probe_requires_json_retry, repeated_remote_ahead_repair_error, PullResponseWithMax,
    RemoteAheadRepairOutcome, RemoteAheadRepairTracker,
};

fn reset_after_v2_reseed(
    conn: &Connection,
    scope_id: &str,
    since: &mut BTreeMap<String, i64>,
    history_lower_bound: Option<&BTreeMap<String, i64>>,
    stale_cursor_recovery_attempted: &mut bool,
    remote_ahead_repair_tracker: &mut RemoteAheadRepairTracker,
) -> Result<()> {
    let _ = super::state_machine::transition(
        conn,
        scope_id,
        super::state_machine::ManagedVaultSyncState::ReseedRequired,
    );
    *since =
        super::reseed::apply_history_lower_bound_reset(conn, scope_id, history_lower_bound, None)?;
    let _ = super::state_machine::transition(
        conn,
        scope_id,
        super::state_machine::ManagedVaultSyncState::Rebootstrapping,
    );
    *stale_cursor_recovery_attempted = false;
    *remote_ahead_repair_tracker = RemoteAheadRepairTracker::default();
    Ok(())
}

pub fn pull(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    base_url: &str,
    vault_id: &str,
    id_token: &str,
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

    let endpoint_json = super::runtime::url(base_url, &format!("/v1/vaults/{vault_id}/ops:pull"))?;
    let endpoint_bin =
        super::runtime::url(base_url, &format!("/v1/vaults/{vault_id}/ops:pull_bin"))?;
    let endpoint_json_v2 =
        super::runtime::url(base_url, &format!("/v1/vaults/{vault_id}/ops:pull_v2"))?;
    let endpoint_bin_v2 =
        super::runtime::url(base_url, &format!("/v1/vaults/{vault_id}/ops:pull_bin_v2"))?;
    let mut applied: u64 = 0;
    let mut pull_bin_supported: Option<bool> = None;
    let mut stale_cursor_recovery_attempted = false;
    let mut remote_ahead_repair_tracker = RemoteAheadRepairTracker::default();
    let mut forbidden_device_recovery_attempted = false;
    loop {
        let checkpoint_state = super::checkpoint::load_checkpoint_state(conn, &scope_id)?;
        let try_pull_bin_v2 = checkpoint_state.supports_pull_bin_v2 != Some(false);
        let try_pull_v2 = checkpoint_state.supports_pull_v2 != Some(false);
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

        if try_pull_bin_v2 {
            match super::v2_client::fetch_pull_bin_v2(
                &http,
                &endpoint_bin_v2,
                id_token,
                &request_v2,
            )? {
                super::v2_client::PullV2RouteResult::Parsed(parsed) => {
                    super::checkpoint::mark_pull_bin_v2_supported(
                        conn,
                        &scope_id,
                        "ops:pull_bin_v2",
                    )?;
                    if parsed.meta.reseed_required {
                        reset_after_v2_reseed(
                            conn,
                            &scope_id,
                            &mut since,
                            parsed.meta.history_lower_bound.as_ref(),
                            &mut stale_cursor_recovery_attempted,
                            &mut remote_ahead_repair_tracker,
                        )?;
                        continue;
                    }

                    let ops: Vec<super::apply_batch::PullCipherOp> = parsed
                        .ops
                        .into_iter()
                        .map(|op| super::apply_batch::PullCipherOp {
                            device_id: op.device_id,
                            seq: op.seq,
                            op_id: op.op_id,
                            ciphertext: op.ciphertext,
                        })
                        .collect();
                    let mut next_since = super::apply_batch::next_since_from_ops(&since, &ops);
                    if next_since == since && (!ops.is_empty() || parsed.meta.has_more) {
                        return Err(anyhow!("managed-vault pull_v2 made no progress"));
                    }

                    let batch_applied = super::apply_batch::apply_pull_cipher_ops(
                        conn,
                        db_key,
                        sync_key,
                        &scope_id,
                        &since,
                        &mut next_since,
                        &ops,
                    )?;
                    super::checkpoint::store_checkpoint_success(
                        conn,
                        &scope_id,
                        &parsed.meta.generation_id,
                        parsed.meta.checkpoint_token.as_deref(),
                        parsed.meta.protocol_version,
                        "ops:pull_bin_v2",
                    )?;
                    applied += batch_applied;
                    since = next_since;

                    if parsed.meta.has_more {
                        continue;
                    }
                    break;
                }
                super::v2_client::PullV2RouteResult::Unsupported => {
                    super::checkpoint::mark_pull_bin_v2_unsupported(conn, &scope_id)?;
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

        if try_pull_v2 {
            match super::v2_client::fetch_pull_v2_json(
                &http,
                &endpoint_json_v2,
                id_token,
                &request_v2,
            )? {
                super::v2_client::PullV2RouteResult::Parsed(parsed) => {
                    super::checkpoint::mark_pull_v2_supported(conn, &scope_id, "ops:pull_v2")?;
                    if parsed.meta.reseed_required {
                        reset_after_v2_reseed(
                            conn,
                            &scope_id,
                            &mut since,
                            parsed.meta.history_lower_bound.as_ref(),
                            &mut stale_cursor_recovery_attempted,
                            &mut remote_ahead_repair_tracker,
                        )?;
                        continue;
                    }

                    let ops: Vec<super::apply_batch::PullCipherOp> = parsed
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
                    let mut next_since = super::apply_batch::next_since_from_ops(&since, &ops);
                    if next_since == since && (!ops.is_empty() || parsed.meta.has_more) {
                        return Err(anyhow!("managed-vault pull_v2 made no progress"));
                    }

                    let batch_applied = super::apply_batch::apply_pull_cipher_ops(
                        conn,
                        db_key,
                        sync_key,
                        &scope_id,
                        &since,
                        &mut next_since,
                        &ops,
                    )?;
                    super::checkpoint::store_checkpoint_success(
                        conn,
                        &scope_id,
                        &parsed.meta.generation_id,
                        parsed.meta.checkpoint_token.as_deref(),
                        parsed.meta.protocol_version,
                        "ops:pull_v2",
                    )?;
                    applied += batch_applied;
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
        let mut parsed_json_override: Option<PullResponseWithMax> = None;
        if pull_bin_supported != Some(false) {
            let resp = http
                .post(&endpoint_bin)
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
            if super::should_fallback_to_json_pull(status.as_u16()) {
                pull_bin_supported = Some(false);
            } else {
                if !status.is_success() {
                    let text = resp.text().unwrap_or_default();
                    return Err(anyhow!(
                        "managed-vault pull_bin failed: HTTP {status} {text}"
                    ));
                }

                pull_bin_supported = Some(true);
                let body = resp.bytes()?;
                let ops = decode_pull_bin_response(body.as_ref())?;
                let ops_len = ops.len();

                let mut next_since = since.clone();
                for op in &ops {
                    next_since
                        .entry(op.device_id.clone())
                        .and_modify(|v| *v = (*v).max(op.seq))
                        .or_insert(op.seq);
                }

                if next_since == since && !ops.is_empty() {
                    return Err(anyhow!("managed-vault pull made no progress"));
                }

                if ops.is_empty() {
                    match probe_pull_response_with_max(&http, &endpoint_json, id_token, &request) {
                        Ok(probe) => {
                            if probe_requires_json_retry(&since, &probe) {
                                pull_bin_supported = Some(false);
                                parsed_json_override = Some(probe);
                            } else {
                                match attempt_remote_ahead_repair(
                                    &mut remote_ahead_repair_tracker,
                                    conn,
                                    &scope_id,
                                    &local_device_id,
                                    &mut since,
                                    &probe.max,
                                )? {
                                    RemoteAheadRepairOutcome::Recovered => continue,
                                    RemoteAheadRepairOutcome::Exhausted(devices) => {
                                        return Err(repeated_remote_ahead_repair_error(&devices));
                                    }
                                    RemoteAheadRepairOutcome::NotNeeded => {}
                                }
                            }
                        }
                        Err(_) => {
                            if !stale_cursor_recovery_attempted
                                && maybe_recover_stale_since_map(
                                    conn,
                                    &scope_id,
                                    &local_device_id,
                                    &mut since,
                                )?
                            {
                                stale_cursor_recovery_attempted = true;
                                continue;
                            }
                            pull_bin_supported = Some(false);
                            continue;
                        }
                    }

                    if parsed_json_override.is_none()
                        && !stale_cursor_recovery_attempted
                        && maybe_recover_stale_since_map(
                            conn,
                            &scope_id,
                            &local_device_id,
                            &mut since,
                        )?
                    {
                        stale_cursor_recovery_attempted = true;
                        continue;
                    }
                }

                if parsed_json_override.is_none() {
                    let decoded_ops: Vec<super::apply_batch::PullCipherOp> = ops
                        .into_iter()
                        .map(|op| super::apply_batch::PullCipherOp {
                            device_id: op.device_id,
                            seq: op.seq,
                            op_id: op.op_id,
                            ciphertext: op.ciphertext,
                        })
                        .collect();
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
                    since = next_since;

                    if ops_len < (PULL_LIMIT as usize) {
                        let probe_request = super::PullRequest {
                            device_id: local_device_id.as_str(),
                            since: since.clone(),
                            limit: PULL_LIMIT,
                        };
                        match probe_pull_response_with_max(
                            &http,
                            &endpoint_json,
                            id_token,
                            &probe_request,
                        ) {
                            Ok(probe) => {
                                if probe_requires_json_retry(&since, &probe) {
                                    pull_bin_supported = Some(false);
                                    parsed_json_override = Some(probe);
                                } else {
                                    match attempt_remote_ahead_repair(
                                        &mut remote_ahead_repair_tracker,
                                        conn,
                                        &scope_id,
                                        &local_device_id,
                                        &mut since,
                                        &probe.max,
                                    )? {
                                        RemoteAheadRepairOutcome::Recovered => continue,
                                        RemoteAheadRepairOutcome::Exhausted(devices) => {
                                            return Err(repeated_remote_ahead_repair_error(
                                                &devices,
                                            ));
                                        }
                                        RemoteAheadRepairOutcome::NotNeeded => {}
                                    }
                                }
                            }
                            Err(error) => {
                                if !stale_cursor_recovery_attempted
                                    && maybe_recover_stale_since_map(
                                        conn,
                                        &scope_id,
                                        &local_device_id,
                                        &mut since,
                                    )?
                                {
                                    stale_cursor_recovery_attempted = true;
                                    continue;
                                }
                                if probe_failure_indicates_json_unavailable(&error) {
                                    break;
                                }
                                pull_bin_supported = Some(false);
                                continue;
                            }
                        }
                        if parsed_json_override.is_none() {
                            break;
                        }
                    }

                    if parsed_json_override.is_none() {
                        continue;
                    }
                }
            }
        }

        let parsed: PullResponseWithMax = if let Some(parsed) = parsed_json_override.take() {
            parsed
        } else {
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
            serde_json::from_slice(body.as_ref())?
        };
        if !parsed.needs_reseed.is_empty() {
            since = super::reseed::apply_history_lower_bound_reset(
                conn,
                &scope_id,
                Some(&parsed.history_lower_bound),
                Some(&parsed.needs_reseed),
            )?;
            stale_cursor_recovery_attempted = false;
            remote_ahead_repair_tracker = RemoteAheadRepairTracker::default();
            continue;
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
    let _ = super::artifacts::download_missing_embedding_artifact_blobs(&download_ctx)?;
    let _ = super::blob_repair::process_pending_blob_repairs(&download_ctx, 8)?;
    let _ = super::state_machine::transition(
        conn,
        &scope_id,
        super::state_machine::ManagedVaultSyncState::Completed,
    );

    Ok(applied)
}
