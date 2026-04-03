use std::fs;
use std::io::Read;
use std::path::Path;

use super::*;

fn read_zip_entry_text(zip_path: &Path, entry_name: &str) -> String {
    let file = fs::File::open(zip_path).expect("open zip");
    let mut archive = zip::ZipArchive::new(file).expect("read zip");
    let mut entry = archive.by_name(entry_name).expect("zip entry");
    let mut text = String::new();
    entry
        .read_to_string(&mut text)
        .expect("read zip entry text");
    text
}

fn zip_has_entry(zip_path: &Path, entry_name: &str) -> bool {
    let file = fs::File::open(zip_path).expect("open zip");
    let mut archive = zip::ZipArchive::new(file).expect("read zip");
    let present = archive.by_name(entry_name).is_ok();
    present
}

#[test]
fn migration_archive_manifest_round_trip_preserves_core_fields() {
    let manifest = MigrationArchiveManifest {
        schema_version: 1,
        archive_kind: "migration".to_string(),
        exported_at_ms: 1_710_000_000_000,
        app_version: "1.2.3".to_string(),
        items: vec![MigrationArchiveItem {
            id: "todo_01HXYZ".to_string(),
            entity_type: "todo".to_string(),
            markdown_path: "items/todo_01HXYZ.md".to_string(),
            created_at_ms: 1_710_000_000_000,
            updated_at_ms: 1_710_000_000_500,
            title: "Buy milk".to_string(),
            tags: vec!["errand".to_string()],
            status: Some("open".to_string()),
            extra_json: None,
        }],
        attachments: vec![MigrationArchiveAttachment {
            sha256: "abc123".to_string(),
            archive_path: "attachments/abc123.png".to_string(),
            original_filename: "milk.png".to_string(),
            mime_type: Some("image/png".to_string()),
            size_bytes: 42,
            item_ids: vec!["todo_01HXYZ".to_string()],
        }],
        relations: vec![MigrationArchiveRelation {
            from_id: "todo_01HXYZ".to_string(),
            to_id: "msg_01HABC".to_string(),
            relation_type: "related_to".to_string(),
        }],
    };

    let json = serde_json::to_string(&manifest).expect("serialize manifest");
    let decoded: MigrationArchiveManifest =
        serde_json::from_str(&json).expect("deserialize manifest");

    assert_eq!(decoded.schema_version, 1);
    assert_eq!(decoded.archive_kind, "migration");
    assert_eq!(decoded.items.len(), 1);
    assert_eq!(decoded.attachments.len(), 1);
    assert_eq!(decoded.relations.len(), 1);
    assert_eq!(decoded.items[0].markdown_path, "items/todo_01HXYZ.md");
}

#[test]
fn migration_archive_item_markdown_path_uses_items_prefix_and_md_extension() {
    assert_eq!(
        migration_archive_markdown_path_for_id("todo_01HXYZ"),
        "items/todo_01HXYZ.md"
    );
}

#[test]
fn migration_archive_wikilink_uses_stable_id_and_title_alias() {
    assert_eq!(
        migration_archive_wikilink("todo_01HXYZ", "Buy milk"),
        "[[todo_01HXYZ|Buy milk]]"
    );
}

#[test]
fn migration_archive_manifest_validation_rejects_missing_required_fields() {
    let json = r#"{
        "schema_version": 1,
        "archive_kind": "migration",
        "exported_at_ms": 1710000000000,
        "app_version": "1.2.3",
        "items": [
          {
            "id": "todo_01HXYZ",
            "entity_type": "todo",
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

    let err = parse_migration_archive_manifest_json(json).expect_err("missing path should fail");

    assert!(err.to_string().contains("markdown_path"));
}

#[test]
fn migration_archive_manifest_validation_rejects_newer_schema_version() {
    let json = r#"{
        "schema_version": 2,
        "archive_kind": "migration",
        "exported_at_ms": 1710000000000,
        "app_version": "1.2.3",
        "items": [],
        "attachments": [],
        "relations": []
      }"#;

    let err = parse_migration_archive_manifest_json(json).expect_err("newer schema should fail");

    assert!(err.to_string().contains("newer than this build supports"));
}

#[test]
fn migration_archive_manifest_validation_rejects_attachment_path_traversal() {
    let json = r#"{
        "schema_version": 1,
        "archive_kind": "migration",
        "exported_at_ms": 1710000000000,
        "app_version": "1.2.3",
        "items": [],
        "attachments": [
          {
            "sha256": "abc123",
            "archive_path": "../../../secret.txt",
            "original_filename": "secret.txt",
            "mime_type": "text/plain",
            "size_bytes": 42,
            "item_ids": []
          }
        ],
        "relations": []
      }"#;

    let err = parse_migration_archive_manifest_json(json)
        .expect_err("attachment path traversal should fail");

    assert!(err.to_string().contains("attachment archive_path"));
}

