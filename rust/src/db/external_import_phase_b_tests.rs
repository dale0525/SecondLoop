use std::fs;
use std::path::{Path, PathBuf};

use tempfile::tempdir;

use super::*;

fn write_text(path: &Path, text: &str) {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).expect("create parent");
    }
    fs::write(path, text).expect("write text");
}

fn write_bytes(path: &Path, bytes: &[u8]) {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).expect("create parent");
    }
    fs::write(path, bytes).expect("write bytes");
}

fn create_obsidian_source_with_text_attachments(root: &Path) -> PathBuf {
    let source = root.join("obsidian-vault-phase-b");
    fs::create_dir_all(source.join(".obsidian")).expect("obsidian dir");
    write_text(
        &source.join("notes/research.md"),
        "# Research\n\nAttachment details live in the linked files.\n\n[Spec](assets/spec.txt)\n\n[Budget](assets/budget.txt)\n",
    );
    write_text(
        &source.join("assets/spec.txt"),
        "Phase B should extract deeper attachment text into the external search index.",
    );
    write_text(
        &source.join("assets/budget.txt"),
        "Budget cap is 1200 and the hotel refund window closes next Tuesday.",
    );
    source
}

fn create_obsidian_source_with_varied_phase_b_attachments(root: &Path) -> PathBuf {
    let source = root.join("obsidian-vault-phase-b-varied");
    fs::create_dir_all(source.join(".obsidian")).expect("obsidian dir");
    write_text(
        &source.join("notes/research.md"),
        "# Research

[Spec](assets/spec.txt)

[Manual](assets/manual.pdf)

![Preview](assets/preview.png)
",
    );
    write_text(
        &source.join("assets/spec.txt"),
        "Short plain text attachment for baseline extraction.",
    );
    write_bytes(&source.join("assets/manual.pdf"), &vec![b'P'; 1_800_000]);
    write_bytes(&source.join("assets/preview.png"), &vec![0x89; 640_000]);
    source
}

#[test]
fn external_import_phase_b_estimates_eligible_attachment_work() {
    let dir = tempdir().expect("tempdir");
    let app_dir = dir.path().join("app");
    let source = create_obsidian_source_with_text_attachments(dir.path());
    let key = [21u8; 32];

    let batch = run_external_import_with_callbacks(&app_dir, &key, &source, &mut |_| {}, &|| false)
        .expect("import");

    let estimate = estimate_external_import_phase_b(&app_dir, &batch.batch_id).expect("estimate");
    assert_eq!(estimate["eligible_attachment_count"].as_i64(), Some(2));
    assert_eq!(estimate["remaining_attachment_count"].as_i64(), Some(2));
    assert!(estimate["estimated_runtime_seconds"].as_i64().unwrap_or(0) >= 2);
}

#[test]
fn external_import_phase_b_estimate_uses_mime_and_size_weighted_costs() {
    let dir = tempdir().expect("tempdir");
    let app_dir = dir.path().join("app");
    let source = create_obsidian_source_with_varied_phase_b_attachments(dir.path());
    let key = [24u8; 32];

    let batch = run_external_import_with_callbacks(&app_dir, &key, &source, &mut |_| {}, &|| false)
        .expect("import");

    let estimate = estimate_external_import_phase_b(&app_dir, &batch.batch_id).expect("estimate");
    assert_eq!(estimate["eligible_attachment_count"].as_i64(), Some(3));
    assert_eq!(estimate["remaining_attachment_count"].as_i64(), Some(3));
    assert!(estimate["estimated_runtime_seconds"].as_i64().unwrap_or(0) > 6);
    assert!(estimate["estimated_local_work_units"].as_i64().unwrap_or(0) > 3);
    assert!(estimate["estimated_cloud_tokens"].as_i64().unwrap_or(0) > 0);
}

