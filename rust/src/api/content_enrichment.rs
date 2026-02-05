use std::path::Path;

use anyhow::{anyhow, Result};

use crate::db;

fn key_from_bytes(bytes: Vec<u8>) -> Result<[u8; 32]> {
    if bytes.len() != 32 {
        return Err(anyhow!("invalid key length"));
    }
    let mut key = [0u8; 32];
    key.copy_from_slice(&bytes);
    Ok(key)
}

#[flutter_rust_bridge::frb]
pub fn db_get_content_enrichment_config(
    app_dir: String,
    key: Vec<u8>,
) -> Result<db::ContentEnrichmentConfig> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::get_content_enrichment_config(&conn)
}

#[flutter_rust_bridge::frb]
pub fn db_set_content_enrichment_config(
    app_dir: String,
    key: Vec<u8>,
    config: db::ContentEnrichmentConfig,
) -> Result<()> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::set_content_enrichment_config(&conn, &config)
}

#[flutter_rust_bridge::frb]
pub fn db_get_storage_policy_config(
    app_dir: String,
    key: Vec<u8>,
) -> Result<db::StoragePolicyConfig> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::get_storage_policy_config(&conn)
}

#[flutter_rust_bridge::frb]
pub fn db_set_storage_policy_config(
    app_dir: String,
    key: Vec<u8>,
    config: db::StoragePolicyConfig,
) -> Result<()> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::set_storage_policy_config(&conn, &config)
}
