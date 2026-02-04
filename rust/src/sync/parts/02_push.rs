pub fn clear_remote_root(remote: &impl RemoteStore, remote_root: &str) -> Result<()> {
    let remote_root_dir = normalize_dir(remote_root);
    if remote_root_dir == "/" {
        return Err(anyhow!("refusing to clear remote root '/'"));
    }

    match remote.delete(&remote_root_dir) {
        Ok(()) => Ok(()),
        Err(e) if e.is::<NotFound>() => Ok(()),
        Err(e) => Err(e),
    }
}

pub fn push(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    remote: &impl RemoteStore,
    remote_root: &str,
) -> Result<u64> {
    push_internal(conn, db_key, sync_key, remote, remote_root, true)
}

pub fn push_ops_only(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    remote: &impl RemoteStore,
    remote_root: &str,
) -> Result<u64> {
    push_internal(conn, db_key, sync_key, remote, remote_root, false)
}

fn push_internal(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    remote: &impl RemoteStore,
    remote_root: &str,
    upload_attachment_bytes: bool,
) -> Result<u64> {
    crate::db::backfill_attachments_oplog_if_needed(conn, db_key)?;

    let device_id = get_or_create_device_id(conn)?;
    let app_dir = app_dir_from_conn(conn)?;
    let app_dir_path = app_dir.as_path();
    let remote_root_dir = normalize_dir(remote_root);
    let scope_id = sync_scope_id(remote, &remote_root_dir);
    let ops_dir = format!("{remote_root_dir}{device_id}/ops/");
    remote.mkdir_all(&ops_dir)?;
    let packs_dir = format!("{remote_root_dir}{device_id}/packs/");
    remote.mkdir_all(&packs_dir)?;

    let last_pushed_key = format!("sync.last_pushed_seq:{scope_id}");
    let last_pushed_seq = kv_get_i64(conn, &last_pushed_key)?.unwrap_or(0);

    let attachments_dir = format!("{remote_root_dir}attachments/");
    remote.mkdir_all(&attachments_dir)?;

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

    fn push_ops_after<R: RemoteStore>(
        ctx: &PushOpsContext<'_, R>,
        after_seq: i64,
    ) -> Result<(u64, i64)> {
        let mut stmt = ctx.conn.prepare(
            r#"SELECT op_id, seq, op_json
               FROM oplog
               WHERE device_id = ?1 AND seq > ?2
               ORDER BY seq ASC"#,
        )?;

        let mut rows = stmt.query(params![ctx.device_id, after_seq])?;
        let mut pushed: u64 = 0;
        let mut max_seq = after_seq;
        let mut uploaded_attachments: BTreeSet<String> = BTreeSet::new();
        let mut deleted_attachments: BTreeSet<String> = BTreeSet::new();
        let mut touched_pack_chunks: BTreeSet<i64> = BTreeSet::new();

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
                        if uploaded_attachments.insert(sha256.to_string()) {
                            let _ = upload_attachment_bytes_if_present(
                                ctx.conn,
                                ctx.db_key,
                                ctx.sync_key,
                                ctx.remote,
                                ctx.attachments_dir,
                                ctx.app_dir,
                                sha256,
                            )?;
                        }
                    }
                }

                if op_json["type"].as_str() == Some("attachment.delete.v1") {
                    if let Some(sha256) = op_json["payload"]["sha256"].as_str() {
                        if deleted_attachments.insert(sha256.to_string()) {
                            let remote_path = format!("{}{}.bin", ctx.attachments_dir, sha256);
                            match ctx.remote.delete(&remote_path) {
                                Ok(()) => {}
                                Err(e) if e.is::<NotFound>() => {}
                                Err(e) => return Err(e),
                            }
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
            ctx.remote.put(&file_path, file_blob)?;
            touched_pack_chunks.insert(ops_pack_chunk_start(seq));

            pushed += 1;
            if seq > max_seq {
                max_seq = seq;
            }
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

    let (pushed, max_seq) = push_ops_after(&ctx, last_pushed_seq)?;

    if pushed > 0 {
        kv_set_i64(conn, &last_pushed_key, max_seq)?;
        return Ok(pushed);
    }

    // If the remote target was cleared/reset (e.g. user switches directories then comes back),
    // our cursor may say "up to date" while the remote no longer has the last pushed file.
    if last_pushed_seq > 0 {
        let last_path = format!("{ops_dir}op_{last_pushed_seq}.json");
        match remote.get(&last_path) {
            Ok(_) => {}
            Err(e) if e.is::<NotFound>() => {
                let (re_pushed, re_max_seq) = push_ops_after(&ctx, 0)?;
                if re_pushed > 0 {
                    kv_set_i64(conn, &last_pushed_key, re_max_seq)?;
                }
                return Ok(re_pushed);
            }
            Err(e) => return Err(e),
        }
    }

    Ok(0)
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

pub fn download_attachment_bytes(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    remote: &impl RemoteStore,
    remote_root: &str,
    sha256: &str,
) -> Result<()> {
    let app_dir = app_dir_from_conn(conn)?;

    let stored_path: Option<String> = conn
        .query_row(
            r#"SELECT path FROM attachments WHERE sha256 = ?1"#,
            params![sha256],
            |row| row.get(0),
        )
        .optional()?;
    let stored_path = stored_path.ok_or_else(|| anyhow!("attachment not found"))?;

    let remote_root_dir = normalize_dir(remote_root);
    let remote_path = format!("{remote_root_dir}attachments/{sha256}.bin");
    let ciphertext = remote.get(&remote_path)?;
    let aad = format!("sync.attachment.bytes:{sha256}");
    let plaintext = decrypt_bytes(sync_key, &ciphertext, aad.as_bytes())?;

    if sha256_hex(&plaintext) != sha256 {
        return Err(anyhow!("attachment sha256 mismatch after download"));
    }

    let local_path = app_dir.join(&stored_path);
    if let Some(parent) = local_path.parent() {
        fs::create_dir_all(parent)?;
    }

    let local_aad = format!("attachment.bytes:{sha256}");
    let local_cipher = encrypt_bytes(db_key, &plaintext, local_aad.as_bytes())?;
    fs::write(local_path, local_cipher)?;
    Ok(())
}

pub fn upload_attachment_bytes(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    remote: &impl RemoteStore,
    remote_root: &str,
    sha256: &str,
) -> Result<bool> {
    let app_dir = app_dir_from_conn(conn)?;
    let remote_root_dir = normalize_dir(remote_root);
    let attachments_dir = format!("{remote_root_dir}attachments/");
    remote.mkdir_all(&attachments_dir)?;
    upload_attachment_bytes_if_present(
        conn,
        db_key,
        sync_key,
        remote,
        &attachments_dir,
        app_dir.as_path(),
        sha256,
    )
}

fn upload_all_local_attachment_bytes(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    remote: &impl RemoteStore,
    attachments_dir: &str,
    app_dir: &Path,
) -> Result<u64> {
    let existing = remote.list(attachments_dir)?;
    let existing: BTreeSet<String> = existing.into_iter().collect();

    let mut stmt =
        conn.prepare(r#"SELECT sha256 FROM attachments ORDER BY created_at ASC, sha256 ASC"#)?;
    let mut rows = stmt.query([])?;

    let mut uploaded = 0u64;
    while let Some(row) = rows.next()? {
        let sha256: String = row.get(0)?;
        let remote_path = format!("{attachments_dir}{sha256}.bin");
        if existing.contains(&remote_path) {
            continue;
        }
        match upload_attachment_bytes_if_present(
            conn,
            db_key,
            sync_key,
            remote,
            attachments_dir,
            app_dir,
            &sha256,
        ) {
            Ok(true) => uploaded += 1,
            Ok(false) => {}
            Err(e) => return Err(e),
        }
    }

    Ok(uploaded)
}

fn upload_attachment_bytes_if_present(
    conn: &Connection,
    db_key: &[u8; 32],
    sync_key: &[u8; 32],
    remote: &impl RemoteStore,
    attachments_dir: &str,
    app_dir: &Path,
    sha256: &str,
) -> Result<bool> {
    let plaintext = match crate::db::read_attachment_bytes(conn, db_key, app_dir, sha256) {
        Ok(bytes) => bytes,
        Err(e)
            if e.downcast_ref::<std::io::Error>()
                .is_some_and(|io| io.kind() == std::io::ErrorKind::NotFound) =>
        {
            return Ok(false);
        }
        Err(e) => return Err(e),
    };

    let remote_aad = format!("sync.attachment.bytes:{sha256}");
    let ciphertext = encrypt_bytes(sync_key, &plaintext, remote_aad.as_bytes())?;
    let remote_path = format!("{attachments_dir}{sha256}.bin");
    remote.put(&remote_path, ciphertext)?;
    Ok(true)
}

fn app_dir_from_conn(conn: &Connection) -> Result<PathBuf> {
    let mut stmt = conn.prepare("PRAGMA database_list")?;
    let mut rows = stmt.query([])?;
    while let Some(row) = rows.next()? {
        let name: String = row.get(1)?;
        if name != "main" {
            continue;
        }
        let file: String = row.get(2)?;
        if file.is_empty() {
            break;
        }
        let path = PathBuf::from(file);
        let Some(parent) = path.parent() else {
            break;
        };
        return Ok(parent.to_path_buf());
    }
    Err(anyhow!("unable to derive app_dir from sqlite connection"))
}

fn sha256_hex(bytes: &[u8]) -> String {
    let digest = Sha256::digest(bytes);
    let mut out = String::with_capacity(64);
    for b in digest {
        use std::fmt::Write;
        let _ = write!(&mut out, "{:02x}", b);
    }
    out
}

