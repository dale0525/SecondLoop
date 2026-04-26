use std::fs;
use std::io::Write as _;

use super::*;

const VALID_TEST_ATTACHMENT_SHA256: &str =
    "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

fn test_sha256_hex(bytes: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    let digest = hasher.finalize();
    let mut out = String::with_capacity(digest.len() * 2);
    for b in digest {
        use std::fmt::Write;
        let _ = write!(&mut out, "{b:02x}");
    }
    out
}

fn write_attachment_import_archive(
    archive_path: &std::path::Path,
    manifest_sha256: &str,
    manifest_size_bytes: i64,
    attachment_bytes: &[u8],
) {
    let file = fs::File::create(archive_path).expect("create archive");
    let mut writer = zip::ZipWriter::new(file);
    let options = zip::write::FileOptions::default();
    let manifest = MigrationArchiveManifest {
        schema_version: 1,
        archive_kind: "migration".to_string(),
        exported_at_ms: 1,
        app_version: "1.0.0".to_string(),
        items: vec![
            MigrationArchiveItem {
                id: "conversation_import".to_string(),
                entity_type: "conversation".to_string(),
                markdown_path: "items/conversation_import.md".to_string(),
                created_at_ms: 1,
                updated_at_ms: 1,
                title: "Import".to_string(),
                tags: vec![],
                status: None,
                extra_json: None,
            },
            MigrationArchiveItem {
                id: "message_import".to_string(),
                entity_type: "message".to_string(),
                markdown_path: "items/message_import.md".to_string(),
                created_at_ms: 1,
                updated_at_ms: 1,
                title: "Import message".to_string(),
                tags: vec![],
                status: None,
                extra_json: Some(
                    r#"{"conversation_id":"conversation_import","role":"user","content":"hello"}"#
                        .to_string(),
                ),
            },
        ],
        attachments: vec![MigrationArchiveAttachment {
            sha256: manifest_sha256.to_string(),
            archive_path: format!("attachments/{manifest_sha256}.bin"),
            original_filename: "attachment.bin".to_string(),
            mime_type: Some("application/octet-stream".to_string()),
            size_bytes: manifest_size_bytes,
            item_ids: vec!["message_import".to_string()],
        }],
        relations: vec![],
    };

    writer
        .start_file("export-manifest.json", options)
        .expect("manifest entry");
    writer
        .write_all(
            serde_json::to_string(&manifest)
                .expect("manifest json")
                .as_bytes(),
        )
        .expect("write manifest");
    writer
        .start_file("items/conversation_import.md", options)
        .expect("conversation entry");
    writer.write_all(b"# Import\n").expect("write conversation");
    writer
        .start_file("items/message_import.md", options)
        .expect("message entry");
    writer.write_all(b"hello\n").expect("write message");
    writer
        .start_file(format!("attachments/{manifest_sha256}.bin"), options)
        .expect("attachment entry");
    writer
        .write_all(attachment_bytes)
        .expect("write attachment");
    writer.finish().expect("finish archive");
}

#[test]
fn migration_archive_manifest_validation_rejects_attachment_sha256_path_traversal() {
    let json = r#"{
        "schema_version": 1,
        "archive_kind": "migration",
        "exported_at_ms": 1710000000000,
        "app_version": "1.2.3",
        "items": [],
        "attachments": [
          {
            "sha256": "../../escape",
            "archive_path": "attachments/blob.bin",
            "original_filename": "blob.bin",
            "mime_type": "application/octet-stream",
            "size_bytes": 42,
            "item_ids": []
          }
        ],
        "relations": []
      }"#;

    let err = parse_migration_archive_manifest_json(json)
        .expect_err("attachment sha256 path traversal should fail");

    assert!(err.to_string().contains("attachment sha256"));
}

#[test]
fn migration_archive_manifest_validation_rejects_item_markdown_path_traversal() {
    let json = r#"{
        "schema_version": 1,
        "archive_kind": "migration",
        "exported_at_ms": 1710000000000,
        "app_version": "1.2.3",
        "items": [
          {
            "id": "todo_01HXYZ",
            "entity_type": "todo",
            "markdown_path": "../todo.md",
            "created_at_ms": 1710000000000,
            "updated_at_ms": 1710000000500,
            "title": "Buy milk",
            "tags": [],
            "status": "open",
            "extra_json": null
          }
        ],
        "attachments": [],
        "relations": []
      }"#;

    let err = parse_migration_archive_manifest_json(json)
        .expect_err("item markdown path traversal should fail");

    assert!(err.to_string().contains("item markdown_path"));
}

#[test]
fn migration_archive_import_rejects_attachment_sha256_mismatch() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().join("app");
    let key = [61u8; 32];
    let archive_path = dir.path().join("bad-attachment-sha.zip");
    let attachment_bytes = b"actual attachment bytes";

    write_attachment_import_archive(
        &archive_path,
        VALID_TEST_ATTACHMENT_SHA256,
        attachment_bytes.len() as i64,
        attachment_bytes,
    );

    let err = import_migration_archive(&app_dir, &key, &archive_path)
        .expect_err("sha256 mismatch should fail import");

    assert!(
        err.to_string().contains("attachment sha256 mismatch"),
        "unexpected error: {err}"
    );
}

#[test]
fn migration_archive_import_rejects_attachment_size_mismatch() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().join("app");
    let key = [62u8; 32];
    let archive_path = dir.path().join("bad-attachment-size.zip");
    let attachment_bytes = b"actual attachment bytes";
    let sha256 = test_sha256_hex(attachment_bytes);

    write_attachment_import_archive(
        &archive_path,
        &sha256,
        attachment_bytes.len() as i64 + 1,
        attachment_bytes,
    );

    let err = import_migration_archive(&app_dir, &key, &archive_path)
        .expect_err("size mismatch should fail import");

    assert!(
        err.to_string().contains("attachment size mismatch"),
        "unexpected error: {err}"
    );
}

