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
pub fn db_create_topic_thread(
    app_dir: String,
    key: Vec<u8>,
    conversation_id: String,
    title: Option<String>,
) -> Result<db::TopicThread> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::create_topic_thread(&conn, &key, &conversation_id, title.as_deref())
}

#[flutter_rust_bridge::frb]
pub fn db_list_topic_threads(
    app_dir: String,
    key: Vec<u8>,
    conversation_id: String,
) -> Result<Vec<db::TopicThread>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_topic_threads(&conn, &key, &conversation_id)
}

#[flutter_rust_bridge::frb]
pub fn db_update_topic_thread_title(
    app_dir: String,
    key: Vec<u8>,
    thread_id: String,
    title: Option<String>,
) -> Result<db::TopicThread> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::update_topic_thread_title(&conn, &key, &thread_id, title.as_deref())
}

#[flutter_rust_bridge::frb]
pub fn db_delete_topic_thread(app_dir: String, key: Vec<u8>, thread_id: String) -> Result<bool> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::delete_topic_thread(&conn, &key, &thread_id)
}

#[flutter_rust_bridge::frb]
pub fn db_set_topic_thread_message_ids(
    app_dir: String,
    key: Vec<u8>,
    thread_id: String,
    message_ids: Vec<String>,
) -> Result<Vec<String>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::set_topic_thread_message_ids(&conn, &key, &thread_id, &message_ids)
}

#[flutter_rust_bridge::frb]
pub fn db_list_topic_thread_message_ids(
    app_dir: String,
    key: Vec<u8>,
    thread_id: String,
) -> Result<Vec<String>> {
    let _ = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_topic_thread_message_ids(&conn, &thread_id)
}
