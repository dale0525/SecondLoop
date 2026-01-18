use anyhow::Result;

pub const DEFAULT_EMBED_DIM: usize = 384;
pub const DEFAULT_MODEL_NAME: &str = "secondloop-default-embed-v0";
pub const PRODUCTION_MODEL_NAME: &str = "fastembed:intfloat/multilingual-e5-small";

#[cfg(all(
    any(target_os = "windows", target_os = "macos", target_os = "linux"),
    not(frb_expand)
))]
mod fastembed;
#[cfg(all(
    any(target_os = "windows", target_os = "macos", target_os = "linux"),
    not(frb_expand)
))]
pub use fastembed::FastEmbedder;

pub trait Embedder {
    fn model_name(&self) -> &str;
    fn dim(&self) -> usize;
    fn embed(&self, texts: &[String]) -> Result<Vec<Vec<f32>>>;
}