#[test]
fn external_import_phase_b_estimate_shrinks_after_partial_completion() {
    let dir = tempdir().expect("tempdir");
    let app_dir = dir.path().join("app");
    let source = create_obsidian_source_with_text_attachments(dir.path());
    let key = [25u8; 32];

    let batch = run_external_import_with_callbacks(&app_dir, &key, &source, &mut |_| {}, &|| false)
        .expect("import");

    let initial =
        estimate_external_import_phase_b(&app_dir, &batch.batch_id).expect("initial estimate");

    let external = open_external_readonly_db(&app_dir).expect("open external");
    seed_external_import_phase_b_attachment_progress_for_test(
        &app_dir,
        &external,
        &key,
        &batch.batch_id,
    )
    .expect("seed persisted progress");

    let after =
        estimate_external_import_phase_b(&app_dir, &batch.batch_id).expect("updated estimate");
    assert_eq!(after["remaining_attachment_count"].as_i64(), Some(1));
    assert!(
        after["estimated_runtime_seconds"]
            .as_i64()
            .unwrap_or(i64::MAX)
            < initial["estimated_runtime_seconds"].as_i64().unwrap_or(0)
    );
    assert!(
        after["estimated_local_bytes"].as_i64().unwrap_or(i64::MAX)
            < initial["estimated_local_bytes"].as_i64().unwrap_or(0)
    );
    assert!(
        after["estimated_local_work_units"]
            .as_i64()
            .unwrap_or(i64::MAX)
            < initial["estimated_local_work_units"].as_i64().unwrap_or(0)
    );
    assert!(
        after["estimated_cloud_tokens"].as_i64().unwrap_or(i64::MAX)
            < initial["estimated_cloud_tokens"].as_i64().unwrap_or(0)
    );
}

#[test]
fn external_import_phase_b_enriches_text_attachments_into_external_search() {
    let dir = tempdir().expect("tempdir");
    let app_dir = dir.path().join("app");
    let source = create_obsidian_source_with_text_attachments(dir.path());
    let key = [22u8; 32];

    let batch = run_external_import_with_callbacks(&app_dir, &key, &source, &mut |_| {}, &|| false)
        .expect("import");

    let mut progress = Vec::<ExternalImportProgress>::new();
    let state =
        run_external_import_phase_b_with_callbacks(&app_dir, &key, &batch.batch_id, &mut |event| {
            progress.push(event.clone())
        })
        .expect("phase b");

    assert_eq!(state["phase_b_status"].as_str(), Some("completed"));
    assert!(progress
        .iter()
        .any(|event| event.stage == "indexing_phase_b"));

    let hits = search_similar_external_document_chunks_default(
        &app_dir,
        &key,
        "hotel refund window 1200",
        5,
    )
    .expect("search external");
    assert!(hits
        .iter()
        .any(|hit| hit.snippet.to_lowercase().contains("refund window")));
}

#[test]
fn external_import_phase_b_resumes_from_persisted_attachment_progress() {
    let dir = tempdir().expect("tempdir");
    let app_dir = dir.path().join("app");
    let source = create_obsidian_source_with_text_attachments(dir.path());
    let key = [23u8; 32];

    let batch = run_external_import_with_callbacks(&app_dir, &key, &source, &mut |_| {}, &|| false)
        .expect("import");

    let external = open_external_readonly_db(&app_dir).expect("open external");
    seed_external_import_phase_b_attachment_progress_for_test(
        &app_dir,
        &external,
        &key,
        &batch.batch_id,
    )
    .expect("seed persisted progress");

    let state =
        run_external_import_phase_b_with_callbacks(&app_dir, &key, &batch.batch_id, &mut |_| {})
            .expect("resume phase b");

    assert_eq!(state["phase_b_status"].as_str(), Some("completed"));
    assert_eq!(state["processed_attachment_count"].as_i64(), Some(2));
    assert!(state["enriched_chunk_count"].as_i64().unwrap_or(0) >= 2);
}
