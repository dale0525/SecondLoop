use std::path::Path;

use anyhow::{anyhow, Result};

use crate::{db, llm, semantic_parse};

fn key_from_bytes(bytes: Vec<u8>) -> Result<[u8; 32]> {
    bytes
        .try_into()
        .map_err(|_| anyhow!("expected 32-byte key"))
}

#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub fn ai_semantic_parse_message_action_enhancement(
    app_dir: String,
    key: Vec<u8>,
    text: String,
    now_local_iso: String,
    locale: String,
    day_end_minutes: i32,
    local_result_json: String,
    unresolved_fields: Vec<String>,
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
        let result = semantic_parse::semantic_parse_message_action_enhancement_json(
            provider.as_ref(),
            &text,
            now_local_iso.trim(),
            locale.trim(),
            day_end_minutes,
            &local_result_json,
            &unresolved_fields,
            &candidates,
            &available_tags,
        );

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
        result
    })();

    result
}

#[flutter_rust_bridge::frb]
#[allow(clippy::too_many_arguments)]
pub fn ai_semantic_parse_message_action_enhancement_cloud_gateway(
    app_dir: String,
    key: Vec<u8>,
    text: String,
    now_local_iso: String,
    locale: String,
    day_end_minutes: i32,
    local_result_json: String,
    unresolved_fields: Vec<String>,
    candidates: Vec<semantic_parse::TodoCandidate>,
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

    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let available_tags = db::list_available_tags_for_semantic_parse(&conn, &key, 200)?;

    let provider = llm::gateway::CloudGatewayProvider::new_with_purpose(
        gateway_base_url,
        firebase_id_token,
        model_name,
        None,
        "semantic_parse".to_string(),
    );

    semantic_parse::semantic_parse_message_action_enhancement_json(
        &provider,
        &text,
        now_local_iso.trim(),
        locale.trim(),
        day_end_minutes,
        &local_result_json,
        &unresolved_fields,
        &candidates,
        &available_tags,
    )
}
