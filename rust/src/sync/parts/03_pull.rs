pub fn pull(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    remote: &impl RemoteStore,
    remote_root: &str,
) -> Result<u64> {
    pull_internal(conn, db_key, sync_key, remote, remote_root, None)
}

pub fn pull_with_progress(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    remote: &impl RemoteStore,
    remote_root: &str,
    progress: &mut dyn FnMut(u64, u64),
) -> Result<u64> {
    pull_internal(conn, db_key, sync_key, remote, remote_root, Some(progress))
}

fn pull_internal(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    remote: &impl RemoteStore,
    remote_root: &str,
    mut progress: Option<&mut dyn FnMut(u64, u64)>,
) -> Result<u64> {
    const OPS_PREFETCH_BATCH_SIZE: usize = 128;
    const OPS_PREFETCH_CONCURRENCY: usize = 8;

    let local_device_id = get_or_create_device_id(conn)?;
    let remote_root_dir = normalize_dir(remote_root);
    let scope_id = sync_scope_id(remote, &remote_root_dir);
    reconcile_remote_generation_before_pull(conn, remote, &remote_root_dir, &scope_id)?;
    let remote_device_ids = list_remote_sync_device_ids(remote, &remote_root_dir)?;

    let total_ops = if progress.is_some() {
        let mut total = 0u64;
        for device_id in remote_device_ids.iter() {
            if *device_id == local_device_id {
                continue;
            }

            let packs_dir = format!("{remote_root_dir}{device_id}/packs/");

            let last_pulled_key = format!("sync.last_pulled_seq:{scope_id}:{device_id}");
            let last_pulled_seq = kv_get_i64(conn, &last_pulled_key)?.unwrap_or(0);

            let max_seq = read_remote_device_max_seq(remote, &remote_root_dir, device_id)?
                .or_else(|| infer_remote_max_seq_from_packs(remote, &packs_dir).ok().flatten())
                .unwrap_or(last_pulled_seq);

            if max_seq > last_pulled_seq {
                total += (max_seq - last_pulled_seq) as u64;
            }
        }
        total
    } else {
        0u64
    };

    let mut done_ops = 0u64;
    if let Some(cb) = progress.as_deref_mut() {
        cb(0, total_ops);
    }

    let mut applied: u64 = 0;

    for device_id in remote_device_ids {
        if device_id == local_device_id {
            continue;
        }

        let ops_dir = format!("{remote_root_dir}{device_id}/ops/");
        let packs_dir = format!("{remote_root_dir}{device_id}/packs/");

        let last_pulled_key = format!("sync.last_pulled_seq:{scope_id}:{device_id}");
        let last_pulled_seq = kv_get_i64(conn, &last_pulled_key)?.unwrap_or(0);

        let mut device_last_reported = last_pulled_seq;

        let mut new_last_pulled = last_pulled_seq;
        let mut seq = last_pulled_seq + 1;

        let mut tried_discover_pack_start = false;
        loop {
            let chunk_start = ops_pack_chunk_start(seq);
            let pack_path = format!("{packs_dir}pack_{chunk_start}.bin");
            let pack_bytes = match remote.get(&pack_path) {
                Ok(bytes) => bytes,
                Err(e) if e.is::<NotFound>() => {
                    if !tried_discover_pack_start && last_pulled_seq == 0 && seq == 1 {
                        tried_discover_pack_start = true;
                        if let Some(start_seq) =
                            discover_first_available_pack_chunk_start(remote, &packs_dir)?
                        {
                            seq = start_seq;
                            continue;
                        }
                    }
                    break;
                }
                Err(e) => return Err(e),
            };

            let entries = match decode_ops_pack(&pack_bytes) {
                Ok(entries) => entries,
                Err(_) => break,
            };
            if entries.is_empty() {
                break;
            }

            let mut pack_applied = 0u64;
            let mut max_seq_in_pack = new_last_pulled;
            with_immediate_transaction(conn, || {
                for (entry_seq, blob) in &entries {
                    max_seq_in_pack = max_seq_in_pack.max(*entry_seq);
                    if *entry_seq < seq {
                        continue;
                    }

                    let plaintext = decrypt_bytes(
                        sync_key,
                        blob,
                        format!("sync.ops:{device_id}:{entry_seq}").as_bytes(),
                    )?;
                    let op_json: serde_json::Value = serde_json::from_slice(&plaintext)?;
                    let inserted = insert_remote_oplog(conn, db_key, &plaintext, &op_json)?;
                    if inserted {
                        apply_op(conn, db_key, &op_json)?;
                        pack_applied += 1;
                    }
                }

                kv_set_i64(conn, &last_pulled_key, max_seq_in_pack)?;
                Ok(())
            })?;

            applied += pack_applied;
            new_last_pulled = max_seq_in_pack;
            seq = new_last_pulled + 1;

            if new_last_pulled > device_last_reported {
                let delta = (new_last_pulled - device_last_reported) as u64;
                device_last_reported = new_last_pulled;
                done_ops = (done_ops + delta).min(total_ops);
                if let Some(cb) = progress.as_deref_mut() {
                    cb(done_ops, total_ops);
                }
            }

            let chunk_end = chunk_start + OPS_PACK_CHUNK_SIZE - 1;
            if max_seq_in_pack < chunk_end {
                break;
            }
        }

        let mut tried_discover_start_seq = false;
        loop {
            let batch = fetch_ops_batch(
                remote,
                &ops_dir,
                seq,
                OPS_PREFETCH_BATCH_SIZE,
                OPS_PREFETCH_CONCURRENCY,
            )?;

            let mut blobs: Vec<(i64, Vec<u8>)> = Vec::with_capacity(batch.len());
            let mut hit_not_found = false;
            for (seq, blob) in batch {
                match blob {
                    Some(blob) => blobs.push((seq, blob)),
                    None => {
                        hit_not_found = true;
                        break;
                    }
                }
            }

            if blobs.is_empty() {
                // If remote ops were pruned/reset, a new device might not have `op_1.json`.
                // Try to discover the first available seq once (without relying exclusively on listing).
                if !tried_discover_start_seq && last_pulled_seq == 0 && seq == 1 {
                    tried_discover_start_seq = true;
                    if let Some(start_seq) = discover_first_available_seq(remote, &ops_dir, 500)? {
                        seq = start_seq;
                        continue;
                    }
                }
                break;
            }

            // Apply in a single transaction to avoid per-op auto-commit overhead.
            let mut batch_applied = 0u64;
            let mut batch_last_seq = new_last_pulled;
            with_immediate_transaction(conn, || {
                for (seq, blob) in &blobs {
                    let plaintext = decrypt_bytes(
                        sync_key,
                        blob,
                        format!("sync.ops:{device_id}:{seq}").as_bytes(),
                    )?;
                    let op_json: serde_json::Value = serde_json::from_slice(&plaintext)?;
                    let inserted = insert_remote_oplog(conn, db_key, &plaintext, &op_json)?;
                    if inserted {
                        apply_op(conn, db_key, &op_json)?;
                        batch_applied += 1;
                    }

                    batch_last_seq = *seq;
                }

                kv_set_i64(conn, &last_pulled_key, batch_last_seq)?;
                Ok(())
            })?;

            applied += batch_applied;
            new_last_pulled = batch_last_seq;
            seq = new_last_pulled + 1;

            if new_last_pulled > device_last_reported {
                let delta = (new_last_pulled - device_last_reported) as u64;
                device_last_reported = new_last_pulled;
                done_ops = (done_ops + delta).min(total_ops);
                if let Some(cb) = progress.as_deref_mut() {
                    cb(done_ops, total_ops);
                }
            }

            if hit_not_found {
                break;
            }
        }
    }

    let app_dir = crate::db::app_dir_from_conn(conn)?;
    let missing_blob_refs = list_missing_embedding_artifact_blob_refs(conn, app_dir.as_path())?;
    let mut total_units = total_ops;
    let mut done_units = done_ops;
    if !missing_blob_refs.is_empty() {
        total_units += missing_blob_refs.len() as u64;
        if let Some(cb) = progress.as_deref_mut() {
            cb(done_units, total_units);
        }
    }

    if !missing_blob_refs.is_empty() {
        let mut on_downloaded = |delta: u64| {
            done_units = (done_units + delta).min(total_units);
            if let Some(cb) = progress.as_deref_mut() {
                cb(done_units, total_units);
            }
        };
        let outcome = download_embedding_artifact_blobs_by_refs(
            conn,
            db_key,
            sync_key,
            remote,
            remote_root,
            app_dir.as_path(),
            &missing_blob_refs,
            Some(&mut on_downloaded),
        )?;
        total_units = total_units.saturating_sub(outcome.missing_remote);
        done_units = done_units.min(total_units);
    }

    let _ = process_pending_blob_repairs_for_scope(conn, db_key, sync_key, remote, remote_root, 8)?;

    if let Some(cb) = progress {
        cb(done_units, total_units);
    }

    Ok(applied)
}

