fn encrypt_topic_thread_title(
    key: &[u8; 32],
    thread_id: &str,
    title: Option<&str>,
) -> Result<Option<Vec<u8>>> {
    let Some(raw) = title else {
        return Ok(None);
    };

    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Ok(None);
    }

    let aad = format!("topic_thread.title:{thread_id}");
    let blob = encrypt_bytes(key, trimmed.as_bytes(), aad.as_bytes())?;
    Ok(Some(blob))
}

fn decrypt_topic_thread_title(
    key: &[u8; 32],
    thread_id: &str,
    title_blob: Option<Vec<u8>>,
) -> Result<Option<String>> {
    let Some(blob) = title_blob else {
        return Ok(None);
    };
    let aad = format!("topic_thread.title:{thread_id}");
    let bytes = decrypt_bytes(key, &blob, aad.as_bytes())?;
    let title = String::from_utf8(bytes)
        .map_err(|_| anyhow!("topic thread title is not valid utf-8"))?;
    let trimmed = title.trim();
    if trimmed.is_empty() {
        return Ok(None);
    }
    Ok(Some(trimmed.to_string()))
}

type TopicThreadRow = (String, String, Option<Vec<u8>>, i64, i64);

fn normalize_topic_thread_title(title: Option<&str>) -> Option<String> {
    title
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(std::string::ToString::to_string)
}

fn insert_topic_thread_upsert_op(
    conn: &Connection,
    key: &[u8; 32],
    thread_id: &str,
    conversation_id: &str,
    title: Option<&str>,
    created_at_ms: i64,
    updated_at_ms: i64,
) -> Result<()> {
    let title_for_op = normalize_topic_thread_title(title);

    let device_id = get_or_create_device_id(conn)?;
    let seq = next_device_seq(conn, &device_id)?;
    let op = serde_json::json!({
        "op_id": uuid::Uuid::new_v4().to_string(),
        "device_id": device_id,
        "seq": seq,
        "ts_ms": updated_at_ms,
        "type": "topic_thread.upsert.v1",
        "payload": {
            "thread_id": thread_id,
            "conversation_id": conversation_id,
            "title": title_for_op,
            "created_at_ms": created_at_ms,
            "updated_at_ms": updated_at_ms,
        }
    });
    insert_oplog(conn, key, &op)
}

fn read_topic_thread_by_id(
    conn: &Connection,
    key: &[u8; 32],
    thread_id: &str,
) -> Result<Option<TopicThread>> {
    let row: Option<TopicThreadRow> = conn
        .query_row(
            r#"SELECT id, conversation_id, title, created_at_ms, updated_at_ms
               FROM topic_threads
               WHERE id = ?1"#,
            params![thread_id],
            |row| {
                Ok((
                    row.get(0)?,
                    row.get(1)?,
                    row.get(2)?,
                    row.get(3)?,
                    row.get(4)?,
                ))
            },
        )
        .optional()?;

    let Some((id, conversation_id, title_blob, created_at_ms, updated_at_ms)) = row else {
        return Ok(None);
    };

    let title = decrypt_topic_thread_title(key, &id, title_blob)?;
    Ok(Some(TopicThread {
        id,
        conversation_id,
        title,
        created_at_ms,
        updated_at_ms,
    }))
}

