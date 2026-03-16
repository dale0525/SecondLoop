#[cfg(test)]
mod cursor_metadata_tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn push_ops_only_writes_cursor_json_with_max_seq() {
        let dir = tempdir().expect("tempdir");
        let conn = crate::db::open(dir.path()).expect("open");
        let db_key = [7u8; 32];
        let sync_key = [9u8; 32];

        let _conversation =
            crate::db::create_conversation(&conn, &db_key, "Test").expect("create conversation");

        let remote = InMemoryRemoteStore::new();
        let pushed = push_ops_only(&conn, &db_key, &sync_key, &remote, "SecondLoop")
            .expect("push ops only");
        assert_eq!(pushed, 1);

        let device_id: String = conn
            .query_row(
                r#"SELECT value FROM kv WHERE key = 'device_id'"#,
                [],
                |row| row.get(0),
            )
            .expect("device id");

        let cursor_path = format!("/SecondLoop/{device_id}/cursor.json");
        let cursor_bytes = remote.get(&cursor_path).expect("cursor.json exists");
        let cursor: serde_json::Value =
            serde_json::from_slice(&cursor_bytes).expect("cursor json");
        assert_eq!(cursor["max_seq"].as_i64(), Some(1));
    }
}

#[cfg(test)]
mod push_progress_tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use tempfile::tempdir;

    struct CountingRemoteStore {
        inner: InMemoryRemoteStore,
        list_calls: AtomicUsize,
        mkdir_calls: AtomicUsize,
        get_calls: AtomicUsize,
        put_calls: AtomicUsize,
    }

    impl CountingRemoteStore {
        fn new() -> Self {
            Self {
                inner: InMemoryRemoteStore::new(),
                list_calls: AtomicUsize::new(0),
                mkdir_calls: AtomicUsize::new(0),
                get_calls: AtomicUsize::new(0),
                put_calls: AtomicUsize::new(0),
            }
        }

        fn reset_counts(&self) {
            self.list_calls.store(0, Ordering::Relaxed);
            self.mkdir_calls.store(0, Ordering::Relaxed);
            self.get_calls.store(0, Ordering::Relaxed);
            self.put_calls.store(0, Ordering::Relaxed);
        }

        fn total_calls(&self) -> usize {
            self.list_calls.load(Ordering::Relaxed)
                + self.mkdir_calls.load(Ordering::Relaxed)
                + self.get_calls.load(Ordering::Relaxed)
                + self.put_calls.load(Ordering::Relaxed)
        }
    }

    impl RemoteStore for CountingRemoteStore {
        fn target_id(&self) -> &str {
            self.inner.target_id()
        }

        fn mkdir_all(&self, path: &str) -> Result<()> {
            self.mkdir_calls.fetch_add(1, Ordering::Relaxed);
            self.inner.mkdir_all(path)
        }

        fn list(&self, dir: &str) -> Result<Vec<String>> {
            self.list_calls.fetch_add(1, Ordering::Relaxed);
            self.inner.list(dir)
        }

        fn get(&self, path: &str) -> Result<Vec<u8>> {
            self.get_calls.fetch_add(1, Ordering::Relaxed);
            self.inner.get(path)
        }

        fn put(&self, path: &str, bytes: Vec<u8>) -> Result<()> {
            self.put_calls.fetch_add(1, Ordering::Relaxed);
            self.inner.put(path, bytes)
        }

        fn delete(&self, path: &str) -> Result<()> {
            self.inner.delete(path)
        }
    }

    #[test]
    fn push_ops_only_with_progress_reports_done_and_total() {
        let dir = tempdir().expect("tempdir");
        let conn = crate::db::open(dir.path()).expect("open");
        let db_key = [7u8; 32];
        let sync_key = [9u8; 32];

        let _c1 = crate::db::create_conversation(&conn, &db_key, "One").expect("c1");
        let _c2 = crate::db::create_conversation(&conn, &db_key, "Two").expect("c2");

        let remote = InMemoryRemoteStore::new();
        let mut seen: Vec<(u64, u64)> = Vec::new();
        let mut on_progress = |done: u64, total: u64| {
            seen.push((done, total));
        };

        let pushed = push_ops_only_with_progress(
            &conn,
            &db_key,
            &sync_key,
            &remote,
            "SecondLoop",
            &mut on_progress,
        )
        .expect("push ops only with progress");
        assert_eq!(pushed, 2);

        assert!(!seen.is_empty());
        assert_eq!(seen[0].1, 2);
        assert_eq!(*seen.last().expect("last progress"), (2, 2));
    }

    #[test]
    fn push_ops_only_with_progress_reports_total_when_repush_from_zero_needed() {
        let dir = tempdir().expect("tempdir");
        let conn = crate::db::open(dir.path()).expect("open");
        let db_key = [7u8; 32];
        let sync_key = [9u8; 32];

        let _c1 = crate::db::create_conversation(&conn, &db_key, "One").expect("c1");
        let _c2 = crate::db::create_conversation(&conn, &db_key, "Two").expect("c2");

        let remote = InMemoryRemoteStore::new();
        let pushed1 = push_ops_only(&conn, &db_key, &sync_key, &remote, "SecondLoop")
            .expect("push 1");
        assert_eq!(pushed1, 2);

        clear_remote_root(&remote, "SecondLoop").expect("clear remote root");
        let mut seen: Vec<(u64, u64)> = Vec::new();
        let mut on_progress = |done: u64, total: u64| {
            seen.push((done, total));
        };

        let pushed2 = push_ops_only_with_progress(
            &conn,
            &db_key,
            &sync_key,
            &remote,
            "SecondLoop",
            &mut on_progress,
        )
        .expect("push 2");
        assert_eq!(pushed2, 2);

        assert!(!seen.is_empty());
        assert_eq!(seen[0].1, 2);
        assert_eq!(*seen.last().expect("last progress"), (2, 2));
    }

    #[test]
    fn push_with_progress_skips_remote_work_for_fresh_device_without_local_ops() {
        let dir_a = tempdir().expect("tempdir A");
        let conn_a = crate::db::open(dir_a.path()).expect("open A");
        let db_key = [7u8; 32];
        let sync_key = [9u8; 32];

        let _conversation =
            crate::db::create_conversation(&conn_a, &db_key, "One").expect("conversation A");
        let _attachment = crate::db::insert_attachment(
            &conn_a,
            &db_key,
            dir_a.path(),
            b"hello sync",
            "image/png",
        )
        .expect("attachment A");

        let remote = CountingRemoteStore::new();
        let pushed_a = push(&conn_a, &db_key, &sync_key, &remote, "SecondLoop").expect("push A");
        assert_eq!(pushed_a, 2);

        let dir_b = tempdir().expect("tempdir B");
        let conn_b = crate::db::open(dir_b.path()).expect("open B");
        let pulled_b = pull(&conn_b, &db_key, &sync_key, &remote, "SecondLoop").expect("pull B");
        assert_eq!(pulled_b, 2);

        remote.reset_counts();

        let mut seen: Vec<(u64, u64)> = Vec::new();
        let mut on_progress = |done: u64, total: u64| {
            seen.push((done, total));
        };

        let pushed_b = push_with_progress(
            &conn_b,
            &db_key,
            &sync_key,
            &remote,
            "SecondLoop",
            &mut on_progress,
        )
        .expect("push B");

        assert_eq!(pushed_b, 0);
        assert_eq!(seen, vec![(0, 0)]);
        assert_eq!(remote.put_calls.load(Ordering::Relaxed), 0);
        assert_eq!(remote.mkdir_calls.load(Ordering::Relaxed), 0);
        assert!(
            remote.total_calls() > 0,
            "fresh device skip path should only probe remote state"
        );
    }

    #[test]
    fn push_with_progress_repairs_remote_bytes_after_fresh_device_remote_reset() {
        let dir_a = tempdir().expect("tempdir A");
        let conn_a = crate::db::open(dir_a.path()).expect("open A");
        let db_key = [7u8; 32];
        let sync_key = [9u8; 32];

        let _conversation =
            crate::db::create_conversation(&conn_a, &db_key, "One").expect("conversation A");
        let _attachment = crate::db::insert_attachment(
            &conn_a,
            &db_key,
            dir_a.path(),
            b"hello sync",
            "image/png",
        )
        .expect("attachment A");

        let remote = CountingRemoteStore::new();
        let pushed_a = push(&conn_a, &db_key, &sync_key, &remote, "SecondLoop").expect("push A");
        assert_eq!(pushed_a, 2);

        let dir_b = tempdir().expect("tempdir B");
        let conn_b = crate::db::open(dir_b.path()).expect("open B");
        let pulled_b = pull(&conn_b, &db_key, &sync_key, &remote, "SecondLoop").expect("pull B");
        assert_eq!(pulled_b, 2);

        clear_remote_root(&remote, "SecondLoop").expect("clear remote root");
        remote.reset_counts();

        let mut seen: Vec<(u64, u64)> = Vec::new();
        let mut on_progress = |done: u64, total: u64| {
            seen.push((done, total));
        }; 

        let pushed_b = push_with_progress(
            &conn_b,
            &db_key,
            &sync_key,
            &remote,
            "SecondLoop",
            &mut on_progress,
        )
        .expect("push B");

        assert!(pushed_b > 0);
        assert!(
            remote.total_calls() > 0,
            "fresh device should still probe and repair remote bytes after reset"
        );
        assert!(
            remote.put_calls.load(Ordering::Relaxed) > 0,
            "fresh device should re-upload attachment/artifact bytes after remote reset"
        );
        assert!(!seen.is_empty());
    }

    #[test]
    fn push_ops_only_repairs_remote_after_reset_without_new_local_ops() {
        let dir = tempdir().expect("tempdir");
        let conn = crate::db::open(dir.path()).expect("open");
        let db_key = [7u8; 32];
        let sync_key = [9u8; 32];

        let _conversation =
            crate::db::create_conversation(&conn, &db_key, "One").expect("conversation");

        let remote = InMemoryRemoteStore::new();
        let pushed1 = push_ops_only(&conn, &db_key, &sync_key, &remote, "SecondLoop")
            .expect("initial push");
        assert_eq!(pushed1, 1);

        clear_remote_root(&remote, "SecondLoop").expect("clear remote root");

        let pushed2 = push_ops_only(&conn, &db_key, &sync_key, &remote, "SecondLoop")
            .expect("repair push");
        assert_eq!(pushed2, 1);
    }
}