fn with_immediate_transaction<T>(conn: &Connection, f: impl FnOnce() -> Result<T>) -> Result<T> {
    conn.execute_batch("BEGIN IMMEDIATE;")?;
    match f() {
        Ok(v) => {
            conn.execute_batch("COMMIT;")?;
            Ok(v)
        }
        Err(e) => {
            let _ = conn.execute_batch("ROLLBACK;");
            Err(e)
        }
    }
}

fn fetch_ops_batch(
    remote: &impl RemoteStore,
    ops_dir: &str,
    start_seq: i64,
    batch_size: usize,
    concurrency: usize,
) -> Result<Vec<(i64, Option<Vec<u8>>)>> {
    if batch_size == 0 {
        return Ok(vec![]);
    }

    let concurrency = concurrency.max(1).min(batch_size);
    let mut buckets: Vec<Vec<i64>> = vec![Vec::new(); concurrency];
    for i in 0..batch_size {
        buckets[i % concurrency].push(start_seq + i as i64);
    }

    let mut out: Vec<(i64, Option<Vec<u8>>)> = Vec::with_capacity(batch_size);
    thread::scope(|scope| -> Result<()> {
        let mut handles = Vec::with_capacity(concurrency);
        for bucket in buckets {
            handles.push(scope.spawn(move || -> Result<Vec<(i64, Option<Vec<u8>>)>> {
                let mut chunk: Vec<(i64, Option<Vec<u8>>)> = Vec::with_capacity(bucket.len());
                let mut hit_not_found = false;
                for seq in bucket {
                    if hit_not_found {
                        chunk.push((seq, None));
                        continue;
                    }

                    let path = format!("{ops_dir}op_{seq}.json");
                    match remote.get(&path) {
                        Ok(bytes) => chunk.push((seq, Some(bytes))),
                        Err(e) if e.is::<NotFound>() => {
                            chunk.push((seq, None));
                            // Ops are expected to be contiguous; if this seq is missing, all higher
                            // seqs are also missing (for this device).
                            hit_not_found = true;
                        }
                        Err(e) => return Err(e),
                    }
                }
                Ok(chunk)
            }));
        }

        for handle in handles {
            let chunk = handle
                .join()
                .map_err(|_| anyhow!("fetch op batch thread panicked"))??;
            out.extend(chunk);
        }
        Ok(())
    })?;

    out.sort_by_key(|(seq, _)| *seq);
    Ok(out)
}