pub fn create_topic_thread(
    conn: &Connection,
    key: &[u8; 32],
    conversation_id: &str,
    title: Option<&str>,
) -> Result<TopicThread> {
    let exists: Option<i64> = conn
        .query_row(
            r#"SELECT 1 FROM conversations WHERE id = ?1"#,
            params![conversation_id],
            |row| row.get(0),
        )
        .optional()?;
    if exists.is_none() {
        return Err(anyhow!("conversation not found: {conversation_id}"));
    }

    let thread_id = uuid::Uuid::new_v4().to_string();
    let now = now_ms();
    let normalized_title = normalize_topic_thread_title(title);
    let title_blob = encrypt_topic_thread_title(key, &thread_id, normalized_title.as_deref())?;
    conn.execute(
        r#"INSERT INTO topic_threads(id, conversation_id, title, created_at_ms, updated_at_ms)
           VALUES (?1, ?2, ?3, ?4, ?5)"#,
        params![thread_id, conversation_id, title_blob, now, now],
    )?;

    insert_topic_thread_upsert_op(
        conn,
        key,
        &thread_id,
        conversation_id,
        normalized_title.as_deref(),
        now,
        now,
    )?;

    read_topic_thread_by_id(conn, key, &thread_id)?
        .ok_or_else(|| anyhow!("failed to read created topic thread"))
}


pub fn update_topic_thread_title(
    conn: &Connection,
    key: &[u8; 32],
    thread_id: &str,
    title: Option<&str>,
) -> Result<TopicThread> {
    let thread = read_topic_thread_by_id(conn, key, thread_id)?
        .ok_or_else(|| anyhow!("topic thread not found: {thread_id}"))?;

    let normalized_title = normalize_topic_thread_title(title);
    if thread.title.as_deref() == normalized_title.as_deref() {
        return Ok(thread);
    }

    let now = now_ms();
    let title_blob = encrypt_topic_thread_title(key, thread_id, normalized_title.as_deref())?;
    conn.execute(
        r#"UPDATE topic_threads
           SET title = ?2,
               updated_at_ms = ?3
           WHERE id = ?1"#,
        params![thread_id, title_blob, now],
    )?;

    insert_topic_thread_upsert_op(
        conn,
        key,
        thread_id,
        &thread.conversation_id,
        normalized_title.as_deref(),
        thread.created_at_ms,
        now,
    )?;

    read_topic_thread_by_id(conn, key, thread_id)?
        .ok_or_else(|| anyhow!("failed to read updated topic thread"))
}

pub fn delete_topic_thread(conn: &Connection, key: &[u8; 32], thread_id: &str) -> Result<bool> {
    let thread = read_topic_thread_by_id(conn, key, thread_id)?;
    let Some(thread) = thread else {
        return Ok(false);
    };

    conn.execute_batch("BEGIN IMMEDIATE;")?;
    let result: Result<()> = (|| {
        conn.execute(
            r#"DELETE FROM topic_threads WHERE id = ?1"#,
            params![thread_id],
        )?;

        let now = now_ms();
        let device_id = get_or_create_device_id(conn)?;
        let seq = next_device_seq(conn, &device_id)?;
        let op = serde_json::json!({
            "op_id": uuid::Uuid::new_v4().to_string(),
            "device_id": device_id,
            "seq": seq,
            "ts_ms": now,
            "type": "topic_thread.delete.v1",
            "payload": {
                "thread_id": thread_id,
                "conversation_id": thread.conversation_id,
                "deleted_at_ms": now,
            }
        });
        insert_oplog(conn, key, &op)?;

        Ok(())
    })();

    match result {
        Ok(()) => {
            conn.execute_batch("COMMIT;")?;
            Ok(true)
        }
        Err(err) => {
            let _ = conn.execute_batch("ROLLBACK;");
            Err(err)
        }
    }
}

pub fn list_topic_threads(
    conn: &Connection,
    key: &[u8; 32],
    conversation_id: &str,
) -> Result<Vec<TopicThread>> {
    let mut stmt = conn.prepare(
        r#"SELECT id, conversation_id, title, created_at_ms, updated_at_ms
           FROM topic_threads
           WHERE conversation_id = ?1
           ORDER BY updated_at_ms DESC, id ASC"#,
    )?;

    let mut rows = stmt.query(params![conversation_id])?;
    let mut out = Vec::new();
    while let Some(row) = rows.next()? {
        let id: String = row.get(0)?;
        let conversation_id: String = row.get(1)?;
        let title_blob: Option<Vec<u8>> = row.get(2)?;
        let created_at_ms: i64 = row.get(3)?;
        let updated_at_ms: i64 = row.get(4)?;
        let title = decrypt_topic_thread_title(key, &id, title_blob)?;

        out.push(TopicThread {
            id,
            conversation_id,
            title,
            created_at_ms,
            updated_at_ms,
        });
    }

    Ok(out)
}

