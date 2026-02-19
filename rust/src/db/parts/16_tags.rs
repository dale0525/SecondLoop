const SYSTEM_TAG_KEYS: [&str; 10] = [
    "work",
    "personal",
    "family",
    "health",
    "finance",
    "study",
    "travel",
    "social",
    "home",
    "hobby",
];

const MAX_SUGGESTED_TAGS_PER_MESSAGE: usize = 3;

fn system_tag_id_for_key(system_key: &str) -> String {
    format!("system.tag.{system_key}")
}

fn normalize_tag_name(raw: &str) -> String {
    raw.split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .to_lowercase()
}

fn map_to_system_key(raw: &str) -> Option<&'static str> {
    let normalized = normalize_tag_name(raw);
    if normalized.is_empty() {
        return None;
    }

    fn contains_any(haystack: &str, needles: &[&str]) -> bool {
        needles.iter().any(|needle| haystack == *needle || haystack.contains(needle))
    }

    let compact = normalized.replace(['-', '_'], " ");

    if contains_any(
        &compact,
        &[
            "work", "job", "office", "career", "工作", "职场", "項目", "项目", "会议",
            "會議", "公司", "周报", "週報", "日报", "匯報", "汇报",
        ],
    ) {
        return Some("work");
    }

    if contains_any(
        &compact,
        &["personal", "life", "个人", "個人", "生活", "私事"],
    ) {
        return Some("personal");
    }

    if contains_any(
        &compact,
        &["family", "家庭", "家人", "父母", "孩子", "育儿", "育兒"],
    ) {
        return Some("family");
    }

    if contains_any(
        &compact,
        &[
            "health", "fitness", "wellness", "medical", "健康", "运动", "運動", "锻炼",
            "鍛鍊", "医疗", "醫療", "睡眠", "就医", "就醫",
        ],
    ) {
        return Some("health");
    }

    if contains_any(
        &compact,
        &[
            "finance", "money", "budget", "expense", "cost", "investment", "财务", "財務",
            "理财", "理財", "记账", "記賬", "投资", "投資", "开销", "開銷", "报销",
            "報銷",
        ],
    ) {
        return Some("finance");
    }

    if contains_any(
        &compact,
        &[
            "study", "learning", "course", "exam", "research", "学习", "學習", "课程",
            "課程", "考试", "考試", "读书", "讀書", "研究",
        ],
    ) {
        return Some("study");
    }

    if contains_any(
        &compact,
        &[
            "travel", "trip", "vacation", "journey", "flight", "hotel", "旅行", "旅游",
            "旅遊", "出行", "差旅", "行程", "机票", "機票", "酒店",
        ],
    ) {
        return Some("travel");
    }

    if contains_any(
        &compact,
        &[
            "social", "friend", "network", "community", "社交", "朋友", "聚会", "聚會", "人脉",
            "人脈",
        ],
    ) {
        return Some("social");
    }

    if contains_any(
        &compact,
        &["home", "house", "household", "家务", "家務", "家居", "居家", "房屋", "维修", "維修", "搬家"],
    ) {
        return Some("home");
    }

    if contains_any(
        &compact,
        &[
            "hobby", "interest", "fun", "entertainment", "娱乐", "娛樂", "兴趣", "興趣",
            "爱好", "愛好", "游戏", "遊戲", "音乐", "音樂", "电影", "電影",
        ],
    ) {
        return Some("hobby");
    }

    None
}

type TagRow = (String, Vec<u8>, Option<String>, i64, Option<String>, i64, i64);

fn decrypt_tag_name(db_key: &[u8; 32], tag_id: &str, name_blob: &[u8]) -> Result<String> {
    let aad = format!("tag.name:{tag_id}");
    let bytes = decrypt_bytes(db_key, name_blob, aad.as_bytes())?;
    String::from_utf8(bytes).map_err(|_| anyhow!("tag name is not valid utf-8"))
}