#[test]
fn migration_archive_export_writes_manifest_markdown_and_deduplicated_attachments() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().join("app");
    let conn = open(&app_dir).expect("open db");
    let key = [5u8; 32];

    let conversation = create_conversation(&conn, &key, "Inbox").expect("conversation");
    let message =
        insert_message(&conn, &key, &conversation.id, "user", "Need to buy milk").expect("message");
    let tag = upsert_tag(&conn, &key, "errand").expect("tag");
    set_message_tags(&conn, &key, &message.id, std::slice::from_ref(&tag.id)).expect("set tags");

    let attachment =
        insert_attachment(&conn, &key, &app_dir, b"png-binary", "image/png").expect("attachment");
    link_attachment_to_message(&conn, &key, &message.id, &attachment.sha256)
        .expect("link attachment");

    let todo = upsert_todo(
        &conn,
        &key,
        "todo_01HXYZ",
        "Buy milk",
        None,
        "open",
        Some(&message.id),
        None,
        None,
        None,
        None,
        None,
    )
    .expect("todo");

    let activity = append_todo_note(
        &conn,
        &key,
        &todo.id,
        "Remember the corner store",
        Some(&message.id),
    )
    .expect("todo activity");
    link_attachment_to_todo_activity(&conn, &key, &activity.id, &attachment.sha256)
        .expect("link activity attachment");

    let export_path = dir.path().join("migration.zip");
    let manifest = export_migration_archive(&conn, &key, &app_dir, &export_path).expect("export");

    assert!(export_path.exists());
    assert_eq!(manifest.archive_kind, "migration");
    assert!(zip_has_entry(&export_path, "export-manifest.json"));
    assert!(zip_has_entry(
        &export_path,
        &format!("items/{}.md", message.id)
    ));
    assert!(zip_has_entry(
        &export_path,
        &format!("items/{}.md", todo.id)
    ));
    assert!(zip_has_entry(
        &export_path,
        &format!("attachments/{}.png", attachment.sha256)
    ));
    assert!(zip_has_entry(&export_path, "attachments/index.json"));

    let manifest_text = read_zip_entry_text(&export_path, "export-manifest.json");
    let decoded = parse_migration_archive_manifest_json(&manifest_text).expect("parse manifest");
    assert!(decoded.items.iter().any(|item| item.id == message.id));
    assert!(decoded.items.iter().any(|item| item.id == todo.id));
    assert!(decoded.items.iter().any(|item| item.id == activity.id));
    assert_eq!(decoded.attachments.len(), 1);
    assert!(decoded.attachments[0].item_ids.contains(&message.id));
    assert!(decoded.attachments[0].item_ids.contains(&activity.id));
    assert!(decoded.relations.iter().any(|relation| {
        relation.from_id == todo.id
            && relation.to_id == message.id
            && relation.relation_type == "source_entry"
    }));

    let message_md = read_zip_entry_text(&export_path, &format!("items/{}.md", message.id));
    assert!(message_md.contains("---"));
    assert!(message_md.contains("Need to buy milk"));
    assert!(message_md.contains("tags: [\"errand\"]"));
    assert!(message_md.contains(&format!("../attachments/{}.png", attachment.sha256)));

    let todo_md = read_zip_entry_text(&export_path, &format!("items/{}.md", todo.id));
    assert!(todo_md.contains("# Buy milk"));
    assert!(todo_md.contains(&format!("[[{}|Need to buy milk]]", message.id)));
}

