fn apply_op(conn: &Connection, db_key: &[u8; 32], op: &serde_json::Value) -> Result<()> {
    let op_type = op["type"]
        .as_str()
        .ok_or_else(|| anyhow!("sync op missing type"))?;
    match op_type {
        "conversation.upsert.v1" => apply_conversation_upsert(conn, db_key, &op["payload"]),
        "message.insert.v1" => apply_message_insert(conn, db_key, op),
        "message.set.v2" => apply_message_set_v2(conn, db_key, op),
        "attachment.upsert.v1" => apply_attachment_upsert(conn, db_key, &op["payload"]),
        "attachment.delete.v1" => apply_attachment_delete(conn, db_key, op),
        "attachment.exif.upsert.v1" => apply_attachment_exif_upsert(conn, db_key, &op["payload"]),
        "attachment.metadata.upsert.v1" => {
            apply_attachment_metadata_upsert(conn, db_key, &op["payload"])
        }
        "attachment.place.upsert.v1" => apply_attachment_place_upsert(conn, db_key, &op["payload"]),
        "attachment.annotation.upsert.v1" => {
            apply_attachment_annotation_upsert(conn, db_key, &op["payload"])
        }
        "message.attachment.link.v1" => apply_message_attachment_link(conn, db_key, &op["payload"]),
        "todo.upsert.v1" => apply_todo_upsert(conn, db_key, &op["payload"]),
        "todo.delete.v1" => apply_todo_delete(conn, op),
        "todo.activity.append.v1" => apply_todo_activity_append(conn, db_key, &op["payload"]),
        "todo.activity.move.v1" => apply_todo_activity_move(conn, op),
        "todo.activity_attachment.link.v1" => {
            apply_todo_activity_attachment_link(conn, db_key, &op["payload"])
        }
        "event.upsert.v1" => apply_event_upsert(conn, db_key, &op["payload"]),
        other => Err(anyhow!("unsupported sync op type: {other}")),
    }
}

