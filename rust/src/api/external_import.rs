use std::path::Path;

use anyhow::{anyhow, Result};

use crate::db;
use crate::frb_generated::StreamSink;

fn key_from_bytes(bytes: Vec<u8>) -> Result<[u8; 32]> {
    if bytes.len() != 32 {
        return Err(anyhow!("invalid key length"));
    }
    let mut key = [0u8; 32];
    key.copy_from_slice(&bytes);
    Ok(key)
}

fn emit_progress(sink: &StreamSink<String>, progress: db::ExternalImportProgress) {
    let payload = serde_json::json!({
        "type": "progress",
        "batch_id": progress.batch_id,
        "stage": progress.stage,
        "done": progress.done,
        "total": progress.total,
        "failed_count": progress.failed_count,
        "status": progress.status,
    })
    .to_string();
    let _ = sink.add(payload);
}

fn emit_result(sink: &StreamSink<String>, summary: db::ExternalImportBatchSummary) {
    let payload = serde_json::json!({
        "type": "result",
        "batch_id": summary.batch_id,
        "source_kind": summary.source_kind,
        "source_label": summary.source_label,
        "status": summary.status,
        "notes_count": summary.notes_count,
        "attachments_count": summary.attachments_count,
        "failed_count": summary.failed_count,
        "copied_bytes": summary.copied_bytes,
        "created_at_ms": summary.created_at_ms,
        "updated_at_ms": summary.updated_at_ms,
        "completed_at_ms": summary.completed_at_ms,
        "last_error": summary.last_error,
    })
    .to_string();
    let _ = sink.add(payload);
}

#[flutter_rust_bridge::frb]
pub fn external_import_scan_source(
    app_dir: String,
    source_path: String,
) -> Result<db::ExternalImportScanSummary> {
    db::scan_external_import_source(Path::new(&app_dir), Path::new(&source_path))
}

#[flutter_rust_bridge::frb]
pub fn external_import_list_batches(
    app_dir: String,
) -> Result<Vec<db::ExternalImportBatchSummary>> {
    db::list_external_import_batches(Path::new(&app_dir))
}

#[flutter_rust_bridge::frb]
pub fn external_import_batch_report_json(app_dir: String, batch_id: String) -> Result<String> {
    db::read_external_import_batch_report_json(Path::new(&app_dir), &batch_id)
}

#[flutter_rust_bridge::frb]
pub fn external_import_delete_batch(app_dir: String, batch_id: String) -> Result<()> {
    db::delete_external_import_batch(Path::new(&app_dir), &batch_id)
}

#[flutter_rust_bridge::frb]
pub fn external_import_request_cancel(app_dir: String, batch_id: String) -> Result<()> {
    db::request_external_import_cancel(Path::new(&app_dir), &batch_id)
}

#[flutter_rust_bridge::frb]
pub fn external_import_phase_b_estimate_json(app_dir: String, batch_id: String) -> Result<String> {
    Ok(db::estimate_external_import_phase_b(Path::new(&app_dir), &batch_id)?.to_string())
}

#[flutter_rust_bridge::frb]
pub fn external_import_phase_b_state_json(app_dir: String, batch_id: String) -> Result<String> {
    Ok(db::read_external_import_phase_b_state(Path::new(&app_dir), &batch_id)?.to_string())
}

#[flutter_rust_bridge::frb]
pub fn external_import_run_progress(
    app_dir: String,
    key: Vec<u8>,
    source_path: String,
    sink: StreamSink<String>,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let mut on_event = |progress: db::ExternalImportProgress| {
        emit_progress(&sink, progress);
    };
    let should_cancel = || false;
    let summary = db::run_external_import_with_callbacks(
        Path::new(&app_dir),
        &key,
        Path::new(&source_path),
        &mut on_event,
        &should_cancel,
    )?;
    emit_result(&sink, summary);
    Ok(())
}

#[flutter_rust_bridge::frb]
pub fn external_import_phase_b_run_progress(
    app_dir: String,
    key: Vec<u8>,
    batch_id: String,
    sink: StreamSink<String>,
) -> Result<()> {
    let key = key_from_bytes(key)?;
    let mut on_event = |progress: db::ExternalImportProgress| {
        emit_progress(&sink, progress);
    };
    let state = db::run_external_import_phase_b_with_callbacks(
        Path::new(&app_dir),
        &key,
        &batch_id,
        &mut on_event,
    )?;
    let payload = serde_json::json!({
        "type": "phase_b_result",
        "batch_id": batch_id,
        "state": state,
    })
    .to_string();
    let _ = sink.add(payload);
    Ok(())
}
