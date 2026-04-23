use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;

#[path = "support/managed_vault_v2_test_server.rs"]
mod managed_vault_v2_test_server;

use managed_vault_v2_test_server::start_mock_v2_server;

#[test]
fn managed_vault_push_skips_redundant_attachment_upload_when_same_batch_deletes_it() {
    let (base_url, stop_tx, state, handle) = start_mock_v2_server();
    let vault_id = "v1".to_string();
    let id_token = "test_uid".to_string();

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let conversation =
        db::get_or_create_loop_home_conversation(&conn, &key).expect("main conversation");
    let message =
        db::insert_message(&conn, &key, &conversation.id, "user", "hello").expect("insert message");
    let attachment = db::insert_attachment(&conn, &key, &app_dir, b"image", "image/png")
        .expect("insert attachment");
    db::link_attachment_to_message(&conn, &key, &message.id, &attachment.sha256)
        .expect("link attachment");

    let purged = db::purge_message_attachments(&conn, &key, &app_dir, &message.id)
        .expect("purge message attachments");
    assert!(purged > 0);

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pushed = sync::managed_vault::push(&conn, &key, &sync_key, &base_url, &vault_id, &id_token)
        .expect("push");
    assert!(pushed > 0);

    let state = state.lock().expect("lock");
    let requests = state.requests.join("\n\n");
    assert!(requests.contains("/v2/vaults/v1/sync/push"));
    assert!(!requests.contains("PUT /v1/vaults/v1/attachments/"));
    assert!(requests.contains("DELETE /v1/vaults/v1/attachments/"));
    assert!(!state.attachments.contains_key(&attachment.sha256));

    stop_tx.send(()).expect("stop");
    handle.join().expect("join");
}
