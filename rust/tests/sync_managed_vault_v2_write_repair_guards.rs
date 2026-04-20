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
fn managed_vault_v2_pull_does_not_drain_local_write_repairs() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");
    let attachment =
        db::insert_attachment(&conn, &key, &app_dir, b"local-write-repair", "image/png")
            .expect("insert attachment");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let scope_id = managed_vault_v2_scope_id(&base_url, &vault_id);
    blob_repair::enqueue_blob_repair(
        &conn,
        &scope_id,
        BlobRepairKind::UploadAttachment {
            sha256: attachment.sha256.clone(),
        },
    )
    .expect("enqueue upload repair");
    blob_repair::enqueue_blob_repair(
        &conn,
        &scope_id,
        BlobRepairKind::DeleteAttachmentRemote {
            sha256: "remote-delete".to_string(),
        },
    )
    .expect("enqueue delete repair");

    {
        let mut server = state.lock().expect("lock");
        server
            .attachments
            .insert("remote-delete".to_string(), b"remote bytes".to_vec());
    }

    let pulled = sync::managed_vault::pull(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
        .expect("pull");
    assert_eq!(pulled, 0);

    let diagnostics =
        blob_repair::load_blob_repair_diagnostics(&conn, &scope_id).expect("load diagnostics");
    assert_eq!(diagnostics.queued_count, 2);

    let state = state.lock().expect("lock");
    let requests = state.requests.join("\n\n");
    assert!(requests.contains("/v2/vaults/v1/sync/pull"));
    assert!(
        !requests.contains("PUT /v1/vaults/v1/attachments/"),
        "pull unexpectedly uploaded attachment bytes: {requests}"
    );
    assert!(
        !requests.contains("DELETE /v1/vaults/v1/attachments/"),
        "pull unexpectedly deleted attachment bytes: {requests}"
    );
    assert!(
        state.attachments.contains_key("remote-delete"),
        "pull should not drain delete repair work"
    );

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_v2_push_stays_on_v2_when_remote_attachment_bytes_are_not_cached_locally() {
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
    let conversation =
        db::create_conversation(&conn_a, &key_a, "Inbox").expect("create conversation");
    let message = db::insert_message(&conn_a, &key_a, &conversation.id, "user", "with attachment")
        .expect("insert message");
    let attachment = db::insert_attachment(
        &conn_a,
        &key_a,
        &app_dir_a,
        b"shared attachment",
        "image/png",
    )
    .expect("insert attachment");
    db::link_attachment_to_message(&conn_a, &key_a, &message.id, &attachment.sha256)
        .expect("link attachment");
    let scope_id_a = managed_vault_v2_scope_id(&base_url, &vault_id);
    conn_a
        .execute(
            "INSERT INTO kv(key, value) VALUES (?1, '1'), (?2, '1')
             ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            rusqlite::params![
                format!("managed_vault.attachments.bytes_backfilled:{scope_id_a}"),
                format!("managed_vault.embedding_artifacts.bytes_backfilled:{scope_id_a}"),
            ],
        )
        .expect("seed A backfill flags");

    let pushed_a =
        sync::managed_vault::push(&conn_a, &key_a, &sync_key, &base_url, &vault_id, &id_token)
            .expect("push A");
    assert!(pushed_a > 0);

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let pulled_b =
        sync::managed_vault::pull(&conn_b, &key_b, &sync_key, &base_url, &vault_id, &id_token)
            .expect("pull B");
    assert!(pulled_b > 0);

    let attachment_row: Option<(String, String)> = conn_b
        .query_row("SELECT sha256, path FROM attachments LIMIT 1", [], |row| {
            Ok((row.get(0)?, row.get(1)?))
        })
        .optional()
        .expect("load attachment row");
    let (pulled_sha256, pulled_path) = attachment_row.expect("pulled attachment row");
    assert_eq!(pulled_sha256, attachment.sha256);
    assert!(
        !app_dir_b.join(pulled_path).exists(),
        "pull should not eagerly materialize remote attachment bytes"
    );

    let convs_b = db::list_conversations(&conn_b, &key_b).expect("list conversations");
    db::insert_message(&conn_b, &key_b, &convs_b[0].id, "user", "follow-up change")
        .expect("insert follow-up");

    state.lock().expect("lock").requests.clear();

    let pushed_b =
        sync::managed_vault::push(&conn_b, &key_b, &sync_key, &base_url, &vault_id, &id_token)
            .expect("push B");
    assert!(pushed_b > 0);

    let requests = state.lock().expect("lock").requests.join("\n\n");
    assert!(
        requests.contains("/v2/vaults/v1/sync/push"),
        "expected B to stay on v2 push route: {requests}"
    );
    assert!(
        !requests.contains("/v1/vaults/v1/ops:push"),
        "cached-remote attachment bytes should not force legacy push: {requests}"
    );

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}

#[test]
fn managed_vault_v2_pull_blocks_destructive_rebuild_when_delete_repair_is_pending() {
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
    blob_repair::enqueue_blob_repair(
        &conn,
        &scope_id,
        BlobRepairKind::DeleteAttachmentRemote {
            sha256: "remote-delete".to_string(),
        },
    )
    .expect("enqueue delete repair");

    let error = sync::managed_vault::pull(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
        .expect_err("pull should refuse destructive rebuild while delete repair is pending");
    assert!(
        error.to_string().contains("local_media_backfill_pending"),
        "unexpected error: {error:#}"
    );

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}
