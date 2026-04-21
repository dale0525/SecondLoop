use super::*;

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
fn managed_vault_v2_pull_blocks_destructive_rebuild_when_cloud_media_backup_is_pending() {
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

    db::enqueue_cloud_media_backup(&conn, &attachment.sha256, "original", 1234, Some(&scope_id))
        .expect("enqueue cloud media backup");
    conn.execute(
        "INSERT INTO kv(key, value) VALUES (?1, ?2), (?3, ?4)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        rusqlite::params![
            format!("managed_vault_v2.generation_id:{scope_id}"),
            "generation-old",
            format!("managed_vault_v2.last_pushed_seq:{scope_id}:{device_id}"),
            last_local_seq.to_string(),
        ],
    )
    .expect("seed old generation and pushed seq");

    let error = sync::managed_vault::pull(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
        .expect_err("pull should refuse destructive rebuild while cloud media backup is pending");
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
fn managed_vault_v2_pull_ignores_cloud_media_backup_pending_from_other_scope() {
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
    db::enqueue_cloud_media_backup(
        &conn,
        &attachment.sha256,
        "original",
        1234,
        Some("managed-vault-legacy-scope"),
    )
    .expect("enqueue cloud media backup for other scope");
    conn.execute(
        "INSERT INTO kv(key, value) VALUES (?1, ?2), (?3, ?4)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        rusqlite::params![
            format!("managed_vault_v2.generation_id:{scope_id}"),
            "generation-old",
            format!("managed_vault_v2.last_pushed_seq:{scope_id}:{device_id}"),
            last_local_seq.to_string(),
        ],
    )
    .expect("seed old generation and pushed seq");

    let pulled = sync::managed_vault::pull(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
        .expect("pull should ignore cloud media backup work from a different scope");
    assert_eq!(pulled, 0);

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}