#[test]
fn migration_archive_import_rolls_back_knowledge_only_vault_when_archive_restore_fails() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().join("app");
    let conn = open(&app_dir).expect("open db");
    let key = [14u8; 32];

    conn.execute(
        r#"INSERT INTO knowledge_pages(
          page_id, page_type, state, created_at_ms, updated_at_ms,
          tags_json, primary_evidence_json, related_page_ids_json,
          source_document_ids_json, claim_ids_json,
          compiled_title, compiled_summary, compiled_body
        ) VALUES (
          'page-knowledge-only', 'fact', 'active', 1, 1,
          '[]', '[]', '[]', '[]', '[]',
          X'7469746C65', X'73756D6D617279', X'626F6479'
        )"#,
        [],
    )
    .expect("insert knowledge page");
    drop(conn);

    let bad_archive_path = dir.path().join("bad-knowledge-import.zip");
    let file = fs::File::create(&bad_archive_path).expect("create bad zip");
    let mut writer = zip::ZipWriter::new(file);
    let options = zip::write::FileOptions::default();
    let missing_sha = VALID_TEST_ATTACHMENT_SHA256;
    let manifest = MigrationArchiveManifest {
        schema_version: 1,
        archive_kind: "migration".to_string(),
        exported_at_ms: 1,
        app_version: "1.0.0".to_string(),
        items: vec![MigrationArchiveItem {
            id: "conversation_import".to_string(),
            entity_type: "conversation".to_string(),
            markdown_path: "items/conversation_import.md".to_string(),
            created_at_ms: 1,
            updated_at_ms: 1,
            title: "Broken Import".to_string(),
            tags: vec![],
            status: None,
            extra_json: None,
        }],
        attachments: vec![MigrationArchiveAttachment {
            sha256: missing_sha.to_string(),
            archive_path: format!("attachments/{missing_sha}.png"),
            original_filename: "missing.png".to_string(),
            mime_type: Some("image/png".to_string()),
            size_bytes: 9,
            item_ids: vec!["conversation_import".to_string()],
        }],
        relations: vec![],
    };
    writer
        .start_file("export-manifest.json", options)
        .expect("manifest entry");
    writer
        .write_all(
            serde_json::to_string(&manifest)
                .expect("manifest json")
                .as_bytes(),
        )
        .expect("write manifest");
    writer
        .start_file("items/conversation_import.md", options)
        .expect("item entry");
    writer.write_all(b"# Broken Import\n").expect("write item");
    writer.finish().expect("finish bad zip");

    import_migration_archive(&app_dir, &key, &bad_archive_path)
        .expect_err("import should fail and rollback");

    let conn = open(&app_dir).expect("reopen db");
    let count_after_rollback: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM knowledge_pages WHERE page_id = 'page-knowledge-only'",
            [],
            |row| row.get(0),
        )
        .expect("count knowledge pages after rollback");
    assert_eq!(count_after_rollback, 1);
}

#[test]
fn vault_rollback_snapshot_uses_chunked_encrypted_file_format() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().join("app");
    let conn = open(&app_dir).expect("open db");
    let key = [56u8; 32];

    create_conversation(&conn, &key, "Chunked snapshot").expect("conversation");
    drop(conn);

    let snapshot_path = migration_archive_create_rollback_snapshot(&app_dir, &key)
        .expect("create snapshot")
        .expect("snapshot path");

    let snapshot_bytes = fs::read(&snapshot_path).expect("read snapshot");
    assert!(snapshot_bytes.starts_with(b"SLVRB2\0\0"));

    migration_archive_restore_rollback_snapshot(&app_dir, &key, &snapshot_path)
        .expect("restore chunked snapshot");
}

#[test]
fn vault_rollback_snapshot_active_marker_survives_registry_reset() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().join("app");
    let conn = open(&app_dir).expect("open db");
    let key = [57u8; 32];

    create_conversation(&conn, &key, "Persistent marker").expect("conversation");
    drop(conn);

    let snapshot_path = migration_archive_create_rollback_snapshot(&app_dir, &key)
        .expect("create snapshot")
        .expect("snapshot path");

    migration_archive_clear_active_rollback_snapshots_for_test();

    assert!(
        migration_archive_is_active_rollback_snapshot(&app_dir, &snapshot_path)
            .expect("read active marker"),
        "active rollback snapshot marker should survive process-local registry loss"
    );
}

#[test]
fn migration_archive_internal_snapshot_cleanup_keeps_marker_when_removal_fails() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().join("app");
    let conn = open(&app_dir).expect("open db");
    let key = [58u8; 32];

    create_conversation(&conn, &key, "Cleanup failure marker").expect("conversation");
    drop(conn);

    let snapshot_path = migration_archive_create_rollback_snapshot(&app_dir, &key)
        .expect("create snapshot")
        .expect("snapshot path");
    fs::remove_file(&snapshot_path).expect("remove snapshot file");
    fs::create_dir(&snapshot_path).expect("create removal blocker");

    let cleanup_error = migration_archive_remove_snapshot(Some(&snapshot_path))
        .expect_err("cleanup failure should be returned");
    assert!(!cleanup_error.to_string().is_empty());

    assert!(
        migration_archive_is_active_rollback_snapshot(&app_dir, &snapshot_path)
            .expect("read active marker"),
        "failed cleanup should keep active marker for retry"
    );
}
