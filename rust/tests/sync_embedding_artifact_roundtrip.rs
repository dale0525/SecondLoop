use secondloop_rust::auth;
use secondloop_rust::crypto::{derive_root_key, KdfParams};
use secondloop_rust::db;
use secondloop_rust::sync;

fn message_updated_at(conn: &rusqlite::Connection, message_id: &str) -> i64 {
    conn.query_row(
        r#"SELECT updated_at FROM messages WHERE id = ?1"#,
        rusqlite::params![message_id],
        |row| row.get(0),
    )
    .expect("message updated_at")
}

#[test]
fn sync_pull_downloads_embedding_artifact_blobs_and_reuses_them() {
    let remote = sync::InMemoryRemoteStore::new();
    let remote_root = "SecondLoopTest";

    let temp_a = tempfile::tempdir().expect("tempdir A");
    let app_dir_a = temp_a.path().join("secondloop_a");
    let key_a =
        auth::init_master_password(&app_dir_a, "pw-a", KdfParams::for_test()).expect("init A");
    let conn_a = db::open(&app_dir_a).expect("open A db");
    let conversation =
        db::get_or_create_loop_home_conversation(&conn_a, &key_a).expect("conversation A");
    let message = db::insert_message(
        &conn_a,
        &key_a,
        &conversation.id,
        "user",
        "shared semantic note",
    )
    .expect("message A");
    let processed =
        db::process_pending_message_embeddings_default(&conn_a, &key_a, 10).expect("process A");
    assert_eq!(processed, 1);

    let revision_a = message_updated_at(&conn_a, &message.id);
    let profile_id = db::embedding_artifact_profile_id(
        secondloop_rust::embedding::DEFAULT_MODEL_NAME,
        secondloop_rust::embedding::DEFAULT_EMBED_DIM,
    );
    let manifests = db::list_active_embedding_artifacts_for_source_revision(
        &conn_a,
        "message",
        &message.id,
        revision_a,
        &profile_id,
    )
    .expect("manifests a");
    assert_eq!(manifests.len(), 1);
    let manifest = manifests[0].clone();
    assert!(db::has_embedding_artifact_blob(
        &app_dir_a,
        &manifest.blob_ref
    ));

    let sync_key = derive_root_key(
        "sync-passphrase",
        b"secondloop-sync1",
        &KdfParams::for_test(),
    )
    .expect("derive sync key");

    let pushed = sync::push(&conn_a, &key_a, &sync_key, &remote, remote_root).expect("push");
    assert!(pushed > 0);

    let temp_b = tempfile::tempdir().expect("tempdir B");
    let app_dir_b = temp_b.path().join("secondloop_b");
    let key_b =
        auth::init_master_password(&app_dir_b, "pw-b", KdfParams::for_test()).expect("init B");
    let conn_b = db::open(&app_dir_b).expect("open B db");

    let applied = sync::pull(&conn_b, &key_b, &sync_key, &remote, remote_root).expect("pull");
    assert!(applied > 0);

    let manifests_b = db::list_active_embedding_artifacts_for_source_revision(
        &conn_b,
        "message",
        &message.id,
        revision_a,
        &profile_id,
    )
    .expect("manifests b");
    assert_eq!(manifests_b.len(), 1);
    let manifest_b = manifests_b[0].clone();
    assert!(db::has_embedding_artifact_blob(
        &app_dir_b,
        &manifest_b.blob_ref
    ));

    conn_b
        .execute(r#"DELETE FROM message_embeddings"#, [])
        .expect("clear vec table");
    conn_b
        .execute(
            r#"UPDATE messages SET needs_embedding = 1 WHERE id = ?1"#,
            rusqlite::params![message.id.as_str()],
        )
        .expect("mark pending");

    let processed_b =
        db::process_pending_message_embeddings_default(&conn_b, &key_b, 10).expect("process B");
    assert_eq!(processed_b, 1);

    let needs_embedding: i64 = conn_b
        .query_row(
            r#"SELECT COALESCE(needs_embedding, 1) FROM messages WHERE id = ?1"#,
            rusqlite::params![message.id.as_str()],
            |row| row.get(0),
        )
        .expect("needs embedding");
    assert_eq!(needs_embedding, 0);
}
