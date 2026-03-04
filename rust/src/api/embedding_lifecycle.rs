use std::time::Duration;

use anyhow::{anyhow, Result};

use crate::embedding;

fn key_from_bytes(bytes: Vec<u8>) -> Result<[u8; 32]> {
    if bytes.len() != 32 {
        return Err(anyhow!("invalid key length"));
    }
    let mut key = [0u8; 32];
    key.copy_from_slice(&bytes);
    Ok(key)
}

#[flutter_rust_bridge::frb]
pub fn db_release_local_embedding_model_if_idle(
    app_dir: String,
    key: Vec<u8>,
    max_idle_ms: u32,
) -> Result<bool> {
    let _key = key_from_bytes(key)?;
    let _ = app_dir;
    Ok(embedding::release_fastembed_if_idle(Duration::from_millis(
        max_idle_ms as u64,
    )))
}
