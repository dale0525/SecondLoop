pub fn create_llm_profile(
    conn: &Connection,
    key: &[u8; 32],
    name: &str,
    provider_type: &str,
    base_url: Option<&str>,
    api_key: Option<&str>,
    model_name: &str,
    set_active: bool,
) -> Result<LlmProfile> {
    let id = uuid::Uuid::new_v4().to_string();
    let now = now_ms();

    let api_key_blob: Option<Vec<u8>> = api_key
        .map(|v| encrypt_bytes(key, v.as_bytes(), format!("llm.api_key:{id}").as_bytes()))
        .transpose()?;

    if set_active {
        conn.execute_batch("UPDATE llm_profiles SET is_active = 0;")?;
    }

    conn.execute(
        r#"INSERT INTO llm_profiles
           (id, name, provider_type, base_url, api_key, model_name, is_active, created_at, updated_at)
           VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)"#,
        params![
            id,
            name,
            provider_type,
            base_url,
            api_key_blob,
            model_name,
            if set_active { 1 } else { 0 },
            now,
            now
        ],
    )?;

    Ok(LlmProfile {
        id,
        name: name.to_string(),
        provider_type: provider_type.to_string(),
        base_url: base_url.map(|v| v.to_string()),
        model_name: model_name.to_string(),
        is_active: set_active,
        created_at_ms: now,
        updated_at_ms: now,
    })
}

pub fn create_embedding_profile(
    conn: &Connection,
    key: &[u8; 32],
    name: &str,
    provider_type: &str,
    base_url: Option<&str>,
    api_key: Option<&str>,
    model_name: &str,
    set_active: bool,
) -> Result<EmbeddingProfile> {
    let id = uuid::Uuid::new_v4().to_string();
    let now = now_ms();

    let api_key_blob: Option<Vec<u8>> = api_key
        .map(|v| {
            encrypt_bytes(
                key,
                v.as_bytes(),
                format!("embedding.api_key:{id}").as_bytes(),
            )
        })
        .transpose()?;

    if set_active {
        conn.execute_batch("UPDATE embedding_profiles SET is_active = 0;")?;
    }

    conn.execute(
        r#"INSERT INTO embedding_profiles
           (id, name, provider_type, base_url, api_key, model_name, is_active, created_at, updated_at)
           VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)"#,
        params![
            id,
            name,
            provider_type,
            base_url,
            api_key_blob,
            model_name,
            if set_active { 1 } else { 0 },
            now,
            now
        ],
    )?;

    Ok(EmbeddingProfile {
        id,
        name: name.to_string(),
        provider_type: provider_type.to_string(),
        base_url: base_url.map(|v| v.to_string()),
        model_name: model_name.to_string(),
        is_active: set_active,
        created_at_ms: now,
        updated_at_ms: now,
    })
}

pub fn list_llm_profiles(conn: &Connection) -> Result<Vec<LlmProfile>> {
    let mut stmt = conn.prepare(
        r#"SELECT id, name, provider_type, base_url, model_name, is_active, created_at, updated_at
           FROM llm_profiles
           ORDER BY updated_at DESC"#,
    )?;

    let mut rows = stmt.query([])?;
    let mut out: Vec<LlmProfile> = Vec::new();

    while let Some(row) = rows.next()? {
        out.push(LlmProfile {
            id: row.get(0)?,
            name: row.get(1)?,
            provider_type: row.get(2)?,
            base_url: row.get(3)?,
            model_name: row.get(4)?,
            is_active: row.get::<_, i64>(5)? != 0,
            created_at_ms: row.get(6)?,
            updated_at_ms: row.get(7)?,
        });
    }

    Ok(out)
}

pub fn list_embedding_profiles(conn: &Connection) -> Result<Vec<EmbeddingProfile>> {
    let mut stmt = conn.prepare(
        r#"SELECT id, name, provider_type, base_url, model_name, is_active, created_at, updated_at
           FROM embedding_profiles
           ORDER BY updated_at DESC"#,
    )?;

    let mut rows = stmt.query([])?;
    let mut out: Vec<EmbeddingProfile> = Vec::new();

    while let Some(row) = rows.next()? {
        out.push(EmbeddingProfile {
            id: row.get(0)?,
            name: row.get(1)?,
            provider_type: row.get(2)?,
            base_url: row.get(3)?,
            model_name: row.get(4)?,
            is_active: row.get::<_, i64>(5)? != 0,
            created_at_ms: row.get(6)?,
            updated_at_ms: row.get(7)?,
        });
    }

    Ok(out)
}

