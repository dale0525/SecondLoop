use std::cell::Cell;
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

fn create_obsidian_source(root: &Path) -> PathBuf {
    let source = root.join("obsidian-vault");
    fs::create_dir_all(source.join(".obsidian")).expect("obsidian dir");
    write_text(
        &source.join("travel/plan.md"),
        "---\ntags:\n  - travel\n  - budget\n---\n# Trip Plan\n\nBudget checklist and hotel notes.\n\n![[assets/ticket.png]]\n",
    );
    write_text(
        &source.join("travel/expenses.md"),
        "# Expense Sheet\n\nRemember the flight refund and budget cap.\n\n[PDF](assets/receipt.pdf)\n",
    );
    write_bytes(&source.join("assets/ticket.png"), b"png-binary");
    write_bytes(&source.join("assets/receipt.pdf"), b"pdf-binary");
    source
}

fn create_siyuan_source(root: &Path) -> PathBuf {
    let source = root.join("siyuan-export");
    let doc_json = r#"{
  \"title\": \"Project Notes\",
  \"blocks\": [
    {\"type\": \"h1\", \"content\": \"Weekly Review\"},
    {\"type\": \"p\", \"content\": \"Budget discussion and roadmap alignment\"},
    {\"type\": \"img\", \"path\": \"assets/review.png\"}
  ]
}"#;
    write_text(&source.join("data/boxA/project-notes.sy"), doc_json);
    write_bytes(&source.join("assets/review.png"), b"review-png");
    source
}

#[test]
fn external_import_scan_detects_obsidian_notes_and_attachments() {
    let dir = tempdir().expect("tempdir");
    let source = create_obsidian_source(dir.path());

    let summary = scan_external_import_source(dir.path(), &source).expect("scan");

    assert_eq!(summary.detected_source_kind, "obsidian");
    assert_eq!(summary.notes_count, 2);
    assert_eq!(summary.attachments_count, 2);
    assert!(summary.estimated_disk_usage_bytes >= 20);
    assert!(summary.warnings.is_empty());
}

#[test]
fn external_import_imports_docs_and_supports_default_search() {
    let dir = tempdir().expect("tempdir");
    let app_dir = dir.path().join("app");
    let source = create_obsidian_source(dir.path());
    let key = [7u8; 32];

    let mut progress_events = Vec::<ExternalImportProgress>::new();
    let batch = run_external_import_with_callbacks(
        &app_dir,
        &key,
        &source,
        &mut |event| progress_events.push(event.clone()),
        &|| false,
    )
    .expect("import");

    assert_eq!(batch.status, "completed");
    assert_eq!(batch.notes_count, 2);
    assert_eq!(batch.attachments_count, 2);
    assert!(progress_events
        .iter()
        .any(|event| event.stage == "indexing_phase_a"));

    let hits =
        search_similar_external_document_chunks_default(&app_dir, &key, "flight refund budget", 5)
            .expect("search external");
    assert!(!hits.is_empty());
    assert!(hits
        .iter()
        .any(|hit| hit.snippet.to_lowercase().contains("budget")));

    let external = open_external_readonly_db(&app_dir).expect("open external");
    let attachment_refs: i64 = external
        .query_row(
            "SELECT COUNT(*) FROM external_document_attachments WHERE doc_id IN (SELECT doc_id FROM external_documents WHERE batch_id = ?1)",
            rusqlite::params![batch.batch_id],
            |row| row.get(0),
        )
        .expect("count refs");
    assert_eq!(attachment_refs, 2);
}

#[test]
fn external_import_delete_batch_removes_docs_and_attachment_files() {
    let dir = tempdir().expect("tempdir");
    let app_dir = dir.path().join("app");
    let source = create_obsidian_source(dir.path());
    let key = [9u8; 32];

    let batch = run_external_import_with_callbacks(&app_dir, &key, &source, &mut |_| {}, &|| false)
        .expect("import");

    let external = open_external_readonly_db(&app_dir).expect("open external");
    let stored_path: String = external
        .query_row(
            "SELECT stored_path FROM external_attachments LIMIT 1",
            [],
            |row| row.get(0),
        )
        .expect("attachment path");
    let full_attachment_path = app_dir.join(stored_path);
    assert!(full_attachment_path.exists());

    delete_external_import_batch(&app_dir, &batch.batch_id).expect("delete batch");

    let external = open_external_readonly_db(&app_dir).expect("reopen external");
    let batch_count: i64 = external
        .query_row(
            "SELECT COUNT(*) FROM external_import_batches WHERE batch_id = ?1",
            rusqlite::params![batch.batch_id],
            |row| row.get(0),
        )
        .expect("batch count");
    assert_eq!(batch_count, 0);
    assert!(!full_attachment_path.exists());

    let hits = search_similar_external_document_chunks_default(&app_dir, &key, "budget", 5)
        .expect("search after delete");
    assert!(hits.is_empty());
}

#[test]
fn external_import_cancel_rolls_back_imported_docs_and_files() {
    let dir = tempdir().expect("tempdir");
    let app_dir = dir.path().join("app");
    let source = create_obsidian_source(dir.path());
    let key = [11u8; 32];
    let should_cancel = Cell::new(false);
    let mut saw_copy_stage = false;

    let batch = run_external_import_with_callbacks(
        &app_dir,
        &key,
        &source,
        &mut |event| {
            if event.stage == "copying_attachments" {
                saw_copy_stage = true;
                should_cancel.set(true);
            }
        },
        &|| should_cancel.get(),
    )
    .expect("cancel import");

    assert!(saw_copy_stage);
    assert_eq!(batch.status, "cancelled");

    let external = open_external_readonly_db(&app_dir).expect("open external");
    let docs_left: i64 = external
        .query_row(
            "SELECT COUNT(*) FROM external_documents WHERE batch_id = ?1",
            rusqlite::params![batch.batch_id],
            |row| row.get(0),
        )
        .expect("docs count");
    let refs_left: i64 = external
        .query_row(
            "SELECT COUNT(*) FROM external_document_attachments",
            [],
            |row| row.get(0),
        )
        .expect("refs count");
    assert_eq!(docs_left, 0);
    assert_eq!(refs_left, 0);
}

#[test]
fn external_import_parses_siyuan_sy_json_best_effort() {
    let dir = tempdir().expect("tempdir");
    let app_dir = dir.path().join("app");
    let source = create_siyuan_source(dir.path());
    let key = [13u8; 32];

    let summary = scan_external_import_source(&app_dir, &source).expect("scan siyuan");
    assert_eq!(summary.detected_source_kind, "siyuan");
    assert_eq!(summary.notes_count, 1);

    let batch = run_external_import_with_callbacks(&app_dir, &key, &source, &mut |_| {}, &|| false)
        .expect("import siyuan");
    assert_eq!(batch.status, "completed");

    let hits =
        search_similar_external_document_chunks_default(&app_dir, &key, "roadmap alignment", 5)
            .expect("search siyuan");
    assert_eq!(hits.len(), 1);
    assert!(hits[0].snippet.to_lowercase().contains("roadmap"));
}
