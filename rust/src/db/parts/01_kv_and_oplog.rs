fn next_device_seq(conn: &Connection, device_id: &str) -> Result<i64> {
    let max_seq: Option<i64> = conn.query_row(
        r#"SELECT MAX(seq) FROM oplog WHERE device_id = ?1"#,
        params![device_id],
        |row| row.get(0),
    )?;
    Ok(max_seq.unwrap_or(0) + 1)
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

fn kv_set_string(conn: &Connection, key: &str, value: &str) -> Result<()> {
    conn.execute(
        r#"INSERT INTO kv(key, value) VALUES (?1, ?2)
           ON CONFLICT(key) DO UPDATE SET value = excluded.value"#,
        params![key, value],
    )?;
    Ok(())
}

fn kv_set_i64(conn: &Connection, key: &str, value: i64) -> Result<()> {
    kv_set_string(conn, key, &value.to_string())
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OplogRetentionBackend {
    WebDav,
    LocalDir,
    ManagedVault,
}

impl OplogRetentionBackend {
    fn enabled_key(self) -> &'static str {
        match self {
            OplogRetentionBackend::WebDav => "oplog.retention.backend.webdav",
            OplogRetentionBackend::LocalDir => "oplog.retention.backend.localdir",
            OplogRetentionBackend::ManagedVault => "oplog.retention.backend.managed_vault",
        }
    }
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct OplogRetentionMaintenanceStats {
    pub before_count: u64,
    pub after_count: u64,
    pub pruned_count: u64,
}

const KV_OPLOG_RETENTION_ENABLED: &str = "oplog.retention.enabled";
const KV_OPLOG_RETENTION_KEEP_RECENT_OPS: &str = "oplog.retention.keep_recent_ops";
const KV_OPLOG_RETENTION_KEEP_RECENT_DAYS: &str = "oplog.retention.keep_recent_days";
const OPLOG_RETENTION_DEFAULT_KEEP_RECENT_OPS: i64 = 5_000;
const OPLOG_RETENTION_DEFAULT_KEEP_RECENT_DAYS: i64 = 7;
const OPLOG_RETENTION_MS_PER_DAY: i64 = 86_400_000;

fn kv_get_i64(conn: &Connection, key: &str) -> Result<Option<i64>> {
    let Some(value) = kv_get_string(conn, key)? else {
        return Ok(None);
    };
    let parsed = value.trim().parse::<i64>().ok();
    Ok(parsed)
}

fn kv_get_bool_or_default(conn: &Connection, key: &str, default: bool) -> Result<bool> {
    let Some(value) = kv_get_string(conn, key)? else {
        return Ok(default);
    };

    let normalized = value.trim().to_ascii_lowercase();
    let parsed = match normalized.as_str() {
        "1" | "true" | "yes" | "on" => Some(true),
        "0" | "false" | "no" | "off" => Some(false),
        _ => None,
    };

    Ok(parsed.unwrap_or(default))
}

fn count_oplog_rows_for_device(conn: &Connection, device_id: &str) -> Result<u64> {
    let count = conn.query_row(
        r#"SELECT COUNT(*) FROM oplog WHERE device_id = ?1"#,
        params![device_id],
        |row| row.get::<_, i64>(0),
    )?;
    Ok(count.max(0) as u64)
}

fn keep_recent_ops(conn: &Connection) -> Result<i64> {
    let value = kv_get_i64(conn, KV_OPLOG_RETENTION_KEEP_RECENT_OPS)?
        .unwrap_or(OPLOG_RETENTION_DEFAULT_KEEP_RECENT_OPS);
    Ok(value.max(0))
}

fn keep_recent_days(conn: &Connection) -> Result<i64> {
    let value = kv_get_i64(conn, KV_OPLOG_RETENTION_KEEP_RECENT_DAYS)?
        .unwrap_or(OPLOG_RETENTION_DEFAULT_KEEP_RECENT_DAYS);
    Ok(value.max(0))
}

fn backend_ack_seq(
    conn: &Connection,
    backend: OplogRetentionBackend,
    scope_id: &str,
    device_id: &str,
) -> Result<i64> {
    let seq = match backend {
        OplogRetentionBackend::WebDav | OplogRetentionBackend::LocalDir => kv_get_i64(
            conn,
            format!("sync.last_pushed_seq:{scope_id}").as_str(),
        )?
        .unwrap_or(0),
        OplogRetentionBackend::ManagedVault => {
            let device_key = format!("managed_vault.last_pushed_seq:{scope_id}:{device_id}");
            if let Some(value) = kv_get_i64(conn, &device_key)? {
                value
            } else {
                kv_get_i64(
                    conn,
                    format!("managed_vault.last_pushed_seq:{scope_id}").as_str(),
                )?
                .unwrap_or(0)
            }
        }
    };
    Ok(seq.max(0))
}

fn ack_seq_floor_across_scopes(conn: &Connection, device_id: &str, current: i64) -> Result<i64> {
    if current <= 0 {
        return Ok(0);
    }

    let mut floor = current;
    let mut stmt = conn.prepare(
        r#"SELECT key, value
           FROM kv
           WHERE key LIKE 'sync.last_pushed_seq:%'
              OR key LIKE 'managed_vault.last_pushed_seq:%'"#,
    )?;
    let mut rows = stmt.query([])?;

    while let Some(row) = rows.next()? {
        let key: String = row.get(0)?;
        let value: String = row.get(1)?;
        let Ok(seq) = value.trim().parse::<i64>() else {
            continue;
        };
        if seq <= 0 {
            continue;
        }

        if key.starts_with("sync.last_pushed_seq:") {
            floor = floor.min(seq);
            continue;
        }

        if let Some(suffix) = key.strip_prefix("managed_vault.last_pushed_seq:") {
            let is_legacy = !suffix.contains(':');
            let is_device_scoped = suffix.ends_with(format!(":{device_id}").as_str());
            if is_legacy || is_device_scoped {
                floor = floor.min(seq);
            }
        }
    }

    Ok(floor.max(0))
}

pub fn run_oplog_retention_maintenance(
    conn: &Connection,
    backend: OplogRetentionBackend,
    scope_id: &str,
) -> Result<OplogRetentionMaintenanceStats> {
    let device_id = get_or_create_device_id(conn)?;
    let before_count = count_oplog_rows_for_device(conn, &device_id)?;
    let mut stats = OplogRetentionMaintenanceStats {
        before_count,
        after_count: before_count,
        pruned_count: 0,
    };

    if before_count == 0 {
        return Ok(stats);
    }

    if !kv_get_bool_or_default(conn, KV_OPLOG_RETENTION_ENABLED, true)? {
        return Ok(stats);
    }

    if !kv_get_bool_or_default(conn, backend.enabled_key(), true)? {
        return Ok(stats);
    }

    let Some(max_seq) = conn.query_row(
        r#"SELECT MAX(seq) FROM oplog WHERE device_id = ?1"#,
        params![device_id.as_str()],
        |row| row.get::<_, Option<i64>>(0),
    )? else {
        return Ok(stats);
    };

    let acknowledged = backend_ack_seq(conn, backend, scope_id, &device_id)?;
    if acknowledged <= 0 {
        return Ok(stats);
    }

    let acknowledged_floor = ack_seq_floor_across_scopes(conn, &device_id, acknowledged)?;
    if acknowledged_floor <= 0 {
        return Ok(stats);
    }

    let keep_ops = keep_recent_ops(conn)?;
    let seq_cutoff = if keep_ops == 0 {
        max_seq
    } else {
        max_seq.saturating_sub(keep_ops)
    };
    if seq_cutoff <= 0 {
        return Ok(stats);
    }

    let prune_up_to_seq = acknowledged_floor.min(seq_cutoff).max(0);
    if prune_up_to_seq <= 0 {
        return Ok(stats);
    }

    let keep_days = keep_recent_days(conn)?;
    let age_cutoff_ms = if keep_days == 0 {
        now_ms()
    } else {
        now_ms().saturating_sub(keep_days.saturating_mul(OPLOG_RETENTION_MS_PER_DAY))
    };

    let _ = conn.execute(
        r#"DELETE FROM oplog
           WHERE device_id = ?1
             AND seq <= ?2
             AND created_at <= ?3"#,
        params![device_id.as_str(), prune_up_to_seq, age_cutoff_ms],
    )?;

    let after_count = count_oplog_rows_for_device(conn, &device_id)?;
    stats.after_count = after_count;
    stats.pruned_count = before_count.saturating_sub(after_count);
    Ok(stats)
}

fn insert_oplog(conn: &Connection, key: &[u8; 32], op_json: &serde_json::Value) -> Result<()> {
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

    let plaintext = serde_json::to_vec(op_json)?;
    let blob = encrypt_bytes(key, &plaintext, format!("oplog.op_json:{op_id}").as_bytes())?;
    conn.execute(
        r#"INSERT INTO oplog(op_id, device_id, seq, op_json, created_at)
           VALUES (?1, ?2, ?3, ?4, ?5)"#,
        params![op_id, device_id, seq, blob, created_at],
    )?;
    Ok(())
}

const KV_ATTACHMENTS_OPLOG_BACKFILLED: &str = "oplog.backfill.attachments.v1";
const KV_ATTACHMENT_EXIF_OPLOG_BACKFILLED: &str = "oplog.backfill.attachment_exif.v1";
const KV_ATTACHMENT_PLACES_OPLOG_BACKFILLED: &str = "oplog.backfill.attachment_places.v1";
const KV_ATTACHMENT_ANNOTATIONS_OPLOG_BACKFILLED: &str =
    "oplog.backfill.attachment_annotations.v1";

pub fn backfill_attachments_oplog_if_needed(conn: &Connection, key: &[u8; 32]) -> Result<u64> {
    let attachments_backfilled = kv_get_string(conn, KV_ATTACHMENTS_OPLOG_BACKFILLED)?.is_some();
    let exif_backfilled = kv_get_string(conn, KV_ATTACHMENT_EXIF_OPLOG_BACKFILLED)?.is_some();
    let places_backfilled = kv_get_string(conn, KV_ATTACHMENT_PLACES_OPLOG_BACKFILLED)?.is_some();
    let annotations_backfilled =
        kv_get_string(conn, KV_ATTACHMENT_ANNOTATIONS_OPLOG_BACKFILLED)?.is_some();
    if attachments_backfilled && exif_backfilled && places_backfilled && annotations_backfilled {
        return Ok(0);
    }

    let device_id = get_or_create_device_id(conn)?;

    let mut ops_inserted = 0u64;

    if !attachments_backfilled {
        let mut stmt = conn.prepare(
            r#"
SELECT sha256, mime_type, byte_len, created_at
FROM attachments
ORDER BY created_at ASC, sha256 ASC
"#,
        )?;
        let mut rows = stmt.query([])?;
        while let Some(row) = rows.next()? {
            let sha256: String = row.get(0)?;
            let mime_type: String = row.get(1)?;
            let byte_len: i64 = row.get(2)?;
            let created_at_ms: i64 = row.get(3)?;

            let seq = next_device_seq(conn, &device_id)?;
            let op = serde_json::json!({
                "op_id": uuid::Uuid::new_v4().to_string(),
                "device_id": device_id.as_str(),
                "seq": seq,
                "ts_ms": created_at_ms,
                "type": "attachment.upsert.v1",
                "payload": {
                    "sha256": sha256,
                    "mime_type": mime_type,
                    "byte_len": byte_len,
                    "created_at_ms": created_at_ms,
                }
            });
            insert_oplog(conn, key, &op)?;
            ops_inserted += 1;
        }
    }

    if !attachments_backfilled {
        let mut stmt = conn.prepare(
            r#"
SELECT message_id, attachment_sha256, created_at
FROM message_attachments
ORDER BY created_at ASC, message_id ASC, attachment_sha256 ASC
"#,
        )?;
        let mut rows = stmt.query([])?;
        while let Some(row) = rows.next()? {
            let message_id: String = row.get(0)?;
            let attachment_sha256: String = row.get(1)?;
            let created_at_ms: i64 = row.get(2)?;

            let seq = next_device_seq(conn, &device_id)?;
            let op = serde_json::json!({
                "op_id": uuid::Uuid::new_v4().to_string(),
                "device_id": device_id.as_str(),
                "seq": seq,
                "ts_ms": created_at_ms,
                "type": "message.attachment.link.v1",
                "payload": {
                    "message_id": message_id,
                    "attachment_sha256": attachment_sha256,
                    "created_at_ms": created_at_ms,
                }
            });
            insert_oplog(conn, key, &op)?;
            ops_inserted += 1;
        }
    }

    if !attachments_backfilled {
        kv_set_string(conn, KV_ATTACHMENTS_OPLOG_BACKFILLED, "1")?;
    }

    if !exif_backfilled {
        let mut stmt = conn.prepare(
            r#"
SELECT attachment_sha256, metadata, created_at_ms, updated_at_ms
FROM attachment_exif
ORDER BY updated_at_ms ASC, attachment_sha256 ASC
"#,
        )?;
        let mut rows = stmt.query([])?;
        while let Some(row) = rows.next()? {
            let attachment_sha256: String = row.get(0)?;
            let blob: Vec<u8> = row.get(1)?;
            let created_at_ms: i64 = row.get(2)?;
            let updated_at_ms: i64 = row.get(3)?;

            let aad = format!("attachment.exif:{attachment_sha256}");
            let json = decrypt_bytes(key, &blob, aad.as_bytes())?;
            let metadata: AttachmentExifMetadata = serde_json::from_slice(&json)?;

            let seq = next_device_seq(conn, &device_id)?;
            let op = serde_json::json!({
                "op_id": uuid::Uuid::new_v4().to_string(),
                "device_id": device_id.as_str(),
                "seq": seq,
                "ts_ms": updated_at_ms,
                "type": "attachment.exif.upsert.v1",
                "payload": {
                    "attachment_sha256": attachment_sha256,
                    "captured_at_ms": metadata.captured_at_ms,
                    "latitude": metadata.latitude,
                    "longitude": metadata.longitude,
                    "created_at_ms": created_at_ms,
                    "updated_at_ms": updated_at_ms,
                }
            });
            insert_oplog(conn, key, &op)?;
            ops_inserted += 1;
        }

        kv_set_string(conn, KV_ATTACHMENT_EXIF_OPLOG_BACKFILLED, "1")?;
    }

    if !places_backfilled {
        let mut stmt = conn.prepare(
            r#"
SELECT attachment_sha256, status, lang, payload, created_at, updated_at
FROM attachment_places
WHERE status = 'ok' AND payload IS NOT NULL
ORDER BY updated_at ASC, attachment_sha256 ASC
"#,
        )?;
        let mut rows = stmt.query([])?;
        while let Some(row) = rows.next()? {
            let attachment_sha256: String = row.get(0)?;
            let status: String = row.get(1)?;
            let lang: String = row.get(2)?;
            let blob: Vec<u8> = row.get(3)?;
            let created_at_ms: i64 = row.get(4)?;
            let updated_at_ms: i64 = row.get(5)?;

            if status != "ok" {
                continue;
            }
            let aad = format!("attachment.place:{attachment_sha256}:{lang}");
            let json = decrypt_bytes(key, &blob, aad.as_bytes())?;
            let payload: serde_json::Value = serde_json::from_slice(&json)?;

            let seq = next_device_seq(conn, &device_id)?;
            let op = serde_json::json!({
                "op_id": uuid::Uuid::new_v4().to_string(),
                "device_id": device_id.as_str(),
                "seq": seq,
                "ts_ms": updated_at_ms,
                "type": "attachment.place.upsert.v1",
                "payload": {
                    "attachment_sha256": attachment_sha256,
                    "lang": lang,
                    "payload": payload,
                    "created_at_ms": created_at_ms,
                    "updated_at_ms": updated_at_ms,
                }
            });
            insert_oplog(conn, key, &op)?;
            ops_inserted += 1;
        }

        kv_set_string(conn, KV_ATTACHMENT_PLACES_OPLOG_BACKFILLED, "1")?;
    }

    if !annotations_backfilled {
        let mut stmt = conn.prepare(
            r#"
SELECT attachment_sha256, status, lang, model_name, payload, created_at, updated_at
FROM attachment_annotations
WHERE status = 'ok' AND payload IS NOT NULL
ORDER BY updated_at ASC, attachment_sha256 ASC
"#,
        )?;
        let mut rows = stmt.query([])?;
        while let Some(row) = rows.next()? {
            let attachment_sha256: String = row.get(0)?;
            let status: String = row.get(1)?;
            let lang: String = row.get(2)?;
            let model_name: Option<String> = row.get(3)?;
            let blob: Vec<u8> = row.get(4)?;
            let created_at_ms: i64 = row.get(5)?;
            let updated_at_ms: i64 = row.get(6)?;

            if status != "ok" {
                continue;
            }

            let aad = format!("attachment.annotation:{attachment_sha256}:{lang}");
            let json = decrypt_bytes(key, &blob, aad.as_bytes())?;
            let payload: serde_json::Value = serde_json::from_slice(&json)?;

            let model_name = model_name
                .unwrap_or_else(|| "unknown".to_string())
                .trim()
                .to_string();
            let model_name = if model_name.is_empty() {
                "unknown".to_string()
            } else {
                model_name
            };

            let seq = next_device_seq(conn, &device_id)?;
            let op = serde_json::json!({
                "op_id": uuid::Uuid::new_v4().to_string(),
                "device_id": device_id.as_str(),
                "seq": seq,
                "ts_ms": updated_at_ms,
                "type": "attachment.annotation.upsert.v1",
                "payload": {
                    "attachment_sha256": attachment_sha256,
                    "lang": lang,
                    "model_name": model_name,
                    "payload": payload,
                    "created_at_ms": created_at_ms,
                    "updated_at_ms": updated_at_ms,
                }
            });
            insert_oplog(conn, key, &op)?;
            ops_inserted += 1;
        }

        kv_set_string(conn, KV_ATTACHMENT_ANNOTATIONS_OPLOG_BACKFILLED, "1")?;
    }

    Ok(ops_inserted)
}

