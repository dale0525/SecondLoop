use std::path::Path;

use anyhow::{anyhow, Result};
use crate::{auth, db};
use crate::crypto::{derive_root_key, KdfParams};
use crate::{llm, rag};
use crate::frb_generated::StreamSink;
use crate::sync;
use crate::sync::RemoteStore;

fn key_from_bytes(bytes: Vec<u8>) -> Result<[u8; 32]> {
    if bytes.len() != 32 {
        return Err(anyhow!("invalid key length"));
    }
    let mut key = [0u8; 32];
    key.copy_from_slice(&bytes);
    Ok(key)
}

fn sync_key_from_bytes(bytes: Vec<u8>) -> Result<[u8; 32]> {
    key_from_bytes(bytes)
}

#[flutter_rust_bridge::frb]
pub fn auth_is_initialized(app_dir: String) -> bool {
    auth::is_initialized(Path::new(&app_dir))
}

#[flutter_rust_bridge::frb]
pub fn auth_init_master_password(app_dir: String, password: String) -> Result<Vec<u8>> {
    let kdf = KdfParams {
        m_cost_kib: 8 * 1024,
        t_cost: 2,
        p_cost: 1,
    };
    let key = auth::init_master_password(Path::new(&app_dir), &password, kdf)?;
    Ok(key.to_vec())
}

#[flutter_rust_bridge::frb]
pub fn auth_unlock_with_password(app_dir: String, password: String) -> Result<Vec<u8>> {
    let key = auth::unlock_with_password(Path::new(&app_dir), &password)?;
    Ok(key.to_vec())
}

#[flutter_rust_bridge::frb]
pub fn auth_validate_key(app_dir: String, key: Vec<u8>) -> Result<()> {
    let key = key_from_bytes(key)?;
    auth::validate_key(Path::new(&app_dir), &key)
}

#[flutter_rust_bridge::frb]
pub fn db_list_conversations(app_dir: String, key: Vec<u8>) -> Result<Vec<db::Conversation>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_conversations(&conn, &key)
}

#[flutter_rust_bridge::frb]
pub fn db_create_conversation(
    app_dir: String,
    key: Vec<u8>,
    title: String,
) -> Result<db::Conversation> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::create_conversation(&conn, &key, &title)
}

#[flutter_rust_bridge::frb]
pub fn db_list_messages(
    app_dir: String,
    key: Vec<u8>,
    conversation_id: String,
) -> Result<Vec<db::Message>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_messages(&conn, &key, &conversation_id)
}

#[flutter_rust_bridge::frb]
pub fn db_insert_message(
    app_dir: String,
    key: Vec<u8>,
    conversation_id: String,
    role: String,
    content: String,
) -> Result<db::Message> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::insert_message(&conn, &key, &conversation_id, &role, &content)
}

#[flutter_rust_bridge::frb]
pub fn db_create_llm_profile(
    app_dir: String,
    key: Vec<u8>,
    name: String,
    provider_type: String,
    base_url: Option<String>,
    api_key: Option<String>,
    model_name: String,
    set_active: bool,
) -> Result<db::LlmProfile> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::create_llm_profile(
        &conn,
        &key,
        &name,
        &provider_type,
        base_url.as_deref(),
        api_key.as_deref(),
        &model_name,
        set_active,
    )
}

#[flutter_rust_bridge::frb]
pub fn db_list_llm_profiles(app_dir: String, key: Vec<u8>) -> Result<Vec<db::LlmProfile>> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::list_llm_profiles(&conn)
}

#[flutter_rust_bridge::frb]
pub fn db_set_active_llm_profile(
    app_dir: String,
    key: Vec<u8>,
    profile_id: String,
) -> Result<()> {
    let _key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::set_active_llm_profile(&conn, &profile_id)
}

#[flutter_rust_bridge::frb]
pub fn db_process_pending_message_embeddings(
    app_dir: String,
    key: Vec<u8>,
    limit: u32,
) -> Result<u32> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let processed = db::process_pending_message_embeddings_default(&conn, &key, limit as usize)?;
    Ok(processed as u32)
}

#[flutter_rust_bridge::frb]
pub fn db_search_similar_messages(
    app_dir: String,
    key: Vec<u8>,
    query: String,
    top_k: u32,
) -> Result<Vec<db::SimilarMessage>> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    db::search_similar_messages_default(&conn, &key, &query, top_k as usize)
}

