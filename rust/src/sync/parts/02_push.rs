pub fn clear_remote_root(remote: &impl RemoteStore, remote_root: &str) -> Result<()> {
    let remote_root_dir = normalize_dir(remote_root);
    if remote_root_dir == "/" {
        return Err(anyhow!("refusing to clear remote root '/'"));
    }

    fn clear_dir_contents(remote: &impl RemoteStore, dir: &str) -> Result<()> {
        for entry in remote.list(dir)? {
            if entry.ends_with('/') {
                clear_dir_contents(remote, &entry)?;
                // Best-effort: Some WebDAV servers reject collection deletes (HTTP 405), even when
                // the directory is empty. Clearing contents is sufficient for reset semantics.
                match remote.delete(&entry) {
                    Ok(()) => {}
                    Err(e) if e.is::<NotFound>() => {}
                    Err(_) => {}
                }
                continue;
            }
            remote.delete(&entry)?;
        }
        Ok(())
    }

    let delete_err = match remote.delete(&remote_root_dir) {
        Ok(()) => return Ok(()),
        Err(e) if e.is::<NotFound>() => return Ok(()),
        Err(e) => e,
    };

    // Fallback for servers that don't support recursive DELETE on collections: remove all
    // descendants using list()+delete(file), then best-effort delete the root directory.
    clear_dir_contents(remote, &remote_root_dir).map_err(|e| {
        anyhow!(
            "failed to clear remote root via recursive delete after initial delete error: {delete_err}; recursive error: {e}"
        )
    })?;

    let _ = remote.delete(&remote_root_dir);
    Ok(())
}

pub fn push(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    remote: &impl RemoteStore,
    remote_root: &str,
) -> Result<u64> {
    push_internal(conn, db_key, sync_key, remote, remote_root, true, None)
}

pub fn push_with_progress(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    remote: &impl RemoteStore,
    remote_root: &str,
    progress: &mut dyn FnMut(u64, u64),
) -> Result<u64> {
    push_internal(
        conn,
        db_key,
        sync_key,
        remote,
        remote_root,
        true,
        Some(progress),
    )
}

pub fn push_ops_only(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    remote: &impl RemoteStore,
    remote_root: &str,
) -> Result<u64> {
    push_internal(conn, db_key, sync_key, remote, remote_root, false, None)
}

pub fn push_ops_only_with_progress(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    remote: &impl RemoteStore,
    remote_root: &str,
    progress: &mut dyn FnMut(u64, u64),
) -> Result<u64> {
    push_internal(
        conn,
        db_key,
        sync_key,
        remote,
        remote_root,
        false,
        Some(progress),
    )
}

fn remote_file_exists(remote: &impl RemoteStore, path: &str) -> Result<bool> {
    remote.exists(path)
}

