pub fn list_messages(
    conn: &Connection,
    key: &[u8; 32],
    conversation_id: &str,
) -> Result<Vec<Message>> {
    let mut stmt = conn.prepare(
        r#"SELECT id, role, content, created_at, COALESCE(is_memory, 1)
           FROM messages
           WHERE conversation_id = ?1 AND COALESCE(is_deleted, 0) = 0
           ORDER BY created_at ASC"#,
    )?;

    let mut rows = stmt.query(params![conversation_id])?;
    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        let id: String = row.get(0)?;
        let role: String = row.get(1)?;
        let content_blob: Vec<u8> = row.get(2)?;
        let created_at_ms: i64 = row.get(3)?;
        let is_memory_i64: i64 = row.get(4)?;

        let content_bytes = decrypt_bytes(key, &content_blob, b"message.content")?;
        let content = String::from_utf8(content_bytes)
            .map_err(|_| anyhow!("message content is not valid utf-8"))?;

        result.push(Message {
            id,
            conversation_id: conversation_id.to_string(),
            role,
            content,
            created_at_ms,
            is_memory: is_memory_i64 != 0,
        });
    }

    Ok(result)
}

pub fn list_messages_page(
    conn: &Connection,
    key: &[u8; 32],
    conversation_id: &str,
    before_created_at_ms: Option<i64>,
    before_id: Option<&str>,
    limit: i64,
) -> Result<Vec<Message>> {
    let limit = limit.clamp(1, 500);

    let mut stmt = match (before_created_at_ms, before_id) {
        (None, None) => conn.prepare(
            r#"SELECT id, role, content, created_at, COALESCE(is_memory, 1)
               FROM messages
               WHERE conversation_id = ?1 AND COALESCE(is_deleted, 0) = 0
               ORDER BY created_at DESC, id DESC
               LIMIT ?2"#,
        )?,
        (Some(_), Some(_)) => conn.prepare(
            r#"SELECT id, role, content, created_at, COALESCE(is_memory, 1)
               FROM messages
               WHERE conversation_id = ?1 AND COALESCE(is_deleted, 0) = 0
                 AND (created_at < ?2 OR (created_at = ?2 AND id < ?3))
               ORDER BY created_at DESC, id DESC
               LIMIT ?4"#,
        )?,
        (Some(_), None) | (None, Some(_)) => {
            return Err(anyhow!(
                "invalid cursor: both before_created_at_ms and before_id required"
            ))
        }
    };

    let mut rows = match (before_created_at_ms, before_id) {
        (None, None) => stmt.query(params![conversation_id, limit])?,
        (Some(ts), Some(id)) => stmt.query(params![conversation_id, ts, id, limit])?,
        _ => unreachable!(),
    };

    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        let id: String = row.get(0)?;
        let role: String = row.get(1)?;
        let content_blob: Vec<u8> = row.get(2)?;
        let created_at_ms: i64 = row.get(3)?;
        let is_memory_i64: i64 = row.get(4)?;

        let content_bytes = decrypt_bytes(key, &content_blob, b"message.content")?;
        let content = String::from_utf8(content_bytes)
            .map_err(|_| anyhow!("message content is not valid utf-8"))?;

        result.push(Message {
            id,
            conversation_id: conversation_id.to_string(),
            role,
            content,
            created_at_ms,
            is_memory: is_memory_i64 != 0,
        });
    }

    Ok(result)
}

