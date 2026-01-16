use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;

struct CachedListingRemote {
    inner: sync::InMemoryRemoteStore,
    remote_root_dir: String,
    device_id: String,
}

impl CachedListingRemote {
    fn new(inner: sync::InMemoryRemoteStore, remote_root_dir: String, device_id: String) -> Self {
        Self {
            inner,
            remote_root_dir,
            device_id,
        }
    }
}

impl sync::RemoteStore for CachedListingRemote {
    fn target_id(&self) -> &str {
        self.inner.target_id()
    }

    fn mkdir_all(&self, path: &str) -> anyhow::Result<()> {
        self.inner.mkdir_all(path)
    }

    fn list(&self, dir: &str) -> anyhow::Result<Vec<String>> {
        // Simulate a cached/broken PROPFIND result: only the root dir listing is correct.
        if dir == self.remote_root_dir {
            return Ok(vec![format!("{}{}/", self.remote_root_dir, self.device_id)]);
        }
        Ok(vec![])
    }

    fn get(&self, path: &str) -> anyhow::Result<Vec<u8>> {
        self.inner.get(path)
    }

    fn put(&self, path: &str, bytes: Vec<u8>) -> anyhow::Result<()> {
        self.inner.put(path, bytes)
    }
}

#[test]
fn pull_does_not_depend_on_ops_listing() {
    let remote_root = "SecondLoopTest";
    let remote_root_dir = format!("/{}/", remote_root.trim_matches('/'));

    // Device A creates data locally.
    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a = auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test())
        .expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");
    let conv_a = db::create_conversation(&conn_a, &key_a, "Inbox").expect("create convo A");
    db::insert_message(&conn_a, &key_a, &conv_a.id, "user", "hello").expect("insert msg A");

    let device_id_a: String = conn_a
        .query_row(
            r#"SELECT value FROM kv WHERE key = 'device_id'"#,
            [],
            |row| row.get(0),
        )
        .expect("device_id exists");

    // Push A -> remote.
    let inner_remote = sync::InMemoryRemoteStore::new();
    let sync_key = derive_root_key("sync-passphrase", b"secondloop-sync1", &KdfParams::for_test())
        .expect("derive sync key");
    let pushed = sync::push(&conn_a, &key_a, &sync_key, &inner_remote, remote_root).expect("push");
    assert!(pushed > 0);

    // Device B pulls from a remote where ops listing is "cached" (empty).
    let remote = CachedListingRemote::new(inner_remote, remote_root_dir, device_id_a);

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b = auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test())
        .expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let applied = sync::pull(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("pull");
    assert!(applied > 0, "expected pull to apply ops even if ops listing is empty");

    let convs_b = db::list_conversations(&conn_b, &key_b).expect("list convs B");
    assert_eq!(convs_b.len(), 1);
    assert_eq!(convs_b[0].title, "Inbox");
    assert_eq!(convs_b[0].id, conv_a.id);

    let msgs_b = db::list_messages(&conn_b, &key_b, &convs_b[0].id).expect("list msgs B");
    assert_eq!(msgs_b.len(), 1);
    assert_eq!(msgs_b[0].content, "hello");
}