fn discover_first_available_seq(
    remote: &impl RemoteStore,
    ops_dir: &str,
    probe_limit: i64,
) -> Result<Option<i64>> {
    fn parse_seq_from_path(ops_dir: &str, entry: &str) -> Option<i64> {
        let rest = entry.strip_prefix(ops_dir)?;
        let rest = rest.strip_prefix("op_")?;
        let rest = rest.strip_suffix(".json")?;
        if rest.is_empty() {
            return None;
        }
        if rest.bytes().any(|b| !b.is_ascii_digit()) {
            return None;
        }
        rest.parse::<i64>().ok()
    }

    // Best effort: use listing if available.
    if let Ok(entries) = remote.list(ops_dir) {
        let mut min_seq: Option<i64> = None;
        for entry in entries {
            let Some(seq) = parse_seq_from_path(ops_dir, &entry) else {
                continue;
            };
            min_seq = Some(match min_seq {
                Some(existing) => existing.min(seq),
                None => seq,
            });
        }
        if min_seq.is_some() {
            return Ok(min_seq);
        }
    }

    // Fallback: probe a small range to avoid depending on listing.
    for seq in 2..=probe_limit {
        let path = format!("{ops_dir}op_{seq}.json");
        match remote.get(&path) {
            Ok(_) => return Ok(Some(seq)),
            Err(e) if e.is::<NotFound>() => continue,
            Err(e) => return Err(e),
        }
    }

    Ok(None)
}

