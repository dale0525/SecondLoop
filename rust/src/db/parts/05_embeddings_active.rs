pub fn process_pending_message_embeddings_active(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    limit: usize,
) -> Result<usize> {
    let desired = desired_embedding_model_name(conn)?;

    if desired == crate::embedding::DEFAULT_MODEL_NAME {
        set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
        return process_pending_message_embeddings_default(conn, key, limit);
    }

    if desired == crate::embedding::PRODUCTION_MODEL_NAME {
        #[cfg(all(
            any(target_os = "windows", target_os = "macos", target_os = "linux"),
            not(frb_expand)
        ))]
        {
            match crate::embedding::FastEmbedder::get_or_try_init(app_dir) {
                Ok(embedder) => {
                    set_active_embedding_model_name(conn, crate::embedding::PRODUCTION_MODEL_NAME)?;
                    return process_pending_message_embeddings(conn, key, &embedder, limit);
                }
                Err(e) => return Err(anyhow!("production embeddings unavailable: {e}")),
            }
        }

        #[cfg(not(all(
            any(target_os = "windows", target_os = "macos", target_os = "linux"),
            not(frb_expand)
        )))]
        {
            set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
            return process_pending_message_embeddings_default(conn, key, limit);
        }
    }

    set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
    process_pending_message_embeddings_default(conn, key, limit)
}

pub fn process_pending_todo_embeddings_active(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    limit: usize,
) -> Result<usize> {
    let desired = desired_embedding_model_name(conn)?;

    if desired == crate::embedding::DEFAULT_MODEL_NAME {
        set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
        return process_pending_todo_embeddings_default(conn, key, limit);
    }

    if desired == crate::embedding::PRODUCTION_MODEL_NAME {
        #[cfg(all(
            any(target_os = "windows", target_os = "macos", target_os = "linux"),
            not(frb_expand)
        ))]
        {
            match crate::embedding::FastEmbedder::get_or_try_init(app_dir) {
                Ok(embedder) => {
                    set_active_embedding_model_name(conn, crate::embedding::PRODUCTION_MODEL_NAME)?;
                    return process_pending_todo_embeddings(conn, key, &embedder, limit);
                }
                Err(e) => return Err(anyhow!("production embeddings unavailable: {e}")),
            }
        }

        #[cfg(not(all(
            any(target_os = "windows", target_os = "macos", target_os = "linux"),
            not(frb_expand)
        )))]
        {
            set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
            return process_pending_todo_embeddings_default(conn, key, limit);
        }
    }

    set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
    process_pending_todo_embeddings_default(conn, key, limit)
}

pub fn process_pending_todo_activity_embeddings_active(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    limit: usize,
) -> Result<usize> {
    let desired = desired_embedding_model_name(conn)?;

    if desired == crate::embedding::DEFAULT_MODEL_NAME {
        set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
        return process_pending_todo_activity_embeddings_default(conn, key, limit);
    }

    if desired == crate::embedding::PRODUCTION_MODEL_NAME {
        #[cfg(all(
            any(target_os = "windows", target_os = "macos", target_os = "linux"),
            not(frb_expand)
        ))]
        {
            match crate::embedding::FastEmbedder::get_or_try_init(app_dir) {
                Ok(embedder) => {
                    set_active_embedding_model_name(conn, crate::embedding::PRODUCTION_MODEL_NAME)?;
                    return process_pending_todo_activity_embeddings(conn, key, &embedder, limit);
                }
                Err(e) => return Err(anyhow!("production embeddings unavailable: {e}")),
            }
        }

        #[cfg(not(all(
            any(target_os = "windows", target_os = "macos", target_os = "linux"),
            not(frb_expand)
        )))]
        {
            set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
            return process_pending_todo_activity_embeddings_default(conn, key, limit);
        }
    }

    set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
    process_pending_todo_activity_embeddings_default(conn, key, limit)
}

