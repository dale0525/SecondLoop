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

