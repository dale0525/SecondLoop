use anyhow::Result;

pub const DEFAULT_EMBED_DIM: usize = 384;
pub const DEFAULT_MODEL_NAME: &str = "secondloop-default-embed-v0";

pub trait Embedder {
    fn model_name(&self) -> &str;
    fn dim(&self) -> usize;
    fn embed(&self, texts: &[String]) -> Result<Vec<Vec<f32>>>;
}