pub fn set_active_llm_profile(conn: &Connection, profile_id: &str) -> Result<()> {
    let now = now_ms();

    conn.execute_batch("BEGIN IMMEDIATE;")?;

    let result: Result<()> = (|| {
        let updated = conn.execute(
            r#"UPDATE llm_profiles
               SET is_active = 1, updated_at = ?2
               WHERE id = ?1"#,
            params![profile_id, now],
        )?;

        if updated == 0 {
            return Err(anyhow!("llm profile not found: {profile_id}"));
        }

        conn.execute(
            r#"UPDATE llm_profiles SET is_active = 0 WHERE id != ?1"#,
            params![profile_id],
        )?;

        Ok(())
    })();

    match result {
        Ok(()) => {
            conn.execute_batch("COMMIT;")?;
            Ok(())
        }
        Err(e) => {
            let _ = conn.execute_batch("ROLLBACK;");
            Err(e)
        }
    }
}

pub fn set_active_embedding_profile(conn: &Connection, profile_id: &str) -> Result<()> {
    let now = now_ms();

    conn.execute_batch("BEGIN IMMEDIATE;")?;

    let result: Result<()> = (|| {
        let updated = conn.execute(
            r#"UPDATE embedding_profiles
               SET is_active = 1, updated_at = ?2
               WHERE id = ?1"#,
            params![profile_id, now],
        )?;

        if updated == 0 {
            return Err(anyhow!("embedding profile not found: {profile_id}"));
        }

        conn.execute(
            r#"UPDATE embedding_profiles SET is_active = 0 WHERE id != ?1"#,
            params![profile_id],
        )?;

        Ok(())
    })();

    match result {
        Ok(()) => {
            conn.execute_batch("COMMIT;")?;
            Ok(())
        }
        Err(e) => {
            let _ = conn.execute_batch("ROLLBACK;");
            Err(e)
        }
    }
}

pub fn delete_llm_profile(conn: &Connection, profile_id: &str) -> Result<()> {
    let deleted = conn.execute(
        r#"DELETE FROM llm_profiles WHERE id = ?1"#,
        params![profile_id],
    )?;

    if deleted == 0 {
        return Err(anyhow!("llm profile not found: {profile_id}"));
    }

    Ok(())
}

pub fn delete_embedding_profile(conn: &Connection, profile_id: &str) -> Result<()> {
    let deleted = conn.execute(
        r#"DELETE FROM embedding_profiles WHERE id = ?1"#,
        params![profile_id],
    )?;

    if deleted == 0 {
        return Err(anyhow!("embedding profile not found: {profile_id}"));
    }

    Ok(())
}

pub fn load_active_llm_profile_config(
    conn: &Connection,
    key: &[u8; 32],
) -> Result<Option<(String, LlmProfileConfig)>> {
    let row = conn
        .query_row(
            r#"SELECT id, provider_type, base_url, api_key, model_name
               FROM llm_profiles
               WHERE is_active = 1
               ORDER BY updated_at DESC
               LIMIT 1"#,
            [],
            |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, Option<String>>(2)?,
                    row.get::<_, Option<Vec<u8>>>(3)?,
                    row.get::<_, String>(4)?,
                ))
            },
        )
        .optional()?;

    let Some((id, provider_type, base_url, api_key_blob, model_name)) = row else {
        return Ok(None);
    };

    let api_key = match api_key_blob {
        Some(blob) => {
            let api_key_bytes = decrypt_bytes(key, &blob, format!("llm.api_key:{id}").as_bytes())?;

            Some(
                String::from_utf8(api_key_bytes)
                    .map_err(|_| anyhow!("llm api_key is not valid utf-8"))?,
            )
        }
        None => None,
    };

    Ok(Some((
        id,
        LlmProfileConfig {
            provider_type,
            base_url,
            api_key,
            model_name,
        },
    )))
}

pub fn load_active_embedding_profile_config(
    conn: &Connection,
    key: &[u8; 32],
) -> Result<Option<(String, EmbeddingProfileConfig)>> {
    let row = conn
        .query_row(
            r#"SELECT id, provider_type, base_url, api_key, model_name
               FROM embedding_profiles
               WHERE is_active = 1
               ORDER BY updated_at DESC
               LIMIT 1"#,
            [],
            |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, Option<String>>(2)?,
                    row.get::<_, Option<Vec<u8>>>(3)?,
                    row.get::<_, String>(4)?,
                ))
            },
        )
        .optional()?;

    let Some((id, provider_type, base_url, api_key_blob, model_name)) = row else {
        return Ok(None);
    };

    let api_key = match api_key_blob {
        Some(blob) => {
            let api_key_bytes =
                decrypt_bytes(key, &blob, format!("embedding.api_key:{id}").as_bytes())?;

            Some(
                String::from_utf8(api_key_bytes)
                    .map_err(|_| anyhow!("embedding api_key is not valid utf-8"))?,
            )
        }
        None => None,
    };

    Ok(Some((
        id,
        EmbeddingProfileConfig {
            provider_type,
            base_url,
            api_key,
            model_name,
        },
    )))
}

