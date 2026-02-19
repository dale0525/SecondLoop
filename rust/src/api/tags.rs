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
pub fn db_list_tags(app_dir: String, key: Vec<u8>) -> Result<Vec<db::Tag>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_tags(&conn, &key)
}

#[flutter_rust_bridge::frb]
pub fn db_upsert_tag(app_dir: String, key: Vec<u8>, name: String) -> Result<db::Tag> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::upsert_tag(&conn, &key, &name)
}

#[flutter_rust_bridge::frb]
pub fn db_list_message_tags(
    app_dir: String,
    key: Vec<u8>,
    message_id: String,
) -> Result<Vec<db::Tag>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_message_tags(&conn, &key, &message_id)
}

#[flutter_rust_bridge::frb]
pub fn db_set_message_tags(
    app_dir: String,
    key: Vec<u8>,
    message_id: String,
    tag_ids: Vec<String>,
) -> Result<Vec<db::Tag>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::set_message_tags(&conn, &key, &message_id, &tag_ids)
}

#[flutter_rust_bridge::frb]
pub fn db_list_message_suggested_tags(
    app_dir: String,
    key: Vec<u8>,
    message_id: String,
) -> Result<Vec<String>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_message_suggested_tags(&conn, &key, &message_id)
}

#[flutter_rust_bridge::frb]
pub fn db_list_tag_merge_suggestions(
    app_dir: String,
    key: Vec<u8>,
    limit: u32,
) -> Result<Vec<db::TagMergeSuggestion>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_tag_merge_suggestions(&conn, &key, limit as usize)
}

#[flutter_rust_bridge::frb]
pub fn db_merge_tags(
    app_dir: String,
    key: Vec<u8>,
    source_tag_id: String,
    target_tag_id: String,
) -> Result<u32> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::merge_tags(&conn, &key, &source_tag_id, &target_tag_id)
}

#[flutter_rust_bridge::frb]
pub fn db_record_tag_merge_feedback(
    app_dir: String,
    key: Vec<u8>,
    source_tag_id: String,
    target_tag_id: String,
    reason: String,
    action: String,
) -> Result<()> {
    let _ = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::record_tag_merge_feedback(&conn, &source_tag_id, &target_tag_id, &reason, &action)
}

#[flutter_rust_bridge::frb]
pub fn db_list_message_ids_by_tag_ids(
    app_dir: String,
    key: Vec<u8>,
    conversation_id: String,
    tag_ids: Vec<String>,
) -> Result<Vec<String>> {
    let _ = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_message_ids_by_tag_ids(&conn, &conversation_id, &tag_ids)
}
