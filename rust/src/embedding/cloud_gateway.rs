use anyhow::{anyhow, Result};
use reqwest::blocking::Client;
use serde::{Deserialize, Serialize};
use std::sync::OnceLock;

use super::{Embedder, DEFAULT_EMBED_DIM};

const HEADER_EMBEDDINGS_MODEL_ID: &str = "x-secondloop-embedding-model-id";

pub fn cloud_gateway_embeddings_url(gateway_base_url: &str) -> String {
    format!("{}/v1/embeddings", gateway_base_url.trim_end_matches('/'))
}

#[derive(Debug, Serialize)]
struct OpenAiEmbeddingsRequest {
    model: String,
    input: Vec<String>,
    encoding_format: String,
}

#[derive(Debug, Deserialize)]
struct OpenAiEmbeddingData {
    index: usize,
    embedding: Vec<f32>,
}

#[derive(Debug, Deserialize)]
struct OpenAiEmbeddingsResponse {
    data: Vec<OpenAiEmbeddingData>,
}

#[derive(Debug)]
pub struct ParsedOpenAiEmbeddings {
    pub dim: usize,
    pub embeddings: Vec<Vec<f32>>,
}

pub fn parse_openai_embeddings_response(
    body: &str,
    expected_len: usize,
) -> Result<ParsedOpenAiEmbeddings> {
    let parsed: OpenAiEmbeddingsResponse =
        serde_json::from_str(body).map_err(|e| anyhow!("invalid embeddings json: {e}"))?;

    if parsed.data.len() != expected_len {
        return Err(anyhow!(
            "expected {expected_len} embeddings, got {}",
            parsed.data.len()
        ));
    }

    let mut out: Vec<Option<Vec<f32>>> = vec![None; expected_len];
    let mut dim: Option<usize> = None;
    for item in parsed.data {
        if item.index >= expected_len {
            return Err(anyhow!(
                "embedding index out of range: {} (expected < {expected_len})",
                item.index
            ));
        }
        let item_dim = item.embedding.len();
        if item_dim == 0 {
            return Err(anyhow!("embedding dim is 0"));
        }
        if let Some(expected) = dim {
            if item_dim != expected {
                return Err(anyhow!(
                    "embedding dim mismatch: expected {expected}, got {item_dim}"
                ));
            }
        } else {
            dim = Some(item_dim);
        }
        out[item.index] = Some(item.embedding);
    }

    let mut finalized = Vec::with_capacity(expected_len);
    for i in 0..expected_len {
        finalized.push(
            out[i]
                .take()
                .ok_or_else(|| anyhow!("missing embedding at index {i}"))?,
        );
    }

    Ok(ParsedOpenAiEmbeddings {
        dim: dim.unwrap_or(0),
        embeddings: finalized,
    })
}

pub struct CloudGatewayEmbedder {
    client: Client,
    gateway_base_url: String,
    id_token: String,
    requested_model_name: String,
    effective_model_id: OnceLock<String>,
    dim: OnceLock<usize>,
}

impl CloudGatewayEmbedder {
    pub fn new(gateway_base_url: String, id_token: String, model_name: String) -> Self {
        Self {
            client: Client::new(),
            gateway_base_url,
            id_token,
            requested_model_name: model_name,
            effective_model_id: OnceLock::new(),
            dim: OnceLock::new(),
        }
    }
}

impl Embedder for CloudGatewayEmbedder {
    fn model_name(&self) -> &str {
        self.effective_model_id
            .get()
            .map(|v| v.as_str())
            .unwrap_or(&self.requested_model_name)
    }

    fn dim(&self) -> usize {
        self.dim.get().copied().unwrap_or(DEFAULT_EMBED_DIM)
    }

    fn embed(&self, texts: &[String]) -> Result<Vec<Vec<f32>>> {
        if texts.is_empty() {
            return Ok(Vec::new());
        }

        let url = cloud_gateway_embeddings_url(&self.gateway_base_url);
        let req = OpenAiEmbeddingsRequest {
            model: self.requested_model_name.clone(),
            input: texts.to_vec(),
            encoding_format: "float".to_string(),
        };

        let resp = self
            .client
            .post(url)
            .bearer_auth(&self.id_token)
            .header("x-secondloop-purpose", "embeddings")
            .json(&req)
            .send()?;

        if !resp.status().is_success() {
            let status = resp.status();
            let body = resp.text().unwrap_or_default();
            return Err(anyhow!(
                "cloud-gateway embeddings request failed: HTTP {status} {body}"
            ));
        }

        if let Some(model_id) = resp
            .headers()
            .get(HEADER_EMBEDDINGS_MODEL_ID)
            .and_then(|v| v.to_str().ok())
            .map(str::trim)
            .filter(|v| !v.is_empty())
        {
            let _ = self.effective_model_id.set(model_id.to_string());
        }

        let body = resp.text().unwrap_or_default();
        let parsed = parse_openai_embeddings_response(&body, texts.len())?;
        let _ = self.dim.set(parsed.dim);
        Ok(parsed.embeddings)
    }
}
