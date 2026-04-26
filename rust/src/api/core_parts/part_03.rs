#[flutter_rust_bridge::frb]
pub fn db_read_attachment_variant_bytes(
    app_dir: String,
    key: Vec<u8>,
    attachment_sha256: String,
    variant: String,
) -> Result<Vec<u8>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::read_attachment_variant_bytes(
        &conn,
        &key,
        Path::new(&app_dir),
        &attachment_sha256,
        &variant,
    )
}

#[flutter_rust_bridge::frb]
pub fn db_enqueue_cloud_media_backup(
    app_dir: String,
    key: Vec<u8>,
    attachment_sha256: String,
    desired_variant: String,
    now_ms: i64,
    scope_id: Option<String>,
) -> Result<()> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::enqueue_cloud_media_backup(
        &conn,
        &attachment_sha256,
        &desired_variant,
        now_ms,
        scope_id.as_deref(),
    )
}

#[flutter_rust_bridge::frb]
pub fn db_backfill_cloud_media_backup_images(
    app_dir: String,
    key: Vec<u8>,
    desired_variant: String,
    now_ms: i64,
    scope_id: Option<String>,
) -> Result<u64> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::backfill_cloud_media_backup_images(&conn, &desired_variant, now_ms, scope_id.as_deref())
}

#[flutter_rust_bridge::frb]
pub fn db_list_due_cloud_media_backups(
    app_dir: String,
    key: Vec<u8>,
    now_ms: i64,
    limit: u32,
    scope_id: Option<String>,
) -> Result<Vec<db::CloudMediaBackup>> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_due_cloud_media_backups(&conn, now_ms, limit as i64, scope_id.as_deref())
}

#[flutter_rust_bridge::frb]
pub fn db_mark_cloud_media_backup_failed(
    app_dir: String,
    key: Vec<u8>,
    attachment_sha256: String,
    attempts: i64,
    next_retry_at_ms: i64,
    last_error: String,
    now_ms: i64,
    scope_id: Option<String>,
) -> Result<()> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::mark_cloud_media_backup_failed(
        &conn,
        &attachment_sha256,
        attempts,
        next_retry_at_ms,
        &last_error,
        now_ms,
        scope_id.as_deref(),
    )
}

#[flutter_rust_bridge::frb]
pub fn db_mark_cloud_media_backup_uploaded(
    app_dir: String,
    key: Vec<u8>,
    attachment_sha256: String,
    now_ms: i64,
    scope_id: Option<String>,
) -> Result<()> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::mark_cloud_media_backup_uploaded(&conn, &attachment_sha256, now_ms, scope_id.as_deref())
}

#[flutter_rust_bridge::frb]
pub fn db_cloud_media_backup_summary(
    app_dir: String,
    key: Vec<u8>,
    scope_id: Option<String>,
) -> Result<db::CloudMediaBackupSummary> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::cloud_media_backup_summary(&conn, scope_id.as_deref())
}

#[flutter_rust_bridge::frb]
pub fn db_reset_vault_data_preserving_llm_profiles(app_dir: String, key: Vec<u8>) -> Result<()> {
    let app_dir = Path::new(&app_dir);
    let key = key_from_bytes(key)?;
    crate::api::auth_state::validate_reset_vault_data_access(app_dir, &key)?;
    let conn = db::open(app_dir)?;
    db::reset_vault_data_preserving_llm_profiles(&conn)
}

#[flutter_rust_bridge::frb]
pub fn db_get_or_create_device_id(app_dir: String) -> Result<String> {
    let conn = db::open(Path::new(&app_dir))?;
    db::get_or_create_device_id(&conn)
}

#[flutter_rust_bridge::frb]
pub fn db_create_llm_profile(
    app_dir: String,
    key: Vec<u8>,
    name: String,
    provider_type: String,
    base_url: Option<String>,
    api_key: Option<String>,
    model_name: String,
    set_active: bool,
) -> Result<db::LlmProfile> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::create_llm_profile(
        &conn,
        &key,
        &name,
        &provider_type,
        base_url.as_deref(),
        api_key.as_deref(),
        &model_name,
        set_active,
    )
}