pub fn rebuild_message_embeddings_active(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    batch_limit: usize,
) -> Result<usize> {
    let desired = desired_embedding_model_name(conn)?;

    if desired == crate::embedding::DEFAULT_MODEL_NAME {
        set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
        return rebuild_message_embeddings_default(conn, key, batch_limit);
    }

    if desired == crate::embedding::PRODUCTION_MODEL_NAME {
        #[cfg(all(
            any(target_os = "windows", target_os = "macos", target_os = "linux"),
            not(frb_expand)
        ))]
        {
            match crate::embedding::FastEmbedder::get_or_try_init(app_dir) {
                Ok(embedder) => {
                    set_active_embedding_model_name(conn, crate::embedding::PRODUCTION_MODEL_NAME)?;
                    return rebuild_message_embeddings(conn, key, &embedder, batch_limit);
                }
                Err(e) => return Err(anyhow!("production embeddings unavailable: {e}")),
            }
        }

        #[cfg(not(all(
            any(target_os = "windows", target_os = "macos", target_os = "linux"),
            not(frb_expand)
        )))]
        {
            set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
            return rebuild_message_embeddings_default(conn, key, batch_limit);
        }
    }

    set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
    rebuild_message_embeddings_default(conn, key, batch_limit)
}

pub fn search_similar_messages_active(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    query: &str,
    top_k: usize,
) -> Result<Vec<SimilarMessage>> {
    let desired = desired_embedding_model_name(conn)?;

    if desired == crate::embedding::DEFAULT_MODEL_NAME {
        set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
        return search_similar_messages_default(conn, key, query, top_k);
    }

    if desired == crate::embedding::PRODUCTION_MODEL_NAME {
        #[cfg(all(
            any(target_os = "windows", target_os = "macos", target_os = "linux"),
            not(frb_expand)
        ))]
        {
            match crate::embedding::FastEmbedder::get_or_try_init(app_dir) {
                Ok(embedder) => {
                    set_active_embedding_model_name(conn, crate::embedding::PRODUCTION_MODEL_NAME)?;
                    return search_similar_messages(conn, key, &embedder, query, top_k);
                }
                Err(e) => return Err(anyhow!("production embeddings unavailable: {e}")),
            }
        }

        #[cfg(not(all(
            any(target_os = "windows", target_os = "macos", target_os = "linux"),
            not(frb_expand)
        )))]
        {
            set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
            return search_similar_messages_default(conn, key, query, top_k);
        }
    }

    set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
    search_similar_messages_default(conn, key, query, top_k)
}

pub fn search_similar_messages_in_conversation_active(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    conversation_id: &str,
    query: &str,
    top_k: usize,
) -> Result<Vec<SimilarMessage>> {
    let desired = desired_embedding_model_name(conn)?;

    if desired == crate::embedding::DEFAULT_MODEL_NAME {
        set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
        return search_similar_messages_in_conversation_default(
            conn,
            key,
            conversation_id,
            query,
            top_k,
        );
    }

    if desired == crate::embedding::PRODUCTION_MODEL_NAME {
        #[cfg(all(
            any(target_os = "windows", target_os = "macos", target_os = "linux"),
            not(frb_expand)
        ))]
        {
            match crate::embedding::FastEmbedder::get_or_try_init(app_dir) {
                Ok(embedder) => {
                    set_active_embedding_model_name(conn, crate::embedding::PRODUCTION_MODEL_NAME)?;
                    return search_similar_messages_in_conversation(
                        conn,
                        key,
                        &embedder,
                        conversation_id,
                        query,
                        top_k,
                    );
                }
                Err(e) => return Err(anyhow!("production embeddings unavailable: {e}")),
            }
        }

        #[cfg(not(all(
            any(target_os = "windows", target_os = "macos", target_os = "linux"),
            not(frb_expand)
        )))]
        {
            set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
            return search_similar_messages_in_conversation_default(
                conn,
                key,
                conversation_id,
                query,
                top_k,
            );
        }
    }

    set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
    search_similar_messages_in_conversation_default(conn, key, conversation_id, query, top_k)
}

