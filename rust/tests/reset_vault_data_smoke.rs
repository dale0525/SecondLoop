use std::path::Path;

use secondloop_rust::auth;
use secondloop_rust::crypto::KdfParams;
use secondloop_rust::db;
use secondloop_rust::sync;
use secondloop_rust::sync::RemoteStore;

#[test]
fn reset_vault_data_preserves_llm_profiles_and_embedding_model() {
    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(Path::new(&app_dir), "pw", KdfParams::for_test())
        .expect("init master password");
    let conn = db::open(&app_dir).expect("open db");

    let conv = db::get_or_create_loop_home_conversation(&conn, &key).expect("loop home");
    db::insert_message(&conn, &key, &conv.id, "user", "hello").expect("insert message");

    let profile = db::create_llm_profile(
        &conn,
        &key,
        "OpenAI",
        "openai-compatible",
        Some("https://api.openai.com/v1"),
        Some("sk-test"),
        "gpt-4o-mini",
        true,
    )
    .expect("create llm profile");
    db::record_llm_usage_daily(
        &conn,
        "2026-04-25",
        &profile.id,
        "ask_ai",
        Some(10),
        Some(20),
        Some(30),
    )
    .expect("record llm usage");

    db::set_active_embedding_model_name(&conn, "secondloop-default-embed-v0")
        .expect("set embedding model");

    assert_eq!(
        db::list_messages(&conn, &key, &conv.id)
            .expect("list messages")
            .len(),
        1
    );
    assert_eq!(
        db::list_llm_profiles(&conn)
            .expect("list llm profiles")
            .len(),
        1
    );
    assert_eq!(
        db::get_active_embedding_model_name(&conn)
            .expect("get embedding model")
            .as_deref(),
        Some("secondloop-default-embed-v0")
    );

    db::reset_vault_data_preserving_llm_profiles(&conn).expect("reset vault data");

    assert_eq!(
        db::list_messages(&conn, &key, &conv.id)
            .expect("list messages after reset")
            .len(),
        0
    );
    assert_eq!(
        db::list_llm_profiles(&conn)
            .expect("list llm profiles after reset")
            .len(),
        1
    );
    assert_eq!(
        db::get_active_embedding_model_name(&conn)
            .expect("get embedding model after reset")
            .as_deref(),
        Some("secondloop-default-embed-v0")
    );
    let usage = db::sum_llm_usage_daily_by_purpose(&conn, &profile.id, "2026-04-25", "2026-04-25")
        .expect("sum llm usage after reset");
    assert_eq!(usage.len(), 1);
    assert_eq!(usage[0].purpose, "ask_ai");
    assert_eq!(usage[0].requests, 1);
    assert_eq!(usage[0].input_tokens, 10);
    assert_eq!(usage[0].output_tokens, 20);
    assert_eq!(usage[0].total_tokens, 30);
}

#[test]
fn reset_vault_data_deletes_external_readonly_import_data() {
    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let _key = auth::init_master_password(Path::new(&app_dir), "pw", KdfParams::for_test())
        .expect("init master password");
    let conn = db::open(&app_dir).expect("open db");
    let external_conn = db::open_external_readonly_db(&app_dir).expect("open external db");

    external_conn
        .execute(
            r#"INSERT INTO external_import_batches(
              batch_id, source_kind, source_label, status,
              created_at_ms, updated_at_ms, stats_json
            ) VALUES ('batch-1', 'obsidian', 'External', 'completed', 1, 1, '{}')"#,
            [],
        )
        .expect("insert external batch");
    external_conn
        .execute(
            r#"INSERT INTO external_documents(
              doc_id, batch_id, title, body_markdown, tags_json,
              created_at_ms, updated_at_ms, checksum_sha256
            ) VALUES ('doc-1', 'batch-1', x'01', x'02', x'03', 1, 1, 'checksum')"#,
            [],
        )
        .expect("insert external document");
    std::fs::create_dir_all(app_dir.join("external_readonly/storage/attachments"))
        .expect("create external attachment dir");
    std::fs::write(
        app_dir.join("external_readonly/storage/attachments/external.bin"),
        b"external attachment",
    )
    .expect("write external attachment");
    drop(external_conn);

    assert!(
        app_dir
            .join("external_readonly/external_readonly.sqlite3")
            .exists(),
        "external readonly db should exist before reset"
    );
    assert_eq!(
        db::list_llm_profiles(&conn)
            .expect("list llm profiles before reset")
            .len(),
        0
    );

    db::reset_vault_data_preserving_llm_profiles(&conn).expect("reset vault data");

    assert!(
        !app_dir.join("external_readonly").exists(),
        "external readonly data should be deleted after reset"
    );
    assert_eq!(
        db::list_llm_profiles(&conn)
            .expect("list llm profiles after reset")
            .len(),
        0
    );
}