#[test]
fn migration_archive_export_rewrites_embedded_attachment_image_refs() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().join("app");
    let conn = open(&app_dir).expect("open db");
    let key = [6u8; 32];

    let conversation = create_conversation(&conn, &key, "Inbox").expect("conversation");
    let attachment =
        insert_attachment(&conn, &key, &app_dir, b"png-binary", "image/png").expect("attachment");
    let body = format!(
        "Inline image\n\n![saved](secondloop://attachment/{})",
        attachment.sha256
    );
    let message = insert_message(&conn, &key, &conversation.id, "user", &body).expect("message");
    link_attachment_to_message(&conn, &key, &message.id, &attachment.sha256)
        .expect("link attachment");

    let export_path = dir.path().join("migration.zip");
    export_migration_archive(&conn, &key, &app_dir, &export_path).expect("export");

    let message_md = read_zip_entry_text(&export_path, &format!("items/{}.md", message.id));
    assert!(message_md.contains(&format!(
        "![saved](../attachments/{}.png)",
        attachment.sha256
    )));
    assert!(!message_md.contains("secondloop://attachment/"));
}

#[test]
fn migration_archive_import_replaces_current_vault_with_archive_contents() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().join("app");
    let conn = open(&app_dir).expect("open db");
    let key = [9u8; 32];

    let conversation = create_conversation(&conn, &key, "Inbox").expect("conversation");
    let message =
        insert_message(&conn, &key, &conversation.id, "user", "Need to buy milk").expect("message");
    let tag = upsert_tag(&conn, &key, "errand").expect("tag");
    set_message_tags(&conn, &key, &message.id, std::slice::from_ref(&tag.id)).expect("set tags");
    let attachment =
        insert_attachment(&conn, &key, &app_dir, b"png-binary", "image/png").expect("attachment");
    link_attachment_to_message(&conn, &key, &message.id, &attachment.sha256)
        .expect("link attachment");
    let todo = upsert_todo(
        &conn,
        &key,
        "todo_01HXYZ",
        "Buy milk",
        None,
        "open",
        Some(&message.id),
        None,
        None,
        None,
        None,
        None,
    )
    .expect("todo");
    let activity = append_todo_note(
        &conn,
        &key,
        &todo.id,
        "Remember the corner store",
        Some(&message.id),
    )
    .expect("activity");
    link_attachment_to_todo_activity(&conn, &key, &activity.id, &attachment.sha256)
        .expect("link activity attachment");

    let export_path = dir.path().join("roundtrip.zip");
    export_migration_archive(&conn, &key, &app_dir, &export_path).expect("export");

    let stray_conversation = create_conversation(&conn, &key, "Stray").expect("stray convo");
    let _ = insert_message(&conn, &key, &stray_conversation.id, "user", "stray message")
        .expect("stray message");
    drop(conn);

    import_migration_archive(&app_dir, &key, &export_path).expect("import");

    let conn = open(&app_dir).expect("reopen db");
    let conversations = list_conversations(&conn, &key).expect("list conversations");
    assert!(conversations.iter().any(|item| item.id == conversation.id));
    assert!(!conversations
        .iter()
        .any(|item| item.id == stray_conversation.id));

    let messages = list_messages(&conn, &key, &conversation.id).expect("list messages");
    assert_eq!(messages.len(), 1);
    assert_eq!(messages[0].id, message.id);
    assert_eq!(messages[0].content, "Need to buy milk");

    let tags = list_message_tags(&conn, &key, &message.id).expect("message tags");
    assert_eq!(tags.len(), 1);
    assert_eq!(tags[0].name, "errand");

    let todo_after = get_todo(&conn, &key, &todo.id).expect("get todo");
    assert_eq!(
        todo_after.source_entry_id.as_deref(),
        Some(message.id.as_str())
    );

    let attachments = list_message_attachments(&conn, &key, &message.id).expect("attachments");
    assert_eq!(attachments.len(), 1);
    assert_eq!(attachments[0].sha256, attachment.sha256);

    let activities = list_todo_activities(&conn, &key, &todo.id).expect("activities");
    assert_eq!(activities.len(), 1);
    assert_eq!(activities[0].id, activity.id);
    assert_eq!(
        activities[0].content.as_deref(),
        Some("Remember the corner store")
    );

    let activity_attachments =
        list_todo_activity_attachments(&conn, &key, &activity.id).expect("activity attachments");
    assert_eq!(activity_attachments.len(), 1);
    assert_eq!(activity_attachments[0].sha256, attachment.sha256);
}