fn read_tag_by_id(conn: &Connection, db_key: &[u8; 32], tag_id: &str) -> Result<Option<Tag>> {
    let row: Option<TagRow> = conn
        .query_row(
            r#"SELECT id, name, system_key, COALESCE(is_system, 0), color, created_at_ms, updated_at_ms
               FROM tags
               WHERE id = ?1"#,
            params![tag_id],
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
        .optional()?;

    let Some((id, name_blob, system_key, is_system_i64, color, created_at_ms, updated_at_ms)) = row
    else {
        return Ok(None);
    };

    let name = decrypt_tag_name(db_key, &id, &name_blob)?;

    Ok(Some(Tag {
        id,
        name,
        system_key,
        is_system: is_system_i64 != 0,
        color,
        created_at_ms,
        updated_at_ms,
    }))
}

fn read_tag_by_system_key(
    conn: &Connection,
    db_key: &[u8; 32],
    system_key: &str,
) -> Result<Option<Tag>> {
    let row: Option<TagRow> = conn
        .query_row(
            r#"SELECT id, name, system_key, COALESCE(is_system, 0), color, created_at_ms, updated_at_ms
               FROM tags
               WHERE system_key = ?1
               LIMIT 1"#,
            params![system_key],
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
        .optional()?;

    let Some((id, name_blob, system_key, is_system_i64, color, created_at_ms, updated_at_ms)) = row
    else {
        return Ok(None);
    };

    let name = decrypt_tag_name(db_key, &id, &name_blob)?;

    Ok(Some(Tag {
        id,
        name,
        system_key,
        is_system: is_system_i64 != 0,
        color,
        created_at_ms,
        updated_at_ms,
    }))
}

fn find_existing_custom_tag_by_name(
    conn: &Connection,
    db_key: &[u8; 32],
    name: &str,
) -> Result<Option<Tag>> {
    let normalized_target = normalize_tag_name(name);
    if normalized_target.is_empty() {
        return Ok(None);
    }

    let mut stmt = conn.prepare(
        r#"SELECT id, name, system_key, COALESCE(is_system, 0), color, created_at_ms, updated_at_ms
           FROM tags
           WHERE COALESCE(is_system, 0) = 0
           ORDER BY updated_at_ms DESC, id DESC"#,
    )?;
    let mut rows = stmt.query([])?;
    while let Some(row) = rows.next()? {
        let id: String = row.get(0)?;
        let name_blob: Vec<u8> = row.get(1)?;
        let system_key: Option<String> = row.get(2)?;
        let is_system_i64: i64 = row.get(3)?;
        let color: Option<String> = row.get(4)?;
        let created_at_ms: i64 = row.get(5)?;
        let updated_at_ms: i64 = row.get(6)?;

        let current_name = decrypt_tag_name(db_key, &id, &name_blob)?;
        if normalize_tag_name(&current_name) != normalized_target {
            continue;
        }

        return Ok(Some(Tag {
            id,
            name: current_name,
            system_key,
            is_system: is_system_i64 != 0,
            color,
            created_at_ms,
            updated_at_ms,
        }));
    }

    Ok(None)
}

fn ensure_system_tags(conn: &Connection, db_key: &[u8; 32]) -> Result<()> {
    let now = now_ms();

    for system_key in SYSTEM_TAG_KEYS {
        let tag_id = system_tag_id_for_key(system_key);
        let aad = format!("tag.name:{tag_id}");
        let name_blob = encrypt_bytes(db_key, system_key.as_bytes(), aad.as_bytes())?;
        conn.execute(
            r#"INSERT OR IGNORE INTO tags(
                   id, name, system_key, is_system, color, created_at_ms, updated_at_ms
               )
               VALUES (?1, ?2, ?3, 1, NULL, ?4, ?5)"#,
            params![tag_id, name_blob, system_key, now, now],
        )?;
    }

    Ok(())
}

pub fn list_tags(conn: &Connection, db_key: &[u8; 32]) -> Result<Vec<Tag>> {
    ensure_system_tags(conn, db_key)?;

    let mut stmt = conn.prepare(
        r#"SELECT id, name, system_key, COALESCE(is_system, 0), color, created_at_ms, updated_at_ms
           FROM tags
           ORDER BY COALESCE(is_system, 0) DESC, updated_at_ms DESC, id ASC"#,
    )?;
    let mut rows = stmt.query([])?;

    let mut out = Vec::new();
    while let Some(row) = rows.next()? {
        let id: String = row.get(0)?;
        let name_blob: Vec<u8> = row.get(1)?;
        let system_key: Option<String> = row.get(2)?;
        let is_system_i64: i64 = row.get(3)?;
        let color: Option<String> = row.get(4)?;
        let created_at_ms: i64 = row.get(5)?;
        let updated_at_ms: i64 = row.get(6)?;

        let name = decrypt_tag_name(db_key, &id, &name_blob)?;
        out.push(Tag {
            id,
            name,
            system_key,
            is_system: is_system_i64 != 0,
            color,
            created_at_ms,
            updated_at_ms,
        });
    }

    Ok(out)
}

pub fn list_tag_merge_suggestions(
    conn: &Connection,
    db_key: &[u8; 32],
    limit: usize,
) -> Result<Vec<TagMergeSuggestion>> {
    ensure_system_tags(conn, db_key)?;

    if limit == 0 {
        return Ok(Vec::new());
    }

    let tags = list_tags(conn, db_key)?;
    if tags.len() < 2 {
        return Ok(Vec::new());
    }

    let usage_counts = load_tag_usage_counts(conn)?;
    let mut system_by_key = std::collections::BTreeMap::<String, Tag>::new();
    for tag in &tags {
        if !tag.is_system {
            continue;
        }
        if let Some(system_key) = tag.system_key.as_ref() {
            system_by_key.insert(system_key.clone(), tag.clone());
        }
    }

    let custom_with_usage = tags
        .iter()
        .filter(|tag| !tag.is_system)
        .filter(|tag| usage_counts.get(&tag.id).copied().unwrap_or(0) > 0)
        .cloned()
        .collect::<Vec<_>>();

    if custom_with_usage.is_empty() {
        return Ok(Vec::new());
    }

    let mut best_by_source = std::collections::BTreeMap::<String, TagMergeSuggestion>::new();

    for source in &custom_with_usage {
        let Some(system_key) = map_to_system_key(&source.name) else {
            continue;
        };
        let Some(target) = system_by_key.get(system_key) else {
            continue;
        };

        let source_usage = usage_counts.get(&source.id).copied().unwrap_or(0);
        let target_usage = usage_counts.get(&target.id).copied().unwrap_or(0);
        push_merge_candidate(
            &mut best_by_source,
            source,
            target,
            "system_domain",
            0.98,
            source_usage,
            target_usage,
        );
    }

    for i in 0..custom_with_usage.len() {
        for j in (i + 1)..custom_with_usage.len() {
            let left = &custom_with_usage[i];
            let right = &custom_with_usage[j];

            let left_key = normalize_tag_merge_key(&left.name);
            let right_key = normalize_tag_merge_key(&right.name);
            if left_key.len() < 3 || right_key.len() < 3 {
                continue;
            }

            let score_and_reason = if left_key == right_key {
                Some((0.92, "name_compact_match"))
            } else {
                let min_len = left_key.len().min(right_key.len());
                if min_len >= 4
                    && (left_key.contains(&right_key) || right_key.contains(&left_key))
                {
                    Some((0.78, "name_contains"))
                } else {
                    None
                }
            };

            let Some((score, reason)) = score_and_reason else {
                continue;
            };

            let (source, target, source_usage, target_usage) =
                choose_merge_direction(left, right, &usage_counts);

            push_merge_candidate(
                &mut best_by_source,
                source,
                target,
                reason,
                score,
                source_usage,
                target_usage,
            );
        }
    }

    let mut out = best_by_source.into_values().collect::<Vec<_>>();
    apply_tag_merge_feedback_scores(conn, &mut out)?;
    out.sort_by(|left, right| {
        right
            .score
            .partial_cmp(&left.score)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| right.source_usage_count.cmp(&left.source_usage_count))
            .then_with(|| left.source_tag.id.cmp(&right.source_tag.id))
    });

    out.truncate(limit.min(50));
    Ok(out)
}

