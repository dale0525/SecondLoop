use anyhow::Result;

pub const DEFAULT_EMBED_DIM: usize = 384;
pub const DEFAULT_MODEL_NAME: &str = "secondloop-default-embed-v0";
pub const PRODUCTION_MODEL_NAME: &str = "fastembed:intfloat/multilingual-e5-small";

pub mod brok;
pub use brok::{brok_embeddings_url, BrokEmbedder};

pub mod cloud_gateway;
pub use cloud_gateway::CloudGatewayEmbedder;

#[cfg(all(
    any(target_os = "windows", target_os = "macos", target_os = "linux"),
    not(frb_expand)
))]
mod fastembed;
#[cfg(all(
    any(target_os = "windows", target_os = "macos", target_os = "linux"),
    not(frb_expand)
))]
pub(crate) use fastembed::fastembed_lifecycle_status;
#[cfg(all(
    any(target_os = "windows", target_os = "macos", target_os = "linux"),
    not(frb_expand)
))]
pub use fastembed::{release_fastembed_if_idle, FastEmbedder};
#[cfg(all(
    test,
    any(target_os = "windows", target_os = "macos", target_os = "linux"),
    not(frb_expand)
))]
pub(crate) use fastembed::{
    reset_fastembed_cache_for_test, seed_fastembed_cache_for_test_with_last_used,
};

#[cfg(not(all(
    any(target_os = "windows", target_os = "macos", target_os = "linux"),
    not(frb_expand)
)))]
pub fn release_fastembed_if_idle(_max_idle: std::time::Duration) -> bool {
    false
}

#[cfg(not(all(
    any(target_os = "windows", target_os = "macos", target_os = "linux"),
    not(frb_expand)
)))]
pub(crate) fn fastembed_lifecycle_status() -> crate::local_model_lifecycle::LocalModelLifecycleStatus
{
    crate::local_model_lifecycle::LocalModelLifecycleStatus::cached(false, 0, None)
}

#[cfg(all(
    test,
    not(all(
        any(target_os = "windows", target_os = "macos", target_os = "linux"),
        not(frb_expand)
    ))
))]
pub(crate) fn seed_fastembed_cache_for_test_with_last_used(_age: std::time::Duration) {}

#[cfg(all(
    test,
    not(all(
        any(target_os = "windows", target_os = "macos", target_os = "linux"),
        not(frb_expand)
    ))
))]
pub(crate) fn reset_fastembed_cache_for_test() {}

pub trait Embedder {
    fn model_name(&self) -> &str;
    fn dim(&self) -> usize;
    fn embed(&self, texts: &[String]) -> Result<Vec<Vec<f32>>>;
}