pub fn list_memory_messages_in_range(
    conn: &Connection,
    key: &[u8; 32],
    conversation_id: Option<&str>,
    start_at_ms_inclusive: i64,
    end_at_ms_exclusive: i64,
    limit: i64,
) -> Result<Vec<Message>> {
    let limit = limit.clamp(1, 2000);

    let mut stmt = match conversation_id {
        Some(_) => conn.prepare(
            r#"SELECT id, conversation_id, role, content, created_at
               FROM messages
               WHERE conversation_id = ?1
                 AND created_at >= ?2 AND created_at < ?3
                 AND COALESCE(is_deleted, 0) = 0
                 AND COALESCE(is_memory, 1) = 1
               ORDER BY created_at ASC, id ASC
               LIMIT ?4"#,
        )?,
        None => conn.prepare(
            r#"SELECT id, conversation_id, role, content, created_at
               FROM messages
               WHERE created_at >= ?1 AND created_at < ?2
                 AND COALESCE(is_deleted, 0) = 0
                 AND COALESCE(is_memory, 1) = 1
               ORDER BY created_at ASC, id ASC
               LIMIT ?3"#,
        )?,
    };

    let mut rows = match conversation_id {
        Some(cid) => stmt.query(params![
            cid,
            start_at_ms_inclusive,
            end_at_ms_exclusive,
            limit
        ])?,
        None => stmt.query(params![start_at_ms_inclusive, end_at_ms_exclusive, limit])?,
    };

    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        let id: String = row.get(0)?;
        let conversation_id: String = row.get(1)?;
        let role: String = row.get(2)?;
        let content_blob: Vec<u8> = row.get(3)?;
        let created_at_ms: i64 = row.get(4)?;

        let content_bytes = decrypt_bytes(key, &content_blob, b"message.content")?;
        let content = String::from_utf8(content_bytes)
            .map_err(|_| anyhow!("message content is not valid utf-8"))?;

        result.push(Message {
            id,
            conversation_id,
            role,
            content,
            created_at_ms,
            is_memory: true,
        });
    }

    Ok(result)
}