fn local_attachment_sha256s(conn: &Connection) -> Result<Vec<String>> {
    conn.prepare(r#"SELECT sha256 FROM attachments ORDER BY created_at ASC, sha256 ASC"#)?
        .query_map([], |row| row.get(0))?
        .collect::<rusqlite::Result<Vec<String>>>()
        .map_err(Into::into)
}

fn local_embedding_artifact_blob_refs(conn: &Connection) -> Result<Vec<String>> {
    crate::db::list_distinct_embedding_artifact_blob_refs(conn)
}

const MAX_FRESH_DEVICE_REMOTE_BYTE_PROBES: i64 = 10;

fn local_attachment_count(conn: &Connection) -> Result<i64> {
    conn.query_row(r#"SELECT count(*) FROM attachments"#, [], |row| row.get(0))
        .map_err(Into::into)
}

fn local_ready_embedding_artifact_blob_ref_count(conn: &Connection) -> Result<i64> {
    conn.query_row(
        r#"SELECT count(DISTINCT blob_ref)
           FROM embedding_artifact_manifests
           WHERE status = 'ready'"#,
        [],
        |row| row.get(0),
    )
    .map_err(Into::into)
}

fn exceeds_fresh_device_remote_byte_probe_budget(conn: &Connection) -> Result<bool> {
    let attachment_count = local_attachment_count(conn)?.max(0);
    if attachment_count > MAX_FRESH_DEVICE_REMOTE_BYTE_PROBES {
        return Ok(true);
    }
    let artifact_count = local_ready_embedding_artifact_blob_ref_count(conn)?.max(0);
    Ok(attachment_count.saturating_add(artifact_count) > MAX_FRESH_DEVICE_REMOTE_BYTE_PROBES)
}

fn remote_metadata_paths_for_other_devices(
    conn: &Connection,
    remote_root_dir: &str,
    device_id: &str,
) -> Result<Vec<String>> {
    let mut metadata_paths = std::collections::BTreeSet::new();
    let mut stmt = conn.prepare(
        r#"SELECT device_id, seq
           FROM oplog
           WHERE device_id != ?1
           ORDER BY device_id ASC, seq ASC"#,
    )?;
    let mut rows = stmt.query(params![device_id])?;
    while let Some(row) = rows.next()? {
        let remote_device_id: String = row.get(0)?;
        let seq: i64 = row.get(1)?;
        metadata_paths.insert(format!(
            "{remote_root_dir}{remote_device_id}/ops/op_{seq}.json"
        ));
        metadata_paths.insert(format!(
            "{remote_root_dir}{remote_device_id}/packs/pack_{}.bin",
            ops_pack_chunk_start(seq)
        ));
        metadata_paths.insert(format!("{remote_root_dir}{remote_device_id}/cursor.json"));
    }
    Ok(metadata_paths.into_iter().collect())
}

fn can_skip_fresh_device_full_push(
    conn: &Connection,
    remote: &impl RemoteStore,
    remote_root_dir: &str,
    device_id: &str,
) -> Result<bool> {
    let metadata_paths = remote_metadata_paths_for_other_devices(conn, remote_root_dir, device_id)?;
    if metadata_paths.is_empty() {
        return Ok(false);
    }
    if exceeds_fresh_device_remote_byte_probe_budget(conn)? {
        return Ok(false);
    }

    for metadata_path in metadata_paths {
        if !remote_file_exists(remote, &metadata_path)? {
            return Ok(false);
        }
    }

    for sha256 in local_attachment_sha256s(conn)? {
        let attachment_path = format!("{remote_root_dir}attachments/{sha256}.bin");
        if !remote_file_exists(remote, &attachment_path)? {
            return Ok(false);
        }
    }

    for blob_ref in local_embedding_artifact_blob_refs(conn)? {
        let artifact_path = format!(
            "{remote_root_dir}{}",
            crate::db::embedding_artifact_blob_rel_path(&blob_ref)
        );
        if !remote_file_exists(remote, &artifact_path)? {
            return Ok(false);
        }
    }

    Ok(true)
}

fn push_internal(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    remote: &impl RemoteStore,
    remote_root: &str,
    upload_attachment_bytes: bool,
    mut progress: Option<&mut dyn FnMut(u64, u64)>,
) -> Result<u64> {
    let device_id = get_or_create_device_id(conn)?;
    let app_dir = crate::db::app_dir_from_conn(conn)?;
    let app_dir_path = app_dir.as_path();
    let remote_root_dir = normalize_dir(remote_root);
    let scope_id = sync_scope_id(remote, &remote_root_dir);

    let last_pushed_key = format!("sync.last_pushed_seq:{scope_id}");
    let last_pushed_seq = kv_get_i64(conn, &last_pushed_key)?.unwrap_or(0);
    let local_pending_ops = conn
        .query_row(
            r#"SELECT count(*) FROM oplog WHERE device_id = ?1 AND seq > ?2"#,
            params![device_id, last_pushed_seq],
            |row| row.get::<_, i64>(0),
        )?
        .max(0) as u64;

    let has_remote_device_ops: bool = conn.query_row(
        r#"SELECT EXISTS(SELECT 1 FROM oplog WHERE device_id != ?1 LIMIT 1)"#,
        params![device_id.as_str()],
        |row| row.get(0),
    )?;

    let can_skip_fresh_device_push = if upload_attachment_bytes
        && local_pending_ops == 0
        && last_pushed_seq == 0
        && has_remote_device_ops
    {
        can_skip_fresh_device_full_push(conn, remote, &remote_root_dir, &device_id).unwrap_or(false)
    } else {
        false
    };

    if can_skip_fresh_device_push {
        // After a fresh pull, this device can have lots of synced metadata but still no local
        // oplog rows of its own. Returning early here avoids a redundant byte backfill/upload
        // phase on the new device, but only after probing that the remote already has the synced
        // metadata and representative attachment/artifact bytes.
        if let Some(cb) = progress.as_deref_mut() {
            cb(0, 0);
        }
        return Ok(0);
    }

    crate::db::backfill_attachments_oplog_if_needed(conn, db_key)?;
    crate::db::backfill_knowledge_memory_feedback_oplog_if_needed(conn, db_key)?;

    let local_pending_ops = conn
        .query_row(
            r#"SELECT count(*) FROM oplog WHERE device_id = ?1 AND seq > ?2"#,
            params![device_id, last_pushed_seq],
            |row| row.get::<_, i64>(0),
        )?
        .max(0) as u64;

    if !upload_attachment_bytes
        && local_pending_ops == 0
        && last_pushed_seq == 0
    {
        if let Some(cb) = progress.as_deref_mut() {
            cb(0, 0);
        }
        return Ok(0);
    }

    let ops_dir = format!("{remote_root_dir}{device_id}/ops/");
    remote.mkdir_all(&ops_dir)?;
    let packs_dir = format!("{remote_root_dir}{device_id}/packs/");
    remote.mkdir_all(&packs_dir)?;

    let mut total_ops = if progress.is_some() {
        local_pending_ops
    } else {
        0
    };
    let mut done_ops = 0u64;
    let mut force_repush_from_zero = false;
    if progress.is_some() && total_ops == 0 && last_pushed_seq > 0 {
        // When there are no new local ops, we may still need to re-push from 0 if the remote
        // target was cleared/reset. If so, compute progress against the full local oplog.
        let last_path = format!("{ops_dir}op_{last_pushed_seq}.json");
        match remote.get(&last_path) {
            Ok(_) => {}
            Err(e) if e.is::<NotFound>() => {
                force_repush_from_zero = true;
                total_ops = conn
                    .query_row(
                        r#"SELECT count(*) FROM oplog WHERE device_id = ?1 AND seq > 0"#,
                        params![device_id],
                        |row| row.get::<_, i64>(0),
                    )?
                    .max(0) as u64;
            }
            Err(e) => return Err(e),
        }
    }
    if let Some(cb) = progress.as_deref_mut() {
        cb(0, total_ops);
    }

    let attachments_dir = format!("{remote_root_dir}attachments/");
    remote.mkdir_all(&attachments_dir)?;
    let embedding_artifacts_dir = format!("{remote_root_dir}embedding_artifacts/");
    remote.mkdir_all(&embedding_artifacts_dir)?;

    if upload_attachment_bytes {
        let attachment_backfill_key = format!("sync.attachments.bytes_backfilled:{scope_id}");
        if kv_get_i64(conn, &attachment_backfill_key)?.unwrap_or(0) == 0 {
            upload_all_local_attachment_bytes(
                conn,
                db_key,
                sync_key,
                remote,
                &attachments_dir,
                app_dir_path,
            )?;
            kv_set_i64(conn, &attachment_backfill_key, 1)?;
        }

        let artifact_backfill_key = format!("sync.embedding_artifacts.bytes_backfilled:{scope_id}");
        if kv_get_i64(conn, &artifact_backfill_key)?.unwrap_or(0) == 0 {
            upload_all_local_embedding_artifact_blobs(
                conn,
                db_key,
                sync_key,
                remote,
                &remote_root_dir,
                app_dir_path,
            )?;
            kv_set_i64(conn, &artifact_backfill_key, 1)?;
        }
    }

    ensure_ops_packs_backfilled(
        conn, db_key, sync_key, remote, &packs_dir, &device_id, &scope_id,
    )?;

    struct PushOpsContext<'a, R: RemoteStore> {
        conn: &'a Connection,
        db_key: &'a [u8; 32],
        sync_key: &'a [u8; 32],
        remote: &'a R,
        device_id: &'a str,
        ops_dir: &'a str,
        packs_dir: &'a str,
        attachments_dir: &'a str,
        app_dir: &'a Path,
        upload_attachment_bytes: bool,
    }

    let ctx = PushOpsContext {
        conn,
        db_key,
        sync_key,
        remote,
        device_id: &device_id,
        ops_dir: &ops_dir,
        packs_dir: &packs_dir,
        attachments_dir: &attachments_dir,
        app_dir: app_dir_path,
        upload_attachment_bytes,
    };

    let mut push_ops_after = |after_seq: i64| -> Result<(u64, i64)> {
        let mut stmt = ctx.conn.prepare(
            r#"SELECT op_id, seq, op_json
               FROM oplog
               WHERE device_id = ?1 AND seq > ?2
               ORDER BY seq ASC"#,
        )?;

        const OP_UPLOAD_BATCH_SIZE: usize = 64;
        const OP_UPLOAD_MAX_CONCURRENCY: usize = 8;
        const OP_UPLOAD_PENALTY_WINDOW_MS: i64 = 10 * 60 * 1000;

        let mut rows = stmt.query(params![ctx.device_id, after_seq])?;
        enum AttachmentAction {
            Upload,
            Delete,
        }

        let mut artifact_blob_refs: BTreeSet<String> = BTreeSet::new();
        let mut pushed: u64 = 0;
        let mut max_seq = after_seq;
        let mut attachment_actions: BTreeMap<String, AttachmentAction> = BTreeMap::new();
        let mut touched_pack_chunks: BTreeSet<i64> = BTreeSet::new();
        let mut pending_op_uploads: Vec<(String, Vec<u8>)> =
            Vec::with_capacity(OP_UPLOAD_BATCH_SIZE);
        let op_upload_penalty_cap_key =
            format!("sync.push.op_upload_concurrency_cap:{scope_id}");
        let op_upload_penalty_until_key =
            format!("sync.push.op_upload_concurrency_cap_until_ms:{scope_id}");
        let penalty_cap = kv_get_i64(ctx.conn, &op_upload_penalty_cap_key)?;
        let penalty_until_ms = kv_get_i64(ctx.conn, &op_upload_penalty_until_key)?;
        let now_ms = current_unix_ms();
        let mut op_upload_concurrency = OP_UPLOAD_MAX_CONCURRENCY;
        if let (Some(cap), Some(until_ms)) = (penalty_cap, penalty_until_ms) {
            if cap > 0 && until_ms > now_ms {
                op_upload_concurrency = op_upload_concurrency.min(cap as usize);
            }
        }

        let mut flush_pending_op_uploads = |pending: &mut Vec<(String, Vec<u8>)>| -> Result<()> {
            let (uploaded, lowered_concurrency) =
                upload_ops_files_batch(ctx.remote, pending, &mut op_upload_concurrency)?;
            if let Some(cap) = lowered_concurrency {
                kv_set_i64(ctx.conn, &op_upload_penalty_cap_key, cap as i64)?;
                kv_set_i64(
                    ctx.conn,
                    &op_upload_penalty_until_key,
                    current_unix_ms() + OP_UPLOAD_PENALTY_WINDOW_MS,
                )?;
            }
            if uploaded > 0 && progress.is_some() {
                done_ops = (done_ops + uploaded as u64).min(total_ops);
                if let Some(cb) = progress.as_deref_mut() {
                    cb(done_ops, total_ops);
                }
            }
            Ok(())
        };

        while let Some(row) = rows.next()? {
            let op_id: String = row.get(0)?;
            let seq: i64 = row.get(1)?;
            let op_json_blob: Vec<u8> = row.get(2)?;

            let plaintext = decrypt_bytes(
                ctx.db_key,
                &op_json_blob,
                format!("oplog.op_json:{op_id}").as_bytes(),
            )?;

            if let Ok(op_json) = serde_json::from_slice::<serde_json::Value>(&plaintext) {
                if ctx.upload_attachment_bytes
                    && op_json["type"].as_str() == Some("attachment.upsert.v1")
                {
                    if let Some(sha256) = op_json["payload"]["sha256"].as_str() {
                        attachment_actions.insert(sha256.to_string(), AttachmentAction::Upload);
                    }
                }

                if op_json["type"].as_str() == Some("attachment.delete.v1") {
                    if let Some(sha256) = op_json["payload"]["sha256"].as_str() {
                        attachment_actions.insert(sha256.to_string(), AttachmentAction::Delete);
                    }
                }

                if op_json["type"].as_str() == Some("embedding.artifact.upsert.v1") {
                    if let Some(blob_ref) = op_json["payload"]["blob_ref"].as_str() {
                        let blob_ref = blob_ref.trim();
                        if !blob_ref.is_empty() {
                            artifact_blob_refs.insert(blob_ref.to_string());
                        }
                    }
                }
            }

            let file_blob = encrypt_bytes(
                ctx.sync_key,
                &plaintext,
                format!("sync.ops:{}:{seq}", ctx.device_id).as_bytes(),
            )?;

            let file_path = format!("{}op_{seq}.json", ctx.ops_dir);
            pending_op_uploads.push((file_path, file_blob));
            touched_pack_chunks.insert(ops_pack_chunk_start(seq));

            pushed += 1;
            if seq > max_seq {
                max_seq = seq;
            }

            if pending_op_uploads.len() >= OP_UPLOAD_BATCH_SIZE {
                flush_pending_op_uploads(&mut pending_op_uploads)?;
            }
        }

        flush_pending_op_uploads(&mut pending_op_uploads)?;

        for (sha256, action) in attachment_actions {
            match action {
                AttachmentAction::Upload => {
                    let _ = upload_attachment_bytes_if_present(
                        ctx.conn,
                        ctx.db_key,
                        ctx.sync_key,
                        ctx.remote,
                        ctx.attachments_dir,
                        ctx.app_dir,
                        &sha256,
                    )?;
                }
                AttachmentAction::Delete => {
                    let remote_path = format!("{}{}.bin", ctx.attachments_dir, sha256);
                    match ctx.remote.delete(&remote_path) {
                        Ok(()) => {}
                        Err(e) if e.is::<NotFound>() => {}
                        Err(e) => return Err(e),
                    }
                }
            }
        }

        for blob_ref in artifact_blob_refs {
            let _ = upload_embedding_artifact_blob_if_present(
                ctx.db_key,
                ctx.sync_key,
                ctx.remote,
                &remote_root_dir,
                ctx.app_dir,
                &blob_ref,
            )?;
        }

        for chunk_start in touched_pack_chunks {
            upload_ops_pack_chunk(
                ctx.conn,
                ctx.db_key,
                ctx.sync_key,
                ctx.remote,
                ctx.packs_dir,
                ctx.device_id,
                chunk_start,
            )?;
        }

        Ok((pushed, max_seq))
    };

    fn write_cursor_json(
        remote: &impl RemoteStore,
        remote_root_dir: &str,
        device_id: &str,
        max_seq: i64,
    ) -> Result<()> {
        let path = format!("{remote_root_dir}{device_id}/cursor.json");
        let payload = serde_json::json!({ "max_seq": max_seq });
        remote.put(&path, payload.to_string().into_bytes())?;
        Ok(())
    }

    let mut pushed_out = 0u64;
    let mut final_max_seq = last_pushed_seq;

    let (pushed, max_seq) = push_ops_after(if force_repush_from_zero {
        0
    } else {
        last_pushed_seq
    })?;
    if pushed > 0 {
        kv_set_i64(conn, &last_pushed_key, max_seq)?;
        pushed_out = pushed;
        final_max_seq = max_seq;
    } else if last_pushed_seq > 0 {
        // If the remote target was cleared/reset (e.g. user switches directories then comes back),
        // our cursor may say "up to date" while the remote no longer has the last pushed file.
        let last_path = format!("{ops_dir}op_{last_pushed_seq}.json");
        match remote.get(&last_path) {
            Ok(_) => {}
            Err(e) if e.is::<NotFound>() => {
                let (re_pushed, re_max_seq) = push_ops_after(0)?;
                if re_pushed > 0 {
                    kv_set_i64(conn, &last_pushed_key, re_max_seq)?;
                    pushed_out = re_pushed;
                    final_max_seq = re_max_seq;
                }
            }
            Err(e) => return Err(e),
        }
    }

    // Best-effort: this is only metadata for progress reporting.
    let _ = write_cursor_json(remote, &remote_root_dir, &device_id, final_max_seq);

    if pushed_out > 0 {
        maybe_run_oplog_retention_after_push(conn, &scope_id, remote)?;
    }

    Ok(pushed_out)
}

fn backend_from_target_id(target_id: &str) -> Option<crate::db::OplogRetentionBackend> {
    if target_id.starts_with("webdav:") {
        return Some(crate::db::OplogRetentionBackend::WebDav);
    }
    if target_id.starts_with("localdir:") {
        return Some(crate::db::OplogRetentionBackend::LocalDir);
    }
    None
}

fn maybe_run_oplog_retention_after_push(
    conn: &Connection,
    scope_id: &str,
    remote: &impl RemoteStore,
) -> Result<()> {
    let Some(backend) = backend_from_target_id(remote.target_id()) else {
        return Ok(());
    };

    let _ = crate::db::run_oplog_retention_maintenance(conn, backend, scope_id)?;
    Ok(())
}

fn current_unix_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64
}

