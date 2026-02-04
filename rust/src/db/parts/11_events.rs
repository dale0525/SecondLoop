fn get_event_by_id(conn: &Connection, key: &[u8; 32], id: &str) -> Result<Event> {
    let (title_blob, start_at_ms, end_at_ms, tz, source_entry_id, created_at_ms, updated_at_ms): (
        Vec<u8>,
        i64,
        i64,
        String,
        Option<String>,
        i64,
        i64,
    ) = conn
        .query_row(
            r#"
SELECT title, start_at_ms, end_at_ms, tz, source_entry_id, created_at_ms, updated_at_ms
FROM events
WHERE id = ?1
"#,
            params![id],
            |row| {
                Ok((
                    row.get(0)?,
                    row.get(1)?,
                    row.get(2)?,
                    row.get(3)?,
                    row.get(4)?,
                    row.get(5)?,
                    row.get(6)?,
                ))
            },
        )
        .map_err(|e| anyhow!("get event failed: {e}"))?;

    let title_bytes = decrypt_bytes(key, &title_blob, b"event.title")?;
    let title =
        String::from_utf8(title_bytes).map_err(|_| anyhow!("event title is not valid utf-8"))?;

    Ok(Event {
        id: id.to_string(),
        title,
        start_at_ms,
        end_at_ms,
        tz,
        source_entry_id,
        created_at_ms,
        updated_at_ms,
    })
}

pub fn upsert_event(
    conn: &Connection,
    key: &[u8; 32],
    id: &str,
    title: &str,
    start_at_ms: i64,
    end_at_ms: i64,
    tz: &str,
    source_entry_id: Option<&str>,
) -> Result<Event> {
    let now = now_ms();
    let title_blob = encrypt_bytes(key, title.as_bytes(), b"event.title")?;
    conn.execute(
        r#"
INSERT INTO events (
  id, title, start_at_ms, end_at_ms, tz, source_entry_id, created_at_ms, updated_at_ms
)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
ON CONFLICT(id) DO UPDATE SET
  title = excluded.title,
  start_at_ms = excluded.start_at_ms,
  end_at_ms = excluded.end_at_ms,
  tz = excluded.tz,
  source_entry_id = excluded.source_entry_id,
  updated_at_ms = excluded.updated_at_ms
"#,
        params![
            id,
            title_blob,
            start_at_ms,
            end_at_ms,
            tz,
            source_entry_id,
            now,
            now
        ],
    )?;

    let event = get_event_by_id(conn, key, id)?;

    let device_id = get_or_create_device_id(conn)?;
    let seq = next_device_seq(conn, &device_id)?;
    let op = serde_json::json!({
        "op_id": uuid::Uuid::new_v4().to_string(),
        "device_id": device_id,
        "seq": seq,
        "ts_ms": now,
        "type": "event.upsert.v1",
        "payload": {
            "event_id": event.id.as_str(),
            "title": event.title.as_str(),
            "start_at_ms": event.start_at_ms,
            "end_at_ms": event.end_at_ms,
            "tz": event.tz.as_str(),
            "source_entry_id": event.source_entry_id.as_deref(),
            "created_at_ms": event.created_at_ms,
            "updated_at_ms": event.updated_at_ms,
        }
    });
    insert_oplog(conn, key, &op)?;

    Ok(event)
}

pub fn list_events(conn: &Connection, key: &[u8; 32]) -> Result<Vec<Event>> {
    let mut stmt = conn.prepare(
        r#"
SELECT id, title, start_at_ms, end_at_ms, tz, source_entry_id, created_at_ms, updated_at_ms
FROM events
ORDER BY start_at_ms ASC, end_at_ms ASC
"#,
    )?;

    let mut rows = stmt.query([])?;
    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        let id: String = row.get(0)?;
        let title_blob: Vec<u8> = row.get(1)?;
        let start_at_ms: i64 = row.get(2)?;
        let end_at_ms: i64 = row.get(3)?;
        let tz: String = row.get(4)?;
        let source_entry_id: Option<String> = row.get(5)?;
        let created_at_ms: i64 = row.get(6)?;
        let updated_at_ms: i64 = row.get(7)?;

        let title_bytes = decrypt_bytes(key, &title_blob, b"event.title")?;
        let title = String::from_utf8(title_bytes)
            .map_err(|_| anyhow!("event title is not valid utf-8"))?;

        result.push(Event {
            id,
            title,
            start_at_ms,
            end_at_ms,
            tz,
            source_entry_id,
            created_at_ms,
            updated_at_ms,
        });
    }
    Ok(result)
}

pub fn list_events_in_range(
    conn: &Connection,
    key: &[u8; 32],
    start_at_ms_inclusive: i64,
    end_at_ms_exclusive: i64,
) -> Result<Vec<Event>> {
    let mut stmt = conn.prepare(
        r#"
SELECT id, title, start_at_ms, end_at_ms, tz, source_entry_id, created_at_ms, updated_at_ms
FROM events
WHERE start_at_ms < ?2 AND end_at_ms > ?1
ORDER BY start_at_ms ASC, end_at_ms ASC
"#,
    )?;

    let mut rows = stmt.query(params![start_at_ms_inclusive, end_at_ms_exclusive])?;
    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        let id: String = row.get(0)?;
        let title_blob: Vec<u8> = row.get(1)?;
        let start_at_ms: i64 = row.get(2)?;
        let end_at_ms: i64 = row.get(3)?;
        let tz: String = row.get(4)?;
        let source_entry_id: Option<String> = row.get(5)?;
        let created_at_ms: i64 = row.get(6)?;
        let updated_at_ms: i64 = row.get(7)?;

        let title_bytes = decrypt_bytes(key, &title_blob, b"event.title")?;
        let title = String::from_utf8(title_bytes)
            .map_err(|_| anyhow!("event title is not valid utf-8"))?;

        result.push(Event {
            id,
            title,
            start_at_ms,
            end_at_ms,
            tz,
            source_entry_id,
            created_at_ms,
            updated_at_ms,
        });
    }
    Ok(result)
}