#[derive(Debug, serde::Deserialize)]
struct DeviceCursorJson {
    max_seq: i64,
}

fn read_remote_cursor_max_seq(
    remote: &impl RemoteStore,
    remote_root_dir: &str,
    device_id: &str,
) -> Result<Option<i64>> {
    let path = format!("{remote_root_dir}{device_id}/cursor.json");
    match remote.get(&path) {
        Ok(bytes) => {
            let parsed: DeviceCursorJson = serde_json::from_slice(&bytes)?;
            Ok(Some(parsed.max_seq.max(0)))
        }
        Err(e) if e.is::<NotFound>() => Ok(None),
        Err(e) => Err(e),
    }
}

fn reconcile_remote_generation_before_pull(
    conn: &Connection,
    remote: &impl RemoteStore,
    remote_root_dir: &str,
    scope_id: &str,
) -> Result<()> {
    let local_generation = webdav_manifest::load_local_generation_id(conn, scope_id)?;
    let remote_generation = webdav_manifest::read_sync_manifest(remote, remote_root_dir)?
        .map(|manifest| manifest.generation_id);

    match (local_generation, remote_generation) {
        (Some(local), Some(remote)) if local != remote => {
            webdav_manifest::clear_local_scope_state(conn, scope_id)?;
            webdav_manifest::store_local_generation_id(conn, scope_id, &remote)?;
        }
        (None, Some(remote)) => {
            webdav_manifest::store_local_generation_id(conn, scope_id, &remote)?;
        }
        (Some(_), None) => {
            webdav_manifest::clear_local_scope_state(conn, scope_id)?;
        }
        (None, None) => {}
        (Some(_), Some(_)) => {}
    }
    Ok(())
}

fn read_remote_device_max_seq(
    remote: &impl RemoteStore,
    remote_root_dir: &str,
    device_id: &str,
) -> Result<Option<i64>> {
    if let Some(manifest) = webdav_manifest::read_device_manifest(remote, remote_root_dir, device_id)?
    {
        return Ok(Some(manifest.max_seq.max(0)));
    }
    read_remote_cursor_max_seq(remote, remote_root_dir, device_id)
}

fn infer_remote_max_seq_from_packs(
    remote: &impl RemoteStore,
    packs_dir: &str,
) -> Result<Option<i64>> {
    let entries = remote.list(packs_dir)?;
    let mut max_chunk_start: Option<i64> = None;
    for entry in entries {
        let Some(rest) = entry.strip_prefix(packs_dir) else {
            continue;
        };
        let Some(chunk_start) = rest
            .strip_prefix("pack_")
            .and_then(|s| s.strip_suffix(".bin"))
            .and_then(|s| s.parse::<i64>().ok())
        else {
            continue;
        };
        max_chunk_start = Some(max_chunk_start.unwrap_or(chunk_start).max(chunk_start));
    }

    let Some(chunk_start) = max_chunk_start else {
        return Ok(None);
    };

    let pack_path = format!("{packs_dir}pack_{chunk_start}.bin");
    let bytes = match remote.get(&pack_path) {
        Ok(bytes) => bytes,
        Err(e) if e.is::<NotFound>() => return Ok(None),
        Err(e) => return Err(e),
    };

    let entries = decode_ops_pack(&bytes)?;
    Ok(entries.iter().map(|(seq, _)| *seq).max())
}