#[flutter_rust_bridge::frb]
pub fn db_list_llm_profiles(app_dir: String, key: Vec<u8>) -> Result<Vec<db::LlmProfile>> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_llm_profiles(&conn)
}

#[flutter_rust_bridge::frb]
pub fn db_set_active_llm_profile(app_dir: String, key: Vec<u8>, profile_id: String) -> Result<()> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::set_active_llm_profile(&conn, &profile_id)
}

#[flutter_rust_bridge::frb]
pub fn db_delete_llm_profile(app_dir: String, key: Vec<u8>, profile_id: String) -> Result<()> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::delete_llm_profile(&conn, &profile_id)
}

#[flutter_rust_bridge::frb]
pub fn db_create_embedding_profile(
    app_dir: String,
    key: Vec<u8>,
    name: String,
    provider_type: String,
    base_url: Option<String>,
    api_key: Option<String>,
    model_name: String,
    set_active: bool,
) -> Result<db::EmbeddingProfile> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::create_embedding_profile(
        &conn,
        &key,
        &name,
        &provider_type,
        base_url.as_deref(),
        api_key.as_deref(),
        &model_name,
        set_active,
    )
}

#[flutter_rust_bridge::frb]
pub fn db_list_embedding_profiles(
    app_dir: String,
    key: Vec<u8>,
) -> Result<Vec<db::EmbeddingProfile>> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_embedding_profiles(&conn)
}

#[flutter_rust_bridge::frb]
pub fn db_set_active_embedding_profile(
    app_dir: String,
    key: Vec<u8>,
    profile_id: String,
) -> Result<()> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::set_active_embedding_profile(&conn, &profile_id)
}

#[flutter_rust_bridge::frb]
pub fn db_delete_embedding_profile(
    app_dir: String,
    key: Vec<u8>,
    profile_id: String,
) -> Result<()> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::delete_embedding_profile(&conn, &profile_id)
}

#[flutter_rust_bridge::frb]
pub fn db_process_pending_message_embeddings(
    app_dir: String,
    key: Vec<u8>,
    limit: u32,
) -> Result<u32> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let processed = db::process_pending_message_embeddings_active(
        &conn,
        &key,
        Path::new(&app_dir),
        limit as usize,
    )?;
    Ok(processed as u32)
}

#[flutter_rust_bridge::frb]
pub fn db_process_pending_todo_thread_embeddings(
    app_dir: String,
    key: Vec<u8>,
    todo_limit: u32,
    activity_limit: u32,
) -> Result<u32> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let todos = db::process_pending_todo_embeddings_active(
        &conn,
        &key,
        Path::new(&app_dir),
        todo_limit as usize,
    )?;
    let activities = db::process_pending_todo_activity_embeddings_active(
        &conn,
        &key,
        Path::new(&app_dir),
        activity_limit as usize,
    )?;
    Ok(todos.saturating_add(activities) as u32)
}

#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub fn db_process_pending_todo_thread_embeddings_cloud_gateway(
    app_dir: String,
    key: Vec<u8>,
    todo_limit: u32,
    activity_limit: u32,
    gateway_base_url: String,
    firebase_id_token: String,
    model_name: String,
) -> Result<u32> {
    let gateway_base_url = gateway_base_url.trim().to_string();
    if gateway_base_url.is_empty() {
        return Err(anyhow!("missing gateway_base_url"));
    }
    let firebase_id_token = firebase_id_token.trim().to_string();
    if firebase_id_token.is_empty() {
        return Err(anyhow!("missing firebase_id_token"));
    }
    let requested_model_name = model_name.trim().to_string();
    if requested_model_name.is_empty() {
        return Err(anyhow!("missing model_name"));
    }

    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    remote_embedding_bootstrap::process_cloud_gateway_pending_todo_thread_embeddings(
        &conn,
        &key,
        todo_limit as usize,
        activity_limit as usize,
        &gateway_base_url,
        &firebase_id_token,
        &requested_model_name,
    )
}

