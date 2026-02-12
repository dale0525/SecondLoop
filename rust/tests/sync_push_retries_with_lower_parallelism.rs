use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Duration;

use anyhow::anyhow;
use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;

struct LimitedParallelPutRemote {
    target_id: String,
    inner: sync::InMemoryRemoteStore,
    max_parallel_ops: usize,
    active_ops: AtomicUsize,
    max_seen_ops: AtomicUsize,
}

impl LimitedParallelPutRemote {
    fn new(target_id: String, max_parallel_ops: usize) -> Self {
        Self {
            target_id,
            inner: sync::InMemoryRemoteStore::new(),
            max_parallel_ops,
            active_ops: AtomicUsize::new(0),
            max_seen_ops: AtomicUsize::new(0),
        }
    }

    fn max_seen_ops(&self) -> usize {
        self.max_seen_ops.load(Ordering::Relaxed)
    }

    fn track_active_op_start(&self) -> usize {
        let active = self.active_ops.fetch_add(1, Ordering::Relaxed) + 1;
        let mut seen = self.max_seen_ops.load(Ordering::Relaxed);
        while active > seen {
            match self.max_seen_ops.compare_exchange(
                seen,
                active,
                Ordering::Relaxed,
                Ordering::Relaxed,
            ) {
                Ok(_) => break,
                Err(cur) => seen = cur,
            }
        }
        active
    }

    fn track_active_op_end(&self) {
        self.active_ops.fetch_sub(1, Ordering::Relaxed);
    }
}

impl sync::RemoteStore for LimitedParallelPutRemote {
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
        if path.contains("/ops/op_") {
            let active = self.track_active_op_start();
            if active > self.max_parallel_ops {
                self.track_active_op_end();
                return Err(anyhow!("simulated parallel PUT limit reached"));
            }

            std::thread::sleep(Duration::from_millis(8));
            let result = self.inner.put(path, bytes);
            self.track_active_op_end();
            return result;
        }
        self.inner.put(path, bytes)
    }

    fn delete(&self, path: &str) -> anyhow::Result<()> {
        self.inner.delete(path)
    }
}

#[test]
fn push_ops_only_retries_with_lower_parallelism_when_remote_limits_concurrency() {
    let remote_root = "SecondLoopTest";
    let target_id = "webdav:https://example.invalid/dav/".to_string();

    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(&app_dir, "pw", KdfParams::for_test()).expect("init");
    let conn = db::open(&app_dir).expect("open db");

    for idx in 0..36 {
        let title = format!("Conversation {idx}");
        let _ = db::create_conversation(&conn, &key, &title).expect("create conversation");
    }

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let remote = LimitedParallelPutRemote::new(target_id, 2);
    let pushed = sync::push_ops_only(&conn, &key, &sync_key, &remote, remote_root)
        .expect("push should adapt to remote limit");

    assert_eq!(pushed, 36);
    assert!(
        remote.max_seen_ops() > 2,
        "expected initial high parallel attempt before fallback"
    );
}
