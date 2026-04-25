use std::fs;
use std::io::Write as _;

use super::*;

const VALID_TEST_ATTACHMENT_SHA256: &str =
    "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

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