fn is_reserved_remote_dir(device_id: &str) -> bool {
    matches!(device_id, "attachments" | "embedding_artifacts")
}

fn list_remote_sync_device_ids(
    remote: &impl RemoteStore,
    remote_root_dir: &str,
) -> Result<Vec<String>> {
    let mut device_ids = std::collections::BTreeSet::new();
    let sync_manifest_path = webdav_manifest::sync_manifest_path(remote_root_dir);
    for entry in remote.list(remote_root_dir)? {
        if entry == sync_manifest_path {
            continue;
        }
        let Some(device_id) = device_id_from_child_dir(remote_root_dir, &entry) else {
            continue;
        };
        if is_reserved_remote_dir(&device_id) {
            continue;
        }

        if webdav_manifest::read_device_manifest(remote, remote_root_dir, &device_id)?.is_some() {
            device_ids.insert(device_id);
            continue;
        }

        let cursor_path = format!("{remote_root_dir}{device_id}/cursor.json");
        let ops_dir = format!("{remote_root_dir}{device_id}/ops/");
        let packs_dir = format!("{remote_root_dir}{device_id}/packs/");
        if remote.exists(&cursor_path)?
            || !remote.list(&ops_dir)?.is_empty()
            || !remote.list(&packs_dir)?.is_empty()
        {
            device_ids.insert(device_id);
        }
    }
    Ok(device_ids.into_iter().collect())
}

#[cfg(test)]
include!("03_pull_tests.rs");

fn discover_first_available_pack_chunk_start(
    remote: &impl RemoteStore,
    packs_dir: &str,
) -> Result<Option<i64>> {
    fn parse_chunk_start_from_path(packs_dir: &str, entry: &str) -> Option<i64> {
        let rest = entry.strip_prefix(packs_dir)?;
        let rest = rest.strip_prefix("pack_")?;
        let rest = rest.strip_suffix(".bin")?;
        if rest.is_empty() {
            return None;
        }
        if rest.bytes().any(|b| !b.is_ascii_digit()) {
            return None;
        }
        rest.parse::<i64>().ok()
    }

    if let Ok(entries) = remote.list(packs_dir) {
        let mut min_seq: Option<i64> = None;
        for entry in entries {
            let Some(seq) = parse_chunk_start_from_path(packs_dir, &entry) else {
                continue;
            };
            min_seq = Some(match min_seq {
                Some(existing) => existing.min(seq),
                None => seq,
            });
        }
        if min_seq.is_some() {
            return Ok(min_seq);
        }
    }

    Ok(None)
}

fn ops_pack_chunk_start(seq: i64) -> i64 {
    if seq <= 1 {
        return 1;
    }
    ((seq - 1) / OPS_PACK_CHUNK_SIZE) * OPS_PACK_CHUNK_SIZE + 1
}

fn encode_ops_pack(entries: &[(i64, Vec<u8>)]) -> Result<Vec<u8>> {
    let count: u32 = entries
        .len()
        .try_into()
        .map_err(|_| anyhow!("too many ops in pack"))?;

    let mut out: Vec<u8> = Vec::new();
    out.extend_from_slice(OPS_PACK_MAGIC_V1);
    out.extend_from_slice(&count.to_le_bytes());

    for (seq, blob) in entries {
        out.extend_from_slice(&seq.to_le_bytes());
        let len: u32 = blob
            .len()
            .try_into()
            .map_err(|_| anyhow!("op blob too large"))?;
        out.extend_from_slice(&len.to_le_bytes());
        out.extend_from_slice(blob);
    }

    Ok(out)
}