#[test]
fn migration_archive_import_rolls_back_when_archive_restore_fails() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().join("app");
    let conn = open(&app_dir).expect("open db");
    let key = [13u8; 32];

    let conversation = create_conversation(&conn, &key, "Keep").expect("conversation");
    let message =
        insert_message(&conn, &key, &conversation.id, "user", "keep me").expect("message");
    drop(conn);

    let bad_archive_path = dir.path().join("bad-import.zip");
    let file = fs::File::create(&bad_archive_path).expect("create bad zip");
    let mut writer = zip::ZipWriter::new(file);
    let options = zip::write::FileOptions::default();
    let manifest = MigrationArchiveManifest {
        schema_version: 1,
        archive_kind: "migration".to_string(),
        exported_at_ms: 1,
        app_version: "1.0.0".to_string(),
        items: vec![MigrationArchiveItem {
            id: conversation.id.clone(),
            entity_type: "conversation".to_string(),
            markdown_path: format!("items/{}.md", conversation.id),
            created_at_ms: 1,
            updated_at_ms: 1,
            title: "Broken Import".to_string(),
            tags: vec![],
            status: None,
            extra_json: None,
        }],
        attachments: vec![MigrationArchiveAttachment {
            sha256: "missing-sha".to_string(),
            archive_path: "attachments/missing-sha.png".to_string(),
            original_filename: "missing.png".to_string(),
            mime_type: Some("image/png".to_string()),
            size_bytes: 9,
            item_ids: vec![message.id.clone()],
        }],
        relations: vec![],
    };
    writer
        .start_file("export-manifest.json", options)
        .expect("manifest entry");
    use std::io::Write as _;
    writer
        .write_all(
            serde_json::to_string(&manifest)
                .expect("manifest json")
                .as_bytes(),
        )
        .expect("write manifest");
    writer
        .start_file(format!("items/{}.md", conversation.id), options)
        .expect("item entry");
    writer.write_all(b"# Broken Import\n").expect("write item");
    writer.finish().expect("finish bad zip");

    let err = import_migration_archive(&app_dir, &key, &bad_archive_path)
        .expect_err("import should fail and rollback");
    let err_text = err.to_string();
    assert!(
        err_text.contains("missing-sha")
            || err_text.contains("No such file")
            || err_text.contains("cannot find the file")
            || err_text.contains("系统找不到指定的文件")
            || err_text.contains("系统找不到指定的路径")
            || err_text.contains("os error 2"),
        "unexpected error: {err_text}"
    );

    let rollback_dir = app_dir.join("migration_archive/rollback");
    let rollback_entries = fs::read_dir(&rollback_dir)
        .map(|entries| entries.count())
        .unwrap_or(0);
    assert_eq!(rollback_entries, 0);

    let conn = open(&app_dir).expect("reopen db");
    let conversations = list_conversations(&conn, &key).expect("conversations after rollback");
    assert!(conversations.iter().any(|item| item.id == conversation.id));
    let messages = list_messages(&conn, &key, &conversation.id).expect("messages after rollback");
    assert_eq!(messages.len(), 1);
    assert_eq!(messages[0].id, message.id);
    assert_eq!(messages[0].content, "keep me");
}

#[test]
fn migration_archive_rollback_snapshot_is_encrypted_on_disk() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().join("app");
    let conn = open(&app_dir).expect("open db");
    let key = [41u8; 32];

    let conversation = create_conversation(&conn, &key, "Inbox").expect("conversation");
    let _message =
        insert_message(&conn, &key, &conversation.id, "user", "secret body").expect("message");

    let snapshot_path = app_dir
        .join("migration_archive/rollback")
        .join("snapshot.bin");
    fs::create_dir_all(snapshot_path.parent().expect("rollback dir")).expect("mkdir rollback");

    migration_archive_write_encrypted_snapshot(&conn, &key, &app_dir, &snapshot_path)
        .expect("write encrypted snapshot");

    let snapshot_bytes = fs::read(&snapshot_path).expect("read snapshot bytes");
    assert!(snapshot_bytes.len() > 4);
    assert_ne!(&snapshot_bytes[..2], b"PK");

    let source = migration_archive_materialize_encrypted_snapshot(&app_dir, &key, &snapshot_path)
        .expect("materialize encrypted snapshot");
    let manifest_json =
        fs::read_to_string(source.root_dir.join("export-manifest.json")).expect("read manifest");
    assert!(manifest_json.contains(&conversation.id));
    cleanup_materialized_external_import_source(&source);
}

