use std::path::{Path, PathBuf};

use crate::api::remote_embedding_bootstrap;
use crate::auth;
use crate::crypto::{derive_root_key, KdfParams};
use crate::db;
use crate::embedding;
use crate::embedding::Embedder;
use crate::frb_generated::StreamSink;
use crate::sync;
use crate::sync::RemoteStore;
use crate::{geo, media_annotation};
use crate::{llm, rag, semantic_parse};
use anyhow::{anyhow, Context, Result};

const ASK_AI_ERROR_PREFIX: &str = "\u{001e}SL_ERROR\u{001e}";
const ATTACHMENT_REMOTE_MISSING_ERROR_CODE: &str = "SL_ERR_ATTACHMENT_REMOTE_MISSING";

fn map_attachment_download_error(err: anyhow::Error) -> anyhow::Error {
    if err.downcast_ref::<sync::NotFound>().is_some() {
        return anyhow!(ATTACHMENT_REMOTE_MISSING_ERROR_CODE);
    }
    err
}

fn finish_ask_ai_stream(sink: &StreamSink<String>, result: Result<()>) -> Result<()> {
    match result {
        Ok(()) => Ok(()),
        Err(e) if e.is::<rag::StreamCancelled>() => Ok(()),
        Err(e) => {
            let _ = sink.add(format!("{ASK_AI_ERROR_PREFIX}{e}"));
            Ok(())
        }
    }
}

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

const DUE_JOB_REFETCH_LIMIT_MULTIPLIER: i64 = 128;

pub(crate) fn is_todo_access_error(err: &anyhow::Error) -> bool {
    crate::crypto::is_decrypt_failed_error(err)
}

fn list_visible_due_todo_followup_generation_jobs(
    conn: &rusqlite::Connection,
    key: &[u8; 32],
    now_ms: i64,
    limit: u32,
) -> Result<Vec<db::TodoFollowupGenerationJob>> {
    let requested_limit = i64::from(limit.max(1));
    let max_requested_limit = requested_limit.saturating_mul(DUE_JOB_REFETCH_LIMIT_MULTIPLIER);

    let mut current_limit = requested_limit;
    let mut jobs = db::list_due_todo_followup_generation_jobs(conn, now_ms, current_limit)?;

    loop {
        let mut visible_jobs = Vec::with_capacity(jobs.len());
        for job in &jobs {
            match db::find_todo(conn, key, &job.todo_id) {
                Ok(Some(_)) => visible_jobs.push(job.clone()),
                Ok(None) => {}
                Err(err) => {
                    if is_todo_access_error(&err) {
                        continue;
                    }
                    return Err(err).context(format!(
                        "failed to read todo for followup job: {}",
                        job.todo_id
                    ));
                }
            }
        }

        if visible_jobs.len() >= requested_limit as usize {
            visible_jobs.truncate(requested_limit as usize);
            return Ok(visible_jobs);
        }

        if jobs.len() < current_limit as usize || current_limit >= max_requested_limit {
            return Ok(visible_jobs);
        }

        let next_limit = (current_limit.saturating_mul(2)).min(max_requested_limit);
        let next_jobs = db::list_due_todo_followup_generation_jobs(conn, now_ms, next_limit)?;
        if next_jobs.len() <= jobs.len() {
            return Ok(visible_jobs);
        }

        jobs = next_jobs;
        current_limit = next_limit;
    }
}

fn check_todo_access(conn: &rusqlite::Connection, key: &[u8; 32], todo_id: &str) -> Result<bool> {
    Ok(db::find_todo(conn, key, todo_id)?.is_some())
}

fn ensure_todo_access(conn: &rusqlite::Connection, key: &[u8; 32], todo_id: &str) -> Result<()> {
    if check_todo_access(conn, key, todo_id)? {
        return Ok(());
    }
    Err(anyhow!("todo not found"))
}

fn default_embedding_model_name_for_platform() -> &'static str {
    if cfg!(any(
        target_os = "windows",
        target_os = "macos",
        target_os = "linux"
    )) {
        embedding::PRODUCTION_MODEL_NAME
    } else {
        embedding::DEFAULT_MODEL_NAME
    }
}

fn collect_provider_text(provider: &dyn rag::AnswerProvider, prompt: &str) -> Result<String> {
    let mut out = String::new();
    provider.stream_answer(prompt, &mut |ev| {
        out.push_str(&ev.text_delta);
        Ok(())
    })?;

    let trimmed = out.trim();
    if trimmed.is_empty() {
        return Err(anyhow!("empty response from LLM"));
    }

    Ok(trimmed.to_string())
}

fn normalize_embedding_model_name(name: &str) -> &'static str {
    match name {
        embedding::DEFAULT_MODEL_NAME => embedding::DEFAULT_MODEL_NAME,
        embedding::PRODUCTION_MODEL_NAME => embedding::PRODUCTION_MODEL_NAME,
        _ => default_embedding_model_name_for_platform(),
    }
}

include!("core_parts/part_01.rs");
include!("core_parts/part_02.rs");
include!("core_parts/part_03.rs");
include!("core_parts/part_04.rs");
include!("core_parts/part_05.rs");
include!("core_parts/part_06_secretary.rs");
