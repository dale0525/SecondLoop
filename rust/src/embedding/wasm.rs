use std::path::Path;
use std::sync::OnceLock;

use anyhow::{anyhow, Result};

pub const DEFAULT_EMBED_DIM: usize = 384;
pub const DEFAULT_MODEL_NAME: &str = "secondloop-default-embed-v0";
pub const PRODUCTION_MODEL_NAME: &str = "fastembed:intfloat/multilingual-e5-small";

pub trait Embedder {
    fn model_name(&self) -> &str;
    fn dim(&self) -> usize;
    fn embed(&self, texts: &[String]) -> Result<Vec<Vec<f32>>>;
}

pub fn brok_embeddings_url(base_url: &str) -> String {
    format!("{}/embeddings", base_url.trim_end_matches('/'))
}

pub fn cloud_gateway_embeddings_url(gateway_base_url: &str) -> String {
    format!("{}/v1/embeddings", gateway_base_url.trim_end_matches('/'))
}

pub struct BrokEmbedder {
    model_name: String,
    dim: OnceLock<usize>,
}

impl BrokEmbedder {
    pub fn new(_base_url: String, _api_key: String, model_name: String) -> Self {
        Self {
            model_name,
            dim: OnceLock::new(),
        }
    }

    pub fn learned_dim(&self) -> Option<usize> {
        self.dim.get().copied()
    }
}

impl Embedder for BrokEmbedder {
    fn model_name(&self) -> &str {
        &self.model_name
    }

    fn dim(&self) -> usize {
        self.dim.get().copied().unwrap_or(DEFAULT_EMBED_DIM)
    }

    fn embed(&self, _texts: &[String]) -> Result<Vec<Vec<f32>>> {
        Err(anyhow!("remote_embeddings_unsupported_on_wasm"))
    }
}

pub struct CloudGatewayEmbedder {
    requested_model_name: String,
    effective_model_id: OnceLock<String>,
    dim: OnceLock<usize>,
}

impl CloudGatewayEmbedder {
    pub fn new(_gateway_base_url: String, _id_token: String, model_name: String) -> Self {
        Self {
            requested_model_name: model_name,
            effective_model_id: OnceLock::new(),
            dim: OnceLock::new(),
        }
    }

    pub fn learned_model_name(&self) -> Option<&str> {
        self.effective_model_id.get().map(|value| value.as_str())
    }

    pub fn learned_dim(&self) -> Option<usize> {
        self.dim.get().copied()
    }

    pub fn seed_effective_model_id_and_dim(&self, model_id: &str, dim: usize) {
        let model_id = model_id.trim();
        if !model_id.is_empty() {
            let _ = self.effective_model_id.set(model_id.to_string());
        }
        if dim > 0 {
            let _ = self.dim.set(dim);
        }
    }
}

impl Embedder for CloudGatewayEmbedder {
    fn model_name(&self) -> &str {
        self.effective_model_id
            .get()
            .map(|value| value.as_str())
            .unwrap_or(&self.requested_model_name)
    }

    fn dim(&self) -> usize {
        self.dim.get().copied().unwrap_or(DEFAULT_EMBED_DIM)
    }

    fn embed(&self, _texts: &[String]) -> Result<Vec<Vec<f32>>> {
        Err(anyhow!("remote_embeddings_unsupported_on_wasm"))
    }
}

pub struct FastEmbedder;

impl FastEmbedder {
    pub fn get_or_try_init(_app_dir: &Path) -> Result<Self> {
        Err(anyhow!("fastembed_unsupported_on_wasm"))
    }
}

impl Embedder for FastEmbedder {
    fn model_name(&self) -> &str {
        PRODUCTION_MODEL_NAME
    }

    fn dim(&self) -> usize {
        DEFAULT_EMBED_DIM
    }

    fn embed(&self, _texts: &[String]) -> Result<Vec<Vec<f32>>> {
        Err(anyhow!("fastembed_unsupported_on_wasm"))
    }
}

pub fn release_fastembed_if_idle(_max_idle: std::time::Duration) -> bool {
    false
}

pub(crate) fn fastembed_lifecycle_status() -> crate::local_model_lifecycle::LocalModelLifecycleStatus
{
    crate::local_model_lifecycle::LocalModelLifecycleStatus::cached(false, 0, None)
}

#[cfg(test)]
pub(crate) fn seed_fastembed_cache_for_test_with_last_used(_age: std::time::Duration) {}

#[cfg(test)]
pub(crate) fn reset_fastembed_cache_for_test() {}
