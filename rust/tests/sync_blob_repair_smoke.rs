use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine as _;
use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;
use secondloop_rust::sync::RemoteStore;

fn scope_id(remote: &impl sync::RemoteStore, remote_root: &str) -> String {
    let root = format!("/{}", remote_root.trim_matches('/'));
    let root = format!("{}/", root.trim_end_matches('/'));
    URL_SAFE_NO_PAD.encode(format!("{}|{root}", remote.target_id()).as_bytes())
}

#[test]
fn webdav_blob_repair_queue_recovers_missing_attachment_on_next_pull() {
    let remote = sync::InMemoryRemoteStore::new();
    let remote_root = "SecondLoopTest";
    let scope_id = scope_id(&remote, remote_root);
    let bytes = b"repair queue attachment bytes";

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");
    let conversation =
        db::get_or_create_loop_home_conversation(&conn_a, &key_a).expect("conversation A");
    let message =
        db::insert_message(&conn_a, &key_a, &conversation.id, "user", "repair me").expect("msg A");
    let attachment = db::insert_attachment(&conn_a, &key_a, &app_dir_a, bytes, "image/jpeg")
        .expect("insert attachment");
    db::link_attachment_to_message(&conn_a, &key_a, &message.id, &attachment.sha256)
        .expect("link attachment");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pushed = sync::push(&conn_a, &key_a, &sync_key, &remote, remote_root).expect("push A");
    assert!(pushed > 0);

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");
    let applied = sync::pull(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("pull B");
    assert!(applied > 0);

    let remote_path = format!("/{remote_root}/attachments/{}.bin", attachment.sha256);
    remote
        .delete(&remote_path)
        .expect("delete remote attachment");

    let err = sync::download_attachment_bytes(
        &conn_b,
        &key_b,
        &sync_key,
        &remote,
        remote_root,
        &attachment.sha256,
    )
    .expect_err("download should fail and enqueue repair");
    assert!(err.to_string().contains("not found"));

    let diagnostics = sync::blob_repair::load_blob_repair_diagnostics(&conn_b, &scope_id)
        .expect("blob repair diagnostics after enqueue");
    assert_eq!(diagnostics.queued_count, 1);

    let uploaded = sync::upload_attachment_bytes(
        &conn_a,
        &key_a,
        &sync_key,
        &remote,
        remote_root,
        &attachment.sha256,
    )
    .expect("restore remote attachment");
    assert!(uploaded);

    let applied_again =
        sync::pull(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("pull B again");
    assert_eq!(applied_again, 0);

    let repaired = db::read_attachment_bytes(&conn_b, &key_b, &app_dir_b, &attachment.sha256)
        .expect("attachment bytes repaired");
    assert_eq!(repaired, bytes);

    let diagnostics = sync::blob_repair::load_blob_repair_diagnostics(&conn_b, &scope_id)
        .expect("blob repair diagnostics after repair");
    assert_eq!(diagnostics.queued_count, 0);
    assert!(diagnostics.last_attempted_at_ms.is_some());
}

#[test]
fn webdav_generation_reset_clears_blob_repair_queue() {
    let target_id = "webdav:https://example.invalid/dav/".to_string();
    let remote_root = "SecondLoopTest";
    let remote = FixedTargetRemote::new(target_id.clone());
    let scope_id = scope_id(&remote, remote_root);

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

    let conversation = db::get_or_create_loop_home_conversation(&conn, &key).expect("conversation");
    let _message =
        db::insert_message(&conn, &key, &conversation.id, "user", "repair me").expect("insert msg");

    let pushed = sync::push(&conn, &key, &sync_key, &remote, remote_root).expect("push");
    assert!(pushed > 0);

    sync::blob_repair::enqueue_blob_repair(
        &conn,
        &scope_id,
        sync::blob_repair::BlobRepairKind::DownloadAttachment {
            sha256: "missing-from-previous-generation".to_string(),
        },
    )
    .expect("enqueue repair");
    sync::blob_repair::record_blob_repair_error(&conn, &scope_id, "stale remote")
        .expect("record repair error");

    let diagnostics = sync::blob_repair::load_blob_repair_diagnostics(&conn, &scope_id)
        .expect("diagnostics before reset");
    assert_eq!(diagnostics.queued_count, 1);
    assert_eq!(diagnostics.last_error.as_deref(), Some("stale remote"));

    let reset_remote = FixedTargetRemote::new(target_id);
    let pushed_after_reset =
        sync::push(&conn, &key, &sync_key, &reset_remote, remote_root).expect("push after reset");
    assert!(pushed_after_reset > 0);

    let diagnostics = sync::blob_repair::load_blob_repair_diagnostics(&conn, &scope_id)
        .expect("diagnostics after reset");
    assert_eq!(diagnostics.queued_count, 0);
    assert_eq!(diagnostics.last_error, None);
}

struct FixedTargetRemote {
    target_id: String,
    inner: sync::InMemoryRemoteStore,
}

impl FixedTargetRemote {
    fn new(target_id: String) -> Self {
        Self {
            target_id,
            inner: sync::InMemoryRemoteStore::new(),
        }
    }
}

impl RemoteStore for FixedTargetRemote {
    fn target_id(&self) -> &str {
        &self.target_id
    }

    fn mkdir_all(&self, path: &str) -> anyhow::Result<()> {
        self.inner.mkdir_all(path)
    }

    fn list(&self, dir: &str) -> anyhow::Result<Vec<String>> {
        self.inner.list(dir)
    }

    fn get(&self, path: &str) -> anyhow::Result<Vec<u8>> {
        self.inner.get(path)
    }

    fn put(&self, path: &str, bytes: Vec<u8>) -> anyhow::Result<()> {
        self.inner.put(path, bytes)
    }

    fn delete(&self, path: &str) -> anyhow::Result<()> {
        self.inner.delete(path)
    }
}
