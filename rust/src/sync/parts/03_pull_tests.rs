#[cfg(test)]
mod read_cursor_tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn read_remote_cursor_max_seq_reads_max_seq() {
        let dir = tempdir().expect("tempdir");
        let conn = crate::db::open(dir.path()).expect("open");
        let db_key = [7u8; 32];
        let sync_key = [9u8; 32];

        let _conversation =
            crate::db::create_conversation(&conn, &db_key, "Test").expect("create conversation");

        let remote = InMemoryRemoteStore::new();
        let _ = push_ops_only(&conn, &db_key, &sync_key, &remote, "SecondLoop")
            .expect("push ops only");

        let device_id: String = conn
            .query_row(
                r#"SELECT value FROM kv WHERE key = 'device_id'"#,
                [],
                |row| row.get(0),
            )
            .expect("device id");

        let remote_root_dir = normalize_dir("SecondLoop");
        let max_seq =
            read_remote_cursor_max_seq(&remote, &remote_root_dir, &device_id).expect("read");
        assert_eq!(max_seq, Some(1));
    }
}

#[cfg(test)]
mod pull_progress_tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn pull_with_progress_reports_total_ops_from_cursor_json() {
        let db_key = [7u8; 32];
        let sync_key = [9u8; 32];
        let remote = InMemoryRemoteStore::new();

        // Device A pushes 1 op + cursor.json to the remote.
        let dir_a = tempdir().expect("tempdir A");
        let conn_a = crate::db::open(dir_a.path()).expect("open A");
        let _conversation =
            crate::db::create_conversation(&conn_a, &db_key, "Test").expect("create A");
        let pushed = push_ops_only(&conn_a, &db_key, &sync_key, &remote, "SecondLoop")
            .expect("push A");
        assert_eq!(pushed, 1);

        // Device B pulls with progress.
        let dir_b = tempdir().expect("tempdir B");
        let conn_b = crate::db::open(dir_b.path()).expect("open B");
        let mut seen: Vec<(u64, u64)> = Vec::new();
        let mut on_progress = |done: u64, total: u64| {
            seen.push((done, total));
        };

        let applied = pull_with_progress(
            &conn_b,
            &db_key,
            &sync_key,
            &remote,
            "SecondLoop",
            &mut on_progress,
        )
        .expect("pull B");
        assert_eq!(applied, 1);

