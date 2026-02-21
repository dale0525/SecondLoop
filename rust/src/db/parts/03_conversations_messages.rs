pub fn create_conversation(conn: &Connection, key: &[u8; 32], title: &str) -> Result<Conversation> {
    let id = uuid::Uuid::new_v4().to_string();
    let now = now_ms();

    let title_blob = encrypt_bytes(key, title.as_bytes(), b"conversation.title")?;
    conn.execute(
        r#"INSERT INTO conversations (id, title, created_at, updated_at) VALUES (?1, ?2, ?3, ?4)"#,
        params![id, title_blob, now, now],
    )?;

    let device_id = get_or_create_device_id(conn)?;
    let seq = next_device_seq(conn, &device_id)?;
    let op = serde_json::json!({
        "op_id": uuid::Uuid::new_v4().to_string(),
        "device_id": device_id,
        "seq": seq,
        "ts_ms": now,
        "type": "conversation.upsert.v1",
        "payload": {
            "conversation_id": id.clone(),
            "title": title,
            "created_at_ms": now,
            "updated_at_ms": now,
        }
    });
    insert_oplog(conn, key, &op)?;

    Ok(Conversation {
        id,
        title: title.to_string(),
        created_at_ms: now,
        updated_at_ms: now,
    })
}

pub fn get_or_create_loop_home_conversation(
    conn: &Connection,
    key: &[u8; 32],
) -> Result<Conversation> {
    let existing: Option<(Vec<u8>, i64, i64)> = conn
        .query_row(
            r#"SELECT title, created_at, updated_at FROM conversations WHERE id = ?1"#,
            params![LOOP_HOME_CONVERSATION_ID],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .optional()?;

    if let Some((title_blob, created_at_ms, updated_at_ms)) = existing {
        let title_bytes = decrypt_bytes(key, &title_blob, b"conversation.title")?;
        let title = String::from_utf8(title_bytes)
            .map_err(|_| anyhow!("conversation title is not valid utf-8"))?;
        return Ok(Conversation {
            id: LOOP_HOME_CONVERSATION_ID.to_string(),
            title,
            created_at_ms,
            updated_at_ms,
        });
    }

    let now = now_ms();
    let title = "Loop";

    let title_blob = encrypt_bytes(key, title.as_bytes(), b"conversation.title")?;
    conn.execute(
        r#"INSERT INTO conversations (id, title, created_at, updated_at) VALUES (?1, ?2, ?3, ?4)"#,
        params![LOOP_HOME_CONVERSATION_ID, title_blob, now, now],
    )?;

    let device_id = get_or_create_device_id(conn)?;
    let seq = next_device_seq(conn, &device_id)?;
    let op = serde_json::json!({
        "op_id": uuid::Uuid::new_v4().to_string(),
        "device_id": device_id,
        "seq": seq,
        "ts_ms": now,
        "type": "conversation.upsert.v1",
        "payload": {
            "conversation_id": LOOP_HOME_CONVERSATION_ID,
            "title": title,
            "created_at_ms": now,
            "updated_at_ms": now,
        }
    });
    insert_oplog(conn, key, &op)?;

    Ok(Conversation {
        id: LOOP_HOME_CONVERSATION_ID.to_string(),
        title: title.to_string(),
        created_at_ms: now,
        updated_at_ms: now,
    })
}

pub fn list_conversations(conn: &Connection, key: &[u8; 32]) -> Result<Vec<Conversation>> {
    let mut stmt = conn.prepare(
        r#"SELECT id, title, created_at, updated_at FROM conversations ORDER BY updated_at DESC"#,
    )?;

    let mut rows = stmt.query([])?;
    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        let id: String = row.get(0)?;
        let title_blob: Vec<u8> = row.get(1)?;
        let created_at_ms: i64 = row.get(2)?;
        let updated_at_ms: i64 = row.get(3)?;

        let title_bytes = decrypt_bytes(key, &title_blob, b"conversation.title")?;
        let title = String::from_utf8(title_bytes)
            .map_err(|_| anyhow!("conversation title is not valid utf-8"))?;

        result.push(Conversation {
            id,
            title,
            created_at_ms,
            updated_at_ms,
        });
    }

    Ok(result)
}

pub fn insert_message(
    conn: &Connection,
    key: &[u8; 32],
    conversation_id: &str,
    role: &str,
    content: &str,
) -> Result<Message> {
    insert_message_with_is_memory(
        conn,
        key,
        conversation_id,
        role,
        content,
        role != "assistant",
    )
}

pub fn insert_message_non_memory(
    conn: &Connection,
    key: &[u8; 32],
    conversation_id: &str,
    role: &str,
    content: &str,
) -> Result<Message> {
    insert_message_with_is_memory(conn, key, conversation_id, role, content, false)
}

fn insert_message_with_is_memory(
    conn: &Connection,
    key: &[u8; 32],
    conversation_id: &str,
    role: &str,
    content: &str,
    is_memory: bool,
) -> Result<Message> {
    let id = uuid::Uuid::new_v4().to_string();
    let now = now_ms();

    let device_id = get_or_create_device_id(conn)?;
    let seq = next_device_seq(conn, &device_id)?;

    let content_blob = encrypt_bytes(key, content.as_bytes(), b"message.content")?;
    conn.execute(
        r#"INSERT INTO messages
           (id, conversation_id, role, content, created_at, updated_at, updated_by_device_id, updated_by_seq, is_deleted, needs_embedding, is_memory)
           VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, 0, ?9, ?10)"#,
        params![
            id,
            conversation_id,
            role,
            content_blob,
            now,
            now,
            device_id,
            seq,
            if is_memory { 1 } else { 0 },
            if is_memory { 1 } else { 0 }
        ],
    )?;

    conn.execute(
        r#"UPDATE conversations SET updated_at = ?2 WHERE id = ?1"#,
        params![conversation_id, now],
    )?;

    let op = serde_json::json!({
        "op_id": uuid::Uuid::new_v4().to_string(),
        "device_id": device_id,
        "seq": seq,
        "ts_ms": now,
        "type": "message.insert.v1",
        "payload": {
            "message_id": id.clone(),
            "conversation_id": conversation_id,
            "role": role,
            "content": content,
            "created_at_ms": now,
            "is_memory": is_memory,
        }
    });
    insert_oplog(conn, key, &op)?;

    if role == "user" {
        run_message_tag_autofill_for_message(conn, key, &id, "message_insert", now)?;
    }

    Ok(Message {
        id,
        conversation_id: conversation_id.to_string(),
        role: role.to_string(),
        content: content.to_string(),
        created_at_ms: now,
        is_memory,
    })
}