fn upload_ops_files_batch(
    remote: &impl RemoteStore,
    pending: &mut Vec<(String, Vec<u8>)>,
    concurrency: &mut usize,
) -> Result<(usize, Option<usize>)> {
    let upload_count = pending.len();
    if upload_count == 0 {
        return Ok((0, None));
    }

    let uploads = std::mem::take(pending);
    let mut attempt_concurrency = (*concurrency).max(1).min(upload_count);
    let initial_concurrency = attempt_concurrency;

    loop {
        match upload_ops_files_batch_once(remote, &uploads, attempt_concurrency) {
            Ok(()) => {
                *concurrency = attempt_concurrency;
                let lowered_concurrency =
                    (attempt_concurrency < initial_concurrency).then_some(attempt_concurrency);
                return Ok((upload_count, lowered_concurrency));
            }
            Err(_) if attempt_concurrency > 1 => {
                attempt_concurrency = (attempt_concurrency / 2).max(1);
            }
            Err(e) => return Err(e),
        }
    }
}

fn upload_ops_files_batch_once(
    remote: &impl RemoteStore,
    uploads: &[(String, Vec<u8>)],
    concurrency: usize,
) -> Result<()> {
    let concurrency = concurrency.max(1).min(uploads.len());
    let mut buckets: Vec<Vec<usize>> = (0..concurrency).map(|_| Vec::new()).collect();
    for (idx, _) in uploads.iter().enumerate() {
        buckets[idx % concurrency].push(idx);
    }

    thread::scope(|scope| -> Result<()> {
        let mut handles = Vec::with_capacity(concurrency);
        for bucket in buckets {
            handles.push(scope.spawn(move || -> Result<()> {
                for idx in bucket {
                    let (path, bytes) = &uploads[idx];
                    remote.put(path, bytes.clone())?;
                }
                Ok(())
            }));
        }

        for handle in handles {
            handle
                .join()
                .map_err(|_| anyhow!("push op upload thread panicked"))??;
        }

        Ok(())
    })
}

