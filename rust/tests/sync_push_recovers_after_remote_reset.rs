use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;
use secondloop_rust::sync::RemoteStore;

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

impl sync::RemoteStore for FixedTargetRemote {
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

#[test]
fn push_reuploads_ops_if_remote_target_lost_cursor_file() {
    let remote_root = "SecondLoopTest";
    let target_id = "webdav:https://example.invalid/dav/".to_string();

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    let conv = db::create_conversation(&conn, &key, "Inbox").expect("create convo");
    db::insert_message(&conn, &key, &conv.id, "user", "hello").expect("insert msg");

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let remote = FixedTargetRemote::new(target_id.clone());
    let pushed = sync::push(&conn, &key, &sync_key, &remote, remote_root).expect("push");
    assert!(pushed > 0);
    let scope_id = {
        use base64::engine::general_purpose::URL_SAFE_NO_PAD;
        use base64::Engine as _;
        URL_SAFE_NO_PAD.encode(format!("{target_id}|/{remote_root}/").as_bytes())
    };
    let initial_generation: String = conn
        .query_row(
            r#"SELECT value FROM kv WHERE key = ?1"#,
            rusqlite::params![format!("sync.webdav.generation_id:{scope_id}")],
            |row| row.get(0),
        )
        .expect("initial generation");

    // Simulate the same remote target being reset/emptied: same target id, but empty storage.
    let reset_remote = FixedTargetRemote::new(target_id);
    let pushed_after_reset =
        sync::push(&conn, &key, &sync_key, &reset_remote, remote_root).expect("push after reset");

    assert!(
        pushed_after_reset > 0,
        "expected re-upload after remote reset, got {pushed_after_reset}"
    );
    let next_generation: String = conn
        .query_row(
            r#"SELECT value FROM kv WHERE key = ?1"#,
            rusqlite::params![format!("sync.webdav.generation_id:{scope_id}")],
            |row| row.get(0),
        )
        .expect("next generation");
    assert_ne!(initial_generation, next_generation);
    let manifest_bytes = reset_remote
        .get(&format!("/{remote_root}/sync_manifest.json"))
        .expect("root manifest exists after reset");
    let manifest_json: serde_json::Value =
        serde_json::from_slice(&manifest_bytes).expect("parse manifest");
    assert_eq!(
        manifest_json["generation_id"].as_str(),
        Some(next_generation.as_str())
    );
}
