use std::path::Path;

use anyhow::{anyhow, Result};

use crate::{db, llm, url_enrichment_ai};

fn key_from_bytes(bytes: Vec<u8>) -> Result<[u8; 32]> {
    if bytes.len() != 32 {
        return Err(anyhow!("invalid key length"));
    }
    let mut key = [0u8; 32];
    key.copy_from_slice(&bytes);
    Ok(key)
}

#[flutter_rust_bridge::frb]
pub fn db_get_media_annotation_config(
    app_dir: String,
    key: Vec<u8>,
) -> Result<db::MediaAnnotationConfig> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::get_media_annotation_config(&conn)
}

#[flutter_rust_bridge::frb]
pub fn db_set_media_annotation_config(
    app_dir: String,
    key: Vec<u8>,
    config: db::MediaAnnotationConfig,
) -> Result<()> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::set_media_annotation_config(&conn, &config)
}

#[flutter_rust_bridge::frb]
pub fn media_annotation_byok_profile(
    app_dir: String,
    key: Vec<u8>,
    profile_id: String,
    local_day: String,
    lang: String,
    mime_type: String,
    image_bytes: Vec<u8>,
) -> Result<String> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;

    let profile = db::load_llm_profile_config_by_id(&conn, &key, profile_id.trim())?
        .ok_or_else(|| anyhow!("llm profile not found: {profile_id}"))?;

    if profile.provider_type != "openai-compatible" {
        return Err(anyhow!(
            "media annotation byok v1 only supports provider_type=openai-compatible (got {})",
            profile.provider_type
        ));
    }

    let base_url = profile
        .base_url
        .ok_or_else(|| anyhow!("missing base_url for llm profile: {profile_id}"))?;
    let api_key = profile
        .api_key
        .ok_or_else(|| anyhow!("missing api_key for llm profile: {profile_id}"))?;

    let client = crate::media_annotation::OpenAiCompatibleMediaAnnotationClient::new(
        base_url,
        api_key,
        profile.model_name,
    );

    let result = client.annotate_image_with_usage(&lang, &mime_type, &image_bytes);

    let trimmed_day = local_day.trim();
    if !trimmed_day.is_empty() {
        match &result {
            Ok((_payload, usage)) => {
                let _ = db::record_llm_usage_daily(
                    &conn,
                    trimmed_day,
                    profile_id.trim(),
                    "media_annotation",
                    usage.input_tokens,
                    usage.output_tokens,
                    usage.total_tokens,
                );
            }
            Err(_) => {
                let _ = db::record_llm_usage_daily(
                    &conn,
                    trimmed_day,
                    profile_id.trim(),
                    "media_annotation",
                    None,
                    None,
                    None,
                );
            }
        }
    }

    let (payload, _usage) = result?;
    Ok(payload.to_string())
}

#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub fn url_enrichment_byok_profile(
    app_dir: String,
    key: Vec<u8>,
    profile_id: String,
    original_url: String,
    final_url: String,
    site: String,
    title: Option<String>,
    readable_text_excerpt: String,
    readable_text_full: String,
) -> Result<String> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;

    let profile = db::load_llm_profile_config_by_id(&conn, &key, profile_id.trim())?
        .ok_or_else(|| anyhow!("llm profile not found: {profile_id}"))?;

    if profile.provider_type != "openai-compatible" {
        return Err(anyhow!(
            "url enrichment byok only supports provider_type=openai-compatible (got {})",
            profile.provider_type
        ));
    }

    let provider = llm::answer_provider_from_profile(&profile)?;
    url_enrichment_ai::enrich_url_content_json(
        provider.as_ref(),
        &original_url,
        &final_url,
        &site,
        title.as_deref(),
        &readable_text_excerpt,
        &readable_text_full,
    )
}

#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub fn url_enrichment_cloud_gateway(
    app_dir: String,
    key: Vec<u8>,
    gateway_base_url: String,
    firebase_id_token: String,
    model_name: String,
    original_url: String,
    final_url: String,
    site: String,
    title: Option<String>,
    readable_text_excerpt: String,
    readable_text_full: String,
) -> Result<String> {
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
    let _conn = db::open(Path::new(&app_dir))?;
    let provider = llm::gateway::CloudGatewayProvider::new_with_purpose(
        gateway_base_url,
        firebase_id_token,
        model_name,
        None,
        "url_enrichment".to_string(),
    );

    url_enrichment_ai::enrich_url_content_json(
        &provider,
        &original_url,
        &final_url,
        &site,
        title.as_deref(),
        &readable_text_excerpt,
        &readable_text_full,
    )
}