pub fn edit_message(
    conn: &Connection,
    key: &[u8; 32],
    message_id: &str,
    content: &str,
) -> Result<()> {
    let (existing, is_memory) = get_message_by_id_with_is_memory(conn, key, message_id)?;
    let conversation_id = existing.conversation_id.clone();
    let role = existing.role.clone();
    let created_at_ms = existing.created_at_ms;
    let now = now_ms();

    let device_id = get_or_create_device_id(conn)?;
    let seq = next_device_seq(conn, &device_id)?;

    let op = serde_json::json!({
        "op_id": uuid::Uuid::new_v4().to_string(),
        "device_id": device_id,
        "seq": seq,
        "ts_ms": now,
        "type": "message.set.v2",
        "payload": {
            "message_id": message_id,
            "conversation_id": conversation_id.as_str(),
            "role": role.as_str(),
            "content": content,
            "created_at_ms": created_at_ms,
            "updated_at_ms": now,
            "is_deleted": false,
            "is_memory": is_memory,
        }
    });
    insert_oplog(conn, key, &op)?;

    let content_blob = encrypt_bytes(key, content.as_bytes(), b"message.content")?;
    let updated = conn.execute(
        r#"UPDATE messages
           SET content = ?2,
               updated_at = ?3,
               updated_by_device_id = ?4,
               updated_by_seq = ?5,
               is_deleted = 0,
               needs_embedding = CASE WHEN COALESCE(is_memory, 1) = 1 THEN 1 ELSE 0 END
           WHERE id = ?1"#,
        params![message_id, content_blob, now, device_id, seq],
    )?;
    if updated == 0 {
        return Err(anyhow!("message not found: {message_id}"));
    }

    conn.execute(
        r#"UPDATE conversations
           SET updated_at = CASE WHEN updated_at < ?2 THEN ?2 ELSE updated_at END
           WHERE id = ?1"#,
        params![conversation_id, now],
    )?;

    Ok(())
}

pub fn set_message_deleted(
    conn: &Connection,
    key: &[u8; 32],
    message_id: &str,
    is_deleted: bool,
) -> Result<()> {
    let (existing, is_memory) = get_message_by_id_with_is_memory(conn, key, message_id)?;
    let conversation_id = existing.conversation_id.clone();
    let role = existing.role.clone();
    let content = existing.content.clone();
    let created_at_ms = existing.created_at_ms;
    let now = now_ms();

    let device_id = get_or_create_device_id(conn)?;
    let seq = next_device_seq(conn, &device_id)?;

    let op = serde_json::json!({
        "op_id": uuid::Uuid::new_v4().to_string(),
        "device_id": device_id,
        "seq": seq,
        "ts_ms": now,
        "type": "message.set.v2",
        "payload": {
            "message_id": message_id,
            "conversation_id": conversation_id.as_str(),
            "role": role.as_str(),
            "content": content.as_str(),
            "created_at_ms": created_at_ms,
            "updated_at_ms": now,
            "is_deleted": is_deleted,
            "is_memory": is_memory,
        }
    });
    insert_oplog(conn, key, &op)?;

    let updated = conn.execute(
        r#"UPDATE messages
           SET updated_at = ?2,
               updated_by_device_id = ?3,
               updated_by_seq = ?4,
               is_deleted = ?5,
               needs_embedding = CASE WHEN ?5 = 0 AND COALESCE(is_memory, 1) = 1 THEN 1 ELSE 0 END
           WHERE id = ?1"#,
        params![
            message_id,
            now,
            device_id,
            seq,
            if is_deleted { 1 } else { 0 }
        ],
    )?;
    if updated == 0 {
        return Err(anyhow!("message not found: {message_id}"));
    }

    conn.execute(
        r#"UPDATE conversations
           SET updated_at = CASE WHEN updated_at < ?2 THEN ?2 ELSE updated_at END
           WHERE id = ?1"#,
        params![conversation_id, now],
    )?;

    Ok(())
}

pub fn append_message_content(
    conn: &Connection,
    key: &[u8; 32],
    message_id: &str,
    text_delta: &str,
) -> Result<()> {
    if text_delta.is_empty() {
        return Ok(());
    }

    let content_blob: Vec<u8> = conn.query_row(
        r#"SELECT content FROM messages WHERE id = ?1"#,
        params![message_id],
        |row| row.get(0),
    )?;
    let content_bytes = decrypt_bytes(key, &content_blob, b"message.content")?;
    let mut content = String::from_utf8(content_bytes)
        .map_err(|_| anyhow!("message content is not valid utf-8"))?;
    content.push_str(text_delta);

    let new_blob = encrypt_bytes(key, content.as_bytes(), b"message.content")?;
    conn.execute(
        r#"UPDATE messages SET content = ?2 WHERE id = ?1"#,
        params![message_id, new_blob],
    )?;

    Ok(())
}

