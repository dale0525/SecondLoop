const KV_MEDIA_ANNOTATION_ANNOTATE_ENABLED: &str = "media_annotation.annotate_enabled";
const KV_MEDIA_ANNOTATION_SEARCH_ENABLED: &str = "media_annotation.search_enabled";
const KV_MEDIA_ANNOTATION_ALLOW_CELLULAR: &str = "media_annotation.allow_cellular";
const KV_MEDIA_ANNOTATION_PROVIDER_MODE: &str = "media_annotation.provider_mode";
const KV_MEDIA_ANNOTATION_BYOK_PROFILE_ID: &str = "media_annotation.byok_profile_id";
const KV_MEDIA_ANNOTATION_CLOUD_MODEL_NAME: &str = "media_annotation.cloud_model_name";

#[derive(Clone, Debug)]
pub struct MediaAnnotationConfig {
    pub annotate_enabled: bool,
    pub search_enabled: bool,
    pub allow_cellular: bool,
    pub provider_mode: String,
    pub byok_profile_id: Option<String>,
    pub cloud_model_name: Option<String>,
}

fn kv_bool_or_media_annotation(conn: &Connection, key: &str, default: bool) -> Result<bool> {
    let raw = kv_get_string(conn, key)?;
    Ok(match raw.as_deref() {
        None => default,
        Some(v) => v.trim() == "1",
    })
}

fn normalize_provider_mode(mode: &str) -> Result<&'static str> {
    match mode.trim() {
        "" | "follow_ask_ai" => Ok("follow_ask_ai"),
        "cloud_gateway" => Ok("cloud_gateway"),
        "byok_profile" => Ok("byok_profile"),
        other => Err(anyhow!("unknown media_annotation.provider_mode: {other}")),
    }
}

fn normalize_optional_string(value: Option<String>) -> Option<String> {
    let trimmed = value?.trim().to_string();
    if trimmed.is_empty() {
        return None;
    }
    Some(trimmed)
}

pub fn get_media_annotation_config(conn: &Connection) -> Result<MediaAnnotationConfig> {
    let annotate_enabled =
        kv_bool_or_media_annotation(conn, KV_MEDIA_ANNOTATION_ANNOTATE_ENABLED, true)?;
    let search_enabled =
        kv_bool_or_media_annotation(conn, KV_MEDIA_ANNOTATION_SEARCH_ENABLED, true)?;
    let allow_cellular =
        kv_bool_or_media_annotation(conn, KV_MEDIA_ANNOTATION_ALLOW_CELLULAR, false)?;

    let provider_mode = kv_get_string(conn, KV_MEDIA_ANNOTATION_PROVIDER_MODE)?
        .unwrap_or_else(|| "follow_ask_ai".to_string());
    let provider_mode = normalize_provider_mode(&provider_mode)?.to_string();

    let byok_profile_id =
        normalize_optional_string(kv_get_string(conn, KV_MEDIA_ANNOTATION_BYOK_PROFILE_ID)?);
    let cloud_model_name =
        normalize_optional_string(kv_get_string(conn, KV_MEDIA_ANNOTATION_CLOUD_MODEL_NAME)?);

    Ok(MediaAnnotationConfig {
        annotate_enabled,
        search_enabled,
        allow_cellular,
        provider_mode,
        byok_profile_id,
        cloud_model_name,
    })
}

fn mark_all_memory_messages_for_reembedding(conn: &Connection) -> Result<()> {
    conn.execute(
        r#"
UPDATE messages
SET needs_embedding = 1
WHERE COALESCE(is_deleted, 0) = 0
  AND COALESCE(is_memory, 1) = 1
"#,
        [],
    )?;
    Ok(())
}

pub fn set_media_annotation_config(conn: &Connection, config: &MediaAnnotationConfig) -> Result<()> {
    let previous_search_enabled =
        kv_bool_or_media_annotation(conn, KV_MEDIA_ANNOTATION_SEARCH_ENABLED, true)?;

    conn.execute_batch("BEGIN IMMEDIATE;")?;

    let result = (|| -> Result<()> {
        kv_set_string(
            conn,
            KV_MEDIA_ANNOTATION_ANNOTATE_ENABLED,
            if config.annotate_enabled { "1" } else { "0" },
        )?;
        kv_set_string(
            conn,
            KV_MEDIA_ANNOTATION_SEARCH_ENABLED,
            if config.search_enabled { "1" } else { "0" },
        )?;
        kv_set_string(
            conn,
            KV_MEDIA_ANNOTATION_ALLOW_CELLULAR,
            if config.allow_cellular { "1" } else { "0" },
        )?;
        kv_set_string(
            conn,
            KV_MEDIA_ANNOTATION_PROVIDER_MODE,
            normalize_provider_mode(&config.provider_mode)?,
        )?;

        match normalize_optional_string(config.byok_profile_id.clone()) {
            Some(id) => kv_set_string(conn, KV_MEDIA_ANNOTATION_BYOK_PROFILE_ID, &id)?,
            None => {
                conn.execute(
                    r#"DELETE FROM kv WHERE key = ?1"#,
                    params![KV_MEDIA_ANNOTATION_BYOK_PROFILE_ID],
                )?;
            }
        }
        match normalize_optional_string(config.cloud_model_name.clone()) {
            Some(name) => kv_set_string(conn, KV_MEDIA_ANNOTATION_CLOUD_MODEL_NAME, &name)?,
            None => {
                conn.execute(
                    r#"DELETE FROM kv WHERE key = ?1"#,
                    params![KV_MEDIA_ANNOTATION_CLOUD_MODEL_NAME],
                )?;
            }
        }

        if previous_search_enabled != config.search_enabled {
            mark_all_memory_messages_for_reembedding(conn)?;
        }

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
