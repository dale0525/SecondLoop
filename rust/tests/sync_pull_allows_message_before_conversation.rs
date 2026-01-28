use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;

struct OrderedRootListingRemote {
    inner: sync::InMemoryRemoteStore,
    remote_root_dir: String,
    ordered_device_ids: Vec<String>,
}

impl OrderedRootListingRemote {
    fn new(
        inner: sync::InMemoryRemoteStore,
        remote_root_dir: String,
        ordered_device_ids: Vec<String>,
    ) -> Self {
        Self {
            inner,
            remote_root_dir,
            ordered_device_ids,
        }
    }
}

impl sync::RemoteStore for OrderedRootListingRemote {
    fn target_id(&self) -> &str {
        self.inner.target_id()
    }

    fn mkdir_all(&self, path: &str) -> anyhow::Result<()> {
        self.inner.mkdir_all(path)
    }

    fn list(&self, dir: &str) -> anyhow::Result<Vec<String>> {
        if dir == self.remote_root_dir {
            return Ok(self
                .ordered_device_ids
                .iter()
                .map(|id| format!("{}{}/", self.remote_root_dir, id))
                .collect());
        }
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
fn pull_allows_message_before_conversation() {
    let remote_root = "SecondLoopTest";
    let remote_root_dir = format!("/{}/", remote_root.trim_matches('/'));

    let remote = sync::InMemoryRemoteStore::new();
    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    // Device A creates a conversation and pushes.
    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");
    let conv_a = db::create_conversation(&conn_a, &key_a, "Inbox").expect("create convo A");

    let pushed_a = sync::push(&conn_a, &key_a, &sync_key, &remote, remote_root).expect("push A");
    assert!(pushed_a > 0);

    // Device B pulls the conversation, then creates a message and pushes.
    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let applied_b = sync::pull(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("pull B");
    assert!(applied_b > 0);

    db::insert_message(&conn_b, &key_b, &conv_a.id, "user", "hello from B").expect("insert msg B");
    let pushed_b = sync::push(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("push B");
    assert!(pushed_b > 0);

    let device_id_a: String = conn_a
        .query_row(
            r#"SELECT value FROM kv WHERE key = 'device_id'"#,
            [],
            |row| row.get(0),
        )
        .expect("device_id A exists");
    let device_id_b: String = conn_b
        .query_row(
            r#"SELECT value FROM kv WHERE key = 'device_id'"#,
            [],
            |row| row.get(0),
        )
        .expect("device_id B exists");

    // Device C is a fresh install and sees root listing as [device B, device A], so message ops
    // may arrive before the conversation op.
    let ordered_remote = OrderedRootListingRemote::new(
        remote,
        remote_root_dir,
        vec![device_id_b.clone(), device_id_a.clone()],
    );

    let temp_c = tempfile::tempdir().expect("tempdir C");
    let app_dir_c = temp_c.path().join("secondloop_c");
    let key_c =
        auth::init_master_password(&app_dir_c, "pw-c", KdfParams::for_test()).expect("init C");
    let conn_c = db::open(&app_dir_c).expect("open C db");

    let applied_c =
        sync::pull(&conn_c, &key_c, &sync_key, &ordered_remote, remote_root).expect("pull C");
    assert!(applied_c > 0);

    let convs_c = db::list_conversations(&conn_c, &key_c).expect("list convs C");
    assert_eq!(convs_c.len(), 1);
    assert_eq!(convs_c[0].title, "Inbox");
    assert_eq!(convs_c[0].id, conv_a.id);

    let msgs_c = db::list_messages(&conn_c, &key_c, &conv_a.id).expect("list msgs C");
    assert_eq!(msgs_c.len(), 1);
    assert_eq!(msgs_c[0].content, "hello from B");
}