pub fn record_llm_usage_daily(
    conn: &Connection,
    day: &str,
    profile_id: &str,
    purpose: &str,
    input_tokens: Option<i64>,
    output_tokens: Option<i64>,
    total_tokens: Option<i64>,
) -> Result<()> {
    let now = now_ms();

    let has_usage = input_tokens.is_some() && output_tokens.is_some() && total_tokens.is_some();
    let requests_with_usage = if has_usage { 1 } else { 0 };

    conn.execute(
        r#"INSERT INTO llm_usage_daily
           (day, profile_id, purpose, requests, requests_with_usage, input_tokens, output_tokens, total_tokens, created_at_ms, updated_at_ms)
           VALUES (?1, ?2, ?3, 1, ?4, ?5, ?6, ?7, ?8, ?8)
           ON CONFLICT(day, profile_id, purpose) DO UPDATE SET
             requests = llm_usage_daily.requests + excluded.requests,
             requests_with_usage = llm_usage_daily.requests_with_usage + excluded.requests_with_usage,
             input_tokens = llm_usage_daily.input_tokens + excluded.input_tokens,
             output_tokens = llm_usage_daily.output_tokens + excluded.output_tokens,
             total_tokens = llm_usage_daily.total_tokens + excluded.total_tokens,
             updated_at_ms = excluded.updated_at_ms"#,
        params![
            day,
            profile_id,
            purpose,
            requests_with_usage,
            input_tokens.unwrap_or(0),
            output_tokens.unwrap_or(0),
            total_tokens.unwrap_or(0),
            now
        ],
    )?;

    Ok(())
}

pub fn sum_llm_usage_daily_by_purpose(
    conn: &Connection,
    profile_id: &str,
    start_day: &str,
    end_day: &str,
) -> Result<Vec<LlmUsageAggregate>> {
    let mut stmt = conn.prepare(
        r#"SELECT purpose,
                  COALESCE(SUM(requests), 0),
                  COALESCE(SUM(requests_with_usage), 0),
                  COALESCE(SUM(input_tokens), 0),
                  COALESCE(SUM(output_tokens), 0),
                  COALESCE(SUM(total_tokens), 0)
           FROM llm_usage_daily
           WHERE profile_id = ?1
             AND day >= ?2
             AND day <= ?3
           GROUP BY purpose
           ORDER BY purpose ASC"#,
    )?;

    let mut rows = stmt.query(params![profile_id, start_day, end_day])?;
    let mut out = Vec::new();
    while let Some(row) = rows.next()? {
        out.push(LlmUsageAggregate {
            purpose: row.get(0)?,
            requests: row.get(1)?,
            requests_with_usage: row.get(2)?,
            input_tokens: row.get(3)?,
            output_tokens: row.get(4)?,
            total_tokens: row.get(5)?,
        });
    }

    Ok(out)
}

fn default_embedding_model_name_for_platform() -> &'static str {
    if cfg!(any(
        target_os = "windows",
        target_os = "macos",
        target_os = "linux"
    )) {
        crate::embedding::PRODUCTION_MODEL_NAME
    } else {
        crate::embedding::DEFAULT_MODEL_NAME
    }
}

fn normalize_embedding_model_name(name: &str) -> &'static str {
    match name {
        crate::embedding::DEFAULT_MODEL_NAME => crate::embedding::DEFAULT_MODEL_NAME,
        crate::embedding::PRODUCTION_MODEL_NAME => crate::embedding::PRODUCTION_MODEL_NAME,
        _ => default_embedding_model_name_for_platform(),
    }
}

fn desired_embedding_model_name(conn: &Connection) -> Result<&'static str> {
    let stored = get_active_embedding_model_name(conn)?;
    Ok(stored
        .as_deref()
        .map(normalize_embedding_model_name)
        .unwrap_or_else(default_embedding_model_name_for_platform))
}

fn default_embed_text(text: &str) -> Vec<f32> {
    let mut v = vec![0.0f32; DEFAULT_EMBEDDING_DIM];
    let t = text.to_lowercase();

    if t.contains("apple") {
        v[0] += 1.0;
    }
    if t.contains("pie") {
        v[0] += 1.0;
    }
    if t.contains("banana") {
        v[1] += 1.0;
    }

    v
}

