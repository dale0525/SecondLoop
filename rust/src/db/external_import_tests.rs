use std::cell::Cell;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

use tempfile::tempdir;
use zip::write::FileOptions;

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

fn create_generic_markdown_source(root: &Path) -> PathBuf {
    let source = root.join("markdown-library");
    write_text(
        &source.join("travel/plan.md"),
        "---\ntags:\n  - travel\n  - budget\n---\n# Trip Plan\n\nBudget checklist and hotel notes.\n\nSee [[expense-sheet|expense sheet]] and [[summary#Costs]].\n\n![[../assets/ticket.png]]\n",
    );
    write_text(
        &source.join("travel/expense-sheet.markdown"),
        "# Expense Sheet\n\nRemember the flight refund and budget cap.\n\n[Receipt](../assets/receipt.pdf)\n",
    );
    write_text(
        &source.join("travel/summary.mdown"),
        "# Summary\n\n## Costs\n\nThe shared budget summary stays searchable.\n",
    );
    write_text(
        &source.join("archive/notes.mkd"),
        "# Archive Notes\n\nReference back to [[travel/summary]].\n",
    );
    write_bytes(&source.join("assets/ticket.png"), b"png-binary");
    write_bytes(&source.join("assets/receipt.pdf"), b"pdf-binary");
    write_bytes(&source.join("assets/orphan.txt"), b"unused");
    source
}

fn create_markdown_source_with_missing_attachment(root: &Path) -> PathBuf {
    let source = root.join("markdown-library-missing-attachment");
    write_text(
        &source.join("travel/plan.md"),
        "# Trip Plan\n\nAttachment is referenced but missing.\n\n[Missing](assets/missing.pdf)\n",
    );
    source
}

fn create_markdown_source_with_ambiguous_wikilink(root: &Path) -> PathBuf {
    let source = root.join("markdown-library-ambiguous");
    write_text(
        &source.join("home.md"),
        "# Home\n\nSee [[overview]] for details.\n",
    );
    write_text(
        &source.join("team/overview.md"),
        "# Team Overview\n\nRoadmap details for one team.\n",
    );
    write_text(
        &source.join("archive/overview.markdown"),
        "# Archive Overview\n\nOlder roadmap notes.\n",
    );
    source
}

fn create_generic_markdown_zip(root: &Path) -> PathBuf {
    let source = create_generic_markdown_source(root);
    let zip_path = root.join("markdown-library.zip");
    let file = fs::File::create(&zip_path).expect("create zip");
    let mut writer = zip::ZipWriter::new(file);
    let options = FileOptions::default();

    let mut files = Vec::<PathBuf>::new();
    collect_files_recursively(&source, &mut files).expect("collect source files");
    files.sort();
    for path in files {
        let rel = path
            .strip_prefix(&source)
            .expect("strip prefix")
            .to_string_lossy()
            .replace('\\', "/");
        writer.start_file(rel, options).expect("start zip file");
        let bytes = fs::read(&path).expect("read source file");
        writer.write_all(&bytes).expect("write zip entry");
    }

    writer.finish().expect("finish zip");
    zip_path
}

fn create_zip_with_oversized_entry(root: &Path) -> PathBuf {
    let zip_path = root.join("oversized-markdown-library.zip");
    let file = fs::File::create(&zip_path).expect("create oversized zip");
    let mut writer = zip::ZipWriter::new(file);
    let options = FileOptions::default();
    writer
        .start_file("notes/too-large.md", options)
        .expect("start oversized entry");
    let chunk = vec![b'a'; 1024 * 1024];
    for _ in 0..65 {
        writer.write_all(&chunk).expect("write oversized chunk");
    }
    writer.finish().expect("finish oversized zip");
    zip_path
}

#[test]
fn external_import_scan_detects_generic_markdown_notes_and_attachments() {
    let dir = tempdir().expect("tempdir");
    let source = create_generic_markdown_source(dir.path());

    let summary = scan_external_import_source(dir.path(), &source).expect("scan");

    assert_eq!(summary.detected_source_kind, "markdown");
    assert_eq!(summary.notes_count, 4);
    assert_eq!(summary.attachments_count, 2);
    assert!(summary.estimated_disk_usage_bytes >= 32);
    assert!(summary.warnings.is_empty());
}

