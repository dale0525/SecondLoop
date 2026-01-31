use anyhow::{anyhow, Result};
use reqwest::blocking::Client;
use serde::Serialize;
use std::sync::OnceLock;

use super::cloud_gateway::parse_openai_embeddings_response;
use super::{Embedder, DEFAULT_EMBED_DIM};

pub fn brok_embeddings_url(base_url: &str) -> String {
    format!("{}/embeddings", base_url.trim_end_matches('/'))
}

#[derive(Debug, Serialize)]
struct BrokOpenAiEmbeddingsRequest {
    model: String,
    input: Vec<String>,
    encoding_format: String,
}

pub struct BrokEmbedder {
    client: Client,
    base_url: String,
    api_key: String,
    model_name: String,
    dim: OnceLock<usize>,
}

impl BrokEmbedder {
    pub fn new(base_url: String, api_key: String, model_name: String) -> Self {
        Self {
            client: Client::new(),
            base_url,
            api_key,
            model_name,
            dim: OnceLock::new(),
        }
    }
}

impl Embedder for BrokEmbedder {
    fn model_name(&self) -> &str {
        &self.model_name
    }

    fn dim(&self) -> usize {
        self.dim.get().copied().unwrap_or(DEFAULT_EMBED_DIM)
    }

    fn embed(&self, texts: &[String]) -> Result<Vec<Vec<f32>>> {
        if texts.is_empty() {
            return Ok(Vec::new());
        }

        if self.base_url.trim().is_empty() {
            return Err(anyhow!("missing base_url"));
        }
        if self.api_key.trim().is_empty() {
            return Err(anyhow!("missing api_key"));
        }

        let url = brok_embeddings_url(&self.base_url);
        let req = BrokOpenAiEmbeddingsRequest {
            model: self.model_name.clone(),
            input: texts.to_vec(),
            encoding_format: "float".to_string(),
        };

        let resp = self
            .client
            .post(url)
            .bearer_auth(&self.api_key)
            .json(&req)
            .send()?;

        if !resp.status().is_success() {
            let status = resp.status();
            let body = resp.text().unwrap_or_default();
            return Err(anyhow!(
                "brok embeddings request failed: HTTP {status} {body}"
            ));
        }

        let body = resp.text().unwrap_or_default();
        let parsed = parse_openai_embeddings_response(&body, texts.len())?;
        let _ = self.dim.set(parsed.dim);
        Ok(parsed.embeddings)
    }
}