#[flutter_rust_bridge::frb]
pub fn db_process_pending_todo_thread_embeddings_brok(
    app_dir: String,
    key: Vec<u8>,
    todo_limit: u32,
    activity_limit: u32,
) -> Result<u32> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;

    let (_profile_id, profile) = db::load_active_embedding_profile_config(&conn, &key)?
        .ok_or_else(|| anyhow!("no active embedding profile configured"))?;

    if profile.provider_type != "openai-compatible" {
        return Err(anyhow!(
            "unsupported embedding provider_type: {}",
            profile.provider_type
        ));
    }

    let base_url = profile
        .base_url
        .filter(|v| !v.trim().is_empty())
        .ok_or_else(|| anyhow!("missing embedding base_url"))?;
    let api_key = profile
        .api_key
        .filter(|v| !v.trim().is_empty())
        .ok_or_else(|| anyhow!("missing embedding api_key"))?;
    let model_name = profile.model_name;

    remote_embedding_bootstrap::process_brok_pending_todo_thread_embeddings(
        &conn,
        &key,
        todo_limit as usize,
        activity_limit as usize,
        &base_url,
        &api_key,
        &model_name,
    )
}

#[flutter_rust_bridge::frb]
pub fn db_search_similar_messages(
    app_dir: String,
    key: Vec<u8>,
    query: String,
    top_k: u32,
) -> Result<Vec<db::SimilarMessage>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::search_similar_messages_active(&conn, &key, Path::new(&app_dir), &query, top_k as usize)
}

#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub fn db_search_similar_messages_cloud_gateway(
    app_dir: String,
    key: Vec<u8>,
    query: String,
    top_k: u32,
    gateway_base_url: String,
    firebase_id_token: String,
    model_name: String,
) -> Result<Vec<db::SimilarMessage>> {
    if gateway_base_url.trim().is_empty() {
        return Err(anyhow!("missing gateway_base_url"));
    }
    if firebase_id_token.trim().is_empty() {
        return Err(anyhow!("missing firebase_id_token"));
    }
    if model_name.trim().is_empty() {
        return Err(anyhow!("missing model_name"));
    }

    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let embedder =
        embedding::CloudGatewayEmbedder::new(gateway_base_url, firebase_id_token, model_name);

    // Avoid wiping the current index if the embedder is misconfigured/unreachable.
    let probe = embedder.embed(&[format!("query: {query}")])?;
    let dim = probe.first().map(|v| v.len()).unwrap_or(0);
    if dim == 0 {
        return Err(anyhow!("cloud-gateway embedder returned empty embeddings"));
    }

    // Best-effort: keep the index reasonably fresh without blocking too long.
    db::set_active_embedding_model(&conn, embedder.model_name(), dim)?;
    db::process_pending_message_embeddings(&conn, &key, &embedder, 64)?;
    db::process_pending_todo_embeddings(&conn, &key, &embedder, 64)?;
    db::process_pending_todo_activity_embeddings(&conn, &key, &embedder, 128)?;

    db::search_similar_messages(&conn, &key, &embedder, &query, top_k as usize)
}

#[flutter_rust_bridge::frb]
pub fn db_search_similar_messages_brok(
    app_dir: String,
    key: Vec<u8>,
    query: String,
    top_k: u32,
) -> Result<Vec<db::SimilarMessage>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;

    let (_profile_id, profile) = db::load_active_embedding_profile_config(&conn, &key)?
        .ok_or_else(|| anyhow!("no active embedding profile configured"))?;

    if profile.provider_type != "openai-compatible" {
        return Err(anyhow!(
            "unsupported embedding provider_type: {}",
            profile.provider_type
        ));
    }

    let base_url = profile
        .base_url
        .filter(|v| !v.trim().is_empty())
        .ok_or_else(|| anyhow!("missing embedding base_url"))?;
    let api_key = profile
        .api_key
        .filter(|v| !v.trim().is_empty())
        .ok_or_else(|| anyhow!("missing embedding api_key"))?;
    let model_name = profile.model_name;

    let embedder = embedding::BrokEmbedder::new(base_url, api_key, model_name);

    // Avoid wiping the current index if the embedder is misconfigured/unreachable.
    let probe = embedder.embed(&[format!("query: {query}")])?;
    let dim = probe.first().map(|v| v.len()).unwrap_or(0);
    if dim == 0 {
        return Err(anyhow!("brok embedder returned empty embeddings"));
    }

    // Best-effort: keep the index reasonably fresh without blocking too long.
    db::set_active_embedding_model(&conn, embedder.model_name(), dim)?;
    db::process_pending_message_embeddings(&conn, &key, &embedder, 64)?;
    db::process_pending_todo_embeddings(&conn, &key, &embedder, 64)?;
    db::process_pending_todo_activity_embeddings(&conn, &key, &embedder, 128)?;

    db::search_similar_messages(&conn, &key, &embedder, &query, top_k as usize)
}