pub fn merge_tags(
    conn: &Connection,
    db_key: &[u8; 32],
    source_tag_id: &str,
    target_tag_id: &str,
) -> Result<u32> {
    ensure_system_tags(conn, db_key)?;

    let source_tag_id = source_tag_id.trim();
    if source_tag_id.is_empty() {
        return Err(anyhow!("source_tag_id cannot be empty"));
    }

    let target_tag_id = target_tag_id.trim();
    if target_tag_id.is_empty() {
        return Err(anyhow!("target_tag_id cannot be empty"));
    }

    if source_tag_id == target_tag_id {
        return Err(anyhow!("source_tag_id and target_tag_id must differ"));
    }

    let source = read_tag_by_id(conn, db_key, source_tag_id)?
        .ok_or_else(|| anyhow!("source tag not found: {source_tag_id}"))?;
    if source.is_system {
        return Err(anyhow!("system tags cannot be merged into other tags"));
    }

    let _target = read_tag_by_id(conn, db_key, target_tag_id)?
        .ok_or_else(|| anyhow!("target tag not found: {target_tag_id}"))?;

    let mut stmt = conn.prepare(
        r#"SELECT DISTINCT message_id
           FROM message_tags
           WHERE tag_id = ?1
           ORDER BY message_id ASC"#,
    )?;
    let mut rows = stmt.query(params![source_tag_id])?;

    let mut message_ids = Vec::<String>::new();
    while let Some(row) = rows.next()? {
        message_ids.push(row.get(0)?);
    }

    let mut updated = 0u32;
    for message_id in message_ids {
        let mut tag_stmt = conn.prepare(
            r#"SELECT tag_id
               FROM message_tags
               WHERE message_id = ?1
               ORDER BY tag_id ASC"#,
        )?;
        let mut tag_rows = tag_stmt.query(params![message_id.as_str()])?;

        let mut existing_tag_ids = Vec::<String>::new();
        while let Some(row) = tag_rows.next()? {
            existing_tag_ids.push(row.get(0)?);
        }

        if !existing_tag_ids.iter().any(|id| id == source_tag_id) {
            continue;
        }

        let mut next_tag_ids = std::collections::BTreeSet::<String>::new();
        for tag_id in existing_tag_ids {
            if tag_id == source_tag_id {
                continue;
            }
            next_tag_ids.insert(tag_id);
        }
        next_tag_ids.insert(target_tag_id.to_string());

        let next_tag_ids = next_tag_ids.into_iter().collect::<Vec<_>>();
        set_message_tags(conn, db_key, &message_id, &next_tag_ids)?;
        updated = updated.saturating_add(1);
    }

    let deleted_at_ms = now_ms();
    conn.execute(
        r#"DELETE FROM tags
           WHERE id = ?1
             AND COALESCE(is_system, 0) = 0"#,
        params![source_tag_id],
    )?;
    let deleted_at_key = format!("tag.deleted_at:{source_tag_id}");
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
            "tag_id": source_tag_id,
            "deleted_at_ms": deleted_at_ms,
        }
    });
    insert_oplog(conn, db_key, &op)?;

    Ok(updated)
}

