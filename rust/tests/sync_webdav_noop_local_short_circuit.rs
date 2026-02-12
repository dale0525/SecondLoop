use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;

struct PanicRemoteStore;

impl sync::RemoteStore for PanicRemoteStore {
    fn target_id(&self) -> &str {
        "webdav:https://example.invalid/dav/"
    }

    fn mkdir_all(&self, _path: &str) -> anyhow::Result<()> {
        panic!("mkdir_all should not be called for local no-op push");
    }

    fn list(&self, _dir: &str) -> anyhow::Result<Vec<String>> {
        panic!("list should not be called for local no-op push");
    }

    fn get(&self, _path: &str) -> anyhow::Result<Vec<u8>> {
        panic!("get should not be called for local no-op push");
    }

    fn put(&self, _path: &str, _bytes: Vec<u8>) -> anyhow::Result<()> {
        panic!("put should not be called for local no-op push");
    }

    fn delete(&self, _path: &str) -> anyhow::Result<()> {
        panic!("delete should not be called for local no-op push");
    }
}

#[test]
fn webdav_push_ops_only_returns_without_remote_calls_when_no_local_ops() {
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

    let pushed = sync::push_ops_only(&conn, &key, &sync_key, &PanicRemoteStore, "SecondLoop")
        .expect("push ops only");

    assert_eq!(pushed, 0);
}
