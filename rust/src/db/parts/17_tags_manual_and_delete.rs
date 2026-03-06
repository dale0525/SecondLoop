fn parse_manual_tag_token(token: &str) -> Option<String> {
    let raw_name = token.strip_prefix('#')?;
    if raw_name.is_empty() || raw_name.starts_with('#') {
        return None;
    }

    let normalized = normalize_tag_name(raw_name);
    if normalized.is_empty() {
        return None;
    }

    Some(normalized)
}

fn parse_manual_message_tag_names(content: &str) -> Vec<String> {
    let mut out = Vec::<String>::new();
    let mut seen = std::collections::HashSet::<String>::new();

    for line in content.lines() {
        let trimmed = line.trim_start();
        if !trimmed.starts_with('#') {
            continue;
        }

        for token in trimmed.split_whitespace() {
            let Some(normalized) = parse_manual_tag_token(token) else {
                continue;
            };
            if !seen.insert(normalized.clone()) {
                continue;
            }
            out.push(normalized);
        }
    }

    out
}

fn build_manual_tag_cleanup_content(content: &str, deleted_tag_name: &str) -> String {
    let mut lines = Vec::<String>::new();

    for line in content.lines() {
        let trimmed = line.trim_start();
        if !trimmed.starts_with('#') {
            lines.push(line.to_string());
            continue;
        }

        let leading_len = line.len().saturating_sub(trimmed.len());
        let leading = &line[..leading_len];
        let mut kept_tokens = Vec::<&str>::new();
        let mut removed_any = false;

for token in trimmed.split_whitespace() {
    let Some(normalized_tag_name) = parse_manual_tag_token(token) else {
        kept_tokens.push(token);
        continue;
    };
    if normalized_tag_name == deleted_tag_name {
        removed_any = true;
        continue;
    }
    kept_tokens.push(token);
}

        if !removed_any {
            lines.push(line.to_string());
            continue;
        }

        if kept_tokens.is_empty() {
            continue;
        }

        lines.push(format!("{leading}{}", kept_tokens.join(" ")));
    }

    let mut out = lines.join("\n");
    if content.ends_with('\n') && !out.ends_with('\n') {
        out.push('\n');
    }
    out
}

pub fn list_manual_message_tag_names(
    conn: &Connection,
    key: &[u8; 32],
    message_id: &str,
) -> Result<Vec<String>> {
    let message = get_message_by_id(conn, key, message_id)?;
    Ok(parse_manual_message_tag_names(&message.content))
}

pub fn list_available_tags_for_semantic_parse(
    conn: &Connection,
    db_key: &[u8; 32],
    limit: usize,
) -> Result<Vec<String>> {
    let clamped_limit = limit.clamp(1, 200);
    let tags = list_tags(conn, db_key)?;

    let mut out = Vec::<String>::new();
    let mut seen = std::collections::HashSet::<String>::new();

    for tag in tags {
        let candidate = tag
            .system_key
            .as_deref()
            .filter(|value| !value.trim().is_empty())
            .unwrap_or(tag.name.as_str());
        let normalized = normalize_tag_name(candidate);
        if normalized.is_empty() || !seen.insert(normalized.clone()) {
            continue;
        }

        out.push(normalized);
        if out.len() >= clamped_limit {
            break;
        }
    }

    Ok(out)
}

pub fn sync_manual_message_tags_for_content_change(
    conn: &Connection,
    db_key: &[u8; 32],
    message_id: &str,
    previous_content: Option<&str>,
    next_content: &str,
) -> Result<Vec<Tag>> {
    let previous_manual = previous_content
        .map(parse_manual_message_tag_names)
        .unwrap_or_default();
    let next_manual = parse_manual_message_tag_names(next_content);

    if previous_manual == next_manual {
        return list_message_tags(conn, db_key, message_id);
    }

    let previous_manual_set = previous_manual.into_iter().collect::<std::collections::HashSet<_>>();
    let next_manual_set = next_manual
        .iter()
        .cloned()
        .collect::<std::collections::HashSet<_>>();

    let existing_tags = list_message_tags(conn, db_key, message_id)?;
    let mut next_tag_ids = existing_tags
        .iter()
        .filter(|tag| {
            let normalized = normalize_tag_name(&tag.name);
            !previous_manual_set.contains(&normalized) || next_manual_set.contains(&normalized)
        })
        .map(|tag| tag.id.clone())
        .collect::<std::collections::BTreeSet<_>>();

    for manual_tag_name in next_manual {
        let tag = upsert_tag(conn, db_key, &manual_tag_name)?;
        next_tag_ids.insert(tag.id);
    }

    let next_tag_ids = next_tag_ids.into_iter().collect::<Vec<_>>();
    set_message_tags(conn, db_key, message_id, &next_tag_ids)
}

pub fn delete_tag(conn: &Connection, db_key: &[u8; 32], tag_id: &str) -> Result<()> {
    ensure_system_tags(conn, db_key)?;

    let tag_id = tag_id.trim();
    if tag_id.is_empty() {
        return Err(anyhow!("tag_id cannot be empty"));
    }

    let tag = read_tag_by_id(conn, db_key, tag_id)?.ok_or_else(|| anyhow!("tag not found: {tag_id}"))?;
    if tag.is_system {
        return Err(anyhow!("system tags cannot be deleted"));
    }

    let normalized_deleted_tag_name = normalize_tag_name(&tag.name);
    let mut stmt = conn.prepare(
        r#"SELECT DISTINCT message_id
           FROM message_tags
           WHERE tag_id = ?1
           ORDER BY message_id ASC"#,
    )?;
    let mut rows = stmt.query(params![tag_id])?;
    let mut message_ids = Vec::<String>::new();
    while let Some(row) = rows.next()? {
        message_ids.push(row.get(0)?);
    }

    for message_id in message_ids {
        let message = get_message_by_id(conn, db_key, &message_id)?;
        let cleaned_content = build_manual_tag_cleanup_content(&message.content, &normalized_deleted_tag_name);

        if cleaned_content != message.content {
            edit_message_internal(conn, db_key, &message_id, &cleaned_content, false)?;
            continue;
        }

        let remaining_tag_ids = list_message_tags(conn, db_key, &message_id)?
            .into_iter()
            .filter(|current| current.id != tag_id)
            .map(|current| current.id)
            .collect::<Vec<_>>();
        set_message_tags(conn, db_key, &message_id, &remaining_tag_ids)?;
    }

    conn.execute(r#"DELETE FROM tags WHERE id = ?1"#, params![tag_id])?;

    let deleted_at_ms = now_ms();
    let deleted_at_key = format!("tag.deleted_at:{tag_id}");
    kv_set_i64(conn, &deleted_at_key, deleted_at_ms)?;

    let device_id = get_or_create_device_id(conn)?;
    let seq = next_device_seq(conn, &device_id)?;
    let op = serde_json::json!({
        "op_id": uuid::Uuid::new_v4().to_string(),
        "device_id": device_id,
        "seq": seq,
        "ts_ms": deleted_at_ms,
        "type": "tag.delete.v1",
        "payload": {
            "tag_id": tag_id,
            "deleted_at_ms": deleted_at_ms,
        }
    });
    insert_oplog(conn, db_key, &op)?;

    Ok(())
}