#[flutter_rust_bridge::frb]
pub fn db_rebuild_message_embeddings(
    app_dir: String,
    key: Vec<u8>,
    batch_limit: u32,
) -> Result<u32> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let rebuilt = db::rebuild_message_embeddings_default(&conn, &key, batch_limit as usize)?;
    Ok(rebuilt as u32)
}

#[flutter_rust_bridge::frb]
pub fn rag_ask_ai_stream(
    app_dir: String,
    key: Vec<u8>,
    conversation_id: String,
    question: String,
    top_k: u32,
    this_thread_only: bool,
    sink: StreamSink<String>,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let conn = db::open(Path::new(&app_dir))?;

    let profile = db::load_active_llm_profile_config(&conn, &key)?
        .ok_or_else(|| anyhow!("no active LLM profile configured"))?;

    let focus = if this_thread_only {
        rag::Focus::ThisThread
    } else {
        rag::Focus::AllMemories
    };

    let provider_type = profile.provider_type.as_str();
    let base_url = profile
        .base_url
        .unwrap_or_else(|| "https://api.openai.com/v1".to_string());
    let model_name = profile.model_name;

    let result = match provider_type {
        "openai-compatible" => {
            let api_key = profile
                .api_key
                .ok_or_else(|| anyhow!("missing api_key for openai-compatible provider"))?;
            let provider =
                llm::openai::OpenAiCompatibleProvider::new(base_url, api_key, model_name, None);
            rag::ask_ai_with_provider(
                &conn,
                &key,
                &conversation_id,
                &question,
                top_k as usize,
                focus,
                &provider,
                &mut |ev| {
                    if ev.done {
                        if sink.add(String::new()).is_err() {
                            return Err(rag::StreamCancelled.into());
                        }
                        return Ok(());
                    }
                    if ev.text_delta.is_empty() {
                        return Ok(());
                    }
                    if sink.add(ev.text_delta).is_err() {
                        return Err(rag::StreamCancelled.into());
                    }
                    Ok(())
                },
            )
            .map(|_| ())
        }
        _ => Err(anyhow!("unsupported provider_type: {provider_type}")),
    };

    match result {
        Ok(()) => Ok(()),
        Err(e) if e.is::<rag::StreamCancelled>() => Ok(()),
        Err(e) => Err(e),
    }
}

#[flutter_rust_bridge::frb]
pub fn sync_derive_key(passphrase: String) -> Result<Vec<u8>> {
    let kdf = KdfParams {
        m_cost_kib: 8 * 1024,
        t_cost: 2,
        p_cost: 1,
    };
    let key = derive_root_key(&passphrase, b"secondloop-sync1", &kdf)?;
    Ok(key.to_vec())
}

#[flutter_rust_bridge::frb]
pub fn sync_webdav_test_connection(
    base_url: String,
    username: Option<String>,
    password: Option<String>,
    remote_root: String,
) -> Result<()> {
    let remote = sync::webdav::WebDavRemoteStore::new(base_url, username, password)?;
    remote.mkdir_all(&remote_root)?;
    let _ = remote.list(&remote_root)?;
    Ok(())
}

#[flutter_rust_bridge::frb]
pub fn sync_webdav_push(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    base_url: String,
    username: Option<String>,
    password: Option<String>,
    remote_root: String,
) -> Result<u64> {
    let key = key_from_bytes(key)?;
    let sync_key = sync_key_from_bytes(sync_key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let remote = sync::webdav::WebDavRemoteStore::new(base_url, username, password)?;
    sync::push(&conn, &key, &sync_key, &remote, &remote_root)
}

#[flutter_rust_bridge::frb]
pub fn sync_webdav_pull(
    app_dir: String,
    key: Vec<u8>,
    sync_key: Vec<u8>,
    base_url: String,
    username: Option<String>,
    password: Option<String>,
    remote_root: String,
) -> Result<u64> {
    let key = key_from_bytes(key)?;
    let sync_key = sync_key_from_bytes(sync_key)?;
    let conn = db::open(Path::new(&app_dir))?;
    let remote = sync::webdav::WebDavRemoteStore::new(base_url, username, password)?;
    sync::pull(&conn, &key, &sync_key, &remote, &remote_root)
}