#[test]
fn migration_archive_restore_from_materialized_source_cleans_up_written_attachments_on_error() {
    let dir = tempfile::tempdir().expect("tempdir");
    let source_root = dir.path().join("source-root");
    let app_dir = dir.path().join("app");
    let key = [29u8; 32];
    fs::create_dir_all(source_root.join("attachments")).expect("create attachments dir");

    let manifest = MigrationArchiveManifest {
        schema_version: MIGRATION_ARCHIVE_SCHEMA_VERSION,
        archive_kind: "migration".to_string(),
        exported_at_ms: 1_710_000_000_000,
        app_version: "1.0.0".to_string(),
        items: vec![],
        attachments: vec![MigrationArchiveAttachment {
            sha256: "deadbeef".to_string(),
            archive_path: "attachments/deadbeef.bin".to_string(),
            original_filename: "deadbeef.bin".to_string(),
            mime_type: Some("application/octet-stream".to_string()),
            size_bytes: 4,
            item_ids: vec!["missing-item".to_string()],
        }],
        relations: vec![],
    };
    fs::write(
        source_root.join("export-manifest.json"),
        serde_json::to_vec(&manifest).expect("serialize manifest"),
    )
    .expect("write manifest");
    fs::write(source_root.join("attachments/deadbeef.bin"), b"blob").expect("write blob");

    let err = migration_archive_restore_from_materialized_source_with_callbacks(
        &app_dir,
        &key,
        &source_root,
        &mut |_| {},
    )
    .expect_err("restore should fail when attachment owner is missing");

    assert!(err.to_string().contains("attachment owner item not found"));
    assert!(!app_dir.join("attachments/deadbeef.bin").exists());
}

#[test]
fn migration_archive_rebuild_derived_indexes_handles_more_than_256_batches() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().join("app");
    let conn = open(&app_dir).expect("open db");
    let key = [30u8; 32];

    let conversation = create_conversation(&conn, &key, "Bulk rebuild").expect("conversation");
    for index in 0..6554usize {
        insert_message(
            &conn,
            &key,
            &conversation.id,
            "user",
            &format!("bulk rebuild message {index}"),
        )
        .expect("insert message");
    }

    migration_archive_rebuild_derived_indexes(&conn, &key)
        .expect("rebuild should finish without hitting an artificial batch limit");

    let status = crate::knowledge::read_knowledge_index_status(&conn, &key).expect("status");
    assert_eq!(status.status, "complete");
    assert!(status.total_documents > 6553);
    assert_eq!(status.documents_indexed, status.total_documents);
}

#[test]
fn migration_archive_restore_from_encrypted_snapshot_cleans_up_on_materialize_failure() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().join("app");
    let key = [42u8; 32];
    let snapshot_path = app_dir
        .join("migration_archive/rollback")
        .join("corrupt-snapshot.bin");
    fs::create_dir_all(snapshot_path.parent().expect("rollback dir")).expect("mkdir rollback");
    fs::write(&snapshot_path, b"not a valid encrypted snapshot").expect("write corrupt snapshot");

    let err = migration_archive_restore_from_encrypted_snapshot(&app_dir, &key, &snapshot_path)
        .expect_err("corrupt snapshot should fail");

    assert!(!snapshot_path.exists());
    assert!(!err.to_string().is_empty());
}

#[test]
fn migration_archive_export_estimate_includes_estimated_size_bytes() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().join("app");
    let conn = open(&app_dir).expect("open db");
    let key = [21u8; 32];

    let conversation = create_conversation(&conn, &key, "Inbox").expect("conversation");
    let message =
        insert_message(&conn, &key, &conversation.id, "user", "hello world").expect("message");
    let attachment =
        insert_attachment(&conn, &key, &app_dir, b"0123456789", "image/png").expect("attachment");
    link_attachment_to_message(&conn, &key, &message.id, &attachment.sha256).expect("link");

    let estimate = migration_archive_export_estimate(&conn).expect("estimate");

    assert!(estimate.item_count >= 2);
    assert!(estimate.attachment_count >= 1);
    assert!(estimate.estimated_size_bytes >= attachment.byte_len);
}

