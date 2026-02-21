use std::sync::atomic::{AtomicUsize, Ordering};

use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;

struct CountingAttachmentRemote {
    inner: sync::InMemoryRemoteStore,
    attachment_put_calls: AtomicUsize,
    attachment_delete_calls: AtomicUsize,
}

impl CountingAttachmentRemote {
    fn new() -> Self {
        Self {
            inner: sync::InMemoryRemoteStore::new(),
            attachment_put_calls: AtomicUsize::new(0),
            attachment_delete_calls: AtomicUsize::new(0),
        }
    }

    fn attachment_put_calls(&self) -> usize {
        self.attachment_put_calls.load(Ordering::Relaxed)
    }

    fn attachment_delete_calls(&self) -> usize {
        self.attachment_delete_calls.load(Ordering::Relaxed)
    }
}

impl sync::RemoteStore for CountingAttachmentRemote {
    fn target_id(&self) -> &str {
        self.inner.target_id()
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
        if path.contains("/attachments/") {
            self.attachment_put_calls.fetch_add(1, Ordering::Relaxed);
        }
        self.inner.put(path, bytes)
    }

    fn delete(&self, path: &str) -> anyhow::Result<()> {
        if path.contains("/attachments/") {
            self.attachment_delete_calls.fetch_add(1, Ordering::Relaxed);
        }
        self.inner.delete(path)
    }
}

#[test]
fn webdav_push_skips_redundant_attachment_upload_when_same_batch_deletes_it() {
    let remote = CountingAttachmentRemote::new();
    let remote_root = "SecondLoopTest";

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

    let pushed = sync::push(&conn, &key, &sync_key, &remote, remote_root).expect("push");
    assert!(pushed > 0);

    assert_eq!(
        remote.attachment_put_calls(),
        0,
        "no attachment upload should be attempted when final op deletes it"
    );
    assert!(remote.attachment_delete_calls() >= 1);
}