fn ensure_ops_packs_backfilled(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    remote: &impl RemoteStore,
    packs_dir: &str,
    device_id: &str,
    scope_id: &str,
) -> Result<()> {
    let (min_seq, max_seq): (Option<i64>, Option<i64>) = conn.query_row(
        r#"SELECT min(seq), max(seq) FROM oplog WHERE device_id = ?1"#,
        params![device_id],
        |row| Ok((row.get(0)?, row.get(1)?)),
    )?;
    let (Some(min_seq), Some(max_seq)) = (min_seq, max_seq) else {
        return Ok(());
    };

    let packs_backfill_key = format!("sync.ops_packs_backfilled:{scope_id}");
    let packs_backfilled = kv_get_i64(conn, &packs_backfill_key)?.unwrap_or(0) != 0;

    let first_chunk_start = ops_pack_chunk_start(min_seq);
    let first_pack_path = format!("{packs_dir}pack_{first_chunk_start}.bin");

    let needs_backfill = if !packs_backfilled {
        true
    } else {
        match remote.get(&first_pack_path) {
            Ok(_) => false,
            Err(e) if e.is::<NotFound>() => true,
            Err(e) => return Err(e),

        }
    };

    if !needs_backfill {
        return Ok(());
    }

    let start_chunk = ops_pack_chunk_start(min_seq);
    let end_chunk = ops_pack_chunk_start(max_seq);
    for chunk_start in (start_chunk..=end_chunk).step_by(OPS_PACK_CHUNK_SIZE as usize) {
        upload_ops_pack_chunk(
            conn,
            db_key,
            sync_key,
            remote,
            packs_dir,
            device_id,
            chunk_start,
        )?;
    }

    kv_set_i64(conn, &packs_backfill_key, 1)?;
    Ok(())
}

