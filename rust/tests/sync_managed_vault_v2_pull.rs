use base64::Engine as _;
use rusqlite::OptionalExtension;
use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;
use secondloop_rust::sync::blob_repair::{self, BlobRepairKind};

#[path = "support/managed_vault_v2_test_server.rs"]
mod managed_vault_v2_test_server;

use managed_vault_v2_test_server::{managed_vault_v2_scope_id, start_mock_v2_server};

#[test]
fn managed_vault_v2_empty_remote_pull_does_not_persist_generation_state() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    {
        let mut server = state.lock().expect("lock");
        server.generation_id.clear();
        server.latest_global_seq = 0;
        server.ops.clear();
    }

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pulled = sync::managed_vault::pull(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
        .expect("pull");
    assert_eq!(pulled, 0);

    let generation_key = format!(
        "managed_vault_v2.generation_id:{}",
        managed_vault_v2_scope_id(&base_url, &vault_id)
    );
    let generation: Option<String> = conn
        .query_row(
            "SELECT value FROM kv WHERE key = ?1",
            rusqlite::params![generation_key],
            |row| row.get(0),
        )
        .optional()
        .expect("load generation");
    assert_eq!(generation, None);

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_v2_generation_rebuild_clears_stale_blob_repair_and_backfill_state() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    {
        let mut server = state.lock().expect("lock");
        server.generation_id = "generation-new".to_string();
        server.latest_global_seq = 0;
        server.ops.clear();
    }

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

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
            format!("managed_vault_v2.generation_id:{scope_id}"),
            "generation-old"
        ],
    )
    .expect("seed old generation");
    conn.execute(
        "INSERT INTO kv(key, value) VALUES (?1, '1'), (?2, '1')
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        rusqlite::params![
            format!("managed_vault.attachments.bytes_backfilled:{scope_id}"),
            format!("managed_vault.embedding_artifacts.bytes_backfilled:{scope_id}"),
        ],
    )
    .expect("seed backfill flags");
    blob_repair::enqueue_blob_repair(
        &conn,
        &scope_id,
        BlobRepairKind::UploadAttachment {
            sha256: "stale-attachment".to_string(),
        },
    )
    .expect("enqueue stale repair");
    blob_repair::record_blob_repair_error(&conn, &scope_id, "stale repair error")
        .expect("record stale repair error");

    let pulled = sync::managed_vault::pull(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
        .expect("pull should rebuild local state");
    assert_eq!(pulled, 0);

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

    let diagnostics = blob_repair::load_blob_repair_diagnostics(&conn, &scope_id)
        .expect("load blob repair diagnostics");
    assert_eq!(diagnostics.queued_count, 0);
    assert_eq!(diagnostics.last_error, None);

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_v2_pull_rebuilds_after_non_contiguous_page() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");
    let conv_a = db::create_conversation(&conn_a, &key_a, "Inbox").expect("create convo A");
    db::insert_message(&conn_a, &key_a, &conv_a.id, "user", "hello").expect("insert msg A");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pushed =
        sync::managed_vault::push(&conn_a, &key_a, &sync_key, &base_url, &vault_id, &id_token)
            .expect("push");
    assert!(pushed > 0);
    let expected_last_applied = state.lock().expect("lock").latest_global_seq;

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let scope_id = managed_vault_v2_scope_id(&base_url, &vault_id);
    conn_b
        .execute(
            "INSERT INTO kv(key, value) VALUES (?1, ?2)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            rusqlite::params![
                format!("managed_vault_v2.generation_id:{scope_id}"),
                "generation-a"
            ],
        )
        .expect("seed generation");

    {
        let mut server = state.lock().expect("lock");
        server.gap_pull_once_after_global_seq = Some(0);
    }

    let pulled =
        sync::managed_vault::pull(&conn_b, &key_b, &sync_key, &base_url, &vault_id, &id_token)
            .expect("pull");
    assert!(pulled > 0);

    let convs_b = db::list_conversations(&conn_b, &key_b).expect("list convs B");
    assert_eq!(convs_b.len(), 1);
    let msgs_b = db::list_messages(&conn_b, &key_b, &convs_b[0].id).expect("list msgs B");
    assert_eq!(msgs_b.len(), 1);
    assert_eq!(msgs_b[0].content, "hello");
    let last_applied: Option<String> = conn_b
        .query_row(
            "SELECT value FROM kv WHERE key = ?1",
            rusqlite::params![format!(
                "managed_vault_v2.last_applied_global_seq:{}",
                managed_vault_v2_scope_id(&base_url, &vault_id)
            )],
            |row| row.get(0),
        )
        .optional()
        .expect("load last_applied");
    let expected_last_applied_text = expected_last_applied.to_string();
    assert_eq!(
        last_applied.as_deref(),
        Some(expected_last_applied_text.as_str()),
    );

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_v2_pull_clears_artifact_backfill_flag_when_local_blob_is_missing() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");
    let conversation =
        db::get_or_create_loop_home_conversation(&conn_a, &key_a).expect("conversation A");
    let message = db::insert_message(&conn_a, &key_a, &conversation.id, "user", "artifact note")
        .expect("insert msg A");
    let processed =
        db::process_pending_message_embeddings_default(&conn_a, &key_a, 10).expect("process A");
    assert_eq!(processed, 1);

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let device_id = db::get_or_create_device_id(&conn_a).expect("device id");
    let mut stmt = conn_a
        .prepare(
            r#"SELECT op_id, seq, op_json
               FROM oplog
               WHERE device_id = ?1
               ORDER BY seq ASC"#,
        )
        .expect("prepare oplog");
    let mut rows = stmt
        .query(rusqlite::params![device_id.as_str()])
        .expect("query oplog");

    let mut remote_ops = Vec::<serde_json::Value>::new();
    while let Some(row) = rows.next().expect("next row") {
        let op_id: String = row.get(0).expect("op_id");
        let seq: i64 = row.get(1).expect("seq");
        let op_json_blob: Vec<u8> = row.get(2).expect("op_json");
        let plaintext = secondloop_rust::crypto::decrypt_bytes(
            &key_a,
            &op_json_blob,
            format!("oplog.op_json:{op_id}").as_bytes(),
        )
        .expect("decrypt op");
        let ciphertext = secondloop_rust::crypto::encrypt_bytes(
            &sync_key,
            &plaintext,
            format!("sync.ops:{device_id}:{seq}").as_bytes(),
        )
        .expect("encrypt op");
        remote_ops.push(serde_json::json!({
            "global_seq": (remote_ops.len() as i64) + 1,
            "device_id": device_id,
            "seq": seq,
            "op_id": op_id,
            "client_op_id": op_id,
            "ciphertext_b64": base64::engine::general_purpose::STANDARD.encode(ciphertext),
        }));
    }

    let profile_id = db::embedding_artifact_profile_id(
        secondloop_rust::embedding::DEFAULT_MODEL_NAME,
        secondloop_rust::embedding::DEFAULT_EMBED_DIM,
    );
    let revision = conn_a
        .query_row(
            r#"SELECT updated_at FROM messages WHERE id = ?1"#,
            rusqlite::params![message.id.as_str()],
            |row| row.get::<_, i64>(0),
        )
        .expect("message revision");
    let manifests = db::list_active_embedding_artifacts_for_source_revision(
        &conn_a,
        "message",
        &message.id,
        revision,
        &profile_id,
    )
    .expect("manifests");
    assert_eq!(manifests.len(), 1);
    let manifest = manifests[0].clone();
    let artifact_plaintext =
        db::read_embedding_artifact_blob(&app_dir_a, &key_a, &manifest.blob_ref)
            .expect("read artifact blob");
    let artifact_ciphertext = secondloop_rust::crypto::encrypt_bytes(
        &sync_key,
        &artifact_plaintext,
        format!("sync.embedding_artifact.blob:{}", manifest.blob_ref).as_bytes(),
    )
    .expect("encrypt artifact");

    {
        let mut server = state.lock().expect("lock");
        server.latest_global_seq = remote_ops.len() as i64;
        server.ops = remote_ops;
        server.attachments.insert(
            db::embedding_artifact_blob_storage_id(&manifest.blob_ref),
            artifact_ciphertext,
        );
    }

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let pulled =
        sync::managed_vault::pull(&conn_b, &key_b, &sync_key, &base_url, &vault_id, &id_token)
            .expect("initial pull");
    assert!(pulled > 0);

    let scope_id = managed_vault_v2_scope_id(&base_url, &vault_id);
    let artifact_backfill_key =
        format!("managed_vault.embedding_artifacts.bytes_backfilled:{scope_id}");
    let initial_backfill: Option<String> = conn_b
        .query_row(
            "SELECT value FROM kv WHERE key = ?1",
            rusqlite::params![artifact_backfill_key.as_str()],
            |row| row.get(0),
        )
        .optional()
        .expect("load initial artifact backfill");
    assert_eq!(initial_backfill.as_deref(), Some("1"));

    let blob_refs = db::list_distinct_embedding_artifact_blob_refs(&conn_b).expect("blob refs B");
    assert_eq!(blob_refs.len(), 1);
    std::fs::remove_file(app_dir_b.join(db::embedding_artifact_blob_rel_path(&blob_refs[0])))
        .expect("remove local artifact blob");
    {
        let mut server = state.lock().expect("lock");
        server
            .attachments
            .remove(&db::embedding_artifact_blob_storage_id(&blob_refs[0]));
    }

    let pulled_again =
        sync::managed_vault::pull(&conn_b, &key_b, &sync_key, &base_url, &vault_id, &id_token)
            .expect("second pull");
    assert_eq!(pulled_again, 0);

    let backfill_after_missing: Option<String> = conn_b
        .query_row(
            "SELECT value FROM kv WHERE key = ?1",
            rusqlite::params![artifact_backfill_key.as_str()],
            |row| row.get(0),
        )
        .optional()
        .expect("load artifact backfill after missing blob");
    assert_eq!(backfill_after_missing, None);

    let diagnostics = blob_repair::load_blob_repair_diagnostics(&conn_b, &scope_id)
        .expect("load blob repair diagnostics");
    assert_eq!(diagnostics.queued_count, 1);

    let requests = state.lock().expect("lock").requests.join("\n\n");
    assert!(requests.contains("/v2/vaults/v1/sync/pull"));

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_v2_pull_generation_switch_resets_applied_count() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");
    let conv_a = db::create_conversation(&conn_a, &key_a, "Inbox").expect("create convo A");
    db::insert_message(&conn_a, &key_a, &conv_a.id, "user", "old generation")
        .expect("insert msg A");
    let pushed_old =
        sync::managed_vault::push(&conn_a, &key_a, &sync_key, &base_url, &vault_id, &id_token)
            .expect("push old generation");
    assert!(pushed_old > 0);

    let (old_generation_id, old_latest_global_seq, old_ops) = {
        let server = state.lock().expect("lock");
        (
            server.generation_id.clone(),
            server.latest_global_seq,
            server.ops.clone(),
        )
    };
    assert!(old_latest_global_seq > 0);

    {
        let mut server = state.lock().expect("lock");
        server.generation_id = "generation-b".to_string();
        server.latest_global_seq = 0;
        server.ops.clear();
    }

    let temp_c = tempfile::tempdir().expect("tempdir C");
    let app_dir_c = temp_c.path().join("secondloop_c");
    let key_c =
        auth::init_master_password(&app_dir_c, "pw-c", KdfParams::for_test()).expect("init C");
    let conn_c = db::open(&app_dir_c).expect("open C db");
    let conv_c = db::create_conversation(&conn_c, &key_c, "Inbox").expect("create convo C");
    db::insert_message(&conn_c, &key_c, &conv_c.id, "user", "new generation")
        .expect("insert msg C");
    let pushed_new =
        sync::managed_vault::push(&conn_c, &key_c, &sync_key, &base_url, &vault_id, &id_token)
            .expect("push new generation");
    assert!(pushed_new > 0);

    let (new_generation_id, new_latest_global_seq, new_ops) = {
        let server = state.lock().expect("lock");
        (
            server.generation_id.clone(),
            server.latest_global_seq,
            server.ops.clone(),
        )
    };
    assert_ne!(new_generation_id, old_generation_id);
    assert!(new_latest_global_seq > 0);

    {
        let mut server = state.lock().expect("lock");
        server.generation_id = old_generation_id;
        server.latest_global_seq = old_latest_global_seq;
        server.ops = old_ops;
        server.pull_page_size = Some(1);
        server.switch_generation_once_after_global_seq = Some(1);
        server.switch_generation_id = Some(new_generation_id);
        server.switch_generation_latest_global_seq = Some(new_latest_global_seq);
        server.switch_generation_ops = new_ops;
    }

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let pulled =
        sync::managed_vault::pull(&conn_b, &key_b, &sync_key, &base_url, &vault_id, &id_token)
            .expect("pull after generation switch");
    assert_eq!(pulled, new_latest_global_seq as u64);

    let convs_b = db::list_conversations(&conn_b, &key_b).expect("list convs B");
    assert_eq!(convs_b.len(), 1);
    let msgs_b = db::list_messages(&conn_b, &key_b, &convs_b[0].id).expect("list msgs B");
    assert_eq!(msgs_b.len(), 1);
    assert_eq!(msgs_b[0].content, "new generation");

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_v2_pull_rebuilds_after_reset_required_response() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");
    let conv_a = db::create_conversation(&conn_a, &key_a, "Inbox").expect("create convo A");
    db::insert_message(&conn_a, &key_a, &conv_a.id, "user", "hello").expect("insert msg A");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pushed =
        sync::managed_vault::push(&conn_a, &key_a, &sync_key, &base_url, &vault_id, &id_token)
            .expect("push");
    assert!(pushed > 0);
    let expected_last_applied = state.lock().expect("lock").latest_global_seq;

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let scope_id = managed_vault_v2_scope_id(&base_url, &vault_id);
    conn_b
        .execute(
            "INSERT INTO kv(key, value) VALUES (?1, ?2)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            rusqlite::params![
                format!("managed_vault_v2.generation_id:{scope_id}"),
                "generation-a"
            ],
        )
        .expect("seed generation");

    {
        let mut server = state.lock().expect("lock");
        server.reset_required_once_after_global_seq = Some(0);
    }

    let pulled =
        sync::managed_vault::pull(&conn_b, &key_b, &sync_key, &base_url, &vault_id, &id_token)
            .expect("pull");
    assert!(pulled > 0);

    let convs_b = db::list_conversations(&conn_b, &key_b).expect("list convs B");
    assert_eq!(convs_b.len(), 1);
    let msgs_b = db::list_messages(&conn_b, &key_b, &convs_b[0].id).expect("list msgs B");
    assert_eq!(msgs_b.len(), 1);
    assert_eq!(msgs_b[0].content, "hello");
    let last_applied: Option<String> = conn_b
        .query_row(
            "SELECT value FROM kv WHERE key = ?1",
            rusqlite::params![format!(
                "managed_vault_v2.last_applied_global_seq:{}",
                managed_vault_v2_scope_id(&base_url, &vault_id)
            )],
            |row| row.get(0),
        )
        .optional()
        .expect("load last_applied");
    let expected_last_applied_text = expected_last_applied.to_string();
    assert_eq!(
        last_applied.as_deref(),
        Some(expected_last_applied_text.as_str()),
    );

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_v2_pull_with_progress_resets_baseline_after_reset_required_response() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");
    let conv_a = db::create_conversation(&conn_a, &key_a, "Inbox").expect("create convo A");
    db::insert_message(&conn_a, &key_a, &conv_a.id, "user", "hello").expect("insert msg A");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pushed =
        sync::managed_vault::push(&conn_a, &key_a, &sync_key, &base_url, &vault_id, &id_token)
            .expect("push");
    assert!(pushed > 0);
    let expected_last_applied = state.lock().expect("lock").latest_global_seq;
    assert_eq!(expected_last_applied, 2);

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let scope_id = managed_vault_v2_scope_id(&base_url, &vault_id);
    conn_b
        .execute(
            "INSERT INTO kv(key, value) VALUES (?1, ?2)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            rusqlite::params![
                format!("managed_vault_v2.generation_id:{scope_id}"),
                "generation-a"
            ],
        )
        .expect("seed generation");
    conn_b
        .execute(
            "INSERT INTO kv(key, value) VALUES (?1, ?2)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            rusqlite::params![
                format!("managed_vault_v2.last_applied_global_seq:{scope_id}"),
                "1"
            ],
        )
        .expect("seed stale last_applied");

    {
        let mut server = state.lock().expect("lock");
        server.reset_required_once_after_global_seq = Some(1);
    }

    let mut seen_progress = Vec::new();
    let pulled = sync::managed_vault::pull_with_progress(
        &conn_b,
        &key_b,
        &sync_key,
        &base_url,
        &vault_id,
        &id_token,
        &mut |done, total| seen_progress.push((done, total)),
    )
    .expect("pull with progress");
    assert!(pulled > 0);

    assert!(
        seen_progress.contains(&(0, expected_last_applied as u64)),
        "expected progress to reset after rebuild, got {seen_progress:?}"
    );
    assert_eq!(
        seen_progress.last().copied(),
        Some((expected_last_applied as u64, expected_last_applied as u64)),
        "expected rebuilt pull to report full recovered total, got {seen_progress:?}"
    );

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_v2_pull_blocks_destructive_rebuild_when_local_media_backfill_is_pending() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    {
        let mut server = state.lock().expect("lock");
        server.generation_id = "generation-new".to_string();
        server.latest_global_seq = 0;
        server.ops.clear();
    }

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    let attachment = db::insert_attachment(&conn, &key, &app_dir, b"local-only", "image/png")
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
            format!("managed_vault_v2.generation_id:{scope_id}"),
            "generation-old"
        ],
    )
    .expect("seed old generation");

    let error = sync::managed_vault::pull(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
        .expect_err("pull should refuse destructive rebuild while media backfill is pending");
    assert!(
        error.to_string().contains("local_media_backfill_pending"),
        "unexpected error: {error:#}"
    );

    let attachment_bytes =
        db::read_attachment_bytes(&conn, &key, &app_dir, &attachment.sha256).expect("attachment");
    assert_eq!(attachment_bytes, b"local-only");

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_v2_pull_blocks_destructive_rebuild_when_local_upload_repair_is_pending() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    {
        let mut server = state.lock().expect("lock");
        server.generation_id = "generation-new".to_string();
        server.latest_global_seq = 0;
        server.ops.clear();
    }

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    let attachment = db::insert_attachment(&conn, &key, &app_dir, b"local-only", "image/png")
        .expect("insert attachment");
    let device_id = db::get_or_create_device_id(&conn).expect("device id");
    let last_local_seq: i64 = conn
        .query_row(
            "SELECT MAX(seq) FROM oplog WHERE device_id = ?1",
            rusqlite::params![device_id.as_str()],
            |row| row.get(0),
        )
        .expect("load max local seq");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let scope_id = managed_vault_v2_scope_id(&base_url, &vault_id);
    conn.execute(
        "INSERT INTO kv(key, value) VALUES (?1, ?2), (?3, '1')
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        rusqlite::params![
            format!("managed_vault_v2.generation_id:{scope_id}"),
            "generation-old",
            format!("managed_vault.attachments.bytes_backfilled:{scope_id}"),
        ],
    )
    .expect("seed generation and attachment backfill");
    conn.execute(
        "INSERT INTO kv(key, value) VALUES (?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        rusqlite::params![
            format!("managed_vault_v2.last_pushed_seq:{scope_id}:{device_id}"),
            last_local_seq.to_string(),
        ],
    )
    .expect("seed last pushed local seq");
    blob_repair::enqueue_blob_repair(
        &conn,
        &scope_id,
        BlobRepairKind::UploadAttachment {
            sha256: attachment.sha256.clone(),
        },
    )
    .expect("enqueue upload repair");

    let error = sync::managed_vault::pull(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
        .expect_err("pull should refuse destructive rebuild while upload repair is pending");
    assert!(
        error.to_string().contains("local_media_backfill_pending"),
        "unexpected error: {error:#}"
    );

    let attachment_bytes =
        db::read_attachment_bytes(&conn, &key, &app_dir, &attachment.sha256).expect("attachment");
    assert_eq!(attachment_bytes, b"local-only");

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_v2_pull_downloads_missing_embedding_artifact_blobs() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");
    let conversation =
        db::get_or_create_loop_home_conversation(&conn_a, &key_a).expect("conversation A");
    let message = db::insert_message(
        &conn_a,
        &key_a,
        &conversation.id,
        "user",
        "shared semantic note",
    )
    .expect("insert message");
    let processed =
        db::process_pending_message_embeddings_default(&conn_a, &key_a, 10).expect("process A");
    assert_eq!(processed, 1);

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let device_id = db::get_or_create_device_id(&conn_a).expect("device id");
    let mut stmt = conn_a
        .prepare(
            r#"SELECT op_id, seq, op_json
               FROM oplog
               WHERE device_id = ?1
               ORDER BY seq ASC"#,
        )
        .expect("prepare oplog");
    let mut rows = stmt
        .query(rusqlite::params![device_id.as_str()])
        .expect("query oplog");

    let mut remote_ops = Vec::<serde_json::Value>::new();
    while let Some(row) = rows.next().expect("next row") {
        let op_id: String = row.get(0).expect("op_id");
        let seq: i64 = row.get(1).expect("seq");
        let op_json_blob: Vec<u8> = row.get(2).expect("op_json");
        let plaintext = secondloop_rust::crypto::decrypt_bytes(
            &key_a,
            &op_json_blob,
            format!("oplog.op_json:{op_id}").as_bytes(),
        )
        .expect("decrypt op");
        let ciphertext = secondloop_rust::crypto::encrypt_bytes(
            &sync_key,
            &plaintext,
            format!("sync.ops:{device_id}:{seq}").as_bytes(),
        )
        .expect("encrypt op");
        remote_ops.push(serde_json::json!({
            "global_seq": (remote_ops.len() as i64) + 1,
            "device_id": device_id,
            "seq": seq,
            "op_id": op_id,
            "client_op_id": op_id,
            "ciphertext_b64": base64::engine::general_purpose::STANDARD.encode(ciphertext),
        }));
    }

    let profile_id = db::embedding_artifact_profile_id(
        secondloop_rust::embedding::DEFAULT_MODEL_NAME,
        secondloop_rust::embedding::DEFAULT_EMBED_DIM,
    );
    let revision = conn_a
        .query_row(
            r#"SELECT updated_at FROM messages WHERE id = ?1"#,
            rusqlite::params![message.id.as_str()],
            |row| row.get::<_, i64>(0),
        )
        .expect("message revision");
    let manifests = db::list_active_embedding_artifacts_for_source_revision(
        &conn_a,
        "message",
        &message.id,
        revision,
        &profile_id,
    )
    .expect("manifests");
    assert_eq!(manifests.len(), 1);
    let manifest = manifests[0].clone();
    let artifact_plaintext =
        db::read_embedding_artifact_blob(&app_dir_a, &key_a, &manifest.blob_ref)
            .expect("read artifact blob");
    let artifact_ciphertext = secondloop_rust::crypto::encrypt_bytes(
        &sync_key,
        &artifact_plaintext,
        format!("sync.embedding_artifact.blob:{}", manifest.blob_ref).as_bytes(),
    )
    .expect("encrypt artifact");

    {
        let mut server = state.lock().expect("lock");
        server.latest_global_seq = remote_ops.len() as i64;
        server.ops = remote_ops;
        server.attachments.insert(
            db::embedding_artifact_blob_storage_id(&manifest.blob_ref),
            artifact_ciphertext,
        );
    }

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let applied =
        sync::managed_vault::pull(&conn_b, &key_b, &sync_key, &base_url, &vault_id, &id_token)
            .expect("pull");
    assert!(applied > 0);

    let manifests_b = db::list_active_embedding_artifacts_for_source_revision(
        &conn_b,
        "message",
        &message.id,
        revision,
        &profile_id,
    )
    .expect("manifests B");
    assert_eq!(manifests_b.len(), 1);
    assert!(db::has_embedding_artifact_blob(
        &app_dir_b,
        &manifests_b[0].blob_ref
    ));

    let scope_id = managed_vault_v2_scope_id(&base_url, &vault_id);
    let artifact_backfill_key =
        format!("managed_vault.embedding_artifacts.bytes_backfilled:{scope_id}");
    let artifact_backfill: Option<String> = conn_b
        .query_row(
            "SELECT value FROM kv WHERE key = ?1",
            rusqlite::params![artifact_backfill_key],
            |row| row.get(0),
        )
        .optional()
        .expect("load artifact backfill flag");
    assert_eq!(artifact_backfill.as_deref(), Some("1"));

    {
        let mut server = state.lock().expect("lock");
        server.generation_id = "generation-b".to_string();
        server.latest_global_seq = 0;
        server.ops.clear();
    }

    let recovered =
        sync::managed_vault::pull(&conn_b, &key_b, &sync_key, &base_url, &vault_id, &id_token)
            .expect("pull after generation switch");
    assert_eq!(recovered, 0);

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}
