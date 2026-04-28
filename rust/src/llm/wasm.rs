use anyhow::{anyhow, Result};

#[derive(Clone, Debug, PartialEq)]
pub struct ChatDelta {
    pub role: Option<String>,
    pub text_delta: String,
    pub done: bool,
}

#[allow(dead_code)]
pub mod request_limiter {
    #[derive(Default)]
    pub(crate) struct RemoteLlmRequestGuard;

    pub(crate) fn acquire_remote_llm_request_slot() -> RemoteLlmRequestGuard {
        RemoteLlmRequestGuard
    }
}

pub mod timeouts {
    use std::time::Duration;

    const ASK_AI_TIMEOUT_MIN_SECONDS: u64 = 180;
    const ASK_AI_TIMEOUT_MAX_SECONDS: u64 = 900;
    const ASK_AI_TIMEOUT_CHARS_PER_SECOND: u64 = 250;

    const MEDIA_TIMEOUT_MIN_SECONDS: u64 = 300;
    const MEDIA_TIMEOUT_MAX_SECONDS: u64 = 1200;
    const MEDIA_TIMEOUT_BASE_SECONDS: u64 = 240;
    const MEDIA_TIMEOUT_SECONDS_PER_MIB: u64 = 90;
    const MEDIA_TIMEOUT_OCR_BONUS_SECONDS: u64 = 180;

    const AUDIO_TIMEOUT_MIN_SECONDS: u64 = 240;
    const AUDIO_TIMEOUT_MAX_SECONDS: u64 = 900;
    const AUDIO_TIMEOUT_BASE_SECONDS: u64 = 180;
    const AUDIO_TIMEOUT_SECONDS_PER_MIB: u64 = 75;
    const AUDIO_TIMEOUT_MULTIMODAL_BONUS_SECONDS: u64 = 180;

    const BYTES_PER_MIB: u64 = 1024 * 1024;

    fn clamp_timeout_seconds(seconds: u64, min_seconds: u64, max_seconds: u64) -> u64 {
        seconds.clamp(min_seconds, max_seconds)
    }

    fn ceil_mib(bytes: usize) -> u64 {
        let bytes_u64 = u64::try_from(bytes).unwrap_or(u64::MAX);
        bytes_u64.saturating_add(BYTES_PER_MIB - 1) / BYTES_PER_MIB
    }

    pub fn ask_ai_timeout_for_prompt_chars(prompt_chars: usize) -> Duration {
        let prompt_chars_u64 = u64::try_from(prompt_chars).unwrap_or(u64::MAX);
        let adaptive_seconds = ASK_AI_TIMEOUT_MIN_SECONDS
            .saturating_add(prompt_chars_u64 / ASK_AI_TIMEOUT_CHARS_PER_SECOND);

        Duration::from_secs(clamp_timeout_seconds(
            adaptive_seconds,
            ASK_AI_TIMEOUT_MIN_SECONDS,
            ASK_AI_TIMEOUT_MAX_SECONDS,
        ))
    }

    pub fn media_annotation_timeout_for_image_bytes(
        image_bytes: usize,
        ocr_markdown: bool,
    ) -> Duration {
        let size_mib = ceil_mib(image_bytes);
        let ocr_bonus = if ocr_markdown {
            MEDIA_TIMEOUT_OCR_BONUS_SECONDS
        } else {
            0
        };
        let adaptive_seconds = MEDIA_TIMEOUT_BASE_SECONDS
            .saturating_add(size_mib.saturating_mul(MEDIA_TIMEOUT_SECONDS_PER_MIB))
            .saturating_add(ocr_bonus);

        Duration::from_secs(clamp_timeout_seconds(
            adaptive_seconds,
            MEDIA_TIMEOUT_MIN_SECONDS,
            MEDIA_TIMEOUT_MAX_SECONDS,
        ))
    }

    pub fn audio_transcribe_timeout_for_audio_bytes(
        audio_bytes: usize,
        multimodal: bool,
    ) -> Duration {
        let size_mib = ceil_mib(audio_bytes);
        let multimodal_bonus = if multimodal {
            AUDIO_TIMEOUT_MULTIMODAL_BONUS_SECONDS
        } else {
            0
        };
        let adaptive_seconds = AUDIO_TIMEOUT_BASE_SECONDS
            .saturating_add(size_mib.saturating_mul(AUDIO_TIMEOUT_SECONDS_PER_MIB))
            .saturating_add(multimodal_bonus);

        Duration::from_secs(clamp_timeout_seconds(
            adaptive_seconds,
            AUDIO_TIMEOUT_MIN_SECONDS,
            AUDIO_TIMEOUT_MAX_SECONDS,
        ))
    }
}

fn unsupported() -> anyhow::Error {
    anyhow!("llm_provider_unsupported_on_wasm")
}

pub mod openai {
    use anyhow::Result;

    pub struct OpenAiCompatibleProvider;

    impl OpenAiCompatibleProvider {
        pub fn new(
            _base_url: String,
            _api_key: String,
            _model_name: String,
            _temperature: Option<f32>,
        ) -> Self {
            Self
        }
    }

    impl crate::rag::AnswerProvider for OpenAiCompatibleProvider {
        fn stream_answer(
            &self,
            _prompt: &str,
            _on_event: &mut dyn FnMut(super::ChatDelta) -> Result<()>,
        ) -> Result<()> {
            Err(super::unsupported())
        }
    }
}

pub mod gateway {
    use anyhow::Result;

    pub struct CloudGatewayProvider;

    impl CloudGatewayProvider {
        pub fn new(
            _gateway_base_url: String,
            _id_token: String,
            _model_name: String,
            _temperature: Option<f32>,
        ) -> Self {
            Self
        }

        pub fn new_with_purpose(
            _gateway_base_url: String,
            _id_token: String,
            _model_name: String,
            _temperature: Option<f32>,
            _purpose_header: String,
        ) -> Self {
            Self
        }
    }

    impl crate::rag::AnswerProvider for CloudGatewayProvider {
        fn stream_answer(
            &self,
            _prompt: &str,
            _on_event: &mut dyn FnMut(super::ChatDelta) -> Result<()>,
        ) -> Result<()> {
            Err(super::unsupported())
        }
    }
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
                .filter(|value| !value.trim().is_empty())
                .unwrap_or_else(|| "https://api.openai.com/v1".to_string());
            Ok(Box::new(openai::OpenAiCompatibleProvider::new(
                base_url, api_key, model_name, None,
            )))
        }
        _ => Err(anyhow!("unsupported provider_type: {provider_type}")),
    }
}