pub fn get_message_by_id_optional(
    conn: &Connection,
    key: &[u8; 32],
    id: &str,
) -> Result<Option<Message>> {
    let row: Option<(String, String, Vec<u8>, i64, i64)> = conn
        .query_row(
            r#"SELECT conversation_id, role, content, created_at, COALESCE(is_memory, 1)
               FROM messages
               WHERE id = ?1 AND COALESCE(is_deleted, 0) = 0"#,
            params![id],
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

    let Some((conversation_id, role, content_blob, created_at_ms, is_memory_i64)) = row else {
        return Ok(None);
    };

    let content_bytes = decrypt_bytes(key, &content_blob, b"message.content")?;
    let content = String::from_utf8(content_bytes)
        .map_err(|_| anyhow!("message content is not valid utf-8"))?;

    Ok(Some(Message {
        id: id.to_string(),
        conversation_id,
        role,
        content,
        created_at_ms,
        is_memory: is_memory_i64 != 0,
    }))
}

fn get_message_by_id(conn: &Connection, key: &[u8; 32], id: &str) -> Result<Message> {
    let (conversation_id, role, content_blob, created_at_ms, is_memory_i64): (
        String,
        String,
        Vec<u8>,
        i64,
        i64,
    ) = conn
        .query_row(
            r#"SELECT conversation_id, role, content, created_at, COALESCE(is_memory, 1)
               FROM messages
               WHERE id = ?1"#,
            params![id],
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
        .map_err(|e| anyhow!("get message failed: {e}"))?;

    let content_bytes = decrypt_bytes(key, &content_blob, b"message.content")?;
    let content = String::from_utf8(content_bytes)
        .map_err(|_| anyhow!("message content is not valid utf-8"))?;

    Ok(Message {
        id: id.to_string(),
        conversation_id,
        role,
        content,
        created_at_ms,
        is_memory: is_memory_i64 != 0,
    })
}

fn get_message_by_id_with_is_memory(
    conn: &Connection,
    key: &[u8; 32],
    id: &str,
) -> Result<(Message, bool)> {
    let (conversation_id, role, content_blob, created_at_ms, is_memory_i64): (
        String,
        String,
        Vec<u8>,
        i64,
        i64,
    ) = conn
        .query_row(
            r#"SELECT conversation_id, role, content, created_at, COALESCE(is_memory, 1)
               FROM messages
               WHERE id = ?1"#,
            params![id],
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
        .map_err(|e| anyhow!("get message failed: {e}"))?;

    let content_bytes = decrypt_bytes(key, &content_blob, b"message.content")?;
    let content = String::from_utf8(content_bytes)
        .map_err(|_| anyhow!("message content is not valid utf-8"))?;

    Ok((
        Message {
            id: id.to_string(),
            conversation_id,
            role,
            content,
            created_at_ms,
            is_memory: is_memory_i64 != 0,
        },
        is_memory_i64 != 0,
    ))
}

pub fn search_similar_messages<E: Embedder + ?Sized>(
    conn: &Connection,
    key: &[u8; 32],
    embedder: &E,
    query: &str,
    top_k: usize,
) -> Result<Vec<SimilarMessage>> {
    let query = format!("query: {query}");
    let mut vectors = embedder.embed(&[query])?;
    if vectors.len() != 1 {
        return Err(anyhow!(
            "embedder output length mismatch: expected 1, got {}",
            vectors.len()
        ));
    }
    let query_vector = vectors.remove(0);
    let expected_dim = current_embedding_dim(conn)?;
    if query_vector.len() != expected_dim {
        return Err(anyhow!(
            "embedder dim mismatch: expected {expected_dim}, got {} (model_name={})",
            query_vector.len(),
            embedder.model_name()
        ));
    }
    search_similar_messages_by_embedding(conn, key, embedder.model_name(), &query_vector, top_k)
}

pub fn search_similar_messages_by_embedding(
    conn: &Connection,
    key: &[u8; 32],
    model_name: &str,
    query_vector: &[f32],
    top_k: usize,
) -> Result<Vec<SimilarMessage>> {
    let expected_dim = current_embedding_dim(conn)?;
    let space_id = embedding_space_id(model_name, expected_dim)?;
    ensure_vec_tables_for_space(conn, &space_id, expected_dim)?;
    let message_table = message_embeddings_table(&space_id)?;

    if query_vector.len() != expected_dim {
        return Err(anyhow!(
            "query vector dim mismatch: expected {expected_dim}, got {} (model_name={model_name})",
            query_vector.len(),
        ));
    }

    let top_k = top_k.max(1);
    let candidate_k = (top_k.saturating_mul(10)).min(1000);

    let mut stmt = conn.prepare(&format!(
        r#"SELECT message_id, distance
           FROM "{message_table}"
           WHERE embedding match ?1 AND k = ?2 AND model_name = ?3
           ORDER BY distance ASC"#
    ))?;

    let mut rows = stmt.query(params![
        query_vector.as_bytes(),
        i64::try_from(candidate_k).unwrap_or(i64::MAX),
        model_name
    ])?;

    let mut result = Vec::new();
    let mut seen_contexts = std::collections::HashSet::new();
    while let Some(row) = rows.next()? {
        let message_id: String = row.get(0)?;
        let distance: f64 = row.get(1)?;
        let message = match get_message_by_id(conn, key, &message_id) {
            Ok(v) => v,
            Err(_) => {
                // Keep retrieval resilient: stale/corrupt rows should not fail the whole query.
                continue;
            }
        };
        let context_key = build_message_rag_context(conn, key, &message.id, &message.content)
            .unwrap_or_else(|_| message.content.clone());
        if !seen_contexts.insert(context_key) {
            continue;
        }
        result.push(SimilarMessage { message, distance });
        if result.len() >= top_k {
            break;
        }
    }

    Ok(result)
}

pub fn search_similar_messages_default(
    conn: &Connection,
    key: &[u8; 32],
    query: &str,
    top_k: usize,
) -> Result<Vec<SimilarMessage>> {
    search_similar_messages_lite(conn, key, None, query, top_k)
}

pub fn search_similar_messages_in_conversation_default(
    conn: &Connection,
    key: &[u8; 32],
    conversation_id: &str,
    query: &str,
    top_k: usize,
) -> Result<Vec<SimilarMessage>> {
    search_similar_messages_lite(conn, key, Some(conversation_id), query, top_k)
}

pub fn search_similar_todo_threads<E: Embedder + ?Sized>(
    conn: &Connection,
    _key: &[u8; 32],
    embedder: &E,
    query: &str,
    top_k: usize,
) -> Result<Vec<SimilarTodoThread>> {
    let top_k = top_k.max(1);

    let query = format!("query: {query}");
    let mut vectors = embedder.embed(&[query])?;
    if vectors.len() != 1 {
        return Err(anyhow!(
            "embedder output length mismatch: expected 1, got {}",
            vectors.len()
        ));
    }
    let query_vector = vectors.remove(0);
    search_similar_todo_threads_by_embedding(conn, embedder.model_name(), &query_vector, top_k)
}

pub fn search_similar_todo_threads_by_embedding(
    conn: &Connection,
    model_name: &str,
    query_vector: &[f32],
    top_k: usize,
) -> Result<Vec<SimilarTodoThread>> {
    let expected_dim = current_embedding_dim(conn)?;
    let space_id = embedding_space_id(model_name, expected_dim)?;
    ensure_vec_tables_for_space(conn, &space_id, expected_dim)?;
    let todo_table = todo_embeddings_table(&space_id)?;
    let activity_table = todo_activity_embeddings_table(&space_id)?;

    if query_vector.len() != expected_dim {
        return Err(anyhow!(
            "query vector dim mismatch: expected {expected_dim}, got {} (model_name={})",
            query_vector.len(),
            model_name
        ));
    }

    let top_k = top_k.max(1);
    let candidate_k = (top_k.saturating_mul(10)).min(1000);

    let mut best: std::collections::HashMap<String, f64> = std::collections::HashMap::new();

    {
        let mut stmt = conn.prepare(&format!(
            r#"SELECT te.todo_id, te.distance
               FROM "{todo_table}" te
               JOIN todos t ON t.id = te.todo_id
               WHERE te.embedding match ?1 AND te.k = ?2 AND te.model_name = ?3
                 AND t.status != 'dismissed'
               ORDER BY te.distance ASC"#
        ))?;

        let mut rows = stmt.query(params![
            query_vector.as_bytes(),
            i64::try_from(candidate_k).unwrap_or(i64::MAX),
            model_name
        ])?;

        while let Some(row) = rows.next()? {
            let todo_id: String = row.get(0)?;
            let distance: f64 = row.get(1)?;
            best.entry(todo_id)
                .and_modify(|d| *d = (*d).min(distance))
                .or_insert(distance);
        }
    }

    {
        let mut stmt = conn.prepare(&format!(
            r#"SELECT tae.todo_id, tae.distance
               FROM "{activity_table}" tae
               JOIN todos t ON t.id = tae.todo_id
               WHERE tae.embedding match ?1 AND tae.k = ?2 AND tae.model_name = ?3
                 AND t.status != 'dismissed'
               ORDER BY tae.distance ASC"#
        ))?;

        let mut rows = stmt.query(params![
            query_vector.as_bytes(),
            i64::try_from(candidate_k).unwrap_or(i64::MAX),
            model_name
        ])?;

        while let Some(row) = rows.next()? {
            let todo_id: String = row.get(0)?;
            let distance: f64 = row.get(1)?;
            best.entry(todo_id)
                .and_modify(|d| *d = (*d).min(distance))
                .or_insert(distance);
        }
    }

    let mut result: Vec<SimilarTodoThread> = best
        .into_iter()
        .map(|(todo_id, distance)| SimilarTodoThread { todo_id, distance })
        .collect();
    result.sort_by(|a, b| {
        a.distance
            .partial_cmp(&b.distance)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| a.todo_id.cmp(&b.todo_id))
    });
    result.truncate(top_k);
    Ok(result)
}

pub fn search_similar_todo_threads_default(
    conn: &Connection,
    key: &[u8; 32],
    query: &str,
    top_k: usize,
) -> Result<Vec<SimilarTodoThread>> {
    let top_k = top_k.max(1);

    let query_norm = lite_normalize_text(query);
    let query_compact = lite_compact_text(&query_norm);
    if query_compact.is_empty() {
        return Ok(Vec::new());
    }

    let query_chars: Vec<char> = query_compact.chars().collect();
    let query_bigrams = lite_collect_bigrams(&query_chars);
    let query_trigrams = lite_collect_trigrams(&query_chars);

    let mut result: Vec<SimilarTodoThread> = Vec::new();

    for todo in list_todos(conn, key)? {
        if todo.status == "dismissed" {
            continue;
        }

        let activities = list_todo_activities(conn, key, &todo.id)?;
        let mut text = String::new();
        text.push_str("TODO ");
        text.push_str(&todo.title);
        for a in activities {
            text.push('\n');
            text.push_str("ACTIVITY ");
            text.push_str(&a.activity_type);
            if let Some(from) = a.from_status.as_deref() {
                text.push_str(" from=");
                text.push_str(from);
            }
            if let Some(to) = a.to_status.as_deref() {
                text.push_str(" to=");
                text.push_str(to);
            }
            if let Some(content) = a.content.as_deref() {
                text.push_str(" content=");
                text.push_str(content);
            }
        }

        let score = lite_score(
            &query_norm,
            &query_compact,
            &query_bigrams,
            &query_trigrams,
            &text,
        );
        if score == 0 {
            continue;
        }

        let distance = 1.0 / (score as f64 + 1.0);
        result.push(SimilarTodoThread {
            todo_id: todo.id,
            distance,
        });
    }

    result.sort_by(|a, b| {
        a.distance
            .partial_cmp(&b.distance)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| a.todo_id.cmp(&b.todo_id))
    });
    result.truncate(top_k);
    Ok(result)
}

fn search_similar_messages_lite(
    conn: &Connection,
    key: &[u8; 32],
    conversation_id: Option<&str>,
    query: &str,
    top_k: usize,
) -> Result<Vec<SimilarMessage>> {
    let top_k = top_k.max(1);

    let query_norm = lite_normalize_text(query);
    let query_compact = lite_compact_text(&query_norm);
    if query_compact.is_empty() {
        return Ok(Vec::new());
    }

    let query_chars: Vec<char> = query_compact.chars().collect();
    let query_bigrams = lite_collect_bigrams(&query_chars);
    let query_trigrams = lite_collect_trigrams(&query_chars);

    let mut result: Vec<SimilarMessage> = Vec::new();
    let mut seen_contents = std::collections::HashSet::new();

    let mut stmt = if conversation_id.is_some() {
        conn.prepare(
            r#"SELECT id, conversation_id, role, content, created_at
               FROM messages
               WHERE conversation_id = ?1
                 AND COALESCE(is_deleted, 0) = 0
                 AND COALESCE(is_memory, 1) = 1
               ORDER BY created_at DESC"#,
        )?
    } else {
        conn.prepare(
            r#"SELECT id, conversation_id, role, content, created_at
               FROM messages
               WHERE COALESCE(is_deleted, 0) = 0
                 AND COALESCE(is_memory, 1) = 1
               ORDER BY created_at DESC"#,
        )?
    };

    let mut rows = if let Some(conversation_id) = conversation_id {
        stmt.query(params![conversation_id])?
    } else {
        stmt.query([])?
    };

    while let Some(row) = rows.next()? {
        let id: String = row.get(0)?;
        let conversation_id: String = row.get(1)?;
        let role: String = row.get(2)?;
        let content_blob: Vec<u8> = row.get(3)?;
        let created_at_ms: i64 = row.get(4)?;

        let content_bytes = decrypt_bytes(key, &content_blob, b"message.content")?;
        let content = String::from_utf8(content_bytes)
            .map_err(|_| anyhow!("message content is not valid utf-8"))?;

        if !seen_contents.insert(content.clone()) {
            continue;
        }

        let score = lite_score(
            &query_norm,
            &query_compact,
            &query_bigrams,
            &query_trigrams,
            &content,
        );
        if score == 0 {
            continue;
        }

        let distance = 1.0 / (score as f64 + 1.0);
        result.push(SimilarMessage {
            message: Message {
                id,
                conversation_id,
                role,
                content,
                created_at_ms,
                is_memory: true,
            },
            distance,
        });
    }

    result.sort_by(|a, b| {
        a.distance
            .partial_cmp(&b.distance)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| b.message.created_at_ms.cmp(&a.message.created_at_ms))
    });

    result.truncate(top_k);
    Ok(result)
}

