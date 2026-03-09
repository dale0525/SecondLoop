use anyhow::{anyhow, Result};
use reqwest::blocking::Client;
use serde::Serialize;
use std::sync::OnceLock;

use super::cloud_gateway::parse_openai_embeddings_response;
use super::{Embedder, DEFAULT_EMBED_DIM};
use crate::knowledge::embedding_batch::{
    average_piece_embeddings, batch_prepared_embedding_inputs, ensure_non_empty_embedding_results,
    prepare_embedding_inputs, EmbeddingBatchPolicy,
};

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

    fn embed_batch(&self, texts: &[String]) -> Result<Vec<Vec<f32>>> {
        let url = brok_embeddings_url(&self.base_url);
        let req = BrokOpenAiEmbeddingsRequest {
            model: self.model_name.clone(),
            input: texts.to_vec(),
            encoding_format: "float".to_string(),
        };
        let _request_guard = crate::llm::request_limiter::acquire_remote_llm_request_slot();

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

        let policy = EmbeddingBatchPolicy::default();
        let prepared = prepare_embedding_inputs(texts, policy);
        let batches = batch_prepared_embedding_inputs(&prepared, policy);
        let mut grouped = vec![Vec::<Vec<f32>>::new(); texts.len()];
        for batch in batches {
            let batch_texts = batch
                .iter()
                .map(|value| value.text.clone())
                .collect::<Vec<_>>();
            let batch_embeddings = self.embed_batch(&batch_texts)?;
            for (item, embedding) in batch.into_iter().zip(batch_embeddings.into_iter()) {
                grouped[item.source_index].push(embedding);
            }
        }
        let embeddings = average_piece_embeddings(grouped, texts.len());
        ensure_non_empty_embedding_results(&embeddings)?;
        Ok(embeddings)
    }
}