fn decode_ops_pack(bytes: &[u8]) -> Result<Vec<(i64, Vec<u8>)>> {
    if bytes.len() < OPS_PACK_MAGIC_V1.len() + 4 {
        return Err(anyhow!("invalid pack: too short"));
    }
    if &bytes[..OPS_PACK_MAGIC_V1.len()] != OPS_PACK_MAGIC_V1 {
        return Err(anyhow!("invalid pack: bad magic"));
    }

    let mut cursor = OPS_PACK_MAGIC_V1.len();
    let count = u32::from_le_bytes(
        bytes[cursor..cursor + 4]
            .try_into()
            .map_err(|_| anyhow!("invalid pack: count"))?,
    ) as usize;
    cursor += 4;

    let mut out: Vec<(i64, Vec<u8>)> = Vec::with_capacity(count);
    for _ in 0..count {
        if cursor + 8 + 4 > bytes.len() {
            return Err(anyhow!("invalid pack: truncated header"));
        }

        let seq = i64::from_le_bytes(
            bytes[cursor..cursor + 8]
                .try_into()
                .map_err(|_| anyhow!("invalid pack: seq"))?,
        );
        cursor += 8;

        let len = u32::from_le_bytes(
            bytes[cursor..cursor + 4]
                .try_into()
                .map_err(|_| anyhow!("invalid pack: len"))?,
        ) as usize;
        cursor += 4;

        if cursor + len > bytes.len() {
            return Err(anyhow!("invalid pack: truncated body"));
        }
        let blob = bytes[cursor..cursor + len].to_vec();
        cursor += len;

        out.push((seq, blob));
    }

    Ok(out)
}

fn get_or_create_device_id(conn: &Connection) -> Result<String> {
    let existing: Option<String> = conn
        .query_row(
            r#"SELECT value FROM kv WHERE key = 'device_id'"#,
            [],
            |row| row.get(0),
        )
        .optional()?;

    if let Some(device_id) = existing {
        return Ok(device_id);
    }

    let device_id = uuid::Uuid::new_v4().to_string();
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES ('device_id', ?1)"#,
        params![device_id],
    )?;
    Ok(device_id)
}

fn kv_get_i64(conn: &Connection, key: &str) -> Result<Option<i64>> {
    let value: Option<String> = conn
        .query_row(
            r#"SELECT value FROM kv WHERE key = ?1"#,
            params![key],
            |row| row.get(0),
        )
        .optional()?;
    Ok(value.and_then(|v| v.parse::<i64>().ok()))
}

fn kv_get_string(conn: &Connection, key: &str) -> Result<Option<String>> {
    conn.query_row(
        r#"SELECT value FROM kv WHERE key = ?1"#,
        params![key],
        |row| row.get(0),
    )
    .optional()
    .map_err(Into::into)
}

fn kv_set_i64(conn: &Connection, key: &str, value: i64) -> Result<()> {
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES (?1, ?2)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        params![key, value.to_string()],
    )?;
    Ok(())
}

fn kv_set_string(conn: &Connection, key: &str, value: &str) -> Result<()> {
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES (?1, ?2)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        params![key, value],
    )?;
    Ok(())
}

fn device_id_from_child_dir(root_dir: &str, child_dir: &str) -> Option<String> {
    let rest = child_dir.strip_prefix(root_dir)?;
    let rest = rest.trim_end_matches('/');
    if rest.is_empty() || rest.contains('/') {
        return None;
    }
    Some(rest.to_string())
}

fn insert_remote_oplog(
    conn: &Connection,
    db_key: &[u8; 32],
    op_plaintext_json: &[u8],
    op_json: &serde_json::Value,
) -> Result<bool> {
    let op_id = op_json["op_id"]
        .as_str()
        .ok_or_else(|| anyhow!("oplog missing op_id"))?;
    let device_id = op_json["device_id"]
        .as_str()
        .ok_or_else(|| anyhow!("oplog missing device_id"))?;
    let seq = op_json["seq"]
        .as_i64()
        .ok_or_else(|| anyhow!("oplog missing seq"))?;
    let created_at = op_json["ts_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("oplog missing ts_ms"))?;

    let blob = encrypt_bytes(
        db_key,
        op_plaintext_json,
        format!("oplog.op_json:{op_id}").as_bytes(),
    )?;

    let mut stmt = conn.prepare_cached(
        r#"INSERT OR IGNORE INTO oplog(op_id, device_id, seq, op_json, created_at)
           VALUES (?1, ?2, ?3, ?4, ?5)"#,
    )?;
    let changed = stmt.execute(params![op_id, device_id, seq, blob, created_at])?;
    Ok(changed > 0)
}