#[flutter_rust_bridge::frb]
pub fn db_search_similar_todo_threads(
    app_dir: String,
    key: Vec<u8>,
    query: String,
    top_k: u32,
) -> Result<Vec<db::SimilarTodoThread>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::search_similar_todo_threads_active(&conn, &key, Path::new(&app_dir), &query, top_k as usize)
}

#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub fn db_search_similar_todo_threads_cloud_gateway(
    app_dir: String,
    key: Vec<u8>,
    query: String,
    top_k: u32,
    gateway_base_url: String,
    firebase_id_token: String,
    model_name: String,
) -> Result<Vec<db::SimilarTodoThread>> {
    if gateway_base_url.trim().is_empty() {
        return Err(anyhow!("missing gateway_base_url"));
    }
    if firebase_id_token.trim().is_empty() {
        return Err(anyhow!("missing firebase_id_token"));
    }
    if model_name.trim().is_empty() {
        return Err(anyhow!("missing model_name"));
    }

    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let embedder =
        embedding::CloudGatewayEmbedder::new(gateway_base_url, firebase_id_token, model_name);

    // Avoid wiping the current index if the embedder is misconfigured/unreachable.
    let mut vectors = embedder.embed(&[format!("query: {query}")])?;
    if vectors.len() != 1 {
        return Err(anyhow!(
            "cloud-gateway embedder output length mismatch: expected 1, got {}",
            vectors.len()
        ));
    }
    let dim = vectors.first().map(|v| v.len()).unwrap_or(0);
    if dim == 0 {
        return Err(anyhow!("cloud-gateway embedder returned empty embeddings"));
    }
    let query_vector = vectors.pop().unwrap();

    db::set_active_embedding_model(&conn, embedder.model_name(), dim)?;
    db::search_similar_todo_threads_by_embedding(
        &conn,
        embedder.model_name(),
        &query_vector,
        top_k as usize,
    )
}

#[flutter_rust_bridge::frb]
pub fn db_search_similar_todo_threads_brok(
    app_dir: String,
    key: Vec<u8>,
    query: String,
    top_k: u32,
) -> Result<Vec<db::SimilarTodoThread>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;

    let (_profile_id, profile) = db::load_active_embedding_profile_config(&conn, &key)?
        .ok_or_else(|| anyhow!("no active embedding profile configured"))?;

    if profile.provider_type != "openai-compatible" {
        return Err(anyhow!(
            "unsupported embedding provider_type: {}",
            profile.provider_type
        ));
    }

    let base_url = profile
        .base_url
        .filter(|v| !v.trim().is_empty())
        .ok_or_else(|| anyhow!("missing embedding base_url"))?;
    let api_key = profile
        .api_key
        .filter(|v| !v.trim().is_empty())
        .ok_or_else(|| anyhow!("missing embedding api_key"))?;
    let model_name = profile.model_name;

    let embedder = embedding::BrokEmbedder::new(base_url, api_key, model_name);

    // Avoid wiping the current index if the embedder is misconfigured/unreachable.
    let mut vectors = embedder.embed(&[format!("query: {query}")])?;
    if vectors.len() != 1 {
        return Err(anyhow!(
            "brok embedder output length mismatch: expected 1, got {}",
            vectors.len()
        ));
    }
    let dim = vectors.first().map(|v| v.len()).unwrap_or(0);
    if dim == 0 {
        return Err(anyhow!("brok embedder returned empty embeddings"));
    }
    let query_vector = vectors.pop().unwrap();

    db::set_active_embedding_model(&conn, embedder.model_name(), dim)?;
    db::search_similar_todo_threads_by_embedding(
        &conn,
        embedder.model_name(),
        &query_vector,
        top_k as usize,
    )
}