#[test]
fn migration_archive_end_to_end_import_into_clean_app_rebuilds_indexes_and_persists_state() {
    let dir = tempfile::tempdir().expect("tempdir");
    let source_app_dir = dir.path().join("source-app");
    let target_app_dir = dir.path().join("target-app");
    let key = [31u8; 32];

    let source_conn = open(&source_app_dir).expect("open source db");
    let conversation = create_conversation(&source_conn, &key, "Inbox").expect("conversation");
    let message = insert_message(
        &source_conn,
        &key,
        &conversation.id,
        "user",
        "Need to buy milk",
    )
    .expect("message");
    let attachment = insert_attachment(
        &source_conn,
        &key,
        &source_app_dir,
        b"png-binary",
        "image/png",
    )
    .expect("attachment");
    link_attachment_to_message(&source_conn, &key, &message.id, &attachment.sha256)
        .expect("link attachment");
    let todo = upsert_todo(
        &source_conn,
        &key,
        "todo_end_to_end",
        "Buy milk",
        None,
        "open",
        Some(&message.id),
        Some(0),
        Some(1_700_000_000_000),
        Some(1_699_000_000_000),
        None,
        None,
    )
    .expect("todo");
    let _activity = append_todo_note(
        &source_conn,
        &key,
        &todo.id,
        "Remember the corner store",
        Some(&message.id),
    )
    .expect("activity");

    let export_path = dir.path().join("migration-e2e.zip");
    export_migration_archive(&source_conn, &key, &source_app_dir, &export_path).expect("export");
    drop(source_conn);

    import_migration_archive(&target_app_dir, &key, &export_path).expect("import into clean app");

    let target_conn = open(&target_app_dir).expect("open target db");
    let imported_conversations = list_conversations(&target_conn, &key).expect("conversations");
    let imported_messages = list_messages(&target_conn, &key, &conversation.id).expect("messages");
    let imported_attachments =
        list_message_attachments(&target_conn, &key, &message.id).expect("attachments");
    let knowledge_status = crate::knowledge::read_knowledge_index_status(&target_conn, &key)
        .expect("knowledge status");

    assert_eq!(imported_conversations.len(), 1);
    assert_eq!(imported_messages.len(), 1);
    assert_eq!(imported_attachments.len(), 1);
    assert_eq!(knowledge_status.status, "complete");
    assert!(knowledge_status.last_rebuild_completed_at_ms.is_some());

    let state_json = fs::read_to_string(target_app_dir.join("migration_archive/state/import.json"))
        .expect("read import state");
    let state: serde_json::Value = serde_json::from_str(&state_json).expect("parse import state");
    assert_eq!(state["stage"].as_str(), Some("reindex_completed"));
    assert_eq!(state["status"].as_str(), Some("completed"));
}

#[test]
fn migration_archive_rewrite_embedded_attachment_refs_skips_code_spans_and_fences() {
    let attachment = MigrationArchiveAttachment {
        sha256: "sha_123".to_string(),
        archive_path: "attachments/sha_123.png".to_string(),
        original_filename: "sha_123.png".to_string(),
        mime_type: Some("image/png".to_string()),
        size_bytes: 1,
        item_ids: vec!["item_1".to_string()],
    };
    let attachments = std::collections::BTreeMap::from([(attachment.sha256.clone(), attachment)]);

    let body = [
        "![saved](secondloop://attachment/sha_123)",
        "",
        "Use `![saved](secondloop://attachment/sha_123)` as an example.",
        "",
        "```markdown",
        "![saved](secondloop://attachment/sha_123)",
        "```",
    ]
    .join(
        "
",
    );

    let rewritten = migration_archive_rewrite_embedded_attachment_refs(&body, &attachments);

    assert!(rewritten.contains("![saved](../attachments/sha_123.png)"));
    assert!(rewritten.contains("Use `![saved](secondloop://attachment/sha_123)` as an example."));
    assert!(rewritten.contains(
        "```markdown
![saved](secondloop://attachment/sha_123)
```"
    ));
}
