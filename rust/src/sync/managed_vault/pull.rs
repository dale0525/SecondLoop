use super::*;

#[cfg(not(target_family = "wasm"))]
pub fn pull(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    base_url: &str,
    vault_id: &str,
    id_token: &str,
) -> Result<u64> {
    const PULL_LIMIT: i64 = 500;

    let http = runtime::client()?;
    let mut local_device_id = super::super::get_or_create_device_id(conn)?;
    let _ =
        runtime::ensure_device_registered(&http, base_url, vault_id, id_token, &local_device_id)?;

    let scope_id = runtime::scope_id(base_url, vault_id);
    let mut since = load_since_map(conn, &scope_id)?;

    let endpoint_json = runtime::url(base_url, &format!("/v1/vaults/{vault_id}/ops:pull"))?;
    let endpoint_bin = runtime::url(base_url, &format!("/v1/vaults/{vault_id}/ops:pull_bin"))?;
    let mut applied: u64 = 0;
    let mut pull_bin_supported: Option<bool> = if should_try_pull_bin_first() {
        None
    } else {
        Some(false)
    };
    let mut stale_cursor_recovery_attempted = false;
    let mut forbidden_device_recovery_attempted = false;
    loop {
        let request = PullRequest {
            device_id: local_device_id.as_str(),
            since: since.clone(),
            limit: PULL_LIMIT,
        };

        if pull_bin_supported != Some(false) {
            let resp = http
                .post(&endpoint_bin)
                .bearer_auth(id_token)
                .json(&request)
                .send()?;

            let status = resp.status();
            let status_code = status.as_u16();
            if status_code == 403 && !forbidden_device_recovery_attempted {
                forbidden_device_recovery_attempted = true;
                if let Ok(Some(next_device_id)) = try_recover_pull_forbidden_by_rotating_device_id(
                    conn,
                    &http,
                    base_url,
                    vault_id,
                    id_token,
                    &local_device_id,
                ) {
                    local_device_id = next_device_id;
                    continue;
                }
            }
            if should_fallback_to_json_pull(status_code) {
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

                if ops.is_empty()
                    && !stale_cursor_recovery_attempted
                    && maybe_recover_stale_since_map(conn, &scope_id, &local_device_id, &mut since)?
                {
                    stale_cursor_recovery_attempted = true;
                    continue;
                }

                let (batch_applied, committed_since) =
                    apply_pull_bin_batch(conn, db_key, sync_key, &scope_id, &since, &ops)?;
                applied += batch_applied;
                since = committed_since;

                if ops.len() < (PULL_LIMIT as usize) {
                    break;
                }
                continue;
            }
        }

        let resp = http
            .post(&endpoint_json)
            .bearer_auth(id_token)
            .json(&request)
            .send()?;

        let status = resp.status();
        if status.as_u16() == 403 && !forbidden_device_recovery_attempted {
            forbidden_device_recovery_attempted = true;
            if let Ok(Some(next_device_id)) = try_recover_pull_forbidden_by_rotating_device_id(
                conn,
                &http,
                base_url,
                vault_id,
                id_token,
                &local_device_id,
            ) {
                local_device_id = next_device_id;
                continue;
            }
        }
        if !status.is_success() {
            let text = resp.text().unwrap_or_default();
            return Err(anyhow!("managed-vault pull failed: HTTP {status} {text}"));
        }

        let body = resp.bytes()?;
        let parsed: PullResponse = serde_json::from_slice(body.as_ref())?;

        let mut next_since = since.clone();
        for (device_id, last_seq) in &parsed.next {
            next_since.insert(device_id.to_string(), *last_seq);
        }

        if next_since == since && !parsed.ops.is_empty() {
            return Err(anyhow!("managed-vault pull made no progress"));
        }

        if parsed.ops.is_empty()
            && !stale_cursor_recovery_attempted
            && maybe_recover_stale_since_map(conn, &scope_id, &local_device_id, &mut since)?
        {
            stale_cursor_recovery_attempted = true;
            continue;
        }

        let (batch_applied, committed_since) =
            apply_pull_json_batch(conn, db_key, sync_key, &scope_id, &since, &parsed)?;
        applied += batch_applied;
        since = committed_since;

        if parsed.ops.len() < (PULL_LIMIT as usize) {
            break;
        }
    }

    let app_dir = super::super::app_dir_from_conn(conn)?;
    let download_ctx = attachments::AttachmentUploadContext {
        conn,
        db_key,
        sync_key,
        http: &http,
        base_url,
        vault_id,
        id_token,
        app_dir: app_dir.as_path(),
    };
    let _ = artifacts::download_missing_embedding_artifact_blobs(&download_ctx)?;

    Ok(applied)
}

