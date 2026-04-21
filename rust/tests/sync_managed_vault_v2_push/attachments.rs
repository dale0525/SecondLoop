use super::*;

#[test]
fn managed_vault_v2_push_uploads_new_attachment_bytes_after_initial_backfill() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    let _attachment =
        db::insert_attachment(&conn, &key, &app_dir, b"fresh attachment", "image/png")
            .expect("insert attachment");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let scope_id = managed_vault_v2_scope_id(&base_url, &vault_id);
    conn.execute(
        "INSERT INTO kv(key, value) VALUES (?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        rusqlite::params![
            format!("managed_vault.attachments.bytes_backfilled:{scope_id}"),
            "1"
        ],
    )
    .expect("seed attachment backfill flag");
    conn.execute(
        "INSERT INTO kv(key, value) VALUES (?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        rusqlite::params![
            format!("managed_vault.embedding_artifacts.bytes_backfilled:{scope_id}"),
            "1"
        ],
    )
    .expect("seed artifact backfill flag");

    let pushed = sync::managed_vault::push(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
        .expect("push");
    assert!(pushed > 0);

    let requests = state.lock().expect("lock").requests.join("\n\n");
    assert!(requests.contains("/v2/vaults/v1/sync/push"));
    assert!(requests.contains("/v1/vaults/v1/attachments/"));

    let attachment_count = state.lock().expect("lock").attachments.len();
    assert_eq!(attachment_count, 1);

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_v2_push_does_not_upload_attachment_bytes_before_commit() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    {
        let mut server = state.lock().expect("lock");
        server.require_generation_for_push_without_id = true;
    }

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    let _attachment =
        db::insert_attachment(&conn, &key, &app_dir, b"fresh attachment", "image/png")
            .expect("insert attachment");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let scope_id = managed_vault_v2_scope_id(&base_url, &vault_id);
    conn.execute(
        "INSERT INTO kv(key, value) VALUES (?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        rusqlite::params![
            format!("managed_vault.attachments.bytes_backfilled:{scope_id}"),
            "1"
        ],
    )
    .expect("seed attachment backfill flag");
    conn.execute(
        "INSERT INTO kv(key, value) VALUES (?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        rusqlite::params![
            format!("managed_vault.embedding_artifacts.bytes_backfilled:{scope_id}"),
            "1"
        ],
    )
    .expect("seed artifact backfill flag");

    let error = sync::managed_vault::push(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
        .expect_err("push should fail before commit");
    assert!(
        error.to_string().contains("generation_required"),
        "unexpected error: {error:#}"
    );

    let state = state.lock().expect("lock");
    assert!(state.attachments.is_empty());
    let requests = state.requests.join("\n\n");
    assert!(requests.contains("/v2/vaults/v1/sync/push"));
    assert!(
        !requests.contains("/v1/vaults/v1/attachments/"),
        "unexpected pre-commit attachment upload: {requests}"
    );

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_v2_push_does_not_delete_remote_attachment_bytes_before_commit() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    {
        let mut server = state.lock().expect("lock");
        server.require_generation_for_push_without_id = true;
    }

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("create convo");
    let message =
        db::insert_message(&conn, &key, &conversation.id, "user", "hello").expect("insert msg");
    let attachment = db::insert_attachment(&conn, &key, &app_dir, b"fresh attachment", "image/png")
        .expect("insert attachment");
    db::link_attachment_to_message(&conn, &key, &message.id, &attachment.sha256).expect("link");
    let deleted = db::purge_message_attachments(&conn, &key, &app_dir, &message.id)
        .expect("purge message attachments");
    assert_eq!(deleted, 1);

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let scope_id = managed_vault_v2_scope_id(&base_url, &vault_id);
    conn.execute(
        "INSERT INTO kv(key, value) VALUES (?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        rusqlite::params![
            format!("managed_vault.attachments.bytes_backfilled:{scope_id}"),
            "1"
        ],
    )
    .expect("seed attachment backfill flag");
    conn.execute(
        "INSERT INTO kv(key, value) VALUES (?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        rusqlite::params![
            format!("managed_vault.embedding_artifacts.bytes_backfilled:{scope_id}"),
            "1"
        ],
    )
    .expect("seed artifact backfill flag");

    {
        let mut server = state.lock().expect("lock");
        server
            .attachments
            .insert(attachment.sha256.clone(), b"remote attachment".to_vec());
    }

    let error = sync::managed_vault::push(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
        .expect_err("push should fail before commit");
    assert!(
        error.to_string().contains("generation_required"),
        "unexpected error: {error:#}"
    );

    let state = state.lock().expect("lock");
    assert_eq!(
        state.attachments.get(&attachment.sha256),
        Some(&b"remote attachment".to_vec())
    );
    let requests = state.requests.join("\n\n");
    assert!(requests.contains("/v2/vaults/v1/sync/push"));
    assert!(
        !requests.contains("DELETE /v1/vaults/v1/attachments/"),
        "unexpected pre-commit attachment delete: {requests}"
    );

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_v2_push_retries_remote_attachment_delete_repairs() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("create convo");
    let message =
        db::insert_message(&conn, &key, &conversation.id, "user", "hello").expect("insert msg");
    let attachment = db::insert_attachment(&conn, &key, &app_dir, b"fresh attachment", "image/png")
        .expect("insert attachment");
    db::link_attachment_to_message(&conn, &key, &message.id, &attachment.sha256).expect("link");
    let deleted = db::purge_message_attachments(&conn, &key, &app_dir, &message.id)
        .expect("purge message attachments");
    assert_eq!(deleted, 1);

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let scope_id = managed_vault_v2_scope_id(&base_url, &vault_id);
    conn.execute(
        "INSERT INTO kv(key, value) VALUES (?1, '1'), (?2, '1')
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        rusqlite::params![
            format!("managed_vault.attachments.bytes_backfilled:{scope_id}"),
            format!("managed_vault.embedding_artifacts.bytes_backfilled:{scope_id}"),
        ],
    )
    .expect("seed backfill flags");

    {
        let mut server = state.lock().expect("lock");
        server
            .attachments
            .insert(attachment.sha256.clone(), b"remote attachment".to_vec());
        server
            .delete_attachment_failures
            .insert(attachment.sha256.clone(), 2);
    }

    let pushed = sync::managed_vault::push(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
        .expect("first push");
    assert!(pushed > 0);

    let diagnostics = sync::blob_repair::load_blob_repair_diagnostics(&conn, &scope_id)
        .expect("blob repair diagnostics after failed delete");
    assert_eq!(diagnostics.queued_count, 1);
    assert!(
        state
            .lock()
            .expect("lock")
            .attachments
            .contains_key(&attachment.sha256),
        "remote attachment should still exist after failed delete"
    );

    let pushed_again =
        sync::managed_vault::push(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
            .expect("second push should drain delete repair");
    assert_eq!(pushed_again, 0);

    let diagnostics_after_retry = sync::blob_repair::load_blob_repair_diagnostics(&conn, &scope_id)
        .expect("blob repair diagnostics after retry");
    assert_eq!(diagnostics_after_retry.queued_count, 0);
    assert!(
        !state
            .lock()
            .expect("lock")
            .attachments
            .contains_key(&attachment.sha256),
        "remote attachment should be deleted after repair retry"
    );

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_legacy_full_push_only_marks_backfill_complete_when_local_media_exists() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let attachment = db::insert_attachment(&conn, &key, &app_dir, b"fresh attachment", "image/png")
        .expect("insert attachment");
    fs::remove_file(app_dir.join(&attachment.path)).expect("remove local attachment bytes");

    db::record_embedding_artifact_manifest(
        &conn,
        db::EmbeddingArtifactManifestInput {
            source_kind: "message",
            source_id: "message-1",
            source_revision: 1,
            chunk_hash: "chunk-1",
            chunk_ordinal: 0,
            profile_id: "profile-1",
            producer_device_id: Some("device-a"),
            producer_class: "desktop",
            quality_tier: "full",
            vector_format: "f32",
            dimension: 384,
            blob_ref: "blob/missing-artifact",
            created_at_ms: Some(100),
        },
    )
    .expect("record missing artifact manifest");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pushed = sync::managed_vault::push(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
        .expect("push should succeed while queueing repairs");
    assert!(pushed > 0);

    let scope_id = managed_vault_v2_scope_id(&base_url, &vault_id);
    let attachment_backfill: Option<String> = conn
        .query_row(
            "SELECT value FROM kv WHERE key = ?1",
            rusqlite::params![format!(
                "managed_vault.attachments.bytes_backfilled:{scope_id}"
            )],
            |row| row.get(0),
        )
        .optional()
        .expect("load attachment backfill");
    assert_eq!(attachment_backfill, None);

    let artifact_backfill: Option<String> = conn
        .query_row(
            "SELECT value FROM kv WHERE key = ?1",
            rusqlite::params![format!(
                "managed_vault.embedding_artifacts.bytes_backfilled:{scope_id}"
            )],
            |row| row.get(0),
        )
        .optional()
        .expect("load artifact backfill");
    assert_eq!(artifact_backfill, None);

    let diagnostics = sync::blob_repair::load_blob_repair_diagnostics(&conn, &scope_id)
        .expect("blob repair diagnostics");
    assert_eq!(diagnostics.queued_count, 1);
    assert!(state.lock().expect("lock").attachments.is_empty());

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_v2_post_commit_missing_attachment_is_queued_for_repair_and_recovers() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let attachment =
        db::insert_attachment(&conn, &key, &app_dir, b"repairable attachment", "image/png")
            .expect("insert attachment");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let scope_id = managed_vault_v2_scope_id(&base_url, &vault_id);
    conn.execute(
        "INSERT INTO kv(key, value) VALUES (?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        rusqlite::params![
            format!("managed_vault.attachments.bytes_backfilled:{scope_id}"),
            "1"
        ],
    )
    .expect("seed attachment backfill flag");
    conn.execute(
        "INSERT INTO kv(key, value) VALUES (?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        rusqlite::params![
            format!("managed_vault.embedding_artifacts.bytes_backfilled:{scope_id}"),
            "1"
        ],
    )
    .expect("seed artifact backfill flag");

    fs::remove_file(app_dir.join(&attachment.path)).expect("remove local attachment before push");

    let pushed = sync::managed_vault::push(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
        .expect("push should succeed and queue repair");
    assert!(pushed > 0);

    let diagnostics = sync::blob_repair::load_blob_repair_diagnostics(&conn, &scope_id)
        .expect("blob repair diagnostics after queued repair");
    assert_eq!(diagnostics.queued_count, 1);

    let requests_after_first_push = state.lock().expect("lock").requests.join("\n\n");
    assert!(
        requests_after_first_push.contains("/v2/vaults/v1/sync/push")
            || requests_after_first_push.contains("/v1/vaults/v1/ops:push"),
        "expected a sync push request, got {requests_after_first_push}"
    );
    assert!(
        !requests_after_first_push.contains("/v1/vaults/v1/attachments/"),
        "unexpected attachment upload before repairable local file exists: {requests_after_first_push}"
    );
    drop(requests_after_first_push);

    let attachment_backfill_after_first_push: Option<String> = conn
        .query_row(
            "SELECT value FROM kv WHERE key = ?1",
            rusqlite::params![format!(
                "managed_vault.attachments.bytes_backfilled:{scope_id}"
            )],
            |row| row.get(0),
        )
        .optional()
        .expect("load attachment backfill after queued repair");
    assert_eq!(attachment_backfill_after_first_push, Some("1".to_string()));

    let restored_attachment =
        db::insert_attachment(&conn, &key, &app_dir, b"repairable attachment", "image/png")
            .expect("restore attachment bytes");
    assert_eq!(restored_attachment.sha256, attachment.sha256);

    let second_push =
        sync::managed_vault::push(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
            .expect("second push should drain repair queue");
    assert_eq!(second_push, 0);

    let diagnostics_after_repair =
        sync::blob_repair::load_blob_repair_diagnostics(&conn, &scope_id)
            .expect("blob repair diagnostics after draining repair");
    assert_eq!(diagnostics_after_repair.queued_count, 0);

    let state = state.lock().expect("lock");
    assert!(state.attachments.contains_key(&attachment.sha256));
    let requests = state.requests.join("\n\n");
    assert!(requests.contains("/v1/vaults/v1/attachments/"));

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_v2_deleted_attachment_repair_does_not_jam_future_pushes() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    let conversation = db::create_conversation(&conn, &key, "Inbox").expect("create convo");
    let message =
        db::insert_message(&conn, &key, &conversation.id, "user", "hello").expect("insert msg");
    let attachment = db::insert_attachment(&conn, &key, &app_dir, b"upload failure", "image/png")
        .expect("insert attachment");
    db::link_attachment_to_message(&conn, &key, &message.id, &attachment.sha256).expect("link");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let scope_id = managed_vault_v2_scope_id(&base_url, &vault_id);
    conn.execute(
        "INSERT INTO kv(key, value) VALUES (?1, '1'), (?2, '1')
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        rusqlite::params![
            format!("managed_vault.attachments.bytes_backfilled:{scope_id}"),
            format!("managed_vault.embedding_artifacts.bytes_backfilled:{scope_id}"),
        ],
    )
    .expect("seed backfill flags");

    sync::blob_repair::enqueue_blob_repair(
        &conn,
        &scope_id,
        sync::blob_repair::BlobRepairKind::UploadAttachment {
            sha256: attachment.sha256.clone(),
        },
    )
    .expect("seed upload repair");

    let diagnostics = sync::blob_repair::load_blob_repair_diagnostics(&conn, &scope_id)
        .expect("load diagnostics after queued repair");
    assert_eq!(diagnostics.queued_count, 1);

    let deleted = db::purge_message_attachments(&conn, &key, &app_dir, &message.id)
        .expect("purge attachment before repair retry");
    assert_eq!(deleted, 1);

    let second_push =
        sync::managed_vault::push(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
            .expect("deleted attachment repair should be treated as done");
    assert!(second_push > 0);

    let diagnostics_after_retry = sync::blob_repair::load_blob_repair_diagnostics(&conn, &scope_id)
        .expect("load diagnostics after deleted attachment retry");
    assert_eq!(diagnostics_after_retry.queued_count, 0);
    assert_eq!(diagnostics_after_retry.last_error, None);

    let requests = state.lock().expect("lock").requests.join("\n\n");
    assert!(requests.contains("/v2/vaults/v1/sync/push"));
    assert!(
        !requests.contains("PUT /v1/vaults/v1/attachments/"),
        "deleted attachment repair should not attempt a remote upload: {requests}"
    );

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_v2_post_commit_attachment_upload_failure_queues_repair_without_failing_push() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let attachment = db::insert_attachment(&conn, &key, &app_dir, b"upload failure", "image/png")
        .expect("insert attachment");

    state
        .lock()
        .expect("lock")
        .put_attachment_failures
        .insert(attachment.sha256.clone(), 2);

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let scope_id = managed_vault_v2_scope_id(&base_url, &vault_id);
    conn.execute(
        "INSERT INTO kv(key, value) VALUES (?1, '1'), (?2, '1')
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        rusqlite::params![
            format!("managed_vault.attachments.bytes_backfilled:{scope_id}"),
            format!("managed_vault.embedding_artifacts.bytes_backfilled:{scope_id}"),
        ],
    )
    .expect("seed backfill flags");

    let pushed = sync::managed_vault::push(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
        .expect("push should succeed while queueing post-commit repair");
    assert!(pushed > 0);

    let diagnostics = sync::blob_repair::load_blob_repair_diagnostics(&conn, &scope_id)
        .expect("blob repair diagnostics after failed post-commit upload");
    assert_eq!(diagnostics.queued_count, 1);

    let last_pushed_seq: Option<i64> = conn
        .query_row(
            "SELECT value FROM kv WHERE key LIKE 'managed_vault_v2.last_pushed_seq:%' LIMIT 1",
            [],
            |row| row.get::<_, String>(0),
        )
        .optional()
        .expect("load last pushed seq")
        .and_then(|raw| raw.parse::<i64>().ok());
    assert!(last_pushed_seq.unwrap_or(0) > 0);

    assert!(
        !state
            .lock()
            .expect("lock")
            .attachments
            .contains_key(&attachment.sha256),
        "attachment upload should have failed on first post-commit attempt"
    );

    let second_push =
        sync::managed_vault::push(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
            .expect("second push should drain queued repair");
    assert_eq!(second_push, 0);

    let diagnostics_after_retry = sync::blob_repair::load_blob_repair_diagnostics(&conn, &scope_id)
        .expect("blob repair diagnostics after retry");
    assert_eq!(diagnostics_after_retry.queued_count, 0);
    assert!(state
        .lock()
        .expect("lock")
        .attachments
        .contains_key(&attachment.sha256));

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}