pub fn upsert_tag(conn: &Connection, db_key: &[u8; 32], name: &str) -> Result<Tag> {
    ensure_system_tags(conn, db_key)?;

    let trimmed = name.trim();
    if trimmed.is_empty() {
        return Err(anyhow!("tag name cannot be empty"));
    }

    if let Some(system_key) = map_to_system_key(trimmed) {
        if let Some(tag) = read_tag_by_system_key(conn, db_key, system_key)? {
            return Ok(tag);
        }
    }

    if let Some(existing) = find_existing_custom_tag_by_name(conn, db_key, trimmed)? {
        return Ok(existing);
    }

    let now = now_ms();
    let id = uuid::Uuid::new_v4().to_string();
    let aad = format!("tag.name:{id}");
    let name_blob = encrypt_bytes(db_key, trimmed.as_bytes(), aad.as_bytes())?;

    conn.execute(
        r#"INSERT INTO tags(id, name, system_key, is_system, color, created_at_ms, updated_at_ms)
           VALUES (?1, ?2, NULL, 0, NULL, ?3, ?4)"#,
        params![id, name_blob, now, now],
    )?;

    let device_id = get_or_create_device_id(conn)?;
    let seq = next_device_seq(conn, &device_id)?;
    let op = serde_json::json!({
        "op_id": uuid::Uuid::new_v4().to_string(),
        "device_id": device_id,
        "seq": seq,
        "ts_ms": now,
        "type": "tag.upsert.v2",
        "payload": {
            "tag_id": id,
            "name": trimmed,
            "system_key": null,
            "is_system": false,
            "color": null,
            "created_at_ms": now,
            "updated_at_ms": now,
        }
    });
    insert_oplog(conn, db_key, &op)?;

    read_tag_by_id(conn, db_key, &id)?.ok_or_else(|| anyhow!("failed to read created tag"))
}