fn lite_normalize_text(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for ch in text.chars() {
        if ch.is_alphanumeric() {
            out.extend(ch.to_lowercase());
        } else {
            out.push(' ');
        }
    }
    out.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn lite_compact_text(text: &str) -> String {
    text.chars().filter(|c| !c.is_whitespace()).collect()
}

fn lite_collect_bigrams(chars: &[char]) -> std::collections::HashSet<u64> {
    let mut set = std::collections::HashSet::new();
    if chars.len() < 2 {
        return set;
    }
    for i in 0..(chars.len() - 1) {
        let a = chars[i] as u64;
        let b = chars[i + 1] as u64;
        set.insert((a << 32) | b);
    }
    set
}

fn lite_collect_trigrams(chars: &[char]) -> std::collections::HashSet<u128> {
    let mut set = std::collections::HashSet::new();
    if chars.len() < 3 {
        return set;
    }
    for i in 0..(chars.len() - 2) {
        let a = chars[i] as u128;
        let b = chars[i + 1] as u128;
        let c = chars[i + 2] as u128;
        set.insert((a << 64) | (b << 32) | c);
    }
    set
}

fn lite_score(
    query_norm: &str,
    query_compact: &str,
    query_bigrams: &std::collections::HashSet<u64>,
    query_trigrams: &std::collections::HashSet<u128>,
    candidate: &str,
) -> u64 {
    let cand_norm = lite_normalize_text(candidate);
    if cand_norm.is_empty() {
        return 0;
    }

    let cand_compact = lite_compact_text(&cand_norm);
    if cand_compact.is_empty() {
        return 0;
    }

    let mut score = 0u64;

    if cand_norm == query_norm {
        score = score.saturating_add(10_000);
    }

    if !query_norm.is_empty() && cand_norm.contains(query_norm) {
        score = score.saturating_add(500);
        score = score.saturating_add((query_compact.chars().count() as u64).saturating_mul(50));
    }

    for token in query_norm.split_whitespace() {
        if token.len() < 2 {
            continue;
        }
        if cand_norm.contains(token) {
            score = score.saturating_add((token.chars().count() as u64).saturating_mul(200));
        }
    }

    let cand_chars: Vec<char> = cand_compact.chars().collect();
    if !query_bigrams.is_empty() {
        let cand_bigrams = lite_collect_bigrams(&cand_chars);
        let overlap = query_bigrams.intersection(&cand_bigrams).count() as u64;
        score = score.saturating_add(overlap.saturating_mul(50));
    }

    if !query_trigrams.is_empty() {
        let cand_trigrams = lite_collect_trigrams(&cand_chars);
        let overlap = query_trigrams.intersection(&cand_trigrams).count() as u64;
        score = score.saturating_add(overlap.saturating_mul(80));
    }

    score
}

pub fn search_similar_messages_in_conversation<E: Embedder + ?Sized>(
    conn: &Connection,
    key: &[u8; 32],
    embedder: &E,
    conversation_id: &str,
    query: &str,
    top_k: usize,
) -> Result<Vec<SimilarMessage>> {
    let query = format!("query: {query}");
    let mut vectors = embedder.embed(&[query])?;
    if vectors.len() != 1 {
        return Err(anyhow!(
            "embedder output length mismatch: expected 1, got {}",
            vectors.len()
        ));
    }
    let query_vector = vectors.remove(0);
    let expected_dim = current_embedding_dim(conn)?;
    if query_vector.len() != expected_dim {
        return Err(anyhow!(
            "embedder dim mismatch: expected {expected_dim}, got {} (model_name={})",
            query_vector.len(),
            embedder.model_name()
        ));
    }
    search_similar_messages_in_conversation_by_embedding(
        conn,
        key,
        embedder.model_name(),
        conversation_id,
        &query_vector,
        top_k,
    )
}

pub fn search_similar_messages_in_conversation_by_embedding(
    conn: &Connection,
    key: &[u8; 32],
    model_name: &str,
    conversation_id: &str,
    query_vector: &[f32],
    top_k: usize,
) -> Result<Vec<SimilarMessage>> {
    // `sqlite-vec` KNN queries currently restrict additional WHERE constraints in ways that make
    // joins/IN filters brittle. For Focus scoping, we over-fetch candidates globally and then
    // filter in Rust.
    let top_k = top_k.max(1);
    let candidate_k = (top_k.saturating_mul(50)).min(1000);

    let candidates =
        search_similar_messages_by_embedding(conn, key, model_name, query_vector, candidate_k)?;
    Ok(candidates
        .into_iter()
        .filter(|sm| sm.message.conversation_id == conversation_id)
        .take(top_k)
        .collect())
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
