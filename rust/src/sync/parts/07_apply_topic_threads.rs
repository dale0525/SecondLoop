// Topic thread sync apply helpers kept separate to keep each file under 1000 lines.

fn topic_thread_deleted_at_ms(conn: &Connection, thread_id: &str) -> Result<i64> {
    let key = format!("topic_thread.deleted_at:{thread_id}");
    Ok(kv_get_i64(conn, &key)?.unwrap_or(0))
}

fn apply_topic_thread_upsert(
    conn: &Connection,
    db_key: &[u8; 32],
    payload: &serde_json::Value,
) -> Result<()> {
    let thread_id = payload["thread_id"]
        .as_str()
        .ok_or_else(|| anyhow!("topic_thread.upsert.v1 missing thread_id"))?
        .trim();
    if thread_id.is_empty() {
        return Err(anyhow!("topic_thread.upsert.v1 thread_id cannot be empty"));
    }

    let conversation_id = payload["conversation_id"]
        .as_str()
        .ok_or_else(|| anyhow!("topic_thread.upsert.v1 missing conversation_id"))?
        .trim();
    if conversation_id.is_empty() {
        return Err(anyhow!(
            "topic_thread.upsert.v1 conversation_id cannot be empty"
        ));
    }

    let created_at_ms = payload["created_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("topic_thread.upsert.v1 missing created_at_ms"))?;
    let updated_at_ms = payload["updated_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("topic_thread.upsert.v1 missing updated_at_ms"))?;

    let deleted_at_ms = topic_thread_deleted_at_ms(conn, thread_id)?;
    if updated_at_ms <= deleted_at_ms {
        return Ok(());
    }

    ensure_placeholder_conversation_row(conn, db_key, conversation_id, created_at_ms)?;

    let title = payload["title"]
        .as_str()
        .map(str::trim)
        .filter(|v| !v.is_empty())
        .map(std::string::ToString::to_string);
    let title_blob = if let Some(value) = title.as_deref() {
        let aad = format!("topic_thread.title:{thread_id}");
        Some(encrypt_bytes(db_key, value.as_bytes(), aad.as_bytes())?)
    } else {
        None
    };

    let title_updated_at_key = format!("topic_thread.title_updated_at:{thread_id}");
    let existing_title_updated_at = kv_get_i64(conn, &title_updated_at_key)?.unwrap_or(0);
    let should_update_title = title_blob.is_some() && updated_at_ms > existing_title_updated_at;

    conn.execute(
        r#"
INSERT INTO topic_threads(id, conversation_id, title, created_at_ms, updated_at_ms)
VALUES (?1, ?2, ?3, ?4, ?5)
ON CONFLICT(id) DO UPDATE SET
  conversation_id = excluded.conversation_id,
  title = CASE WHEN ?6 = 1 THEN excluded.title ELSE topic_threads.title END,
  created_at_ms = min(topic_threads.created_at_ms, excluded.created_at_ms),
  updated_at_ms = max(topic_threads.updated_at_ms, excluded.updated_at_ms)
"#,
        params![
            thread_id,
            conversation_id,
            title_blob,
            created_at_ms,
            updated_at_ms,
            if should_update_title { 1 } else { 0 }
        ],
    )?;

    if should_update_title {
        kv_set_i64(conn, &title_updated_at_key, updated_at_ms)?;
    }

    Ok(())
}

fn apply_topic_thread_message_set(
    conn: &Connection,
    db_key: &[u8; 32],
    payload: &serde_json::Value,
) -> Result<()> {
    let thread_id = payload["thread_id"]
        .as_str()
        .ok_or_else(|| anyhow!("topic_thread.message_set.v1 missing thread_id"))?
        .trim();
    if thread_id.is_empty() {
        return Err(anyhow!("topic_thread.message_set.v1 thread_id cannot be empty"));
    }

    let conversation_id = payload["conversation_id"]
        .as_str()
        .ok_or_else(|| anyhow!("topic_thread.message_set.v1 missing conversation_id"))?
        .trim();
    if conversation_id.is_empty() {
        return Err(anyhow!(
            "topic_thread.message_set.v1 conversation_id cannot be empty"
        ));
    }

    let created_at_ms = payload["created_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("topic_thread.message_set.v1 missing created_at_ms"))?;

    let deleted_at_ms = topic_thread_deleted_at_ms(conn, thread_id)?;
    if created_at_ms <= deleted_at_ms {
        return Ok(());
    }

    ensure_placeholder_conversation_row(conn, db_key, conversation_id, created_at_ms)?;
    conn.execute(
        r#"INSERT OR IGNORE INTO topic_threads(id, conversation_id, title, created_at_ms, updated_at_ms)
           VALUES (?1, ?2, NULL, ?3, ?4)"#,
        params![thread_id, conversation_id, created_at_ms, created_at_ms],
    )?;

    let raw_ids = payload["message_ids"]
        .as_array()
        .ok_or_else(|| anyhow!("topic_thread.message_set.v1 missing message_ids"))?;

    let mut seen = BTreeSet::<String>::new();
    let mut desired_ids = Vec::<String>::new();
    for value in raw_ids {
        let Some(raw_message_id) = value.as_str() else {
            continue;
        };
        let message_id = raw_message_id.trim();
        if message_id.is_empty() || seen.contains(message_id) {
            continue;
        }

        let exists: Option<i64> = conn
            .query_row(
                r#"SELECT 1
                   FROM messages
                   WHERE id = ?1
                     AND conversation_id = ?2
                     AND COALESCE(is_deleted, 0) = 0"#,
                params![message_id, conversation_id],
                |row| row.get(0),
            )
            .optional()?;
        if exists.is_some() {
            seen.insert(message_id.to_string());
            desired_ids.push(message_id.to_string());
        }
    }

    let mut stmt = conn.prepare(
        r#"SELECT m.id
           FROM topic_thread_messages ttm
           JOIN messages m ON m.id = ttm.message_id
           WHERE ttm.thread_id = ?1
             AND COALESCE(m.is_deleted, 0) = 0
           ORDER BY ttm.created_at_ms ASC, m.id ASC"#,
    )?;
    let mut rows = stmt.query(params![thread_id])?;
    let mut existing_ids = Vec::<String>::new();
    while let Some(row) = rows.next()? {
        existing_ids.push(row.get(0)?);
    }

    if existing_ids == desired_ids {
        return Ok(());
    }

    conn.execute(
        r#"DELETE FROM topic_thread_messages WHERE thread_id = ?1"#,
        params![thread_id],
    )?;
    for (index, message_id) in desired_ids.iter().enumerate() {
        conn.execute(
            r#"INSERT INTO topic_thread_messages(thread_id, message_id, created_at_ms)
               VALUES (?1, ?2, ?3)"#,
            params![thread_id, message_id, created_at_ms + index as i64],
        )?;
    }

    conn.execute(
        r#"UPDATE topic_threads
           SET updated_at_ms = CASE WHEN updated_at_ms < ?2 THEN ?2 ELSE updated_at_ms END
           WHERE id = ?1"#,
        params![thread_id, created_at_ms],
    )?;

    Ok(())
}

fn apply_topic_thread_delete(conn: &Connection, payload: &serde_json::Value) -> Result<()> {
    let thread_id = payload["thread_id"]
        .as_str()
        .ok_or_else(|| anyhow!("topic_thread.delete.v1 missing thread_id"))?
        .trim();
    if thread_id.is_empty() {
        return Err(anyhow!("topic_thread.delete.v1 thread_id cannot be empty"));
    }

    let deleted_at_ms = payload["deleted_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("topic_thread.delete.v1 missing deleted_at_ms"))?;

    let deleted_at_key = format!("topic_thread.deleted_at:{thread_id}");
    let existing_deleted_at_ms = kv_get_i64(conn, &deleted_at_key)?.unwrap_or(0);
    if deleted_at_ms < existing_deleted_at_ms {
        return Ok(());
    }

    conn.execute(
        r#"DELETE FROM topic_thread_messages WHERE thread_id = ?1"#,
        params![thread_id],
    )?;
    conn.execute(
        r#"DELETE FROM topic_threads WHERE id = ?1"#,
        params![thread_id],
    )?;

    kv_set_i64(conn, &deleted_at_key, deleted_at_ms)?;

    Ok(())
}