fn upload_ops_pack_chunk(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    remote: &impl RemoteStore,
    packs_dir: &str,
    device_id: &str,
    chunk_start: i64,
) -> Result<()> {
    let chunk_end = chunk_start + OPS_PACK_CHUNK_SIZE - 1;

    let mut stmt = conn.prepare(
        r#"SELECT op_id, seq, op_json
           FROM oplog
           WHERE device_id = ?1
             AND seq >= ?2
             AND seq <= ?3
           ORDER BY seq ASC"#,
    )?;

    let mut rows = stmt.query(params![device_id, chunk_start, chunk_end])?;
    let mut entries: Vec<(i64, Vec<u8>)> = Vec::new();

    while let Some(row) = rows.next()? {
        let op_id: String = row.get(0)?;
        let seq: i64 = row.get(1)?;
        let op_json_blob: Vec<u8> = row.get(2)?;

        let plaintext = decrypt_bytes(
            db_key,
            &op_json_blob,
            format!("oplog.op_json:{op_id}").as_bytes(),
        )?;

        let file_blob = encrypt_bytes(
            sync_key,
            &plaintext,
            format!("sync.ops:{device_id}:{seq}").as_bytes(),
        )?;

        entries.push((seq, file_blob));
    }

    if entries.is_empty() {
        return Ok(());
    }

    let pack_bytes = encode_ops_pack(&entries)?;
    let pack_path = format!("{packs_dir}pack_{chunk_start}.bin");
    remote.put(&pack_path, pack_bytes)?;
    Ok(())
}

#[cfg(test)]
include!("02_push_tests.rs");