pub fn list_message_tags(conn: &Connection, db_key: &[u8; 32], message_id: &str) -> Result<Vec<Tag>> {
    ensure_system_tags(conn, db_key)?;

    let mut stmt = conn.prepare(
        r#"SELECT t.id, t.name, t.system_key, COALESCE(t.is_system, 0), t.color, t.created_at_ms, t.updated_at_ms
           FROM tags t
           JOIN message_tags mt ON mt.tag_id = t.id
           WHERE mt.message_id = ?1
           ORDER BY COALESCE(t.is_system, 0) DESC, t.updated_at_ms DESC, t.id ASC"#,
    )?;
    let mut rows = stmt.query(params![message_id])?;

    let mut out = Vec::new();
    while let Some(row) = rows.next()? {
        let id: String = row.get(0)?;
        let name_blob: Vec<u8> = row.get(1)?;
        let system_key: Option<String> = row.get(2)?;
        let is_system_i64: i64 = row.get(3)?;
        let color: Option<String> = row.get(4)?;
        let created_at_ms: i64 = row.get(5)?;
        let updated_at_ms: i64 = row.get(6)?;
        let name = decrypt_tag_name(db_key, &id, &name_blob)?;

        out.push(Tag {
            id,
            name,
            system_key,
            is_system: is_system_i64 != 0,
            color,
            created_at_ms,
            updated_at_ms,
        });
    }

    Ok(out)
}