#[test]
fn reset_vault_data_deletes_dynamic_embedding_tables() {
    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let _key = auth::init_master_password(Path::new(&app_dir), "pw", KdfParams::for_test())
        .expect("init master password");
    let conn = db::open(&app_dir).expect("open db");

    conn.execute_batch(
        r#"
CREATE TABLE message_embeddings__s_review_4(embedding BLOB, message_id TEXT, model_name TEXT);
CREATE TABLE todo_embeddings__s_review_4(embedding BLOB, todo_id TEXT, model_name TEXT);
CREATE TABLE todo_activity_embeddings__s_review_4(embedding BLOB, activity_id TEXT, todo_id TEXT, model_name TEXT);
CREATE TABLE attachment_chunk_embeddings__s_review_4(embedding BLOB, chunk_rowid INTEGER, model_name TEXT);
INSERT INTO message_embeddings__s_review_4 VALUES (X'01', 'message-1', 'review');
INSERT INTO todo_embeddings__s_review_4 VALUES (X'02', 'todo-1', 'review');
INSERT INTO todo_activity_embeddings__s_review_4 VALUES (X'03', 'activity-1', 'todo-1', 'review');
INSERT INTO attachment_chunk_embeddings__s_review_4 VALUES (X'04', 1, 'review');
"#,
    )
    .expect("seed dynamic embedding tables");

    db::reset_vault_data_preserving_llm_profiles(&conn).expect("reset vault data");

    for table in [
        "message_embeddings__s_review_4",
        "todo_embeddings__s_review_4",
        "todo_activity_embeddings__s_review_4",
        "attachment_chunk_embeddings__s_review_4",
    ] {
        let count: i64 = conn
            .query_row(&format!(r#"SELECT COUNT(*) FROM "{table}""#), [], |row| {
                row.get(0)
            })
            .expect("count dynamic embedding table");
        assert_eq!(count, 0, "{table} should be empty after reset");
    }
}

#[test]
fn reset_vault_data_deletes_embedding_artifact_blobs() {
    let temp = tempfile::tempdir().expect("tempdir");
    let app_dir = temp.path().join("secondloop");
    let key = auth::init_master_password(Path::new(&app_dir), "pw", KdfParams::for_test())
        .expect("init master password");
    let conn = db::open(&app_dir).expect("open db");
    let blob_ref = "blob/reset-artifact";

    db::write_embedding_artifact_blob(&app_dir, &key, blob_ref, b"artifact-secret")
        .expect("write artifact blob");
    db::record_embedding_artifact_manifest(
        &conn,
        db::EmbeddingArtifactManifestInput {
            source_kind: "message",
            source_id: "message-1",
            source_revision: 1,
            chunk_hash: "chunk-1",
            chunk_ordinal: 0,
            profile_id: "profile-1",
            producer_device_id: Some("device-a"),
            producer_class: "desktop",
            quality_tier: "full",
            vector_format: "f32",
            dimension: 4,
            blob_ref,
            created_at_ms: Some(1),
        },
    )
    .expect("record artifact manifest");
    let artifact_path = app_dir.join(db::embedding_artifact_blob_rel_path(blob_ref));
    assert!(
        artifact_path.exists(),
        "artifact blob should exist before reset"
    );

    db::reset_vault_data_preserving_llm_profiles(&conn).expect("reset vault data");

    let manifest_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM embedding_artifact_manifests",
            [],
            |row| row.get(0),
        )
        .expect("count artifact manifests");
    assert_eq!(manifest_count, 0);
    assert!(
        !artifact_path.exists(),
        "artifact blob should be deleted after reset"
    );
}

#[test]
fn reset_vault_data_removes_stale_attachment_reset_staging_dirs() {
    let dir = tempfile::tempdir().expect("tempdir");
    let app_dir = dir.path().join("app");
    let conn = db::open(&app_dir).expect("open db");

    let stale_staged_dir = app_dir.join("attachments.reset-staged-stale");
    std::fs::create_dir_all(&stale_staged_dir).expect("create stale staged dir");
    std::fs::write(stale_staged_dir.join("orphan.bin"), b"orphan")
        .expect("write stale staged attachment");

    db::reset_vault_data_preserving_llm_profiles(&conn).expect("reset vault data");

    assert!(
        !stale_staged_dir.exists(),
        "stale attachment reset staging data should be removed"
    );
}

#[test]
fn clear_remote_root_deletes_localdir_data() {
    let remote_dir = tempfile::tempdir().expect("remote dir");
    let remote = sync::localdir::LocalDirRemoteStore::new(remote_dir.path().to_path_buf())
        .expect("create localdir remote");
    let remote_root = "SecondLoopTest";

    remote.mkdir_all(remote_root).expect("mkdir remote root");
    remote
        .put(
            &format!("{remote_root}/deviceA/ops/op_1.json"),
            br#"{"op_id":"1"}"#.to_vec(),
        )
        .expect("write remote op");

    let remote_root_path = remote_dir.path().join(remote_root);
    assert!(remote_root_path.exists(), "remote root should exist");

    sync::clear_remote_root(&remote, remote_root).expect("clear remote root");

    assert!(
        !remote_root_path.exists(),
        "remote root directory should be deleted"
    );
}