#[cfg(target_family = "wasm")]
pub async fn pull(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    base_url: &str,
    vault_id: &str,
    id_token: &str,
) -> Result<u64> {
    const PULL_LIMIT: i64 = 500;

    let http = runtime::async_client()?;
    let mut local_device_id = super::super::get_or_create_device_id(conn)?;
    let _ = runtime::ensure_device_registered_async(
        conn,
        &http,
        base_url,
        vault_id,
        id_token,
        &local_device_id,
    )
    .await?;

    let scope_id = runtime::scope_id(base_url, vault_id);
    let mut since = load_since_map(conn, &scope_id)?;

    let endpoint_json = runtime::url(base_url, &format!("/v1/vaults/{vault_id}/ops:pull"))?;
    let endpoint_bin = runtime::url(base_url, &format!("/v1/vaults/{vault_id}/ops:pull_bin"))?;
    let mut applied: u64 = 0;
    let mut pull_bin_supported: Option<bool> = if should_try_pull_bin_first() {
        None
    } else {
        Some(false)
    };
    let mut stale_cursor_recovery_attempted = false;
    let mut forbidden_device_recovery_attempted = false;
    loop {
        let request = PullRequest {
            device_id: local_device_id.as_str(),
            since: since.clone(),
            limit: PULL_LIMIT,
        };

        if pull_bin_supported != Some(false) {
            let resp = http
                .post(&endpoint_bin)
                .bearer_auth(id_token)
                .json(&request)
                .send()
                .await?;

            let status = resp.status();
            let status_code = status.as_u16();
            if status_code == 403 && !forbidden_device_recovery_attempted {
                forbidden_device_recovery_attempted = true;
                if let Ok(Some(next_device_id)) =
                    try_recover_pull_forbidden_by_rotating_device_id_async(
                        conn,
                        &http,
                        base_url,
                        vault_id,
                        id_token,
                        &local_device_id,
                    )
                    .await
                {
                    local_device_id = next_device_id;
                    continue;
                }
            }
            if should_fallback_to_json_pull(status_code) {
                pull_bin_supported = Some(false);
            } else {
                if !status.is_success() {
                    let text = resp.text().await.unwrap_or_default();
                    return Err(anyhow!(
                        "managed-vault pull_bin failed: HTTP {status} {text}"
                    ));
                }

                pull_bin_supported = Some(true);
                let body = resp.bytes().await?;
                let ops = decode_pull_bin_response(body.as_ref())?;
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

                if ops.is_empty()
                    && !stale_cursor_recovery_attempted
                    && maybe_recover_stale_since_map(conn, &scope_id, &local_device_id, &mut since)?
                {
                    stale_cursor_recovery_attempted = true;
                    continue;
                }

                let (batch_applied, committed_since) =
                    apply_pull_bin_batch(conn, db_key, sync_key, &scope_id, &since, &ops)?;
                applied += batch_applied;
                since = committed_since;

                if ops.len() < (PULL_LIMIT as usize) {
                    break;
                }
                continue;
            }
        }

        let resp = http
            .post(&endpoint_json)
            .bearer_auth(id_token)
            .json(&request)
            .send()
            .await?;

        let status = resp.status();
        if status.as_u16() == 403 && !forbidden_device_recovery_attempted {
            forbidden_device_recovery_attempted = true;
            if let Ok(Some(next_device_id)) =
                try_recover_pull_forbidden_by_rotating_device_id_async(
                    conn,
                    &http,
                    base_url,
                    vault_id,
                    id_token,
                    &local_device_id,
                )
                .await
            {
                local_device_id = next_device_id;
                continue;
            }
        }
        if !status.is_success() {
            let text = resp.text().await.unwrap_or_default();
            return Err(anyhow!("managed-vault pull failed: HTTP {status} {text}"));
        }

        let body = resp.bytes().await?;
        let parsed: PullResponse = serde_json::from_slice(body.as_ref())?;

        let mut next_since = since.clone();
        for (device_id, last_seq) in &parsed.next {
            next_since.insert(device_id.to_string(), *last_seq);
        }

        if next_since == since && !parsed.ops.is_empty() {
            return Err(anyhow!("managed-vault pull made no progress"));
        }

        if parsed.ops.is_empty()
            && !stale_cursor_recovery_attempted
            && maybe_recover_stale_since_map(conn, &scope_id, &local_device_id, &mut since)?
        {
            stale_cursor_recovery_attempted = true;
            continue;
        }

        let (batch_applied, committed_since) =
            apply_pull_json_batch(conn, db_key, sync_key, &scope_id, &since, &parsed)?;
        applied += batch_applied;
        since = committed_since;

        if parsed.ops.len() < (PULL_LIMIT as usize) {
            break;
        }
    }

    let app_dir = super::super::app_dir_from_conn(conn)?;
    let _ = artifacts::download_missing_embedding_artifact_blobs_async(
        conn,
        db_key,
        sync_key,
        &http,
        base_url,
        vault_id,
        id_token,
        app_dir.as_path(),
    )
    .await?;

    Ok(applied)
}