        assert!(!seen.is_empty());
        assert_eq!(seen[0].1, 1);
        assert_eq!(*seen.last().unwrap(), (1, 1));
    }

    #[test]
    fn pull_syncs_non_recurring_todo_completion() {
        let db_key = [11u8; 32];
        let sync_key = [12u8; 32];
        let remote = InMemoryRemoteStore::new();

        let dir_a = tempdir().expect("tempdir A");
        let conn_a = crate::db::open(dir_a.path()).expect("open A");
        let todo_a = crate::db::upsert_todo(
            &conn_a,
            &db_key,
            "todo:sync:plain",
            "Plain task",
            Some(1_710_000_000_000),
            "open",
            None,
            None,
            None,
            Some(1_710_000_000_100),
            None,
            None,
        )
        .expect("create todo A");
        crate::db::set_todo_status(&conn_a, &db_key, &todo_a.id, "done", None)
            .expect("complete todo A");
        let pushed_a = push_ops_only(&conn_a, &db_key, &sync_key, &remote, "SecondLoop")
            .expect("push A");
        assert!(pushed_a >= 2);

        let dir_b = tempdir().expect("tempdir B");
        let conn_b = crate::db::open(dir_b.path()).expect("open B");
        let applied = pull(&conn_b, &db_key, &sync_key, &remote, "SecondLoop")
            .expect("pull B");
        assert!(applied >= 2);

        let synced = crate::db::get_todo(&conn_b, &db_key, &todo_a.id).expect("todo B");
        assert_eq!(synced.status, "done");
    }

    #[test]
    fn pull_syncs_recurring_todo_completion_and_next_occurrence() {
        let db_key = [13u8; 32];
        let sync_key = [14u8; 32];
        let remote = InMemoryRemoteStore::new();
        let recurrence_rule = r#"{"freq":"daily","interval":1}"#;

        let dir_a = tempdir().expect("tempdir A");
        let conn_a = crate::db::open(dir_a.path()).expect("open A");
        let todo_a = crate::db::upsert_todo(
            &conn_a,
            &db_key,
            "todo:sync:recurring:0",
            "Recurring task",
            Some(1_710_000_000_000),
            "open",
            None,
            None,
            None,
            Some(1_710_000_000_100),
            None,
            None,
        )
        .expect("create recurring todo A");
        crate::db::upsert_todo_recurrence_with_sync(
            &conn_a,
            &db_key,
            &todo_a.id,
            "series:sync:recurring",
            recurrence_rule,
        )
        .expect("create recurrence A");
        crate::db::set_todo_status(&conn_a, &db_key, &todo_a.id, "done", None)
            .expect("complete recurring todo A");
        let pushed_a = push_ops_only(&conn_a, &db_key, &sync_key, &remote, "SecondLoop")
            .expect("push A");
        assert!(pushed_a >= 4);

        let dir_b = tempdir().expect("tempdir B");
        let conn_b = crate::db::open(dir_b.path()).expect("open B");
        let applied = pull(&conn_b, &db_key, &sync_key, &remote, "SecondLoop")
            .expect("pull B");
        assert!(applied >= 4);

        let synced_current = crate::db::get_todo(&conn_b, &db_key, &todo_a.id)
            .expect("current recurring todo B");
        assert_eq!(synced_current.status, "done");

        let synced_next = crate::db::get_todo(
            &conn_b,
            &db_key,
            "todo:series:sync:recurring:1",
        )
        .expect("next recurring todo B");
        assert_eq!(synced_next.status, "open");
        assert_eq!(synced_next.due_at_ms, Some(1_710_086_400_000));

        let synced_rule = crate::db::get_todo_recurrence_rule_json(
            &conn_b,
            "todo:series:sync:recurring:1",
        )
        .expect("next recurrence rule B");
        assert_eq!(synced_rule.as_deref(), Some(recurrence_rule));
    }

    #[test]
    fn pull_with_progress_includes_embedding_artifact_downloads() {
        let db_key = [7u8; 32];
        let sync_key = [9u8; 32];
        let remote = InMemoryRemoteStore::new();

        let dir_a = tempdir().expect("tempdir A");
        let conn_a = crate::db::open(dir_a.path()).expect("open A");
        let conversation =
            crate::db::get_or_create_loop_home_conversation(&conn_a, &db_key).expect("conv A");
        let message = crate::db::insert_message(
            &conn_a,
            &db_key,
            &conversation.id,
            "user",
            "artifact progress note",
        )
        .expect("message A");
        let processed =
            crate::db::process_pending_message_embeddings_default(&conn_a, &db_key, 10)
                .expect("process embeddings A");
        assert_eq!(processed, 1);

        let pushed = push(&conn_a, &db_key, &sync_key, &remote, "SecondLoop").expect("push A");
        assert!(pushed > 0);

        let revision: i64 = conn_a
            .query_row(
                r#"SELECT updated_at FROM messages WHERE id = ?1"#,
                params![message.id.as_str()],
                |row| row.get(0),
            )
            .expect("revision A");
        let profile_id = crate::db::embedding_artifact_profile_id(
            crate::embedding::DEFAULT_MODEL_NAME,
            crate::embedding::DEFAULT_EMBED_DIM,
        );
        let manifests = crate::db::list_active_embedding_artifacts_for_source_revision(
            &conn_a,
            "message",
            &message.id,
            revision,
            &profile_id,
        )
        .expect("manifests A");
        assert_eq!(manifests.len(), 1);

        let dir_b = tempdir().expect("tempdir B");
        let conn_b = crate::db::open(dir_b.path()).expect("open B");
        let mut seen: Vec<(u64, u64)> = Vec::new();
        let mut on_progress = |done: u64, total: u64| {
            seen.push((done, total));
        };

        let applied = pull_with_progress(
            &conn_b,
            &db_key,
            &sync_key,
            &remote,
            "SecondLoop",
            &mut on_progress,
        )
        .expect("pull B");
        assert!(applied > 0);

        assert!(!seen.is_empty());
        let initial_total = seen[0].1;
        assert!(initial_total > 0, "expected non-zero initial total: {seen:?}");
        assert!(
            seen.iter().any(|&(_, total)| total == initial_total + 1),
            "expected total to grow by one artifact download: {seen:?}"
        );
        assert_eq!(
            *seen.last().expect("last progress"),
            (initial_total + 1, initial_total + 1)
        );
    }

    #[test]
    fn pull_with_progress_reclamps_done_when_some_embedding_artifact_blobs_are_missing() {
        let db_key = [7u8; 32];
        let sync_key = [9u8; 32];
        let remote = InMemoryRemoteStore::new();

        let dir_a = tempdir().expect("tempdir A");
        let conn_a = crate::db::open(dir_a.path()).expect("open A");
        let conversation =
            crate::db::get_or_create_loop_home_conversation(&conn_a, &db_key).expect("conv A");
        let _message_a = crate::db::insert_message(
            &conn_a,
            &db_key,
            &conversation.id,
            "user",
            "artifact reclamp A",
        )
        .expect("message A");
        let _message_b = crate::db::insert_message(
            &conn_a,
            &db_key,
            &conversation.id,
            "user",
            "artifact reclamp B",
        )
        .expect("message B");
        let processed = crate::db::process_pending_message_embeddings_default(&conn_a, &db_key, 10)
            .expect("process embeddings A");
        assert_eq!(processed, 2);

        let pushed = push(&conn_a, &db_key, &sync_key, &remote, "SecondLoop").expect("push A");
        assert!(pushed > 0);

        let blob_refs = crate::db::list_distinct_embedding_artifact_blob_refs(&conn_a)
            .expect("blob refs A");
        assert_eq!(blob_refs.len(), 2);
        let missing_blob_path = format!(
            "/SecondLoop/{}",
            crate::db::embedding_artifact_blob_rel_path(&blob_refs[1])
        );
        remote.delete(&missing_blob_path).expect("delete missing blob");

        let dir_b = tempdir().expect("tempdir B");
        let conn_b = crate::db::open(dir_b.path()).expect("open B");
        let mut seen: Vec<(u64, u64)> = Vec::new();
        let mut on_progress = |done: u64, total: u64| {
            seen.push((done, total));
        };

        let applied = pull_with_progress(
            &conn_b,
            &db_key,
            &sync_key,
            &remote,
            "SecondLoop",
            &mut on_progress,
        )
        .expect("pull B");
        assert!(applied > 0);

        let last = *seen.last().expect("last progress");
        assert_eq!(last.0, last.1, "expected final progress to stay clamped: {seen:?}");
    }

    #[test]
    fn pull_with_progress_finishes_when_remote_embedding_artifact_blob_is_missing() {
        let db_key = [7u8; 32];
        let sync_key = [9u8; 32];
        let remote = InMemoryRemoteStore::new();

        let dir_a = tempdir().expect("tempdir A");
        let conn_a = crate::db::open(dir_a.path()).expect("open A");
        let conversation =
            crate::db::get_or_create_loop_home_conversation(&conn_a, &db_key).expect("conv A");
        let message = crate::db::insert_message(
            &conn_a,
            &db_key,
            &conversation.id,
            "user",
            "artifact missing note",
        )
        .expect("message A");
        let processed =
            crate::db::process_pending_message_embeddings_default(&conn_a, &db_key, 10)
                .expect("process embeddings A");
        assert_eq!(processed, 1);

        let pushed = push(&conn_a, &db_key, &sync_key, &remote, "SecondLoop").expect("push A");
        assert!(pushed > 0);

        let revision: i64 = conn_a
            .query_row(
                r#"SELECT updated_at FROM messages WHERE id = ?1"#,
                params![message.id.as_str()],
                |row| row.get(0),
            )
            .expect("revision A");
        let profile_id = crate::db::embedding_artifact_profile_id(
            crate::embedding::DEFAULT_MODEL_NAME,
            crate::embedding::DEFAULT_EMBED_DIM,
        );
        let manifests = crate::db::list_active_embedding_artifacts_for_source_revision(
            &conn_a,
            "message",
            &message.id,
            revision,
            &profile_id,
        )
        .expect("manifests A");
        assert_eq!(manifests.len(), 1);

        let blob_path = format!(
            "/SecondLoop/{}",
            crate::db::embedding_artifact_blob_rel_path(&manifests[0].blob_ref)
        );
        remote.delete(&blob_path).expect("delete remote artifact blob");

        let dir_b = tempdir().expect("tempdir B");
        let conn_b = crate::db::open(dir_b.path()).expect("open B");
        let mut seen: Vec<(u64, u64)> = Vec::new();
        let mut on_progress = |done: u64, total: u64| {
            seen.push((done, total));
        };

        let applied = pull_with_progress(
            &conn_b,
            &db_key,
            &sync_key,
            &remote,
            "SecondLoop",
            &mut on_progress,
        )
        .expect("pull B");
        assert!(applied > 0);

        assert!(!seen.is_empty());
        let last = *seen.last().expect("last progress");
        assert_eq!(
            last.0, last.1,
            "progress should still complete when remote artifact blob is missing: {seen:?}"
        );
    }
}
