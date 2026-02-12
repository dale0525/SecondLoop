pub mod anthropic;
pub mod gateway;
pub mod gemini;
pub mod openai;
pub mod timeouts;

use anyhow::{anyhow, Result};

#[derive(Clone, Debug, PartialEq)]
pub struct ChatDelta {
    pub role: Option<String>,
    pub text_delta: String,
    pub done: bool,
}

pub fn answer_provider_from_profile(
    profile: &crate::db::LlmProfileConfig,
) -> Result<Box<dyn crate::rag::AnswerProvider>> {
    let provider_type = profile.provider_type.as_str();
    let model_name = profile.model_name.clone();

    match provider_type {
        "openai-compatible" => {
            let api_key = profile
                .api_key
                .clone()
                .ok_or_else(|| anyhow!("missing api_key for openai-compatible provider"))?;
            let base_url = profile
                .base_url
                .clone()
                .filter(|v| !v.trim().is_empty())
                .unwrap_or_else(|| "https://api.openai.com/v1".to_string());

            Ok(Box::new(openai::OpenAiCompatibleProvider::new(
                base_url, api_key, model_name, None,
            )))
        }
        "gemini-compatible" => {
            let api_key = profile
                .api_key
                .clone()
                .ok_or_else(|| anyhow!("missing api_key for gemini-compatible provider"))?;
            let base_url = profile
                .base_url
                .clone()
                .filter(|v| !v.trim().is_empty())
                .unwrap_or_else(|| "https://generativelanguage.googleapis.com/v1beta".to_string());

            Ok(Box::new(gemini::GeminiCompatibleProvider::new(
                base_url, api_key, model_name,
            )))
        }
        "anthropic-compatible" => {
            let api_key = profile
                .api_key
                .clone()
                .ok_or_else(|| anyhow!("missing api_key for anthropic-compatible provider"))?;
            let base_url = profile
                .base_url
                .clone()
                .filter(|v| !v.trim().is_empty())
                .unwrap_or_else(|| "https://api.anthropic.com/v1".to_string());

            Ok(Box::new(anthropic::AnthropicCompatibleProvider::new(
                base_url, api_key, model_name, 1024,
            )))
        }
        _ => Err(anyhow!("unsupported provider_type: {provider_type}")),
    }
}
