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
pub fn db_list_due_image_attachment_annotations(
    app_dir: String,
    key: Vec<u8>,
    now_ms: i64,
    limit: u32,
) -> Result<Vec<db::AttachmentAnnotationJob>> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_due_image_attachment_annotations(&conn, now_ms, limit as i64)
}

#[flutter_rust_bridge::frb]
pub fn db_list_due_url_manifest_attachment_annotations(
    app_dir: String,
    key: Vec<u8>,
    now_ms: i64,
    limit: u32,
) -> Result<Vec<db::AttachmentAnnotationJob>> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_due_url_manifest_attachment_annotations(&conn, now_ms, limit as i64)
}

#[flutter_rust_bridge::frb]
pub fn db_process_pending_document_extractions(
    app_dir: String,
    key: Vec<u8>,
    limit: u32,
) -> Result<u32> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let processed =
        db::process_pending_document_extractions(&conn, &key, Path::new(&app_dir), limit as usize)?;
    Ok(processed as u32)
}

#[flutter_rust_bridge::frb]
pub fn db_read_attachment_annotation_payload_json(
    app_dir: String,
    key: Vec<u8>,
    attachment_sha256: String,
) -> Result<Option<String>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::read_attachment_annotation_payload_json(&conn, &key, &attachment_sha256)
}