#[flutter_rust_bridge::frb]
pub fn db_rebuild_message_embeddings(
    app_dir: String,
    key: Vec<u8>,
    batch_limit: u32,
) -> Result<u32> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let rebuilt = db::rebuild_message_embeddings_active(
        &conn,
        &key,
        Path::new(&app_dir),
        batch_limit as usize,
    )?;
    Ok(rebuilt as u32)
}

#[flutter_rust_bridge::frb]
pub fn db_list_embedding_model_names(app_dir: String, key: Vec<u8>) -> Result<Vec<String>> {
    let _key = key_from_bytes(key)?;
    let _conn = db::open(Path::new(&app_dir))?;

    let mut models = vec![embedding::DEFAULT_MODEL_NAME.to_string()];
    if cfg!(any(
        target_os = "windows",
        target_os = "macos",
        target_os = "linux"
    )) {
        models.push(embedding::PRODUCTION_MODEL_NAME.to_string());
    }
    Ok(models)
}

#[flutter_rust_bridge::frb]
pub fn db_get_active_embedding_model_name(app_dir: String, key: Vec<u8>) -> Result<String> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;

    let stored = db::get_active_embedding_model_name(&conn)?;
    let model_name = stored
        .as_deref()
        .map(normalize_embedding_model_name)
        .unwrap_or_else(default_embedding_model_name_for_platform);
    Ok(model_name.to_string())
}

#[flutter_rust_bridge::frb]
pub fn db_set_active_embedding_model_name(
    app_dir: String,
    key: Vec<u8>,
    model_name: String,
) -> Result<bool> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;

    let desired = match model_name.as_str() {
        embedding::DEFAULT_MODEL_NAME => embedding::DEFAULT_MODEL_NAME,
        embedding::PRODUCTION_MODEL_NAME => {
            if cfg!(any(
                target_os = "windows",
                target_os = "macos",
                target_os = "linux"
            )) {
                embedding::PRODUCTION_MODEL_NAME
            } else {
                return Err(anyhow!(
                    "production embeddings are not supported on this platform"
                ));
            }
        }
        _ => return Err(anyhow!("unknown embedding model: {model_name}")),
    };

    db::set_active_embedding_model_name(&conn, desired)
}

#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub fn db_record_llm_usage_daily(
    app_dir: String,
    key: Vec<u8>,
    day: String,
    profile_id: String,
    purpose: String,
    input_tokens: Option<i64>,
    output_tokens: Option<i64>,
    total_tokens: Option<i64>,
) -> Result<()> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::record_llm_usage_daily(
        &conn,
        day.trim(),
        &profile_id,
        &purpose,
        input_tokens,
        output_tokens,
        total_tokens,
    )
}

#[flutter_rust_bridge::frb]
pub fn db_sum_llm_usage_daily_by_purpose(
    app_dir: String,
    key: Vec<u8>,
    profile_id: String,
    start_day: String,
    end_day: String,
) -> Result<Vec<db::LlmUsageAggregate>> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::sum_llm_usage_daily_by_purpose(&conn, &profile_id, start_day.trim(), end_day.trim())
}

