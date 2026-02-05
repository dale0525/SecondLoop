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
pub fn db_read_attachment_metadata(
    app_dir: String,
    key: Vec<u8>,
    attachment_sha256: String,
) -> Result<Option<db::AttachmentMetadata>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::read_attachment_metadata(&conn, &key, &attachment_sha256)
}

#[flutter_rust_bridge::frb]
pub fn db_upsert_attachment_metadata(
    app_dir: String,
    key: Vec<u8>,
    attachment_sha256: String,
    title: Option<String>,
    filenames: Vec<String>,
    source_urls: Vec<String>,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::upsert_attachment_metadata(
        &conn,
        &key,
        &attachment_sha256,
        title.as_deref(),
        &filenames,
        &source_urls,
    )
}