fn apply_conversation_upsert(
    conn: &Connection,
    db_key: &[u8; 32],
    payload: &serde_json::Value,
) -> Result<()> {
    let conversation_id = payload["conversation_id"]
        .as_str()
        .ok_or_else(|| anyhow!("conversation op missing conversation_id"))?;
    let title = payload["title"]
        .as_str()
        .ok_or_else(|| anyhow!("conversation op missing title"))?;
    let created_at_ms = payload["created_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("conversation op missing created_at_ms"))?;
    let updated_at_ms = payload["updated_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("conversation op missing updated_at_ms"))?;

    let title_blob = encrypt_bytes(db_key, title.as_bytes(), b"conversation.title")?;
    let title_updated_at_key = format!("conversation.title_updated_at:{conversation_id}");
    let existing_title_updated_at = kv_get_i64(conn, &title_updated_at_key)?.unwrap_or(0);
    let should_update_title = updated_at_ms > existing_title_updated_at;
    conn.execute(
        r#"
INSERT INTO conversations(id, title, created_at, updated_at)
VALUES (?1, ?2, ?3, ?4)
ON CONFLICT(id) DO UPDATE SET
  title = CASE WHEN ?5 = 1 THEN excluded.title ELSE conversations.title END,
  created_at = min(conversations.created_at, excluded.created_at),
  updated_at = max(conversations.updated_at, excluded.updated_at)
"#,
        params![
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

fn ensure_placeholder_conversation_row(
    conn: &Connection,
    db_key: &[u8; 32],
    conversation_id: &str,
    created_at_ms: i64,
) -> Result<()> {
    let title_blob = encrypt_bytes(db_key, b"", b"conversation.title")?;
    conn.execute(
        r#"INSERT OR IGNORE INTO conversations(id, title, created_at, updated_at)
           VALUES (?1, ?2, ?3, 0)"#,
        params![conversation_id, title_blob, created_at_ms],
    )?;
    Ok(())
}

fn is_foreign_key_constraint(err: &rusqlite::Error) -> bool {
    match err {
        rusqlite::Error::SqliteFailure(e, _) => {
            e.extended_code == rusqlite::ffi::SQLITE_CONSTRAINT_FOREIGNKEY
        }
        _ => false,
    }
}

fn apply_todo_upsert(
    conn: &Connection,
    db_key: &[u8; 32],
    payload: &serde_json::Value,
) -> Result<()> {
    let todo_id = payload["todo_id"]
        .as_str()
        .ok_or_else(|| anyhow!("todo op missing todo_id"))?;
    let title = payload["title"]
        .as_str()
        .ok_or_else(|| anyhow!("todo op missing title"))?;
    let status = payload["status"]
        .as_str()
        .ok_or_else(|| anyhow!("todo op missing status"))?;
    let created_at_ms = payload["created_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("todo op missing created_at_ms"))?;
    let updated_at_ms = payload["updated_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("todo op missing updated_at_ms"))?;

    let existing_delete: Option<i64> = conn
        .query_row(
            r#"SELECT deleted_at_ms FROM todo_deletions WHERE todo_id = ?1"#,
            params![todo_id],
            |row| row.get(0),
        )
        .optional()?;
    if let Some(deleted_at_ms) = existing_delete {
        // Ignore upserts that are older than (or equal to) the delete tombstone.
        if updated_at_ms <= deleted_at_ms {
            return Ok(());
        }
        // Allow resurrection when the new todo is updated after the deletion.
        conn.execute(
            r#"DELETE FROM todo_deletions WHERE todo_id = ?1"#,
            params![todo_id],
        )?;
    }

    let due_at_ms = payload["due_at_ms"].as_i64();
    let source_entry_id = payload["source_entry_id"].as_str();
    let review_stage = payload["review_stage"].as_i64();
    let next_review_at_ms = payload["next_review_at_ms"].as_i64();
    let last_review_at_ms = payload["last_review_at_ms"].as_i64();

    let title_blob = encrypt_bytes(db_key, title.as_bytes(), b"todo.title")?;
    conn.execute(
        r#"
INSERT INTO todos(
  id, title, due_at_ms, status, source_entry_id, created_at_ms, updated_at_ms,
  review_stage, next_review_at_ms, last_review_at_ms, needs_embedding
)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, 1)
ON CONFLICT(id) DO UPDATE SET
  title = excluded.title,
  due_at_ms = excluded.due_at_ms,
  status = excluded.status,
  source_entry_id = excluded.source_entry_id,
  updated_at_ms = excluded.updated_at_ms,
  review_stage = excluded.review_stage,
  next_review_at_ms = excluded.next_review_at_ms,
  last_review_at_ms = excluded.last_review_at_ms,
  needs_embedding = 1
WHERE excluded.updated_at_ms > todos.updated_at_ms
"#,
        params![
            todo_id,
            title_blob,
            due_at_ms,
            status,
            source_entry_id,
            created_at_ms,
            updated_at_ms,
            review_stage,
            next_review_at_ms,
            last_review_at_ms,
        ],
    )?;

    Ok(())
}

fn apply_todo_delete(conn: &Connection, op: &serde_json::Value) -> Result<()> {
    let device_id = op["device_id"]
        .as_str()
        .ok_or_else(|| anyhow!("todo.delete.v1 missing device_id"))?;
    let seq = op["seq"]
        .as_i64()
        .ok_or_else(|| anyhow!("todo.delete.v1 missing seq"))?;
    let payload = &op["payload"];

    let todo_id = payload["todo_id"]
        .as_str()
        .ok_or_else(|| anyhow!("todo.delete.v1 missing todo_id"))?;
    let deleted_at_ms = payload["deleted_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("todo.delete.v1 missing deleted_at_ms"))?;

    let existing_delete: Option<i64> = conn
        .query_row(
            r#"SELECT deleted_at_ms FROM todo_deletions WHERE todo_id = ?1"#,
            params![todo_id],
            |row| row.get(0),
        )
        .optional()?;

    let should_update_tombstone = match existing_delete {
        None => true,
        Some(existing_at) => deleted_at_ms > existing_at,
    };
    if should_update_tombstone {
        conn.execute(
            r#"
INSERT INTO todo_deletions(todo_id, deleted_at_ms)
VALUES (?1, ?2)
ON CONFLICT(todo_id) DO UPDATE SET
  deleted_at_ms = excluded.deleted_at_ms
"#,
            params![todo_id, deleted_at_ms],
        )?;
    }

    // Best-effort: delete messages linked to this todo.
    // - The todo's source_entry_id message (if present)
    // - Any messages linked via todo_activities.source_message_id
    let mut message_ids: BTreeSet<String> = BTreeSet::new();

    let source_entry_id: Option<Option<String>> = conn
        .query_row(
            r#"SELECT source_entry_id FROM todos WHERE id = ?1"#,
            params![todo_id],
            |row| row.get(0),
        )
        .optional()?;
    if let Some(Some(source_entry_id)) = source_entry_id {
        let trimmed = source_entry_id.trim();
        if !trimmed.is_empty() {
            message_ids.insert(trimmed.to_string());
        }
    }

    let mut stmt = conn.prepare(
        r#"SELECT DISTINCT source_message_id
           FROM todo_activities
           WHERE todo_id = ?1
             AND source_message_id IS NOT NULL
             AND source_message_id != ''"#,
    )?;
    let mut rows = stmt.query(params![todo_id])?;
    while let Some(row) = rows.next()? {
        let message_id: String = row.get(0)?;
        let trimmed = message_id.trim();
        if trimmed.is_empty() {
            continue;
        }
        message_ids.insert(trimmed.to_string());
    }

    for message_id in message_ids {
        let existing: Option<(String, i64, String, i64)> = conn
            .query_row(
                r#"SELECT conversation_id, updated_at, updated_by_device_id, updated_by_seq
                   FROM messages
                   WHERE id = ?1"#,
                params![message_id.as_str()],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
            )
            .optional()?;
        let Some((conversation_id, existing_updated_at, existing_device_id, existing_seq)) =
            existing
        else {
            continue;
        };

        if !message_version_newer(
            deleted_at_ms,
            device_id,
            seq,
            existing_updated_at,
            &existing_device_id,
            existing_seq,
        ) {
            continue;
        }

        let _ = conn.execute(
            r#"UPDATE messages
               SET updated_at = ?2,
                   updated_by_device_id = ?3,
                   updated_by_seq = ?4,
                   is_deleted = 1,
                   needs_embedding = 0
               WHERE id = ?1"#,
            params![message_id, deleted_at_ms, device_id, seq],
        )?;
        let _ = conn.execute(
            r#"UPDATE conversations
               SET updated_at = CASE WHEN updated_at < ?2 THEN ?2 ELSE updated_at END
               WHERE id = ?1"#,
            params![conversation_id, deleted_at_ms],
        )?;
    }

    // Remove todo and related data (including orphaned rows from cross-device ordering).
    let _ = conn.execute(
        r#"DELETE FROM todo_activity_attachments
           WHERE activity_id IN (SELECT id FROM todo_activities WHERE todo_id = ?1)"#,
        params![todo_id],
    )?;
    let _ = conn.execute(
        r#"DELETE FROM todo_activities WHERE todo_id = ?1"#,
        params![todo_id],
    )?;
    let _ = conn.execute(
        r#"DELETE FROM todo_activity_embeddings WHERE todo_id = ?1"#,
        params![todo_id],
    )?;
    let _ = conn.execute(
        r#"DELETE FROM todo_embeddings WHERE todo_id = ?1"#,
        params![todo_id],
    )?;

    conn.execute(r#"DELETE FROM todos WHERE id = ?1"#, params![todo_id])?;

    Ok(())
}

fn apply_todo_activity_append(
    conn: &Connection,
    db_key: &[u8; 32],
    payload: &serde_json::Value,
) -> Result<()> {
    let activity_id = payload["activity_id"]
        .as_str()
        .ok_or_else(|| anyhow!("todo activity op missing activity_id"))?;
    let todo_id = payload["todo_id"]
        .as_str()
        .ok_or_else(|| anyhow!("todo activity op missing todo_id"))?;
    let mut todo_id = todo_id.to_string();
    let todo_id_override_key = format!("todo_activity.todo_id_override:{activity_id}");
    if let Some(override_todo_id) = kv_get_string(conn, &todo_id_override_key)? {
        let trimmed = override_todo_id.trim();
        if !trimmed.is_empty() {
            todo_id = trimmed.to_string();
        }
    }
    let activity_type = payload["activity_type"]
        .as_str()
        .ok_or_else(|| anyhow!("todo activity op missing activity_type"))?;
    let created_at_ms = payload["created_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("todo activity op missing created_at_ms"))?;

    let deleted_at_ms: Option<i64> = conn
        .query_row(
            r#"SELECT deleted_at_ms FROM todo_deletions WHERE todo_id = ?1"#,
            params![todo_id.as_str()],
            |row| row.get(0),
        )
        .optional()?;
    if let Some(deleted_at_ms) = deleted_at_ms {
        // Ignore older activity ops for deleted todos.
        if created_at_ms <= deleted_at_ms {
            return Ok(());
        }
    }

    let from_status = payload["from_status"].as_str();
    let to_status = payload["to_status"].as_str();
    let source_message_id = payload["source_message_id"].as_str();
    let content = payload["content"].as_str();

    let existing: Option<i64> = conn
        .query_row(
            r#"SELECT created_at_ms FROM todo_activities WHERE id = ?1"#,
            params![activity_id],
            |row| row.get(0),
        )
        .optional()?;
    if existing.is_some() {
        return Ok(());
    }

    let content_blob = if let Some(content) = content {
        let aad = format!("todo_activity.content:{activity_id}");
        Some(encrypt_bytes(db_key, content.as_bytes(), aad.as_bytes())?)
    } else {
        None
    };

    let todo_exists: Option<i64> = conn
        .query_row(
            r#"SELECT 1 FROM todos WHERE id = ?1"#,
            params![todo_id.as_str()],
            |row| row.get(0),
        )
        .optional()?;
    if todo_exists.is_none() {
        // Avoid hard sync failures due to cross-device ordering. We'll accept an orphan activity
        // temporarily; if the todo arrives later, it will become valid.
        conn.execute_batch("PRAGMA foreign_keys = OFF;")?;
    }

    let insert_result = conn.execute(
        r#"INSERT OR IGNORE INTO todo_activities(
             id, todo_id, type, from_status, to_status, content, source_message_id, created_at_ms, needs_embedding
           )
           VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, 1)"#,
        params![
            activity_id,
            todo_id.as_str(),
            activity_type,
            from_status,
            to_status,
            content_blob,
            source_message_id,
            created_at_ms
        ],
    );

    if todo_exists.is_none() {
        let _ = conn.execute_batch("PRAGMA foreign_keys = ON;");
    }

    insert_result?;
    Ok(())
}

fn apply_todo_activity_move(conn: &Connection, op: &serde_json::Value) -> Result<()> {
    let payload = &op["payload"];
    let activity_id = payload["activity_id"]
        .as_str()
        .ok_or_else(|| anyhow!("todo activity move op missing activity_id"))?;
    let to_todo_id = payload["to_todo_id"]
        .as_str()
        .ok_or_else(|| anyhow!("todo activity move op missing to_todo_id"))?;
    let moved_at_ms = payload["moved_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("todo activity move op missing moved_at_ms"))?;

    let deleted_at_ms: Option<i64> = conn
        .query_row(
            r#"SELECT deleted_at_ms FROM todo_deletions WHERE todo_id = ?1"#,
            params![to_todo_id],
            |row| row.get(0),
        )
        .optional()?;
    if let Some(deleted_at_ms) = deleted_at_ms {
        // Ignore moves targeting deleted todos (when the move is older than the delete tombstone).
        if moved_at_ms <= deleted_at_ms {
            return Ok(());
        }
    }

    let moved_at_key = format!("todo_activity.todo_id_updated_at:{activity_id}");
    let existing_moved_at = kv_get_i64(conn, &moved_at_key)?.unwrap_or(0);
    if moved_at_ms <= existing_moved_at {
        return Ok(());
    }
    kv_set_i64(conn, &moved_at_key, moved_at_ms)?;

    // Store the latest target todo_id so append ops can respect out-of-order moves.
    let todo_id_override_key = format!("todo_activity.todo_id_override:{activity_id}");
    kv_set_string(conn, &todo_id_override_key, to_todo_id)?;

    let todo_exists: Option<i64> = conn
        .query_row(
            r#"SELECT 1 FROM todos WHERE id = ?1"#,
            params![to_todo_id],
            |row| row.get(0),
        )
        .optional()?;
    if todo_exists.is_none() {
        // Avoid hard sync failures due to cross-device ordering. We'll accept an orphan activity
        // temporarily; if the todo arrives later, it will become valid.
        conn.execute_batch("PRAGMA foreign_keys = OFF;")?;
    }

    let update_result = conn.execute(
        r#"UPDATE todo_activities
           SET todo_id = ?2,
               needs_embedding = 1
           WHERE id = ?1"#,
        params![activity_id, to_todo_id],
    );

    if todo_exists.is_none() {
        let _ = conn.execute_batch("PRAGMA foreign_keys = ON;");
    }

    update_result?;
    Ok(())
}

fn apply_todo_activity_attachment_link(
    conn: &Connection,
    _db_key: &[u8; 32],
    payload: &serde_json::Value,
) -> Result<()> {
    let activity_id = payload["activity_id"]
        .as_str()
        .ok_or_else(|| anyhow!("todo activity attachment op missing activity_id"))?;
    let attachment_sha256 = payload["attachment_sha256"]
        .as_str()
        .ok_or_else(|| anyhow!("todo activity attachment op missing attachment_sha256"))?;
    let created_at_ms = payload["created_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("todo activity attachment op missing created_at_ms"))?;

    // Best-effort: ignore old links for deleted todos (when the activity is present locally).
    let activity_todo_id: Option<String> = conn
        .query_row(
            r#"SELECT todo_id FROM todo_activities WHERE id = ?1"#,
            params![activity_id],
            |row| row.get(0),
        )
        .optional()?;
    if let Some(todo_id) = activity_todo_id {
        let deleted_at_ms: Option<i64> = conn
            .query_row(
                r#"SELECT deleted_at_ms FROM todo_deletions WHERE todo_id = ?1"#,
                params![todo_id.as_str()],
                |row| row.get(0),
            )
            .optional()?;
        if let Some(deleted_at_ms) = deleted_at_ms {
            if created_at_ms <= deleted_at_ms {
                return Ok(());
            }
        }
    }

    let existing: Option<i64> = conn
        .query_row(
            r#"SELECT 1
               FROM todo_activity_attachments
               WHERE activity_id = ?1 AND attachment_sha256 = ?2"#,
            params![activity_id, attachment_sha256],
            |row| row.get(0),
        )
        .optional()?;
    if existing.is_some() {
        return Ok(());
    }

    let activity_exists: Option<i64> = conn
        .query_row(
            r#"SELECT 1 FROM todo_activities WHERE id = ?1"#,
            params![activity_id],
            |row| row.get(0),
        )
        .optional()?;
    let attachment_exists: Option<i64> = conn
        .query_row(
            r#"SELECT 1 FROM attachments WHERE sha256 = ?1"#,
            params![attachment_sha256],
            |row| row.get(0),
        )
        .optional()?;

    if activity_exists.is_none() || attachment_exists.is_none() {
        // Avoid hard sync failures due to cross-device ordering. Accept orphan links temporarily;
        // they'll resolve once the activity/attachment arrives.
        conn.execute_batch("PRAGMA foreign_keys = OFF;")?;
    }

    let insert_result = conn.execute(
        r#"INSERT OR IGNORE INTO todo_activity_attachments(activity_id, attachment_sha256, created_at_ms)
           VALUES (?1, ?2, ?3)"#,
        params![activity_id, attachment_sha256, created_at_ms],
    );

    if activity_exists.is_none() || attachment_exists.is_none() {
        let _ = conn.execute_batch("PRAGMA foreign_keys = ON;");
    }

    insert_result?;
    Ok(())
}

fn apply_event_upsert(
    conn: &Connection,
    db_key: &[u8; 32],
    payload: &serde_json::Value,
) -> Result<()> {
    let event_id = payload["event_id"]
        .as_str()
        .ok_or_else(|| anyhow!("event op missing event_id"))?;
    let title = payload["title"]
        .as_str()
        .ok_or_else(|| anyhow!("event op missing title"))?;
    let start_at_ms = payload["start_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("event op missing start_at_ms"))?;
    let end_at_ms = payload["end_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("event op missing end_at_ms"))?;
    let tz = payload["tz"]
        .as_str()
        .ok_or_else(|| anyhow!("event op missing tz"))?;
    let created_at_ms = payload["created_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("event op missing created_at_ms"))?;
    let updated_at_ms = payload["updated_at_ms"]
        .as_i64()
        .ok_or_else(|| anyhow!("event op missing updated_at_ms"))?;

    let source_entry_id = payload["source_entry_id"].as_str();

    let title_blob = encrypt_bytes(db_key, title.as_bytes(), b"event.title")?;
    conn.execute(
        r#"
INSERT INTO events(
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
WHERE excluded.updated_at_ms > events.updated_at_ms
"#,
        params![
            event_id,
            title_blob,
            start_at_ms,
            end_at_ms,
            tz,
            source_entry_id,
            created_at_ms,
            updated_at_ms
        ],
    )?;

    Ok(())
}