#[flutter_rust_bridge::frb]
pub fn ai_task_priority_rerank(
    app_dir: String,
    key: Vec<u8>,
    prompt: String,
    local_day: String,
) -> Result<String> {
    let result = (|| -> Result<String> {
        let key = key_from_bytes(key)?;
        let conn = db::open(Path::new(&app_dir))?;

        let (profile_id, profile) = db::load_active_llm_profile_config(&conn, &key)?
            .ok_or_else(|| anyhow!("no active LLM profile configured"))?;

        let provider = llm::answer_provider_from_profile(&profile)?;
        let result = collect_provider_text(provider.as_ref(), &prompt);

        match result {
            Ok(output) => {
                let day = local_day.trim();
                if !day.is_empty() {
                    let _ = db::record_llm_usage_daily(
                        &conn,
                        day,
                        &profile_id,
                        "task_priority",
                        None,
                        None,
                        None,
                    );
                }
                Ok(output)
            }
            Err(e) => {
                let day = local_day.trim();
                if !day.is_empty() {
                    let _ = db::record_llm_usage_daily(
                        &conn,
                        day,
                        &profile_id,
                        "task_priority",
                        None,
                        None,
                        None,
                    );
                }
                Err(e)
            }
        }
    })();

    result
}

#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub fn ai_task_priority_rerank_cloud_gateway(
    _app_dir: String,
    key: Vec<u8>,
    prompt: String,
    gateway_base_url: String,
    firebase_id_token: String,
    model_name: String,
) -> Result<String> {
    if gateway_base_url.trim().is_empty() {
        return Err(anyhow!("missing gateway_base_url"));
    }
    if firebase_id_token.trim().is_empty() {
        return Err(anyhow!("missing firebase_id_token"));
    }

    let _key = key_from_bytes(key)?;

    // Cloud gateway semantic-parse usage is tagged server-side via the provider
    // purpose. We intentionally do not write a local `llm_usage_daily` row here
    // because this route does not depend on a local active LLM profile id or local
    // token accounting.
    let provider = llm::gateway::CloudGatewayProvider::new_with_purpose(
        gateway_base_url,
        firebase_id_token,
        model_name,
        None,
        "task_priority".to_string(),
    );

    collect_provider_text(&provider, &prompt)
}

#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub fn ai_todo_followup_rerank_cloud_gateway(
    _app_dir: String,
    key: Vec<u8>,
    prompt: String,
    gateway_base_url: String,
    firebase_id_token: String,
    model_name: String,
) -> Result<String> {
    if gateway_base_url.trim().is_empty() {
        return Err(anyhow!("missing gateway_base_url"));
    }
    if firebase_id_token.trim().is_empty() {
        return Err(anyhow!("missing firebase_id_token"));
    }

    let _key = key_from_bytes(key)?;

    let provider = llm::gateway::CloudGatewayProvider::new_with_purpose(
        gateway_base_url,
        firebase_id_token,
        model_name,
        None,
        "todo_followup".to_string(),
    );

    collect_provider_text(&provider, &prompt)
}

#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub fn ai_semantic_parse_message_action(
    app_dir: String,
    key: Vec<u8>,
    text: String,
    now_local_iso: String,
    locale: String,
    day_end_minutes: i32,
    candidates: Vec<semantic_parse::TodoCandidate>,
    local_day: String,
) -> Result<String> {
    let result = (|| -> Result<String> {
        let key = key_from_bytes(key)?;
        let conn = db::open(Path::new(&app_dir))?;

        let (profile_id, profile) = db::load_active_llm_profile_config(&conn, &key)?
            .ok_or_else(|| anyhow!("no active LLM profile configured"))?;
        let available_tags = db::list_available_tags_for_semantic_parse(&conn, &key, 200)?;

        let provider = llm::answer_provider_from_profile(&profile)?;
        let result = semantic_parse::semantic_parse_message_action_json(
            provider.as_ref(),
            &text,
            now_local_iso.trim(),
            locale.trim(),
            day_end_minutes,
            &candidates,
            &available_tags,
        );

        match result {
            Ok(json) => {
                let day = local_day.trim();
                if !day.is_empty() {
                    let _ = db::record_llm_usage_daily(
                        &conn,
                        day,
                        &profile_id,
                        "semantic_parse",
                        None,
                        None,
                        None,
                    );
                }
                Ok(json)
            }
            Err(e) => {
                let day = local_day.trim();
                if !day.is_empty() {
                    let _ = db::record_llm_usage_daily(
                        &conn,
                        day,
                        &profile_id,
                        "semantic_parse",
                        None,
                        None,
                        None,
                    );
                }
                Err(e)
            }
        }
    })();

    result
}
