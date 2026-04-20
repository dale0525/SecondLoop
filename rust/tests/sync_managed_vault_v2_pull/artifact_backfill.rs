use super::*;

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
