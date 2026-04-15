use anyhow::{anyhow, Result};
use serde_json::Value;

#[derive(Clone, Debug)]
pub struct MediaAnnotationUsage {
    pub input_tokens: Option<i64>,
    pub output_tokens: Option<i64>,
    pub total_tokens: Option<i64>,
}

pub struct OpenAiCompatibleMediaAnnotationClient;

impl OpenAiCompatibleMediaAnnotationClient {
    pub fn new(_base_url: String, _api_key: String, _model_name: String) -> Self {
        Self
    }

    pub fn annotate_image_with_usage(
        &self,
        _lang: &str,
        _mime_type: &str,
        _image_bytes: &[u8],
    ) -> Result<(Value, MediaAnnotationUsage)> {
        Err(anyhow!("media_annotation_unsupported_on_wasm"))
    }
}

pub struct CloudGatewayMediaAnnotationClient;

impl CloudGatewayMediaAnnotationClient {
    pub fn new(_gateway_base_url: String, _id_token: String, _model_name: String) -> Self {
        Self
    }

    pub fn annotate_image(
        &self,
        _lang: &str,
        _mime_type: &str,
        _image_bytes: &[u8],
    ) -> Result<Value> {
        Err(anyhow!("media_annotation_unsupported_on_wasm"))
    }
}