#[test]
fn external_import_scan_supports_zip_sources() {
    let dir = tempdir().expect("tempdir");
    let source = create_generic_markdown_zip(dir.path());

    let summary = scan_external_import_source(dir.path(), &source).expect("scan zip");

    assert_eq!(summary.detected_source_kind, "markdown");
    assert_eq!(summary.notes_count, 4);
    assert_eq!(summary.attachments_count, 2);
}

#[test]
fn external_import_scan_rejects_oversized_zip_entries() {
    let dir = tempdir().expect("tempdir");
    let source = create_zip_with_oversized_entry(dir.path());

    let err =
        scan_external_import_source(dir.path(), &source).expect_err("oversized zip should fail");

    assert!(err.to_string().contains("archive entry exceeds size limit"));
}

#[test]
fn external_import_imports_docs_and_keeps_wikilink_notes_out_of_attachment_refs() {
    let dir = tempdir().expect("tempdir");
    let app_dir = dir.path().join("app");
    let source = create_generic_markdown_source(dir.path());
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
    assert_eq!(batch.source_kind, "markdown");
    assert_eq!(batch.notes_count, 4);
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
    let source = create_generic_markdown_source(dir.path());
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
    let source = create_generic_markdown_source(dir.path());
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
fn external_import_batch_report_json_includes_terminal_metrics() {
    let dir = tempdir().expect("tempdir");
    let app_dir = dir.path().join("app");
    let source = create_generic_markdown_source(dir.path());
    let key = [15u8; 32];

    let batch = run_external_import_with_callbacks(&app_dir, &key, &source, &mut |_| {}, &|| false)
        .expect("import");

    let report =
        read_external_import_batch_report_json(&app_dir, &batch.batch_id).expect("read report");
    let json: serde_json::Value = serde_json::from_str(&report).expect("report json");

    assert_eq!(json["status"].as_str(), Some("completed"));
    assert_eq!(json["source_kind"].as_str(), Some("markdown"));
    assert_eq!(json["success_count"].as_i64(), Some(4));
    assert_eq!(json["copied_attachment_count"].as_i64(), Some(2));
    assert_eq!(json["failed_count"].as_i64(), Some(0));
    assert!(json["disk_usage_bytes"].as_i64().unwrap_or(0) > 0);
    assert!(json["elapsed_ms"].as_i64().unwrap_or(-1) >= 0);
}

#[test]
fn external_import_batch_report_json_includes_parse_diagnostics() {
    let dir = tempdir().expect("tempdir");
    let app_dir = dir.path().join("app");
    let source = create_markdown_source_with_missing_attachment(dir.path());
    let key = [17u8; 32];

    let batch = run_external_import_with_callbacks(&app_dir, &key, &source, &mut |_| {}, &|| false)
        .expect("import");

    let report =
        read_external_import_batch_report_json(&app_dir, &batch.batch_id).expect("read report");
    let json: serde_json::Value = serde_json::from_str(&report).expect("report json");
    let diagnostics = json["diagnostics"].as_array().expect("diagnostics array");

    assert!(!diagnostics.is_empty());
    assert!(diagnostics.iter().any(|item| {
        item["code"].as_str() == Some("missing_attachment_reference")
            && item["message"]
                .as_str()
                .unwrap_or_default()
                .contains("missing attachment reference")
    }));
}

#[test]
fn external_import_reports_ambiguous_wikilinks_without_failing_batch() {
    let dir = tempdir().expect("tempdir");
    let app_dir = dir.path().join("app");
    let source = create_markdown_source_with_ambiguous_wikilink(dir.path());
    let key = [19u8; 32];

    let batch = run_external_import_with_callbacks(&app_dir, &key, &source, &mut |_| {}, &|| false)
        .expect("import");
    assert_eq!(batch.status, "completed");

    let report =
        read_external_import_batch_report_json(&app_dir, &batch.batch_id).expect("read report");
    let json: serde_json::Value = serde_json::from_str(&report).expect("report json");
    let diagnostics = json["diagnostics"].as_array().expect("diagnostics array");

    assert!(diagnostics.iter().any(|item| {
        item["code"].as_str() == Some("ambiguous_wikilink_target")
            && item["message"]
                .as_str()
                .unwrap_or_default()
                .contains("overview")
    }));
}