pub fn list_topic_thread_message_ids(conn: &Connection, thread_id: &str) -> Result<Vec<String>> {
    let mut stmt = conn.prepare(
        r#"SELECT m.id
           FROM topic_thread_messages ttm
           JOIN messages m ON m.id = ttm.message_id
           WHERE ttm.thread_id = ?1
             AND COALESCE(m.is_deleted, 0) = 0
           ORDER BY ttm.created_at_ms ASC, m.id ASC"#,
    )?;

    let mut rows = stmt.query(params![thread_id])?;
    let mut out = Vec::new();
    while let Some(row) = rows.next()? {
        out.push(row.get(0)?);
    }
    Ok(out)
}

pub fn set_topic_thread_message_ids(
    conn: &Connection,
    key: &[u8; 32],
    thread_id: &str,
    message_ids: &[String],
) -> Result<Vec<String>> {
    let thread = read_topic_thread_by_id(conn, key, thread_id)?
        .ok_or_else(|| anyhow!("topic thread not found: {thread_id}"))?;

    let mut seen = BTreeSet::<String>::new();
    let mut desired_ids = Vec::<String>::new();
    for raw in message_ids {
        let trimmed = raw.trim();
        if trimmed.is_empty() || seen.contains(trimmed) {
            continue;
        }

        let exists: Option<i64> = conn
            .query_row(
                r#"SELECT 1
                   FROM messages
                   WHERE id = ?1
                     AND conversation_id = ?2
                     AND COALESCE(is_deleted, 0) = 0"#,
                params![trimmed, thread.conversation_id.as_str()],
                |row| row.get(0),
            )
            .optional()?;
        if exists.is_some() {
            seen.insert(trimmed.to_string());
            desired_ids.push(trimmed.to_string());
        }
    }
    let existing_ids = list_topic_thread_message_ids(conn, thread_id)?;
    if existing_ids == desired_ids {
        return Ok(existing_ids);
    }

    conn.execute_batch("BEGIN IMMEDIATE;")?;
    let result: Result<()> = (|| {
        conn.execute(
            r#"DELETE FROM topic_thread_messages WHERE thread_id = ?1"#,
            params![thread_id],
        )?;

        let now = now_ms();
        for (index, message_id) in desired_ids.iter().enumerate() {
            conn.execute(
                r#"INSERT INTO topic_thread_messages(thread_id, message_id, created_at_ms)
                   VALUES (?1, ?2, ?3)"#,
                params![thread_id, message_id, now + index as i64],
            )?;
        }

        conn.execute(
            r#"UPDATE topic_threads
               SET updated_at_ms = ?2
               WHERE id = ?1"#,
            params![thread_id, now],
        )?;

        let device_id = get_or_create_device_id(conn)?;
        let seq = next_device_seq(conn, &device_id)?;
        let op = serde_json::json!({
            "op_id": uuid::Uuid::new_v4().to_string(),
            "device_id": device_id,
            "seq": seq,
            "ts_ms": now,
            "type": "topic_thread.message_set.v1",
            "payload": {
                "thread_id": thread_id,
                "conversation_id": thread.conversation_id,
                "message_ids": desired_ids,
                "created_at_ms": now,
            }
        });
        insert_oplog(conn, key, &op)?;

        Ok(())
    })();

    match result {
        Ok(()) => {
            conn.execute_batch("COMMIT;")?;
        }
        Err(err) => {
            let _ = conn.execute_batch("ROLLBACK;");
            return Err(err);
        }
    }

    list_topic_thread_message_ids(conn, thread_id)
}