pub fn search_similar_todo_threads_active(
    conn: &Connection,
    key: &[u8; 32],
    app_dir: &Path,
    query: &str,
    top_k: usize,
) -> Result<Vec<SimilarTodoThread>> {
    let desired = desired_embedding_model_name(conn)?;

    if desired == crate::embedding::DEFAULT_MODEL_NAME {
        set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
        return search_similar_todo_threads_default(conn, key, query, top_k);
    }

    if desired == crate::embedding::PRODUCTION_MODEL_NAME {
        #[cfg(all(
            any(target_os = "windows", target_os = "macos", target_os = "linux"),
            not(frb_expand)
        ))]
        {
            match crate::embedding::FastEmbedder::get_or_try_init(app_dir) {
                Ok(embedder) => {
                    set_active_embedding_model_name(conn, crate::embedding::PRODUCTION_MODEL_NAME)?;
                    return search_similar_todo_threads(conn, key, &embedder, query, top_k);
                }
                Err(e) => return Err(anyhow!("production embeddings unavailable: {e}")),
            }
        }

        #[cfg(not(all(
            any(target_os = "windows", target_os = "macos", target_os = "linux"),
            not(frb_expand)
        )))]
        {
            set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
            return search_similar_todo_threads_default(conn, key, query, top_k);
        }
    }

    set_active_embedding_model_name(conn, crate::embedding::DEFAULT_MODEL_NAME)?;
    search_similar_todo_threads_default(conn, key, query, top_k)
}

const MAX_ATTACHMENT_ENRICHMENT_CHARS: usize = 1024;

fn truncate_utf8_to_max_bytes(s: &str, max_bytes: usize) -> &str {
    if s.len() <= max_bytes {
        return s;
    }
    let mut end = max_bytes;
    while end > 0 && !s.is_char_boundary(end) {
        end -= 1;
    }
    &s[..end]
}

fn read_attachment_place_display_name_optional(
    conn: &Connection,
    key: &[u8; 32],
    attachment_sha256: &str,
) -> Result<Option<String>> {
    let row: Option<(String, Vec<u8>)> = conn
        .query_row(
            r#"SELECT lang, payload
               FROM attachment_places
               WHERE attachment_sha256 = ?1
                 AND status = 'ok'
                 AND payload IS NOT NULL"#,
            params![attachment_sha256],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .optional()?;

    let Some((lang, payload_blob)) = row else {
        return Ok(None);
    };

    let aad = format!("attachment.place:{attachment_sha256}:{lang}");
    let json = match decrypt_bytes(key, &payload_blob, aad.as_bytes()) {
        Ok(v) => v,
        Err(_) => return Ok(None),
    };

    let payload: serde_json::Value = match serde_json::from_slice(&json) {
        Ok(v) => v,
        Err(_) => return Ok(None),
    };

    let display_name = payload
        .get("display_name")
        .and_then(|v| v.as_str())
        .or_else(|| payload.get("displayName").and_then(|v| v.as_str()))
        .unwrap_or_default()
        .trim();

    if !display_name.is_empty() {
        return Ok(Some(display_name.to_string()));
    }

    // Backwards-compatible fallback for older payload versions that only
    // include structured city/district fields.
    fn normalize_str(value: Option<&str>) -> Option<&str> {
        let s = value?.trim();
        if s.is_empty() {
            None
        } else {
            Some(s)
        }
    }

    let district_name = normalize_str(
        payload
            .get("district")
            .and_then(|v| v.get("name"))
            .and_then(|v| v.as_str()),
    );
    let city_name = normalize_str(
        payload
            .get("city")
            .and_then(|v| v.get("name"))
            .and_then(|v| v.as_str()),
    );

    let mut parts = Vec::new();
    for candidate in [district_name, city_name].into_iter().flatten() {
        if parts.iter().any(|existing: &&str| existing == &candidate) {
            continue;
        }
        parts.push(candidate);
    }

    if parts.is_empty() {
        return Ok(None);
    }

    Ok(Some(parts.join(", ")))
}