pub fn set_message_tags(
    conn: &Connection,
    db_key: &[u8; 32],
    message_id: &str,
    tag_ids: &[String],
) -> Result<Vec<Tag>> {
    ensure_system_tags(conn, db_key)?;

    let message_exists: Option<i64> = conn
        .query_row(
            r#"SELECT 1 FROM messages WHERE id = ?1"#,
            params![message_id],
            |row| row.get(0),
        )
        .optional()?;
    if message_exists.is_none() {
        return Err(anyhow!("message not found: {message_id}"));
    }

    let mut dedup = std::collections::BTreeSet::<String>::new();
    for raw in tag_ids {
        let trimmed = raw.trim();
        if trimmed.is_empty() {
            continue;
        }
        let tag_exists: Option<i64> = conn
            .query_row(
                r#"SELECT 1 FROM tags WHERE id = ?1"#,
                params![trimmed],
                |row| row.get(0),
            )
            .optional()?;
        if tag_exists.is_some() {
            dedup.insert(trimmed.to_string());
        }
    }

    let next_tag_ids: Vec<String> = dedup.into_iter().collect();

    let mut stmt = conn.prepare(
        r#"SELECT tag_id
           FROM message_tags
           WHERE message_id = ?1
           ORDER BY tag_id ASC"#,
    )?;
    let mut rows = stmt.query(params![message_id])?;
    let mut existing_tag_ids = Vec::<String>::new();
    while let Some(row) = rows.next()? {
        existing_tag_ids.push(row.get(0)?);
    }

    if existing_tag_ids == next_tag_ids {
        return list_message_tags(conn, db_key, message_id);
    }

    conn.execute_batch("BEGIN IMMEDIATE;")?;
    let result: Result<()> = (|| {
        conn.execute(
            r#"DELETE FROM message_tags WHERE message_id = ?1"#,
            params![message_id],
        )?;

        let now = now_ms();
        for tag_id in &next_tag_ids {
            conn.execute(
                r#"INSERT INTO message_tags(message_id, tag_id, created_at_ms)
                   VALUES (?1, ?2, ?3)"#,
                params![message_id, tag_id, now],
            )?;
        }

        let device_id = get_or_create_device_id(conn)?;
        let seq = next_device_seq(conn, &device_id)?;
        let op = serde_json::json!({
            "op_id": uuid::Uuid::new_v4().to_string(),
            "device_id": device_id,
            "seq": seq,
            "ts_ms": now,
            "type": "message.tag_set.v1",
            "payload": {
                "message_id": message_id,
                "tag_ids": next_tag_ids,
                "created_at_ms": now,
            }
        });
        insert_oplog(conn, db_key, &op)?;

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

    list_message_tags(conn, db_key, message_id)
}

fn normalize_non_empty_tag_ids(tag_ids: &[String]) -> Vec<String> {
    let mut dedup = std::collections::BTreeSet::<String>::new();
    for raw in tag_ids {
        let trimmed = raw.trim();
        if trimmed.is_empty() {
            continue;
        }
        dedup.insert(trimmed.to_string());
    }
    dedup.into_iter().collect()
}

fn list_message_ids_by_tag_ids_with_optional_conversation(
    conn: &Connection,
    conversation_id: Option<&str>,
    tag_ids: &[String],
) -> Result<Vec<String>> {
    let tag_ids = normalize_non_empty_tag_ids(tag_ids);

    if tag_ids.is_empty() {
        return Ok(Vec::new());
    }

    let conversation_clause = if conversation_id.is_some() {
        "m.conversation_id = ?1 AND "
    } else {
        ""
    };
    let first_tag_param = if conversation_id.is_some() { 2 } else { 1 };

    let placeholders = (0..tag_ids.len())
        .map(|idx| format!("?{}", idx + first_tag_param))
        .collect::<Vec<_>>()
        .join(", ");

    let sql = format!(
        r#"SELECT DISTINCT m.id
           FROM messages m
           JOIN message_tags mt ON mt.message_id = m.id
           WHERE {conversation_clause}COALESCE(m.is_deleted, 0) = 0
             AND mt.tag_id IN ({placeholders})
           ORDER BY m.created_at DESC, m.id DESC"#
    );

    let mut values = Vec::<rusqlite::types::Value>::with_capacity(
        tag_ids.len() + if conversation_id.is_some() { 1 } else { 0 },
    );
    if let Some(conversation_id) = conversation_id {
        values.push(rusqlite::types::Value::Text(conversation_id.to_string()));
    }
    for tag_id in &tag_ids {
        values.push(rusqlite::types::Value::Text(tag_id.clone()));
    }

    let mut stmt = conn.prepare(&sql)?;
    let mut rows = stmt.query(rusqlite::params_from_iter(values.iter()))?;

    let mut out = Vec::new();
    while let Some(row) = rows.next()? {
        out.push(row.get(0)?);
    }
    Ok(out)
}

pub fn list_message_ids_by_tag_ids(
    conn: &Connection,
    conversation_id: &str,
    tag_ids: &[String],
) -> Result<Vec<String>> {
    list_message_ids_by_tag_ids_with_optional_conversation(
        conn,
        Some(conversation_id),
        tag_ids,
    )
}

pub fn list_message_ids_by_tag_ids_all(conn: &Connection, tag_ids: &[String]) -> Result<Vec<String>> {
    list_message_ids_by_tag_ids_with_optional_conversation(conn, None, tag_ids)
}