#[cfg(test)]
mod push_parallel_upload_tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::time::Duration;
    use tempfile::tempdir;

    struct TrackingRemoteStore {
        inner: InMemoryRemoteStore,
        op_put_delay: Duration,
        active_op_puts: AtomicUsize,
        max_parallel_op_puts: AtomicUsize,
    }

    impl TrackingRemoteStore {
        fn new(op_put_delay: Duration) -> Self {
            Self {
                inner: InMemoryRemoteStore::new(),
                op_put_delay,
                active_op_puts: AtomicUsize::new(0),
                max_parallel_op_puts: AtomicUsize::new(0),
            }
        }

        fn max_parallel_op_puts(&self) -> usize {
            self.max_parallel_op_puts.load(Ordering::Relaxed)
        }

        fn record_parallel_put_start(&self) {
            let active = self.active_op_puts.fetch_add(1, Ordering::Relaxed) + 1;
            let mut seen = self.max_parallel_op_puts.load(Ordering::Relaxed);
            while active > seen {
                match self.max_parallel_op_puts.compare_exchange(
                    seen,
                    active,
                    Ordering::Relaxed,
                    Ordering::Relaxed,
                ) {
                    Ok(_) => break,
                    Err(cur) => seen = cur,
                }
            }
        }

        fn record_parallel_put_end(&self) {
            self.active_op_puts.fetch_sub(1, Ordering::Relaxed);
        }
    }

    impl RemoteStore for TrackingRemoteStore {
        fn target_id(&self) -> &str {
            self.inner.target_id()
        }

        fn mkdir_all(&self, path: &str) -> Result<()> {
            self.inner.mkdir_all(path)
        }

        fn list(&self, dir: &str) -> Result<Vec<String>> {
            self.inner.list(dir)
        }

        fn get(&self, path: &str) -> Result<Vec<u8>> {
            self.inner.get(path)
        }

        fn put(&self, path: &str, bytes: Vec<u8>) -> Result<()> {
            if path.contains("/ops/op_") {
                self.record_parallel_put_start();
                std::thread::sleep(self.op_put_delay);
                let result = self.inner.put(path, bytes);
                self.record_parallel_put_end();
                return result;
            }
            self.inner.put(path, bytes)
        }

        fn delete(&self, path: &str) -> Result<()> {
            self.inner.delete(path)
        }
    }

    #[test]
    fn push_ops_only_uploads_op_files_with_parallelism() {
        let dir = tempdir().expect("tempdir");
        let conn = crate::db::open(dir.path()).expect("open");
        let db_key = [7u8; 32];
        let sync_key = [9u8; 32];

        for idx in 0..24 {
            let title = format!("Conversation {idx}");
            let _ = crate::db::create_conversation(&conn, &db_key, &title).expect("create");
        }

        let remote = TrackingRemoteStore::new(Duration::from_millis(20));
        let pushed =
            push_ops_only(&conn, &db_key, &sync_key, &remote, "SecondLoop").expect("push");
        assert_eq!(pushed, 24);

        assert!(
            remote.max_parallel_op_puts() > 1,
            "expected parallel PUT uploads for op files"
        );
    }
}
